module Infernix.CommandRegistry
  ( Command (..),
    documentedCommandLines,
    helpText,
    internalHelpText,
    lintHelpText,
    parseCommand,
    testHelpText,
    topicHelpText,
  )
where

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

helpText :: String
helpText =
  unlines
    [ "infernix [--runtime-mode apple-silicon|linux-cpu|linux-cuda]",
      "",
      "Commands:"
    ]
    <> unlines (map ("  " <>) documentedCommandLines)

testHelpText :: String
testHelpText = unlines (map commandWithPrefix ["test lint", "test unit", "test integration", "test e2e", "test all"])

lintHelpText :: String
lintHelpText = unlines (map commandWithPrefix ["lint files", "lint docs", "lint proto", "lint chart"])

internalHelpText :: String
internalHelpText =
  unlines
    ( map
        commandWithPrefix
        [ "internal generate-purs-contracts PATH",
          "internal discover images RENDERED_CHART",
          "internal discover claims RENDERED_CHART",
          "internal discover harbor-overlay OVERLAY",
          "internal publish-chart-images RENDERED_CHART OUTPUT",
          "internal demo-config load PATH",
          "internal demo-config validate PATH",
          "internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT"
        ]
    )

topicHelpText :: String -> String
topicHelpText topic =
  case topic of
    "cluster" -> unlines (map commandWithPrefix ["cluster up", "cluster down", "cluster status"])
    "test" -> testHelpText
    "lint" -> lintHelpText
    "internal" -> internalHelpText
    _ -> helpText

documentedCommandLines :: [String]
documentedCommandLines =
  map
    commandWithPrefix
    [ "service",
      "cluster up",
      "cluster down",
      "cluster status",
      "cache status",
      "cache evict [--model MODEL_ID]",
      "cache rebuild [--model MODEL_ID]",
      "kubectl ...",
      "lint files",
      "lint docs",
      "lint proto",
      "lint chart",
      "test lint",
      "test unit",
      "test integration",
      "test e2e",
      "test all",
      "docs check",
      "internal generate-purs-contracts PATH",
      "internal discover {images,claims,harbor-overlay} PATH",
      "internal publish-chart-images RENDERED_CHART OUTPUT",
      "internal demo-config {load,validate} PATH",
      "internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT"
    ]

parseCommand :: [String] -> Either String Command
parseCommand args =
  case args of
    [] -> Right ShowRootHelp
    ["--help"] -> Right ShowRootHelp
    ["cluster", "--help"] -> Right (ShowTopicHelp "cluster")
    ["test", "--help"] -> Right (ShowTopicHelp "test")
    ["lint", "--help"] -> Right (ShowTopicHelp "lint")
    ["internal", "--help"] -> Right (ShowTopicHelp "internal")
    ["service"] -> Right ServiceCommand
    ["cluster", "up"] -> Right ClusterUpCommand
    ["cluster", "down"] -> Right ClusterDownCommand
    ["cluster", "status"] -> Right ClusterStatusCommand
    ["cache", "status"] -> Right CacheStatusCommand
    ["cache", "evict"] -> Right (CacheEvictCommand Nothing)
    ["cache", "evict", "--model", modelIdValue] -> Right (CacheEvictCommand (Just modelIdValue))
    ["cache", "rebuild"] -> Right (CacheRebuildCommand Nothing)
    ["cache", "rebuild", "--model", modelIdValue] -> Right (CacheRebuildCommand (Just modelIdValue))
    "kubectl" : kubectlArgs -> Right (KubectlCommand kubectlArgs)
    ["docs", "check"] -> Right DocsCheckCommand
    ["lint", "files"] -> Right LintFilesCommand
    ["lint", "docs"] -> Right LintDocsCommand
    ["lint", "proto"] -> Right LintProtoCommand
    ["lint", "chart"] -> Right LintChartCommand
    ["test", "lint"] -> Right TestLintCommand
    ["test", "unit"] -> Right TestUnitCommand
    ["test", "integration"] -> Right TestIntegrationCommand
    ["test", "e2e"] -> Right TestE2ECommand
    ["test", "all"] -> Right TestAllCommand
    ["internal", "discover", "images", renderedChartPath] -> Right (InternalDiscoverImagesCommand renderedChartPath)
    ["internal", "discover", "claims", renderedChartPath] -> Right (InternalDiscoverClaimsCommand renderedChartPath)
    ["internal", "discover", "harbor-overlay", overlayPath] -> Right (InternalDiscoverHarborOverlayCommand overlayPath)
    ["internal", "publish-chart-images", renderedChartPath, outputPath] ->
      Right (InternalPublishChartImagesCommand renderedChartPath outputPath)
    ["internal", "demo-config", "load", demoConfigPath] -> Right (InternalDemoConfigLoadCommand demoConfigPath)
    ["internal", "demo-config", "validate", demoConfigPath] -> Right (InternalDemoConfigValidateCommand demoConfigPath)
    ["internal", "generate-purs-contracts", outputDir] -> Right (InternalGeneratePursContractsCommand outputDir)
    ["internal", "pulsar-roundtrip", demoConfigPath, modelIdValue, inputTextValue] ->
      Right (InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue)
    _ -> Left "Unsupported infernix command"

commandWithPrefix :: String -> String
commandWithPrefix commandSuffix = "infernix " <> commandSuffix
