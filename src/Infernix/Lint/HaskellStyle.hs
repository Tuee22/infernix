module Infernix.Lint.HaskellStyle
  ( runHaskellStyleLintWith,
    appleArtifactProvisioningViolations,
    appleClosureFixtureOwnershipViolations,
    appleMaterializationTransactionOwnershipViolations,
    artifactCapabilityBoundaryViolations,
    artifactWriterBoundaryViolations,
    boundedEngineOutputViolations,
    cappedEngineBoundaryViolations,
    isGeneratedHaskellProtoSource,
    linuxNativeMaterializationBoundaryViolations,
    nativeArtifactInvocationKernelOwnershipViolations,
    provisioningKernelOwnershipViolations,
    unsafeNativeBoundaryViolations,
    unboundedCeilingInstallViolations,
    unboundedDescriptorSpawnViolations,
    unboundedToolchainSpawnViolations,
    unboundedEngineSpawnViolations,
  )
where

import Data.Char (isAlphaNum, isSpace)
import Data.List (intercalate, isInfixOf, isSuffixOf, mapAccumL, sort)
import Data.Maybe (fromMaybe)
import Infernix.Config (Paths (..), discoverPathsWithHostManifest)
import Infernix.HostTools qualified as HostTools
import Infernix.Lint.Proto qualified as Proto
import System.Directory
  ( doesDirectoryExist,
    doesFileExist,
    listDirectory,
    withCurrentDirectory,
  )
import System.FilePath ((</>))

-- | Run the repo-owned inventory and readability checks around test-owned,
-- in-process formatter and linter callbacks. Keeping the heavyweight tool APIs
-- in the dedicated style component prevents every production executable from
-- linking them while this module remains the sole owner of the exact source
-- inventory and generated-source exclusion.
runHaskellStyleLintWith ::
  ([FilePath] -> IO ()) ->
  ([FilePath] -> IO ()) ->
  IO ()
runHaskellStyleLintWith checkFormatting checkHints = do
  paths <- discoverPathsWithHostManifest Nothing
  let root = repoRoot paths
  sources <- haskellSources root
  withCurrentDirectory root $ do
    checkFormatting sources
    checkHints sources
  checkReadabilityRules root sources
  putStrLn "haskell-style-check: ok"

haskellSources :: FilePath -> IO [FilePath]
haskellSources repoRoot = do
  sourceFiles <- concat <$> mapM (collectHsFiles . (repoRoot </>)) ["app", "src", "test"]
  pure
    ( sort
        ( filter
            (not . isGeneratedHaskellProtoSource)
            (map (makeRelative repoRoot) sourceFiles)
        )
    )

-- | The complete and deliberately exact style exclusion for checked-in
-- upstream @proto-lens-protoc@ output. The byte-exact source is owned by
-- 'Infernix.Lint.Proto'; similarly named handwritten modules remain in the
-- Ormolu, HLint, and readability-rule source inventory.
isGeneratedHaskellProtoSource :: FilePath -> Bool
isGeneratedHaskellProtoSource sourceFile =
  sourceFile `elem` Proto.generatedHaskellProtoFiles

collectHsFiles :: FilePath -> IO [FilePath]
collectHsFiles directoryPath = do
  exists <- doesDirectoryExist directoryPath
  if not exists
    then pure []
    else do
      children <- listDirectory directoryPath
      concat <$> mapM (collectChild . (directoryPath </>)) children
  where
    collectChild childPath = do
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then collectHsFiles childPath
        else do
          isFile <- doesFileExist childPath
          if isFile && hasHsExtension childPath
            then pure [childPath]
            else pure []

hasHsExtension :: FilePath -> Bool
hasHsExtension pathValue =
  any (`isSuffixOf` pathValue) repoOwnedHaskellExtensions

repoOwnedHaskellExtensions :: [String]
repoOwnedHaskellExtensions =
  [ ".hs",
    ".lhs",
    ".hs-boot",
    ".lhs-boot",
    ".hsig",
    ".lhsig"
  ]

checkReadabilityRules :: FilePath -> [FilePath] -> IO ()
checkReadabilityRules repoRoot sourceFiles = do
  violations <- concat <$> mapM (checkSourceReadability repoRoot) sourceFiles
  case violations of
    [] -> pure ()
    _ ->
      ioError
        ( userError
            ( "haskell-style-check: readability rules failed\n"
                <> intercalate "\n" violations
            )
        )

checkSourceReadability :: FilePath -> FilePath -> IO [String]
checkSourceReadability repoRoot sourceFile = do
  contents <- readFile (repoRoot </> sourceFile)
  let numberedLines = zip [1 :: Int ..] (lines contents)
  pure
    ( hangingCaseViolations sourceFile numberedLines
        <> aliasCommentViolations sourceFile numberedLines
        <> envFunctionViolations sourceFile numberedLines
        <> bareNameProcViolations sourceFile numberedLines
        <> ambientToolLookupViolations sourceFile numberedLines
        <> engineRuntimeBoundaryViolations sourceFile numberedLines
        <> sharedPhase7BoundaryViolations sourceFile numberedLines
        <> realnessFabricationViolations sourceFile numberedLines
        <> escapeTokenViolations sourceFile numberedLines
        <> unsafeNativeBoundaryViolations sourceFile numberedLines
        <> appleArtifactProvisioningViolations sourceFile numberedLines
        <> appleClosureFixtureOwnershipViolations sourceFile numberedLines
        <> appleMaterializationTransactionOwnershipViolations sourceFile numberedLines
        <> artifactCapabilityBoundaryViolations sourceFile numberedLines
        <> artifactWriterBoundaryViolations sourceFile numberedLines
        <> boundedEngineOutputViolations sourceFile numberedLines
        <> cappedEngineBoundaryViolations sourceFile numberedLines
        <> linuxNativeMaterializationBoundaryViolations sourceFile numberedLines
        <> nativeArtifactInvocationKernelOwnershipViolations sourceFile numberedLines
        <> provisioningKernelOwnershipViolations sourceFile numberedLines
        <> capabilityGatingViolations sourceFile numberedLines
    )

-- | Only the exact validator and capped-engine kernel may see the
-- constructor-bearing artifact capability representation or enter its
-- validation boundary. Runtime callers cannot copy a raw runner path out of
-- the shared-lock region.
artifactCapabilityBoundaryViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
artifactCapabilityBoundaryViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | otherwise =
      representationViolations <> boundaryViolations
  where
    sanitizedLines = sanitizeNativeBoundarySource numberedLines
    representationViolations =
      [ renderViolation lineNumber
      | sourceFile `notElem` artifactCapabilityRepresentationOwners,
        lineNumber <- artifactCapabilityImportLines sanitizedLines
      ]
    boundaryViolations =
      [ renderViolation lineNumber
      | sourceFile `notElem` artifactCapabilityBoundaryOwners,
        (lineNumber, codeLine) <- sanitizedLines,
        containsToken "withFirstValidatedEngineArtifact" codeLine
      ]
    renderViolation lineNumber =
      sourceFile
        <> ":"
        <> show lineNumber
        <> ": forbidden engine artifact capability access; only the exact validator and capped-engine kernel may enter the validated artifact boundary"

artifactCapabilityImportLines :: [(Int, String)] -> [Int]
artifactCapabilityImportLines =
  moduleImportLines artifactCapabilityModuleName

moduleImportLines :: String -> [(Int, String)] -> [Int]
moduleImportLines moduleName sanitizedLines =
  findImports sourceTokens
  where
    sourceTokens =
      [ (lineNumber, token)
      | (lineNumber, codeLine) <- maskNativeBoundaryPragmas sanitizedLines,
        token <- words codeLine
      ]

    findImports ((lineNumber, "import") : remainingTokens) =
      importMatches
        lineNumber
        remainingTokens
        ( dropWhile
            ((`elem` ["qualified", "safe"]) . snd)
            remainingTokens
        )
    findImports (_ : remainingTokens) =
      findImports remainingTokens
    findImports [] = []

    importMatches lineNumber remainingTokens afterModifiers =
      case afterModifiers of
        (_, moduleToken) : _
          | isExactModuleToken moduleName moduleToken ->
              lineNumber : findImports remainingTokens
        _ -> findImports remainingTokens

isExactModuleToken :: String -> String -> Bool
isExactModuleToken moduleName token =
  moduleName `isPrefixOfString` token
    && case drop (length moduleName) token of
      [] -> True
      nextCharacter : _ -> not (isAlphaNum nextCharacter || nextCharacter `elem` ['.', '_', '\''])

artifactCapabilityModuleName :: String
artifactCapabilityModuleName =
  "Infernix.Engines.Artifact.Capability"

artifactCapabilityRepresentationOwners :: [FilePath]
artifactCapabilityRepresentationOwners =
  [ "src/Infernix/Engines/Artifact/Internal.hs",
    "src/Infernix/Runtime/CappedEngine/Internal.hs"
  ]

artifactCapabilityBoundaryOwners :: [FilePath]
artifactCapabilityBoundaryOwners =
  "src/Infernix/Engines/Artifact.hs"
    : artifactCapabilityRepresentationOwners

