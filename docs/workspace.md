## Workspace: Multi-Makefile support for monorepos

### Overview

Workspace enables exposing Make targets from multiple submodules in a single MCP server started at the repository root. It discovers Makefiles in configured subdirectories, namespaces their targets, registers them as tools, and executes them in their respective directories.

### Goals

- Support multiple Makefiles under a single repo root.
- Provide stable namespacing to avoid target collisions.
- Keep default single-`Makefile` behavior unchanged.
- Execute targets within their submodule directories with combined output and error propagation.
- Zero-config defaults; minimal, explicit CLI flags only.

### Non-goals

- Live file watching or hot reloading of new Makefiles.
- Parsing full Make semantics (only target discovery via text parsing).
- Cross-module orchestration beyond invoking a single target per tool call.

### Terminology

- Workspace: the set of directories under the repo root that may contain Makefiles.
- Module: a directory containing a `Makefile`.
- Namespace: the string derived from a module path used to qualify targets.

## UX

### CLI flags

- `--workspace`: enable workspace mode; if omitted, the other workspace flags are also ignored.
- `--workspace-root <path>`: repo root for scanning (default `.`).
- `--workspace-include <glob>`: include glob(s) for module paths; repeatable.
- `--workspace-exclude <glob>`: exclude glob(s); repeatable.
- `--workspace-max-depth <n>`: limit recursive scan depth (default `4`).

Notes:

- The `--makefile` flag is removed. When `--workspace` is not set, the tool uses the top-level `./Makefile`.

### Tool naming

- For root targets (top-level `./Makefile`), tool name is just the target name.
- For module targets, format is `{namespace}_{target}`.
- Namespace is the module path relative to root with disallowed characters mapped to `_`:
  - Replace `/` and `:` with `_`.
  - Collapse consecutive `_`.
  - Keep alphanumerics, `_`, `-`, and `.`; map everything else to `_`.
- Aliases are not supported.

### Invocation

- Change working directory to the module directory, then run `make <target>`.
- Implementation uses the process `workingDirectory` option (no `-C`).

## Configuration

No configuration file. Behavior is controlled only via CLI flags.

## Discovery

- Starting from `workspace.root`, scan recursively up to `--workspace-max-depth`.
- Apply `--workspace-include` and `--workspace-exclude` globs to module directories.
- A directory is a module if it contains a `Makefile`.
- Parse each Makefile with the existing line-based parser to extract targets and doc comments.
- Does not read or honor `.gitignore`; only the provided include/exclude globs apply.

## Registration and namespacing

- Tool names are either `{target}` (root) or `{namespace}_{target}` (modules).
- Namespace is derived from the relative path by mapping disallowed characters to `_`.
- Title/description come from the Makefile doc-comments (existing rules).
- Description augmentation: append a final line `Runs in directory: <path>` to every tool description, where `<path>` is `.` for root tools or the module path (relative to `workspace-root`) for module tools.

## Execution model

- Runner executes `make <target>` with `workingDirectory` set to the module directory.
- Output is streamed and combined as today; exit code propagation unchanged.

## Error handling

- Missing Makefiles after discovery: skip with a warning unless neither root nor any modules are found (then exit with error).
- Invalid flags or glob patterns: print diagnostics and exit with error.

## Performance

- Discovery uses glob filtering to avoid walking the entire tree by default.
- Parsing is line-based and fast; no recipe expansion.
- Consider memoizing the discovery result during server startup; no live reload.

## Security considerations

- Do not execute implicit recipes; only run explicitly invoked targets.
- Honor include/exclude flags to avoid exposing sensitive directories.
- No shell interpolation beyond `make` arguments; do not include user input in names.

## Backward compatibility

- Default behavior remains single-`Makefile` mode using the top-level `./Makefile` when `--workspace` is not set.
- Workspace mode is opt-in via `--workspace`.

## Implementation plan

1) Core types
   - Add `WorkspaceScanner`, `DiscoveredModule { path, namespace, targets }`.
   - Implement glob include/exclude with a small utility (e.g., `package:glob`).
2) CLI
   - Add `--workspace*` flags; remove `--makefile`.
3) Discovery
   - Implement scanning logic honoring `--workspace-max-depth` and globs.
   - Parse Makefiles with existing parser to produce `MakeTargetMeta`.
4) Namespacing and registration
   - Build `{namespace}_{target}` names; root targets keep `{target}`.
   - Register tools with existing server, preserving title/description.
5) Runner
   - Extend `MakeCommandRunner` to accept module directory (e.g., `runIn(String dir, String target)`).
   - Default implementation executes `make <target>` with `workingDirectory: dir`.
   - Maintain a compatibility path for single-file mode.
6) Tests
   - Unit tests for discovery, namespacing, name encoding, and runner invocation.
   - Integration test that registers tools from root and modules and invokes them.

## Testing strategy

- Verify name encoding: path to namespace with `_` mapping; root vs module tools.
- Exclude/Include interaction and depth limits.
- Removing `--makefile`: root-only mode works without workspace.

## Decisions

- Dynamic refresh tool (e.g., `workspace_reload`): not supported.
- Passing additional `make` arguments via input schema: not supported currently.
- Discovery does not respect `.gitignore`; only provided globs are used.
