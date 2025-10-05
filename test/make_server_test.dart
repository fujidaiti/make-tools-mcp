import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:make_tools/makefile.dart';
import 'package:make_tools/runner.dart';
import 'package:mockito/mockito.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../bin/make_tools.dart' show MakeMCPServer, version;

final class _TestClient extends MCPClient {
  _TestClient() : super(Implementation(name: 'test client', version: '0.1.0'));
}

class _MockRunner extends Mock implements MakeCommandRunner {
  @override
  Future<CommandResult> runTarget(String target) => super.noSuchMethod(
    Invocation.method(#runTarget, [target]),
    returnValue: Future.value(
      const CommandResult(exitCode: 0, stdoutText: 'ok', stderrText: ''),
    ),
    returnValueForMissingStub: Future.value(
      const CommandResult(exitCode: 0, stdoutText: 'ok', stderrText: ''),
    ),
  );
}

void main() {
  group('MakeMCPServer', () {
    late StreamController<String> c2s;
    late StreamController<String> s2c;
    late StreamChannel<String> clientChannel;
    late StreamChannel<String> serverChannel;
    late MakeMCPServer server;
    late _TestClient client;
    late ServerConnection conn;
    late InitializeResult init;

    late List<MakeTargetMeta> parsedTargets;

    setUp(() async {
      c2s = StreamController<String>();
      s2c = StreamController<String>();
      clientChannel = StreamChannel.withCloseGuarantee(s2c.stream, c2s.sink);
      serverChannel = StreamChannel.withCloseGuarantee(c2s.stream, s2c.sink);

      // Fake parsed Makefile content
      parsedTargets = const [
        MakeTargetMeta(
          name: 'build-app',
          title: 'Title',
          description: 'Description',
        ),
      ];
      final runner = _MockRunner();

      server = MakeMCPServer(
        serverChannel,
        parsedTargets,
        runner,
        verbose: false,
      );
      client = _TestClient();
      conn = client.connectServer(clientChannel);
      init = await conn.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      conn.notifyInitialized(InitializedNotification());
      await server.initialized;
    });

    tearDown(() async {
      await client.shutdown();
      await server.shutdown();
      // nothing to clean
    });

    test('initializes and lists tools', () async {
      expect(init.serverInfo.name, 'make_tools');
      expect(init.serverInfo.version, version);
      final list = await conn.listTools();
      expect(list.tools.map((t) => t.name), contains('build-app'));
    });

    test('runs target and returns output', () async {
      final result = await conn.callTool(CallToolRequest(name: 'build-app'));
      expect(result.isError ?? false, false);
      final text = TextContent.fromMap(
        result.content.single as Map<String, Object?>,
      );
      expect(text.text, 'ok');
    });

    test('calling unknown tool returns error result', () async {
      final result = await conn.callTool(CallToolRequest(name: 'nope'));
      expect(result.isError, true);
      final text = TextContent.fromMap(
        result.content.single as Map<String, Object?>,
      );
      expect(text.text, contains('No tool registered'));
    });

    test('non-zero exit code is returned as error', () async {
      // Override stub for this test
      final runnerField = server.runner as _MockRunner;
      when(runnerField.runTarget('build-app')).thenAnswer(
        (_) async => const CommandResult(
          exitCode: 2,
          stdoutText: '',
          stderrText: 'No rule to make target',
        ),
      );
      final result = await conn.callTool(CallToolRequest(name: 'build-app'));
      expect(result.isError, true);
      final text = TextContent.fromMap(
        result.content.last as Map<String, Object?>,
      );
      expect(text.text, contains('No rule'));
    });
  });
}