-- | Raw artifact activation/reconciliation and exclusive materialization-lock
-- entrypoints stay inside their audited writer owners. Runtime readers and
-- unrelated production modules cannot add a cooperative writer by convention.
artifactWriterBoundaryViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
artifactWriterBoundaryViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | otherwise =
      internalImportViolations
        <> concatMap lineViolations sanitizedLines
  where
    sanitizedLines = sanitizeNativeBoundarySource numberedLines
    internalImportViolations =
      [ renderViolation
          lineNumber
          "forbidden raw artifact transaction implementation import"
      | sourceFile `notElem` artifactTransactionInternalImportOwners,
        lineNumber <-
          moduleImportLines
            "Infernix.Engines.Artifact.Internal"
            sanitizedLines
      ]
        <> [ renderViolation
               lineNumber
               "forbidden exclusive materialization-lock implementation import"
           | sourceFile `notElem` materializationLockInternalImportOwners,
             lineNumber <-
               moduleImportLines
                 "Infernix.Engines.MaterializationLock.Internal"
                 sanitizedLines
           ]
        <> [ renderViolation
               lineNumber
               "forbidden Poetry project-mutation lock implementation import"
           | sourceFile `notElem` pythonMutationLockInternalImportOwners,
             lineNumber <-
               moduleImportLines
                 "Infernix.Python.MutationLock.Internal"
                 sanitizedLines
           ]
        <> [ renderViolation
               lineNumber
               "forbidden engine download-cache lock implementation import"
           | sourceFile `notElem` downloadCacheLockInternalImportOwners,
             lineNumber <-
               moduleImportLines
                 "Infernix.Engines.DownloadCacheLock.Internal"
                 sanitizedLines
           ]

    lineViolations (lineNumber, codeLine) =
      [ renderViolation
          lineNumber
          "forbidden raw artifact transaction access"
      | sourceFile `notElem` artifactTransactionOwners,
        transactionToken <- artifactTransactionTokens,
        containsToken transactionToken codeLine
      ]
        <> [ renderViolation
               lineNumber
               "forbidden exclusive engine-materialization lock access"
           | sourceFile `notElem` engineMaterializationLockOwners,
             containsToken "withEngineMaterializationLock" codeLine
           ]
        <> [ renderViolation
               lineNumber
               "forbidden engine download-cache lock access"
           | sourceFile `notElem` downloadCacheLockInternalImportOwners,
             containsToken "withDownloadCacheMutationLockInternal" codeLine
           ]

    renderViolation lineNumber reason =
      sourceFile
        <> ":"
        <> show lineNumber
        <> ": "
        <> reason
        <> "; engine-root writers must remain inside the audited materialization authority boundary"

artifactTransactionOwners :: [FilePath]
artifactTransactionOwners =
  [ "src/Infernix/Engines/Artifact/Internal.hs",
    "src/Infernix/Engines/Artifact/Activation.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

engineMaterializationLockOwners :: [FilePath]
engineMaterializationLockOwners =
  [ "src/Infernix/Engines/MaterializationLock/Internal.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

artifactTransactionInternalImportOwners :: [FilePath]
artifactTransactionInternalImportOwners =
  [ "src/Infernix/Engines/Artifact.hs",
    "src/Infernix/Engines/Artifact/Activation.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

materializationLockInternalImportOwners :: [FilePath]
materializationLockInternalImportOwners =
  [ "src/Infernix/Engines/Artifact/Activation.hs",
    "src/Infernix/Engines/Artifact/Internal.hs",
    "src/Infernix/Engines/MaterializationLock.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

pythonMutationLockInternalImportOwners :: [FilePath]
pythonMutationLockInternalImportOwners =
  [ "src/Infernix/Engines/Provisioning.hs",
    "src/Infernix/Python.hs"
  ]

downloadCacheLockInternalImportOwners :: [FilePath]
downloadCacheLockInternalImportOwners =
  [ "src/Infernix/Engines/DownloadCacheLock/Internal.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

artifactTransactionTokens :: [String]
artifactTransactionTokens =
  [ "activateAppleEngineArtifactWithInstalledSmoke",
    "activateAppleEngineArtifactWithInstalledPythonSourceIsolationSmoke",
    "activateEngineArtifactAfterCheck",
    "activateLinuxEngineArtifactWithInstalledSmoke",
    "withEngineArtifactActivation",
    "finishEngineArtifactActivation",
    "installEngineArtifactRoot",
    "installEngineArtifactRootWithExpectedDigest",
    "installEngineArtifactRootWithObserverForTest",
    "installEngineArtifactRootWithPendingActionForTest",
    "installEngineArtifactRootWithCleanupObserverForTest",
    "reconcileEngineArtifactRoot"
  ]

-- | The capped-engine implementation is the sole owner of raw engine process
-- descriptions and environment rendering. The hidden facade may import the
-- implementation only to re-export closed semantic operations.
cappedEngineBoundaryViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
cappedEngineBoundaryViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | otherwise =
      internalImportViolations
        <> concatMap lineViolations sanitizedLines
  where
    sanitizedLines = sanitizeNativeBoundarySource numberedLines
    internalImportViolations =
      [ renderViolation
          lineNumber
          "forbidden capped-engine implementation import"
      | sourceFile /= cappedEngineFacadeFile,
        lineNumber <-
          moduleImportLines
            cappedEngineInternalModuleName
            sanitizedLines
      ]
        <> [ renderViolation
               lineNumber
               "forbidden capped-engine output-capture implementation import"
           | sourceFile /= cappedEngineKernelFile,
             lineNumber <-
               moduleImportLines
                 cappedEngineOutputCaptureModuleName
                 sanitizedLines
           ]
    lineViolations (lineNumber, codeLine) =
      [ renderViolation
          lineNumber
          "forbidden raw capped-engine process authority"
      | sourceFile /= cappedEngineKernelFile,
        authorityToken <- rawCappedEngineAuthorityTokens,
        containsToken authorityToken codeLine
      ]
        <> [ renderViolation
               lineNumber
               "forbidden subprocess-environment rendering"
           | sourceFile
               `notElem` [ boundedCommandKernelFile,
                           cappedEngineKernelFile
                         ],
             containsToken "renderSubprocessEnv" codeLine
           ]

    renderViolation lineNumber reason =
      sourceFile
        <> ":"
        <> show lineNumber
        <> ": "
        <> reason
        <> "; use a closed typed CappedEngine operation and keep SubprocessEnv opaque"

cappedEngineFacadeFile :: FilePath
cappedEngineFacadeFile =
  "src/Infernix/Runtime/CappedEngine.hs"

cappedEngineInternalModuleName :: String
cappedEngineInternalModuleName =
  "Infernix.Runtime.CappedEngine.Internal"

cappedEngineOutputCaptureModuleName :: String
cappedEngineOutputCaptureModuleName =
  "Infernix.Runtime.CappedEngine.OutputCapture"

rawCappedEngineAuthorityTokens :: [String]
rawCappedEngineAuthorityTokens =
  [ "DirectEngineCommand",
    "EngineCommand",
    "directEngineCommand",
    "nativeArtifactArgumentsForTest",
    "nativeArtifactInstallRoots",
    "renderNativeArtifactArguments",
    "resolvePythonWorkerCommand",
    "runExecutableProcess",
    "runExecutableStdioEngine"
  ]

-- | Engine output must be captured by the fixed strict bounded reader. Lazy or
-- unbounded handle reads would retain the artifact read lock while allowing
-- attacker-controlled parent-memory growth.
boundedEngineOutputViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
boundedEngineOutputViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden unbounded engine-output capture; use the fixed strict bounded CappedEngine output reader"
      | (lineNumber, codeLine) <-
          sanitizeNativeBoundarySource numberedLines,
        token <- unboundedEngineOutputTokens,
        containsToken token codeLine
      ]

unboundedEngineOutputTokens :: [String]
unboundedEngineOutputTokens =
  [ "hGetContents",
    "readAllText"
  ]

-- | Linux image materialization is a closed catalog operation. Production
-- callers may request the complete catalog, but cannot inspect raw recipe
-- fields, mint manifests, select a candidate root, or
-- invoke the authority-scoped implementation directly.
linuxNativeMaterializationBoundaryViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
linuxNativeMaterializationBoundaryViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | sourceFile == linuxNativeMaterializationOwner = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden raw Linux native materialization access; use the closed complete-catalog materializer"
      | (lineNumber, codeLine) <-
          sanitizeNativeBoundarySource numberedLines,
        token <- rawLinuxNativeMaterializationTokens,
        containsToken token codeLine
      ]

linuxNativeMaterializationOwner :: FilePath
linuxNativeMaterializationOwner =
  "src/Infernix/Engines/LinuxNative.hs"

rawLinuxNativeMaterializationTokens :: [String]
rawLinuxNativeMaterializationTokens =
  [ "linuxNativeEngineBuildPlan",
    "manifestForLinuxNativeEngineArtifact",
    "materializeLinuxNativeEnginesAt",
    "materializeLinuxNativeEngineArtifactUnlocked",
    "linuxNativeEngineName",
    "linuxNativeEngineArtifactKind",
    "linuxNativeEngineSourceRef",
    "linuxNativeEngineVersion",
    "linuxNativeRuntimeVersion"
  ]

-- | Keep the lifecycle and bounded-subprocess kernels on public Haskell APIs.
-- Internal @process@ modules and inline-C are forbidden throughout production.
-- Direct foreign imports are forbidden throughout repository-owned Haskell.
unsafeNativeBoundaryViolations :: FilePath -> [(Int, String)] -> [String]
unsafeNativeBoundaryViolations sourceFile numberedLines
  | not (isRepoOwnedHaskellSource sourceFile) = []
  | otherwise =
      concatMap lineViolations sanitizedLines
        <> foreignImportViolations
  where
    sanitizedLines = sanitizeNativeBoundarySource numberedLines
    declarationLines = maskNativeBoundaryPragmas sanitizedLines
    lineViolations (lineNumber, codeLine) =
      [ nativeBoundaryViolation
          lineNumber
          "forbidden internal process module; bounded subprocess supervision must use only public System.Process and System.Posix APIs"
      | any (`isInfixOf` codeLine) forbiddenProcessInternalModules
      ]
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden inline-C use; repository-owned lifecycle and subprocess boundaries must be implemented in Haskell"
           | "Language.C.Inline" `isInfixOf` codeLine
           ]
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden raw POSIX fork/exec primitive outside the bounded-command kernel"
           | isProductionHaskellSource sourceFile,
             sourceFile /= boundedCommandKernelFile,
             needle <- forbiddenRawPosixProcessTokens,
             containsToken needle codeLine
           ]
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden CPP macro definition; native-boundary tokens must remain visible to source lint"
           | isCppDefine codeLine
           ]
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden subprocess protocol/activity import outside its audited kernel owner"
           | isProductionHaskellSource sourceFile,
             forbiddenSubprocessCapabilityImport sourceFile codeLine
           ]
    foreignImportViolations =
      foreignImportDeclarationViolations
        declarationLines
        nativeBoundaryViolation
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden direct foreign export; repository-owned native implementation boundaries are not permitted"
           | lineNumber <- foreignDeclarationStartLines "export" declarationLines
           ]
        <> [ nativeBoundaryViolation
               lineNumber
               "forbidden ForeignFunctionInterface extension; repository-owned direct FFI is not permitted"
           | lineNumber <- foreignFunctionInterfacePragmaLines sanitizedLines
           ]
    nativeBoundaryViolation lineNumber reason =
      sourceFile
        <> ":"
        <> show lineNumber
        <> ": "
        <> reason
        <> " (see documents/architecture/managed_state_transitions.md)"

