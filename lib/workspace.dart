import 'dart:io';

import 'package:glob/glob.dart';
import 'package:make_tools/makefile.dart';
import 'package:path/path.dart' as p;

final class DiscoveredModule {
  final String pathRelativeToRoot;
  final String namespace;
  final List<MakeTargetMeta> targets;

  const DiscoveredModule({
    required this.pathRelativeToRoot,
    required this.namespace,
    required this.targets,
  });
}

class WorkspaceScanner {
  final String root;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxDepth;

  WorkspaceScanner({
    required this.root,
    required this.includeGlobs,
    required this.excludeGlobs,
    required this.maxDepth,
  });

  Future<List<DiscoveredModule>> discover() async {
    final Directory rootDir = Directory(root);
    if (!await rootDir.exists()) return [];
    final String rootPath = p.normalize(rootDir.absolute.path);

    final List<Glob> includes = includeGlobs.isEmpty
        ? [Glob('**')]
        : includeGlobs.map((g) => Glob(g)).toList();
    final List<Glob> excludes = excludeGlobs.map((g) => Glob(g)).toList();

    final List<DiscoveredModule> modules = [];

    await for (final entity in rootDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (p.basename(entity.path) != 'Makefile') continue;
      final String rel = p.relative(entity.parent.path, from: rootPath);
      // Skip the root Makefile; root targets are handled separately
      if (rel == '.' || rel.isEmpty) continue;
      if (_depth(rel) > maxDepth) continue;
      if (!_matchesAny(rel, includes)) continue;
      if (_matchesAny(rel, excludes)) continue;

      final parser = MakefileParser();
      final lines = await File(
        p.join(entity.parent.path, 'Makefile'),
      ).readAsLines();
      final parsed = parser.parseLines(lines);
      final namespace = _encodeNamespace(rel);
      final List<MakeTargetMeta> metas = parsed.targets
          .map(
            (t) => MakeTargetMeta(
              name: '${namespace}_${t.name}',
              title: t.title,
              description: _augmentDescription(t.description, rel),
              runDirectory: rel,
              originalTargetName: t.name,
            ),
          )
          .toList();
      modules.add(
        DiscoveredModule(
          pathRelativeToRoot: rel,
          namespace: namespace,
          targets: metas,
        ),
      );
    }

    return modules;
  }

  static String _encodeNamespace(String relPath) {
    // Replace disallowed characters ':' and '/' with '_', collapse repeats
    final replaced = relPath.replaceAll(RegExp(r'[:/]+'), '_');
    final safe = replaced.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return safe.replaceAll(RegExp(r'_+'), '_');
  }

  static String? _augmentDescription(String? base, String relPath) {
    final suffix = 'Runs in directory: $relPath';
    if (base == null || base.trim().isEmpty) return suffix;
    return '$base\n$suffix';
  }

  static bool _matchesAny(String rel, List<Glob> globs) {
    if (globs.isEmpty) return false;
    return globs.any((g) => g.matches(rel));
  }

  static int _depth(String rel) {
    if (rel.isEmpty) return 0;
    return rel.split('/').where((p) => p.isNotEmpty).length;
  }
}
