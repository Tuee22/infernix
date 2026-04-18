import Data.List (isPrefixOf)
import Data.ProtoLens.Setup (defaultMainGeneratingProtos)
import System.Directory (createDirectoryIfMissing, doesFileExist, findExecutable, getCurrentDirectory)
import System.Environment (getEnv, lookupEnv, setEnv)
import System.FilePath ((</>))
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
  repoRoot <- getCurrentDirectory
  let toolRoot = repoRoot </> ".build" </> "proto-tools"
      toolBinDir = toolRoot </> "bin"
      toolBuildDir = toolRoot </> "cabal"
      toolBinary = toolBinDir </> "proto-lens-protoc"
  createDirectoryIfMissing True toolBinDir
  maybeToolOnPath <- findExecutable "proto-lens-protoc"
  toolPath <-
    case maybeToolOnPath of
      Just path -> pure path
      Nothing -> do
        toolExists <- doesFileExist toolBinary
        if toolExists
          then pure toolBinary
          else do
            callProcess
              "cabal"
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
            pure toolBinary
  prependPath toolBinDir
  ensureToolVisible toolPath
  defaultMainGeneratingProtos "proto"

prependPath :: FilePath -> IO ()
prependPath entry = do
  maybePath <- lookupEnv "PATH"
  let updatedPath = case maybePath of
        Nothing -> entry
        Just currentPath
          | entry `isPrefixOf` currentPath -> currentPath
          | otherwise -> entry <> ":" <> currentPath
  setEnv "PATH" updatedPath

ensureToolVisible :: FilePath -> IO ()
ensureToolVisible expectedPath = do
  maybeResolved <- findExecutable "proto-lens-protoc"
  case maybeResolved of
    Just _ -> pure ()
    Nothing -> do
      pathValue <- getEnv "PATH"
      error
        ( "proto-lens-protoc bootstrap failed; expected "
            <> expectedPath
            <> " to be visible in PATH="
            <> pathValue
        )
