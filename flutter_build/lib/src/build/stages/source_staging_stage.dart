//

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../io/fs_utils.dart';
import '../build_context.dart';
import '../debug_instrumentation.dart';
import '../flutter_ephemeral.dart';
import '../incremental.dart';
import '../plugin_source_patcher.dart';
import 'build_stage.dart';

///
Future<void> materializePluginSymlinks(
    BuildContext ctx, String ephemeralDir) async {
  final symlinkDir = Directory(p.join(ephemeralDir, '.plugin_symlinks'));
  if (symlinkDir.existsSync()) {
    await symlinkDir.delete(recursive: true);
  }
  await symlinkDir.create(recursive: true);

  for (final plugin in ctx.project.plugins.where((p) => p.hasNativeCode)) {
    final linkPath = p.join(symlinkDir.path, plugin.name);
    final existing = FileSystemEntity.typeSync(linkPath);
    if (existing == FileSystemEntityType.link) {
      await Link(linkPath).delete();
    } else if (existing == FileSystemEntityType.directory) {
      await Directory(linkPath).delete(recursive: true);
    } else if (existing != FileSystemEntityType.notFound) {
      await File(linkPath).delete();
    }
    await Link(linkPath).create(plugin.rootPath, recursive: true);
  }
}

class SourceStagingStage extends BuildStage {
  SourceStagingStage({super.logger, super.runner});

  @override
  String get name => 'stage Windows CMake sources';

  @override
  Future<void> run(BuildContext ctx) async {
    await Directory(ctx.intermediatesDir).create(recursive: true);
    final stagingStamp = File(
      p.join(ctx.intermediatesDir, 'windows_source_staging.stamp'),
    );
    final expectedStamp = _stagingFingerprint(ctx);
    if (ctx.incremental &&
        stagingStamp.existsSync() &&
        stagingStamp.readAsStringSync() == expectedStamp &&
        _isCompleteStage(ctx)) {
      log.info(
          '  fontes Windows não mudaram; reutilizando stage e cache Ninja.');
      return;
    }

    // Always restage from scratch: merging into a previous (possibly
    // half-finished) tree leaves stale symlinks/copies behind.
    final staleStage = Directory(ctx.windowsStageDir);
    if (staleStage.existsSync()) {
      await staleStage.delete(recursive: true);
    }
    await Directory(ctx.windowsStageDir).create(recursive: true);
    await copyTree(ctx.project.windowsDir, ctx.windowsStageDir);
    _applySidecarEdits(ctx);
    await _generateFlutterEphemeral(ctx);
    await _patchPluginSources(ctx);
    await _normalizeResourceScripts(ctx);
    if (ctx.debugConsole) await _instrumentRunner(ctx);
    await stagingStamp.writeAsString(expectedStamp);
  }

  String _stagingFingerprint(BuildContext ctx) {
    const schema = 'source-staging-v5';
    final pluginInputs = <String>[
      for (final plugin in ctx.project.plugins.where((p) => p.hasNativeCode))
        plugin.windowsCMakeDir,
    ];
    return hashInputs(<String>[
      schema,
      'flutter=${ctx.env.flutterVersion}',
      'engine=${ctx.env.engineCommitHash}',
      'mode=${ctx.mode.name}',
      'debugConsole=${ctx.debugConsole}',
      'sidecar=${Platform.environment['SIDECAR_MSVC'] ?? ''}',
      'cppwinrt=${Platform.environment['CPPWINRT_INCLUDE_DIR'] ?? ''}',
      'plugins=${ctx.project.plugins.map((p) => '${p.name}:${p.rootPath}').join('|')}',
      fileTreeMetadataFingerprint(<String>[
        ctx.project.windowsDir,
        ctx.project.packageConfig,
        ...pluginInputs,
      ]),
    ]);
  }

  bool _isCompleteStage(BuildContext ctx) {
    final flutterDir = p.join(ctx.windowsStageDir, 'flutter');
    return File(p.join(ctx.windowsStageDir, 'CMakeLists.txt')).existsSync() &&
        File(p.join(flutterDir, 'generated_plugins.cmake')).existsSync() &&
        File(p.join(flutterDir, 'generated_plugin_registrant.cc'))
            .existsSync() &&
        File(p.join(flutterDir, 'ephemeral', 'generated_config.cmake'))
            .existsSync() &&
        Directory(p.join(flutterDir, 'ephemeral', '.plugin_symlinks'))
            .existsSync();
  }

