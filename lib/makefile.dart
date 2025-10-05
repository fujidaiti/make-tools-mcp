import 'dart:io';

final class MakeTargetMeta {
  final String name;
  final String title;
  final String? description;
  final String? runDirectory;
  final String? originalTargetName;

  const MakeTargetMeta({
    required this.name,
    required this.title,
    this.description,
    this.runDirectory,
    this.originalTargetName,
  });
}

final class MakefileParseResult {
  final List<MakeTargetMeta> targets;
  const MakefileParseResult(this.targets);
}

class MakefileParser {
  static final RegExp _targetLine = RegExp(r'^(?<name>[A-Za-z0-9_.-]+):');

  Future<MakefileParseResult> parseFile(File file) async {
    final lines = await file.readAsLines();
    return parseLines(lines);
  }

  MakefileParseResult parseLines(List<String> lines) {
    final List<MakeTargetMeta> targets = [];
    for (var i = 0; i < lines.length; i++) {
      final commentMatch = _readDocComment(lines, i);
      if (commentMatch != null) {
        i = commentMatch.nextIndex;
      }

      final match = _targetLine.firstMatch(lines[i]);
      if (match == null) {
        continue;
      }
      final name = match.namedGroup('name')!;
      // Ignore special make meta-targets like .PHONY
      if (name.startsWith('.')) {
        continue;
      }

      // Compute title/description from commentMatch if present; else default.
      String title = name;
      String? description;
      if (commentMatch != null && commentMatch.docs.isNotEmpty) {
        final docs = commentMatch.docs;
        final int sepIndex = docs.indexWhere((e) => e.trim() == '#');
        if (sepIndex == -1) {
          title = _stripHashes(docs.join('\n'));
        } else {
          final titleLines = docs.take(sepIndex).toList();
          final descLines = docs.skip(sepIndex + 1).toList();
          final filteredDesc = descLines
              .where((l) => !l.trimLeft().startsWith('#!'))
              .toList();
          title = _stripHashes(titleLines.join('\n'));
          final desc = _stripHashes(filteredDesc.join('\n'));
          description = desc.trim().isEmpty ? null : desc;
        }
        // Remove any leading '#!' plain comments from a pure title-only block
        if (!title.contains('\n')) {
          final t = title.trimLeft();
          if (t.startsWith('!')) {
            title = name;
          }
        }
      }

      targets.add(
        MakeTargetMeta(name: name, title: title, description: description),
      );
    }
    return MakefileParseResult(targets);
  }

  _DocCapture? _readDocComment(List<String> lines, int index) {
    // Walk upwards to capture contiguous doc-comment block above a target.
    int i = index;
    // Skip any empty lines; doc-comment must be immediately above target without blank lines
    // so we only read when the next non-empty lines are comments.
    // We capture only when current line is a comment and the following non-empty line is a target.
    if (!_isDocCommentLine(lines[i])) return null;

    // Ensure the next non-empty line after this block is a target line.
    int j = i;
    final List<String> docs = [];
    while (j < lines.length && _isDocCommentLine(lines[j])) {
      docs.add(lines[j]);
      j++;
    }
    // If any blank line appears before target, it's still part of docs only if it's a comment line '#'
    if (j >= lines.length) return null;
    final next = lines[j];
    if (!_targetLine.hasMatch(next)) return null;
    return _DocCapture(docs: docs, nextIndex: j);
  }

  bool _isDocCommentLine(String line) {
    final t = line.trimLeft();
    return t.startsWith('#');
  }

  String _stripHashes(String text) {
    final List<String> out = [];
    for (final raw in text.split('\n')) {
      final s = raw.trimLeft();
      if (!s.startsWith('#')) {
        out.add(raw);
        continue;
      }
      // Skip lines starting with '#!' (plain comments) entirely
      if (s.startsWith('#!')) continue;
      // Line is a doc comment; remove leading '#'
      var trimmed = s.substring(1);
      if (trimmed.startsWith(' ')) trimmed = trimmed.substring(1);
      out.add(trimmed);
    }
    return out.join('\n');
  }
}

final class _DocCapture {
  final List<String> docs;
  final int nextIndex;
  const _DocCapture({required this.docs, required this.nextIndex});
}
