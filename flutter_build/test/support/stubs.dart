//

import 'package:flutter_build/src/build/build_context.dart';
import 'package:flutter_build/src/engine_artifacts.dart';
import 'package:flutter_build/src/flutter_env.dart';
import 'package:flutter_build/src/project.dart';
import 'package:flutter_build/src/toolchain.dart';

FlutterEnv stubEnv() => FlutterEnv.forTesting(
      sdkRoot: '/sdk',
      flutterVersion: '3.22.0',
      dartSdkVersion: '3.5.0',
      engineCommitHash: 'abc123',
      engineRealm: '',
      storageBaseUrl: 'https://storage.googleapis.com',
      dartExecutable: '/sdk/bin/cache/dart-sdk/bin/dart',
      frontendServerSnapshot:
          '/sdk/bin/cache/artifacts/engine/linux-x64/frontend_server_aot.dart.snapshot',
      hostEngineDir: '/sdk/bin/cache/artifacts/engine/linux-x64',
    );

FlutterProject stubProject({
  String root = '/home/user/myapp',
  String appName = 'myapp',
  String? entryPoint,
  String? windowsDir,
  bool hasWindowsScaffold = true,
  List<WindowsPluginRef> plugins = const <WindowsPluginRef>[],
}) =>
    FlutterProject.forTesting(
      root: root,
      appName: appName,
      entryPoint: entryPoint ?? '$root/lib/main.dart',
      windowsDir: windowsDir ?? '$root/windows',
      hasWindowsScaffold: hasWindowsScaffold,
      plugins: plugins,
    );

EngineArtifacts stubArtifacts() => EngineArtifacts(
      env: stubEnv(),
      embedderDir: '/sdk/bin/cache/artifacts/engine/windows-x64',
      releaseArtifactsDir:
          '/sdk/bin/cache/artifacts/engine/windows-x64-release',
      profileArtifactsDir:
          '/sdk/bin/cache/artifacts/engine/windows-x64-profile',
      hostEngineDir: '/sdk/bin/cache/artifacts/engine/linux-x64',
    );

Toolchain stubToolchain() => Toolchain(
      llvmMingwRoot: '/opt/llvm-mingw',
      targetTriple: 'x86_64-w64-mingw32',
      wineExecutable: '/usr/bin/wine64',
      cmakeExecutable: '/usr/bin/cmake',
      ninjaExecutable: '/usr/bin/ninja',
    );

BuildContext stubContext({
  required String buildRoot,
  WindowsFlavor mode = WindowsFlavor.release,
  FlutterProject? project,
  List<String> dartDefines = const <String>[],
}) =>
    BuildContext(
      env: stubEnv(),
      project: project ?? stubProject(),
      artifacts: stubArtifacts(),
      toolchain: stubToolchain(),
      mode: mode,
      buildRoot: buildRoot,
      dartDefines: dartDefines,
    );