forbiddenProcessInternalModules :: [String]
forbiddenProcessInternalModules =
  [ "System.Process.Internal",
    "System.Process.Internals",
    "System.Posix.Process.Internal",
    "System.Posix.Process.Internals"
  ]

boundedCommandKernelFile :: FilePath
boundedCommandKernelFile =
  "src/Infernix/Cluster/Subprocess.hs"

isRepoOwnedHaskellSource :: FilePath -> Bool
isRepoOwnedHaskellSource =
  hasHsExtension

isProductionHaskellSource :: FilePath -> Bool
isProductionHaskellSource sourceFile =
  any
    (`isPrefixOfString` sourceFile)
    ["app/", "src/"]

isCppDefine :: String -> Bool
isCppDefine codeLine =
  case dropWhile isSpace codeLine of
    '#' : remaining ->
      case words remaining of
        directive : _ -> directive == "define"
        [] -> False
    _ -> False

forbiddenSubprocessCapabilityImport :: FilePath -> String -> Bool
forbiddenSubprocessCapabilityImport sourceFile codeLine
  | isModuleDeclaration codeLine = False
  | "Infernix.Cluster.Subprocess.Protocol" `isInfixOf` codeLine =
      sourceFile /= boundedCommandKernelFile
  | "Infernix.Cluster.Subprocess.Activity" `isInfixOf` codeLine =
      sourceFile
        `notElem` [ boundedCommandKernelFile,
                    "src/Infernix/Cluster/Subprocess/Protocol.hs"
                  ]
  | otherwise = False

isModuleDeclaration :: String -> Bool
isModuleDeclaration codeLine =
  case words codeLine of
    "module" : _ -> True
    _ -> False

forbiddenRawPosixProcessTokens :: [String]
forbiddenRawPosixProcessTokens =
  [ "forkProcess",
    "forkProcessWithUnmask",
    "executeFile"
  ]

foreignImportDeclarationViolations ::
  [(Int, String)] ->
  (Int -> String -> String) ->
  [String]
foreignImportDeclarationViolations sanitizedLines renderViolation =
  [ renderViolation
      lineNumber
      "forbidden direct foreign import; repository-owned direct FFI is not permitted"
  | lineNumber <- foreignImportStartLines sanitizedLines
  ]

foreignImportStartLines :: [(Int, String)] -> [Int]
foreignImportStartLines =
  foreignDeclarationStartLines "import"

foreignDeclarationStartLines :: String -> [(Int, String)] -> [Int]
foreignDeclarationStartLines declarationKind sanitizedLines =
  adjacentForeignDeclarations
    [ (lineNumber, token)
    | (lineNumber, codeLine) <- sanitizedLines,
      token <- words codeLine
    ]
  where
    adjacentForeignDeclarations
      ((lineNumber, "foreign") : (_, candidateKind) : remainingTokens)
        | candidateKind == declarationKind =
            lineNumber : adjacentForeignDeclarations remainingTokens
    adjacentForeignDeclarations (_ : remainingTokens) =
      adjacentForeignDeclarations remainingTokens
    adjacentForeignDeclarations [] = []

data NativeBoundaryPragmaMaskState
  = OutsideNativeBoundaryPragma
  | InsideNativeBoundaryPragma

maskNativeBoundaryPragmas :: [(Int, String)] -> [(Int, String)]
maskNativeBoundaryPragmas numberedLines =
  snd (mapAccumL maskLine OutsideNativeBoundaryPragma numberedLines)
  where
    maskLine state (lineNumber, lineValue) =
      let (nextState, maskedLine) = maskPragmaLine state lineValue
       in (nextState, (lineNumber, maskedLine))

    maskPragmaLine state [] = (state, [])
    maskPragmaLine OutsideNativeBoundaryPragma ('{' : '-' : '#' : remaining) =
      prependPragmaMask 3 (maskPragmaLine InsideNativeBoundaryPragma remaining)
    maskPragmaLine OutsideNativeBoundaryPragma (character : remaining) =
      prependPragmaCharacter character (maskPragmaLine OutsideNativeBoundaryPragma remaining)
    maskPragmaLine InsideNativeBoundaryPragma ('#' : '-' : '}' : remaining) =
      prependPragmaMask 3 (maskPragmaLine OutsideNativeBoundaryPragma remaining)
    maskPragmaLine InsideNativeBoundaryPragma (_ : remaining) =
      prependPragmaMask 1 (maskPragmaLine InsideNativeBoundaryPragma remaining)

    prependPragmaMask characterCount (state, remaining) =
      (state, replicate characterCount ' ' <> remaining)

    prependPragmaCharacter character (state, remaining) =
      (state, character : remaining)

foreignFunctionInterfacePragmaLines :: [(Int, String)] -> [Int]
foreignFunctionInterfacePragmaLines sanitizedLines =
  [ lineNumber
  | (lineNumber, pragmaBody) <- nativeBoundaryPragmaBodies sanitizedLines,
    case pragmaBodyTokens pragmaBody of
      "LANGUAGE" : extensions ->
        "ForeignFunctionInterface" `elem` extensions
      _ -> False
  ]

pragmaBodyTokens :: String -> [String]
pragmaBodyTokens =
  words . map normalizePragmaCharacter
  where
    normalizePragmaCharacter character
      | isAlphaNum character = character
      | otherwise = ' '

nativeBoundaryPragmaBodies :: [(Int, String)] -> [(Int, String)]
nativeBoundaryPragmaBodies =
  collectOutside
  where
    collectOutside [] = []
    collectOutside ((lineNumber, lineValue) : remainingLines) =
      case breakAtSubstring "{-#" lineValue of
        Nothing -> collectOutside remainingLines
        Just (_, afterOpening) ->
          collectInside
            lineNumber
            []
            ((lineNumber, afterOpening) : remainingLines)

    collectInside _ _ [] = []
    collectInside startLine bodyParts ((lineNumber, lineValue) : remainingLines) =
      case breakAtSubstring "#-}" lineValue of
        Nothing ->
          collectInside startLine (lineValue : bodyParts) remainingLines
        Just (finalPart, afterClosing) ->
          (startLine, unlines (reverse (finalPart : bodyParts)))
            : collectOutside
              ((lineNumber, afterClosing) : remainingLines)

breakAtSubstring :: String -> String -> Maybe (String, String)
breakAtSubstring needle =
  search []
  where
    search _ [] = Nothing
    search prefix remaining
      | needle `isPrefixOfString` remaining =
          Just (reverse prefix, drop (length needle) remaining)
    search prefix (character : remaining) =
      search (character : prefix) remaining

data NativeBoundaryLexState
  = NativeBoundaryCode
  | NativeBoundaryBlockComment Int
  | NativeBoundaryString
  | NativeBoundaryPragma

sanitizeNativeBoundarySource :: [(Int, String)] -> [(Int, String)]
sanitizeNativeBoundarySource numberedLines =
  snd (mapAccumL sanitizeLine NativeBoundaryCode numberedLines)
  where
    sanitizeLine state (lineNumber, lineValue) =
      let (nextState, sanitizedLine) = sanitizeNativeBoundaryLine state lineValue
       in (nextState, (lineNumber, sanitizedLine))

sanitizeNativeBoundaryLine :: NativeBoundaryLexState -> String -> (NativeBoundaryLexState, String)
sanitizeNativeBoundaryLine =
  sanitize
  where
    sanitize state [] = (state, [])
    sanitize NativeBoundaryCode ('{' : '-' : '#' : remaining) =
      prependSanitized "{-#" (sanitize NativeBoundaryPragma remaining)
    sanitize NativeBoundaryCode ('-' : '-' : remaining) =
      (NativeBoundaryCode, replicate (length remaining + 2) ' ')
    sanitize NativeBoundaryCode ('{' : '-' : remaining) =
      prependMasked 2 (sanitize (NativeBoundaryBlockComment 1) remaining)
    sanitize NativeBoundaryCode ('"' : remaining) =
      prependMasked 1 (sanitize NativeBoundaryString remaining)
    sanitize NativeBoundaryCode ('\'' : remaining) =
      case takeCharacterLiteral remaining of
        Just (literalTail, afterLiteral) ->
          prependMasked
            (1 + length literalTail)
            (sanitize NativeBoundaryCode afterLiteral)
        Nothing ->
          prependSanitized "'" (sanitize NativeBoundaryCode remaining)
    sanitize NativeBoundaryCode (character : remaining) =
      prependSanitized [character] (sanitize NativeBoundaryCode remaining)
    sanitize (NativeBoundaryBlockComment depth) ('{' : '-' : remaining) =
      prependMasked 2 (sanitize (NativeBoundaryBlockComment (depth + 1)) remaining)
    sanitize (NativeBoundaryBlockComment 1) ('-' : '}' : remaining) =
      prependMasked 2 (sanitize NativeBoundaryCode remaining)
    sanitize (NativeBoundaryBlockComment depth) ('-' : '}' : remaining) =
      prependMasked 2 (sanitize (NativeBoundaryBlockComment (depth - 1)) remaining)
    sanitize state@(NativeBoundaryBlockComment _) (_ : remaining) =
      prependMasked 1 (sanitize state remaining)
    sanitize NativeBoundaryString ('\\' : _escapedCharacter : remaining) =
      prependMasked 2 (sanitize NativeBoundaryString remaining)
    sanitize NativeBoundaryString ('"' : remaining) =
      prependMasked 1 (sanitize NativeBoundaryCode remaining)
    sanitize NativeBoundaryString (_ : remaining) =
      prependMasked 1 (sanitize NativeBoundaryString remaining)
    sanitize NativeBoundaryPragma ('#' : '-' : '}' : remaining) =
      prependSanitized "#-}" (sanitize NativeBoundaryCode remaining)
    sanitize NativeBoundaryPragma (character : remaining) =
      prependSanitized [character] (sanitize NativeBoundaryPragma remaining)

