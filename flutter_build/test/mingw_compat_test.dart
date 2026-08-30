import 'dart:io';

import 'package:flutter_build/src/build/mingw_compat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('mingw_compat_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('test_case_668', () async {
    final out = p.join(tmp.path, 'compat');
    await materializeMingwCompat(
        outDir: out, mingwLibDir: p.join(tmp.path, 'nolib'));

    for (final entry in kMingwCompatHeaders.entries) {
      final f = File(p.join(out, entry.key));
      expect(f.existsSync(), isTrue, reason: 'expected condition');
      expect(f.readAsStringSync(), entry.value);
    }
  });

  test('test_case_680', () async {
    final out = p.join(tmp.path, 'compat');
    final libDir = p.join(tmp.path, 'nolib');
    await materializeMingwCompat(outDir: out, mingwLibDir: libDir);

    final header = File(p.join(out, 'shobjidl_core.h'));
    final firstMtime = header.lastModifiedSync();
    header.setLastModifiedSync(firstMtime.subtract(const Duration(hours: 1)));
    final marked = header.lastModifiedSync();

    await materializeMingwCompat(outDir: out, mingwLibDir: libDir);
    expect(header.lastModifiedSync(), marked);
  });

  test('test_case_694', () async {
    final out = p.join(tmp.path, 'compat');
    final libDir = Directory(p.join(tmp.path, 'lib'))..createSync();
    final gdi32 = File(p.join(libDir.path, 'libgdi32.a'))
      ..writeAsStringSync('archive');
    final shlwapi = File(p.join(libDir.path, 'libshlwapi.a'))
      ..writeAsStringSync('archive');

    await materializeMingwCompat(outDir: out, mingwLibDir: libDir.path);

    final link = Link(p.join(out, 'libGdi32.a'));
    expect(link.existsSync(), isTrue);
    expect(link.targetSync(), gdi32.path);
    final shellLink = Link(p.join(out, 'libShlwapi.a'));
    expect(shellLink.existsSync(), isTrue);
    expect(shellLink.targetSync(), shlwapi.path);
  });

  test('test_case_712', () async {
    final out = p.join(tmp.path, 'compat');
    await materializeMingwCompat(
        outDir: out, mingwLibDir: p.join(tmp.path, 'empty'));
    expect(Link(p.join(out, 'libGdi32.a')).existsSync(), isFalse);
  });

  test('provides the case-sensitive Media Foundation reader header alias', () {
    expect(kMingwCompatHeaders['Mfreadwrite.h'], contains('mfreadwrite.h'));
    expect(kMingwCompatHeaders['Mferror.h'], contains('mferror.h'));
  });
}
