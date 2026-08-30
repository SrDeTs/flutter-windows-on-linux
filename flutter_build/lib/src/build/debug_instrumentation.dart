//
//
//

const String _sentinel = '// flutter_build debug instrumentation';

const String _utilsInclude = '#include "utils.h"';

const String _consoleBlock =
    '  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {\n'
    '    CreateAndAttachConsole();\n'
    '  }';

const String _failReturn = 'return EXIT_FAILURE;';

const String _successReturn = 'return EXIT_SUCCESS;';

String instrumentRunnerMain(String source) {
  if (source.contains(_sentinel)) return source;
  var out = source;

  if (out.contains(_utilsInclude)) {
    out = out.replaceFirst(
      _utilsInclude,
      '$_utilsInclude\n'
      '#include <stdio.h>          // flutter_build\n'
      '#include <flutter_windows.h> // flutter_build',
    );
  }

  if (out.contains(_consoleBlock)) {
    out = out.replaceFirst(
      _consoleBlock,
      '  // flutter_build: surface engine logs on the launching console\n'
      '  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {\n'
      '    ::AllocConsole();\n'
      '  }\n'
      '  {\n'
      '    FILE* fb_console = nullptr;\n'
      '    freopen_s(&fb_console, "CONOUT\$", "w", stdout);\n'
      '    freopen_s(&fb_console, "CONOUT\$", "w", stderr);\n'
      '    FlutterDesktopResyncOutputStreams();\n'
      '    fprintf(stderr, "[flutter_build] wWinMain reached; init engine...\\n");\n'
      '    fflush(stderr);\n'
      '  }',
    );
  }

  if (out.contains(_failReturn)) {
    out = out.replaceFirst(
      _failReturn,
      'fprintf(stderr, "[flutter_build] engine/window failed to start "\n'
      '        "(likely empty data/flutter_assets or missing data/app.so)\\n");\n'
      '    fflush(stderr);\n'
      '    ::FreeConsole();\n'
      '    $_failReturn',
    );
  }

  if (out.contains(_successReturn)) {
    out = out.replaceFirst(
      _successReturn,
      'fflush(stdout);\n'
      '    fflush(stderr);\n'
      '    ::FreeConsole();\n'
      '    $_successReturn',
    );
  }

  return '$_sentinel\n$out';
}
