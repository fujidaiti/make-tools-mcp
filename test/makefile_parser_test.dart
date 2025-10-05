import 'package:make_tools/makefile.dart';
import 'package:test/test.dart';

void main() {
  group('MakefileParser', () {
    test(
      'parses title and description with blank separator and #! filtering',
      () {
        final source = '''
# Title line 1
#
# Description line 1
#! plain comment
# Description line 2
build-app:
\tflutter build apk --release
''';
        final parsed = MakefileParser().parseLines(source.split('\n'));
        expect(parsed.targets.length, 1);
        final t = parsed.targets.single;
        expect(t.name, 'build-app');
        expect(t.title, 'Title line 1');
        expect(t.description, 'Description line 1\nDescription line 2');
      },
    );

    test('defaults title to target name when no doc-comments', () {
      final source = '''
format:
\tdart format .
''';
      final parsed = MakefileParser().parseLines(source.split('\n'));
      final t = parsed.targets.single;
      expect(t.name, 'format');
      expect(t.title, 'format');
      expect(t.description, isNull);
    });

    test('ignores comments not attached directly above a target', () {
      final source = '''
# stray comment

analyze:
\tdart analyze
''';
      final parsed = MakefileParser().parseLines(source.split('\n'));
      final t = parsed.targets.single;
      expect(t.title, 'analyze');
      expect(t.description, isNull);
    });
  });
}