takeCharacterLiteral :: String -> Maybe (String, String)
takeCharacterLiteral remaining =
  case remaining of
    character : '\'' : afterLiteral
      | character /= '\\' && character /= '\'' ->
          Just ([character, '\''], afterLiteral)
    '\\' : '\'' : '\'' : afterLiteral ->
      Just ("\\''", afterLiteral)
    '\\' : escaped : afterEscape ->
      takeEscapedCharacterLiteral escaped afterEscape
    _ -> Nothing

takeEscapedCharacterLiteral :: Char -> String -> Maybe (String, String)
takeEscapedCharacterLiteral escaped afterEscape =
  case break (== '\'') afterEscape of
    (escapeTail, '\'' : afterLiteral)
      | validCharacterEscape escaped escapeTail ->
          Just ('\\' : escaped : escapeTail <> "'", afterLiteral)
    _ -> Nothing

validCharacterEscape :: Char -> String -> Bool
validCharacterEscape escaped escapeTail =
  not (isSpace escaped)
    && escaped /= '\''
    && not (any isSpace escapeTail)

prependSanitized :: String -> (NativeBoundaryLexState, String) -> (NativeBoundaryLexState, String)
prependSanitized prefix (state, remaining) =
  (state, prefix <> remaining)

prependMasked :: Int -> (NativeBoundaryLexState, String) -> (NativeBoundaryLexState, String)
prependMasked characterCount (state, remaining) =
  (state, replicate characterCount ' ' <> remaining)

-- | Sprint 6.39 (managed-state-transition doctrine) — capability-gating lint.
-- Reject raw destructive shell primitives (@rm -rf@ / @docker exec ... rm@) and
-- empty subprocess environments (@env = Just []@). Retained-state deletion must
-- go through the lease-gated teardown (Sprint 2.14), and every subprocess must
-- carry a typed 'Infernix.Cluster.Subprocess.SubprocessEnv' (which always
-- carries @HOME@/@TMPDIR@) rather than an empty environment. The
-- cluster-lifecycle module has no raw-shell exemption; its Haskell filesystem
-- deletion is an unexported implementation detail of the lease-consuming
-- retained-state transition. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
capabilityGatingViolations :: FilePath -> [(Int, String)] -> [String]
capabilityGatingViolations sourceFile numberedLines =
  rawDestructiveViolations sourceFile numberedLines
    <> emptySubprocessEnvViolations sourceFile numberedLines
    <> unboundedExecViolations sourceFile numberedLines
    <> unboundedEngineSpawnViolations sourceFile numberedLines
    <> unboundedCeilingInstallViolations sourceFile numberedLines
    <> unboundedDescriptorSpawnViolations sourceFile numberedLines
    <> unboundedToolchainSpawnViolations sourceFile numberedLines
    <> unboundedHttpViolations sourceFile numberedLines
    <> threadDelayViolations sourceFile numberedLines
    <> predictedAdmissionViolations sourceFile numberedLines

rawDestructiveViolations :: FilePath -> [(Int, String)] -> [String]
rawDestructiveViolations sourceFile numberedLines
  | sourceFile `elem` rawDestructiveExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": " <> reason
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        reason <- rawDestructiveReasons lineValue
      ]

rawDestructiveReasons :: String -> [String]
rawDestructiveReasons lineValue =
  [ "forbidden raw `rm -rf` scrub; route retained-state deletion through the lease-gated teardown (Sprint 2.14; see documents/architecture/managed_state_transitions.md)"
  | any (`isInfixOf` lineValue) ["rm -rf", "rm -fr"]
  ]
    <> [ "forbidden `docker exec ... rm` destructive primitive; route through the lease-gated teardown (see documents/architecture/managed_state_transitions.md)"
       | "docker exec" `isInfixOf` lineValue,
         " rm " `isInfixOf` lineValue
       ]

rawDestructiveExemptedFiles :: [FilePath]
rawDestructiveExemptedFiles =
  [ -- This lint module names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

emptySubprocessEnvViolations :: FilePath -> [(Int, String)] -> [String]
emptySubprocessEnvViolations sourceFile numberedLines
  | sourceFile `elem` emptySubprocessEnvExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden empty subprocess environment `env = Just []`; build a typed Infernix.Cluster.Subprocess.SubprocessEnv (which always carries HOME/TMPDIR) instead (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        "env = Just []" `isInfixOf` lineValue
      ]

emptySubprocessEnvExemptedFiles :: [FilePath]
emptySubprocessEnvExemptedFiles =
  [ -- This lint module names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Sprint 3.15 (managed-state-transition doctrine) — reject raw unbounded
-- process spawns outside the bounded-command kernel. Every cluster-lifecycle
-- subprocess must go through
-- 'Infernix.Cluster.Subprocess.runBoundedCommand', which carries a required
-- 'Infernix.Cluster.Subprocess.Timeout' and returns a total
-- 'Infernix.Cluster.Subprocess.CommandOutcome', so an unbounded exec — the
-- class that produced the ~23-minute registry @docker pull@ hang — is
-- unrepresentable. The exemption list is deliberately shrinking:
-- 'ProcessMonitor.hs' was retired onto the kernel by Sprint 6.41 and
-- 'Cluster.hs' by Sprint 2.16; the engine/runtime/host-tool spawn surface
-- (long-lived inference runners, host prerequisite probes, Python tooling) is a
-- different domain not owned by the cluster kernel. The kernel module and this
-- lint module (which names the tokens as literals) are permanently exempt.
-- Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
unboundedExecViolations :: FilePath -> [(Int, String)] -> [String]
unboundedExecViolations sourceFile numberedLines
  -- The bounded-command doctrine governs the production cluster surface, not the
  -- test harness, which orchestrates real clusters.
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedExecExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw unbounded process spawn `" <> needle <> "`; route it through Infernix.Cluster.Subprocess.runBoundedCommand (a required Timeout + total CommandOutcome) so an unbounded exec is unrepresentable (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenUnboundedExecTokens,
        containsToken needle lineValue
      ]

-- | Sprint 6.44 closed a real hole here. Token matching is whole-token, so
-- @withCreateProcess@ never matched @createProcess@ and a non-exempt module
-- could bracket an unbounded spawn in plain sight; @HostTools.hs@ already used
-- exactly that call. @runInteractiveProcess@, @runProcess@, and
-- @cleanupProcess@ are the remaining public @System.Process@ launch and
-- teardown primitives with the same property.
forbiddenUnboundedExecTokens :: [String]
forbiddenUnboundedExecTokens =
  [ "readCreateProcessWithExitCode",
    "readProcessWithExitCode",
    "readProcess",
    "createProcess",
    "withCreateProcess",
    "runInteractiveProcess",
    "runProcess",
    "waitForProcess",
    "spawnProcess",
    "callProcess",
    "callCommand",
    "cleanupProcess"
  ]

-- | Phase 1 Sprint 1.20 — Apple engine artifacts may provision only through
-- the opaque, bounded provisioning grant. The artifact facade, transaction
-- implementation, and provisioning modules therefore cannot import
-- 'System.Process' or invoke one of its raw process primitives directly. The
-- sole process owner remains the bounded-command kernel.
appleArtifactProvisioningViolations :: FilePath -> [(Int, String)] -> [String]
appleArtifactProvisioningViolations sourceFile numberedLines
  | sourceFile `notElem` appleArtifactProvisioningFiles = []
  | otherwise =
      concatMap lineViolations (sanitizeNativeBoundarySource numberedLines)
  where
    lineViolations (lineNumber, codeLine) =
      [ renderViolation lineNumber "forbidden System.Process access"
      | "System.Process" `isInfixOf` codeLine
      ]
        <> [ renderViolation lineNumber ("forbidden raw process primitive `" <> needle <> "`")
           | needle <- forbiddenUnboundedExecTokens,
             containsToken needle codeLine
           ]
        <> [ renderViolation lineNumber ("forbidden delegation to legacy unbounded Python helper `" <> needle <> "`")
           | needle <- forbiddenAppleProvisioningHelperTokens,
             containsToken needle codeLine
           ]
        <> [ renderViolation lineNumber "forbidden direct bounded-command kernel use outside the provisioning facade"
           | sourceFile /= appleProvisioningFacadeFile,
             containsToken "runBoundedCommand" codeLine
           ]
    renderViolation lineNumber reason =
      sourceFile
        <> ":"
        <> show lineNumber
        <> ": "
        <> reason
        <> "; Apple artifact provisioning must use the opaque bounded Infernix.Engines.Provisioning grant (see documents/architecture/managed_state_transitions.md)"

appleArtifactProvisioningFiles :: [FilePath]
appleArtifactProvisioningFiles =
  [ "src/Infernix/Engines/AppleSilicon.hs",
    "src/Infernix/Engines/AppleSilicon/Internal.hs",
    "src/Infernix/Engines/Artifact.hs",
    "src/Infernix/Engines/Artifact/Internal.hs",
    appleProvisioningFacadeFile,
    "src/Infernix/Engines/Provisioning/Internal.hs"
  ]

appleProvisioningFacadeFile :: FilePath
appleProvisioningFacadeFile =
  "src/Infernix/Engines/Provisioning.hs"

forbiddenAppleProvisioningHelperTokens :: [String]
forbiddenAppleProvisioningHelperTokens =
  [ "ensurePoetryExecutable",
    "ensurePoetryProjectReady",
    "liftProvisioningIO"
  ]

-- | The indexed Apple materialization runner is private to the concrete Apple
-- materializer implementation. Other production modules receive only the
-- public materialization command; they cannot name an intermediate phase or
-- reintroduce the deleted callback-shaped request interpreter.
appleMaterializationTransactionOwnershipViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
appleMaterializationTransactionOwnershipViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | sourceFile `elem` appleMaterializationTransactionOwners = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden Apple materialization transaction kernel access; "
          <> "only the concrete Apple materializer may advance its private indexed runner"
      | (lineNumber, codeLine) <- sanitizeNativeBoundarySource numberedLines,
        token <- appleMaterializationTransactionTokens,
        containsToken token codeLine
      ]

appleMaterializationTransactionOwners :: [FilePath]
appleMaterializationTransactionOwners =
  ["src/Infernix/Engines/AppleSilicon/Internal.hs"]

appleMaterializationTransactionTokens :: [String]
appleMaterializationTransactionTokens =
  [ "Infernix.Engines.AppleSilicon.MaterializationTransaction",
    "MaterializationRequest",
    "closedMaterializationRequest",
    "runMaterializationTransaction",
    "completeCandidate",
    "AppleMaterializationSession",
    "beginAppleMaterialization",
    "prepareMetalEngineCandidate",
    "writeMetalEngineCandidatePayload",
    "completeMetalEngineCandidate",
    "cleanupMetalEngineCandidate"
  ]

-- | Generic provisioning mutation construction, command compilation, and
-- executable resolution are owned by the bounded subprocess kernel, its
-- indexed provisioning facade, and the hidden final-path activation
-- interpreter. Other production modules receive only closed provisioning
-- operations and cannot assemble a raw mutation or compile one of its command
-- specifications.
provisioningKernelOwnershipViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
provisioningKernelOwnershipViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden generic provisioning kernel access; "
          <> "only the bounded subprocess kernel, indexed provisioning facade, and hidden activation interpreter may construct mutations or compile commands"
      | sourceFile `notElem` provisioningKernelOwners,
        (lineNumber, codeLine) <- sanitizeNativeBoundarySource numberedLines,
        token <- provisioningKernelTokens,
        containsToken token codeLine
      ]

