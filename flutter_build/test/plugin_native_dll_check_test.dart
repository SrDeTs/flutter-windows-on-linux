//

import 'package:flutter_build/src/build/pipeline.dart';
import 'package:test/test.dart';

void main() {
  group('referencedDllPaths', () {
    test('test_case_1270', () {
      const content = r'''
set(PLUGIN_NAME "libcimbar_plugin")
add_library(${PLUGIN_NAME} SHARED "libcimbar_plugin.cpp")
# Pre-built native DLLs compiled separately via native/build_windows.bat
set(LIBCIMBAR_NATIVE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../native/build_windows/Release/libcimbar.dll")
set(OPENCV_DLL "C:/project/paddle_ocr/windows/third_party/opencv/lib/opencv_world490.dll")
set(BUNDLED_LIBS "$<TARGET_FILE:${PLUGIN_NAME}>")
''';
      final refs = BuildPipeline.referencedDllPaths(content);
      final names = refs.map((r) => r.split('/').last).toSet();

      expect(
          names, containsAll(<String>['libcimbar.dll', 'opencv_world490.dll']));
      expect(refs.any((r) => r.contains(r'$<')), isFalse);
    });

    test('test_case_1287', () {
      const content = '# Documentation mentions foo.dll\nset(X "bar.dll")';
      final names = BuildPipeline.referencedDllPaths(content)
          .map((r) => r.split('/').last);

      expect(names, contains('bar.dll'));
      expect(names, isNot(contains('foo.dll')));
    });

    test('test_case_1296', () {
      const content = 'add_library(foo SHARED "foo.cpp")\n'
          'target_link_libraries(foo PRIVATE flutter)';
      expect(BuildPipeline.referencedDllPaths(content), isEmpty);
    });
  });
}
