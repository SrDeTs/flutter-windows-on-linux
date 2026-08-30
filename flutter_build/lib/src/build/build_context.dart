//

import 'package:path/path.dart' as p;

import '../engine_artifacts.dart';
import '../flutter_env.dart';
import '../project.dart';
import '../toolchain.dart';

class BuildContext {
  BuildContext({
    required this.env,
    required this.project,
    required this.artifacts,
    required this.toolchain,
    required this.mode,
    required this.buildRoot,
    this.dartDefines = const <String>[],
    this.enableObfuscation = false,
    this.splitDebugInfoDir,
    this.treeShakeIcons = true,
    this.verbose = false,
    this.debugConsole = false,
    this.incremental = true,
    this.dllSearchRoot,
  });

  final FlutterEnv env;
  final FlutterProject project;
  final EngineArtifacts artifacts;
  final Toolchain toolchain;
  final WindowsFlavor mode;
  final String buildRoot;
  final List<String> dartDefines;
  final bool enableObfuscation;
  final String? splitDebugInfoDir;
  final bool treeShakeIcons;
  final bool verbose;

  final bool debugConsole;

  final bool incremental;

  final String? dllSearchRoot;

  String get modeDir => p.join(buildRoot, mode.cliName);

  String get windowsStageDir => p.join(modeDir, 'windows_src');

  String get cmakeBuildDir => p.join(modeDir, 'cmake_build');

  String get intermediatesDir => p.join(modeDir, 'intermediates');

  String get kernelDill => p.join(intermediatesDir, 'app.dill');

  String get appAotElf => p.join(intermediatesDir, 'app.so');

  /// (Actual exe basename may differ when the project customizes CMake's
  /// BINARY_NAME; AssembleBundleStage copies the built name into this path.)
  String get finalExe =>
      p.join(modeDir, project.appName, '${project.appName}.exe');

  String get outputDir => p.dirname(finalExe);

  String get dataDir => p.join(outputDir, 'data');

  String get flutterAssetsDir => p.join(dataDir, 'flutter_assets');

  String get mingwCompatDir => p.join(intermediatesDir, 'mingw_compat');
}
