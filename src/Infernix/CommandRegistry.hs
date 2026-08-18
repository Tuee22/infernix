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
import Text.Read (readMaybe)

data Command
  = ShowRootHelp
  | ShowTopicHelp String
  | InitCommand (Maybe RuntimeMode) (Maybe Bool) (Maybe Int) Bool Bool
  | TestInitCommand (Maybe RuntimeMode) (Maybe Bool) (Maybe Int)
  | ServiceCommand (Maybe DaemonRole) (Maybe String) (Maybe FilePath)
  | ClusterUpCommand
  | ClusterDownCommand
  | ClusterStatusCommand
  | ClusterReclaimSlotCommand (Maybe Integer)
  | CacheStatusCommand
  | CacheEvictCommand (Maybe String)
  | CacheRebuildCommand (Maybe String)
  | KubectlCommand [String]
  | DocsCheckCommand
  | LintFilesCommand
  | LintDocsCommand
  | LintProtoCommand
  | LintChartCommand
  | LintPlanCommand
  | TestLintCommand
  | TestUnitCommand
  | TestIntegrationCommand
  | TestE2ECommand
  | TestAllCommand
  | InternalDiscoverImagesCommand FilePath
  | InternalDiscoverClaimsCommand FilePath
  | InternalDiscoverHarborOverlayCommand FilePath
  | InternalPublishChartImagesCommand FilePath FilePath
  | InternalMaterializeSubstrateCommand RuntimeMode (Maybe Int) Bool Bool
  | InternalMaterializeMetalEnginesCommand
  | InternalMaterializeLinuxNativeEnginesCommand
  | InternalDemoConfigLoadCommand FilePath
  | InternalDemoConfigValidateCommand FilePath
  | InternalDhallSchemaCommand DhallSchema
  | InternalGeneratePursContractsCommand FilePath
  | InternalValidateDarwinBuildMemoryCommand
  | InternalValidateDarwinAudiverisCancellationCommand
  | InternalValidateDarwinInstalledPythonSourceIsolationCommand
  | InternalPulsarRoundTripCommand FilePath String String
  | InternalPlaywrightPrepareEngineCommand String
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
  [ initCommandFamily,
    serviceCommandFamily,
    clusterCommandFamily,
    cacheCommandFamily,
    kubectlCommandFamily,
    lintCommandFamily,
    testCommandFamily,
    docsCommandFamily,
    internalCommandFamily
  ]

initCommandFamily :: CommandFamily
initCommandFamily =
  CommandFamily
    { familyTopic = "init",
      familyOverview = "creates the operator runtime config `./infernix.dhall` and host manifest `./infernix-host.dhall`",
      familyCommands =
        [ initCommandSpec
        ]
    }

initCommandSpec :: CommandSpec
initCommandSpec =
  CommandSpec
    { commandUsageSuffix = "init [--runtime-mode apple-silicon|linux-cpu|linux-gpu] [--demo-ui true|false] [--engine-machines N] [--force] [--if-missing]",
      commandDescription = "writes the runtime config `./infernix.dhall` and host manifest `./infernix-host.dhall`. Fails fast if `./infernix.dhall` already exists unless `--force`; `--if-missing` makes an existing config a no-op. `--engine-machines` declares how many engine machines the fleet has (default 1, one engine process per machine). No other command auto-generates config.",
      commandParse = \case
        ("init" : rest) -> parseInitFlags Nothing Nothing Nothing False False rest
        _ -> Nothing
    }

parseInitFlags ::
  Maybe RuntimeMode -> Maybe Bool -> Maybe Int -> Bool -> Bool -> [String] -> Maybe Command
