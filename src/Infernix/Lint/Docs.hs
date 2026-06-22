module Infernix.Lint.Docs
  ( runDocsLint,
  )
where

import Control.Monad (forM_, unless, when)
import Data.Char (isSpace, toLower)
import Data.List (dropWhileEnd, find, intercalate, isInfixOf, isPrefixOf, nub)
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Infernix.CommandRegistry
  ( renderCliReferenceCommandsSection,
    renderCliSurfaceFamiliesSection,
  )
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.DhallSchema
  ( allDhallSchemas,
    dhallSchemaFileName,
    dhallSchemaName,
    renderDhallSchema,
  )
import Infernix.Models (catalogForMode, matrixRowReadmeKeys, residualMatrixRowIdsForMode)
import Infernix.Routes
  ( renderClusterBootstrapRouteChecksSection,
    renderEdgeRoutingInventorySection,
    renderHarborRouteSummarySection,
    renderMinioRouteSummarySection,
    renderPulsarRouteSummarySection,
    renderReadmeRouteSummarySection,
    renderWebPortalRoutesSection,
  )
import Infernix.Types (RuntimeMode (..), allRuntimeModes, matrixRowId, referenceModel, runtimeModeId, selectedEngine)
import System.Directory (doesFileExist, doesPathExist)
import System.FilePath (dropDrive, normalise, takeDirectory, (</>))

requiredDocs :: [FilePath]
requiredDocs =
  [ "documents/README.md",
    "documents/documentation_standards.md",
    "documents/architecture/overview.md",
    "documents/architecture/model_catalog.md",
    "documents/architecture/runtime_modes.md",
    "documents/architecture/web_ui_architecture.md",
    "documents/development/chaos_testing.md",
    "documents/development/frontend_contracts.md",
    "documents/development/haskell_style.md",
    "documents/development/assistant_workflow.md",
    "documents/development/local_dev.md",
    "documents/development/python_policy.md",
    "documents/development/purescript_policy.md",
    "documents/development/testing_strategy.md",
    "documents/engineering/build_artifacts.md",
    "documents/engineering/docker_policy.md",
    "documents/engineering/edge_routing.md",
    "documents/engineering/implementation_boundaries.md",
    "documents/engineering/k8s_native_dev_policy.md",
    "documents/engineering/k8s_storage.md",
    "documents/engineering/model_lifecycle.md",
    "documents/engineering/object_storage.md",
    "documents/engineering/portability.md",
    "documents/engineering/storage_and_state.md",
    "documents/engineering/testing.md",
    "documents/operations/apple_silicon_runbook.md",
    "documents/operations/cluster_bootstrap_runbook.md",
    "documents/reference/api_surface.md",
    "documents/reference/cli_reference.md",
    "documents/reference/cli_surface.md",
    "documents/reference/web_portal_surface.md",
    "documents/tools/harbor.md",
    "documents/tools/minio.md",
    "documents/tools/postgresql.md",
    "documents/tools/pulsar.md",
    "documents/research/README.md"
  ]

forbiddenPhrases :: [String]
forbiddenPhrases =
  [ "Python HTTP server",
    "JavaScript workbench",
    "web/build.mjs",
    "Homebrew-installed poetry",
    "single Haskell binary",
    "infernix edge",
    "infernix gateway harbor",
    "infernix gateway minio",
    "infernix gateway pulsar",
    "tools/python_quality.sh",
    "scripts/install-formatter.sh",
    "web/Dockerfile",
    "docker/infernix.Dockerfile",
    "docker/service.Dockerfile",
    "python/adapters/<engine>/",
    "python/<substrate>/adapters/",
    "python/apple-silicon/",
    "python/linux-cpu/",
    "python/linux-gpu/",
    "src/Generated/Contracts.hs",
    "docker/linux-base.Dockerfile",
    "docker/linux-cpu.Dockerfile",
    "docker/linux-gpu.Dockerfile",
    "npx playwright",
    "Harbor admin Basic-auth"
  ]

phaseDocs :: [FilePath]
phaseDocs =
  [ "DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md",
    "DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md",
    "DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md",
    "DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md",
    "DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md",
    "DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md",
    "DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md"
  ]

data RootDocRule = RootDocRule
  { rootDocPath :: FilePath,
    rootDocStatus :: String,
    rootDocCanonicalHomes :: [FilePath]
  }

