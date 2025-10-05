## make_tools

Expose Makefile targets as MCP tools.

### Install

```bash
dart pub get
```

### Run

```bash
dart run bin/make_tools.dart
```

The server communicates over stdio (MCP). It parses a `Makefile` at the project root and registers each target as a tool. Doc-comments above each target form the tool title/description per the rules:

- Lines starting with `#` directly above a target are doc-comments.
- The first blank doc line (`#`) separates title (above) and description (below).
- Lines starting with `#!` are ignored as plain comments.
- Targets without doc-comments use the target name as the title.

When a tool is invoked, `make <target>` is executed and the combined output is returned; non-zero exit codes are flagged as errors.

### Test

```bash
dart test
```

A sample command-line application providing basic argument parsing with an entrypoint in `bin/`.
