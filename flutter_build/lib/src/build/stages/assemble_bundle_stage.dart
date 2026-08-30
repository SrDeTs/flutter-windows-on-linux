//   <app>/
//     <app>.exe
//     flutter_windows.dll
//     data/
//       icudtl.dat
//       app.so            (release/profile)

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../engine_artifacts.dart';
import '../../exceptions.dart';
import '../build_context.dart';
import '../incremental.dart';
import '../native_dll.dart' as dll;
import 'build_stage.dart';

class AssembleBundleStage extends BuildStage {
  AssembleBundleStage({super.logger, super.runner});

  @override
  String get name => 'assemble Windows bundle';

  @override
  Future<void> run(BuildContext ctx) async {
    final outDir = ctx.outputDir;
    final dataDir = ctx.dataDir;
    await Directory(outDir).create(recursive: true);
    await Directory(ctx.flutterAssetsDir).create(recursive: true);

    final scan = _scanCmakeBuild(ctx);
    final builtExe = scan.exe;
    if (builtExe == null) {
      throw ArtifactException(
        'Build completed but ${ctx.project.appName}.exe was not found under '
        '${ctx.cmakeBuildDir}.',
      );
    }
    await _copyIfChanged(builtExe, ctx.finalExe);
    // Keep the project's real exe name alongside, since Windows shortcuts /
    // installers reference BINARY_NAME (may differ from the pubspec name).
    if (p.basename(builtExe.path) != p.basename(ctx.finalExe)) {
      await _copyIfChanged(
        builtExe,
        p.join(p.dirname(ctx.finalExe), p.basename(builtExe.path)),
      );
    }

    final engineDll = ctx.artifacts.flutterWindowsDllForMode(ctx.mode);
    if (File(engineDll).existsSync()) {
      await _copyIfChanged(
        File(engineDll),
        p.join(outDir, 'flutter_windows.dll'),
      );
    }

    for (final dllFile in scan.dlls) {
      final name = p.basename(dllFile.path);
      final dest = p.join(outDir, name);
      await _copyIfChanged(dllFile, dest);
    }

    final scanner = dll.NativeDllScanner(logger: log);
    await scanner.copyResolvedReferencedDlls(
      outDir: outDir,
      plugins: ctx.project.plugins,
    );
    //    FLUTTER_BUILD_DLL_SEARCH_ROOT fully overrides (set it to a nonexistent
    //    path to disable the sweep entirely — recommended when the parent dirs
    //    contain unrelated Windows DLLs, e.g. wine prefixes or toolchains).
    final envRoot = Platform.environment['FLUTTER_BUILD_DLL_SEARCH_ROOT'];
    await scanner.copyPrebuiltDlls(
      outDir: outDir,
      searchRoot: envRoot ??
          ctx.dllSearchRoot ??
          p.dirname(p.dirname(ctx.project.root)),
    );

    await Directory(dataDir).create(recursive: true);
    if (File(ctx.artifacts.icudtl).existsSync()) {
      await _copyIfChanged(
        File(ctx.artifacts.icudtl),
        p.join(dataDir, 'icudtl.dat'),
      );
    }

    if (ctx.mode.isAot && File(ctx.appAotElf).existsSync()) {
      await _copyIfChanged(File(ctx.appAotElf), p.join(dataDir, 'app.so'));
    }

    await _bundleFlutterAssets(ctx);

    // Flutter's stock Windows CMake install step copies
    // `${PROJECT_BUILD_DIR}/native_assets/windows/` beside the executable.
    // Our direct `flutter assemble` output nests that directory under
    // flutter_assets, so reproduce the install step explicitly. Entries in
    // NativeAssetsManifest.json use `absolute` names such as `sqlite3.dll`
    // and will fail at runtime if they remain nested inside data/.
    await _copyWindowsNativeAssets(ctx);

    final assetsEmpty = Directory(ctx.flutterAssetsDir).listSync().isEmpty;
    if (assetsEmpty) {
      log.warn(
          'data/flutter_assets is empty; asset packaging may have failed.');
      log.warn(
          'Run the executable from PowerShell or use --debug-console for logs.');
    }

    scanner.verifyPluginNativeDlls(
      outDir: outDir,
      plugins: ctx.project.plugins,
    );
  }

  /// Copies an artifact only when its source is newer or its size changed.
  /// Besides avoiding disk I/O, preserving destination mtimes lets packaging
  /// layers reliably detect that a bundle is unchanged.
  Future<void> _copyIfChanged(File source, String destination) async {
    final dest = File(destination);
    if (dest.existsSync()) {
      final sourceStat = source.statSync();
      final destStat = dest.statSync();
      if (sourceStat.size == destStat.size &&
          !sourceStat.modified.isAfter(destStat.modified)) {
        return;
      }
    }
    await dest.parent.create(recursive: true);
    await source.copy(destination);
  }

