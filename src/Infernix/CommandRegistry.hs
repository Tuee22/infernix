{-# LANGUAGE LambdaCase #-}

module Infernix.CommandRegistry
  ( Command (..),
    documentedCommandLines,
    helpText,
    parseCommand,
    renderCliReferenceCommandsSection,
    renderCliSurfaceFamiliesSection,
    topicHelpText,
  )
where

import Data.Char (toLower)
import Data.List (find)
import Data.Maybe (mapMaybe)
import Data.Text qualified as Text
import Infernix.DhallSchema (DhallSchema, parseDhallSchema)
import Infernix.Types (DaemonRole, RuntimeMode, parseDaemonRole, parseRuntimeMode)

data Command
  = ShowRootHelp
  | ShowTopicHelp String
  | ServiceCommand (Maybe DaemonRole) (Maybe String) (Maybe FilePath)
  | ClusterUpCommand
  | ClusterDownCommand
  | ClusterStatusCommand
  | CacheStatusCommand
  | CacheEvictCommand (Maybe String)
  | CacheRebuildCommand (Maybe String)
  | KubectlCommand [String]
  | DocsCheckCommand
  | LintFilesCommand
  | LintDocsCommand
  | LintProtoCommand
  | LintChartCommand
  | TestLintCommand
  | TestUnitCommand
  | TestIntegrationCommand
  | TestE2ECommand
  | TestAllCommand
  | InternalDiscoverImagesCommand FilePath
  | InternalDiscoverClaimsCommand FilePath
  | InternalDiscoverHarborOverlayCommand FilePath
  | InternalPublishChartImagesCommand FilePath FilePath
  | InternalMaterializeSubstrateCommand RuntimeMode Bool
  | InternalMaterializeMetalEnginesCommand
  | InternalMaterializeLinuxNativeEnginesCommand
  | InternalDemoConfigLoadCommand FilePath
  | InternalDemoConfigValidateCommand FilePath
  | InternalDhallSchemaCommand DhallSchema
  | InternalGeneratePursContractsCommand FilePath
  | InternalPulsarRoundTripCommand FilePath String String
  deriving (Eq, Show)

data CommandFamily = CommandFamily
  { familyTopic :: String,
    familyOverview :: String,
    familyCommands :: [CommandSpec]
  }

data CommandSpec = CommandSpec
  { commandUsageSuffix :: String,
    commandDescription :: String,
    commandParse :: [String] -> Maybe Command
  }

helpText :: String
helpText =
  unlines
    ( [ "infernix COMMAND",
        "",
        "Commands:"
      ]
        <> map (("  " <>) . commandWithPrefix . commandUsageSuffix) allCommandSpecs
    )

topicHelpText :: String -> String
topicHelpText topic =
  case lookupFamily topic of
    Just family ->
      unlines
        ( map
            (commandWithPrefix . commandUsageSuffix)
            (familyCommands family)
        )
    Nothing -> helpText

documentedCommandLines :: [String]
documentedCommandLines =
  map (commandWithPrefix . commandUsageSuffix) allCommandSpecs

renderCliReferenceCommandsSection :: String
renderCliReferenceCommandsSection =
  unlines
    ( ["## `infernix` (production daemon and operator workflow)", ""]
        <> concatMap renderReferenceFamily commandFamilies
    )
  where
    renderReferenceFamily family =
      [ "### `" <> familyTopic family <> "`",
        ""
      ]
        <> map renderReferenceCommand (familyCommands family)
        <> [""]
    renderReferenceCommand commandSpec =
      "- `"
        <> commandWithPrefix (commandUsageSuffix commandSpec)
        <> "` - "
        <> commandDescription commandSpec

renderCliSurfaceFamiliesSection :: String
renderCliSurfaceFamiliesSection =
  unlines
    ( ["## `infernix` Families", ""]
        <> map renderFamilyOverview commandFamilies
    )
  where
    renderFamilyOverview family =
      "- `" <> familyTopic family <> "` - " <> familyOverview family

parseCommand :: [String] -> Either String Command
parseCommand args =
  case args of
    [] -> Right ShowRootHelp
    ["--help"] -> Right ShowRootHelp
    [topic, "--help"]
      | topicSupported topic -> Right (ShowTopicHelp topic)
    _ ->
      case mapMaybe (`commandParse` args) allCommandSpecs of
        command : _ -> Right command
        [] -> Left "Unsupported infernix command"

commandFamilies :: [CommandFamily]
commandFamilies =
  [ serviceCommandFamily,
    clusterCommandFamily,
    cacheCommandFamily,
    kubectlCommandFamily,
    lintCommandFamily,
    testCommandFamily,
    docsCommandFamily,
    internalCommandFamily
  ]

serviceCommandFamily :: CommandFamily
serviceCommandFamily =
  CommandFamily
    { familyTopic = "service",
      familyOverview = "starts the long-running production daemon that consumes Pulsar work and binds no HTTP port",
      familyCommands =
        [ serviceCommandSpec
        ]
    }

-- | `infernix service [--role coordinator|engine] [--engine-name NAME] [--config PATH]`.
-- The optional `--role` arg replaces the retired `INFERNIX_DAEMON_ROLE`
-- env var (Phase 4 Sprint 4.13): coordinator + engine pods each pass
-- the matching role via chart-supplied `args`, while host-native flows
-- omit the flag and fall back to the active substrate dhall's
-- `daemonRole` field. Engine pods or host daemons may pass
-- `--engine-name` to select a stable engine member id from the derived
-- pool/member graph. `--config` is a typed path override used by
-- targeted validation harnesses and operator diagnostics that need an
-- isolated substrate file.
serviceCommandSpec :: CommandSpec
serviceCommandSpec =
  CommandSpec
    { commandUsageSuffix = "service [--role coordinator|engine] [--engine-name NAME] [--config PATH]",
      commandDescription =
        "starts the long-running production daemon; it binds no HTTP port and consumes the active `.dhall` request and result topics. The optional `--role` arg overrides the substrate dhall's `daemonRole` field for split coordinator/engine Deployments, `--engine-name` selects a stable engine member id, and `--config` points the daemon at an explicit substrate file.",
      commandParse = parseServiceCommand
    }

parseServiceCommand :: [String] -> Maybe Command
parseServiceCommand = \case
  "service" : args -> parseServiceArgs Nothing Nothing Nothing args
  _ -> Nothing

parseServiceArgs :: Maybe DaemonRole -> Maybe String -> Maybe FilePath -> [String] -> Maybe Command
parseServiceArgs maybeRole maybeEngineName maybeConfigPath = \case
  [] -> Just (ServiceCommand maybeRole maybeEngineName maybeConfigPath)
  "--role" : rawRole : rest
    | Nothing <- maybeRole,
      Just role <- parseDaemonRole (Text.pack rawRole) ->
        parseServiceArgs (Just role) maybeEngineName maybeConfigPath rest
  "--engine-name" : engineName : rest
    | Nothing <- maybeEngineName ->
        parseServiceArgs maybeRole (Just engineName) maybeConfigPath rest
  "--config" : configPath : rest
    | Nothing <- maybeConfigPath ->
        parseServiceArgs maybeRole maybeEngineName (Just configPath) rest
  _ -> Nothing

clusterCommandFamily :: CommandFamily
clusterCommandFamily =
  CommandFamily
    { familyTopic = "cluster",
      familyOverview = "reconciles or reports cluster state, lifecycle progress, generated substrate publication, and routed surfaces",
      familyCommands =
        [ simpleCommand "cluster up" "reconciles Kind, Harbor-first bootstrap, the generated substrate file, and routed publication state" ClusterUpCommand,
          simpleCommand "cluster down" "tears the cluster down while leaving durable repo-local state under `./.data/` intact" ClusterDownCommand,
          simpleCommand "cluster status" "reports cluster presence, lifecycle phase, active substrate, publication state, build paths, and route inventory; on Linux outer-container paths it may attach the launcher to Docker's `kind` network for observation" ClusterStatusCommand
        ]
    }

cacheCommandFamily :: CommandFamily
cacheCommandFamily =
  CommandFamily
    { familyTopic = "cache",
      familyOverview = "inspects or reconciles manifest-backed derived cache state for the active substrate",
      familyCommands =
        [ simpleCommand "cache status" "reports the manifest-backed cache inventory for the active substrate" CacheStatusCommand,
          optionalModelCommand
            "cache evict [--model MODEL_ID]"
            "evicts derived cache state for one model or for the whole active substrate"
            CacheEvictCommand,
          optionalModelCommand
            "cache rebuild [--model MODEL_ID]"
            "rebuilds derived cache state from durable manifests for one model or for the whole active substrate"
            CacheRebuildCommand
        ]
    }

kubectlCommandFamily :: CommandFamily
kubectlCommandFamily =
  CommandFamily
    { familyTopic = "kubectl",
      familyOverview = "proxies upstream Kubernetes access through the repo-local kubeconfig",
      familyCommands =
        [ CommandSpec
            { commandUsageSuffix = "kubectl ...",
              commandDescription = "wraps upstream `kubectl` and injects the repo-local kubeconfig for the active control-plane context",
              commandParse = \case
                "kubectl" : kubectlArgs -> Just (KubectlCommand kubectlArgs)
                _ -> Nothing
            }
        ]
    }

lintCommandFamily :: CommandFamily
lintCommandFamily =
  CommandFamily
    { familyTopic = "lint",
      familyOverview = "runs the focused Haskell-owned static checks for files, docs, `.proto`, and chart assets",
      familyCommands =
        [ simpleCommand "lint files" "runs the tracked-file and generated-artifact hygiene checks" LintFilesCommand,
          simpleCommand "lint docs" "runs the governed documentation validator" LintDocsCommand,
          simpleCommand "lint proto" "runs the protobuf contract validator" LintProtoCommand,
          simpleCommand "lint chart" "runs the Helm and chart ownership validator" LintChartCommand
        ]
    }

testCommandFamily :: CommandFamily
testCommandFamily =
  CommandFamily
    { familyTopic = "test",
      familyOverview = "runs the aggregate validation entrypoints for lint, unit, integration, routed E2E, and the full suite",
      familyCommands =
        [ simpleCommand "test lint" "runs the focused lint entrypoints together with the strict Haskell style and Python quality gates" TestLintCommand,
          simpleCommand "test unit" "runs the Haskell unit suites and the PureScript frontend unit suites" TestUnitCommand,
          simpleCommand "test integration" "runs the cluster-backed integration suite against the active substrate" TestIntegrationCommand,
          simpleCommand "test e2e" "runs routed Playwright coverage for every demo-visible generated catalog entry" TestE2ECommand,
          simpleCommand "test all" "runs lint, unit, integration, and routed E2E validation in sequence" TestAllCommand
        ]
    }

docsCommandFamily :: CommandFamily
docsCommandFamily =
  CommandFamily
    { familyTopic = "docs",
      familyOverview = "validates the governed documentation suite and the development-plan shape",
      familyCommands =
        [ simpleCommand "docs check" "runs the canonical documentation validator" DocsCheckCommand
        ]
    }

internalCommandFamily :: CommandFamily
internalCommandFamily =
  CommandFamily
    { familyTopic = "internal",
      familyOverview = "runs build-time helpers for contract generation, chart discovery, substrate materialization, demo-config inspection, and Pulsar round-trip validation",
      familyCommands =
        [ singlePathCommand
            "internal generate-purs-contracts PATH"
            "emits generated PureScript browser contracts into the requested output directory"
            InternalGeneratePursContractsCommand
            ["internal", "generate-purs-contracts"],
          singlePathCommand
            "internal discover images RENDERED_CHART"
            "prints the unique image references discovered in a rendered chart manifest"
            InternalDiscoverImagesCommand
            ["internal", "discover", "images"],
          singlePathCommand
            "internal discover claims RENDERED_CHART"
            "prints the persistent-claim inventory discovered in a rendered chart manifest"
            InternalDiscoverClaimsCommand
            ["internal", "discover", "claims"],
          singlePathCommand
            "internal discover harbor-overlay OVERLAY"
            "prints the Harbor-backed image references discovered in a rendered override payload"
            InternalDiscoverHarborOverlayCommand
            ["internal", "discover", "harbor-overlay"],
          twoPathCommand
            "internal publish-chart-images RENDERED_CHART OUTPUT"
            "publishes the chart image inventory into a Harbor override file"
            InternalPublishChartImagesCommand
            ["internal", "publish-chart-images"],
          materializeSubstrateCommand,
          simpleCommand
            "internal materialize-metal-engines"
            "materializes the allowlisted Apple Metal/Core ML engine manifests under `./.data/engines/<adapterId>/` through the Tart-free headless host lane (Apple-only; mirrors `internal materialize-substrate`)"
            InternalMaterializeMetalEnginesCommand,
          simpleCommand
            "internal materialize-linux-native-engines"
            "materializes the allowlisted Linux native runner roots under `/opt/infernix/engines/<adapterId>/` for substrate images"
            InternalMaterializeLinuxNativeEnginesCommand,
          singlePathCommand
            "internal demo-config load PATH"
            "loads one generated demo config and prints the rendered model listing"
            InternalDemoConfigLoadCommand
            ["internal", "demo-config", "load"],
          singlePathCommand
            "internal demo-config validate PATH"
            "validates one generated demo config file"
            InternalDemoConfigValidateCommand
            ["internal", "demo-config", "validate"],
          dhallSchemaCommand,
          pulsarRoundTripCommand
        ]
    }

materializeSubstrateCommand :: CommandSpec
materializeSubstrateCommand =
  CommandSpec
    { commandUsageSuffix = "internal materialize-substrate RUNTIME_MODE [--demo-ui true|false]",
      commandDescription = "writes the generated substrate file for one explicit substrate id into the active build root",
      commandParse = \case
        ["internal", "materialize-substrate", rawRuntimeMode] ->
          flip InternalMaterializeSubstrateCommand True
            <$> parseRuntimeModeArg rawRuntimeMode
        ["internal", "materialize-substrate", rawRuntimeMode, "--demo-ui", rawDemoUiEnabled] ->
          InternalMaterializeSubstrateCommand
            <$> parseRuntimeModeArg rawRuntimeMode
            <*> parseDemoUiArg rawDemoUiEnabled
        _ -> Nothing
    }

pulsarRoundTripCommand :: CommandSpec
pulsarRoundTripCommand =
  CommandSpec
    { commandUsageSuffix = "internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT",
      commandDescription = "publishes one inference request through Pulsar and waits for the matching result",
      commandParse = \case
        ["internal", "pulsar-roundtrip", demoConfigPath, modelIdValue, inputTextValue] ->
          Just (InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue)
        _ -> Nothing
    }

dhallSchemaCommand :: CommandSpec
dhallSchemaCommand =
  CommandSpec
    { commandUsageSuffix = "internal dhall-schema host|cluster|secrets|substrate",
      commandDescription = "prints the Dhall type expression reflected from the binary's decoder for one packaged schema",
      commandParse = \case
        ["internal", "dhall-schema", rawSchema] ->
          InternalDhallSchemaCommand <$> parseDhallSchema rawSchema
        _ -> Nothing
    }

allCommandSpecs :: [CommandSpec]
allCommandSpecs = concatMap familyCommands commandFamilies

lookupFamily :: String -> Maybe CommandFamily
lookupFamily topic = find ((== topic) . familyTopic) commandFamilies

topicSupported :: String -> Bool
topicSupported topic =
  case lookupFamily topic of
    Just _ -> True
    Nothing -> False

simpleCommand :: String -> String -> Command -> CommandSpec
simpleCommand usageSuffix description commandValue =
  CommandSpec
    { commandUsageSuffix = usageSuffix,
      commandDescription = description,
      commandParse = \args ->
        if words usageSuffix == args
          then Just commandValue
          else Nothing
    }

optionalModelCommand :: String -> String -> (Maybe String -> Command) -> CommandSpec
optionalModelCommand usageSuffix description constructor =
  let prefix = take 2 (words usageSuffix)
   in CommandSpec
        { commandUsageSuffix = usageSuffix,
          commandDescription = description,
          commandParse = \case
            args
              | args == prefix -> Just (constructor Nothing)
            [prefixOne, prefixTwo, "--model", modelIdValue]
              | [prefixOne, prefixTwo] == prefix -> Just (constructor (Just modelIdValue))
            _ -> Nothing
        }

singlePathCommand :: String -> String -> (FilePath -> Command) -> [String] -> CommandSpec
singlePathCommand usageSuffix description constructor prefix =
  CommandSpec
    { commandUsageSuffix = usageSuffix,
      commandDescription = description,
      commandParse = \case
        args
          | take (length prefix) args == prefix,
            [pathValue] <- drop (length prefix) args ->
              Just (constructor pathValue)
        _ -> Nothing
    }

twoPathCommand :: String -> String -> (FilePath -> FilePath -> Command) -> [String] -> CommandSpec
twoPathCommand usageSuffix description constructor prefix =
  CommandSpec
    { commandUsageSuffix = usageSuffix,
      commandDescription = description,
      commandParse = \case
        args
          | take (length prefix) args == prefix,
            [leftPath, rightPath] <- drop (length prefix) args ->
              Just (constructor leftPath rightPath)
        _ -> Nothing
    }

commandWithPrefix :: String -> String
commandWithPrefix commandSuffix = "infernix " <> commandSuffix

parseRuntimeModeArg :: String -> Maybe RuntimeMode
parseRuntimeModeArg =
  parseRuntimeMode . Text.pack

parseDemoUiArg :: String -> Maybe Bool
parseDemoUiArg rawValue =
  case map toLower rawValue of
    "true" -> Just True
    "false" -> Just False
    "on" -> Just True
    "off" -> Just False
    _ -> Nothing
