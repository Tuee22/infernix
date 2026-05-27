module Infernix.Lint.Chart
  ( runChartLint,
  )
where

import Control.Monad (forM_, unless, when)
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.Routes (renderChartRouteRegistryCommentSection)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

requiredFiles :: [FilePath]
requiredFiles =
  [ "chart/Chart.yaml",
    "chart/values.yaml",
    "chart/templates/configmap-demo-catalog.yaml",
    "chart/templates/configmap-publication-state.yaml",
    "chart/templates/deployment-coordinator.yaml",
    "chart/templates/deployment-demo.yaml",
    "chart/templates/deployment-engine.yaml",
    "chart/templates/envoyproxy.yaml",
    "chart/templates/gateway.yaml",
    "chart/templates/gatewayclass.yaml",
    "chart/templates/httproutes.yaml",
    "chart/templates/runtimeclass-nvidia.yaml",
    "chart/templates/service-demo.yaml",
    "kind/cluster-apple-silicon.yaml",
    "kind/cluster-linux-cpu.yaml",
    "kind/cluster-linux-gpu.yaml"
  ]

requiredPhrases :: [(FilePath, [String])]
requiredPhrases =
  [ ( "chart/values.yaml",
      [ "runtimeMode:",
        "upstreamCharts:",
        "envoyGateway:",
        "harbor:",
        "minio:",
        "pulsar:",
        "gateway:",
        "repoGateway:",
        "routes:",
        "demo:",
        "enabled:",
        "catalogPayload:",
        "publication:",
        "engineAdapters:",
        "commandEnv:",
        "service:",
        "enabled:",
        "30002",
        "30011",
        "30650",
        "webSocketServiceEnabled: \"true\"",
        "storageClass: infernix-manual",
        "storageClassName: infernix-manual"
      ]
    ),
    -- Phase 7 Sprint 7.17: the demo Deployment's `INFERNIX_MINIO_ACCESS_KEY`
    -- / `INFERNIX_MINIO_SECRET_KEY` entries retire together with the
    -- `cluster-secrets` Secret mount at `/etc/infernix/secrets/`.
    -- Phase 6 Sprint 6.28 follow-on (May 26, 2026): the data-root
    -- override env entry retired too; `dataRoot` decodes from the
    -- mounted host manifest.
    ( "chart/templates/deployment-demo.yaml",
      [ ".Values.demo.enabled",
        "name: infernix-demo",
        "- infernix-demo",
        "--dhall",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "emptyDir: {}"
      ]
    ),
    ( "chart/templates/envoyproxy.yaml",
      [ ".Values.repoGateway.enabled",
        "kind: EnvoyProxy",
        "name: infernix-edge",
        "type: NodePort",
        "externalTrafficPolicy: Cluster",
        ".Values.gateway.publishedNodePort"
      ]
    ),
    ( "chart/templates/gatewayclass.yaml",
      [ ".Values.repoGateway.enabled",
        "GatewayClass",
        "name: infernix-gateway",
        "gateway.envoyproxy.io/gatewayclass-controller"
      ]
    ),
    ( "chart/templates/gateway.yaml",
      [ ".Values.repoGateway.enabled",
        "kind: Gateway",
        "name: infernix-edge",
        "parametersRef:",
        "kind: EnvoyProxy",
        ".Values.gateway.listenerPort",
        "allowedRoutes:",
        "from: Same"
      ]
    ),
    -- Phase 7 Sprint 7.7: the supported split topology routes engine
    -- runtime-class + GPU resource shape through
    -- `chart/templates/deployment-engine.yaml`. The legacy
    -- `chart/templates/deployment-service.yaml` is retired together
    -- with the fused `service.*` Deployment.
    --
    -- Phase 4 Sprint 4.13: `INFERNIX_PULSAR_*` + `INFERNIX_DAEMON_*`
    -- env families retired; the daemon now reads them from
    -- `cluster.dhall` mounted from `ConfigMap/{{ .Values.clusterConfig.name }}`
    -- and `--role coordinator|engine` is the typed CLI arg that
    -- replaces `INFERNIX_DAEMON_ROLE`.
    ( "chart/templates/deployment-engine.yaml",
      [ ".Values.engine.enabled",
        "demoConfig.mountPath",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "- --role",
        "- engine",
        "runtimeClassName: nvidia",
        "infernix.runtime/gpu",
        "nvidia.com/gpu"
      ]
    ),
    ( "chart/templates/deployment-coordinator.yaml",
      [ ".Values.coordinator.enabled",
        ".Values.clusterConfig.name",
        "name: cluster-config",
        "mountPath: /opt/infernix/cluster.dhall",
        "name: cluster-secrets",
        "mountPath: /etc/infernix/secrets",
        "secretName: infernix-cluster-secrets",
        "- --role",
        "- coordinator"
      ]
    ),
    ( "chart/templates/secret-cluster-secrets.yaml",
      [ "kind: Secret",
        "name: infernix-cluster-secrets",
        "InfernixSecrets.dhall:",
        "minio.json:",
        "keycloak-admin.json:",
        "keycloak-db.json:",
        "{ \"accessKey\":"
      ]
    ),
    ( "chart/templates/configmap-cluster-config.yaml",
      [ ".Values.clusterConfig.name",
        "cluster.dhall:",
        "{ pulsar =",
        ", minio =",
        ", keycloak =",
        ", demoBackend =",
        ", engine =",
        ", coordinator ="
      ]
    ),
    ( "chart/templates/httproutes.yaml",
      [ ".Values.repoGateway.enabled",
        ".Values.routes",
        ".Values.demo.enabled",
        "kind: HTTPRoute",
        "infernix.io/purpose:",
        "value: {{ $route.pathPrefix }}",
        "name: {{ $route.serviceName }}",
        "replacePrefixMatch: {{ $route.rewritePrefix }}"
      ]
    ),
    ( "chart/templates/runtimeclass-nvidia.yaml",
      ["RuntimeClass", "name: nvidia", "handler: nvidia", ".Values.runtimeMode", "linux-gpu"]
    ),
    ("chart/templates/service-demo.yaml", [".Values.demo.enabled", "name: infernix-demo", "targetPort: {{ .Values.demo.port }}"])
  ]

