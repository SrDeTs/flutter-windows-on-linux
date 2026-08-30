//

import 'package:flutter_build/src/build/flutter_ephemeral.dart';
import 'package:test/test.dart';

void main() {
  group('parseFlutterVersion', () {
    test('test_case_1574', () {
      final v = parseFlutterVersion('1.0.0+1');
      expect(v.full, '1.0.0+1');
      expect([v.major, v.minor, v.patch, v.build], [1, 0, 0, 1]);
    });

    test('test_case_1580', () {
      final v = parseFlutterVersion('2.3.4');
      expect([v.major, v.minor, v.patch, v.build], [2, 3, 4, 0]);
    });

    test('test_case_1585', () {
      final v = parseFlutterVersion(null);
      expect(v.full, '1.0.0');
      expect([v.major, v.minor, v.patch, v.build], [1, 0, 0, 0]);
      expect(parseFlutterVersion('  ').major, 1);
    });

    test('test_case_1592', () {
      final v = parseFlutterVersion('1.2');
      expect([v.major, v.minor, v.patch], [1, 2, 0]);
    });

    test('test_case_1597', () {
      expect(parseFlutterVersion('1.0.0+foo').build, 0);
    });
  });

  group('renderGeneratedConfigCmake', () {
    test('test_case_1603', () {
      final out = renderGeneratedConfigCmake(
        flutterRoot: '/opt/flutter',
        projectDir: '/home/user/app',
        version: parseFlutterVersion('1.2.3+4'),
      );
      expect(out, contains('file(TO_CMAKE_PATH "/opt/flutter" FLUTTER_ROOT)'));
      expect(out, contains('file(TO_CMAKE_PATH "/home/user/app" PROJECT_DIR)'));
      expect(out, contains('set(FLUTTER_VERSION "1.2.3+4" PARENT_SCOPE)'));
      expect(out, contains('set(FLUTTER_VERSION_MAJOR 1 PARENT_SCOPE)'));
      expect(out, contains('set(FLUTTER_VERSION_BUILD 4 PARENT_SCOPE)'));
    });
  });

  group('neutralizeFlutterAssemble', () {
    const sample = '''
add_dependencies(flutter flutter_assemble)

# === Flutter tool backend ===
set(PHONY_OUTPUT "\${CMAKE_CURRENT_BINARY_DIR}/_phony_")
add_custom_command(
  OUTPUT \${FLUTTER_LIBRARY}
  COMMAND \${CMAKE_COMMAND} -E env
    "\${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      windows-x64 \$<CONFIG>
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "\${FLUTTER_LIBRARY}"
)
''';

    test('test_case_1635', () {
      final out = neutralizeFlutterAssemble(sample);
      expect(out, isNot(contains('tool_backend')));
      expect(out, isNot(contains('add_custom_command')));
      expect(out, contains('add_custom_target(flutter_assemble)'));
      expect(out, contains('add_dependencies(flutter flutter_assemble)'));
    });

    test('test_case_1643', () {
      const noMarker = 'add_custom_target(flutter_assemble)\n';
      expect(neutralizeFlutterAssemble(noMarker), noMarker);
    });
  });
}