data GeneratedSectionRule = GeneratedSectionRule
  { generatedSectionPath :: FilePath,
    generatedSectionStartMarker :: String,
    generatedSectionEndMarker :: String,
    generatedSectionExpected :: String
  }

data DocumentStructureRule = DocumentStructureRule
  { documentStructurePath :: FilePath,
    documentStructureRequirements :: [SectionRequirement]
  }

data SectionRequirement
  = RequireSection String
  | RequireOneOfSections [String]

rootDocRules :: [RootDocRule]
rootDocRules =
  [ RootDocRule
      { rootDocPath = "README.md",
        rootDocStatus = "Governed orientation document",
        rootDocCanonicalHomes =
          [ "documents/README.md",
            "documents/reference/cli_reference.md",
            "documents/development/local_dev.md",
            "DEVELOPMENT_PLAN/README.md"
          ]
      },
    RootDocRule
      { rootDocPath = "AGENTS.md",
        rootDocStatus = "Governed entry document",
        rootDocCanonicalHomes =
          [ "documents/README.md",
            "documents/documentation_standards.md",
            "documents/development/assistant_workflow.md",
            "documents/development/local_dev.md",
            "DEVELOPMENT_PLAN/README.md"
          ]
      },
    RootDocRule
      { rootDocPath = "CLAUDE.md",
        rootDocStatus = "Governed entry document",
        rootDocCanonicalHomes =
          [ "documents/README.md",
            "documents/documentation_standards.md",
            "documents/development/assistant_workflow.md",
            "documents/development/local_dev.md",
            "DEVELOPMENT_PLAN/README.md"
          ]
      }
  ]

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules =
  [ GeneratedSectionRule
      { generatedSectionPath = "documents/reference/cli_reference.md",
        generatedSectionStartMarker = "<!-- infernix:command-registry:start -->",
        generatedSectionEndMarker = "<!-- infernix:command-registry:end -->",
        generatedSectionExpected = trimTrailingNewlines renderCliReferenceCommandsSection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/reference/cli_surface.md",
        generatedSectionStartMarker = "<!-- infernix:family-overview:start -->",
        generatedSectionEndMarker = "<!-- infernix:family-overview:end -->",
        generatedSectionExpected = trimTrailingNewlines renderCliSurfaceFamiliesSection
      },
    GeneratedSectionRule
      { generatedSectionPath = "README.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:readme:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:readme:end -->",
        generatedSectionExpected = trimTrailingNewlines renderReadmeRouteSummarySection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/engineering/edge_routing.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:edge-routing:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:edge-routing:end -->",
        generatedSectionExpected = trimTrailingNewlines renderEdgeRoutingInventorySection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/reference/web_portal_surface.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:web-portal:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:web-portal:end -->",
        generatedSectionExpected = trimTrailingNewlines renderWebPortalRoutesSection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/tools/harbor.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:harbor:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:harbor:end -->",
        generatedSectionExpected = trimTrailingNewlines renderHarborRouteSummarySection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/tools/minio.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:minio:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:minio:end -->",
        generatedSectionExpected = trimTrailingNewlines renderMinioRouteSummarySection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/tools/pulsar.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:pulsar:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:pulsar:end -->",
        generatedSectionExpected = trimTrailingNewlines renderPulsarRouteSummarySection
      },
    GeneratedSectionRule
      { generatedSectionPath = "documents/operations/cluster_bootstrap_runbook.md",
        generatedSectionStartMarker = "<!-- infernix:route-registry:cluster-bootstrap:start -->",
        generatedSectionEndMarker = "<!-- infernix:route-registry:cluster-bootstrap:end -->",
        generatedSectionExpected = trimTrailingNewlines renderClusterBootstrapRouteChecksSection
      }
  ]

