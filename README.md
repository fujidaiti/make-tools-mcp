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

- Title and description are parsed from consecutive lines that start with `#` and appear immediately above the target line (no non-comment lines in between).
- The first blank doc-comment line that contains only `#` splits the doc block into title (above) and description (below).
- Multiple title lines are supported; they are preserved as-is.
- Description lines may contain blank lines. Lines starting with `#!` inside the doc block are treated as plain comments and are ignored in the help text.
- Comments not directly attached to a target (i.e. separated by any non-comment line) are ignored.
- Special make meta-targets (e.g. `.PHONY`) are ignored and not exposed as tools.

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
