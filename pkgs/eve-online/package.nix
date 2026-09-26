{
  coreutils,
  winePrefix ? null,
  grabPointer ? null,
  extraEnvironment ? { },
  fetchurl,
  icoutils,
  lib,
  makeDesktopItem,
  proton-ge-bin,
  protonPackage ? proton-ge-bin,
  runCommand,
  symlinkJoin,
  umu-launcher,
  writeShellApplication,
}:

let
  pname = "eve-online";
  version = "1.16.1";
  reservedEnvironmentNames = [
    "WINEPREFIX"
    "EVE_WINEPREFIX"
    "EVE_GRAB_POINTER"
    "STEAM_COMPAT_INSTALL_PATH"
    "PROTONPATH"
  ];
  validEnvironmentName =
    name:
    builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null
    && !(builtins.elem name reservedEnvironmentNames);
  defaultEnvironment = {
    GAMEID = "umu-default";
    STORE = "none";
    UMU_CONTAINER_NSENTER = "1";
    PROTONFIXES_DISABLE = "1";
    PROTON_USE_XALIA = "0";
  };
  # extraEnvironment values are defaults the caller's environment can
  # override; defaultEnvironment values are always forced. Variables named in
  # extraEnvironment are also kept rather than cleared.
  environmentToClear = builtins.filter (name: !(builtins.hasAttr name extraEnvironment)) [
    "PROTON_VERB"
    "STEAM_COMPAT_LAUNCHER_SERVICE"
    "UMU_CONTAINER_NSENTER"
    "UMU_CONTAINER_NSENTER_CREATE"
    "UMU_CONTAINER_NSENTER_REQUIRED"
  ];
  environmentExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      if builtins.hasAttr name extraEnvironment then
        ''
          if [[ ! -v ${name} ]]; then
            export ${name}=${lib.escapeShellArg value}
          fi
        ''
      else
        "export ${name}=${lib.escapeShellArg value}"
    ) (defaultEnvironment // extraEnvironment)
  );

  installer = fetchurl {
    url = "https://launcher.ccpgames.com/eve-online/release/win32/x64/eve-online-${version}+Setup.exe";
    name = "eve-online-${version}+Setup.exe";
    hash = "sha256-feTzI01T8nYVoBJviwIvrLZooitEYzNP/jcNk5LgLOc=";
  };

  launcherIcon = runCommand "${pname}-icon-${version}" { nativeBuildInputs = [ icoutils ]; } ''
    iconPath="$out/share/icons/hicolor/256x256/apps/${pname}.png"
    mkdir -p "$(dirname "$iconPath")"
    wrestool --extract --raw --type=3 --name=19 --output="$iconPath" ${lib.escapeShellArg installer}
  '';

  launcher = writeShellApplication {
    name = pname;
    runtimeInputs = [
      coreutils
      umu-launcher
    ];
    text = ''
      default_prefix=${
        if winePrefix == null then ''"$HOME/Games/eve-online"'' else lib.escapeShellArg winePrefix
      }
      default_grab_pointer=${
        lib.escapeShellArg (lib.optionalString (grabPointer != null) (if grabPointer then "Y" else "N"))
      }
      packaged_proton=${lib.escapeShellArg protonPackage.steamcompattool}
      installer=${lib.escapeShellArg installer}

      # Exports the package's environment. Inherited launch settings are cleared
      # unless explicitly configured through extraEnvironment, so UMU can choose
      # the verb and reuse this prefix's container.
      apply_package_environment() {
        ${lib.optionalString (
          environmentToClear != [ ]
        ) "unset ${lib.concatStringsSep " " environmentToClear}"}
        ${lib.optionalString (!(extraEnvironment ? WINEDLLOVERRIDES)) ''
          export WINEDLLOVERRIDES="winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
        ''}
        ${environmentExports}
      }

    ''
    + builtins.readFile ./launcher.sh;
  };

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "EVE Online";
    genericName = "EVE Online Launcher";
    comment = "EVE Online launcher";
    exec = "${launcher}/bin/${pname}";
    icon = pname;
    categories = [ "Game" ];
    startupNotify = true;
  };
in
assert lib.assertMsg (
  protonPackage ? steamcompattool
) "protonPackage must provide a steamcompattool path";
assert lib.assertMsg (
  winePrefix == null || lib.hasPrefix "/" winePrefix
) "winePrefix must be an absolute path";
assert lib.assertMsg (
  grabPointer == null || builtins.isBool grabPointer
) "grabPointer must be null or a boolean";
assert lib.assertMsg (builtins.all validEnvironmentName (builtins.attrNames extraEnvironment))
  "extraEnvironment needs valid shell variable names; use dedicated overrides for reserved variables";
assert lib.assertMsg (builtins.all builtins.isString (
  builtins.attrValues extraEnvironment
)) "extraEnvironment values must be strings";
symlinkJoin {
  inherit pname version;
  paths = [
    launcher
    launcherIcon
    desktopItem
  ];

  meta = {
    description = "EVE Online launcher using UMU and Proton";
    homepage = "https://www.eveonline.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
