import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:make_tools/makefile.dart';
import 'package:make_tools/runner.dart';
import 'package:make_tools/workspace.dart';
import 'package:path/path.dart' as p;

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.')
    ..addFlag(
      'workspace',
      negatable: false,
      help: 'Enable workspace mode (discover multiple Makefiles).',
    )
    ..addOption(
      'workspace-root',
      valueHelp: 'path',
      defaultsTo: '.',
      help: 'Repo root for scanning (default .).',
    )
    ..addMultiOption(
      'workspace-include',
      valueHelp: 'glob',
      help: 'Include glob(s) for module directories; repeatable.',
    )
    ..addMultiOption(
      'workspace-exclude',
      valueHelp: 'glob',
      help: 'Exclude glob(s) for module directories; repeatable.',
    )
    ..addOption(
      'workspace-max-depth',
      valueHelp: 'n',
      defaultsTo: '4',
      help: 'Maximum depth for recursive scanning (default 4).',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart make_tools.dart <flags> [arguments]');
  print(argParser.usage);
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      print('make_tools version: $version');
      return;
    }
    if (results.flag('verbose')) {
      verbose = true;
    }

    final bool workspace = results.flag('workspace');
    final List<MakeTargetMeta> targets = [];
    final MakefileParser parser = MakefileParser();

    if (workspace) {
      final String root = results.option('workspace-root') ?? '.';
      final List<String> includes =
          (results['workspace-include'] as List<Object?>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      final List<String> excludes =
          (results['workspace-exclude'] as List<Object?>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      final int maxDepth =
          int.tryParse(results.option('workspace-max-depth') ?? '4') ?? 4;

      // Root Makefile (optional in workspace mode)
      final String rootMakefile = p.join(root, 'Makefile');
      final io.File rootFile = io.File(rootMakefile);
      if (rootFile.existsSync()) {
        try {
          final parsed = parser.parseLines(rootFile.readAsLinesSync());
          for (final t in parsed.targets) {
            targets.add(
              MakeTargetMeta(
                name: t.name,
                title: t.title,
                description: _augmentRootDescription(t.description),
                runDirectory: '.',
                originalTargetName: t.name,
              ),
            );
          }
        } catch (e) {
          io.stderr.writeln('Failed to read root Makefile: $e');
          io.exit(1);
        }
      }

      // Modules
      final scanner = WorkspaceScanner(
        root: root,
        includeGlobs: includes,
        excludeGlobs: excludes,
        maxDepth: maxDepth,
      );
      final modules = await scanner.discover();
      for (final m in modules) {
        targets.addAll(m.targets);
      }

      if (targets.isEmpty) {
        io.stderr.writeln(
          'No make targets found in workspace at ${io.Directory(root).absolute.path}',
        );
        io.exit(1);
      }
    } else {
      // Non-workspace mode: use top-level ./Makefile
      final io.File file = io.File('Makefile');
      if (!file.existsSync()) {
        io.stderr.writeln('Makefile not found at ${file.path}');
        io.exit(1);
      }
      try {
        final parsed = parser.parseLines(file.readAsLinesSync());
        if (parsed.targets.isEmpty) {
          io.stderr.writeln('No make targets found in ${file.path}');
          io.exit(1);
        }
        for (final t in parsed.targets) {
          targets.add(
            MakeTargetMeta(
              name: t.name,
              title: t.title,
              description: _augmentRootDescription(t.description),
              runDirectory: '.',
              originalTargetName: t.name,
            ),
          );
        }
      } catch (e) {
        io.stderr.writeln('Failed to read Makefile: $e');
        io.exit(1);
      }
    }

    // Start MCP server with parsed targets
    MakeMCPServer(
      stdioChannel(input: io.stdin, output: io.stdout),
      targets,
      DefaultMakeCommandRunner(),
      verbose: verbose,
    );
    // Keep running; server manages lifecycle
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    io.stderr.writeln(e.message);
    io.stderr.writeln('');
    printUsage(argParser);
  }
}

base class MakeMCPServer extends MCPServer with ToolsSupport {
  final List<MakeTargetMeta> targets;
  final MakeCommandRunner runner;
  final bool verbose;

  MakeMCPServer(
    super.channel,
    this.targets,
    this.runner, {
    this.verbose = false,
  }) : super.fromStreamChannel(
         implementation: Implementation(
           name: 'make_tools',
           title: 'Expose Makefile targets as MCP tools',
           version: version,
         ),
       ) {
    _registerTools();
  }

  void _registerTools() {
    for (final meta in targets) {
      final Tool tool = Tool(
        name: meta.name,
        title: meta.title,
        description: meta.description,
        inputSchema: Schema.object(properties: const {}),
        annotations: ToolAnnotations()
      );
      registerTool(tool, (req) async {
        final String dir = meta.runDirectory ?? '.';
        final String target = meta.originalTargetName ?? meta.name;
        final res = await runner.runTargetInDir(dir, target);
        final contents = <Content>[];
        if (res.stdoutText.isNotEmpty) {
          contents.add(TextContent(text: res.stdoutText));
        }
        if (res.stderrText.isNotEmpty) {
          contents.add(TextContent(text: res.stderrText));
        }
        return CallToolResult(
          isError: res.exitCode != 0,
          content: contents.isEmpty ? [TextContent(text: '')] : contents,
        );
      });
    }
  }
}

String? _augmentRootDescription(String? base) {
  const suffix = 'Runs in directory: .';
  if (base == null || base.trim().isEmpty) return suffix;
  return '$base\n$suffix';
}
