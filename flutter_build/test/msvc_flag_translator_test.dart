//
//   - /W3 → -Wall
//   - /WX → -Werror
//   - /std:c++17 → -std=c++17
//   - /GR- → -fno-rtti
//

import 'dart:io';

import 'package:flutter_build/src/build/msvc_flag_translator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('msvc_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  Future<String> translate(String content) async {
    final file = File(p.join(tmpDir.path, 'CMakeLists.txt'));
    file.writeAsStringSync(content);
    await MsvcFlagTranslator().transformTree(tmpDir.path);
    return file.readAsStringSync();
  }

  group('group_case_1108', () {
    test('test_case_1109', () async {
      final out = await translate(r'target_compile_options(foo PRIVATE /W3)');
      expect(out, contains('-Wall'));
      expect(out, isNot(contains('/W3')));
    });

    test('test_case_1115', () async {
      final out = await translate(r'target_compile_options(foo PRIVATE /WX)');
      expect(out, contains('-Werror'));
    });

    test('test_case_1120', () async {
      final out = await translate(
        r'target_compile_options(foo PRIVATE /EHsc /W3)',
      );
      expect(out, isNot(contains('/EHsc')));
      expect(out, contains('-Wall'));
    });

    test('test_case_1128', () async {
      final out = await translate(
        r'target_compile_options(foo PRIVATE /std:c++17)',
      );
      expect(out, contains('-std=c++17'));
    });

    test('test_case_1135', () async {
      final out = await translate(
        r'target_compile_options(foo PRIVATE /GR-)',
      );
      expect(out, contains('-fno-rtti'));
    });
  });

  group('group_case_1143', () {
    test('test_case_1144', () async {
      final out = await translate(
        'target_link_libraries(app PRIVATE "advapi32.lib")',
      );
      expect(out, contains('"advapi32"'));
      expect(out, isNot(contains('.lib')));
    });
  });

  group('group_case_1153', () {
    test('test_case_1154', () async {
      const input = '''
function(APPLY_STANDARD_SETTINGS target)
  target_compile_options(\${target} PRIVATE /W3 /WX)
endfunction()

APPLY_STANDARD_SETTINGS(foo)
''';
      final out = await translate(input);
      expect(out, isNot(contains('PRIVATE /W3 /WX')));
      expect(out, contains('APPLY_STANDARD_SETTINGS'));
    });
  });

  group('group_case_1168', () {
    test('test_case_1169', () async {
      final file = File(p.join(tmpDir.path, 'README.md'));
      file.writeAsStringSync('/W3 /WX');
      await MsvcFlagTranslator().transformTree(tmpDir.path);
      expect(file.readAsStringSync(), '/W3 /WX');
    });
  });

  group('group_case_1177', () {
    test('test_case_1178', () async {
      final out = await translate('add_compile_options(/W4)');
      expect(out, contains('-Wall -Wextra'));
      expect(out, isNot(contains('/W4')));
    });

    test('test_case_1184', () async {
      final out = await translate(
        r'target_compile_options(x PRIVATE /std:c++20)',
      );
      expect(out, contains('-std=c++20'));
    });

    test('test_case_1191', () async {
      final out = await translate('add_compile_options(/permissive- /MP)');
      expect(out, isNot(contains('/permissive-')));
      expect(out, isNot(contains('/MP')));
    });

    test('test_case_1197', () async {
      final out = await translate('add_compile_options(/GS-)');
      expect(out, contains('-fno-stack-protector'));
    });
  });

  group('group_case_1203', () {
    test('test_case_1204', () async {
      const input = '''
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_options(\${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(\${TARGET} PRIVATE /EHsc)
  target_compile_definitions(\${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
endfunction()
''';
      final out = await translate(input);
      expect(out, contains('if(MSVC)'));
      expect(out, contains('else()'));
      expect(out, contains('endif()'));
      expect(out, contains('/W4 /WX'));
      expect(out, contains('-Wall -Werror'));
    });

    test('test_case_1220', () async {
      const input = '''
function(APPLY_STANDARD_SETTINGS MYTARGET)
  target_compile_options(\${MYTARGET} PRIVATE /W3)
endfunction()
''';
      final out = await translate(input);
      expect(out, contains('function(APPLY_STANDARD_SETTINGS MYTARGET)'));
      expect(out, contains(r'${MYTARGET}'));
    });
  });

  group('group_case_1232', () {
    test('test_case_1233', () async {
      final out = await translate(
        'target_compile_definitions(app PRIVATE "_HAS_EXCEPTIONS=0")',
      );
      expect(out, contains(r'$<$<CXX_COMPILER_ID:MSVC>:_HAS_EXCEPTIONS=0>'));
      expect(out, isNot(contains('"_HAS_EXCEPTIONS=0"')));
    });
  });

  group('group_case_1242', () {
    test('test_case_1243', () {
      final warnings = <String>[];
      const MsvcFlagTranslator().transformContent(
        r'target_compile_options(x PRIVATE /W3 /Qunknown)',
        warnings: warnings,
      );
      expect(warnings, isNotEmpty);
      expect(warnings.join(), contains('/Qunknown'));
    });

    test('test_case_1253', () {
      final warnings = <String>[];
      const MsvcFlagTranslator().transformContent(
        'add_compile_options(-I /usr/include)',
        warnings: warnings,
      );
      expect(warnings, isEmpty);
    });
  });
}
