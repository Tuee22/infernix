module Infernix.Lint.Chart
  ( runChartLint,
  )
where

import Control.Monad (forM_, unless)
import Infernix.Config (Paths (..), discoverPaths)
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
    "kind/cluster-linux-cuda.yaml"
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
      ["RuntimeClass", "name: nvidia", "handler: nvidia", ".Values.runtimeMode", "linux-cuda"]
    ),
    ("chart/templates/service-demo.yaml", [".Values.demo.enabled", "name: infernix-demo", "targetPort: {{ .Values.demo.port }}"])
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
