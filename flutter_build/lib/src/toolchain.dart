//
//
//   final tc = await ToolchainProvisioner(paths: cachePaths, runner: runner)
//       .provision(allowDownload: true);
//   print(tc.clang);  // /home/you/.flutter_build/toolchains/llvm-mingw-.../bin/x86_64-w64-mingw32-clang
//
//   - https://clang.llvm.org/docs/CrossCompilation.html

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'cache_paths.dart';
import 'exceptions.dart';
import 'logger.dart';
import 'process_runner.dart';

/// Metadata for one release of the LLVM-MinGW toolchain.
class LlvmMingwRelease {
  const LlvmMingwRelease({
    required this.version,
    required this.crt,
    required this.linuxDistroTag,
    this.sha256,
  });

  /// e.g. `20240619`
  final String version;

  /// `ucrt` (recommended, modern CRT) or `msvcrt` (legacy).
  final String crt;

  /// The Ubuntu tag of this release's Linux x86_64 build.
  ///
  ///
  final String linuxDistroTag;

  /// Optional expected sha256 of the tarball (hex). If null, integrity is
  /// not verified — enable in production builds.
  final String? sha256;

  String get archiveName =>
      'llvm-mingw-$version-$crt-$linuxDistroTag-x86_64.tar.xz';

  String downloadUrl() =>
      'https://github.com/mstorsjo/llvm-mingw/releases/download/'
      '$version/$archiveName';

  String get extractedDirName =>
      'llvm-mingw-$version-$crt-$linuxDistroTag-x86_64';

  ///
  static const Map<String, String> _linuxTagByVersion = {
    '20240619': 'ubuntu-20.04',
    '20260616': 'ubuntu-22.04',
  };

  static const String _fallbackLinuxTag = 'ubuntu-20.04';

  static String linuxTagForVersion(String version) =>
      _linuxTagByVersion[version] ?? _fallbackLinuxTag;

  factory LlvmMingwRelease.pinned({
    String version = '20240619',
    String crt = 'ucrt',
    String? sha256,
  }) =>
      LlvmMingwRelease(
        version: version,
        crt: crt,
        linuxDistroTag: linuxTagForVersion(version),
        sha256: sha256,
      );
}

/// Default LLVM-MinGW release we ship against.
///
/// This is intentionally pinned. To bump: update `version` in the factory
/// call below, register its Linux tag in [LlvmMingwRelease._linuxTagByVersion],
/// download the tarball once, compute sha256, and pass it here.
///
final LlvmMingwRelease defaultLlvmMingw = LlvmMingwRelease.pinned(
  version: '20240619',
  crt: 'ucrt',
  // sha256: 'fill-in-once-verified',
);

/// Resolved paths to the tools we drive during a cross-build.
///
enum ToolchainBackend { llvmMingw, systemMingw }

class Toolchain {
  Toolchain({
    this.backend = ToolchainBackend.llvmMingw,
    required this.llvmMingwRoot,
    required this.targetTriple,
    required this.wineExecutable,
    required this.cmakeExecutable,
    required this.ninjaExecutable,
  });

  final ToolchainBackend backend;

  final String llvmMingwRoot;

  /// Cross-compile target triple, e.g. `x86_64-w64-mingw32`.
  final String targetTriple;

  /// Absolute path to `wine` or `wine64`.
  final String wineExecutable;

  /// Absolute path to `cmake`.
  final String cmakeExecutable;

  /// Absolute path to `ninja`.
  final String ninjaExecutable;

  String get clang => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', '$targetTriple-clang')
      : '$targetTriple-gcc';

  String get clangxx => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', '$targetTriple-clang++')
      : '$targetTriple-g++';

  String get windres => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', '$targetTriple-windres')
      : '$targetTriple-windres';

  String get lldLink => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', 'ld.lld')
      : '$targetTriple-ld';

  String get llvmDllTool => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', 'llvm-dlltool')
      : '$targetTriple-dlltool';

  String get llvmRc => p.join(llvmMingwRoot, 'bin', 'llvm-rc');
  String get llvmAr => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', 'llvm-ar')
      : '$targetTriple-ar';
  String get llvmRanlib => backend == ToolchainBackend.llvmMingw
      ? p.join(llvmMingwRoot, 'bin', 'llvm-ranlib')
      : '$targetTriple-ranlib';

