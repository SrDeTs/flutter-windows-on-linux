//

import 'dart:io';

import '../../engine_artifacts.dart';
import '../build_context.dart';
import '../incremental.dart';
import '../wine_wrapper.dart';
import 'build_stage.dart';

class AotCompileStage extends BuildStage {
  AotCompileStage({super.logger, super.runner});

  @override
  String get name => 'AOT compile';

  @override
  bool shouldRun(BuildContext ctx) => ctx.mode.isAot;

  @override
  Future<void> run(BuildContext ctx) async {
    final stampPath = '${ctx.appAotElf}.stamp';
    final stamp = hashInputs(<String>[
      'obfuscate=${ctx.enableObfuscation}',
      'splitDebug=${ctx.splitDebugInfoDir ?? ''}',
      ...ctx.dartDefines,
      'genSnapshot=${ctx.artifacts.genSnapshotExe(ctx.mode)}',
    ]);
    if (ctx.incremental &&
        isUpToDate(
          outputPath: ctx.appAotElf,
          inputPaths: <String>[ctx.kernelDill],
          stampPath: stampPath,
          expectedStamp: stamp,
        )) {
      log.info('  AOT output is current; skipping gen_snapshot.');
      return;
    }

    final wine =
        WineWrapper(toolchain: ctx.toolchain, buildRoot: ctx.buildRoot);
    await wine.materialize();

    final args = <String>[
      ctx.artifacts.genSnapshotExe(ctx.mode),
      '--snapshot-kind=app-aot-elf',
      '--elf=${ctx.appAotElf}',
      if (ctx.enableObfuscation) '--obfuscate',
      if (ctx.splitDebugInfoDir != null)
        '--split-debug-info=${ctx.splitDebugInfoDir}',
      for (final define in ctx.dartDefines) '--define=$define',
      ctx.kernelDill,
    ];
    await runner.run(
      wine.scriptPath,
      <String>[ctx.artifacts.genSnapshotExe(ctx.mode), ...args.skip(1)],
      tag: 'gen_snapshot',
      environment: wine.environment(),
    );
    await File(stampPath).writeAsString(stamp);
  }
}
