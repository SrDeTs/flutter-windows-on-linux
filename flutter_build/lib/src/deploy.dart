//
//
//

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'io/fs_utils.dart';
import 'logger.dart';
import 'process_runner.dart';

class DeployConfig {
  const DeployConfig({
    required this.host,
    required this.username,
    required this.password,
    required this.autoCopy,
    required this.remoteDir,
    required this.baseDir,
    this.port = 22,
  });

  final String host;

  final String username;

  final String? password;

  final bool autoCopy;

  final String remoteDir;

  final String baseDir;

  final int port;

  static const fileName = 'config.yaml';

  ///
  static DeployConfig? find(String startDir) {
    final local = _findFrom(startDir);
    if (local != null) return local;

    try {
      final scriptDir = p.dirname(Platform.script.toFilePath());
      final tool = _findFrom(scriptDir);
      if (tool != null) return tool;
    } catch (_) {}

    final home = Platform.environment['HOME'];
    if (home != null) {
      final f = File(p.join(home, '.flutter_build', fileName));
      if (f.existsSync()) {
        return parse(f.readAsStringSync(), baseDir: p.dirname(f.path));
      }
    }

    return null;
  }

  static DeployConfig? _findFrom(String dir) {
    var d = Directory(p.normalize(p.absolute(dir)));
    while (true) {
      final f = File(p.join(d.path, fileName));
      if (f.existsSync()) {
        return parse(f.readAsStringSync(), baseDir: d.path);
      }
      final parent = d.parent;
      if (parent.path == d.path) return null;
      d = parent;
    }
  }

  static DeployConfig parse(String yamlText, {required String baseDir}) {
    final doc = loadYaml(yamlText);
    if (doc is! YamlMap) {
      throw ToolException('config.yaml is not a valid YAML map.');
    }
    final host = (doc['host'] ?? doc['ip'])?.toString().trim();
    if (host == null || host.isEmpty) {
      throw ToolException('config.yaml is missing host (or ip).');
    }
    final remoteDir = doc['remote_dir']?.toString().trim();
    if (remoteDir == null || remoteDir.isEmpty) {
      throw ToolException('config.yaml is missing remote_dir.');
    }
    final rawPwd = doc['password']?.toString();
    return DeployConfig(
      host: host,
      username: doc['username']?.toString().trim() ?? 'ubuntu',
      password: (rawPwd != null && rawPwd.isNotEmpty) ? rawPwd : null,
      autoCopy: doc['auto_copy'] == true,
      remoteDir: _toPosix(remoteDir),
      baseDir: p.normalize(p.absolute(baseDir)),
      port: doc['port'] is int ? doc['port'] as int : 22,
    );
  }

  ///
  String remotePathFor(String localPath) {
    final base = remoteDir.endsWith('/')
        ? remoteDir.substring(0, remoteDir.length - 1)
        : remoteDir;
    final name = p.basename(p.normalize(p.absolute(localPath)));
    return name.isEmpty ? base : '$base/$name';
  }

  static String _toPosix(String s) => s.replaceAll('\\', '/');
}

class DeployResult {
  DeployResult({
    required this.remotePath,
    required this.duration,
    required this.bytes,
  });

  final String remotePath;
  final Duration duration;
  final int bytes;
}

class SshDeployer {
  SshDeployer({
    required this.config,
    Logger? logger,
    ProcessRunner? runner,
  })  : _log = logger ?? Logger.instance,
        _runner = runner ?? ProcessRunner(logger: logger ?? Logger.instance);

  final DeployConfig config;
  final Logger _log;
  final ProcessRunner _runner;

  Future<DeployResult> deployDir(String localDir) async {
    final dir = Directory(localDir);
    if (!dir.existsSync()) {
      throw ArtifactException('Directory to copy does not exist: $localDir');
    }
    final remotePath = config.remotePathFor(localDir);
    final remoteParent = _posixDirname(remotePath);
    final bytes = dirSize(dir);

    if (config.password != null) {
      await _requireTool(
        'sshpass',
        'Password authentication requires sshpass: sudo apt install sshpass',
      );
    }
    await _requireTool(
        'scp', 'scp is required: sudo apt install openssh-client');

    _log.step(
        'Deploy · copying to ${config.username}@${config.host} → $remotePath');
    _log.info('  Size: ${_fmtBytes(bytes)}');

    final sw = Stopwatch()..start();
    _log.info('  Ensuring remote directory exists: $remoteParent');
    await _ssh([
      'powershell',
      '-NoProfile',
      '-Command',
      "New-Item -ItemType Directory -Force -Path '$remoteParent'",
    ]);
    await _scp(localDir, remoteParent);
    sw.stop();

    final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
    _log.success('Deploy complete: $remotePath in ${secs}s '
        '(${_fmtBytes(bytes)}, ${_fmtRate(bytes, sw.elapsed)})');
    return DeployResult(
        remotePath: remotePath, duration: sw.elapsed, bytes: bytes);
  }

  Future<void> _ssh(List<String> remoteCmd) async {
    final args = <String>[
      ..._commonSshOpts,
      '-p',
      '${config.port}',
      '${config.username}@${config.host}',
      ...remoteCmd,
    ];
    await _runWithAuth('ssh', args);
  }

  Future<void> _scp(String localDir, String remoteParent) async {
    final target = '${config.username}@${config.host}:$remoteParent';
    final args = <String>[
      '-r',
      ..._commonSshOpts,
      '-P',
      '${config.port}',
      localDir,
      target,
    ];
    await _runWithAuth('scp', args);
  }

  static const List<String> _commonSshOpts = [
    '-o',
    'StrictHostKeyChecking=no',
    '-o',
    'UserKnownHostsFile=/dev/null',
    '-o',
    'LogLevel=ERROR',
  ];

  Future<void> _runWithAuth(String tool, List<String> args) async {
    if (config.password != null) {
      await _runner.run(
        'sshpass',
        ['-e', tool, ...args],
        environment: {'SSHPASS': config.password!},
        stream: true,
        tag: 'deploy',
      );
    } else {
      await _runner.run(tool, args, stream: true, tag: 'deploy');
    }
  }

  Future<void> _requireTool(String tool, String hint) async {
    final path = await _runner.which(tool);
    if (path == null) throw MissingToolException(tool, hint: hint);
  }

  static String _posixDirname(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? path : path.substring(0, i);
  }

  String _fmtBytes(int b) {
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(1)} KB';
    return '$b B';
  }

  String _fmtRate(int bytes, Duration d) {
    final s = d.inMilliseconds / 1000.0;
    if (s <= 0) return '—';
    return '${((bytes / (1 << 20)) / s).toStringAsFixed(1)} MB/s';
  }
}