provisioningKernelOwners :: [FilePath]
provisioningKernelOwners =
  [ "src/Infernix/Cluster/Subprocess.hs",
    "src/Infernix/Engines/Artifact/Activation.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

provisioningKernelTokens :: [String]
provisioningKernelTokens =
  [ "observeProvisioningMutationRoot",
    "provisioningCreateDirectoryLeaf",
    "provisioningCreateSymbolicLinkLeaf",
    "provisioningRemoveTreeLeaf",
    "provisioningRenameSiblingDirectory",
    "provisioningRenameSiblingRegularFile",
    "provisioningReplaceSiblingRegularFile",
    "runProvisioningFilesystemMutation",
    "compileProvisioningCommand",
    "compileProvisioningCommandWithExecutable",
    "compileProvisioningCommandWithExecutableInMutationRoot",
    "resolveProvisioningCommandExecutable"
  ]

-- | The general native-artifact invocation plan is an internal bridge between
-- the closed capped-engine interpreter and the bounded subprocess kernel.
-- Other production modules cannot construct a raw plan or invoke the kernel
-- directly.
nativeArtifactInvocationKernelOwnershipViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
nativeArtifactInvocationKernelOwnershipViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | sourceFile `elem` nativeArtifactInvocationKernelOwners = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden native-artifact invocation kernel access; "
          <> "only the bounded subprocess kernel and hidden capped-engine interpreter may construct or run an invocation plan"
      | (lineNumber, codeLine) <- sanitizeNativeBoundarySource numberedLines,
        token <- nativeArtifactInvocationKernelTokens,
        containsToken token codeLine
      ]

nativeArtifactInvocationKernelOwners :: [FilePath]
nativeArtifactInvocationKernelOwners =
  [ "src/Infernix/Cluster/Subprocess.hs",
    "src/Infernix/Runtime/CappedEngine/Internal.hs"
  ]

nativeArtifactInvocationKernelTokens :: [String]
nativeArtifactInvocationKernelTokens =
  [ "NativeArtifactInvocationPlan",
    "nativeArtifactInvocationPlan",
    "runBoundedNativeArtifact"
  ]

-- | The deterministic Mach-O byte/finite-graph interpreter is test support
-- owned by the Apple materialization kernel. Production modules may not invoke
-- or import it; production flow uses descriptor-backed source facades.
appleClosureFixtureOwnershipViolations ::
  FilePath ->
  [(Int, String)] ->
  [String]
appleClosureFixtureOwnershipViolations sourceFile numberedLines
  | not (isProductionHaskellSource sourceFile) = []
  | sourceFile `elem` appleClosureFixtureOwners = []
  | otherwise =
      [ sourceFile
          <> ":"
          <> show lineNumber
          <> ": forbidden Apple Mach-O fixture interpreter access; production closure inspection must use the bounded otool interpreter"
      | (lineNumber, codeLine) <- sanitizeNativeBoundarySource numberedLines,
        token <- appleClosureFixtureTokens,
        containsToken token codeLine
      ]

appleClosureFixtureOwners :: [FilePath]
appleClosureFixtureOwners =
  [ "src/Infernix/Engines/AppleSilicon/Internal.hs",
    "src/Infernix/Engines/Provisioning.hs"
  ]

appleClosureFixtureTokens :: [String]
appleClosureFixtureTokens =
  [ "MachOFixturePlan",
    "inspectMachOFixtureForTest",
    "resolveMachOPathsFixtureForTest"
  ]

-- | Phase 6 Sprint 6.42 (memory-safety-by-construction doctrine) — reject a raw
-- engine subprocess spawn outside the capped-engine kernel. An inference engine
-- subprocess must run only through a closed semantic operation in
-- 'Infernix.Runtime.CappedEngine', which requires an 'ExecutableModel' carrying
-- a resource-indexed grant and verified enforcer. Raw commands, argument
-- vectors, working directories, and rendered environments remain in the hidden
-- kernel. The raw spawn primitives have no type-level chokepoint, so this
-- line-based gate keeps a new engine-spawn call site on the grant-gated kernel,
-- mirroring the 'unboundedExecViolations' / 'threadDelayViolations' per-rule
-- exemption pattern. The fixed Darwin observer kernel owns only its closed
-- @/usr/bin/top@ and @/usr/bin/footprint@ specifications. Canonical doctrine:
-- documents/architecture/bounded_inference_memory.md.
unboundedEngineSpawnViolations :: FilePath -> [(Int, String)] -> [String]
unboundedEngineSpawnViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedEngineSpawnExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw engine subprocess spawn `" <> needle <> "`; route inference execution through an ExecutableModel-gated Infernix.Runtime.CappedEngine launch so an engine without a matching grant and live enforcer, or unbounded by its admitted ceiling, is unrepresentable (see documents/architecture/bounded_inference_memory.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEngineSpawnTokens,
        containsToken needle lineValue
      ]

-- | The raw engine-spawn primitives the capped-engine kernel encapsulates.
forbiddenEngineSpawnTokens :: [String]
forbiddenEngineSpawnTokens =
  [ "readCreateProcessWithExitCode",
    "createProcess",
    "withCreateProcess",
    "waitForProcess"
  ]

-- | The capped-engine kernel: the single legitimate engine-spawn surface.
cappedEngineKernelFile :: FilePath
cappedEngineKernelFile = "src/Infernix/Runtime/CappedEngine/Internal.hs"

fixedObserverKernelFile :: FilePath
fixedObserverKernelFile =
  "src/Infernix/Runtime/CappedEngine/FixedObserver.hs"

-- | The engine-spawn gate's exemption set is /exactly/ the bounded-command
-- gate's, and Sprint 6.44's follow-on states that as a decision rather than
-- leaving it looking like an oversight.
--
-- Sprint 6.44 recorded an intent to make this set "strictly smaller" than
-- 'unboundedExecExemptedFiles'. That is not achievable with this rule's
-- detection strategy, and the honest record matters more than the aspiration.
-- Both gates match the same raw @System.Process@ tokens on the same source
-- lines; nothing in a token tells the two rules apart. So for any file that
-- legitimately retains a /non-engine/ raw spawn — an operator passthrough, a
-- long-lived host daemon, a pre-manifest host probe — removing it from the
-- engine set would make the engine rule fire on a line that is not an engine
-- spawn at all. The only way to pass would be to delete a legitimate spawn or
-- to weaken a rule, and the doctrine forbids both. The two sets therefore
-- coincide by construction, and this definition says so directly instead of
-- implying a narrowing through a redundant cons: 'cappedEngineKernelFile' is
-- already a member of 'unboundedExecExemptedFiles', so consing it produced a
-- duplicate, not a wider set.
--
-- Separating the gates needs a strictly stronger detector, not a smaller list.
-- Two designs would work: a per-site annotation that marks a spawn as
-- engine-launching (so the engine rule keys on intent rather than on the
-- primitive), or an AST pass that resolves what each spawn actually executes
-- (the @check-code@ pass already demonstrates that shape for the realness
-- contract). Either would let the engine gate cover files the exec gate must
-- still exempt. Until one exists, the coupling is load-bearing in one useful
-- direction: a migration that removes a raw spawn from the exec list removes it
-- from both, and a brand-new raw engine spawn — which must carry a
-- 'MemoryGrant' — still has nowhere to hide but the capped-engine kernel.
unboundedEngineSpawnExemptedFiles :: [FilePath]
unboundedEngineSpawnExemptedFiles = unboundedExecExemptedFiles

-- | Sprint 6.44 follow-on (bounded descriptor space) — a spawn kernel that sets
-- @close_fds@ must observe the descriptor bound before it spawns.
--
-- @close_fds@ is unsupported by @posix_spawn@, so @process@ forks and, in the
-- child, closes every descriptor from 3 up to @sysconf(_SC_OPEN_MAX)@ — the soft
-- @RLIMIT_NOFILE@ — before @exec@. That walk is linear in a limit the process
-- inherits rather than chooses, and containerd hands a pod @1073741816@, which
-- was measured at 313 s per spawn. The observer's 50 ms sampling cadence and 5 s
-- deadline turn that into an enforcement failure with two empty captured
-- streams, which reads as a hang rather than as a resource bound.
--
-- The correction bounds the resource instead of weakening the isolation:
-- 'Infernix.DescriptorSpace.establishBoundedDescriptorSpace' lowers the soft
-- limit before the process opens its first descriptor, so the child's walk still
-- covers the entire descriptor space and @close_fds@ keeps its exact meaning.
-- This rule is the structural half — it keeps a /new/ @close_fds@ spawn surface
-- from appearing without the fail-closed observation, so an unbounded process
-- image produces a named error rather than a stall. It is file-scoped like its
-- sibling rules, so it does not catch a second unguarded spawn added to a file
-- that already observes the bound. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
unboundedDescriptorSpawnViolations :: FilePath -> [(Int, String)] -> [String]
unboundedDescriptorSpawnViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedDescriptorSpawnExemptedFiles = []
  | observesDescriptorBound = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": `close_fds` spawn without a preceding Infernix.DescriptorSpace.requireBoundedDescriptorSpace observation; the forked child closes every descriptor up to the soft RLIMIT_NOFILE before exec, which is 313 s per spawn at a containerd pod's 1073741816, so an unbounded process image must fail closed by name instead of stalling (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, _) <- closeFdsSites
      ]
  where
    codeLines =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue)
      ]
    closeFdsSites =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- codeLines,
        containsToken "close_fds" lineValue
      ]
    observesDescriptorBound =
      any
        (containsToken "requireBoundedDescriptorSpace" . snd)
        codeLines

