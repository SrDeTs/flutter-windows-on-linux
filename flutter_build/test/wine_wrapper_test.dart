//

import 'dart:io';

import 'package:flutter_build/src/build/wine_wrapper.dart';
import 'package:flutter_build/src/toolchain.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('wine_wrapper_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  Toolchain fakeToolchain({String wine = '/usr/bin/wine64'}) => Toolchain(
        llvmMingwRoot: '/opt/llvm-mingw',
        targetTriple: 'x86_64-w64-mingw32',
        wineExecutable: wine,
        cmakeExecutable: '/usr/bin/cmake',
        ninjaExecutable: '/usr/bin/ninja',
      );

  group('group_case_1484', () {
    test('test_case_1485', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      final content = File(wrapper.scriptPath).readAsStringSync();
      expect(content, startsWith('#!/usr/bin/env bash'));
    });

    test('test_case_1495', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(wine: '/custom/wine64'),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      final content = File(wrapper.scriptPath).readAsStringSync();
      expect(content, contains('/custom/wine64'));
    });

    test('test_case_1505', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      final content = File(wrapper.scriptPath).readAsStringSync();
      expect(content, contains(p.join(tmpDir.path, '.wineprefix')));
    });

    test('test_case_1515', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      final stat = FileStat.statSync(wrapper.scriptPath);
      expect(stat.mode & 0x40, isNonZero);
    });

    test('test_case_1525', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      await wrapper.materialize();
      final content = File(wrapper.scriptPath).readAsStringSync();
      expect(content, contains('exec'));
    });

    test('test_case_1536', () async {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      await wrapper.materialize();
      final content = File(wrapper.scriptPath).readAsStringSync();
      expect(content, contains('exec'));
    });
  });

  group('WineWrapper.environment()', () {
    test('test_case_1548', () {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      final env = wrapper.environment();
      expect(env['WINEDEBUG'], '-all');
    });

    test('test_case_1557', () {
      final wrapper = WineWrapper(
        toolchain: fakeToolchain(),
        buildRoot: tmpDir.path,
      );
      final env = wrapper.environment();
      expect(env['WINEPREFIX'], contains(tmpDir.path));
    });
  });
}
