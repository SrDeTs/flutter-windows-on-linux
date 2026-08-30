//

import 'package:flutter_build/src/build/host_env.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizedCrossBuildEnv', () {
    test('test_case_359', () {
      final base = {
        'CXXFLAGS': '-B/snap/flutter/current/usr/lib -lepoxy',
        'LDFLAGS': '-L/snap/flutter/current/usr/lib -lfontconfig',
        'CFLAGS': '-B/snap/...',
        'CPPFLAGS': '-I/snap/...',
        'LIBRARY_PATH': '/snap/flutter/current/usr/lib',
        'PKG_CONFIG_PATH': '/snap/flutter/current/usr/lib/pkgconfig',
        'PATH': '/usr/bin:/bin',
        'HOME': '/home/user',
      };
      final result = sanitizedCrossBuildEnv(base);

      for (final key in kHostBuildFlagVars) {
        expect(result.containsKey(key), isFalse, reason: 'expected condition');
      }
      expect(result['PATH'], '/usr/bin:/bin');
      expect(result['HOME'], '/home/user');
    });

    test('test_case_379', () {
      final base = {
        'LD_LIBRARY_PATH': '/snap/flutter/current/usr/lib',
        'CXXFLAGS': '-lepoxy',
      };
      final result = sanitizedCrossBuildEnv(base);
      expect(result['LD_LIBRARY_PATH'], '/snap/flutter/current/usr/lib');
      expect(result.containsKey('CXXFLAGS'), isFalse);
    });

    test('test_case_389', () {
      final base = {'CXXFLAGS': '-lepoxy', 'WINEPREFIX': '/old'};
      final result = sanitizedCrossBuildEnv(
        base,
        overrides: {'WINEPREFIX': '/new', 'WINEDEBUG': '-all'},
      );
      expect(result['WINEPREFIX'], '/new');
      expect(result['WINEDEBUG'], '-all');
      expect(result.containsKey('CXXFLAGS'), isFalse);
    });

    test('test_case_400', () {
      final base = {'CXXFLAGS': '-lepoxy', 'PATH': '/bin'};
      sanitizedCrossBuildEnv(base, overrides: {'X': '1'});
      expect(base, {'CXXFLAGS': '-lepoxy', 'PATH': '/bin'});
    });
  });
}
