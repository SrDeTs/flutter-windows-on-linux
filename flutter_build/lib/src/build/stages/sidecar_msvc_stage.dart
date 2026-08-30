// Sidecar: build livekit_client + flutter_webrtc native plugins against the
// prebuilt MSVC-ABI libwebrtc.dll using the real MSVC toolchain under Wine
// (msvc-wine layout: <root>/bin/x64/{cl,link} wrappers).
//
// Why: both plugins bind directly to libwebrtc.dll through C++ classes
// (portable::string, scoped_refptr, ...) whose symbols are MSVC-mangled in
// the import library — unresolvable by Itanium-mangled windows-gnu objects.
// The registrar entry points are extern "C", so the MinGW-linked app exe
// keeps resolving them from small dlltool-generated import libraries.
//
// Requirements:
//   MSVC_ROOT   msvc-wine install root (default ~/.msvc2)
//   WIN_SDK_ROOT unused here — SDK inside MSVC_ROOT is used
//   PATH        must contain llvm-dlltool (llvm package)
//
// Outputs consumed downstream without further wiring:
//   <cmake_build>/plugins/flutter_webrtc/flutter_webrtc_plugin.dll (+ libwebrtc.dll)
//   <cmake_build>/plugins/livekit_client/livekit_client_plugin.dll
//   $ENV{SIDECAR_IMPORT_LIBS} → dlltool .lib files linked into the exe.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../exceptions.dart';
import '../build_context.dart';
import '../incremental.dart';
import 'build_stage.dart';

class SidecarMsvcStage extends BuildStage {
  SidecarMsvcStage({super.logger, super.runner});

  @override
  String get name => 'build webrtc/livekit plugins with MSVC under Wine';

