module Infernix.Lint.Chart
  ( runChartLint,
  )
where

import Control.Monad (forM_, unless)
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
    "chart/templates/deployment-demo.yaml",
    "chart/templates/deployment-service.yaml",
    "chart/templates/envoyproxy.yaml",
    "chart/templates/gateway.yaml",
    "chart/templates/gatewayclass.yaml",
    "chart/templates/httproutes.yaml",
    "chart/templates/persistentvolumeclaim-service-data.yaml",
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
        "30002",
        "30011",
        "30650",
        "webSocketServiceEnabled: \"true\"",
        "storageClass: infernix-manual",
        "storageClassName: infernix-manual"
      ]
    ),
    ( "chart/templates/deployment-demo.yaml",
      [ ".Values.demo.enabled",
        "name: infernix-demo",
        "- infernix-demo",
        "--dhall",
        "INFERNIX_PUBLICATION_STATE_PATH",
        "INFERNIX_DATA_ROOT",
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
    ( "chart/templates/deployment-service.yaml",
      [ "demoConfig.mountPath",
        "INFERNIX_DEMO_CONFIG_PATH",
        "INFERNIX_PUBLICATION_STATE_PATH",
        "INFERNIX_MINIO_ENDPOINT",
        "INFERNIX_PULSAR_ADMIN_URL",
        "INFERNIX_PULSAR_WS_BASE_URL",
        ".Values.service.engineAdapters.commandEnv",
        "runtimeClassName: nvidia",
        "infernix.runtime/gpu",
        "nvidia.com/gpu"
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
    ( "chart/templates/persistentvolumeclaim-service-data.yaml",
      ["storageClassName:", "infernix.io/workload: service", ".Values.service.dataPvc.name"]
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