  bool get usesLld => backend == ToolchainBackend.llvmMingw;

  String get mingwSysrootInclude =>
      p.join(llvmMingwRoot, targetTriple, 'include');

  Map<String, String> describe() => {
        'Backend': backend == ToolchainBackend.llvmMingw
            ? 'LLVM-MinGW'
            : 'System GCC-MinGW (apt)',
        'Root': llvmMingwRoot,
        'Target': targetTriple,
        'C compiler': clang,
        'C++ compiler': clangxx,
        'cmake': cmakeExecutable,
        'ninja': ninjaExecutable,
        'wine': wineExecutable,
      };
}

///
class ToolchainProvisioner {
  ToolchainProvisioner({
    required this.paths,
    Logger? logger,
    ProcessRunner? runner,
    LlvmMingwRelease? release,
    String targetTriple = 'x86_64-w64-mingw32',
    this.toolchainPathOverride,
  })  : _log = logger ?? Logger.instance,
        _runner = runner ?? ProcessRunner(logger: logger ?? Logger.instance),
        _release = release ?? defaultLlvmMingw,
        _targetTriple = targetTriple;

  final CachePaths paths;
  final Logger _log;
  final ProcessRunner _runner;
  final LlvmMingwRelease _release;
  final String _targetTriple;

  final String? toolchainPathOverride;

  ///
  Future<Toolchain> provision({
    bool allowDownload = true,
    bool allowSystemFallback = true,
  }) async {
    await paths.ensure();

    final wine = await _detectWine();
    final cmake = await _detectRequired('cmake', 'sudo apt install cmake');
    final ninja =
        await _detectRequired('ninja', 'sudo apt install ninja-build');

    final explicitRoot =
        toolchainPathOverride ?? Platform.environment['LLVM_MINGW_ROOT'];
    if (explicitRoot != null && explicitRoot.isNotEmpty) {
      _log.debug('Using the user-specified toolchain: $explicitRoot');
      _validateLlvmMingwDir(explicitRoot);
      return Toolchain(
        backend: ToolchainBackend.llvmMingw,
        llvmMingwRoot: explicitRoot,
        targetTriple: _targetTriple,
        wineExecutable: wine,
        cmakeExecutable: cmake,
        ninjaExecutable: ninja,
      );
    }

    try {
      final llvmRoot = await _ensureLlvmMingw(allowDownload: allowDownload);
      return Toolchain(
        backend: ToolchainBackend.llvmMingw,
        llvmMingwRoot: llvmRoot,
        targetTriple: _targetTriple,
        wineExecutable: wine,
        cmakeExecutable: cmake,
        ninjaExecutable: ninja,
      );
    } on ToolException catch (e) {
      if (!allowSystemFallback) rethrow;
      _log.debug(
          'LLVM-MinGW is unavailable: ${e.message}; trying system GCC-MinGW...');
    }

    return _trySystemMingw(
      wine: wine,
      cmake: cmake,
      ninja: ninja,
    );
  }

  Future<String> _ensureLlvmMingw({required bool allowDownload}) async {
    final destDir = paths.toolchainRoot(_release.extractedDirName);
    final marker = File(p.join(destDir, '.installed'));

    if (marker.existsSync()) {
      _log.debug('LLVM-MinGW cache hit: $destDir');
      return destDir;
    }

    if (!allowDownload) {
      throw ToolException(
        'LLVM-MinGW is not installed at $destDir',
        hint: 'Run `flutter_build precache` first, or set '
            'LLVM_MINGW_ROOT to a pre-existing installation, or '
            '`sudo apt install gcc-mingw-w64-x86-64` as fallback.',
      );
    }

    final mirror = Platform.environment['FLUTTER_BUILD_MIRROR'];
    final downloadUrl = mirror != null && mirror.isNotEmpty
        ? '$mirror/${_release.version}/${_release.archiveName}'
        : _release.downloadUrl();

    _log.step('Downloading LLVM-MinGW ${_release.version}');
    if (mirror != null && mirror.isNotEmpty) {
      _log.info('  Using mirror: $mirror');
    }
    final archivePath = p.join(paths.downloadsDir, _release.archiveName);
    await _download(downloadUrl, archivePath);

    if (_release.sha256 != null) {
      await _verifySha256(archivePath, _release.sha256!);
    }

    _log.step('Extracting ${_release.archiveName}');
    // Use system `tar` — piping through xz is streaming and avoids loading
    // the whole ~250MB tarball into memory.
    await Directory(paths.toolchainsDir).create(recursive: true);
    await _runner.run(
      'tar',
      ['-xJf', archivePath, '-C', paths.toolchainsDir],
      stream: false,
    );

    if (!Directory(destDir).existsSync()) {
      throw ArtifactException(
        'Extraction succeeded but expected directory is missing: $destDir',
      );
    }
    await marker.writeAsString(DateTime.now().toIso8601String());
    _log.success('LLVM-MinGW ${_release.version} ready at $destDir');
    return destDir;
  }

