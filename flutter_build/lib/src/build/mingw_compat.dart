//
//

import 'dart:io';

import 'package:path/path.dart' as p;

///
const Map<String, String> kMingwCompatHeaders = {
  'shobjidl_core.h': '// flutter_build MinGW compatibility shim\n'
      '// shobjidl_core.h is a Windows 10 SDK header absent from MinGW-w64;\n'
      '// its interfaces are available via shobjidl.h.\n'
      '#ifndef _FLUTTER_BUILD_SHOBJIDL_CORE_SHIM\n'
      '#define _FLUTTER_BUILD_SHOBJIDL_CORE_SHIM\n'
      '#include <shobjidl.h>\n'
      '#endif\n',
  'Windows.h': '// flutter_build MinGW compatibility shim\n'
      '// On case-sensitive filesystems <Windows.h> is not found because\n'
      '// MinGW ships the header as <windows.h> (lowercase).\n'
      '#ifndef _FLUTTER_BUILD_WINDOWS_H_SHIM\n'
      '#define _FLUTTER_BUILD_WINDOWS_H_SHIM\n'
      '#include <windows.h>\n'
      '#endif\n',
  // record_windows follows the Windows SDK casing. LLVM-MinGW ships the same
  // Media Foundation Source Reader declarations in lowercase only.
  'Mfreadwrite.h': '// flutter_build MinGW compatibility shim\n'
      '#ifndef _FLUTTER_BUILD_MFREADWRITE_H_SHIM\n'
      '#define _FLUTTER_BUILD_MFREADWRITE_H_SHIM\n'
      '#include <mfreadwrite.h>\n'
      '#endif\n',
  'Mferror.h': '// flutter_build MinGW compatibility shim\n'
      '#ifndef _FLUTTER_BUILD_MFERROR_H_SHIM\n'
      '#define _FLUTTER_BUILD_MFERROR_H_SHIM\n'
      '#include <mferror.h>\n'
      '#endif\n',
  // share_plus includes <ShObjIdl.h>; MinGW ships shobjidl.h (lowercase,
  // without the CamelCase alias).
  'ShObjIdl.h': '// flutter_build MinGW compatibility shim\n'
      '#ifndef _FLUTTER_BUILD_SHOBJIDL_H_SHIM\n'
      '#define _FLUTTER_BUILD_SHOBJIDL_H_SHIM\n'
      '#include <shobjidl.h>\n'
      '#endif\n',
  // flutter_secure_storage_windows includes <ShlObj_core.h>; MinGW only has
  // the monolithic shlobj.h.
  'ShlObj_core.h': '// flutter_build MinGW compatibility shim\n'
      '#ifndef _FLUTTER_BUILD_SHLOBJ_CORE_H_SHIM\n'
      '#define _FLUTTER_BUILD_SHLOBJ_CORE_H_SHIM\n'
      '#include <shlobj.h>\n'
      '#endif\n',
  // flutter_secure_storage_windows includes <VersionHelpers.h>; MinGW ships
  // versionhelpers.h (lowercase).
  'VersionHelpers.h': '// flutter_build MinGW compatibility shim\n'
      '#ifndef _FLUTTER_BUILD_VERSIONHELPERS_H_SHIM\n'
      '#define _FLUTTER_BUILD_VERSIONHELPERS_H_SHIM\n'
      '#include <versionhelpers.h>\n'
      '#endif\n',
  // ATL is MSVC-only and absent from both MinGW-w64 and the Windows SDK.
  // flutter_secure_storage_windows merely #includes <atlstr.h> without using
  // any ATL type, so an effectively empty shim is enough.
  'atlstr.h': '// flutter_build MinGW compatibility shim: ATL is MSVC-only.\n'
      '#ifndef _FLUTTER_BUILD_ATLSTR_H_SHIM\n'
      '#define _FLUTTER_BUILD_ATLSTR_H_SHIM\n'
      '#include <string>\n'
      '#endif\n',
};

/// Import libraries referenced with Windows SDK casing. The Windows linker is
/// case-insensitive, while LLVM-MinGW runs on a case-sensitive Linux host.
const Map<String, String> kMingwLibraryAliases = {
  'Gdi32': 'gdi32',
  'Shlwapi': 'shlwapi',
};

///
///
Future<String> materializeMingwCompat({
  required String outDir,
  required String mingwLibDir,
}) async {
  final dir = Directory(outDir);
  await dir.create(recursive: true);

  for (final entry in kMingwCompatHeaders.entries) {
    final file = File(p.join(dir.path, entry.key));
    if (!file.existsSync() || file.readAsStringSync() != entry.value) {
      await file.writeAsString(entry.value);
    }
  }

  // Library case aliases: Windows resolves these case-insensitively, Linux
  // does not. Keep the real toolchain untouched and expose aliases only in
  // the compatibility search directory.
  for (final entry in kMingwLibraryAliases.entries) {
    final target = p.join(mingwLibDir, 'lib${entry.value}.a');
    if (File(target).existsSync()) {
      final link = Link(p.join(dir.path, 'lib${entry.key}.a'));
      if (!link.existsSync()) {
        await link.create(target);
      }
    }
  }

  return dir.path;
}
