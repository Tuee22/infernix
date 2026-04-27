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
    "chart/templates/gateway.yaml",
    "chart/templates/gatewayclass.yaml",
    "chart/templates/httproutes/demo-api.yaml",
    "chart/templates/httproutes/demo-objects.yaml",
    "chart/templates/httproutes/demo-root.yaml",
    "chart/templates/httproutes/harbor-api.yaml",
    "chart/templates/httproutes/harbor-portal.yaml",
    "chart/templates/httproutes/minio-console.yaml",
    "chart/templates/httproutes/minio-s3.yaml",
    "chart/templates/httproutes/pulsar-admin.yaml",
    "chart/templates/httproutes/pulsar-ws.yaml",
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
        "demo:",
        "enabled:",
        "catalogPayload:",
        "demo_ui",
        "request_topics",
        "result_topic",
        "adapterId",
        "pythonNative",
        "publication:",
        "engineAdapters:",
        "commandEnv:",
        "30002",
        "30011",
        "30650",
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
    ( "chart/templates/gatewayclass.yaml",
      ["GatewayClass", "name: infernix-gateway", "gateway.envoyproxy.io/gatewayclass-controller"]
    ),
    ( "chart/templates/gateway.yaml",
      [ "kind: Gateway",
        "name: infernix-edge",
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
    ( "chart/templates/httproutes/demo-root.yaml",
      ["HTTPRoute", "name: infernix-demo-root", ".Values.demo.enabled", "infernix.io/purpose: Demo workbench", "value: /", "backendRefs:"]
    ),
    ( "chart/templates/httproutes/demo-api.yaml",
      ["HTTPRoute", "name: infernix-demo-api", ".Values.demo.enabled", "infernix.io/purpose: Demo API", "value: /api", "name: infernix-demo"]
    ),
    ( "chart/templates/httproutes/demo-objects.yaml",
      ["HTTPRoute", "name: infernix-demo-objects", ".Values.demo.enabled", "infernix.io/purpose: Demo object store", "value: /objects", "name: infernix-demo"]
    ),
    ( "chart/templates/httproutes/harbor-api.yaml",
      ["HTTPRoute", "name: infernix-harbor-api", "infernix.io/purpose: Harbor API", "value: /harbor/api", "URLRewrite", "replacePrefixMatch: /api", "name: infernix-harbor-core"]
    ),
    ( "chart/templates/httproutes/harbor-portal.yaml",
      ["HTTPRoute", "name: infernix-harbor-portal", "infernix.io/purpose: Harbor portal", "value: /harbor", "URLRewrite", "replacePrefixMatch: /", "name: infernix-harbor-portal"]
    ),
    ( "chart/templates/httproutes/minio-console.yaml",
      ["HTTPRoute", "name: infernix-minio-console", "infernix.io/purpose: MinIO console", "value: /minio/console", "replacePrefixMatch: /", "name: infernix-minio-console"]
    ),
    ( "chart/templates/httproutes/minio-s3.yaml",
      ["HTTPRoute", "name: infernix-minio-s3", "infernix.io/purpose: MinIO S3 API", "value: /minio/s3", "replacePrefixMatch: /", "name: infernix-minio"]
    ),
    ( "chart/templates/httproutes/pulsar-admin.yaml",
      ["HTTPRoute", "name: infernix-pulsar-admin", "infernix.io/purpose: Pulsar admin surface", "value: /pulsar/admin", "replacePrefixMatch: /", "name: infernix-infernix-pulsar-proxy"]
    ),
    ( "chart/templates/httproutes/pulsar-ws.yaml",
      ["HTTPRoute", "name: infernix-pulsar-ws", "infernix.io/purpose: Pulsar websocket surface", "value: /pulsar/ws", "replacePrefixMatch: /", "name: infernix-infernix-pulsar-proxy"]
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
