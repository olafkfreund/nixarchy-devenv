---
status: approved
issue: 55
intent: intent/2026-09-28-55-secret-policy.md
---

# Spec: Standardize encrypted secrets across templates

## Design

Use one policy with two supported delivery modes:

1. **Built-in presets use the shared agenix-compatible scaffold by default.**
   The CLI index marks every built-in `preset` as `secretPolicy = "agenix"`,
   regardless of whether the catalogue entry currently carries an explicit
   `secretScaffold` flag. Existing explicit flags remain valid metadata during
   the transition. New presets inherit the safe default automatically.
2. **Generators declare their external secret policy.** The cloud generator
   entries use `secretPolicy = "external-agenix"`; the pinned generator remains
   responsible for writing `secrets.nix`, encrypted `secrets/*.age`, and its
   helper scripts. The plugin's real template check verifies those files and
   helper names after generation.

The shared preset scaffold remains agenix-format: encrypted `.age` files,
`secrets.nix` recipient declarations, and devenv scripts for add, edit, delete,
list, run, rekey, and recipient add. It uses runtime decryption only and does
not read secret values during Nix evaluation. The existing validation and
rollback behavior is retained and strengthened with credential-free refusal
tests.

Use devenv SecretSpec only when a template has a real provider-backed
environment-variable contract. No current built-in preset needs that contract,
so this change does not create an empty `secretspec.toml` or pretend that a
provider exists. A future NixOS or hosted-AI generator can declare SecretSpec
explicitly without changing the agenix file policy for repository secrets.

Update `data/templates.nix` field documentation, `pkgs/cli.nix` index metadata,
`pkgs/templates-check.nix` generated-project assertions, CLI tests, the shared
secret scaffold tests, README, and usage documentation. The catalogue will
state that secret names and recipient public keys are metadata, while values
remain encrypted/runtime-only.

The policy follows devenv's current options reference: `scripts.<name>.packages`
is the correct project-local dependency boundary, and `secretspec.enable` is
only an integration switch when a SecretSpec manifest/provider is actually
used. See https://devenv.sh/reference/options/.

## Alternatives rejected

- **Mark every preset manually forever:** rejected because a new preset could
  silently omit secret handling; the CLI default is safer and smaller.
- **Replace agenix with SOPS for every project:** rejected because the current
  scaffold, cloud generator, recipient helpers, and encrypted-file format are
  already agenix-compatible and meet the requirement without adding another
  file format or provider configuration.
- **Enable SecretSpec everywhere:** rejected because an empty or provider-less
  manifest adds setup without defining what the application needs.
- **Copy helper implementations into each template:** rejected because the
  existing shared scaffold is the single place for validation, deletion
  rollback, recipient checks, and rekey behavior.
- **Put provider credentials in `devenv.nix`:** rejected because evaluation
  can copy values into `/nix/store`; credentials stay encrypted or runtime-only.

## Risks

- Existing preset projects do not change; only newly generated projects receive
  the default scaffold.
- The external generator's pinned output can drift; generated-file assertions
  must fail if its secret contract disappears.
- Users still need to add recipients before creating a first secret; the note
  and helper error must make that prerequisite explicit.
- A future SecretSpec template may need provider-specific documentation and
  credentials; it must be a separate declared policy, not inferred.

## Verification

- Catalogue/index tests assert every built-in preset has `secretPolicy =
  "agenix"` and every generator has an explicit supported policy.
- CLI tests scaffold representative existing presets and assert
  `secrets.nix`, `secrets/.gitkeep`, all helper names, encrypted-only paths,
  and refusal of invalid secret names/recipient input without credentials.
- `nix run .#templates-check` asserts every preset and generator emits its
  declared secret files and evaluates without changing the real allow list.
- `node --test 'tests/model/*.test.js'`
- `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
- `nix flake check --all-systems --no-build`
