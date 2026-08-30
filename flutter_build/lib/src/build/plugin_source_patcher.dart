//
//

import 'dart:io';

import 'package:path/path.dart' as p;

import '../io/fs_utils.dart';
import '../logger.dart';

///
String patchHotkeyManagerPluginCpp(String content) {
  return content.replaceAll(
    'flutter::EncodableMap({{"identifier", identifier}})',
    'flutter::EncodableMap({{flutter::EncodableValue("identifier"), '
        'flutter::EncodableValue(identifier)}})',
  );
}

/// Rewrites the small set of `record_windows` constructs whose spelling or
/// implicit conversions differ between the Windows SDK/MSVC STL and
/// LLVM-MinGW/libc++.
String patchRecordWindowsPluginCpp(String content) {
  return content.replaceAll(
    'printf("Record: Error when reading sample (0x%X)\\n%s\\n", '
        'hrStatus, errorText.c_str());',
    'printf("Record: Error when reading sample (0x%lX)\\n%s\\n", '
        'static_cast<unsigned long>(hrStatus), errorText.c_str());',
  );
}

String patchRecordWindowsRecorderCpp(String content) {
  const original = '''
		: m_nRefCount(1),
		m_critsec(),
		m_pConfig(nullptr),
		m_pSource(NULL),
		m_pReader(NULL),
		m_pWriter(NULL),
		m_pPresentationDescriptor(NULL),
		m_stateEventHandler(stateEventHandler),
		m_recordEventHandler(recordEventHandler),
		m_recordEventHandlerOrigin(recordEventHandler),
		m_recordingPath(std::wstring()),
		m_pMediaType(NULL)
''';
  const replacement = '''
		: m_nRefCount(1),
		m_critsec(),
		m_pSource(NULL),
		m_pPresentationDescriptor(NULL),
		m_pReader(NULL),
		m_pWriter(NULL),
		m_pMediaType(NULL),
		m_recordingPath(std::wstring()),
		m_stateEventHandler(stateEventHandler),
		m_recordEventHandler(recordEventHandler),
		m_recordEventHandlerOrigin(recordEventHandler),
		m_pConfig(nullptr)
''';
  final lineEnding = content.contains('\r\n') ? '\r\n' : '\n';
  return content.replaceFirst(
    original.replaceAll('\n', lineEnding),
    replacement.replaceAll('\n', lineEnding),
  );
}

String patchRecordWindowsAudioDeviceCpp(String content) {
  var out = content.replaceAll(
    'pPart->GetTopologyObject(',
    'pPart->GetTopologyObjects(',
  );

  const mapStart = 'devices.push_back(flutter::EncodableMap({';
  final start = out.indexOf(mapStart);
  if (start < 0) return out;
  final end = out.indexOf('}));', start + mapStart.length);
  if (end < 0) return out;

  out = out.replaceRange(
    start,
    start + mapStart.length,
    'devices.push_back(flutter::EncodableValue(flutter::EncodableMap({',
  );
  final adjustedEnd = out.indexOf('}));', start);
  return out.replaceRange(adjustedEnd, adjustedEnd + 4, '})));');
}

/// Rewrites the staged `permission_handler_windows/windows/CMakeLists.txt`.
///
/// The stock file shells out to `nuget install Microsoft.Windows.CppWinRT`
/// and then runs `cppwinrt.exe -input sdk`, both of which require a real
/// Windows SDK + .NET runtime. When the environment variable
/// `CPPWINRT_INCLUDE_DIR` points at a directory that already contains the
/// generated `winrt/*.h` projections, we skip the whole download/generate
/// dance and include that directory instead. The original block is kept in
/// the `else()` branch so the tree still builds unmodified on a real
/// Windows + MSVC host.
String patchPermissionHandlerCmake(String content) {
  const startMarker = 'FetchContent_Declare(nuget';
  const endMarker =
      'include_directories(BEFORE SYSTEM \${CMAKE_BINARY_DIR}/include)';
  final start = content.indexOf(startMarker);
  final end = content.indexOf(endMarker);
  if (start < 0 || end < 0 || end < start) return content;

  final replacement = '''
if(DEFINED ENV{CPPWINRT_INCLUDE_DIR})
  # Pre-generated C++/WinRT projections supplied by the cross-build host.
  include_directories(BEFORE SYSTEM \$ENV{CPPWINRT_INCLUDE_DIR})
else()
  ${content.substring(start, end + endMarker.length)}
endif()''';

  return content.replaceRange(start, end + endMarker.length, replacement);
}