documentStructureRules :: [DocumentStructureRule]
documentStructureRules =
  [ DocumentStructureRule
      { documentStructurePath = "documents/documentation_standards.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Broad Doctrine Structure",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/build_artifacts.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Current Status",
            RequireSection "## Build Roots",
            RequireSection "## Generated Demo Config Publication",
            RequireSection "## Rules",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/docker_policy.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Current Status",
            RequireSection "## Host Prerequisite Boundary",
            RequireSection "## Supported Usage",
            RequireSection "## Image Set",
            RequireSection "## Unsupported Usage",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/edge_routing.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Current Status",
            RequireSection "## Route Inventory",
            RequireSection "## Gateway Ownership",
            RequireSection "## Port Selection Rules",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/implementation_boundaries.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Ownership Matrix",
            RequireSection "## Type Boundaries",
            RequireSection "## Module-Boundary Doctrine",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/storage_and_state.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Owner And Durability Table",
            RequireSection "## Failure And Rebuild Rules",
            RequireSection "## Cleanup Rules",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/portability.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Current Status",
            RequireSection "## Portable Platform Invariants",
            RequireSection "## Supported Substrate Detail",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/engineering/testing.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Preflight Expectations",
            RequireSection "## Validation Obligations",
            RequireSection "## Unsupported Paths",
            RequireSection "## Validation"
          ]
      },
    DocumentStructureRule
      { documentStructurePath = "documents/development/haskell_style.md",
        documentStructureRequirements =
          [ RequireOneOfSections ["## TL;DR", "## Executive Summary"],
            RequireSection "## Hard Gates",
            RequireSection "## Editor-Only Guidance",
            RequireSection "## Review Doctrine",
            RequireSection "## Enforcement Model",
            RequireSection "## Validation"
          ]
      }
  ]

monitoringUnsupportedStatement :: String
monitoringUnsupportedStatement = "Monitoring is not a supported first-class surface."

monitoringStancePaths :: [FilePath]
monitoringStancePaths =
  [ "documents/README.md",
    "DEVELOPMENT_PLAN/README.md",
    "DEVELOPMENT_PLAN/00-overview.md",
    "DEVELOPMENT_PLAN/system-components.md",
    "DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md"
  ]

runDocsLint :: IO ()
runDocsLint = do
  paths <- discoverPaths
  forM_ requiredDocs $ \relativePath -> do
    let fullPath = repoRoot paths </> relativePath
    exists <- doesFileExist fullPath
    unless exists $
      ioError (userError ("missing governed document: " <> relativePath))
  readmeContents <- readFile (repoRoot paths </> "README.md")
  unless ("documents/" `isInfixOf` readmeContents && "DEVELOPMENT_PLAN/" `isInfixOf` readmeContents) $
    ioError (userError "README.md must reference documents/ and DEVELOPMENT_PLAN/")
  validateReadmeRuntimeModeContract readmeContents
  validateReadmeMatrixCoverage readmeContents
  validateReadmeMatrixCellDrift readmeContents
  forM_ requiredDocs $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    validateGovernedDocumentMetadata relativePath contents
    validateRelativeLinks paths relativePath contents
    validateForbiddenPhrases relativePath contents
    validateForbiddenConfigurationOverrideReferences relativePath contents
  forM_ rootDocRules $ \rule -> do
    contents <- readFile (repoRoot paths </> rootDocPath rule)
    validateRootDocMetadata rule contents
    validateRelativeLinks paths (rootDocPath rule) contents
    validateForbiddenPhrases (rootDocPath rule) contents
    validateForbiddenConfigurationOverrideReferences (rootDocPath rule) contents
  forM_ generatedSectionRules $ \rule -> do
    contents <- readFile (repoRoot paths </> generatedSectionPath rule)
    validateGeneratedSection rule contents
  forM_ documentStructureRules $ \rule -> do
    contents <- readFile (repoRoot paths </> documentStructurePath rule)
    validateDocumentStructure rule contents
  validateDhallSchemaDrift paths
  validateTestingDocOwnership paths
  validateUnsupportedMonitoringStance paths
  forM_ phaseDocs $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    validatePhaseDoc relativePath contents
    validateRelativeLinks paths relativePath contents

validateGovernedDocumentMetadata :: FilePath -> String -> IO ()
validateGovernedDocumentMetadata relativePath contents = do
  unless (startsWithHeading contents) $
    ioError (userError (relativePath <> " must start with a Markdown heading"))
  unless ("**Status**:" `isInfixOf` contents) $
    ioError (userError (relativePath <> " is missing the **Status** metadata line"))
  unless ("**Referenced by**:" `isInfixOf` contents) $
    ioError (userError (relativePath <> " is missing the **Referenced by** metadata line"))
  unless ("> **Purpose**:" `isInfixOf` contents) $
    ioError (userError (relativePath <> " is missing the purpose quote block"))

