//

import 'dart:io';

import '../../engine_artifacts.dart';
import '../build_context.dart';
import '../incremental.dart';
import 'build_stage.dart';

class CompileKernelStage extends BuildStage {
  CompileKernelStage({super.logger, super.runner});

  @override
  String get name => 'compile Dart kernel';

  @override
  Future<void> run(BuildContext ctx) async {
    if (ctx.treeShakeIcons) {
      log.debug(
          'Note: icon tree-shaking is not implemented in this packaging stage.');
    }
    final registrant = File(ctx.project.dartPluginRegistrant).absolute;
    final hasRegistrant = registrant.existsSync();
    if (hasRegistrant) {
      log.debug('Using Dart plugin registrant: ${registrant.path}');
    } else {
      log.debug(
          'dart_plugin_registrant.dart was not found. Run flutter pub get '
          'before building projects that use Dart-only plugins.');
    }

    final depfile = '${ctx.kernelDill}.d';
    final stampPath = '${ctx.kernelDill}.stamp';
    final stamp = hashInputs(<String>[
      'mode=${ctx.mode.cliName}',
      'product=${ctx.mode.isProduct}',
      'aot=${ctx.mode.isAot}',
      ...ctx.mode.kernelModeDefines,
      ...ctx.dartDefines,
      'entry=${ctx.project.entryPoint}',
      'sdkRoot=${ctx.env.sdkRoot}',
      'registrant=$hasRegistrant',
    ]);
    if (ctx.incremental &&
        _kernelUpToDate(
            ctx, depfile, stampPath, stamp, hasRegistrant, registrant)) {
      log.info('  Kernel unchanged; skipping compilation.');
      return;
    }

    final args = <String>[
      ctx.env.frontendServerSnapshot,
      '--sdk-root',
      ctx.env.patchedSdkPath(product: ctx.mode.isProduct),
      '--target=flutter',
      '--no-print-incremental-dependencies',
      for (final define in ctx.mode.kernelModeDefines) '--define=$define',
      if (!ctx.mode.isAot) '--enable-asserts',
      if (ctx.mode.isAot) ...['--aot', '--tfa'],
      for (final define in ctx.dartDefines) '--define=$define',
      '--packages',
      ctx.project.packageConfig,
      if (hasRegistrant) ...[
        '--source',
        registrant.path,
        '--source',
        'package:flutter/src/dart_plugin_registrant.dart',
        '-Dflutter.dart_plugin_registrant=${registrant.uri}',
      ],
      '--depfile',
      depfile,
      '--output-dill',
      ctx.kernelDill,
      ctx.project.entryPoint,
    ];
    await runner.run(ctx.env.frontendServerRuntime, args,
        tag: 'frontend_server');
    await File(stampPath).writeAsString(stamp);
  }

  bool _kernelUpToDate(BuildContext ctx, String depfile, String stampPath,
      String stamp, bool hasRegistrant, File registrant) {
    final depFile = File(depfile);
    if (!depFile.existsSync()) return false;
    return isUpToDate(
      outputPath: ctx.kernelDill,
      inputPaths: <String>[
        ...parseDepfileInputs(depFile.readAsStringSync()),
        ctx.project.packageConfig,
        if (hasRegistrant) registrant.path,
      ],
      stampPath: stampPath,
      expectedStamp: stamp,
    );
  }
}