data GeneratedSectionRule = GeneratedSectionRule
  { generatedSectionPath :: FilePath,
    generatedSectionStartMarker :: String,
    generatedSectionEndMarker :: String,
    generatedSectionExpected :: String
  }

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules =
  [ GeneratedSectionRule
      { generatedSectionPath = "chart/templates/httproutes.yaml",
        generatedSectionStartMarker = "{{/* infernix:route-registry:start */}}",
        generatedSectionEndMarker = "{{/* infernix:route-registry:end */}}",
        generatedSectionExpected = trimTrailingNewlines renderChartRouteRegistryCommentSection
      }
  ]

runChartLint :: IO ()
runChartLint = do
  paths <- discoverPaths
  forM_ requiredFiles $ \relativePath -> do
    exists <- doesFileExist (repoRoot paths </> relativePath)
    unless exists $
      ioError (userError ("missing required platform asset: " <> relativePath))
  forM_ requiredPhrases $ \(relativePath, phrases) -> do
    contents <- readFile (repoRoot paths </> relativePath)
    forM_ phrases $ \requiredPhrase ->
      unless (requiredPhrase `contains` contents) $
        ioError (userError (relativePath <> " is missing required phrase: " <> requiredPhrase))
  forM_ generatedSectionRules $ \rule -> do
    contents <- readFile (repoRoot paths </> generatedSectionPath rule)
    validateGeneratedSection rule contents
  forM_ envBlockRejectionPaths $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    forM_ (lines contents) $ \lineValue ->
      when
        (isEnvBlockStartLine lineValue)
        ( ioError
            ( userError
                ( relativePath
                    <> ": Phase 6 Sprint 6.28 chart lint gate rejects `env:` blocks "
                    <> "in infernix-owned deployment templates. The supported flow reads "
                    <> "runtime wiring from the mounted `cluster.dhall` ConfigMap and "
                    <> "credentials from the mounted `infernix-cluster-secrets` Secret. "
                    <> "Found `env:` at: "
                    <> lineValue
                )
            )
        )