validateRootDocMetadata :: RootDocRule -> String -> IO ()
validateRootDocMetadata rule contents = do
  unless (startsWithHeading contents) $
    ioError (userError (rootDocPath rule <> " must start with a Markdown heading"))
  unless (("**Status**: " <> rootDocStatus rule) `isInfixOf` contents) $
    ioError
      ( userError
          ( rootDocPath rule
              <> " must declare **Status**: "
              <> rootDocStatus rule
          )
      )
  unless ("**Supersedes**:" `isInfixOf` contents) $
    ioError (userError (rootDocPath rule <> " is missing the **Supersedes** metadata line"))
  unless ("**Canonical homes**:" `isInfixOf` contents) $
    ioError (userError (rootDocPath rule <> " is missing the **Canonical homes** metadata line"))
  unless ("> **Purpose**:" `isInfixOf` contents) $
    ioError (userError (rootDocPath rule <> " is missing the purpose quote block"))
  forM_ (rootDocCanonicalHomes rule) $ \target ->
    unless (target `isInfixOf` contents) $
      ioError
        ( userError
            ( rootDocPath rule
                <> " is missing the canonical-home link to "
                <> target
            )
        )

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
                    <> " has drifted from the Haskell command registry generated section"
                )
            )
        )

validateDhallSchemaDrift :: Paths -> IO ()
validateDhallSchemaDrift paths =
  forM_ allDhallSchemas $ \schema -> do
    let relativePath = "dhall" </> dhallSchemaFileName schema
        fullPath = repoRoot paths </> relativePath
    actual <- readFile fullPath
    expected <-
      case renderDhallSchema schema of
        Left err ->
          ioError (userError ("could not render " <> Text.unpack (dhallSchemaName schema) <> " Dhall schema: " <> err))
        Right schemaText ->
          pure (Text.unpack schemaText)
    unless (actual == expected) $
      ioError
        ( userError
            ( relativePath
                <> " has drifted from the decoder-reflected schema; regenerate with `infernix internal dhall-schema "
                <> Text.unpack (dhallSchemaName schema)
                <> " > "
                <> relativePath
                <> "`"
            )
        )

validateForbiddenPhrases :: FilePath -> String -> IO ()
validateForbiddenPhrases relativePath contents =
  when
    (any (`isInfixOf` contents) forbiddenPhrases)
    (ioError (userError ("forbidden retired-doctrine phrase found in " <> relativePath)))

validateForbiddenConfigurationOverrideReferences :: FilePath -> String -> IO ()
validateForbiddenConfigurationOverrideReferences relativePath contents =
  case violations of
    [] -> pure ()
    _ ->
      ioError
        ( userError
            ( "forbidden env/PATH override reference found in "
                <> relativePath
                <> ":\n"
                <> intercalate "\n" violations
            )
        )
  where
    violations =
      [ show lineNumber <> ": " <> lineValue
      | (lineNumber, lineValue) <- zip [1 :: Int ..] (lines contents),
        any (`isInfixOf` lineValue) forbiddenConfigurationOverrideTokens
      ]

forbiddenConfigurationOverrideTokens :: [String]
forbiddenConfigurationOverrideTokens =
  [ "INFERNIX_",
    "$INFERNIX",
    "$PATH"
  ]

validateDocumentStructure :: DocumentStructureRule -> String -> IO ()
validateDocumentStructure rule contents =
  forM_ (documentStructureRequirements rule) validateRequirement
  where
    validateRequirement requirement =
      case requirement of
        RequireSection headingText ->
          unless
            (headingText `isInfixOf` contents)
            ( ioError
                ( userError
                    ( documentStructurePath rule
                        <> " is missing the required section "
                        <> headingText
                    )
                )
            )
        RequireOneOfSections headingTexts ->
          unless
            (any (`isInfixOf` contents) headingTexts)
            ( ioError
                ( userError
                    ( documentStructurePath rule
                        <> " must contain one of the required sections: "
                        <> intercalate ", " headingTexts
                    )
                )
            )

validateReadmeRuntimeModeContract :: String -> IO ()
validateReadmeRuntimeModeContract contents = do
  unless
    ("| Apple Silicon / Metal | host-native Apple binary path |" `isInfixOf` contents)
    (ioError (userError "README.md must describe Apple Silicon as the host-native binary path"))
  unless
    ("| Ubuntu 24.04 / CPU | containerized Linux CPU path |" `isInfixOf` contents)
    (ioError (userError "README.md must describe linux-cpu as the containerized Linux CPU path"))

