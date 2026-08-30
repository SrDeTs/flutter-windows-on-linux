//
//   3. XDG_CACHE_HOME
//   4. $HOME/.flutter_build

import 'dart:io';

import 'package:flutter_build/src/cache_paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('group_case_163', () {
    test('test_case_164', () {
      final paths = CachePaths.resolve(cacheDirOverride: '/override/cache');
      expect(paths.root, '/override/cache');
    });

    test('test_case_169', () {
      final paths = CachePaths.resolve(cacheDirOverride: '/tmp/test_cache');
      expect(paths.toolchainsDir, p.join('/tmp/test_cache', 'toolchains'));
      expect(paths.engineDir, p.join('/tmp/test_cache', 'engine'));
      expect(paths.downloadsDir, p.join('/tmp/test_cache', 'downloads'));
    });

    test('test_case_176', () async {
      final tmp = Directory.systemTemp.createTempSync('cache_test_');
      try {
        final paths = CachePaths.resolve(cacheDirOverride: tmp.path);
        await paths.ensure();
        expect(Directory(paths.toolchainsDir).existsSync(), isTrue);
        expect(Directory(paths.engineDir).existsSync(), isTrue);
        expect(Directory(paths.downloadsDir).existsSync(), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('test_case_189', () {
      final paths = CachePaths.resolve(cacheDirOverride: '/cache');
      expect(
        paths.toolchainRoot('llvm-mingw-20240619'),
        '/cache/toolchains/llvm-mingw-20240619',
      );
    });
  });
}