-- | Phase 4 Sprint 4.41 — an engine spawn must reach the ceiling installation
-- region.
--
-- The sibling of 'unboundedDescriptorSpawnViolations', and it exists for the
-- same reason that one does: the bound is established at one site and required
-- at another, so a new engine-spawn surface added later would compile perfectly
-- while observing neither. A ceiling that is installed everywhere except on the
-- one path someone added last week is not a ceiling, and the failing case is
-- silent until a cohort run — which is exactly the cost this repository has
-- already paid twice. Canonical doctrine:
-- documents/architecture/bounded_inference_memory.md.
unboundedCeilingInstallViolations :: FilePath -> [(Int, String)] -> [String]
unboundedCeilingInstallViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedCeilingInstallExemptedFiles = []
  | installsCeiling = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": engine spawn without a preceding Infernix.Runtime.CappedEngine.Ceiling installation region; a ceiling installed before the engine's first allocation is what makes the launch bounded, and a spawn surface that skips the region is an unbounded launch that compiles (see documents/architecture/bounded_inference_memory.md)"
      | (lineNumber, _) <- engineSpawnSites
      ]
  where
    codeLines =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue)
      ]
    engineSpawnSites =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- codeLines,
        containsToken "withCappedEngine" lineValue
      ]
    installsCeiling =
      any
        (containsToken "withEngineCeilingInstalled" . snd)
        codeLines

-- | The ceiling-install rule exempts the module that owns the region (it names
-- both tokens by definition) and this lint module (it names both as literals).
unboundedCeilingInstallExemptedFiles :: [FilePath]
unboundedCeilingInstallExemptedFiles =
  [ "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | The descriptor-bound rule exempts only the module that owns the bound (it
-- names the primitive it exports) and this lint module (it names both tokens as
-- literals).
unboundedDescriptorSpawnExemptedFiles :: [FilePath]
unboundedDescriptorSpawnExemptedFiles =
  [ "src/Infernix/DescriptorSpace.hs",
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.46 (bounded host memory) — a surface that starts the
-- compiler toolchain must observe the declared per-process ceiling and retain
-- its owned group through normal completion or exceptional cleanup.
--
-- The hazard this rule guards is not hypothetical: on 2026-08-03 a host-side
-- @cabal build@ from this checkout reached 109.46 GiB resident on a 124.94 GiB
-- host, wedged the machine for five and a half hours, and was never selected by
-- the kernel because it ran at @oom_score_adj@ 0 while every cluster pod sat at
-- 996-1000. It did not exceed its budget; it had no account it could exceed.
--
-- Structurally this is a copy of 'unboundedDescriptorSpawnViolations': it is
-- file-scoped, it fires on the /naming/ of the toolchain rather than on a
-- specific spawn expression, and it clears as soon as the file observes the
-- boundary. The opaque 'Infernix.BuildMemory.ToolchainSpawnAuthority', closed
-- 'Infernix.BuildMemory.ToolchainInvocation' vocabulary, and its private
-- single-flight token govern the existing CLI path; this rule keeps a /new/
-- raw surface from appearing beside them. Canonical doctrine:
-- documents/architecture/bounded_host_memory.md.
unboundedToolchainSpawnViolations :: FilePath -> [(Int, String)] -> [String]
unboundedToolchainSpawnViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedToolchainSpawnExemptedFiles = []
  | not spawnsAProcess = []
  | observesToolchainLifecycle = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": toolchain spawn surface names `HostCabal` without the complete bounded child lifecycle; route it through Infernix.BuildMemory.withToolchainSpawnAuthority plus withBoundedToolchainChild, refuse unreviewed invocation project state, require the descriptor bound, close inherited descriptors, own a fresh process group through a masked nonblocking leader reap, and kill/reap it on failure (see documents/architecture/bounded_host_memory.md)"
      | (lineNumber, _) <- toolchainSites
      ]
  where
    codeLines =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue)
      ]
    toolchainSites =
      [ (lineNumber, lineValue)
      | (lineNumber, lineValue) <- codeLines,
        containsToken "HostCabal" lineValue
      ]
    spawnsAProcess =
      any
        ( \(_, lineValue) ->
            containsToken "createProcess" lineValue
              || containsToken "readCreateProcessWithExitCode" lineValue
        )
        codeLines
    observesToolchainLifecycle =
      all
        (\requiredToken -> any (containsToken requiredToken . snd) codeLines)
        [ "withBoundedToolchainChild",
          "requireToolchainInvocationProjectState",
          "requireBoundedDescriptorSpace",
          "close_fds",
          "create_group",
          "cleanupToolchainProcessGroupParts",
          "awaitProcessExitReadiness"
        ]

-- | The toolchain rule's declared exemptions.
--
-- Each is a decision rather than an unclosed migration.
unboundedToolchainSpawnExemptedFiles :: [FilePath]
unboundedToolchainSpawnExemptedFiles =
  [ -- Owns the boundary and names both tokens as literals.
    "src/Infernix/BuildMemory.hs",
    -- Names the forbidden and required tokens as literals.
    "src/Infernix/Lint/HaskellStyle.hs",
    -- The pre-manifest host-tool probes. They run before the host manifest a
    -- derived ceiling is measured against exists, and they never start a build:
    -- the closed catalog is fixed-argv version probes under a required
    -- deadline. Same shape as the raw-spawn gate's pre-manifest exemption.
    "src/Infernix/HostTools.hs",
    -- Composes PATH from the manifest's tool directories; the `HostCabal`
    -- mention is a directory, not an invocation.
    "src/Infernix/Cluster/Subprocess.hs"
  ]

-- | Sprint 4.29 (managed-state-transition doctrine) — reject raw streaming HTTP
-- reads of an upstream body outside the bounded model-download wrapper. The
-- model-weight download from an untrusted third-party origin must go through
-- 'Infernix.Runtime.Pulsar.downloadUpstreamModelToFile', which sends a
-- User-Agent, bounds the transfer, and classifies the status into a total
-- @DownloadOutcome@ (so a rate-limit is retried with a bounded backoff, not
-- hammered forever). @withResponse@ — the streaming-body reader that pattern
-- powers — is therefore forbidden elsewhere in production code; trusted
-- in-cluster MinIO/registry calls use @httpLbs@ and are unaffected. Canonical
-- doctrine: documents/architecture/managed_state_transitions.md.
unboundedHttpViolations :: FilePath -> [(Int, String)] -> [String]
unboundedHttpViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` unboundedHttpExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw streaming HTTP read `withResponse`; route an upstream download through Infernix.Runtime.Pulsar.downloadUpstreamModelToFile (User-Agent + bounded transfer + total DownloadOutcome) so a rate-limited fetch is retried with backoff, not hammered forever (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        containsToken "withResponse" lineValue
      ]

-- | Sprint 4.34 (machine-local admission) — keep memory admission on the
-- machine that will execute. 'Infernix.ExecutionPlan.predictedAdmissionRejection'
-- recomputes a machine's admission verdict from a declared budget, which is
-- exactly the coordinator-side veto the admission split exists to remove. It is
-- a validation-harness prediction only; production code reaches admission
-- solely through the engine's refined plan. Canonical doctrine:
-- documents/architecture/bounded_inference_memory.md.
predictedAdmissionViolations :: FilePath -> [(Int, String)] -> [String]
predictedAdmissionViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` predictedAdmissionExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden production use of `predictedAdmissionRejection`; memory admission belongs to the machine that will execute, so read the engine's refined plan (lookupRuntimeUnavailableModel) instead of recomputing a verdict from a declared budget (see documents/architecture/bounded_inference_memory.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        containsToken "predictedAdmissionRejection" lineValue
      ]

