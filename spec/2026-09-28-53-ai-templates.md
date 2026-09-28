---
status: draft
issue: 53
intent: intent/2026-09-28-53-ai-templates.md
---

# Spec: Add local and hosted AI templates

## Design

Add two preset entries to `data/templates.nix`, both in the `AI` group and
both inheriting the existing built-in `agenix` secret policy:

- `local-ai`: Python with uv and a project virtualenv, plus the Nix packages
  `ollama`, `llama-cpp`, `nvtopPackages.full`, `pciutils`, and `clinfo`.
  These provide local model clients/runners and hardware diagnostics without
  enabling an Ollama service, downloading model weights, selecting a GPU
  driver, or exposing a network endpoint.
- `ai-providers`: Python with uv plus `curl` and `jq` for provider API
  inspection and small integration scripts. The note will show that provider
  SDKs belong in the project's `pyproject.toml`, added with `uv add`, rather
  than being frozen as Nix Python packages in the template. No provider
  credential or default endpoint is generated.

Presets currently cannot declare a second `packages` option because
`devenv init` creates `packages = [ pkgs.git ];`. Add a `shellPackages` metadata
field for presets. `pkgs/cli.nix` will render those packages by extending the
existing init line, for example `packages = [ pkgs.git ] ++ [ pkgs.ollama ];`.
The field is catalogue metadata, not a user-authored `packages` option. Keep
the field optional so existing presets and custom generators are unchanged.

Update the generated template index and template-check validation so the two
new presets are checked for their declared shell packages, secret scaffold,
and successful `devenv info`. Update `README.md` and `docs/usage.md` with the
two entries and the boundary between project tooling, machine GPU drivers,
model weights, provider SDKs, and runtime-managed secrets. Extend the CLI
fixture tests only where they assert the generated package line or template
count.

## Alternatives rejected

- Adding `packages = ...` to each preset: `devenv init` already emits that
  attribute, so the generated Nix would fail with a duplicate definition.
- Installing Python provider SDKs from nixpkgs: provider SDK versions and
  release cadence belong to the project's uv-managed dependency graph.
- Enabling Ollama, a model service, Open WebUI, or model downloads: this would
  create machine/service policy and large runtime state from a project
  template.
- Making AI templates generators in a second repository: the requested
  starting points are option lines plus a small package list and do not need a
  generator lifecycle or external revision pin.

## Risks

- `ollama`, `llama-cpp`, GPU diagnostics, or their transitive closures may be
  large; the template note must make that cost visible, and template checks
  must catch unavailable packages on supported systems.
- GPU tools report hardware but do not configure drivers; users may mistake a
  successful shell evaluation for a ready inference stack. Documentation must
  state that NixOS GPU setup remains machine-level work.
- Appending shell packages changes `pkgs/cli.nix` output for only templates
  that opt into `shellPackages`; existing templates must remain byte-for-byte
  compatible apart from the generated index metadata.
- Hosted provider credentials are still sensitive even though the template
  creates no values; the shared agenix helpers and runtime-only guidance must
  remain present.

## Verification

- `node --test 'tests/model/*.test.js'`
- `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
- `nix flake check --all-systems --no-build`
- `nix run .#templates-check local-ai ai-providers`
- Confirm the generated projects contain no plaintext secrets, preserve the
  invoking user's devenv allow list, expose the declared shell tools, and
  evaluate with `devenv info`.