  /// When SIDECAR_MSVC=1, livekit_client and flutter_webrtc are built by
  /// [SidecarMsvcStage] with clang-cl (MSVC ABI) instead of the windows-gnu
  /// CMake graph: remove them from generated_plugins.cmake and teach the
  /// staged root CMakeLists to link their dlltool import libraries.
  void _applySidecarEdits(BuildContext ctx) {
    if (Platform.environment['SIDECAR_MSVC'] != '1') return;
    final stagedFlutter = p.join(ctx.windowsStageDir, 'flutter');

    final pluginsFile = File(p.join(stagedFlutter, 'generated_plugins.cmake'));
    if (pluginsFile.existsSync()) {
      const sidecarPlugins = [
        'flutter_webrtc',
        'livekit_client',
        'permission_handler_windows',
        'flutter_local_notifications_windows',
        'share_plus',
        'connectivity_plus',
        'flutter_secure_storage_windows',
        'audioplayers_windows',
      ];
      final content = pluginsFile.readAsStringSync();
      final filtered = content
          .split('\n')
          .where((l) => !sidecarPlugins.any(l.contains))
          .join('\n');
      if (filtered != content) pluginsFile.writeAsStringSync(filtered);
    }

    // The sidecar plugin headers live outside the CMake include graph now;
    // replace their #includes with plain extern "C" declarations so the
    // MinGW-compiled registrant only needs the C ABI.
    final registrant =
        File(p.join(stagedFlutter, 'generated_plugin_registrant.cc'));
    if (registrant.existsSync()) {
      const externDecls = '''
extern "C" {
void FlutterWebRTCPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void LiveKitPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void PermissionHandlerWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void SharePlusWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void ConnectivityPlusWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
void AudioplayersWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
}
''';
      var content = registrant.readAsStringSync();
      for (final inc in [
        '#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>',
        '#include <livekit_client/live_kit_plugin.h>',
        '#include <permission_handler_windows/permission_handler_windows_plugin.h>',
        '#include <share_plus/share_plus_windows_plugin_c_api.h>',
        '#include <connectivity_plus/connectivity_plus_windows_plugin.h>',
        '#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>',
        '#include <audioplayers_windows/audioplayers_windows_plugin.h>',
      ]) {
        content = content.replaceFirst(inc, '');
      }
      if (!content.contains(externDecls)) {
        final marker = 'void RegisterPlugins(';
        final idx = content.indexOf(marker);
        if (idx >= 0) {
          content = content.replaceFirst(marker, '$externDecls\n$marker');
        }
      }
      registrant.writeAsStringSync(content);
    }

    // The registrant keeps calling the extern "C" registrar symbols; only
    // the plugin *targets* disappear from the CMake graph.
    final rootCmake = File(p.join(ctx.windowsStageDir, 'CMakeLists.txt'));
    if (rootCmake.existsSync()) {
      const marker = '# flutter_build sidecar imports';
      var content = rootCmake.readAsStringSync();
      if (!content.contains(marker)) {
        content = '$content\n'
            '$marker\n'
            'if(DEFINED ENV{SIDECAR_IMPORT_LIBS})\n'
            '  target_link_libraries(\${BINARY_NAME} PRIVATE '
            '\$ENV{SIDECAR_IMPORT_LIBS})\n'
            'endif()\n';
        rootCmake.writeAsStringSync(content);
      }
    }
  }

  /// Scan staged plugin CMakeLists for `nuget install <Pkg> -Version <V>`
  /// and pre-download each .nupkg into the shared preseed dir
  /// (`~/.flutter_build/nuget/<Pkg>.<V>/`), so the CMakeLists patcher can
  /// bypass nuget.exe (unrunnable on Linux) with identical content.
  Future<void> _preseedNugetPackages(BuildContext ctx) async {
    final linksDir = Directory(p.join(
        ctx.windowsStageDir, 'flutter', 'ephemeral', '.plugin_symlinks'));
    if (!linksDir.existsSync()) return;
    final home = Platform.environment['HOME'] ?? '.';
    final nugetRoot = Directory(p.join(
        Platform.environment['FLUTTER_BUILD_NUGET_PRESEED'] ??
            p.join(home, '.flutter_build', 'nuget')));
    final re = RegExp(
        r'install\s+([A-Za-z0-9_.-]+)\s+-Version\s+(?:\$\{(\w+)\}|([0-9][A-Za-z0-9.*]*))');
    final seen = <String>{};
    for (final pluginDir in linksDir.listSync()) {
      final cm = File(p.join(pluginDir.path, 'windows', 'CMakeLists.txt'));
      if (!cm.existsSync()) continue;
      final content = cm.readAsStringSync();
      for (final m in re.allMatches(content)) {
        final pkg = m.group(1)!;
        var ver = m.group(3);
        final verVar = m.group(2);
        if (ver == null && verVar != null) {
          final vm = RegExp('set\\($verVar\\s+"([0-9A-Za-z.]+)"\\)')
              .firstMatch(content);
          if (vm == null) continue;
          ver = vm.group(1)!;
        }
        ver ??= '';
        if (ver.isEmpty) continue;
        final key = '$pkg.$ver';
        if (!seen.add(key)) continue;
        final dest = Directory(p.join(nugetRoot.path, key));
        if (dest.existsSync()) continue;
        log.info('Pre-seed NuGet: $pkg $ver');
        dest.createSync(recursive: true);
        final zip = p.join(nugetRoot.path, '$key.nupkg');
        await runner.run(
            'curl',
            [
              '-fL',
              '-o',
              zip,
              'https://www.nuget.org/api/v2/package/$pkg/$ver',
            ],
            stream: true,
            tag: 'curl');
        await runner.run('bsdtar', ['-xf', zip, '-C', dest.path]);
      }
    }
  }