  Future<void> _copyWindowsNativeAssets(BuildContext ctx) async {
    final nativeAssets = Directory(
      p.join(ctx.flutterAssetsDir, 'native_assets', 'windows'),
    );
    if (!nativeAssets.existsSync()) return;

    for (final entity in nativeAssets.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: nativeAssets.path);
      await _copyIfChanged(entity, p.join(ctx.outputDir, relative));
    }
  }

  ///
  /// Projects may customize CMake's BINARY_NAME (e.g. "MyCalls" for
  /// mycalls_app), so any runner-produced .exe is accepted, preferring the
  /// pubspec-derived name first.
  ({File? exe, List<File> dlls}) _scanCmakeBuild(BuildContext ctx) {
    final name = '${ctx.project.appName}.exe';
    final sep = p.separator;
    final dlls = <File>[];
    final exeCandidates = <File>[];
    final dir = Directory(ctx.cmakeBuildDir);
    if (dir.existsSync()) {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (base.endsWith('.dll')) {
          dlls.add(e);
        } else if (base.endsWith('.exe') &&
            !e.path.contains('${sep}CMakeFiles$sep')) {
          exeCandidates.add(e);
        }
      }
    }
    return (exe: _pickExe(ctx, exeCandidates, name), dlls: dlls);
  }

  File? _pickExe(BuildContext ctx, List<File> candidates, String name) {
    for (final pref in <String>[
      p.join(ctx.cmakeBuildDir, 'runner', name),
      p.join(ctx.cmakeBuildDir, name),
    ]) {
      for (final f in candidates) {
        if (p.equals(f.path, pref)) return f;
      }
    }
    return candidates.isNotEmpty ? candidates.first : null;
  }

  ///
  Future<void> _bundleFlutterAssets(BuildContext ctx) async {
    final cachedDepfile = File(
      p.join(ctx.intermediatesDir, 'flutter_assets.d'),
    );
    final stampFile = File(
      p.join(ctx.intermediatesDir, 'flutter_assets.stamp'),
    );
    final manifest = p.join(ctx.flutterAssetsDir, 'AssetManifest.bin');
    final expectedStamp = hashInputs(<String>[
      'flutter-assets-v1',
      'flutter=${ctx.env.flutterVersion}',
      'engine=${ctx.env.engineCommitHash}',
      'mode=${ctx.mode.cliName}',
      'treeShakeIcons=${ctx.treeShakeIcons}',
    ]);

    if (ctx.incremental &&
        cachedDepfile.existsSync() &&
        stampFile.existsSync()) {
      final inputs = parseDepfileInputs(cachedDepfile.readAsStringSync())
          .where((path) => !p.basename(path).startsWith(
                'DOES_NOT_EXIST_RERUN_FOR_WILDCARD',
              ))
          .toSet()
          .toList();
      if (inputs.isNotEmpty &&
          isUpToDate(
            outputPath: manifest,
            inputPaths: <String>[
              ...inputs,
              ctx.kernelDill,
              if (ctx.mode.isAot) ctx.appAotElf,
            ],
            stampPath: stampFile.path,
            expectedStamp: expectedStamp,
          )) {
        log.info('  flutter_assets não mudou; reutilizando bundle de assets.');
        return;
      }
    }

    log.info('  Generating flutter_assets with flutter assemble...');
    final env = <String, String>{
      'PROGRAMFILES(X86)': '',
    };
    await runner.run(
      p.join(ctx.env.sdkRoot, 'bin', 'flutter'),
      <String>[
        'assemble',
        '-dTargetPlatform=windows-x64',
        '-dBuildMode=${ctx.mode.cliName}',
        '-dTreeShakeIcons=${ctx.treeShakeIcons}',
        '--output=${ctx.flutterAssetsDir}',
        'copy_flutter_bundle',
      ],
      workingDirectory: ctx.project.root,
      environment: env,
      stream: true,
      tag: 'assemble',
    );

    final generatedDepfile = _findGeneratedAssetDepfile(ctx);
    if (generatedDepfile != null) {
      await cachedDepfile.writeAsString(generatedDepfile.readAsStringSync());
      await stampFile.writeAsString(expectedStamp);
    } else {
      log.warn('  flutter_assets.d não encontrado; cache de assets desativado '
          'nesta execução.');
    }
  }

  /// Finds Flutter's depfile for this exact output directory. The hash under
  /// `.dart_tool/flutter_build` is intentionally opaque and can change across
  /// SDK releases, so matching the declared outputs is more robust than
  /// reconstructing that hash.
  File? _findGeneratedAssetDepfile(BuildContext ctx) {
    final root = Directory(
      p.join(ctx.project.root, '.dart_tool', 'flutter_build'),
    );
    if (!root.existsSync()) return null;

    File? newest;
    final outputNeedle = p.normalize(ctx.flutterAssetsDir);
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || p.basename(entity.path) != 'flutter_assets.d') {
        continue;
      }
      final content = entity.readAsStringSync();
      if (!content.contains(outputNeedle)) continue;
      if (newest == null ||
          entity.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
        newest = entity;
      }
    }
    return newest;
  }
}
