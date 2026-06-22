{ hostExecutionContext : < AppleHostNative | LinuxOuterContainer >
, hostArchitecture : Text
, toolPaths :
    { docker : Text
    , kubectl : Text
    , helm : Text
    , kind : Text
    , cabal : Text
    , ghc : Text
    , ghcup : Text
    , ormolu : Text
    , hlint : Text
    , npm : Text
    , node : Text
    , python3 : Text
    , poetry : Text
    , protoc : Text
    , git : Text
    , tar : Text
    , curl : Text
    , aptGet : Text
    , brew : Text
    , sudo : Text
    , systemctl : Text
    , mkdir : Text
    , chmod : Text
    , ln : Text
    , install : Text
    , id : Text
    , getent : Text
    , cut : Text
    , dirname : Text
    , bash : Text
    , crictl : Text
    , chown : Text
    , nvidiaSmi : Text
    , nvkind : Text
    , skopeo : Text
    , hostname : Text
    }
, filesystem :
    { repoRoot : Text
    , buildRoot : Text
    , dataRoot : Text
    , runtimeRoot : Text
    , kubeconfigPath : Text
    , secretsRoot : Text
    , homeDirectory : Text
    , kindRoot : Text
    }
, playwrightHost : Text
, controlPlaneContext : Text
}
