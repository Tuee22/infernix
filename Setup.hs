import Data.List (intercalate)
import Data.ProtoLens.Setup (generatingProtos)
import Distribution.Simple (defaultMainWithHooks, simpleUserHooks)
import System.Directory (createDirectoryIfMissing, doesFileExist, doesPathExist, getCurrentDirectory)
import qualified System.Environment as Env
import System.FilePath (takeDirectory, (</>))
import System.Posix.User (getRealUserID, getUserEntryForID, homeDirectory)
import System.Process (callProcess)

protoLensAllowNewer :: [String]
protoLensAllowNewer =
  [ "binary:containers",
    "lens-family:base",
    "lens-family:containers",
    "lens-family:lens-family-core",
    "lens-family-core:containers",
    "proto-lens:lens-family",
    "proto-lens-setup:Cabal"
  ]

main :: IO ()
main = do
  cwd <- getCurrentDirectory
  repoRoot <- findRepoRoot cwd
  setupHome <- currentUserHome
  let buildRoot = repoRoot </> ".build"
  cabalPath <- resolveRequiredTool "cabal" (cabalCandidates setupHome)
  let toolRoot = buildRoot </> "proto-tools"
      toolBinDir = toolRoot </> "bin"
      toolBuildDir = toolRoot </> "cabal"
      toolBinary = toolBinDir </> "proto-lens-protoc"
  createDirectoryIfMissing True toolBinDir
  setProtoLensSetupPath toolBinDir setupHome
  toolExists <- doesFileExist toolBinary
  if toolExists
    then pure ()
    else
      callProcess
        cabalPath
        ( [ "--ignore-project",
            "--builddir=" <> toolBuildDir,
            "install",
            "proto-lens-protoc",
            "--installdir",
            toolBinDir,
            "--install-method=copy",
            "--overwrite-policy=always"
          ]
            <> concatMap (\constraintValue -> ["--allow-newer=" <> constraintValue]) protoLensAllowNewer
        )
  ensureToolExists toolBinary
  defaultMainWithHooks (generatingProtos "proto" simpleUserHooks)

setProtoLensSetupPath :: FilePath -> FilePath -> IO ()
setProtoLensSetupPath toolBinDir setupHome =
  -- proto-lens-setup discovers proto-lens-protoc through PATH. Keep that
  -- upstream shim deterministic and setup-local: no inherited PATH is read.
  Env.setEnv "PATH" (intercalate ":" (setupPathEntries toolBinDir setupHome))

setupPathEntries :: FilePath -> FilePath -> [FilePath]
setupPathEntries toolBinDir setupHome =
  [ toolBinDir,
    setupHome </> ".ghcup" </> "bin",
    "/root/.ghcup/bin",
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin"
  ]

ensureToolExists :: FilePath -> IO ()
ensureToolExists expectedPath = do
  toolExists <- doesFileExist expectedPath
  if toolExists
    then pure ()
    else
      error
        ( "proto-lens-protoc bootstrap failed; expected "
            <> expectedPath
            <> " to exist after bootstrap"
        )

currentUserHome :: IO FilePath
currentUserHome = do
  userId <- getRealUserID
  userEntry <- getUserEntryForID userId
  pure (homeDirectory userEntry)

cabalCandidates :: FilePath -> [FilePath]
cabalCandidates setupHome =
  [ setupHome </> ".ghcup" </> "bin" </> "cabal",
    "/root/.ghcup/bin/cabal",
    "/usr/local/bin/cabal",
    "/usr/bin/cabal"
  ]

resolveRequiredTool :: String -> [FilePath] -> IO FilePath
resolveRequiredTool toolName candidates =
  case candidates of
    [] ->
      error ("Unable to resolve required setup tool " <> toolName <> " from fixed candidates")
    candidate : rest -> do
      exists <- doesFileExist candidate
      if exists
        then pure candidate
        else resolveRequiredTool toolName rest

findRepoRoot :: FilePath -> IO FilePath
findRepoRoot start = go start
  where
    go current = do
      hasPlan <- doesPathExist (current </> "DEVELOPMENT_PLAN" </> "README.md")
      hasGit <- doesPathExist (current </> ".git")
      if hasPlan || hasGit
        then pure current
        else
          let parent = takeDirectory current
           in if parent == current
                then pure start
                else go parent
