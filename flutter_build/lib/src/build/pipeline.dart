//

import '../io/fs_utils.dart';
import '../logger.dart';
import '../process_runner.dart';
import 'build_context.dart';
import 'native_dll.dart' as dll;
import 'stages/aot_compile_stage.dart';
import 'stages/assemble_bundle_stage.dart';
import 'stages/build_stage.dart';
import 'stages/cmake_build_stage.dart';
import 'stages/compile_kernel_stage.dart';
import 'stages/sidecar_msvc_stage.dart';
import 'stages/source_staging_stage.dart';
import 'stages/translate_flags_stage.dart';

export 'stages/source_staging_stage.dart' show materializePluginSymlinks;

///
Future<void> copyTreePreservingLinks(String src, String dst) =>
    copyTree(src, dst);

class BuildPipeline {
  BuildPipeline({
    Logger? logger,
    ProcessRunner? runner,
  })  : _log = logger ?? Logger.instance,
        _runner = runner ?? ProcessRunner(logger: logger ?? Logger.instance);

  final Logger _log;
  final ProcessRunner _runner;

  List<BuildStage> _stages() => <BuildStage>[
        SourceStagingStage(logger: _log, runner: _runner),
        TranslateFlagsStage(logger: _log, runner: _runner),
        SidecarMsvcStage(logger: _log, runner: _runner),
        CompileKernelStage(logger: _log, runner: _runner),
        AotCompileStage(logger: _log, runner: _runner),
        CMakeBuildStage(logger: _log, runner: _runner),
        AssembleBundleStage(logger: _log, runner: _runner),
      ];

  Future<void> run(BuildContext ctx) async {
    final stages = _stages().where((s) => s.shouldRun(ctx)).toList();
    final total = stages.length;
    for (var i = 0; i < total; i++) {
      final stage = stages[i];
      await _log.group(
        'Stage ${i + 1}/$total · ${stage.name}',
        () => stage.run(ctx),
      );
    }
    _log.success('Windows build complete: ${ctx.finalExe}');
  }

  static List<String> referencedDllPaths(String cmakeContent) =>
      dll.referencedDllPaths(cmakeContent);
}