parseInitFlags mode demoUi engineMachines force ifMissing args =
  case args of
    [] -> Just (InitCommand mode demoUi engineMachines force ifMissing)
    ("--runtime-mode" : rawMode : rest) ->
      parseRuntimeModeArg rawMode
        >>= \parsedMode -> parseInitFlags (Just parsedMode) demoUi engineMachines force ifMissing rest
    ("--demo-ui" : rawDemoUi : rest) ->
      parseDemoUiArg rawDemoUi
        >>= \parsedDemoUi -> parseInitFlags mode (Just parsedDemoUi) engineMachines force ifMissing rest
    ("--engine-machines" : rawMachines : rest) ->
      parseEngineMachinesArg rawMachines
        >>= \parsedMachines -> parseInitFlags mode demoUi (Just parsedMachines) force ifMissing rest
    ("--force" : rest) -> parseInitFlags mode demoUi engineMachines True ifMissing rest
    ("--if-missing" : rest) -> parseInitFlags mode demoUi engineMachines force True rest
    _ -> Nothing

-- | Phase 8 Sprint 8.12 — parse @--engine-machines@ as a plain positive
-- integer.
--
-- The domain check — whether the resolved runtime mode supports a fleet of that
-- size — belongs to 'Infernix.Models.engineMachineCountForMode' and runs where
-- the mode is resolved. Keeping the two apart is what lets an unsupported fleet
-- fail with a named refusal that says why, instead of with usage text that says
-- only that something was wrong.
parseEngineMachinesArg :: String -> Maybe Int
parseEngineMachinesArg rawMachines =
  case reads rawMachines of
    [(parsed, "")] | parsed >= 1 -> Just parsed
    _ -> Nothing

testInitCommandSpec :: CommandSpec
testInitCommandSpec =
  CommandSpec
    { commandUsageSuffix = "test init [--runtime-mode apple-silicon|linux-cpu|linux-gpu] [--demo-ui true|false] [--engine-machines N]",
      commandDescription = "writes the thin `./infernix.test.dhall` the test harness reads to generate the run's `./infernix.dhall`. `--engine-machines` declares the run's fleet size (default 1).",
      commandParse = \case
        ("test" : "init" : rest) -> parseTestInitFlags Nothing Nothing Nothing rest
        _ -> Nothing
    }

parseTestInitFlags :: Maybe RuntimeMode -> Maybe Bool -> Maybe Int -> [String] -> Maybe Command
parseTestInitFlags mode demoUi engineMachines args =
  case args of
    [] -> Just (TestInitCommand mode demoUi engineMachines)
    ("--runtime-mode" : rawMode : rest) ->
      parseRuntimeModeArg rawMode
        >>= \parsedMode -> parseTestInitFlags (Just parsedMode) demoUi engineMachines rest
    ("--demo-ui" : rawDemoUi : rest) ->
      parseDemoUiArg rawDemoUi
        >>= \parsedDemoUi -> parseTestInitFlags mode (Just parsedDemoUi) engineMachines rest
    ("--engine-machines" : rawMachines : rest) ->
      parseEngineMachinesArg rawMachines
        >>= \parsedMachines -> parseTestInitFlags mode demoUi (Just parsedMachines) rest
    _ -> Nothing

serviceCommandFamily :: CommandFamily
serviceCommandFamily =
  CommandFamily
    { familyTopic = "service",
      familyOverview = "starts one long-running role from the single infernix binary: coordinator, engine, or webapp",
      familyCommands =
        [ serviceCommandSpec
        ]
    }

