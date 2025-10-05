import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class CommandResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;

  const CommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });
}

abstract class MakeCommandRunner {
  Future<CommandResult> runTarget(String target);
}

final class DefaultMakeCommandRunner implements MakeCommandRunner {
  @override
  Future<CommandResult> runTarget(String target) async {
    final Process proc = await Process.start("make", [
      target,
    ], runInShell: false);
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    await Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(out.write),
      proc.stderr.transform(utf8.decoder).forEach(err.write),
    ]);
    final code = await proc.exitCode;
    return CommandResult(
      exitCode: code,
      stdoutText: out.toString(),
      stderrText: err.toString(),
    );
  }

  Future<CommandResult> runTargetInDir(String directory, String target) async {
    final Process proc = await Process.start(
      "make",
      [target],
      runInShell: false,
      workingDirectory: directory,
    );
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    await Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(out.write),
      proc.stderr.transform(utf8.decoder).forEach(err.write),
    ]);
    final code = await proc.exitCode;
    return CommandResult(
      exitCode: code,
      stdoutText: out.toString(),
      stderrText: err.toString(),
    );
  }
}

extension MakeCommandRunnerX on MakeCommandRunner {
  Future<CommandResult> runTargetInDir(String directory, String target) {
    if (this is DefaultMakeCommandRunner) {
      return (this as DefaultMakeCommandRunner).runTargetInDir(
        directory,
        target,
      );
    }
    // Fallback for runners that don't support workingDirectory
    return runTarget(target);
  }
}