predictedAdmissionExemptedFiles :: [FilePath]
predictedAdmissionExemptedFiles =
  [ -- Defines the prediction and the admission it delegates to.
    "src/Infernix/ExecutionPlan.hs",
    -- Names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

unboundedHttpExemptedFiles :: [FilePath]
unboundedHttpExemptedFiles =
  [ -- Owns the single bounded upstream-download wrapper
    -- ('downloadUpstreamModelToFile'), the sole legitimate 'withResponse'.
    "src/Infernix/Runtime/Pulsar.hs",
    -- Names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Sprint 6.41 (managed-state-transition doctrine) — reject raw 'threadDelay'
-- readiness/poll loops outside the readiness kernel. A hand-rolled
-- @threadDelay@-in-a-recursion is exactly the bare-recursion readiness wait the
-- kernel replaces: 'Infernix.Evidence.Readiness.awaitReadiness' owns the one
-- legitimate inter-poll delay and is the sole minter of a positive 'Readiness',
-- so an unbounded or fabricated-ready wait is unrepresentable. The exemption list
-- is deliberately shrinking: the kernel (owns the delay) and this lint module
-- (names the token as a literal) are permanent; the remaining files retain
-- genuine backoff / heartbeat / runtime-loop-park delays whose migration is
-- deferred. 'CLI.hs' is intentionally kept OUT of the list — Sprint 6.41 migrated
-- its two readiness waits onto the kernel, so the gate now keeps it clean.
-- Canonical doctrine: documents/architecture/managed_state_transitions.md.
threadDelayViolations :: FilePath -> [(Int, String)] -> [String]
threadDelayViolations sourceFile numberedLines
  | not ("src/Infernix/" `isPrefixOfString` sourceFile) = []
  | sourceFile `elem` threadDelayExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden raw `threadDelay` outside the readiness kernel; route a poll/readiness wait through Infernix.Evidence.Readiness.awaitReadiness (a required Deadline + typed Readiness evidence) so an unbounded or fabricated-ready wait is unrepresentable (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        containsToken "threadDelay" lineValue
      ]

threadDelayExemptedFiles :: [FilePath]
threadDelayExemptedFiles =
  [ -- The readiness kernel owns the one legitimate inter-poll delay.
    "src/Infernix/Evidence/Readiness.hs",
    -- Names the forbidden token as a literal; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs",
    -- The capped-engine kernel's resident-memory watchdog samples the child's
    -- footprint on a fixed inter-poll delay (Phase 4 Sprint 4.30).
    "src/Infernix/Runtime/CappedEngine/Internal.hs",
    -- Cluster lifecycle: retains genuine backoff sites (claim chmod retry, probe
    -- backoff, teardown-absence backoff) after the Sprint 6.41 wait migration.
    "src/Infernix/Cluster.hs",
    -- Runtime transport / service loop: producer + WebSocket connect retry backoff,
    -- dispatcher topic poll, and the idle runtime-loop park / heartbeat.
    "src/Infernix/Runtime/Pulsar.hs",
    -- Engine worker: inference retry backoff.
    "src/Infernix/Runtime/Worker.hs",
    -- Daemon: startup settle + idle park / heartbeat.
    "src/Infernix/Runtime/Daemon.hs",
    -- Demo API: bounded object-readiness backoff.
    "src/Infernix/Demo/Api.hs"
  ]

-- | Every file allowed to hold a raw @System.Process@ spawn, and why.
--
-- Sprint 6.44's follow-on closed this list out. The two rows it named as
-- "mechanically migratable" are gone — 'Lint/Files.hs' and 'Workflow.hs' now
-- run their commands through the closed catalog — and the three that remain
-- are recorded here as settled scope decisions, not as backlog. Each surviving
-- row is a named kernel or a stated boundary, and every raw spawn behind those
-- rows now carries a required total deadline, so "exempt from the closed
-- catalog" no longer means "unbounded".
unboundedExecExemptedFiles :: [FilePath]
unboundedExecExemptedFiles =
  [ -- Owns the bounded-command kernel (the one legitimate raw spawn surface).
    "src/Infernix/Cluster/Subprocess.hs",
    -- Owns the capped-engine kernel (the one legitimate raw engine-spawn surface,
    -- Phase 4 Sprint 4.30); every engine spawn there runs under a MemoryGrant.
    "src/Infernix/Runtime/CappedEngine/Internal.hs",
    -- Owns the fixed Apple footprint observers. The module does not accept a
    -- caller-supplied executable, arguments, environment, or working directory.
    fixedObserverKernelFile,
    -- Names the forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs",
    -- Two surfaces that are deliberately outside the closed catalog's scope,
    -- named individually because the scope decision differs for each.
    --
    -- 'withRuntimeServiceDaemon' starts the long-lived `infernix service` host
    -- daemon. A required /total/ deadline is the wrong shape for a process
    -- whose whole purpose is to outlive the command that started it; the
    -- bounded-command kernel's contract is "run to completion within a
    -- timeout", which this can never satisfy. Its lifetime is instead bounded
    -- structurally: it is bracketed with terminate + wait, so it cannot outlive
    -- the region that started it.
    --
    -- 'runCommandWithCwdAndEnvRemovingWithPaths' is the operator passthrough
    -- behind `infernix test ...` and `infernix kubectl ...`. Its executable and
    -- argv come from the operator's own invocation, it must stream to the
    -- operator's terminal rather than capture, and it must exit with the
    -- child's code. Bounding an operator's own `cabal test` run with a deadline
    -- the operator did not choose would be a defect, not a safeguard, and the
    -- closed catalog cannot model a command whose tokens are the operator's.
    --
    -- The one CLI capture that is /not/ a passthrough — the demo-UI `curl`
    -- fetch — does carry a required deadline.
    "src/Infernix/CLI.hs",
    -- Apple host prerequisite reconciliation: `brew install <closed formula>`,
    -- `docker context show`, and `docker info --format {{json .}}`. All three
    -- have fully fixed argv and fixed literal Homebrew executables, so the
    -- objection is not caller-supplied tokens — it is ordering. They run on an
    -- Apple host *before* any host manifest or Docker context exists, because
    -- reconciling exactly those things is their job. A closed `ClusterCommand`
    -- compiles against 'clusterSubprocessEnv', which fails closed without a
    -- manifest, so routing them through the catalog would make the bootstrap
    -- depend on the artifact it is bootstrapping. That is a boundary, not a
    -- backlog item. All three carry required deadlines instead.
    "src/Infernix/HostPrereqs.hs",
    -- A named kernel: owns the pre-manifest fixed host probes. The three
    -- generic runners that used to live here had no callers left anywhere in
    -- the repository and were deleted rather than migrated. The two remaining
    -- invocations — `sysctl -n hw.memsize` and `colima list --json` — carry
    -- fixed argv and a required deadline, and run during `infernix init`,
    -- before the manifest a closed command would need exists.
    "src/Infernix/HostTools.hs"
  ]

-- | Phase 0 Sprint 0.13 (managed-state-transition doctrine) — the escape-token
-- gate. Inside the evidence-kernel modules the type system is the enforcement:
-- opaque newtypes with hidden constructors, rank-2 region leases, and total
-- 'Infernix.Cluster.Subprocess.CommandOutcome' values. The only two escapes GHC
-- cannot close from inside those modules are @unsafeCoerce@ (forge an opaque
-- evidence value past its hidden constructor) and @unsafePerformIO@ (let a
-- probe fabricate evidence purely, the same masked-failure the realness
-- contract rejects). Both are forbidden in the evidence modules; the type
-- system closes everything else, so the gate is deliberately scoped to that
-- small audit surface. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
escapeTokenViolations :: FilePath -> [(Int, String)] -> [String]
escapeTokenViolations sourceFile numberedLines
  | sourceFile `notElem` escapeTokenScopedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden escape token `" <> needle <> "` in an evidence module; the managed-state-transition doctrine closes evidence with the type system and these two escapes would forge it (see documents/architecture/managed_state_transitions.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEscapeTokens,
        containsToken needle lineValue
      ]

-- | The evidence-kernel modules whose guarantees rest on the type system. The
-- list grows as later sprints add evidence-minting modules (the lease-gated
-- scrub, the sentinel commit, the token leases), so their escape surface is
-- gated the moment they land.
escapeTokenScopedFiles :: [FilePath]
escapeTokenScopedFiles =
  [ "src/Infernix/Evidence/Readiness.hs",
    "src/Infernix/Evidence/Lease.hs",
    "src/Infernix/Cluster/Subprocess.hs",
    -- Sprint 3.15: mints the opaque 'BlobServable' evidence (hidden ctor);
    -- forbid the two escapes that could forge it.
    "src/Infernix/Cluster/PublishImages.hs"
  ]

forbiddenEscapeTokens :: [String]
forbiddenEscapeTokens =
  [ "unsafeCoerce",
    "unsafePerformIO"
  ]

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject new
-- occurrences of @lookupEnv@ / @getEnv@ / @getEnvironment@ /
-- @setEnv@ / @unsetEnv@ outside the explicit exemption list. The
-- exemption list names the modules whose env retirements are
-- deferred to specific later sprints (Phase 7 Sprint 7.17 for the
-- credential-bearing reads, the Apple validation pass for the
-- Apple-only code paths). As those sprints close, their rows leave
-- this list and the gate tightens automatically.
envFunctionViolations :: FilePath -> [(Int, String)] -> [String]
envFunctionViolations sourceFile numberedLines
  | sourceFile `elem` envFunctionExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden env-IO call `" <> needle <> "`; route through HostConfig or a typed Dhall manifest"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEnvFunctions,
        containsToken needle lineValue
      ]

forbiddenEnvFunctions :: [String]
forbiddenEnvFunctions =
  [ "lookupEnv",
    "getEnv",
    "getEnvironment",
    "setEnv",
    "unsetEnv"
  ]

-- | Realness lint mechanism (Phase 0 Sprint 0.12 governance) — realness by
-- construction. The generated native-engine runner must emit only real engine
-- output (or exit non-zero); it may never fabricate a result. This lint module
-- lists the fabrication tokens as literals and is itself out of scope, so it
-- does not trip its own check. The per-runner scope ('realnessScopedFiles') is
-- extended by each accelerator phase as it de-stubs, and now covers both
-- generated-runner modules: Phase 4 Sprint 4.21 added Engines/LinuxNative.hs;
-- Phase 1 Sprint 1.20 keeps the Apple runner in its hidden implementation
-- module behind the public Engines/AppleSilicon.hs facade.
-- Canonical doctrine: documents/architecture/realness_contract.md.
realnessFabricationViolations :: FilePath -> [(Int, String)] -> [String]
realnessFabricationViolations sourceFile numberedLines
  | sourceFile `notElem` realnessScopedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden fabrication token `" <> needle <> "`; native runners must emit real engine output or exit non-zero (see documents/architecture/realness_contract.md)"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenNativeFabricationTokens,
        needle `isInfixOf` lineValue
      ]

realnessScopedFiles :: [FilePath]
realnessScopedFiles =
  [ "src/Infernix/Engines/LinuxNative.hs",
    "src/Infernix/Engines/AppleSilicon.hs",
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
  ]

forbiddenNativeFabricationTokens :: [String]
forbiddenNativeFabricationTokens =
  -- NB: `np.zeros` is intentionally NOT forbidden — it is a fundamental NumPy
  -- primitive that real engines use legitimately for scratch buffers (e.g. the
  -- basic-pitch note-creation peak matrix). The fabrication signal is the
  -- constant artifact (`b64decode` of a literal) and the masking helpers; the
  -- fake-input-to-model pattern is prohibited by the realness doctrine + review.
  [ "emit_fallback_result",
    "infernix_emit_validation_result",
    "native-validation",
    "b64decode",
    "native fallback"
  ]

