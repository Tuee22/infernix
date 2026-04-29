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

import Data.List (find)
import Data.Maybe (mapMaybe)

data Command
  = ShowRootHelp
  | ShowTopicHelp String
  | ServiceCommand
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
  | InternalDemoConfigLoadCommand FilePath
  | InternalDemoConfigValidateCommand FilePath
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
    ( [ "infernix [--runtime-mode apple-silicon|linux-cpu|linux-cuda]",
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
        <> [ "Runtime-mode override:",
             "",
             "- `infernix [--runtime-mode apple-silicon|linux-cpu|linux-cuda] COMMAND`"
           ]
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
  [ CommandFamily
      { familyTopic = "service",
        familyOverview = "starts the long-running production daemon that consumes Pulsar work and binds no HTTP port",
        familyCommands =
          [ simpleCommand
              "service"
              "starts the long-running production daemon; it binds no HTTP port and consumes the active `.dhall` request and result topics"
              ServiceCommand
          ]
      },
    CommandFamily
      { familyTopic = "cluster",
        familyOverview = "reconciles or reports cluster state, generated config publication, and routed surfaces",
        familyCommands =
          [ simpleCommand "cluster up" "reconciles Kind, Harbor-first bootstrap, generated demo config, and routed publication state" ClusterUpCommand,
            simpleCommand "cluster down" "tears the cluster down while leaving durable repo-local state under `./.data/` intact" ClusterDownCommand,
            simpleCommand "cluster status" "reports cluster presence, runtime mode, publication state, build paths, and route inventory without mutation" ClusterStatusCommand
          ]
      },
    CommandFamily
      { familyTopic = "cache",
        familyOverview = "inspects or reconciles manifest-backed derived cache state for the active runtime mode",
        familyCommands =
          [ simpleCommand "cache status" "reports the manifest-backed cache inventory for the active runtime mode" CacheStatusCommand,
            optionalModelCommand
              "cache evict [--model MODEL_ID]"
              "evicts derived cache state for one model or for the whole active runtime mode"
              CacheEvictCommand,
            optionalModelCommand
              "cache rebuild [--model MODEL_ID]"
              "rebuilds derived cache state from durable manifests for one model or for the whole active runtime mode"
              CacheRebuildCommand
          ]
      },
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
      },
    CommandFamily
      { familyTopic = "lint",
        familyOverview = "runs the focused Haskell-owned static checks for files, docs, `.proto`, and chart assets",
        familyCommands =
          [ simpleCommand "lint files" "runs the tracked-file and generated-artifact hygiene checks" LintFilesCommand,
            simpleCommand "lint docs" "runs the governed documentation validator" LintDocsCommand,
            simpleCommand "lint proto" "runs the protobuf contract validator" LintProtoCommand,
            simpleCommand "lint chart" "runs the Helm and chart ownership validator" LintChartCommand
          ]
      },
    CommandFamily
      { familyTopic = "test",
        familyOverview = "runs the aggregate validation entrypoints for lint, unit, integration, routed E2E, and the full suite",
        familyCommands =
          [ simpleCommand "test lint" "runs the focused lint entrypoints together with the strict Haskell style and Python quality gates" TestLintCommand,
            simpleCommand "test unit" "runs the Haskell unit suites and the PureScript frontend unit suites" TestUnitCommand,
            simpleCommand "test integration" "runs the cluster-backed integration suite against the active runtime mode or matrix" TestIntegrationCommand,
            simpleCommand "test e2e" "runs routed Playwright coverage for every demo-visible generated catalog entry" TestE2ECommand,
            simpleCommand "test all" "runs lint, unit, integration, and routed E2E validation in sequence" TestAllCommand
          ]
      },
    CommandFamily
      { familyTopic = "docs",
        familyOverview = "validates the governed documentation suite and the development-plan shape",
        familyCommands =
          [ simpleCommand "docs check" "runs the canonical documentation validator" DocsCheckCommand
          ]
      },
    CommandFamily
      { familyTopic = "internal",
        familyOverview = "runs build-time helpers for contract generation, chart discovery, demo-config inspection, and Pulsar round-trip validation",
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
            CommandSpec
              { commandUsageSuffix = "internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT",
                commandDescription = "publishes one inference request through Pulsar and waits for the matching result",
                commandParse = \case
                  ["internal", "pulsar-roundtrip", demoConfigPath, modelIdValue, inputTextValue] ->
                    Just (InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue)
                  _ -> Nothing
              }
          ]
      }
  ]

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