  @override
  Future<void> run(BuildContext ctx) async {
    final home = Platform.environment['HOME'] ?? '';
    final msvcRoot =
        Platform.environment['MSVC_ROOT'] ?? p.join(home, '.msvc2');

    final binDir = p.join(msvcRoot, 'bin', 'x64');
    final cl = File(p.join(binDir, 'cl'));
    final link = File(p.join(binDir, 'link'));
    if (!cl.existsSync() || !link.existsSync()) {
      throw ArtifactException(
        'msvc-wine wrappers não encontrados em $binDir',
        hint: 'Rode ./install.sh <dest> do repositório msvc-wine.',
      );
    }

    // Tool versions + Windows-style environment for cl/link.
    final vcDir = p.join(msvcRoot, 'VC', 'Tools', 'MSVC',
        _latest(p.join(msvcRoot, 'VC', 'Tools', 'MSVC')));
    final kitsDir = p.join(msvcRoot, 'Windows Kits', '10');
    final sdkVer = _latest(p.join(kitsDir, 'Include'));
    String win(String posixPath) =>
        'Z:\\${posixPath.replaceAll('/', '\\').replaceFirst('\\', '')}';

    var include = [
      '${win(vcDir)}\\include',
      '${win(kitsDir)}\\Include\\$sdkVer\\um',
      '${win(kitsDir)}\\Include\\$sdkVer\\shared',
      '${win(kitsDir)}\\Include\\$sdkVer\\ucrt',
    ].join(';');
    var lib = [
      '${win(vcDir)}\\lib\\x64',
      '${win(kitsDir)}\\Lib\\$sdkVer\\um\\x64',
      '${win(kitsDir)}\\Lib\\$sdkVer\\ucrt\\x64',
    ].join(';');
    // ATL lives under <VC>/atlmfc when installed; flutter_local_notifications
    // genuinely uses CComPtr etc.
    final atlInc = Directory(p.join(vcDir, 'atlmfc', 'include'));
    if (atlInc.existsSync()) {
      include += ';${win(p.join(atlInc.path))}';
      lib += ';${win(p.join(vcDir, 'atlmfc', 'lib', 'x64'))}';
    }
    final toolEnv = <String, String>{'INCLUDE': include, 'LIB': lib};

    final wrapperInc = p.join(ctx.artifacts.cppClientWrapperDir, 'include');
    final embedderInc = ctx.artifacts.embedderDir;
    final webrtc = ctx.project.plugins
        .firstWhere((e) => e.name == 'flutter_webrtc')
        .rootPath;
    final livekit = ctx.project.plugins
        .firstWhere((e) => e.name == 'livekit_client')
        .rootPath;

    final outRoot = p.join(ctx.cmakeBuildDir, 'sidecar');
    final objDir = p.join(outRoot, 'obj');
    await Directory(objDir).create(recursive: true);

    final winLibRoot = await _ensurePrivateWebrtcWin(webrtc, outRoot);
    final webrtcWinInc = p.join(winLibRoot, 'include');
    final webrtcWinImportLib = p.join(winLibRoot, 'lib', 'libwebrtc.dll.lib');
    final webrtcWinDll = p.join(winLibRoot, 'lib', 'libwebrtc.dll');

    final pluginsOut = p.join(ctx.cmakeBuildDir, 'plugins');
    final importDir = p.join(outRoot, 'import');
    final sidecarOutputs = <String>[
      p.join(pluginsOut, 'flutter_webrtc', 'flutter_webrtc_plugin.dll'),
      p.join(pluginsOut, 'flutter_webrtc', 'libwebrtc.dll'),
      p.join(pluginsOut, 'livekit_client', 'livekit_client_plugin.dll'),
      p.join(pluginsOut, 'permission_handler_windows',
          'permission_handler_windows_plugin.dll'),
      p.join(pluginsOut, 'flutter_local_notifications_windows',
          'flutter_local_notifications_windows.dll'),
      p.join(pluginsOut, 'share_plus_plugin', 'share_plus_plugin.dll'),
      p.join(pluginsOut, 'connectivity_plus_plugin',
          'connectivity_plus_plugin.dll'),
      p.join(pluginsOut, 'flutter_secure_storage_windows_plugin',
          'flutter_secure_storage_windows_plugin.dll'),
      p.join(pluginsOut, 'audioplayers_windows_plugin',
          'audioplayers_windows_plugin.dll'),
      for (final name in <String>[
        'flutter_webrtc_plugin',
        'livekit_client_plugin',
        'permission_handler_windows_plugin',
        'share_plus_plugin',
        'connectivity_plus_plugin',
        'flutter_secure_storage_windows_plugin',
        'audioplayers_windows_plugin',
      ])
        p.join(importDir, '${name}_import.lib'),
    ];
    final sidecarStamp = File(p.join(outRoot, '.inputs.stamp'));
    final expectedSidecarStamp = hashInputs(<String>[
      'sidecar-msvc-v4',
      'vc=$vcDir',
      'sdk=$sdkVer',
      'storagePrefix=${Platform.environment['STORAGE_PREFIX'] ?? ctx.project.appName}',
      fileTreeMetadataFingerprint(<String>[
        ctx.artifacts.cppClientWrapperDir,
        ctx.artifacts.embedderDir,
        ctx.artifacts.flutterWindowsImportLib,
        winLibRoot,
        if ((Platform.environment['CPPWINRT_INCLUDE_DIR'] ?? '').isNotEmpty)
          Platform.environment['CPPWINRT_INCLUDE_DIR']!,
        for (final plugin in ctx.project.plugins.where(
          (plugin) => const <String>{
            'flutter_webrtc',
            'livekit_client',
            'permission_handler_windows',
            'flutter_local_notifications_windows',
            'share_plus',
            'connectivity_plus',
            'flutter_secure_storage_windows',
            'audioplayers_windows',
          }.contains(plugin.name),
        ))
          plugin.rootPath,
      ]),
    ]);
    if (ctx.incremental &&
        sidecarStamp.existsSync() &&
        sidecarStamp.readAsStringSync() == expectedSidecarStamp &&
        sidecarOutputs.every((output) => File(output).existsSync())) {
      log.info('  sidecar MSVC não mudou; reutilizando DLLs e import libs.');
      return;
    }

    // ── 1. engine cpp_client_wrapper (shared by both plugins) ──
    final wrapperObjs = <File>[];
    // Newer SDKs ship a consolidated core_implementations.cc alongside the
    // legacy per-class translation units; linking both double-defines
    // TextureRegistrarImpl etc. Skip the legacy duplicates.
    const legacyDuplicates = {'engine_method_result.cc'};
    for (final f in _sources(ctx.artifacts.cppClientWrapperDir)
        .where((f) => !legacyDuplicates.contains(p.basename(f.path)))) {
      wrapperObjs.add(await _compile(cl.path, f, objDir, toolEnv, [
        '/I${win(wrapperInc)}',
        '/I${win(embedderInc)}',
        '/DFLUTTER_PLUGIN_IMPL',
      ]));
    }

    // ── 2. flutter_webrtc_plugin.dll ──
    final webrtcDef = p.join(outRoot, 'flutter_webrtc_plugin.def');
    await File(webrtcDef).writeAsString('''
LIBRARY flutter_webrtc_plugin
EXPORTS
  FlutterWebRTCPluginRegisterWithRegistrar
  FlutterWebRTCPluginSharedInstance
''');
    final webrtcInc = [
      '/I${win(p.join(webrtc, "windows"))}',
      '/I${win(p.join(webrtc, 'common', 'cpp', 'include'))}',
      '/I${win(p.join(webrtc, 'third_party', 'svpng'))}',
      '/I${win(webrtcWinInc)}',
      '/I${win(wrapperInc)}',
      '/I${win(embedderInc)}',
    ];
    const webrtcDefines = [
      '/DFLUTTER_PLUGIN_IMPL',
      '/DLIB_WEBRTC_API_DLL',
      '/DRTC_DESKTOP_DEVICE',
      '/DNOMINMAX',
      '/DWIN32',
      '/DUNICODE',
      '/D_UNICODE',
    ];
    final webrtcObjs = <File>[
      for (final f in _sources(p.join(webrtc, 'common', 'cpp', 'src')))
        await _compile(
            cl.path, f, objDir, toolEnv, [...webrtcDefines, ...webrtcInc]),
      for (final f in _sources(p.join(webrtc, 'windows')))
        await _compile(
            cl.path, f, objDir, toolEnv, [...webrtcDefines, ...webrtcInc]),
    ];

    final webrtcOutDir = p.join(pluginsOut, 'flutter_webrtc');
    await Directory(webrtcOutDir).create(recursive: true);
    final webrtcDll = p.join(webrtcOutDir, 'flutter_webrtc_plugin.dll');
    await _run(
        link.path,
        [
          '/DLL',
          '/NOLOGO',
          '/OUT:${win(webrtcDll)}',
          '/DEF:${win(webrtcDef)}',
          ...wrapperObjs.map((f) => win(f.path)),
          ...webrtcObjs.map((f) => win(f.path)),
          win(webrtcWinImportLib),
          win(ctx.artifacts.flutterWindowsImportLib),
          'user32.lib',
          'avrt.lib',
          'ksuser.lib',
          'mmdevapi.lib',
          'ole32.lib',
          'runtimeobject.lib',
          'uuid.lib',
          'winmm.lib',
        ],
        toolEnv);

    // GNU-side import library so the MinGW-linked exe resolves the two
    // extern "C" entry points.
    await Directory(importDir).create(recursive: true);
    final webrtcImportLib =
        p.join(importDir, 'flutter_webrtc_plugin_import.lib');
    await _dlltool(webrtcDef, 'flutter_webrtc_plugin.dll', webrtcImportLib);

    // Runtime dependency where the assemble scan expects plugin DLLs.
    final libwebrtcDll = File(webrtcWinDll);
    if (libwebrtcDll.existsSync()) {
      await libwebrtcDll.copy(p.join(webrtcOutDir, 'libwebrtc.dll'));
    }

    // ── 3. livekit_client_plugin.dll ──
    final livekitDef = p.join(outRoot, 'livekit_client_plugin.def');
    await File(livekitDef).writeAsString('''
LIBRARY livekit_client_plugin
EXPORTS
  LiveKitPluginRegisterWithRegistrar
''');
    final livekitInc = [
      '/I${win(p.join(livekit, "windows"))}',
      '/I${win(p.join(livekit, 'shared_cpp'))}',
      '/I${win(p.join(webrtc, 'windows'))}',
      '/I${win(p.join(webrtc, 'common', 'cpp', 'include'))}',
      '/I${win(webrtcWinInc)}',
      '/I${win(wrapperInc)}',
      '/I${win(embedderInc)}',
    ];
    const livekitDefines = [
      '/DFLUTTER_PLUGIN_IMPL',
      '/DRTC_DESKTOP_DEVICE',
      '/D_USE_MATH_DEFINES',
      '/DNOMINMAX',
      '/DWIN32',
      '/DUNICODE',
      '/D_UNICODE',
    ];
    final livekitObjs = <File>[
      for (final f in _sources(p.join(livekit, 'windows')))
        await _compile(
            cl.path, f, objDir, toolEnv, [...livekitDefines, ...livekitInc]),
      for (final f in _sources(p.join(livekit, 'shared_cpp')))
        await _compile(
            cl.path, f, objDir, toolEnv, [...livekitDefines, ...livekitInc]),
    ];

    final livekitOutDir = p.join(pluginsOut, 'livekit_client');
    await Directory(livekitOutDir).create(recursive: true);
    await _run(
        link.path,
        [
          '/DLL',
          '/NOLOGO',
          '/OUT:${win(p.join(livekitOutDir, 'livekit_client_plugin.dll'))}',
          '/DEF:${win(livekitDef)}',
          ...wrapperObjs.map((f) => win(f.path)),
          ...livekitObjs.map((f) => win(f.path)),
          win(webrtcImportLib),
          win(ctx.artifacts.flutterWindowsImportLib),
          'user32.lib',
          'ole32.lib',
          'uuid.lib',
        ],
        toolEnv);

    final livekitImportLib =
        p.join(importDir, 'livekit_client_plugin_import.lib');
    await _dlltool(livekitDef, 'livekit_client_plugin.dll', livekitImportLib);

    // ── 4. permission_handler_windows.dll (C++/WinRT → compila nativo aqui) ──
    final perm = ctx.project.plugins
        .firstWhere((e) => e.name == 'permission_handler_windows')
        .rootPath;
    final permDef = p.join(outRoot, 'permission_handler_windows_plugin.def');
    await File(permDef).writeAsString('''
LIBRARY permission_handler_windows_plugin
EXPORTS
  PermissionHandlerWindowsPluginRegisterWithRegistrar
''');
    final permInc = [
      '/I${win(p.join(perm, "windows"))}',
      '/I${win(p.join(perm, 'windows', 'include'))}',
      if ((Platform.environment['CPPWINRT_INCLUDE_DIR'] ?? '').isNotEmpty)
        '/I${win(Platform.environment['CPPWINRT_INCLUDE_DIR']!)}',
      '/I${win(wrapperInc)}',
      '/I${win(embedderInc)}',
    ];
    const permDefines = [
      '/DFLUTTER_PLUGIN_IMPL',
      '/DWIN32',
      '/DUNICODE',
      '/D_UNICODE',
      '/DNOMINMAX',
      // WinRT fire_and_forget needs coroutines; use the standard C++20 ones
      // (the MSVC legacy /await switch is deprecated/removed in new STLs).
      '/std:c++20',
    ];
    final permObjs = <File>[
      for (final f in _sources(p.join(perm, 'windows')))
        await _compile(
            cl.path, f, objDir, toolEnv, [...permDefines, ...permInc]),
    ];

    final permOutDir = p.join(pluginsOut, 'permission_handler_windows');
    await Directory(permOutDir).create(recursive: true);
    await _run(
        link.path,
        [
          '/DLL',
          '/NOLOGO',
          '/OUT:${win(p.join(permOutDir, 'permission_handler_windows_plugin.dll'))}',
          '/DEF:${win(permDef)}',
          ...wrapperObjs.map((f) => win(f.path)),
          ...permObjs.map((f) => win(f.path)),
          win(ctx.artifacts.flutterWindowsImportLib),
          'user32.lib',
          'ole32.lib',
          'runtimeobject.lib',
          'WindowsApp.lib',
        ],
        toolEnv);

    final permImportLib =
        p.join(importDir, 'permission_handler_windows_plugin_import.lib');
    await _dlltool(
        permDef, 'permission_handler_windows_plugin.dll', permImportLib);

    // ── 5. flutter_local_notifications_windows.dll (FFI: WinRT + ATL) ──
    final fln = ctx.project.plugins
        .firstWhere((e) => e.name == 'flutter_local_notifications_windows')
        .rootPath;
    // Materialize + patch: including cppwinrt headers makes MSVC reject the
    // implicit CW2A→std::string user conversion; an explicit LPSTR cast keeps
    // the source MSVC-compatible while unblocking the C++20 build.
    final flnSrc = p.join(outRoot, 'fln_src');
    {
      final srcDir = Directory(p.join(fln, 'src'));
      final dstDir = Directory(flnSrc);
      if (dstDir.existsSync()) dstDir.deleteSync(recursive: true);
      dstDir.createSync(recursive: true);
      for (final f in srcDir.listSync().whereType<File>()) {
        var text = f.readAsStringSync();
        text = text
            .replaceAll('= CW2A(item.Key, CP_UTF8);',
                '= std::string(static_cast<LPSTR>(CW2A(item.Key, CP_UTF8)));')
            .replaceAll('= CW2A(item.Value, CP_UTF8);',
                '= std::string(static_cast<LPSTR>(CW2A(item.Value, CP_UTF8)));');
        File(p.join(dstDir.path, p.basename(f.path))).writeAsStringSync(text);
      }
    }
    const flnDefines = [
      '/DDART_SHARED_LIB',
      '/DWIN32',
      '/DUNICODE',
      '/D_UNICODE',
      '/DNOMINMAX',
      '/std:c++20',
    ];
    final flnInc = [
      '/I${win(flnSrc)}',
      if ((Platform.environment['CPPWINRT_INCLUDE_DIR'] ?? '').isNotEmpty)
        '/I${win(Platform.environment['CPPWINRT_INCLUDE_DIR']!)}',
      '/I${win(embedderInc)}',
      if (atlInc.existsSync()) '/I${win(p.join(atlInc.path))}',
    ];
    final flnObjs = <File>[
      for (final f in _sources(flnSrc))
        await _compile(cl.path, f, objDir, toolEnv, [...flnDefines, ...flnInc]),
    ];

    final flnOutDir = p.join(pluginsOut, 'flutter_local_notifications_windows');
    await Directory(flnOutDir).create(recursive: true);
    await _run(
        link.path,
        [
          '/DLL',
          '/NOLOGO',
          '/OUT:${win(p.join(flnOutDir, 'flutter_local_notifications_windows.dll'))}',
          ...flnObjs.map((f) => win(f.path)),
          'user32.lib',
          'ole32.lib',
          'runtimeobject.lib',
          'WindowsApp.lib',
        ],
        toolEnv);

    // ── 6. share_plus / connectivity_plus (shell & COM heavy) ──
    Future<void> buildSimplePlugin({
      required String packageName,
      required String dllName,
      required List<String> sourceDirs,
      required List<String> includeDirs,
      required List<String> exports,
      required List<String> libs,
      List<String> extraDefines = const [],
    }) async {
      final root =
          ctx.project.plugins.firstWhere((e) => e.name == packageName).rootPath;
      final defPath = p.join(outRoot, '$dllName.def');
      await File(defPath).writeAsString('LIBRARY $dllName\nEXPORTS\n'
          '${exports.map((e) => '  $e').join('\n')}\n');
      final incs = [
        for (final d in includeDirs) '/I${win(d)}',
        '/I${win(wrapperInc)}',
        '/I${win(embedderInc)}',
      ];
      final defines = [
        '/DFLUTTER_PLUGIN_IMPL',
        '/DWIN32',
        '/DUNICODE',
        '/D_UNICODE',
        '/DNOMINMAX',
        ...extraDefines,
      ];
      final objs = <File>[
        for (final d in sourceDirs)
          for (final f in _sources(p.join(root, d)))
            await _compile(cl.path, f, objDir, toolEnv, [...defines, ...incs]),
      ];
      final outDir = p.join(pluginsOut, dllName);
      await Directory(outDir).create(recursive: true);
      await _run(
          link.path,
          [
            '/DLL',
            '/NOLOGO',
            '/OUT:${win(p.join(outDir, '$dllName.dll'))}',
            '/DEF:${win(defPath)}',
            ...wrapperObjs.map((f) => win(f.path)),
            ...objs.map((f) => win(f.path)),
            win(ctx.artifacts.flutterWindowsImportLib),
            ...libs,
          ],
          toolEnv);
      final importLib = p.join(importDir, '${dllName}_import.lib');
      await _dlltool(defPath, '$dllName.dll', importLib);
    }

    await buildSimplePlugin(
      packageName: 'share_plus',
      dllName: 'share_plus_plugin',
      sourceDirs: ['windows'],
      includeDirs: [
        p.join(
            ctx.project.plugins
                .firstWhere((e) => e.name == 'share_plus')
                .rootPath,
            'windows'),
      ],
      exports: ['SharePlusWindowsPluginCApiRegisterWithRegistrar'],
      libs: ['user32.lib', 'ole32.lib', 'uuid.lib', 'shell32.lib'],
    );
    // share_plus bundles its DLL as share_plus_plugin.dll; the assemble scan
    // picks it up from cmake_build/plugins/share_plus_plugin/.

    await buildSimplePlugin(
      packageName: 'connectivity_plus',
      dllName: 'connectivity_plus_plugin',
      sourceDirs: ['windows'],
      includeDirs: [
        p.join(
            ctx.project.plugins
                .firstWhere((e) => e.name == 'connectivity_plus')
                .rootPath,
            'windows',
            'include'),
        p.join(
            ctx.project.plugins
                .firstWhere((e) => e.name == 'connectivity_plus')
                .rootPath,
            'windows'),
      ],
      exports: ['ConnectivityPlusWindowsPluginRegisterWithRegistrar'],
      libs: ['user32.lib', 'ole32.lib', 'uuid.lib', 'iphlpapi.lib'],
    );

    // ── 7. flutter_secure_storage_windows_plugin.dll (uses real ATL) ──
    final fss = ctx.project.plugins
        .firstWhere((e) => e.name == 'flutter_secure_storage_windows')
        .rootPath;
    final storagePrefix =
        Platform.environment['STORAGE_PREFIX'] ?? ctx.project.appName;
    final fssDef = p.join(outRoot, 'flutter_secure_storage_windows_plugin.def');
    await File(fssDef).writeAsString('''
LIBRARY flutter_secure_storage_windows_plugin
EXPORTS
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar
''');
    final fssInc = [
      '/I${win(p.join(fss, "windows"))}',
      '/I${win(p.join(fss, 'windows', 'include'))}',
      '/I${win(wrapperInc)}',
      '/I${win(embedderInc)}',
    ];
    const fssDefines = [
      '/DFLUTTER_PLUGIN_IMPL',
      '/DWIN32',
      '/DUNICODE',
      '/D_UNICODE',
      '/DNOMINMAX',
    ];
    final fssObjs = <File>[
      for (final f in _sources(p.join(fss, 'windows')))
        await _compile(cl.path, f, objDir, toolEnv, [
          ...fssDefines,
          ...fssInc,
          '/DSECURE_STORAGE_KEY_PREFIX="$storagePrefix'
              '_VGhpcyBpcyB0aGUgcHJlZml4IGZv_"',
        ]),
    ];

    final fssOutDir =
        p.join(pluginsOut, 'flutter_secure_storage_windows_plugin');
    await Directory(fssOutDir).create(recursive: true);
    await _run(
        link.path,
        [
          '/DLL',
          '/NOLOGO',
          '/OUT:${win(p.join(fssOutDir, 'flutter_secure_storage_windows_plugin.dll'))}',
          '/DEF:${win(fssDef)}',
          ...wrapperObjs.map((f) => win(f.path)),
          ...fssObjs.map((f) => win(f.path)),
          win(ctx.artifacts.flutterWindowsImportLib),
          'user32.lib',
          'ole32.lib',
          'uuid.lib',
          'advapi32.lib',
          'crypt32.lib',
        ],
        toolEnv);

    final fssImportLib =
        p.join(importDir, 'flutter_secure_storage_windows_plugin_import.lib');
    await _dlltool(
        fssDef, 'flutter_secure_storage_windows_plugin.dll', fssImportLib);

    // ── 8. audioplayers_windows_plugin.dll (Media Foundation + WIL + WinRT) ──
    final homeDir = Platform.environment['HOME'] ?? '.';
    final nugetPreseed = Directory(
        Platform.environment['FLUTTER_BUILD_NUGET_PRESEED'] ??
            p.join(homeDir, '.flutter_build', 'nuget'));
    String? wilInc;
    if (nugetPreseed.existsSync()) {
      for (final d in nugetPreseed.listSync()) {
        if (p
            .basename(d.path)
            .startsWith('Microsoft.Windows.ImplementationLibrary')) {
          final cand = p.join(d.path, 'include');
          if (Directory(cand).existsSync()) wilInc = cand;
        }
      }
    }
    final audioRoot = ctx.project.plugins
        .firstWhere((e) => e.name == 'audioplayers_windows')
        .rootPath;
    await buildSimplePlugin(
      packageName: 'audioplayers_windows',
      dllName: 'audioplayers_windows_plugin',
      sourceDirs: ['windows'],
      includeDirs: [
        p.join(audioRoot, 'windows'),
        p.join(audioRoot, 'windows', 'include'),
        if (wilInc != null) wilInc,
        if ((Platform.environment['CPPWINRT_INCLUDE_DIR'] ?? '').isNotEmpty)
          Platform.environment['CPPWINRT_INCLUDE_DIR']!,
        wrapperInc,
        embedderInc,
      ],
      exports: ['AudioplayersWindowsPluginRegisterWithRegistrar'],
      libs: [
        'user32.lib',
        'ole32.lib',
        'mfplat.lib',
        'mfuuid.lib',
        'windowsapp.lib',
        'shlwapi.lib'
      ],
      extraDefines: ['/std:c++20'],
    );

    log.info('Sidecar concluído: flutter_webrtc_plugin.dll + '
        'livekit_client_plugin.dll (MSVC real sob Wine).');
    await sidecarStamp.writeAsString(expectedSidecarStamp);
  }

