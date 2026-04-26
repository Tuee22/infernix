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
    "chart/templates/deployment-edge.yaml",
    "chart/templates/deployment-service.yaml",
    "chart/templates/edge-configmap.yaml",
    "chart/templates/persistentvolumeclaim-service-data.yaml",
    "chart/templates/runtimeclass-nvidia.yaml",
    "chart/templates/service-demo.yaml",
    "chart/templates/service-edge.yaml",
    "chart/templates/workloads-platform-portals.yaml",
    "kind/cluster-apple-silicon.yaml",
    "kind/cluster-linux-cpu.yaml",
    "kind/cluster-linux-cuda.yaml"
  ]

requiredPhrases :: [(FilePath, [String])]
requiredPhrases =
  [ ( "chart/values.yaml",
      [ "runtimeMode:",
        "upstreamCharts:",
        "harbor:",
        "minio:",
        "pulsar:",
        "platformPortals:",
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
        "30080",
        "30650",
        "/api",
        "/harbor",
        "/minio/console",
        "/pulsar/admin",
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
    ("chart/templates/edge-configmap.yaml", ["edge-port", "routes.yaml", ".Values.edge.routes"]),
    ( "chart/templates/deployment-edge.yaml",
      [ "command:",
        "- infernix",
        "args:",
        "- edge",
        "INFERNIX_DEMO_UPSTREAM",
        "INFERNIX_HARBOR_UPSTREAM",
        "INFERNIX_MINIO_UPSTREAM",
        "INFERNIX_PULSAR_UPSTREAM",
        ".Values.demo.enabled"
      ]
    ),
    ( "chart/templates/persistentvolumeclaim-service-data.yaml",
      ["storageClassName:", "infernix.io/workload: service", ".Values.service.dataPvc.name"]
    ),
    ( "chart/templates/runtimeclass-nvidia.yaml",
      ["RuntimeClass", "name: nvidia", "handler: nvidia", ".Values.runtimeMode", "linux-cuda"]
    ),
    ( "chart/templates/workloads-platform-portals.yaml",
      [ "infernix-harbor-gateway",
        "infernix-minio-gateway",
        "infernix-pulsar-gateway",
        "- gateway",
        "- harbor",
        "- minio",
        "- pulsar",
        "INFERNIX_HARBOR_BACKEND_URL",
        "INFERNIX_MINIO_S3_ENDPOINT",
        "INFERNIX_PULSAR_ADMIN_URL"
      ]
    ),
    ("chart/templates/service-demo.yaml", [".Values.demo.enabled", "name: infernix-demo", "targetPort: {{ .Values.demo.port }}"]),
    ("chart/templates/service-edge.yaml", ["type: NodePort", "nodePort:"])
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