  void _validateLlvmMingwDir(String root) {
    final clang = p.join(root, 'bin', '$_targetTriple-clang');
    if (!File(clang).existsSync()) {
      throw ToolException(
        'LLVM_MINGW_ROOT ($root) does not contain $clang',
        hint: 'Ensure the directory is a valid LLVM-MinGW installation.\n'
            'Expected layout: $root/bin/$_targetTriple-clang',
      );
    }
  }

  ///
  ///   sudo apt install gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64
  Future<Toolchain> _trySystemMingw({
    required String wine,
    required String cmake,
    required String ninja,
  }) async {
    final gccPath = await _runner.which('$_targetTriple-gcc');
    if (gccPath == null) {
      throw ToolException(
        'Neither LLVM-MinGW nor system GCC-MinGW could be found.',
        hint: 'Choose one:\n'
            '  • export LLVM_MINGW_ROOT=/path/to/llvm-mingw  (manually downloaded)\n'
            '  • flutter_build precache  (auto-download from GitHub)\n'
            '  • sudo apt install gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64  (GCC fallback)',
      );
    }

    _log.warn('Using system GCC-MinGW (apt) as fallback. '
        'LLVM-MinGW is recommended for best compatibility.');
    return Toolchain(
      backend: ToolchainBackend.systemMingw,
      llvmMingwRoot: '/usr',
      targetTriple: _targetTriple,
      wineExecutable: wine,
      cmakeExecutable: cmake,
      ninjaExecutable: ninja,
    );
  }

  Future<String> _detectWine() async {
    for (final name in ['wine64', 'wine']) {
      final path = await _runner.which(name);
      if (path != null) return path;
    }
    throw MissingToolException(
      'wine',
      hint: 'Install with: sudo apt install wine64',
    );
  }

  Future<String> _detectRequired(String tool, String installHint) async {
    final path = await _runner.which(tool);
    if (path != null) return path;
    throw MissingToolException(tool, hint: installHint);
  }

  Future<void> _download(String url, String destPath) async {
    _log.debug('GET $url');
    final dest = File(destPath);
    // Skip re-download if the file already exists (and has non-zero size).
    if (dest.existsSync() && dest.lengthSync() > 0) {
      _log.debug('Reusing cached download: $destPath');
      return;
    }
    final req = http.Request('GET', Uri.parse(url));
    final streamed = await req.send();
    if (streamed.statusCode ~/ 100 != 2) {
      throw ArtifactException(
        'HTTP ${streamed.statusCode} downloading $url',
      );
    }
    final tmp = File('$destPath.part');
    final sink = tmp.openWrite();
    var received = 0;
    final total = streamed.contentLength ?? 0;
    var lastReport = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0 && received - lastReport > 4 * 1024 * 1024) {
        final pct = (received * 100 / total).toStringAsFixed(1);
        _log.debug('  … ${(received / (1024 * 1024)).toStringAsFixed(1)} MB / '
            '${(total / (1024 * 1024)).toStringAsFixed(1)} MB ($pct%)');
        lastReport = received;
      }
    }
    await sink.flush();
    await sink.close();
    await tmp.rename(destPath);
  }

  Future<void> _verifySha256(String path, String expectedHex) async {
    final stream = File(path).openRead();
    final digest = await sha256.bind(stream).first;
    final actual = digest.toString();
    if (actual.toLowerCase() != expectedHex.toLowerCase()) {
      throw ArtifactException(
        'SHA-256 mismatch for $path\n  expected: $expectedHex\n  actual:   $actual',
      );
    }
  }
}
