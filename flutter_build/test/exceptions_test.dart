//

import 'package:flutter_build/flutter_build.dart';
import 'package:test/test.dart';

void main() {
  group('group_case_1309', () {
    test('test_case_1310', () {
      final e = ToolException('Build failed', hint: 'Check the CMake version');
      expect(e.message, 'Build failed');
      expect(e.hint, 'Check the CMake version');
      expect(e.exitCode, 1);
    });

    test('test_case_1317', () {
      expect(ToolException('x').exitCode, 1);
    });

    test('test_case_1321', () {
      final e = ToolException('x', exitCode: 42);
      expect(e.exitCode, 42);
    });

    test('test_case_1326', () {
      final e = ToolException('Network timeout');
      expect(e.toString(), contains('Network timeout'));
    });
  });

  group('group_case_1332', () {
    test('test_case_1333', () {
      final e = MissingToolException('ninja', hint: 'apt install ninja-build');
      expect(e, isA<ToolException>());
      expect(e.message, contains('ninja'));
    });
  });

  group('group_case_1340', () {
    test('test_case_1341', () {
      final e = FlutterSdkException('Flutter was not found');
      expect(e, isA<ToolException>());
      expect(e.exitCode, 3);
    });
  });

  group('group_case_1348', () {
    test('test_case_1349', () {
      final e = ProjectException('pubspec.yaml is missing');
      expect(e, isA<ToolException>());
    });
  });

  group('group_case_1355', () {
    test('test_case_1356', () {
      final e = SubprocessException(
        executable: 'cmake',
        arguments: ['--build', '.'],
        subprocessExitCode: 2,
        stderrText: 'Ninja was not found',
      );
      expect(e, isA<ToolException>());
      expect(e.subprocessExitCode, 2);
      expect(e.executable, 'cmake');
      expect(e.stderrText, 'Ninja was not found');
      expect(e.arguments, ['--build', '.']);
    });
  });

  group('group_case_1371', () {
    test('test_case_1372', () {
      final e = ArtifactException('flutter_windows.dll is missing');
      expect(e, isA<ToolException>());
      expect(e.message, contains('flutter_windows.dll'));
    });
  });
}