/// Rewrites the staged `audioplayers_windows/windows/CMakeLists.txt` so the
/// WIL (Windows Implementation Library) nuget package comes from our preseed
/// dir instead of nuget.exe, and the MSBuild-only `.targets` link line is
/// skipped (WIL is header-only; Media Foundation libs are linked explicitly
/// right below it). Falls back to the original machinery on real Windows.
String patchAudioplayersCmake(String content) {
  final home = Platform.environment['HOME'] ?? '.';
  final preseedRoot = Platform.environment['FLUTTER_BUILD_NUGET_PRESEED'] ??
      p.join(home, '.flutter_build', 'nuget');

  final installRe = RegExp(
      r'install\s+([A-Za-z0-9_.-]+)\s+-Version\s+\$\{(\w+)\}\s+(-ExcludeVersion\s+)?-OutputDirectory');
  final m = installRe.firstMatch(content);
  if (m == null) return content;
  final pkg = m.group(1)!;
  final verVar = m.group(2)!;
  final verMatch =
      RegExp('set\\($verVar\\s+"([0-9A-Za-z.]+)"\\)').firstMatch(content);
  if (verMatch == null) return content;
  final ver = verMatch.group(1)!;
  // Preseed extracts as <pkg>.<ver>; nuget -ExcludeVersion would use <pkg>.
  // Accept either so the layout stays consistent on both sides.
  String seeded = p.join(preseedRoot, '$pkg.$ver');
  if (!Directory(seeded).existsSync()) {
    final alt = p.join(preseedRoot, pkg);
    if (Directory(alt).existsSync()) seeded = alt;
  }

  const startMarker = 'FetchContent_Declare(nuget';
  const fatalNeedle =
      'Failed to install nuget package Microsoft.Windows.ImplementationLibrary.';
  final start = content.indexOf(startMarker);
  final fatalIdx = content.indexOf(fatalNeedle);
  if (start < 0 || fatalIdx < 0) return content;
  final endifIdx = content.indexOf('endif()', fatalIdx);
  if (endifIdx < 0) return content;
  final end = content.indexOf('\n', endifIdx);

  final guarded = '''
if(EXISTS "$seeded")
  # Pre-seeded WIL package (Linux cross build: no nuget.exe available).
  # WIL is header-only, so pointing the include path at the preseed is enough.
  include_directories(BEFORE SYSTEM "$seeded/include")
else()
  ${content.substring(start, end)}
endif()''';

  var out = content.replaceRange(start, end, guarded);

  // Skip the MSBuild-only .targets "link" when preseeded (it adds include
  // paths for MSBuild, not for CMake; WIL needs no linking).
  final targetsLine = RegExp(
      r'target_link_libraries\(\$\{PLUGIN_NAME\} PRIVATE \$\{CMAKE_BINARY_DIR\}/packages/[^\n]*\.targets\)');
  out = out.replaceAllMapped(targetsLine, (mm) {
    return 'if(NOT EXISTS "$seeded")\n  ${mm.group(0)}\nendif()';
  });
  return out;
}

const Map<String, Map<String, String Function(String)>> _pluginPatches = {
  'hotkey_manager_windows': {
    'hotkey_manager_windows_plugin.cpp': patchHotkeyManagerPluginCpp,
  },
  'permission_handler_windows': {
    'CMakeLists.txt': patchPermissionHandlerCmake,
  },
  'audioplayers_windows': {
    'CMakeLists.txt': patchAudioplayersCmake,
  },
  'record_windows': {
    'record/record_readercallback.cpp': patchRecordWindowsPluginCpp,
    'record/record.cpp': patchRecordWindowsRecorderCpp,
    'audio_device/record_audio_device.cpp': patchRecordWindowsAudioDeviceCpp,
  },
};

class PluginSourcePatcher {
  const PluginSourcePatcher();

  ///
  Future<void> apply(String ephemeralDir, {Logger? logger}) async {
    if (_pluginPatches.isEmpty) return;
    final log = logger ?? Logger.instance;
    final symlinkDir = Directory(p.join(ephemeralDir, '.plugin_symlinks'));
    if (!symlinkDir.existsSync()) return;

    final patched = <String>[];
    for (final entry in _pluginPatches.entries) {
      patched.addAll(
        await _patchPlugin(symlinkDir.path, entry.key, entry.value),
      );
    }

    if (patched.isNotEmpty) {
      log.info('Patched plugin sources for Clang/MinGW: ${patched.join(', ')}');
    }
  }

  Future<List<String>> _patchPlugin(
    String symlinkDirPath,
    String pluginName,
    Map<String, String Function(String)> patches,
  ) async {
    final pluginLinkPath = p.join(symlinkDirPath, pluginName);
    final link = Link(pluginLinkPath);
    if (!link.existsSync()) return const [];

    final realPath = link.resolveSymbolicLinksSync();
    await link.delete();
    await copyTree(realPath, pluginLinkPath);

    final patchedFiles = <String>[];
    for (final entry in patches.entries) {
      final file = File(p.join(pluginLinkPath, 'windows', entry.key));
      if (!file.existsSync()) continue;
      final original = await file.readAsString();
      final result = entry.value(original);
      if (result != original) {
        await file.writeAsString(result);
        patchedFiles.add('$pluginName/${entry.key}');
      }
    }
    return patchedFiles;
  }
}
