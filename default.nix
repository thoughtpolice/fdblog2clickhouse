{ nixpkgs ? null
, src ? builtins.fetchGit ./.
, official-release ? false
}:

with builtins;

let
  config = {
    packageOverrides = pkgs: with pkgs; {};
  };

  pkgs = import (if nixpkgs != null then nixpkgs else fetchTarball {
    url    = "https://github.com/nixos/nixpkgs-channels/archive/bc94dcf500286495e3c478a9f9322debc94c4304.tar.gz";
    sha256 = "1siqklf863181fqk19d0x5cd0xzxf1w0zh08lv0l0dmjc8xic64a";
  }) { inherit config; };

  versionBase   = pkgs.lib.fileContents ./.version;
  versionSuffix = pkgs.lib.optionalString (!official-release)
    "pre${toString src.revCount}_${src.shortRev}";
  version = "${versionBase}${versionSuffix}";

  jobs = rec {
    entrypoint = pkgs.writers.writeBashBin "entrypoint" (readFile ./entrypoint.sh);

    ## needed for container/host resolution
    nsswitch-conf = pkgs.writeTextFile {
      name = "nsswitch.conf";
      text = "hosts: dns files";
      destination = "/etc/nsswitch.conf";
    };

    trace-converter = pkgs.callPackage ({ stdenv, python3, python3Packages }:
      with python3Packages; stdenv.mkDerivation {
        pname = "trace-convert";
        inherit version;
        src = ./trace-converter.py;

        nativeBuildInputs = [ wrapPython ];
        pythonPath = [ python3 requests pandas ];

        unpackPhase = ":";
        installPhase = ''
          mkdir -p $out/bin
          cp -v ${./trace-converter.py} $out/bin/trace-convert
          chmod +x $out/bin/trace-convert
          wrapPythonPrograms
        '';
      }
    ) {};

    docker =
      pkgs.dockerTools.buildLayeredImage {
        name = "fdblog2clickhouse";
        tag  = version;

        contents = with pkgs; with python3Packages;
          [ iana-etc cacert tzdata nsswitch-conf
            inotifyTools coreutils bash gawk
            entrypoint trace-converter
          ];

        config = {
          Entrypoint = [ "/bin/entrypoint" ];
          WorkingDir = "/logs";
          Volumes = { "/logs" = {}; };
        };
      };
  };
in jobs
