# make_tools (WIP)

Expose Makefile targets as MCP tools.

## Install

```bash
dart pub get
```

## Run

```bash
dart run bin/make_tools.dart
```

The server communicates over stdio (MCP). It parses a `Makefile` at the project root and registers each target as a tool. Doc-comments above each target form the tool title/description. When a tool is invoked, `make <target>` is executed and the combined output is returned; non-zero exit codes are flagged as errors.

## Doc-comment syntax and examples

### Attachment and placement

Doc-comments are composed of consecutive lines that start with `#` and must appear immediately above a target definition. There must be no non-comment lines between the doc-comment and the target. If a comment block is separated from a target by a blank or non-comment line, that block is ignored for that target.

### Title and description

Within a doc-comment block, the first blank line that contains only `#` is a separator. All comment lines above the separator are interpreted as the title. All comment lines below the separator are interpreted as the description. The title can span multiple lines and is preserved as written. The description can contain multiple paragraphs separated by blank comment lines and is optional; if omitted, only the title is used.

If a target has no doc-comment block at all, its tool title defaults to the target name.

### Ignored lines and meta-targets

Any line within a doc-comment that begins with `#!` is treated as a plain comment intended for maintainers and is not included in the generated help text. Make meta-targets that begin with a dot, such as `.PHONY`, are ignored by the parser and are never exposed as tools.

Title only (no description):

```makefile
# Build Flutter app and generate an APK
build-app:
 flutter build apk --release
```

Title and description (split by a blank `#` line); `#!` lines are ignored:

```makefile
# tidyup is a shortcut for fix, format, and analyze
#
# This runs "fix", "format", and "analyze" in sequence.
#! internal note: this line is ignored
# Extra description line.
tidyup: fix format analyze
```

No doc-comment (title defaults to the target name):

```makefile
format:
 dart format .
```

Stray comments are ignored if not attached directly above a target:

```makefile
# Not attached to any target

analyze:
 dart analyze
```

Meta targets are ignored:

```makefile
.PHONY: analyze format tidyup
```

## Test

```bash
dart test
```

A sample command-line application providing basic argument parsing with an entrypoint in `bin/`.
