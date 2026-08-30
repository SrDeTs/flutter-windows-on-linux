import 'dart:io';

import 'package:flutter_build/src/build/incremental.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('parseDepfileInputs', () {
    test('test_case_498', () {
      const content = '/out/app.dill: /a/main.dart /a/util.dart';
      expect(parseDepfileInputs(content), ['/a/main.dart', '/a/util.dart']);
    });

    test('test_case_503', () {
      const content = '/out/app.dill: \\\n  /a/main.dart \\\n  /a/util.dart\n';
      expect(parseDepfileInputs(content), ['/a/main.dart', '/a/util.dart']);
    });

    test('test_case_508', () {
      const content = r'/out/app.dill: /a/my\ file.dart';
      expect(parseDepfileInputs(content), ['/a/my file.dart']);
    });

    test('test_case_513', () {
      expect(parseDepfileInputs('no colon here'), isEmpty);
    });
  });

  group('hashInputs', () {
    test('test_case_519', () {
      expect(hashInputs(['a', 'b']), hashInputs(['a', 'b']));
    });

    test('test_case_523', () {
      expect(hashInputs(['a', 'b']), isNot(hashInputs(['b', 'a'])));
    });

    test('test_case_527', () {
      expect(hashInputs(['ab']), isNot(hashInputs(['a', 'b'])));
    });
  });

  group('fileTreeMetadataFingerprint', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('tree_stamp_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('is stable while the tree is unchanged', () {
      File(p.join(tmp.path, 'source.cpp')).writeAsStringSync('int main() {}');

      final first = fileTreeMetadataFingerprint([tmp.path]);
      final second = fileTreeMetadataFingerprint([tmp.path]);

      expect(second, first);
    });

    test('detects source additions and modifications', () async {
      final source = File(p.join(tmp.path, 'source.cpp'))
        ..writeAsStringSync('old');
      final first = fileTreeMetadataFingerprint([tmp.path]);

      source.writeAsStringSync('new source with another size');
      final modified = fileTreeMetadataFingerprint([tmp.path]);
      File(p.join(tmp.path, 'extra.h')).writeAsStringSync('#pragma once');
      final added = fileTreeMetadataFingerprint([tmp.path]);

      expect(modified, isNot(first));
      expect(added, isNot(modified));
    });

    test('detects symbolic-link target changes without following them', () {
      final firstTarget = Directory(p.join(tmp.path, 'one'))..createSync();
      final secondTarget = Directory(p.join(tmp.path, 'two'))..createSync();
      final link = Link(p.join(tmp.path, 'plugin'))
        ..createSync(firstTarget.path);
      final first = fileTreeMetadataFingerprint([link.path]);

      link.deleteSync();
      link.createSync(secondTarget.path);

      expect(fileTreeMetadataFingerprint([link.path]), isNot(first));
    });
  });

  group('isUpToDate', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('incr_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File write(String name, String content) =>
        File(p.join(tmp.path, name))..writeAsStringSync(content);

    test('test_case_584', () {
      expect(
        isUpToDate(
            outputPath: p.join(tmp.path, 'missing.out'), inputPaths: const []),
        isFalse,
      );
    });

    test('test_case_592', () {
      final input = write('in.dart', 'x');
      final output = write('out.dill', 'y');
      final past = DateTime.now().subtract(const Duration(hours: 1));
      input.setLastModifiedSync(past);
      output.setLastModifiedSync(DateTime.now());
      expect(
        isUpToDate(outputPath: output.path, inputPaths: [input.path]),
        isTrue,
      );
    });

    test('test_case_604', () {
      final output = write('out.dill', 'y');
      final input = write('in.dart', 'x');
      output.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)));
      input.setLastModifiedSync(DateTime.now());
      expect(
        isUpToDate(outputPath: output.path, inputPaths: [input.path]),
        isFalse,
      );
    });

    test('test_case_616', () {
      final output = write('out.dill', 'y');
      expect(
        isUpToDate(
            outputPath: output.path,
            inputPaths: [p.join(tmp.path, 'gone.dart')]),
        isFalse,
      );
    });

    test('test_case_626', () {
      final output = write('out.dill', 'y');
      write('out.dill.stamp', 'OLD');
      expect(
        isUpToDate(
          outputPath: output.path,
          inputPaths: const [],
          stampPath: p.join(tmp.path, 'out.dill.stamp'),
          expectedStamp: 'NEW',
        ),
        isFalse,
      );
    });

    test('test_case_640', () {
      final output = write('out.dill', 'y');
      write('out.dill.stamp', 'MATCH');
      expect(
        isUpToDate(
          outputPath: output.path,
          inputPaths: const [],
          stampPath: p.join(tmp.path, 'out.dill.stamp'),
          expectedStamp: 'MATCH',
        ),
        isTrue,
      );
    });
  });
}