  // ─── helpers ───

  /// Ensures a PRIVATE copy of the Windows libwebrtc binaries under
  /// `<outRoot>/libwebrtc_win/` and returns that root.
  ///
  /// Why private: the plugin's own CMake keeps per-platform binaries inside
  /// the pub-cache package (`third_party/libwebrtc/lib`), where Windows and
  /// Linux builds overwrite each other (`.dll` vs `.so`). The sidecar must
  /// never touch pub-cache — otherwise cross-building for Windows deletes
  /// `libwebrtc.so` out from under native Linux builds. The asset URL comes
  /// from the plugin's authoritative `libwebrtc_version.ini`; the zip is
  /// cached in our own download dir, never in pub-cache.
  Future<String> _ensurePrivateWebrtcWin(
      String webrtcRoot, String outRoot) async {
    final winRoot = p.join(outRoot, 'libwebrtc_win');
    final marker = File(p.join(winRoot, 'lib', 'libwebrtc.dll.lib'));
    if (marker.existsSync()) return winRoot;

    log.info('Preparando libwebrtc win-x64 privado (não toca no pub-cache)…');
    String? ver;
    String? urlBase;
    final iniPath = p.join(webrtcRoot, 'third_party', 'libwebrtc_version.ini');
    for (final raw in File(iniPath).readAsStringSync().split('\n')) {
      final l = raw.trim();
      if (l.isEmpty ||
          l.startsWith('#') ||
          l.startsWith('[') ||
          !l.contains('=')) {
        continue;
      }
      final i = l.indexOf('=');
      final k = l.substring(0, i).trim();
      final v = l.substring(i + 1).trim();
      if (k == 'binary_version') ver = v;
      if (k == 'download_url') urlBase = v;
    }
    if (ver == null || urlBase == null || ver.isEmpty || urlBase.isEmpty) {
      throw ArtifactException(
        'libwebrtc_version.ini inválido',
        hint: iniPath,
      );
    }
    const asset = 'libwebrtc-win-x64-release';
    final dlDir = Directory(p.join(outRoot, 'downloads'));
    dlDir.createSync(recursive: true);
    final zip = p.join(dlDir.path, '$asset.zip');
    if (!File(zip).existsSync()) {
      await runner.run('curl', ['-fL', '-o', zip, '$urlBase/$ver/$asset.zip'],
          stream: true, tag: 'curl');
    }
    final staging = Directory(p.join(outRoot, '.libwebrtc_extract'));
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    await runner.run('bsdtar', ['-xf', zip, '-C', staging.path]);

    // Normalize layout: promote a single top-level dir into winRoot/,
    // mirroring _libwebrtc_extract_and_normalize in the plugin's CMake.
    final target = Directory(winRoot);
    if (target.existsSync()) target.deleteSync(recursive: true);
    final entries = staging.listSync();
    if (entries.length == 1 && Directory(entries.single.path).existsSync()) {
      await entries.single.rename(target.path);
    } else {
      target.createSync(recursive: true);
      for (final e in entries) {
        await e.rename(p.join(target.path, p.basename(e.path)));
      }
    }
    staging.deleteSync(recursive: true);
    if (!marker.existsSync()) {
      throw ArtifactException(
        'libwebrtc.dll.lib não encontrado após extração',
        hint: 'Verifique o conteúdo de $asset.zip',
      );
    }
    return winRoot;
  }

