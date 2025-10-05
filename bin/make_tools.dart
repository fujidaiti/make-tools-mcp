import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:make_tools/makefile.dart';
import 'package:make_tools/runner.dart';

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
    ..addOption(
      'makefile',
      valueHelp: 'path/to/Makefile',
      help: 'Path to the Makefile to parse (defaults to ./Makefile).',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart make_tools.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) {
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

    // Parse Makefile before starting server
    final path = results.option('makefile') ?? 'Makefile';
    final file = io.File(path);
    final parser = MakefileParser();
    if (!file.existsSync()) {
      io.stderr.writeln('Makefile not found at ${file.path}');
      io.exit(1);
    }
    List<MakeTargetMeta> targets;
    try {
      targets = parser.parseLines(file.readAsLinesSync()).targets;
    } catch (e) {
      io.stderr.writeln('Failed to read Makefile: $e');
      io.exit(1);
    }
    if (targets.isEmpty) {
      io.stderr.writeln('No make targets found in ${file.path}');
      io.exit(1);
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
      );
      registerTool(tool, (req) async {
        final res = await runner.runTarget(meta.name);
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
