{
  # horas: a calendar in Bend, one copy per machine, joined
  # over ssh and with Google Calendar. The program is Main.bend and
  # the files it imports; this flake only builds it and names the programs
  # it runs (ssh, curl, date, mv, mkdir, mktemp, chmod, sha256sum; and
  # xdg-open, from the desktop, to show Google's sign-in).
  description = "horas: a distributed calendar in Bend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/08d3a97586f6b6343b3b5e799980773629432610";
    # the Bend that ~/src/enc pins (2.0.39)
    bend2.url = "github:bendlang/bend/0ba4e5ec0d3c9e93d653883b9184488468040001";
    bend2.inputs.nixpkgs.follows = "nixpkgs";
    bend-frp.url = "github:hhefesto/bend-frp";
    bend-frp.flake = false;
  };

  outputs = { self, nixpkgs, bend2, bend-frp }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);
    in {
      packages = each (pkgs: system:
        let
          bend = bend2.packages.${system}.default;
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.fileFilter (f: f.hasExt "bend") ./.;
          };
          bin = pkgs.runCommand "horas-bin" { nativeBuildInputs = [ bend ]; } ''
            export HOME=$TMPDIR BEND_NO_TELEMETRY=1
            mkdir -p w/horas w/bend-frp $out/bin
            cp -r ${src}/. w/horas/
            cp ${bend-frp}/Frp.bend w/bend-frp/
            chmod -R u+w w
            cd w/horas
            bend --check-only Main.bend | tee check.log
            grep -q 'ALL PROOFS CHECK' check.log
            bend Main.bend -o $out/bin/horas
          '';
        in {
          default = pkgs.writeShellApplication {
            name = "horas";
            runtimeInputs = [ pkgs.openssh pkgs.coreutils pkgs.curl ];
            text = ''exec ${bin}/bin/horas "$@"'';
          };
        });
    };
}