  /// Compile one translation unit with wine-wrapped cl.exe.
  Future<File> _compile(String cl, File src, String objDir,
      Map<String, String> env, List<String> extra) async {
    final flat = src.path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final obj = p.join(objDir, '$flat.obj');
    String w(String posixPath) =>
        'Z:\\${posixPath.replaceAll('/', '\\').replaceFirst('\\', '')}';

    final explicitStandard = extra.any((arg) => arg.startsWith('/std:'));
    await runner.run(
        cl,
        [
          '/nologo',
          '/c',
          if (!explicitStandard) '/std:c++17',
          '/EHsc',
          '/O2',
          '/W1',
          '/Zc:__cplusplus',
          '/utf-8',
          ...extra,
          '/Fo${w(obj)}',
          w(src.path),
        ],
        environment: env,
        stream: true,
        tag: 'cl');
    return File(obj);
  }

  Future<void> _run(
      String exe, List<String> args, Map<String, String> env) async {
    await runner.run(
      exe,
      args,
      environment: env,
      stream: true,
      tag: p.basename(exe),
    );
  }

  Future<void> _dlltool(String def, String dllName, String outLib) async {
    await runner.run('llvm-dlltool', [
      '-m',
      'i386:x86-64',
      '-d',
      def,
      '-D',
      dllName,
      '-l',
      outLib,
    ]);
  }

  List<File> _sources(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.extension(f.path) == '.cc' ||
            p.extension(f.path) == '.cpp' ||
            p.extension(f.path) == '.c')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  String _latest(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) {
      throw ArtifactException(
        'Diretório ausente: $dir',
        hint: 'Use um instalador msvc-wine completo (--dest ~/.msvc2).',
      );
    }
    final versions = d
        .listSync()
        .whereType<Directory>()
        .map((e) => p.basename(e.path))
        .toList()
      ..sort();
    return versions.last;
  }
}
