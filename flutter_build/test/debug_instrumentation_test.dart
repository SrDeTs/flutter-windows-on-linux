import 'package:flutter_build/src/build/debug_instrumentation.dart';
import 'package:test/test.dart';

const _sampleMain = '''
#include <flutter/dart_project.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(...) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  FlutterWindow window(project);
  if (!window.Create(L"hello", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  return EXIT_SUCCESS;
}
''';

void main() {
  group('instrumentRunnerMain', () {
    test('test_case_315', () {
      final out = instrumentRunnerMain(_sampleMain);
      expect(out, contains('#include <stdio.h>'));
      expect(out, contains('#include <flutter_windows.h>'));
    });

    test('test_case_321', () {
      final out = instrumentRunnerMain(_sampleMain);
      expect(out, contains('AttachConsole(ATTACH_PARENT_PROCESS)'));
      expect(out, contains('AllocConsole()'));
      expect(out, contains(r'freopen_s(&fb_console, "CONOUT$", "w", stdout)'));
      expect(out, contains('FlutterDesktopResyncOutputStreams()'));
      expect(out, isNot(contains('flutter_build_debug.log')));
    });

    test('test_case_330', () {
      final out = instrumentRunnerMain(_sampleMain);
      expect(out, contains('failed to start'));
      expect(out.indexOf('failed to start'),
          lessThan(out.indexOf('return EXIT_FAILURE;')));
      expect(out, contains('return EXIT_SUCCESS;'));
    });

    test('test_case_338', () {
      final once = instrumentRunnerMain(_sampleMain);
      final twice = instrumentRunnerMain(once);
      expect(twice, once);
    });

    test('test_case_344', () {
      const noMarkers = 'int main() { return 0; }\n';
      final out = instrumentRunnerMain(noMarkers);
      expect(out, contains('int main() { return 0; }'));
      expect(instrumentRunnerMain(out), out);
    });
  });
}
