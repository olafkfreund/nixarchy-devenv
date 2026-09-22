# The `nixarchy-devenv` command. The script is pkgs/cli.sh; this file builds
# the catalogue it reads and hands it the store path as `share`.
#
# Why a store-side index rather than the plugin evaluating data/templates.nix:
# drawing a list must never run Nix. The plugin reads `templates --json`,
# which is this file plus whatever personal templates exist.
{
  lib,
  stdenv,
  runCommand,
  writeText,
  writeShellApplication,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  jq,
}:
let
  templates = import ../data/templates.nix;
  # An entry with `systems` exists only there: hidden elsewhere means absent
  # from the index, from share/presets, and from templates-check.
  ids = lib.filter (
    n: !(templates.${n} ? systems) || lib.elem stdenv.hostPlatform.system templates.${n}.systems
  ) (lib.attrNames templates);
  presetIds = lib.filter (n: templates.${n}.kind == "preset") ids;

  # A preset's yaml changes the project's own nixpkgs configuration (android's
  # allows unfree packages), and the form's only word on a template is its
  # note -- so the note has to say so, or the catalogue does not build.
  unannouncedYaml = lib.filter (
    n: templates.${n} ? yaml && !(lib.hasInfix "devenv.yaml" templates.${n}.note)
  ) (lib.attrNames templates);

  # Nix '' strings strip common indentation, so the catalogue is flush left and
  # the two spaces devenv's own scaffold uses go on here. Blank lines stay blank.
  indent =
    text:
    lib.concatMapStrings (l: if l == "" then "\n" else "  ${l}\n") (
      lib.splitString "\n" (lib.removeSuffix "\n" text)
    );

  # Flat fields, so the shell reads them with one jq path each.
  entry =
    id:
    let
      t = templates.${id};
    in
    {
      inherit id;
      inherit (t) kind group label note;
    }
    // lib.optionalAttrs (t ? yaml) { yaml = true; }
    // lib.optionalAttrs (t.kind == "generator") {
      inherit (t) flake rev providers;
      honours_git = t.honours.git;
      honours_allow = t.honours.allow;
    };

  index = writeText "templates.json" (builtins.toJSON (map entry ids));

  share = runCommand "nixarchy-devenv-templates" { } (
    ''
      mkdir -p $out/presets
      cp ${index} $out/templates.json
    ''
    + lib.concatMapStrings (n: ''
      cp ${writeText "${n}.nix" (indent templates.${n}.lines)} $out/presets/${n}.nix
    '') presetIds
    # YAML indentation is meaning, so the keys go in verbatim.
    + lib.concatMapStrings (n: ''
      cp ${writeText "${n}.yaml" templates.${n}.yaml} $out/presets/${n}.yaml
    '') (lib.filter (n: templates.${n} ? yaml) presetIds)
  );
in
assert lib.assertMsg (unannouncedYaml == [ ])
  "templates with yaml whose note does not mention devenv.yaml: ${toString unannouncedYaml}";
writeShellApplication {
  name = "nixarchy-devenv";
  runtimeInputs = [
    coreutils
    findutils
    gnugrep
    gnused
    jq
  ];
  text = ''
    share=${share}
  ''
  + builtins.readFile ./cli.sh;
  passthru.templateIds = ids;
}
