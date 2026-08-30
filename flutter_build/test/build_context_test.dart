//
//   buildRoot/<mode>/
//     ├── windows_src/          (staged CMake source)
//     ├── cmake_build/          (CMake outputs)
//     ├── intermediates/        (kernel dill + aot elf)
//     └── <app_name>/           (final packaged output)
//           ├── <app>.exe
//           └── data/
//                 └── flutter_assets/

import 'package:flutter_build/src/build/build_context.dart';
import 'package:flutter_build/src/engine_artifacts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/stubs.dart';

void main() {
  late BuildContext ctx;

  setUp(() {
    ctx = stubContext(
      mode: WindowsFlavor.release,
      buildRoot: '/home/user/myapp/build/win_cross',
      dartDefines: ['APP_NAME=hello'],
    );
  });

  group('group_case_29', () {
    test('modeDir = buildRoot/release', () {
      expect(ctx.modeDir, '/home/user/myapp/build/win_cross/release');
    });

    test('test_case_34', () {
      expect(ctx.windowsStageDir, endsWith('/release/windows_src'));
    });

    test('test_case_38', () {
      expect(ctx.cmakeBuildDir, endsWith('/release/cmake_build'));
    });

    test('test_case_42', () {
      expect(p.basename(ctx.kernelDill), 'app.dill');
      expect(ctx.kernelDill, contains('/intermediates/'));
    });

    test('test_case_47', () {
      expect(p.basename(ctx.appAotElf), 'app.so');
    });

    test('test_case_51', () {
      expect(ctx.finalExe, endsWith('/myapp/myapp.exe'));
    });

    test('test_case_55', () {
      expect(ctx.outputDir, endsWith('/myapp'));
      expect(ctx.outputDir, p.dirname(ctx.finalExe));
    });

    test('test_case_60', () {
      expect(ctx.dataDir, endsWith('/myapp/data'));
    });

    test('test_case_64', () {
      expect(ctx.flutterAssetsDir, endsWith('/data/flutter_assets'));
    });

    test('test_case_68', () {
      expect(ctx.mingwCompatDir, endsWith('/intermediates/mingw_compat'));
    });
  });

  group('group_case_73', () {
    test('test_case_74', () {
      final debugCtx =
          stubContext(mode: WindowsFlavor.debug, buildRoot: '/build');
      expect(debugCtx.modeDir, '/build/debug');
    });

    test('test_case_80', () {
      final profileCtx =
          stubContext(mode: WindowsFlavor.profile, buildRoot: '/build');
      expect(profileCtx.modeDir, '/build/profile');
    });
  });

  group('group_case_87', () {
    test('test_case_88', () {
      expect(ctx.incremental, isTrue);
    });

    test('test_case_92', () {
      expect(ctx.dllSearchRoot, isNull);
    });
  });
}
