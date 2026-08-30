import 'dart:io';

import 'package:flutter_build/src/io/fs_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fs_utils_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('copyTree', () {
    test('test_case_212', () async {
      final src = Directory(p.join(tmp.path, 'src'))..createSync();
      for (var i = 0; i < 50; i++) {
        File(p.join(src.path, 'sub$i', 'file$i.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync('content-$i');
      }
      final dst = p.join(tmp.path, 'dst');

      await copyTree(src.path, dst);

      for (var i = 0; i < 50; i++) {
        final f = File(p.join(dst, 'sub$i', 'file$i.txt'));
        expect(f.existsSync(), isTrue, reason: 'expected condition');
        expect(f.readAsStringSync(), 'content-$i');
      }
    });

    test('test_case_230', () async {
      final dst = p.join(tmp.path, 'dst');
      await copyTree(p.join(tmp.path, 'nope'), dst);
      expect(Directory(dst).existsSync(), isFalse);
    });

    test('test_case_236', () async {
      final src = Directory(p.join(tmp.path, 'empty'))..createSync();
      final dst = p.join(tmp.path, 'dst_empty');
      await copyTree(src.path, dst);
      expect(Directory(dst).existsSync(), isTrue);
    });

    test('test_case_243', () async {
      final target = Directory(p.join(tmp.path, 'target'))..createSync();
      File(p.join(target.path, 'a.txt')).writeAsStringSync('hi');

      final src = Directory(p.join(tmp.path, 'src'))..createSync();
      Link(p.join(src.path, 'link'))
          .createSync(p.relative(target.path, from: src.path));

      final dst = p.join(tmp.path, 'dst');
      await copyTree(src.path, dst);

      final copied = p.join(dst, 'link');
      expect(
        FileSystemEntity.typeSync(copied, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(Link(copied).targetSync(), target.path);
    });
  });

  group('copyFileIfExists', () {
    test('test_case_264', () async {
      final src = File(p.join(tmp.path, 'a.txt'))..writeAsStringSync('data');
      final dst = p.join(tmp.path, 'nested', 'b.txt');
      await copyFileIfExists(src.path, dst);
      expect(File(dst).readAsStringSync(), 'data');
    });

    test('test_case_271', () async {
      final dst = p.join(tmp.path, 'out.txt');
      await copyFileIfExists(p.join(tmp.path, 'missing.txt'), dst);
      expect(File(dst).existsSync(), isFalse);
    });
  });

  group('dirSize', () {
    test('test_case_279', () {
      final d = Directory(p.join(tmp.path, 'd'))..createSync();
      File(p.join(d.path, 'a')).writeAsBytesSync(List.filled(10, 0));
      File(p.join(d.path, 'sub', 'b'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(5, 0));
      expect(dirSize(d), 15);
    });
  });
}
