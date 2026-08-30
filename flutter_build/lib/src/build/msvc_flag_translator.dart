//
//
//
//

import 'dart:io';

import 'package:path/path.dart' as p;

import '../logger.dart';

class MsvcFlagTranslator {
  const MsvcFlagTranslator({Logger? logger}) : _logger = logger;

  final Logger? _logger;

  Logger get _log => _logger ?? Logger.instance;

  ///
  Future<void> transformTree(String rootPath) async {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path) != 'CMakeLists.txt') continue;

      final original = entity.readAsStringSync();
      final warnings = <String>[];
      final translated = transformContent(
        original,
        warnings: warnings,
        sourcePath: entity.path,
      );
      if (translated != original) {
        entity.writeAsStringSync(translated);
        _log.debug(
            'MSVC translation: updated ${p.relative(entity.path, from: rootPath)}');
      }
      for (final w in warnings) {
        _log.warn('MSVC translation: $w');
      }
    }
  }

  ///
  ///
  String transformContent(
    String content, {
    List<String>? warnings,
    String? sourcePath,
  }) {
    var result = content;
    result = _neutralizeHasExceptions(result);
    result = _transformApplyStandardSettings(result);
    result =
        _translateFlags(result, warnings: warnings, sourcePath: sourcePath);
    result = _translateLibRefs(result);
    return result;
  }

  static const String _guardBegin =
      '# >>> flutter_build: APPLY_STANDARD_SETTINGS (no-translate)';
  static const String _guardEnd = '# <<< flutter_build';

  static const Map<String, String> _flagMap = {
    '/EHsc': '',
    // MSVC legacy coroutines switch. Clang enables standard coroutines with
    // C++20 (cxx_std_20), so drop it entirely on the MinGW branch.
    '/await': '',
    '/EHa': '',
    '/EHs': '',
    '/GR-': '-fno-rtti',
    '/GR': '-frtti',
    '/GS-': '-fno-stack-protector',
    '/std:c++20': '-std=c++20',
    '/std:c++17': '-std=c++17',
    '/std:c++14': '-std=c++14',
    '/std:c11': '-std=c11',
    '/W0': '-w',
    '/W1': '-Wall',
    '/W2': '-Wall',
    '/W3': '-Wall',
    '/W4': '-Wall -Wextra',
    '/WX': '-Werror',
    '/permissive-': '',
    '/Zc:__cplusplus': '',
    '/Zc:preprocessor': '',
    '/MP': '',
    '/utf-8': '-finput-charset=UTF-8 -fexec-charset=UTF-8',
  };

  static final RegExp _ignorableToken = RegExp(
    r'^/(?:D|I|Fo|Fd|Fp|Tp|Tc|wd\d+)',
    caseSensitive: false,
  );

  bool _looksLikeFlagsLine(String line) {
    return line.contains('compile_options') ||
        line.contains('CMAKE_CXX_FLAGS') ||
        line.contains('CMAKE_C_FLAGS') ||
        line.contains('add_compile_options') ||
        line.contains('add_definitions');
  }

  RegExp _boundaryRegExp(String flag) {
    return RegExp(
      r'(?<![A-Za-z0-9+/])' + RegExp.escape(flag) + r'(?![A-Za-z0-9+/-])',
    );
  }

  String _translateFlags(
    String content, {
    List<String>? warnings,
    String? sourcePath,
  }) {
    var inGuard = false;
    return content.split('\n').map((line) {
      if (line.contains(_guardBegin)) {
        inGuard = true;
        return line;
      }
      if (line.contains(_guardEnd)) {
        inGuard = false;
        return line;
      }
      if (inGuard) return line;
      if (!_looksLikeFlagsLine(line)) return line;

      var out = line;
      _flagMap.forEach((msvc, gcc) {
        out = out.replaceAll(_boundaryRegExp(msvc), gcc);
      });

      if (warnings != null) {
        final leftover = _detectUnknownFlags(out);
        if (leftover.isNotEmpty) {
          final where = sourcePath == null ? '' : '（$sourcePath）';
          warnings
              .add('Unknown MSVC-style flags$where: ${leftover.join(', ')}');
        }
      }
      return out;
    }).join('\n');
  }

  List<String> _detectUnknownFlags(String line) {
    final matches =
        RegExp(r'(?<![A-Za-z0-9])/[A-Za-z][A-Za-z0-9:_"+.-]*').allMatches(line);
    final result = <String>[];
    for (final m in matches) {
      final tok = m.group(0)!;
      final nextIsSlash = m.end < line.length && line[m.end] == '/';
      if (nextIsSlash) continue;
      if (_ignorableToken.hasMatch(tok)) continue;
      result.add(tok);
    }
    return result;
  }

  String _translateLibRefs(String content) {
    return content.replaceAllMapped(
      RegExp(r'"([A-Za-z0-9_]+)\.lib"'),
      (m) => '"${m.group(1)}"',
    );
  }

  ///
  String _neutralizeHasExceptions(String content) {
    return content.replaceAll(
      '"_HAS_EXCEPTIONS=0"',
      r'"$<$<CXX_COMPILER_ID:MSVC>:_HAS_EXCEPTIONS=0>"',
    );
  }

  ///
  String _transformApplyStandardSettings(String content) {
    final re = RegExp(
      r'function\s*\(\s*APPLY_STANDARD_SETTINGS\s+(\w+)[^)]*\)'
      r'[\s\S]*?endfunction\s*\([^)]*\)',
      caseSensitive: false,
    );
    return content.replaceAllMapped(re, (m) {
      final param = m.group(1) ?? 'TARGET';
      final ref = '\${$param}';
      return '$_guardBegin\n'
          '# Rewritten by flutter_build: preserve the MSVC branch for native Windows builds.\n'
          '# MinGW/Clang uses equivalent flags in the alternate branch.\n'
          'function(APPLY_STANDARD_SETTINGS $param)\n'
          '  target_compile_features($ref PUBLIC cxx_std_17)\n'
          '  if(MSVC)\n'
          '    target_compile_options($ref PRIVATE /W4 /WX /wd"4100")\n'
          '    target_compile_options($ref PRIVATE /EHsc)\n'
          '    target_compile_definitions($ref PRIVATE "_HAS_EXCEPTIONS=0")\n'
          '  else()\n'
          '    target_compile_options($ref PRIVATE -Wall -Werror)\n'
          '  endif()\n'
          '  target_compile_definitions($ref PRIVATE "\$<\$<CONFIG:Debug>:_DEBUG>")\n'
          'endfunction()\n'
          '$_guardEnd';
    });
  }
}