  Future<void> _instrumentRunner(BuildContext ctx) async {
    final mainCpp = File(p.join(ctx.windowsStageDir, 'runner', 'main.cpp'));
    if (!mainCpp.existsSync()) {
      log.debug(
          'runner/main.cpp was not found; skipping debug instrumentation.');
      return;
    }
    final patched = instrumentRunnerMain(await mainCpp.readAsString());
    await mainCpp.writeAsString(patched);
    log.info('Debug instrumentation enabled. Engine logs and startup failures '
        'will be shown in PowerShell/cmd.');
  }

  Future<void> _patchPluginSources(BuildContext ctx) async {
    final ephemeralDir = p.join(ctx.windowsStageDir, 'flutter', 'ephemeral');
    await const PluginSourcePatcher().apply(ephemeralDir, logger: log);
  }

  Future<void> _normalizeResourceScripts(BuildContext ctx) async {
    final dir = Directory(ctx.windowsStageDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.rc') continue;
      final content = await entity.readAsString();
      if (!content.contains(r'\\')) continue;
      await entity.writeAsString(content.replaceAll(r'\\', '/'));
    }
  }

  Future<void> _generateFlutterEphemeral(BuildContext ctx) async {
    final stagedFlutterDir = p.join(ctx.windowsStageDir, 'flutter');
    final ephemeralDir = p.join(stagedFlutterDir, 'ephemeral');
    await Directory(ephemeralDir).create(recursive: true);

    final art = ctx.artifacts;
    await copyFileIfExists(
        art.flutterWindowsDll, p.join(ephemeralDir, 'flutter_windows.dll'));
    await copyFileIfExists(art.flutterWindowsImportLib,
        p.join(ephemeralDir, 'flutter_windows.dll.lib'));
    for (final h in _embedderHeaderNames(art.embedderDir)) {
      await copyFileIfExists(
          p.join(art.embedderDir, h), p.join(ephemeralDir, h));
    }
    await copyTree(
        art.cppClientWrapperDir, p.join(ephemeralDir, 'cpp_client_wrapper'));
    await copyFileIfExists(art.icudtl, p.join(ephemeralDir, 'icudtl.dat'));
    await materializePluginSymlinks(ctx, ephemeralDir);
    await _preseedNugetPackages(ctx);

    final version = parseFlutterVersion(ctx.project.versionString);
    await File(p.join(ephemeralDir, 'generated_config.cmake')).writeAsString(
      renderGeneratedConfigCmake(
        flutterRoot: ctx.env.sdkRoot,
        projectDir: ctx.project.root,
        version: version,
      ),
    );

    final flutterCmake = File(p.join(stagedFlutterDir, 'CMakeLists.txt'));
    if (flutterCmake.existsSync()) {
      final original = await flutterCmake.readAsString();
      final patched = neutralizeFlutterAssemble(original);
      if (patched == original) {
        log.debug(
            'Flutter tool backend marker not found; skipping neutralization.');
      } else {
        await flutterCmake.writeAsString(patched);
      }
    }

    final generatedPlugins =
        File(p.join(stagedFlutterDir, 'generated_plugins.cmake'));
    if (generatedPlugins.existsSync()) {
      final content = await generatedPlugins.readAsString();
      if (!content.contains('IMPORT_PREFIX')) {
        const marker =
            '  add_subdirectory(flutter/ephemeral/.plugin_symlinks/\${plugin}/windows plugins/\${plugin})';
        const insertion = '$marker\n'
            '  set_target_properties(\${plugin}_plugin PROPERTIES PREFIX "" IMPORT_PREFIX "")';
        final patched = content.replaceAll(marker, insertion);
        if (patched != content) {
          await generatedPlugins.writeAsString(patched);
          log.debug('Removed the MinGW lib prefix from plugin targets.');
        }
      }
    }
  }

  Iterable<String> _embedderHeaderNames(String embedderDir) {
    final names = <String>{...kEmbedderHeaders};
    final dir = Directory(embedderDir);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File && p.extension(entity.path) == '.h') {
          names.add(p.basename(entity.path));
        }
      }
    }
    return names;
  }
}