envFunctionExemptedFiles :: [FilePath]
envFunctionExemptedFiles =
  [ -- This lint module defines the forbidden tokens as string
    -- literals; it must exempt itself or the check trips on its own
    -- token list.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject
-- bare-name @proc "<command>"@ invocations whose name matches a
-- known external tool. The supported flow routes every invocation
-- through a closed `ClusterCommand` (or, before the host manifest exists,
-- `Infernix.HostTools`) so the absolute path
-- comes from the typed `HostConfig.toolPaths.*` record.
bareNameProcViolations :: FilePath -> [(Int, String)] -> [String]
bareNameProcViolations sourceFile numberedLines
  | sourceFile `elem` bareNameProcExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden bare-name `proc " <> show toolName <> "`; resolve the executable through a closed ClusterCommand, or through Infernix.HostTools for a pre-manifest host probe"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        toolName <- forbiddenBareProcCommands,
        let needle = "proc \"" <> toolName <> "\"",
        needle `isInfixOf` lineValue
      ]

-- | Derived from the 'HostTools.HostTool' enum (via
-- 'HostTools.hostToolCommandNames') so the forbidden bare-name set cannot
-- drift from the registered host-tool set. Retired standalone tools remain
-- explicit forbidden names: the protobuf pair is confined to the Dockerfile's
-- fixed Linux generation gate after Sprint 1.24, while Sprint 1.25 links
-- Ormolu and HLint only through the dedicated style component's APIs.
forbiddenBareProcCommands :: [String]
forbiddenBareProcCommands =
  ["protoc", "proto-lens-protoc", "ormolu", "hlint"]
    <> HostTools.hostToolCommandNames

bareNameProcExemptedFiles :: [FilePath]
bareNameProcExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.28 follow-on: reject ambient executable discovery
-- for registered host tools. Supported invocation paths either read
-- absolute paths from HostConfig.toolPaths or use fixed absolute
-- fallback candidates from Infernix.HostTools.
ambientToolLookupViolations :: FilePath -> [(Int, String)] -> [String]
ambientToolLookupViolations sourceFile numberedLines
  | sourceFile `elem` ambientToolLookupExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden ambient host-tool lookup `" <> needle <> "`; route through HostTools and HostConfig.toolPaths"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenAmbientToolLookups,
        containsToken needle lineValue
      ]

forbiddenAmbientToolLookups :: [String]
forbiddenAmbientToolLookups =
  [ "findExecutable",
    "findExecutables"
  ]

ambientToolLookupExemptedFiles :: [FilePath]
ambientToolLookupExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 7 Sprint 7.8: keep the engine runtime surface from
-- importing frontend, coordinator, auth, object-presign, or WebSocket
-- modules. `Runtime.Daemon` owns role orchestration and may wire both
-- coordinator and engine loops, so this gate is scoped to the concrete
-- engine runtime modules.
engineRuntimeBoundaryViolations :: FilePath -> [(Int, String)] -> [String]
engineRuntimeBoundaryViolations sourceFile numberedLines
  | sourceFile `notElem` engineRuntimeBoundaryFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": engine runtime module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenEngineRuntimeImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

engineRuntimeBoundaryFiles :: [FilePath]
engineRuntimeBoundaryFiles =
  [ "src/Infernix/Runtime.hs",
    "src/Infernix/Runtime/Cache.hs",
    "src/Infernix/Runtime/KVCache.hs",
    "src/Infernix/Runtime/Worker.hs"
  ]

forbiddenEngineRuntimeImports :: [String]
forbiddenEngineRuntimeImports =
  [ "Infernix.Demo.",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Infernix.Dispatch.SingleFlight",
    "Infernix.Bridge.Result",
    "Infernix.Bootstrap.Models",
    "Network.WebSockets"
  ]

-- | Phase 7 shared-library modules must remain product/runtime agnostic.
-- Conversation primitives are allowed to depend on generated wire contracts,
-- but not on demo application modules. The pure dispatcher/result/bootstrap
-- helpers must also stay out of runtime orchestration, auth, object-presign,
-- and WebSocket concerns.
sharedPhase7BoundaryViolations :: FilePath -> [(Int, String)] -> [String]
sharedPhase7BoundaryViolations sourceFile numberedLines =
  case lookup sourceFile sharedPhase7BoundaryFiles of
    Nothing -> []
    Just forbiddenImports ->
      [ sourceFile <> ":" <> show lineNumber <> ": shared Phase 7 module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

sharedPhase7BoundaryFiles :: [(FilePath, [String])]
sharedPhase7BoundaryFiles =
  map conversationBoundaryFile conversationPrimitiveFiles
    <> [ ( "src/Infernix/Dispatch/SingleFlight.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Dispatch/ContextModelMap.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bridge/Result.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bootstrap/Models.hs",
           productAgnosticHelperForbiddenImports
         )
       ]

conversationBoundaryFile :: FilePath -> (FilePath, [String])
conversationBoundaryFile sourceFile =
  (sourceFile, conversationForbiddenImports)

conversationPrimitiveFiles :: [FilePath]
conversationPrimitiveFiles =
  [ "src/Infernix/Conversation/Event.hs",
    "src/Infernix/Conversation/Hash.hs",
    "src/Infernix/Conversation/Idempotency.hs",
    "src/Infernix/Conversation/Reducer.hs",
    "src/Infernix/Conversation/Topic.hs"
  ]

conversationForbiddenImports :: [String]
conversationForbiddenImports =
  [ "Infernix.Demo",
    "Infernix.Runtime",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Network.WebSockets"
  ]

productAgnosticHelperForbiddenImports :: [String]
productAgnosticHelperForbiddenImports =
  conversationForbiddenImports
    <> [ "Infernix.Dispatch.SingleFlight",
         "Infernix.Bridge.Result",
         "Infernix.Bootstrap.Models"
       ]

isPrefixOfString :: String -> String -> Bool
isPrefixOfString expected value =
  case stripPrefix expected value of
    Just _ -> True
    Nothing -> False

hangingCaseViolations :: FilePath -> [(Int, String)] -> [String]
hangingCaseViolations sourceFile numberedLines =
  [ sourceFile <> ":" <> show lineNumber <> ": avoid hanging `case`; move it into a named helper or make it the outer expression"
  | (lineNumber, lineValue) <- numberedLines,
    not (isCommentLine lineValue),
    lineHasHangingCase lineValue
  ]

lineHasHangingCase :: String -> Bool
lineHasHangingCase lineValue =
  any
    (`isInfixOf` paddedLine)
    hangingCaseNeedles
  where
    paddedLine = " " <> lineValue <> " "

hangingCaseNeedles :: [String]
hangingCaseNeedles =
  [ "(" <> " case",
    "->" <> " case",
    "then" <> " case",
    "else" <> " case",
    "<-" <> " case",
    " in" <> " case "
  ]

aliasCommentViolations :: FilePath -> [(Int, String)] -> [String]
aliasCommentViolations sourceFile numberedLines =
  concatMap signatureViolations (signatureBlocks numberedLines)
  where
    signatureViolations (lineNumber, signatureLines) =
      [ sourceFile <> ":" <> show lineNumber <> ": aliased type `" <> aliasName <> "` needs comment `" <> requiredComment <> "`"
      | (aliasName, requiredComment) <- aliasedTypeComments,
        containsToken aliasName (unlines signatureLines),
        not (hasRequiredAliasComment requiredComment lineNumber numberedLines)
      ]

aliasedTypeComments :: [(String, String)]
aliasedTypeComments =
  [ ("Application", "-- type Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived"),
    ("HostPreference", "-- type HostPreference = String"),
    ("InferenceResponse", "-- type InferenceResponse = Either (Status, ErrorResponse) InferenceResult"),
    ("PublishedImage", "-- type PublishedImage = (String, String)")
  ]

signatureBlocks :: [(Int, String)] -> [(Int, [String])]
signatureBlocks [] = []
signatureBlocks ((lineNumber, lineValue) : remainingLines)
  | isSignatureStart lineValue =
      let (continuation, rest) = span isSignatureContinuation remainingLines
       in (lineNumber, lineValue : map snd continuation) : signatureBlocks rest
  | otherwise = signatureBlocks remainingLines

isSignatureStart :: String -> Bool
isSignatureStart lineValue =
  not (startsWithSpace lineValue)
    && not (isCommentLine lineValue)
    && "::" `isInfixOf` lineValue

isSignatureContinuation :: (Int, String) -> Bool
isSignatureContinuation (_, lineValue) =
  null (trimWhitespace lineValue) || startsWithSpace lineValue || isCommentLine lineValue

startsWithSpace :: String -> Bool
startsWithSpace (' ' : _) = True
startsWithSpace ('\t' : _) = True
startsWithSpace _ = False

hasRequiredAliasComment :: String -> Int -> [(Int, String)] -> Bool
hasRequiredAliasComment requiredComment lineNumber numberedLines =
  requiredComment `elem` precedingNonBlankLines
  where
    precedingNonBlankLines =
      take
        6
        [ trimWhitespace candidateLine
        | (candidateLineNumber, candidateLine) <- reverse numberedLines,
          candidateLineNumber < lineNumber,
          not (null (trimWhitespace candidateLine))
        ]

containsToken :: String -> String -> Bool
containsToken token value =
  token `elem` tokenize value

tokenize :: String -> [String]
tokenize =
  words . map tokenCharacter
  where
    tokenCharacter character
      | isAlphaNum character || character == '_' || character == '\'' = character
      | otherwise = ' '

isCommentLine :: String -> Bool
isCommentLine lineValue =
  case trimWhitespace lineValue of
    '-' : '-' : _ -> True
    _ -> False

trimWhitespace :: String -> String
trimWhitespace =
  reverse . dropWhile (`elem` [' ', '\t']) . reverse . dropWhile (`elem` [' ', '\t'])

makeRelative :: FilePath -> FilePath -> FilePath
makeRelative root fullPath =
  fromMaybe fullPath (stripPrefix (root <> "/") fullPath)

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing
