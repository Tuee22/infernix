module Infernix.Lint.Docs
  ( runDocsLint,
  )
where

import Control.Monad (forM_, unless, when)
import Data.List (isInfixOf, isPrefixOf)
import Infernix.CommandRegistry
  ( renderCliReferenceCommandsSection,
    renderCliSurfaceFamiliesSection,
  )
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.Routes
  ( renderClusterBootstrapRouteChecksSection,
    renderEdgeRoutingInventorySection,
    renderHarborRouteSummarySection,
    renderMinioRouteSummarySection,
    renderPulsarRouteSummarySection,
    renderReadmeRouteSummarySection,
    renderWebPortalRoutesSection,
  )
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
    "python/linux-cuda/",
    "src/Generated/Contracts.hs",
    "docker/linux-base.Dockerfile",
    "docker/linux-cpu.Dockerfile",
    "docker/linux-cuda.Dockerfile",
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
  forM_ requiredDocs $ \relativePath -> do
    contents <- readFile (repoRoot paths </> relativePath)
    validateGovernedDocumentMetadata relativePath contents
    validateRelativeLinks paths relativePath contents
    validateForbiddenPhrases relativePath contents
  forM_ rootDocRules $ \rule -> do
    contents <- readFile (repoRoot paths </> rootDocPath rule)
    validateRootDocMetadata rule contents
    validateRelativeLinks paths (rootDocPath rule) contents
    validateForbiddenPhrases (rootDocPath rule) contents
  forM_ generatedSectionRules $ \rule -> do
    contents <- readFile (repoRoot paths </> generatedSectionPath rule)
    validateGeneratedSection rule contents
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

validateForbiddenPhrases :: FilePath -> String -> IO ()
validateForbiddenPhrases relativePath contents =
  when
    (any (`isInfixOf` contents) forbiddenPhrases)
    (ioError (userError ("forbidden retired-doctrine phrase found in " <> relativePath)))

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
          let (target, remainder) = break (== ')') afterOpen
           in case remainder of
                ')' : remaining -> target : go remaining
                _ -> go afterOpen
        (_label, _ : remaining) -> go remaining
    go (_ : remaining) = go remaining

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
    && head (dropDrive target) /= '/'

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