-- | `infernix service [--role coordinator|engine|webapp] [--engine-name NAME] [--config PATH]`.
-- The optional `--role` arg replaces the retired `INFERNIX_DAEMON_ROLE`
-- env var (Phase 4 Sprint 4.13): coordinator + engine pods each pass
-- the matching role via chart-supplied `args`, the webapp Deployment
-- passes `--role webapp`, while host-native flows omit the flag and
-- fall back to this machine's contract (`machine.role`).
-- Engine pods or host daemons may pass
-- `--engine-name` to name one of the engine member identities this
-- machine's contract declares (Phase 8 Sprint 8.11); a name outside that
-- set is refused rather than adopted. `--config` is a typed path override used by
-- targeted validation harnesses and operator diagnostics that need an
-- isolated runtime config.
serviceCommandSpec :: CommandSpec
serviceCommandSpec =
  CommandSpec
    { commandUsageSuffix = "service [--role coordinator|engine|webapp] [--engine-name NAME] [--config PATH]",
      commandDescription =
        "starts one long-running role from the single infernix binary. Coordinator and engine roles consume the effective runtime-config request and result topics; the webapp role serves the demo HTTP/WebSocket surface. The optional `--role` arg overrides the machine contract's `machine.role` for split Deployments, `--engine-name` selects one of the engine member identities this machine declares, and `--config` points the daemon at an explicit runtime config.",
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
        [ simpleCommand "cluster up" "requires the initialized repo-root runtime config, then reconciles Kind, Harbor-first bootstrap, its cluster deployment mirror, and routed publication state" ClusterUpCommand,
          simpleCommand "cluster down" "tears the cluster down while leaving durable repo-local state under `./.data/` intact" ClusterDownCommand,
          simpleCommand "cluster status" "reports cluster presence, lifecycle phase, active substrate, publication state, build paths, and route inventory; on Linux outer-container paths it may attach the launcher to Docker's `kind` network for observation" ClusterStatusCommand,
          CommandSpec
            { commandUsageSuffix = "cluster reclaim-slot [--force-owner-pid PID]",
              commandDescription = "reports the typed evidence for an interrupted harness cluster-slot reservation and retires it only after owner-death or an exact operator-transcribed PID premise, bounded-command quiescence, and config-transaction recovery",
              commandParse = parseClusterReclaimSlotCommand
            }
        ]
    }

