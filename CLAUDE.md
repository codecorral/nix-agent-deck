# nix-agent-deck

Home Manager module that generates `~/.agent-deck/config.toml` from typed Nix options.

## Commands

```bash
nix flake check          # Run all tests (pure Nix evaluation, no VM needed)
```

## Architecture

- `modules/agent-deck.nix` — Single Home Manager module with all options and config generation
- `tests/default.nix` — Pure Nix evaluation tests (no NixOS VM); each test is a `pkgs.runCommand` derivation
- `examples/flake.nix` — Example consumer flake
- `flake.nix` — Exposes `homeManagerModules.default` and `checks` per system

## Key Patterns

- **camelCase → snake_case mapping**: Uses explicit lookup tables (`keyNameMap`, `sectionNameMap`), not regex. Add new mappings to these tables when adding options.
- **Null-driven omission**: All options default to `null`; `removeNulls` + `buildSection` ensure empty sections are omitted from generated TOML.
- **`extraConfig` deep merge**: Uses `lib.recursiveUpdate` so extra keys merge into typed sections rather than replacing them.
- **Generated config is read-only**: Output is a Nix store symlink — agent-deck must not write to `config.toml` at runtime.

## Code Style

- Nix options use camelCase; generated TOML uses snake_case
- Freeform sections (`mcps`, `tools`) pass through as-is (user provides snake_case keys)
- Tests use `builtins.fromTOML` to round-trip validate generated output
