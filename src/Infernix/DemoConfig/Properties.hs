{-# LANGUAGE OverloadedStrings #-}

module Infernix.DemoConfig.Properties
  ( runColimaPledgeParserProperties,
    runDemoConfigParserProperties,
  )
where

import Control.Exception (IOException, try)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isLeft)
import Infernix.Config (Paths (buildRoot))
import Infernix.DemoConfig.Colima (colimaPledgeMibFromJsonLines)
import Infernix.DemoConfig.Internal
  ( decodeBootstrapDemoConfigFile,
    decodeDemoConfigFile,
    renderGeneratedDemoConfigPayload,
    validateDemoConfig,
  )
import Infernix.Models (encodeDemoConfig)
import Infernix.Types
  ( DaemonRole (Coordinator, Engine),
    DemoConfig (..),
    HostMemoryPartition,
    InferenceMemoryBudget (HostEnforcedBudget, SubstrateEnforcedBudget),
    InferenceMemoryResource (PodRam),
    PodMemoryLimit (..),
    PodMemoryLimitSource (..),
    RuntimeMode (AppleSilicon, LinuxCpu),
    hostPartitionForCapacity,
  )
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

runColimaPledgeParserProperties :: IO ()
runColimaPledgeParserProperties = do
  assertEqual
    "multiple active profiles are summed before a single MiB round-up"
    (Right 4)
    ( colimaPledgeMibFromJsonLines
        ( unlines
            [ profile "default" "Running" 1048576,
              profile "build" "Running" 2097153
            ]
        )
    )
  assertEqual
    "an explicitly stopped profile contributes zero"
    (Right 0)
    (colimaPledgeMibFromJsonLines (profile "default" "Stopped" 8589934592))
  assertEqual
    "transitional and unknown statuses are counted conservatively"
    (Right 3)
    ( colimaPledgeMibFromJsonLines
        ( unlines
            [ profile "starting" "Starting" 1048576,
              profile "future" "FutureState" 1048577
            ]
        )
    )
  mapM_
    ( \(label, payload) ->
        assert
          (isLeft (colimaPledgeMibFromJsonLines payload))
          label
    )
    [ ("malformed JSON fails closed", "{not-json"),
      ("negative memory fails closed", profile "default" "Running" (-1)),
      ("a blank profile name fails closed", profile " " "Running" 1048576),
      ("a blank profile status fails closed", profile "default" " " 1048576),
      ( "an aggregate outside the Int MiB domain fails closed",
        profile
          "overflow"
          "Running"
          ((toInteger (maxBound :: Int) + 1) * bytesPerMib)
      ),
      ("blank output fails closed", " \n\t\n")
    ]
  putStrLn "Colima memory-pledge parser properties passed"

runDemoConfigParserProperties :: Paths -> IO ()
runDemoConfigParserProperties paths = do
  let propertyRoot = buildRoot paths </> "demo-config-parser-properties"
      linuxConfigPath = propertyRoot </> "linux-cpu.dhall"
      emptyConfigPath = propertyRoot </> "linux-cpu-empty.dhall"
      appleConfigPath = propertyRoot </> "apple-silicon.dhall"
      linuxBudget =
        SubstrateEnforcedBudget
          PodMemoryLimit
            { podMemoryLimitResource = PodRam,
              podMemoryLimitSource = ClusterEnginePodMemoryLimit,
              podMemoryLimitMib = 65536
            }
      appleBudget = HostEnforcedBudget (requireHostPartition 65536)
  createDirectoryIfMissing True propertyRoot
  ByteString.writeFile
    linuxConfigPath
    (renderGeneratedDemoConfigPayload paths LinuxCpu True Coordinator linuxBudget)
  linuxConfig <- decodeDemoConfigFile linuxConfigPath
  assert
    (configRuntimeMode linuxConfig == LinuxCpu && not (null (models linuxConfig)))
    "the private strict parser accepts a generated Linux CPU config"
  LazyByteString.writeFile
    emptyConfigPath
    (encodeDemoConfig linuxConfig {models = []})
  strictEmptyResult <-
    try (decodeDemoConfigFile emptyConfigPath) ::
      IO (Either IOException DemoConfig)
  assert
    (isLeft strictEmptyResult)
    "the private strict parser rejects an empty model catalog"
  bootstrapConfig <- decodeBootstrapDemoConfigFile emptyConfigPath
  assert
    (configRuntimeMode bootstrapConfig == LinuxCpu && null (models bootstrapConfig))
    "the private bootstrap parser accepts an explicitly empty image catalog"
  ByteString.writeFile
    appleConfigPath
    (renderGeneratedDemoConfigPayload paths AppleSilicon True Engine appleBudget)
  appleConfig <- decodeDemoConfigFile appleConfigPath
  mapM_
    ( \(label, capacityMib) ->
        assert
          ( isRight
              ( validateDemoConfig
                  False
                  ( appleConfig
                      { inferenceMemoryBudget =
                          HostEnforcedBudget (requireHostPartition capacityMib)
                      }
                  )
              )
          )
          label
    )
    -- Phase 4 Sprint 4.34 removed the zero-capacity row: a zero-capacity
    -- partition is no longer constructible, because a daemon that starts and
    -- can answer nothing is a worse failure than one that refuses to start.
    [ ("the private validator accepts a fitting host budget", 65536),
      ("the private validator leaves per-model admission to the compiler", 512)
    ]
  putStrLn "private demo-config parser properties passed"

requireHostPartition :: Int -> HostMemoryPartition
requireHostPartition capacityMib =
  case hostPartitionForCapacity capacityMib of
    Left partitionError ->
      error ("invalid parser-property host partition: " <> partitionError)
    Right partition -> partition

isRight :: Either error value -> Bool
isRight value =
  case value of
    Left _ -> False
    Right _ -> True

profile :: String -> String -> Integer -> String
profile profileName status memoryBytes =
  "{\"name\":"
    <> show profileName
    <> ",\"status\":"
    <> show status
    <> ",\"memory\":"
    <> show memoryBytes
    <> "}"

bytesPerMib :: Integer
bytesPerMib = 1048576

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  assert
    (actual == expected)
    (label <> ": expected " <> show expected <> ", got " <> show actual)

assert :: Bool -> String -> IO ()
assert condition message =
  if condition
    then pure ()
    else fail message
