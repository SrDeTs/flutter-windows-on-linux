// `flutter_build windows [--debug|--profile|--release]`
//
// The command performs the full cross-build pipeline on the current
// directory (assumed to be a Flutter app project).

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/build_context.dart';
import '../build/pipeline.dart';
import '../cache_paths.dart';
import '../deploy.dart';
import '../engine_artifacts.dart';
import '../exceptions.dart';
import '../flutter_env.dart';
import '../logger.dart';
import '../process_runner.dart';
import '../project.dart';
import '../toolchain.dart';

class WindowsCommand extends Command<int> {
  WindowsCommand() {
    argParser
      ..addFlag('debug',
          negatable: false, help: 'Build the debug (JIT) flavor.')
      ..addFlag('profile',
          negatable: false,
          help: 'Build the profile (AOT + observatory) flavor.')
      ..addFlag('release',
          negatable: false, help: 'Build the release (AOT) flavor. Default.')
      ..addMultiOption('dart-define',
          abbr: 'D',
          help: 'Pass a Dart --define to the kernel compiler.',
          splitCommas: false)
      ..addFlag('obfuscate',
          negatable: false,
          help: 'Enable AOT obfuscation (release/profile). '
              'Requires --split-debug-info.')
      ..addOption('split-debug-info',
          help: 'Directory to save split debug symbols/obfuscation map.')
      ..addFlag('tree-shake-icons',
          defaultsTo: true,
          help: 'Tree-shake icon fonts based on IconData usage.')
      ..addOption('target',
          abbr: 't', help: 'Entry point (default: lib/main.dart).')
      ..addOption('output-dir',
          abbr: 'o', help: 'Override output root (default: build/win_cross).')
      ..addFlag('no-precache',
          negatable: false,
          help: 'Fail instead of downloading LLVM-MinGW / engine artifacts.')
      ..addOption('toolchain-path',
          help: 'Path to a pre-installed LLVM-MinGW directory.\n'
              'Same as setting env LLVM_MINGW_ROOT. Skips download.')
      ..addFlag('copy',
          help: 'Copy successful build output to the remote Windows machine '
              'configured in config.yaml. Overrides auto_copy when explicitly '
              'set; use --no-copy to disable it.')
      ..addOption('config',
          help: 'Path to config.yaml. By default it searches upward from the '
              'project and tool directories, then ~/.flutter_build/config.yaml.')
      ..addFlag('debug-console',
          defaultsTo: false,
          help: 'Disabled by default for a clean GUI executable. Enable with '
              '--debug-console to attach engine logs to PowerShell/cmd and '
              'diagnose silent startup failures.')
      ..addFlag('incremental',
          defaultsTo: true,
          help: 'Skip kernel and AOT recompilation when inputs are unchanged. '
              'Use --no-incremental to force a full rebuild.')
      ..addOption('dll-search-root',
          help: 'Root directory used to discover prebuilt DLLs. Narrowing it '
              'can significantly speed up assembly in large workspaces.');
  }

  @override
  String get name => 'windows';
  @override
  String get description =>
      'Cross-compile the Flutter Windows executable for the current project.';

  @override
  Future<int> run() async {
    final log = Logger.instance;
    final runner = ProcessRunner(logger: log);

    final flavor = _pickFlavor();
    log.debug('Requested flavor: ${flavor.cliName}');

    final project = await FlutterProject.load();
    final env = await FlutterEnv.locate(runner: runner);
    final paths = CachePaths.resolve(
      cacheDirOverride: globalResults?['cache-dir'] as String?,
    );
    await paths.ensure();

    final allowDownload = argResults?['no-precache'] != true;
    final toolchainPath = argResults?['toolchain-path'] as String?;
    final toolchain = await ToolchainProvisioner(
      paths: paths,
      runner: runner,
      toolchainPathOverride: toolchainPath,
    ).provision(allowDownload: allowDownload);

    final artifacts = await EngineArtifactsProvisioner(
      env: env,
      runner: runner,
    ).ensure();

    final buildRoot = (argResults?['output-dir'] as String?) ??
        p.join(project.root, 'build', 'win_cross');

    final defines = List<String>.from(
      (argResults?['dart-define'] as List<dynamic>?)?.cast<String>() ??
          const [],
    );
    final obfuscate = argResults?['obfuscate'] == true;
    final splitDebug = argResults?['split-debug-info'] as String?;
    if (obfuscate && splitDebug == null) {
      throw ToolException(
        '--obfuscate requires --split-debug-info=<dir> for the symbol map.',
      );
    }

    final context = BuildContext(
      env: env,
      project: project,
      artifacts: artifacts,
      toolchain: toolchain,
      mode: flavor,
      buildRoot: buildRoot,
      dartDefines: defines,
      enableObfuscation: obfuscate,
      splitDebugInfoDir: splitDebug,
      treeShakeIcons: argResults?['tree-shake-icons'] == true,
      verbose: log.verbose,
      debugConsole: argResults?['debug-console'] == true,
      incremental: (argResults?['incremental'] as bool?) ?? true,
      dllSearchRoot: argResults?['dll-search-root'] as String?,
    );

    await BuildPipeline().run(context);
    await _maybeDeploy(context, log, runner);
    return 0;
  }

  ///
  Future<void> _maybeDeploy(
    BuildContext ctx,
    Logger log,
    ProcessRunner runner,
  ) async {
    final configPath = argResults?['config'] as String?;
    final DeployConfig? config;
    if (configPath != null) {
      final f = File(configPath);
      if (!f.existsSync()) {
        throw ToolException('The specified config does not exist: $configPath');
      }
      config = DeployConfig.parse(f.readAsStringSync(),
          baseDir: p.dirname(p.absolute(configPath)));
    } else {
      config = DeployConfig.find(ctx.project.root);
    }

    if (config == null) {
      log.debug('config.yaml was not found; skipping remote copy.');
      return;
    }

    final bool shouldCopy;
    if (argResults?.wasParsed('copy') == true) {
      shouldCopy = argResults?['copy'] == true;
    } else {
      shouldCopy = config.autoCopy;
    }
    if (!shouldCopy) {
      log.debug(
          'auto_copy is disabled and --copy was not set; skipping remote copy.');
      return;
    }

    final bundleDir = p.dirname(ctx.finalExe);
    await SshDeployer(config: config, logger: log, runner: runner)
        .deployDir(bundleDir);
  }

  WindowsFlavor _pickFlavor() {
    final debug = argResults?['debug'] == true;
    final profile = argResults?['profile'] == true;
    final release = argResults?['release'] == true;
    final count = [debug, profile, release].where((b) => b).length;
    if (count > 1) {
      throw ToolException(
        '--debug, --profile and --release are mutually exclusive.',
      );
    }
    if (debug) return WindowsFlavor.debug;
    if (profile) return WindowsFlavor.profile;
    // Default is release, matching `flutter build windows`.
    return WindowsFlavor.release;
  }
}