-- | Phase 6 Sprint 6.6 — the README-to-matrix coverage check. Every model
-- in the generated catalog (the union of 'catalogForMode' across every
-- substrate, which equals 'Infernix.Models.allMatrixRowIds') must be named
-- by the README's comprehensive model/format/engine matrix. The
-- @referenceModel@ is the stable identifier shared by the catalog row and
-- the README matrix entry; the union-equals-README-rows invariant itself is
-- asserted by `infernix test unit`.
validateReadmeMatrixCoverage :: String -> IO ()
validateReadmeMatrixCoverage contents = do
  let lowerReadme = map toLower contents
      catalogModels = concatMap catalogForMode allRuntimeModes
      missing =
        nub
          [ referenceModelName
          | model <- catalogModels,
            let referenceModelName = Text.unpack (referenceModel model),
            not (map toLower referenceModelName `isInfixOf` lowerReadme)
          ]
  unless (null missing) $
    ioError
      ( userError
          ( "README.md model matrix is missing generated-catalog reference models: "
              <> intercalate ", " missing
          )
      )

validateReadmeMatrixCellDrift :: String -> IO ()
validateReadmeMatrixCellDrift contents = do
  let readmeRows = parseReadmeMatrixRows contents
      missingRows =
        [ Text.unpack rowIdValue
        | (rowIdValue, artifactTypeValue, referenceModelValue) <- matrixRowReadmeKeys,
          isNothing (lookupReadmeMatrixRow artifactTypeValue referenceModelValue readmeRows)
        ]
      drift =
        concat
          [ readmeMatrixCellDriftForRow readmeRows rowKey
          | rowKey <- matrixRowReadmeKeys
          ]
  unless (null missingRows) $
    ioError
      ( userError
          ( "README.md model matrix is missing generated-catalog row keys: "
              <> intercalate ", " missingRows
          )
      )
  unless (null drift) $
    ioError
      ( userError
          ( "README.md model matrix cells have drifted from generated catalog/residual state:\n"
              <> intercalate "\n" drift
          )
      )

data ReadmeMatrixRow = ReadmeMatrixRow
  { readmeArtifactType :: Text.Text,
    readmeReferenceModel :: Text.Text,
    readmeLinuxCpuEngine :: String,
    readmeLinuxGpuEngine :: String,
    readmeAppleEngine :: String
  }

parseReadmeMatrixRows :: String -> [ReadmeMatrixRow]
parseReadmeMatrixRows contents =
  [ ReadmeMatrixRow
      { readmeArtifactType = Text.pack artifactTypeCell,
        readmeReferenceModel = Text.pack referenceModelCell,
        readmeLinuxCpuEngine = linuxCpuCell,
        readmeLinuxGpuEngine = linuxGpuCell,
        readmeAppleEngine = appleCell
      }
  | lineValue <- lines contents,
    cells@(workloadCell : _) <- [tableCells lineValue],
    length cells >= 7,
    workloadCell /= "Model / workload type",
    not (all (`elem` ['-', ' ']) workloadCell),
    let artifactTypeCell = cells !! 1,
    let referenceModelCell = cells !! 2,
    let linuxCpuCell = cells !! 4,
    let linuxGpuCell = cells !! 5,
    let appleCell = cells !! 6
  ]

tableCells :: String -> [String]
tableCells lineValue =
  case splitOn "|" lineValue of
    "" : rest -> map trimWhitespaceString (dropTrailingEmpty rest)
    _ -> []

dropTrailingEmpty :: [String] -> [String]
dropTrailingEmpty values =
  case reverse values of
    "" : rest -> reverse rest
    _ -> values

lookupReadmeMatrixRow :: Text.Text -> Text.Text -> [ReadmeMatrixRow] -> Maybe ReadmeMatrixRow
lookupReadmeMatrixRow artifactTypeValue referenceModelValue =
  find
    ( \row ->
        readmeArtifactType row == artifactTypeValue
          && readmeReferenceModel row == referenceModelValue
    )

readmeMatrixCellDriftForRow :: [ReadmeMatrixRow] -> (Text.Text, Text.Text, Text.Text) -> [String]
readmeMatrixCellDriftForRow readmeRows (rowIdValue, artifactTypeValue, referenceModelValue) =
  case lookupReadmeMatrixRow artifactTypeValue referenceModelValue readmeRows of
    Nothing -> []
    Just row ->
      [ "  "
          <> Text.unpack rowIdValue
          <> " "
          <> Text.unpack (runtimeModeId runtimeMode)
          <> ": expected "
          <> expectedCellDescription expectedCell
          <> ", found "
          <> show actualCell
      | runtimeMode <- allRuntimeModes,
        let expectedCell = expectedMatrixCell runtimeMode rowIdValue,
        let actualCell = readmeCellForMode runtimeMode row,
        not (readmeCellMatches expectedCell actualCell)
      ]

