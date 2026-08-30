//

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

///
///
List<String> parseDepfileInputs(String content) {
  final unwrapped = content.replaceAll('\\\n', ' ');
  final colon = unwrapped.indexOf(':');
  if (colon < 0) return const <String>[];
  final deps = unwrapped.substring(colon + 1);

  final result = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < deps.length; i++) {
    final c = deps[i];
    if (c == r'\' && i + 1 < deps.length) {
      final next = deps[i + 1];
      if (next == ' ' || next == r'\') {
        buf.write(next);
        i++;
        continue;
      }
    }
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (buf.isNotEmpty) {
        result.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) result.add(buf.toString());
  return result;
}

String hashInputs(Iterable<String> parts) {
  final digest = sha256.convert(utf8.encode(parts.join('\u0000')));
  return digest.toString();
}

/// Builds a stable, inexpensive fingerprint for source trees.
///
/// Build systems already use file size and modification time for incremental
/// decisions. Recording the normalized path as well also detects additions,
/// removals and renames without reading large SDK/plugin trees into memory.
/// Symbolic links are not followed; their resolved target is fingerprinted.
String fileTreeMetadataFingerprint(Iterable<String> roots) {
  final entries = <String>[];
  for (final rawRoot in roots) {
    final root = p.normalize(p.absolute(rawRoot));
    final type = FileSystemEntity.typeSync(root, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      entries.add('missing:$root');
      continue;
    }
    if (type == FileSystemEntityType.file) {
      final file = File(root);
      final stat = file.statSync();
      entries.add(
        'file:$root:${stat.size}:${stat.modified.microsecondsSinceEpoch}',
      );
      continue;
    }
    if (type == FileSystemEntityType.link) {
      entries.add('link:$root:${Link(root).targetSync()}');
      continue;
    }

    final directory = Directory(root);
    entries.add('dir:$root');
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final entityType = FileSystemEntity.typeSync(
        entity.path,
        followLinks: false,
      );
      if (entityType == FileSystemEntityType.file) {
        final stat = File(entity.path).statSync();
        entries.add(
          'file:${p.normalize(entity.path)}:${stat.size}:'
          '${stat.modified.microsecondsSinceEpoch}',
        );
      } else if (entityType == FileSystemEntityType.link) {
        entries.add(
          'link:${p.normalize(entity.path)}:${Link(entity.path).targetSync()}',
        );
      }
    }
  }
  entries.sort();
  return hashInputs(entries);
}

///
///
bool isUpToDate({
  required String outputPath,
  required Iterable<String> inputPaths,
  String? stampPath,
  String? expectedStamp,
}) {
  final output = File(outputPath);
  if (!output.existsSync()) return false;

  if (stampPath != null) {
    final stampFile = File(stampPath);
    if (!stampFile.existsSync()) return false;
    if (stampFile.readAsStringSync() != (expectedStamp ?? '')) return false;
  }

  final outMtime = output.lastModifiedSync();
  for (final input in inputPaths) {
    final f = File(input);
    if (!f.existsSync()) return false;
    if (f.lastModifiedSync().isAfter(outMtime)) return false;
  }
  return true;
}
