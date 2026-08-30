import 'dart:io';

import 'package:flutter_build/src/build/build_context.dart';
import 'package:flutter_build/src/build/msvc_flag_translator.dart';
import 'package:flutter_build/src/build/pipeline.dart';
import 'package:flutter_build/src/build/plugin_source_patcher.dart';
import 'package:flutter_build/src/engine_artifacts.dart';
import 'package:flutter_build/src/project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/stubs.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flutter_build_symlink_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('test_case_750', () async {
    final pluginRoot = Directory(p.join(tempDir.path, 'libcimbar'))
      ..createSync(recursive: true);
    File(p.join(pluginRoot.path, 'windows', 'CMakeLists.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('add_library(libcimbar_plugin SHARED plugin.cpp)\n');
    File(
      p.join(
        pluginRoot.path,
        'example',
        'build',
        'win_cross',
        'release',
        'windows_src',
        'loop.txt',
      ),
    )
      ..createSync(recursive: true)
      ..writeAsStringSync('should stay outside staged tree\n');

    final source = Directory(p.join(tempDir.path, 'windows'))..createSync();
    File(p.join(source.path, 'CMakeLists.txt'))
        .writeAsStringSync('cmake_minimum_required(VERSION 3.14)\n');
    final symlinkDir = Directory(
        p.join(source.path, 'flutter', 'ephemeral', '.plugin_symlinks'))
      ..createSync(recursive: true);
    final relativePluginPath =
        p.relative(pluginRoot.path, from: symlinkDir.path);
    Link(p.join(symlinkDir.path, 'libcimbar')).createSync(relativePluginPath);

    final dest = p.join(tempDir.path, 'windows_src');
    await copyTreePreservingLinks(source.path, dest);

    final copiedLink =
        p.join(dest, 'flutter', 'ephemeral', '.plugin_symlinks', 'libcimbar');
    expect(
      FileSystemEntity.typeSync(copiedLink, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(Link(copiedLink).targetSync(), pluginRoot.path);
    expect(Directory(p.join(copiedLink, 'windows')).existsSync(), isTrue);

    final stagedEntries = Directory(dest)
        .listSync(recursive: true, followLinks: false)
        .map((e) => p.relative(e.path, from: dest))
        .toSet();
    expect(stagedEntries,
        contains('flutter/ephemeral/.plugin_symlinks/libcimbar'));
    expect(
      stagedEntries
          .any((path) => path.contains('.plugin_symlinks/libcimbar/example')),
      isFalse,
    );
  });

  test('test_case_805', () async {
    final pluginRoot = Directory(p.join(tempDir.path, 'plugin_root'))
      ..createSync(recursive: true);
    final linkedCmake =
        File(p.join(pluginRoot.path, 'windows', 'CMakeLists.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            'target_compile_options(plugin PRIVATE /EHsc /W3)\n',
          );

    final stagedRoot = Directory(p.join(tempDir.path, 'windows_src'))
      ..createSync(recursive: true);
    final localCmake = File(p.join(stagedRoot.path, 'CMakeLists.txt'))
      ..writeAsStringSync(
        'target_compile_options(app PRIVATE /EHsc /W3)\n',
      );
    final symlinkDir = Directory(
      p.join(stagedRoot.path, 'flutter', 'ephemeral', '.plugin_symlinks'),
    )..createSync(recursive: true);
    final relativePluginPath =
        p.relative(pluginRoot.path, from: symlinkDir.path);
    Link(p.join(symlinkDir.path, 'plugin')).createSync(relativePluginPath);

    await const MsvcFlagTranslator().transformTree(stagedRoot.path);

    expect(localCmake.readAsStringSync(), isNot(contains('/EHsc')));
    expect(localCmake.readAsStringSync(), contains('-Wall'));
    expect(linkedCmake.readAsStringSync(), contains('/EHsc /W3'));
  });

  test('test_case_835', () async {
    final pluginRoot = Directory(p.join(tempDir.path, 'plugin_root'))
      ..createSync(recursive: true);
    File(p.join(pluginRoot.path, 'windows', 'CMakeLists.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('add_library(plugin SHARED plugin.cpp)\n');

    final project = stubProject(
      root: p.join(tempDir.path, 'app'),
      appName: 'app',
      plugins: [
        WindowsPluginRef(
          name: 'sample_plugin',
          rootPath: pluginRoot.path,
          pluginClass: 'SamplePlugin',
        ),
      ],
    );
    final ctx = BuildContext(
      env: stubEnv(),
      project: project,
      artifacts: stubArtifacts(),
      toolchain: stubToolchain(),
      mode: WindowsFlavor.release,
      buildRoot: p.join(tempDir.path, 'app', 'build', 'win_cross'),
      dartDefines: const [],
    );

    final ephemeralDir = p.join(tempDir.path, 'staged', 'flutter', 'ephemeral');
    await Directory(p.join(ephemeralDir, '.plugin_symlinks')).create(
      recursive: true,
    );
    Link(p.join(ephemeralDir, '.plugin_symlinks', 'stale'))
        .createSync('/tmp/stale-target');

    await materializePluginSymlinks(ctx, ephemeralDir);

    final pluginLink =
        p.join(ephemeralDir, '.plugin_symlinks', 'sample_plugin');
    expect(
      FileSystemEntity.typeSync(pluginLink, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(Link(pluginLink).targetSync(), pluginRoot.path);
    expect(Directory(p.join(pluginLink, 'windows')).existsSync(), isTrue);
    expect(
      FileSystemEntity.typeSync(
        p.join(ephemeralDir, '.plugin_symlinks', 'stale'),
        followLinks: false,
      ),
      FileSystemEntityType.notFound,
    );
  });

  group('patchHotkeyManagerPluginCpp', () {
    test('test_case_891', () {
      const input = 'args["data"] =\n'
          '    flutter::EncodableMap({{"identifier", identifier}});\n';
      final out = patchHotkeyManagerPluginCpp(input);
      expect(out, contains('flutter::EncodableValue("identifier")'));
      expect(out, contains('flutter::EncodableValue(identifier)'));
      expect(
          out, isNot(contains('EncodableMap({{"identifier", identifier}})')));
    });

    test('test_case_901', () {
      const input = 'flutter::EncodableMap({{"identifier", identifier}})';
      expect(patchHotkeyManagerPluginCpp(patchHotkeyManagerPluginCpp(input)),
          patchHotkeyManagerPluginCpp(input));
    });
  });

  group('record_windows compatibility patches', () {
    test('formats HRESULT with its actual width', () {
      const input =
          'printf("Record: Error when reading sample (0x%X)\\n%s\\n", hrStatus, errorText.c_str());';
      final out = patchRecordWindowsPluginCpp(input);
      expect(out, contains('0x%lX'));
      expect(out, contains('static_cast<unsigned long>(hrStatus)'));
    });

    test('orders recorder initializers like the class declaration', () {
      const input = '''
		: m_nRefCount(1),
		m_critsec(),
		m_pConfig(nullptr),
		m_pSource(NULL),
		m_pReader(NULL),
		m_pWriter(NULL),
		m_pPresentationDescriptor(NULL),
		m_stateEventHandler(stateEventHandler),
		m_recordEventHandler(recordEventHandler),
		m_recordEventHandlerOrigin(recordEventHandler),
		m_recordingPath(std::wstring()),
		m_pMediaType(NULL)
''';
      final out = patchRecordWindowsRecorderCpp(input);
      expect(out.indexOf('m_pSource'), lessThan(out.indexOf('m_pReader')));
      expect(out.indexOf('m_pMediaType'),
          lessThan(out.indexOf('m_recordingPath')));
      expect(out.indexOf('m_recordingPath'),
          lessThan(out.indexOf('m_stateEventHandler')));
      expect(out.indexOf('m_pConfig'),
          greaterThan(out.indexOf('m_recordEventHandlerOrigin')));
    });

    test('orders recorder initializers in CRLF package sources', () {
      const input = '''
		: m_nRefCount(1),
		m_critsec(),
		m_pConfig(nullptr),
		m_pSource(NULL),
		m_pReader(NULL),
		m_pWriter(NULL),
		m_pPresentationDescriptor(NULL),
		m_stateEventHandler(stateEventHandler),
		m_recordEventHandler(recordEventHandler),
		m_recordEventHandlerOrigin(recordEventHandler),
		m_recordingPath(std::wstring()),
		m_pMediaType(NULL)
''';
      final out = patchRecordWindowsRecorderCpp(
        input.replaceAll('\n', '\r\n'),
      );
      expect(out, contains('m_pSource(NULL),\r\n'));
      expect(out.indexOf('m_pConfig'),
          greaterThan(out.indexOf('m_recordEventHandlerOrigin')));
      expect(out, isNot(contains('\r\r\n')));
    });

    test('uses MinGW topology spelling and explicit EncodableValue', () {
      const input = '''
pPart->GetTopologyObject(&topology);
devices.push_back(flutter::EncodableMap({
  {flutter::EncodableValue("id"), flutter::EncodableValue("mic")},
}));
''';
      final out = patchRecordWindowsAudioDeviceCpp(input);
      expect(out, contains('GetTopologyObjects(&topology)'));
      expect(
          out,
          contains(
              'push_back(flutter::EncodableValue(flutter::EncodableMap({'));
      expect(out, contains('})));'));
      expect(patchRecordWindowsAudioDeviceCpp(out), out);
    });
  });
}