data ExpectedMatrixCell
  = ExpectedRunnable Text.Text
  | ExpectedResidual
  | ExpectedNotRecommended

expectedMatrixCell :: RuntimeMode -> Text.Text -> ExpectedMatrixCell
expectedMatrixCell runtimeMode rowIdValue =
  case lookup rowIdValue catalogEngines of
    Just engineValue -> ExpectedRunnable engineValue
    Nothing
      | rowIdValue `elem` residualMatrixRowIdsForMode runtimeMode -> ExpectedResidual
      | otherwise -> ExpectedNotRecommended
  where
    catalogEngines =
      [ (matrixRowId model, selectedEngine model)
      | model <- catalogForMode runtimeMode
      ]

readmeCellForMode :: RuntimeMode -> ReadmeMatrixRow -> String
readmeCellForMode runtimeMode row =
  case runtimeMode of
    AppleSilicon -> readmeAppleEngine row
    LinuxCpu -> readmeLinuxCpuEngine row
    LinuxGpu -> readmeLinuxGpuEngine row

readmeCellMatches :: ExpectedMatrixCell -> String -> Bool
readmeCellMatches expectedCell actualCell =
  case expectedCell of
    ExpectedRunnable engineValue -> actualCell == Text.unpack engineValue
    ExpectedResidual -> "Named residual" `isPrefixOf` actualCell
    ExpectedNotRecommended -> actualCell == "Not recommended"

expectedCellDescription :: ExpectedMatrixCell -> String
expectedCellDescription expectedCell =
  case expectedCell of
    ExpectedRunnable engineValue -> show (Text.unpack engineValue)
    ExpectedResidual -> "a Named residual cell"
    ExpectedNotRecommended -> show "Not recommended"

validateTestingDocOwnership :: Paths -> IO ()
validateTestingDocOwnership paths = do
  doctrineContents <- readFile (repoRoot paths </> "documents/engineering/testing.md")
  unless
    ("**Status**: Authoritative source" `isInfixOf` doctrineContents)
    (ioError (userError "documents/engineering/testing.md must remain an authoritative source"))
  strategyContents <- readFile (repoRoot paths </> "documents/development/testing_strategy.md")
  unless
    ("**Status**: Supporting reference" `isInfixOf` strategyContents)
    (ioError (userError "documents/development/testing_strategy.md must be a supporting reference"))
  unless
    ("support the canonical testing doctrine" `isInfixOf` strategyContents)
    ( ioError
        ( userError
            "documents/development/testing_strategy.md must describe itself as supporting the canonical testing doctrine"
        )
    )
  when
    ("canonical validation surface" `isInfixOf` strategyContents)
    ( ioError
        ( userError
            "documents/development/testing_strategy.md must not present itself as the canonical validation surface"
        )
    )

validateUnsupportedMonitoringStance :: Paths -> IO ()
validateUnsupportedMonitoringStance paths = do
  forM_ monitoringStancePaths $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    unless
      (monitoringUnsupportedStatement `isInfixOf` contents)
      ( ioError
          ( userError
              ( relativePath
                  <> " must declare the monitoring stance with the sentence: "
                  <> monitoringUnsupportedStatement
              )
          )
      )
  monitoringDocExists <- doesFileExist (repoRoot paths </> "documents/engineering/monitoring.md")
  when monitoringDocExists $
    ioError
      (userError "documents/engineering/monitoring.md must not exist while monitoring is unsupported")
  chartContents <- readFile (repoRoot paths </> "chart/values.yaml")
  when
    ("victoria-metrics-k8s-stack" `isInfixOf` chartContents)
    (ioError (userError "chart/values.yaml must not retain dormant monitoring-stack configuration"))

