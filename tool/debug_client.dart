import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

Future<void> main(List<String> arguments) async {
  final bool listOnly = arguments.contains('--list-only');
  final List<String> serverArgs = arguments
      .where((a) => a != '--list-only')
      .toList();
  final process = await Process.start('dart', [
    'run',
    'bin/make_tools.dart',
    ...serverArgs,
  ]);

  final serverOut = StreamController<List<int>>(sync: true);
  String stdoutCarry = '';
  process.stdout.listen((chunk) {
    // Always forward raw bytes to the MCP channel
    serverOut.add(chunk);

    // Pretty-print to console
    final text = utf8.decode(chunk);
    stdoutCarry += text;
    final parts = stdoutCarry.split('\n');
    stdoutCarry = parts.removeLast();
    for (final line in parts) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = json.decode(trimmed);
        stdout.writeln(prettyJson(decoded));
      } catch (_) {
        // Suppress non-JSON lines
      }
    }
  });
  process.stderr.listen((_) {});

  final client = MCPClient(
    Implementation(name: 'debug client', version: '0.1.0'),
  );
  final server = client.connectServer(
    stdioChannel(input: serverOut.stream, output: process.stdin),
  );
  unawaited(server.done.then((_) => process.kill()));

  await server.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  server.notifyInitialized();

  if (listOnly) {
    // Trigger list so the server response shows up via stdout pretty printer
    await server.listTools(ListToolsRequest());
    await client.shutdown();
    process.kill();
    return;
  }

  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) break;

    if (trimmed == '!list') {
      try {
        await server.listTools(ListToolsRequest());
      } catch (_) {
        // Suppress
      }
      continue;
    }

    final int space = trimmed.indexOf(' ');
    final String name;
    Map<String, Object?>? args;
    if (space < 0) {
      name = trimmed;
      args = null;
    } else {
      name = trimmed.substring(0, space);
      final jsonPart = trimmed.substring(space + 1).trim();
      try {
        final decoded = json.decode(jsonPart);
        if (decoded is Map<String, Object?>) {
          args = decoded;
        } else {
          // Suppress non-JSON output
          continue;
        }
      } catch (_) {
        // Suppress non-JSON output
        continue;
      }
    }

    try {
      await server.callTool(CallToolRequest(name: name, arguments: args));
    } catch (_) {
      // Suppress
    }
  }

  await client.shutdown();
  process.kill();
}

String prettyJson(Object? obj) {
  final encoder = const JsonEncoder.withIndent('  ');
  return encoder.convert(obj);
}