parseClusterReclaimSlotCommand :: [String] -> Maybe Command
parseClusterReclaimSlotCommand = \case
  ["cluster", "reclaim-slot"] ->
    Just (ClusterReclaimSlotCommand Nothing)
  ["cluster", "reclaim-slot", "--force-owner-pid", rawOwnerPid]
    | Just ownerPid <- readMaybe rawOwnerPid,
      ownerPid > 0,
      ownerPid <= 2147483647 ->
        Just (ClusterReclaimSlotCommand (Just ownerPid))
  _ -> Nothing

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
      familyOverview = "proxies read-only Kubernetes diagnostics through the repo-local kubeconfig",
      familyCommands =
        [ CommandSpec
            { commandUsageSuffix = "kubectl ...",
              commandDescription = "wraps an allowlisted read-only subset of upstream `kubectl` and injects the repo-local kubeconfig for the active control-plane context",
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
      familyOverview = "runs the focused Haskell-owned static checks for files, docs, `.proto`, chart assets, and development-plan standards",
      familyCommands =
        [ simpleCommand "lint files" "runs the tracked-file and generated-artifact hygiene checks" LintFilesCommand,
          simpleCommand "lint docs" "runs the governed-documentation and development-plan-shape validator (`runDocsLint`)" LintDocsCommand,
          simpleCommand "lint proto" "runs the protobuf contract validator" LintProtoCommand,
          simpleCommand "lint chart" "runs the Helm and chart ownership validator" LintChartCommand,
          simpleCommand "lint plan" "runs the development-plan standards scans for status vocabulary, dependency direction, accelerator scope, declarative language, and the removal ledger" LintPlanCommand
        ]
    }

testCommandFamily :: CommandFamily
testCommandFamily =
  CommandFamily
    { familyTopic = "test",
      familyOverview = "runs the aggregate validation entrypoints for lint, unit, integration, routed E2E, and the full suite",
      familyCommands =
        [ testInitCommandSpec,
          simpleCommand "test lint" "runs the focused lint entrypoints together with the strict Haskell/Cabal style and Python quality gates" TestLintCommand,
          simpleCommand
            "test unit"
            "runs all machine-independent Haskell suites (compile-fail, artifact transaction, Apple materializer, capped observer, execution-plan, and unit) plus the PureScript frontend unit suite"
            TestUnitCommand,
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
        [ simpleCommand "docs check" "alias of `lint docs` (same `runDocsLint`); runs the governed-documentation and development-plan-shape validator" DocsCheckCommand
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
          simpleCommand
            "internal validate-darwin-build-memory"
            "runs the closed Darwin-only fresh toolchain build and reports sampled peak aggregate physical footprint evidence"
            InternalValidateDarwinBuildMemoryCommand,
          simpleCommand
            "internal validate-darwin-audiveris-cancellation"
            "runs the fixed Darwin production Audiveris cancellation-recovery cohort gate"
            InternalValidateDarwinAudiverisCancellationCommand,
          simpleCommand
            "internal validate-darwin-installed-python-source-isolation"
            "runs the fixed Darwin installed-Python source-isolation cohort gate"
            InternalValidateDarwinInstalledPythonSourceIsolationCommand,
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
            "materializes the allowlisted Apple Metal/Core ML engine manifests under `./.data/engines/<adapterId>/` and prepares the canonical Apple per-engine Python framework plan through the Tart-free headless host lane (Apple-only; mirrors `internal materialize-substrate`)"
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
          pulsarRoundTripCommand,
          CommandSpec
            { commandUsageSuffix = "internal playwright prepare-engine MODEL_ID",
              commandDescription = "selects the generated model's closed engine deployment under harness ownership",
              commandParse = \case
                ["internal", "playwright", "prepare-engine", modelIdValue] ->
                  Just (InternalPlaywrightPrepareEngineCommand modelIdValue)
                _ -> Nothing
            }
        ]
    }

materializeSubstrateCommand :: CommandSpec
materializeSubstrateCommand =
  CommandSpec
    { commandUsageSuffix = "internal materialize-substrate RUNTIME_MODE [--demo-ui true|false] [--engine-machines N] [--empty-models]",
      commandDescription = "writes the generated runtime config and prepares the closed per-engine Python framework plan for one explicit substrate id",
      commandParse = \case
        ("internal" : "materialize-substrate" : rawRuntimeMode : rest) ->
          parseRuntimeModeArg rawRuntimeMode
            >>= \runtimeMode -> parseMaterializeSubstrateFlags runtimeMode True Nothing False rest
        _ -> Nothing
    }

-- | Phase 8 Sprint 8.12 — @--engine-machines@ reaches the lane-facing generator,
-- not only @init@.
--
-- @init@ deliberately discovers its paths /without/ an existing host manifest,
-- because it is the migration boundary that replaces one. That makes it the
-- wrong entry point inside the Linux launcher image, where the execution
-- context a manifest records — @outer-container@ — is exactly the fact a
-- context-free regeneration loses. The image and the fleet lane materialize
-- through this command instead, which resolves its paths from the manifest it
-- regenerates beside, so the context survives.
parseMaterializeSubstrateFlags ::
  RuntimeMode -> Bool -> Maybe Int -> Bool -> [String] -> Maybe Command
parseMaterializeSubstrateFlags runtimeMode demoUi engineMachines emptyModels args =
  case args of
    [] -> Just (InternalMaterializeSubstrateCommand runtimeMode engineMachines demoUi emptyModels)
    ("--demo-ui" : rawDemoUi : rest) ->
      parseDemoUiArg rawDemoUi
        >>= \parsedDemoUi -> parseMaterializeSubstrateFlags runtimeMode parsedDemoUi engineMachines emptyModels rest
    ("--engine-machines" : rawMachines : rest) ->
      parseEngineMachinesArg rawMachines
        >>= \parsedMachines -> parseMaterializeSubstrateFlags runtimeMode demoUi (Just parsedMachines) emptyModels rest
    ("--empty-models" : rest) ->
      parseMaterializeSubstrateFlags runtimeMode demoUi engineMachines True rest
    _ -> Nothing

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