validatePhaseDoc :: FilePath -> String -> IO ()
validatePhaseDoc relativePath contents = do
  unless ("## Documentation Requirements" `isInfixOf` contents) $
    ioError (userError (relativePath <> " is missing the Documentation Requirements section"))
  let sprintBlocks = splitOn "\n## Sprint " contents
      normalizedBlocks =
        case sprintBlocks of
          [] -> []
          firstBlock : remainingBlocks -> firstBlock : map ("## Sprint " <>) remainingBlocks
  when (length normalizedBlocks <= 1) $
    ioError (userError (relativePath <> " must contain at least one sprint section"))
  forM_ (drop 1 normalizedBlocks) $ \block -> do
    unless ("**Status**:" `isInfixOf` block) $
      ioError (userError (relativePath <> " has a sprint without a status line"))
    unless ("**Docs to update**:" `isInfixOf` block) $
      ioError (userError (relativePath <> " has a sprint without a docs line"))
    unless ("### Objective" `isInfixOf` block && "### Deliverables" `isInfixOf` block && "### Validation" `isInfixOf` block && "### Remaining Work" `isInfixOf` block) $
      ioError (userError (relativePath <> " has a sprint missing one of the required sections"))

validateRelativeLinks :: Paths -> FilePath -> String -> IO ()
validateRelativeLinks paths relativePath contents =
  forM_ (extractMarkdownLinkTargets (stripFencedCodeBlocks contents)) $ \target -> do
    let normalizedTarget = trimLinkAnchor target
    when
      (isRepoRelativeTarget normalizedTarget)
      ( do
          let resolvedPath =
                repoRoot paths
                  </> normalise (takeDirectory relativePath </> normalizedTarget)
          exists <- doesPathExist resolvedPath
          unless exists $
            ioError
              ( userError
                  ( relativePath
                      <> " links to a missing relative target: "
                      <> target
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

extractMarkdownLinkTargets :: String -> [String]
extractMarkdownLinkTargets = go
  where
    go [] = []
    go ('!' : '[' : rest) = go ('[' : rest)
    go ('[' : rest) =
      case break (== ']') rest of
        (_, []) -> go rest
        (_label, ']' : '(' : afterOpen) ->
          extractLinkTarget afterOpen
        (_label, _ : remaining) -> go remaining
    go (_ : remaining) = go remaining

    extractLinkTarget afterOpen =
      case break (== ')') afterOpen of
        (target, ')' : remaining) -> target : go remaining
        _ -> go afterOpen

stripFencedCodeBlocks :: String -> String
stripFencedCodeBlocks contents =
  unlines (go False (lines contents))
  where
    go _ [] = []
    go insideFence (lineValue : remaining)
      | "```" `isPrefixOf` lineValue = go (not insideFence) remaining
      | insideFence = go insideFence remaining
      | otherwise = lineValue : go insideFence remaining

findLineIndex :: String -> [String] -> Maybe Int
findLineIndex target = go 0
  where
    go _ [] = Nothing
    go index (lineValue : remaining)
      | lineValue == target = Just index
      | otherwise = go (index + 1) remaining

isRepoRelativeTarget :: String -> Bool
isRepoRelativeTarget target =
  not (null target)
    && not ("#" `isPrefixOf` target)
    && not ("http://" `isPrefixOf` target)
    && not ("https://" `isPrefixOf` target)
    && not ("mailto:" `isPrefixOf` target)
    && not ("file://" `isPrefixOf` target)
    && not ("app://" `isPrefixOf` target)
    && not ("vscode://" `isPrefixOf` target)
    && case dropDrive target of
      '/' : _ -> False
      _ -> True

startsWithHeading :: String -> Bool
startsWithHeading contents =
  case dropWhile null (lines contents) of
    headingLine : _ -> "# " `isPrefixOf` headingLine
    [] -> False

trimLinkAnchor :: String -> String
trimLinkAnchor target =
  case break (== '#') target of
    (pathValue, _) -> pathValue

trimTrailingNewlines :: String -> String
trimTrailingNewlines =
  reverse . dropWhile (`elem` ['\n', '\r']) . reverse

trimWhitespaceString :: String -> String
trimWhitespaceString =
  dropWhileEnd isSpace . dropWhile isSpace

splitOn :: String -> String -> [String]
splitOn needle haystack
  | null needle = [haystack]
  | otherwise = go haystack
  where
    go value =
      case breakOn needle value of
        Nothing -> [value]
        Just (prefix, suffix) -> prefix : go suffix

breakOn :: String -> String -> Maybe (String, String)
breakOn needle = search ""
  where
    search _ [] = Nothing
    search prefix remaining
      | needle `isPrefixOf` remaining = Just (reverse prefix, drop (length needle) remaining)
      | otherwise =
          case remaining of
            current : rest -> search (current : prefix) rest
