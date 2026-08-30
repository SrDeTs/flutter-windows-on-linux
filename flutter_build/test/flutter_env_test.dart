//

import 'package:flutter_build/src/flutter_env.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _dartExe = '/sdk/bin/cache/dart-sdk/bin/dart';
const _engineDir = '/sdk/bin/cache/artifacts/engine/linux-x64';

FlutterEnv _envWithSnapshot(String snapshot) => FlutterEnv.forTesting(
      sdkRoot: '/sdk',
      flutterVersion: '3.22.0',
      dartSdkVersion: '3.5.0',
      engineCommitHash: 'abc123',
      engineRealm: '',
      storageBaseUrl: 'https://storage.googleapis.com',
      dartExecutable: _dartExe,
      frontendServerSnapshot: snapshot,
      hostEngineDir: _engineDir,
    );

void main() {
  group('group_case_1048', () {
    test('test_case_1049', () {
      final env = _envWithSnapshot(
        p.join(_engineDir, 'frontend_server_aot.dart.snapshot'),
      );
      expect(env.frontendServerIsAot, isTrue);
      expect(env.dartAotRuntimeExecutable,
          '/sdk/bin/cache/dart-sdk/bin/dartaotruntime');
      expect(env.frontendServerRuntime, env.dartAotRuntimeExecutable);
      expect(env.frontendServerRuntime, isNot(env.dartExecutable));
    });

    test('test_case_1060', () {
      final env = _envWithSnapshot(
        p.join(_engineDir, 'frontend_server.dart.snapshot'),
      );
      expect(env.frontendServerIsAot, isFalse);
      expect(env.frontendServerRuntime, env.dartExecutable);
    });

    test('test_case_1068', () {
      final env = _envWithSnapshot(
        p.join(_engineDir, 'frontend_server_aot.dart.snapshot'),
      );
      expect(p.dirname(env.dartAotRuntimeExecutable),
          p.dirname(env.dartExecutable));
    });
  });
}
