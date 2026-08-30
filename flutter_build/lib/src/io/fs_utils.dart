//
//

import 'dart:io';

import 'package:path/path.dart' as p;

///
const int kDefaultCopyConcurrency = 8;

///
///
Future<void> copyTree(
  String src,
  String dst, {
  int concurrency = kDefaultCopyConcurrency,
}) async {
  final srcDir = Directory(src);
  if (!srcDir.existsSync()) return;

  final ops = <Future<void> Function()>[];
  void walk(Directory dir, String target) {
    Directory(target).createSync(recursive: true);
    for (final entity in dir.listSync(recursive: false, followLinks: false)) {
      final t = p.join(target, p.basename(entity.path));
      if (entity is Directory) {
        walk(entity, t);
      } else if (entity is File) {
        ops.add(() => entity.copy(t));
      } else if (entity is Link) {
        final resolved = entity.resolveSymbolicLinksSync();
        ops.add(() => Link(t).create(resolved, recursive: true));
      }
    }
  }

  walk(srcDir, dst);
  await runBounded(ops, concurrency);
}

Future<void> copyFileIfExists(String src, String dst) async {
  final f = File(src);
  if (!f.existsSync()) return;
  await Directory(p.dirname(dst)).create(recursive: true);
  await f.copy(dst);
}

int dirSize(Directory dir) {
  var total = 0;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File) total += e.lengthSync();
  }
  return total;
}

///
Future<void> runBounded(
  List<Future<void> Function()> ops,
  int concurrency,
) async {
  if (ops.isEmpty) return;
  final limit = concurrency < 1 ? 1 : concurrency;
  var index = 0;

  Future<void> worker() async {
    while (index < ops.length) {
      final op = ops[index++];
      await op();
    }
  }

  final workerCount = limit < ops.length ? limit : ops.length;
  await Future.wait(<Future<void>>[
    for (var i = 0; i < workerCount; i++) worker(),
  ]);
}
