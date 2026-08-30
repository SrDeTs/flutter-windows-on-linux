//

import 'dart:io';

import 'package:path/path.dart' as p;

import '../build_context.dart';
import '../host_env.dart';
import '../incremental.dart';
import '../mingw_compat.dart';
import '../wine_wrapper.dart';
import 'build_stage.dart';

class CMakeBuildStage extends BuildStage {
  CMakeBuildStage({super.logger, super.runner});

  @override
  String get name => 'configure & build with CMake';

  @override
  Future<void> run(BuildContext ctx) async {
    final wine =
        WineWrapper(toolchain: ctx.toolchain, buildRoot: ctx.buildRoot);
    await wine.materialize();
    await Directory(ctx.cmakeBuildDir).create(recursive: true);

    final compatDir = await _materializeCompatHeaders(ctx);

    final configureArgs = <String>[
      '-S',
      ctx.windowsStageDir,
      '-B',
      ctx.cmakeBuildDir,
      '-G',
      'Ninja',
      '-DCMAKE_SYSTEM_NAME=Windows',
      '-DCMAKE_SYSTEM_PROCESSOR=AMD64',
      '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
      '-DCMAKE_BUILD_TYPE=${ctx.mode.name.toUpperCase()}',
      '-DCMAKE_C_COMPILER=${ctx.toolchain.clang}',
      '-DCMAKE_CXX_COMPILER=${ctx.toolchain.clangxx}',
      '-DCMAKE_RC_COMPILER=${ctx.toolchain.llvmRc}',
      '-DCMAKE_RC_FLAGS=-I ${ctx.toolchain.mingwSysrootInclude}',
      '-DCMAKE_MAKE_PROGRAM=${ctx.toolchain.ninjaExecutable}',
      //    `undefined symbol: WinMain`；
      '-DCMAKE_EXE_LINKER_FLAGS=-municode -static -ldwmapi -L $compatDir',
      '-DCMAKE_SHARED_LINKER_FLAGS=-static -ldwmapi -L $compatDir',
      '-DCMAKE_MODULE_LINKER_FLAGS=-static',
      //   -Wno-deprecated-declarations — wstring_convert/codecvt_utf8_utf16
      '-DCMAKE_C_FLAGS=-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 '
          '-DNTDDI_VERSION=0x0A000000',
      '-DCMAKE_CXX_FLAGS=-I $compatDir '
          '-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 '
          '-DNTDDI_VERSION=0x0A000000 '
          '-Wno-pragma-once-outside-header -Wno-deprecated-declarations '
          '-fms-extensions '
          '-Wno-error=unknown-pragmas '
          '-Wno-error=unused-const-variable '
          '-Wno-error=unused-local-typedef '
          '-Wno-error=microsoft-extra-qualification '
          // MSVC never warns on these, so plugin code written for MSVC
          // (e.g. flutter_webrtc application_loopback_capturer.cc) trips
          // -Wall -Werror under Clang. Downgrade to plain warnings.
          '-Wno-error=delete-non-abstract-non-virtual-dtor '
          '-Wno-error=unused-but-set-variable '
          '-Wno-error=unused-function',
    ];
    final crossEnv = sanitizedCrossBuildEnv(
      Platform.environment,
      overrides: wine.environment(),
    );
    final configureStamp = File(
      p.join(ctx.cmakeBuildDir, '.flutter_build_configure.stamp'),
    );
    final expectedConfigureStamp = hashInputs(<String>[
      ...configureArgs,
      'sidecarImports=${crossEnv['SIDECAR_IMPORT_LIBS'] ?? ''}',
      'cppwinrt=${crossEnv['CPPWINRT_INCLUDE_DIR'] ?? ''}',
    ]);
    final hasHealthyCache = await _ensureCleanCrossCache(ctx);
    if (!ctx.incremental ||
        !hasHealthyCache ||
        !configureStamp.existsSync() ||
        configureStamp.readAsStringSync() != expectedConfigureStamp) {
      await runner.run(
        ctx.toolchain.cmakeExecutable,
        configureArgs,
        tag: 'cmake',
        environment: crossEnv,
        includeParentEnvironment: false,
      );
      await configureStamp.writeAsString(expectedConfigureStamp);
    } else {
      log.info('  configuração CMake não mudou; reutilizando build.ninja.');
    }

    final jobs = _parallelJobs();
    await runner.run(
      ctx.toolchain.cmakeExecutable,
      <String>['--build', ctx.cmakeBuildDir, '--parallel', '$jobs'],
      tag: 'cmake',
      environment: crossEnv,
      includeParentEnvironment: false,
    );
  }

  Future<bool> _ensureCleanCrossCache(BuildContext ctx) async {
    final cache = File(p.join(ctx.cmakeBuildDir, 'CMakeCache.txt'));
    if (!cache.existsSync()) return false;
    final content = await cache.readAsString();
    final isWindowsCross = RegExp(
      r'^CMAKE_SYSTEM_NAME[^=\n]*=\s*Windows\s*$',
      multiLine: true,
    ).hasMatch(content);
    final generated =
        File(p.join(ctx.cmakeBuildDir, 'build.ninja')).existsSync();
    if (isWindowsCross && generated) return true;
    log.debug(
        'Removed an incomplete or incompatible CMake cache before reconfiguration.');
    await cache.delete();
    final cmakeFiles = Directory(p.join(ctx.cmakeBuildDir, 'CMakeFiles'));
    if (cmakeFiles.existsSync()) await cmakeFiles.delete(recursive: true);
    return false;
  }

  int _parallelJobs() {
    final configured = int.tryParse(
      Platform.environment['FLUTTER_BUILD_JOBS'] ?? '',
    );
    if (configured != null && configured > 0) return configured;
    // Native plugin builds are memory-heavy. Eight workers saturate common
    // SSDs/CPUs without making 16 GB development machines swap excessively.
    return Platform.numberOfProcessors.clamp(1, 8);
  }

  ///
  Future<String> _materializeCompatHeaders(BuildContext ctx) {
    return materializeMingwCompat(
      outDir: ctx.mingwCompatDir,
      mingwLibDir: p.join(
          ctx.toolchain.llvmMingwRoot, ctx.toolchain.targetTriple, 'lib'),
    );
  }
}
