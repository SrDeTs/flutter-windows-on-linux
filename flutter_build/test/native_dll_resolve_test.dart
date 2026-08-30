import 'dart:io';

import 'package:flutter_build/src/build/native_dll.dart';
import 'package:flutter_build/src/project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveReferencedDll', () {
    const cmakeDir = '/plug/windows';

    test('test_case_1391', () {
      expect(
        resolveReferencedDll(
            r'${CMAKE_CURRENT_SOURCE_DIR}/../native/x.dll', cmakeDir),
        '/plug/native/x.dll',
      );
    });

    test('test_case_1399', () {
      expect(
        resolveReferencedDll(r'${CMAKE_CURRENT_LIST_DIR}/lib/y.dll', cmakeDir),
        '/plug/windows/lib/y.dll',
      );
    });

    test('test_case_1406', () {
      expect(resolveReferencedDll('lib/w.dll', cmakeDir),
          '/plug/windows/lib/w.dll');
    });

    test('test_case_1411', () {
      expect(resolveReferencedDll(r'C:/opencv/opencv_world490.dll', cmakeDir),
          isNull);
    });

    test('test_case_1416', () {
      expect(
          resolveReferencedDll(r'${SOME_OTHER_VAR}/z.dll', cmakeDir), isNull);
    });
  });

  group('resolveReferencedDllFiles', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('native_dll_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('test_case_1428', () {
      final pluginRoot = Directory(p.join(tmp.path, 'plug'))..createSync();
      final windows = Directory(p.join(pluginRoot.path, 'windows'))
        ..createSync();
      final realDll = File(p.join(pluginRoot.path, 'native', 'good.dll'))
        ..createSync(recursive: true)
        ..writeAsStringSync('MZ');
      File(p.join(windows.path, 'CMakeLists.txt')).writeAsStringSync('''
set(GOOD "\${CMAKE_CURRENT_SOURCE_DIR}/../native/good.dll")
set(MISSING "\${CMAKE_CURRENT_SOURCE_DIR}/../native/missing.dll")
set(WINABS "C:/somewhere/other.dll")
''');

      final plugin = WindowsPluginRef(
        name: 'plug',
        rootPath: pluginRoot.path,
        pluginClass: 'PlugPlugin',
      );

      final files = NativeDllScanner().resolveReferencedDllFiles([plugin]);
      final paths = files.map((f) => p.normalize(f.path)).toSet();

      expect(paths, contains(p.normalize(realDll.path)));
      expect(paths.any((x) => x.contains('missing.dll')), isFalse);
      expect(paths.any((x) => x.contains('other.dll')), isFalse);
    });
  });
}
