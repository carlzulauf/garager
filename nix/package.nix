{
  lib,
  stdenv,
  bundlerEnv,
  defaultGemConfig,
  ruby_4_0,
  makeWrapper,
  openssl,
  pkg-config,
}:

let
  gems = bundlerEnv {
    name = "garager-gems";
    ruby = ruby_4_0;
    gemdir = ../.;
    groups = [ "default" ];
    gemConfig = defaultGemConfig // {
      openssl = attrs: {
        nativeBuildInputs = [ pkg-config ];
        buildInputs = [ openssl ];
      };
    };
  };
in
stdenv.mkDerivation {
  pname = "garager";
  version = builtins.head (
    builtins.match ''.*VERSION = "([^"]+)".*'' (builtins.readFile ../lib/garager/version.rb)
  );

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../bin
      ../config/env.rb
      ../lib
      ../doc/test.jpg
      ../Gemfile
      ../Gemfile.lock
    ];
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ gems.wrappedRuby ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/garager $out/bin
    cp -r . $out/share/garager
    patchShebangs $out/share/garager/bin

    makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/garager \
      --set BUNDLE_WITHOUT development:test \
      --add-flags $out/share/garager/bin/client

    runHook postInstall
  '';

  passthru = { inherit gems; };

  meta = {
    description = "Connects a garage door opener to a control server over a websocket";
    homepage = "https://github.com/carlzulauf/garager";
    license = lib.licenses.mit;
    mainProgram = "garager";
    platforms = lib.platforms.linux;
  };
}