-- | Phase 6 Sprint 6.28 follow-on (May 26, 2026): the chart lint
-- gate rejects new @env:@ blocks in the three infernix-owned
-- daemon deployment templates. Runtime wiring must flow through
-- the mounted @cluster.dhall@ ConfigMap; credentials must flow
-- through the mounted @infernix-cluster-secrets@ Secret. Comments
-- mentioning @env:@ are fine — the check only looks at top-level
-- pod-spec @env:@ lines (whitespace + @env:@).
envBlockRejectionPaths :: [FilePath]
envBlockRejectionPaths =
  [ "chart/templates/deployment-coordinator.yaml",
    "chart/templates/deployment-engine.yaml",
    "chart/templates/deployment-demo.yaml"
  ]

-- | Whether a single chart-template line starts an @env:@ block.
-- Matches the canonical pod-spec position (leading whitespace, then
-- the literal @env:@, optionally trailing whitespace). Comment lines
-- starting with @#@ are skipped.
isEnvBlockStartLine :: String -> Bool
isEnvBlockStartLine lineValue =
  let leadingTrimmed = dropWhile (`elem` (" \t" :: String)) lineValue
   in isEnvBlockTrimmed leadingTrimmed

isEnvBlockTrimmed :: String -> Bool
isEnvBlockTrimmed ('#' : _) = False
isEnvBlockTrimmed trimmed = dropTrailingWhitespace trimmed == "env:"

dropTrailingWhitespace :: String -> String
dropTrailingWhitespace = reverse . dropWhile (`elem` (" \t\r" :: String)) . reverse

contains :: String -> String -> Bool
contains needle haystack = any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (expected : expectedRest) (actual : actualRest) =
  expected == actual && prefixOf expectedRest actualRest

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_ : rest) = value : tails rest

validateGeneratedSection :: GeneratedSectionRule -> String -> IO ()
validateGeneratedSection rule contents =
  case extractGeneratedSection (generatedSectionStartMarker rule) (generatedSectionEndMarker rule) contents of
    Nothing ->
      ioError
        ( userError
            ( generatedSectionPath rule
                <> " is missing the generated section markers "
                <> generatedSectionStartMarker rule
                <> " and "
                <> generatedSectionEndMarker rule
            )
        )
    Just renderedSection ->
      unless
        (trimTrailingNewlines renderedSection == generatedSectionExpected rule)
        ( ioError
            ( userError
                ( generatedSectionPath rule
                    <> " has drifted from the Haskell route registry generated section"
                )
            )
        )

extractGeneratedSection :: String -> String -> String -> Maybe String
extractGeneratedSection startMarker endMarker contents = do
  let contentLines = lines contents
  startIndex <- findLineIndex startMarker contentLines
  endIndex <- findLineIndex endMarker contentLines
  if endIndex <= startIndex
    then Nothing
    else Just (unlines (take (endIndex - startIndex - 1) (drop (startIndex + 1) contentLines)))

findLineIndex :: String -> [String] -> Maybe Int
findLineIndex target = go 0
  where
    go _ [] = Nothing
    go index (lineValue : remaining)
      | lineValue == target = Just index
      | otherwise = go (index + 1) remaining

trimTrailingNewlines :: String -> String
trimTrailingNewlines =
  reverse . dropWhile (`elem` ['\n', '\r']) . reverse
