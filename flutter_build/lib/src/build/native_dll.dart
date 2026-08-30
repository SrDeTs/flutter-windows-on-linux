//
//

import 'dart:io';

import 'package:path/path.dart' as p;

import '../logger.dart';
import '../project.dart';

const int kDefaultDllSearchDepth = 5;

const Set<String> kDllSearchSkipDirs = {
  'build',
  '.dart_tool',
  '.pub-cache',
  '.git',
  '.flutter_build',
  'snap',
  'proc',
  'sys',
  'dev',
};

///
List<String> referencedDllPaths(String cmakeContent) {
  final out = <String>[];
  for (final rawLine in cmakeContent.split('\n')) {
    final hash = rawLine.indexOf('#');
    final line = hash >= 0 ? rawLine.substring(0, hash) : rawLine;
    for (final m in RegExp(r'''[^\s"'()]+\.dll''', caseSensitive: false)
        .allMatches(line)) {
      final ref = m.group(0)!;
      if (ref.contains(r'$<')) continue;
      out.add(ref);
    }
  }
  return out;
}

bool looksLikeWindowsAbsPath(String ref) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(ref);

///
String? resolveReferencedDll(String rawRef, String cmakeDir) {
  var ref = rawRef.replaceAll(r'\', '/');
  ref = ref
      .replaceAll(r'${CMAKE_CURRENT_SOURCE_DIR}', cmakeDir)
      .replaceAll(r'${CMAKE_CURRENT_LIST_DIR}', cmakeDir);
  if (ref.contains(r'${')) return null;
  if (looksLikeWindowsAbsPath(ref)) return null;
  final abs = p.isAbsolute(ref) ? ref : p.join(cmakeDir, ref);
  return p.normalize(abs);
}

class NativeDllScanner {
  NativeDllScanner({Logger? logger}) : _log = logger ?? Logger.instance;

  final Logger _log;

  ///
  Future<void> copyPrebuiltDlls({
    required String outDir,
    required String searchRoot,
    int maxDepth = kDefaultDllSearchDepth,
  }) async {
    final existing = _presentDllBasenames(outDir);

    final found = <File>[];
    _findDlls(Directory(searchRoot), found, 0, maxDepth);

    for (final dll in found) {
      final name = p.basename(dll.path);
      if (existing.contains(name.toLowerCase())) continue;
      await dll.copy(p.join(outDir, name));
      _log.info('  Prebuilt DLL: $name');
      existing.add(name.toLowerCase());
    }
  }

  ///
  Future<void> copyResolvedReferencedDlls({
    required String outDir,
    required Iterable<WindowsPluginRef> plugins,
  }) async {
    final existing = _presentDllBasenames(outDir);
    for (final file in resolveReferencedDllFiles(plugins)) {
      final name = p.basename(file.path);
      if (existing.contains(name.toLowerCase())) continue;
      await file.copy(p.join(outDir, name));
      _log.info('  Prebuilt DLL resolved from plugin declaration: $name');
      existing.add(name.toLowerCase());
    }
  }

  List<File> resolveReferencedDllFiles(Iterable<WindowsPluginRef> plugins) {
    final out = <File>[];
    for (final plugin in plugins.where((pl) => pl.hasNativeCode)) {
      final cmakeDir = plugin.windowsCMakeDir;
      final cmake = File(p.join(cmakeDir, 'CMakeLists.txt'));
      if (!cmake.existsSync()) continue;
      for (final rawRef in referencedDllPaths(cmake.readAsStringSync())) {
        final resolved = resolveReferencedDll(rawRef, cmakeDir);
        if (resolved == null) continue;
        final f = File(resolved);
        if (f.existsSync()) out.add(f);
      }
    }
    return out;
  }

  void verifyPluginNativeDlls({
    required String outDir,
    required Iterable<WindowsPluginRef> plugins,
  }) {
    final present = _presentDllBasenames(outDir);

    final missing = <String, String>{};
    for (final plugin in plugins.where((pl) => pl.hasNativeCode)) {
      final cmake = File(p.join(plugin.windowsCMakeDir, 'CMakeLists.txt'));
      if (!cmake.existsSync()) continue;
      for (final ref in referencedDllPaths(cmake.readAsStringSync())) {
        final base = p.basename(ref.replaceAll(r'\', '/'));
        if (present.contains(base.toLowerCase())) continue;
        missing.putIfAbsent(base, () => ref);
      }
    }
    if (missing.isEmpty) return;

    _log.warn(
        'Missing native DLLs: plugins declare the following files, but they');
    _log.warn(
        'were not included in this cross-build. The Windows application may');
    _log.warn('fail to load them at runtime:');
    missing.forEach((base, ref) {
      final reason = looksLikeWindowsAbsPath(ref)
          ? 'hard-coded Windows path unavailable in the cross environment'
          : 'prebuilt Windows artifact was not generated on Linux';
      _log.warn('  ✗ $base（$reason：$ref）');
    });
    _log.hint(
        'Cross-compile these DLLs on Linux or copy them from Windows into '
        'the bundle directory. Ignore this warning only if they are optional.');
  }

  Set<String> _presentDllBasenames(String outDir) {
    final present = <String>{};
    final dir = Directory(outDir);
    if (!dir.existsSync()) return present;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.dll')) {
        present.add(p.basename(entity.path).toLowerCase());
      }
    }
    return present;
  }

  void _findDlls(Directory dir, List<File> results, int depth, int maxDepth) {
    if (depth > maxDepth) return;
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        if (entity.path.endsWith('.dll')) results.add(entity);
      } else if (entity is Directory) {
        if (kDllSearchSkipDirs.contains(p.basename(entity.path))) continue;
        _findDlls(entity, results, depth + 1, maxDepth);
      }
    }
  }
}
