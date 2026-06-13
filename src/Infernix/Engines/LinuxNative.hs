{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.LinuxNative
  ( LinuxNativeEngineArtifact (..),
    linuxNativeEngineArtifactAdapterIds,
    linuxNativeEngineBuildPlan,
    linuxNativeEngineImageRoot,
    linuxNativeEngineInstallRoot,
    linuxNativeRunnerScript,
    manifestForLinuxNativeEngineArtifact,
    materializeLinuxNativeEngineArtifact,
    materializeLinuxNativeEngines,
    materializeLinuxNativeEnginesAt,
  )
where

import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Engines.AppleSilicon
  ( EngineArtifactManifest (..),
    engineArtifactManifestPath,
    engineArtifactTempRoot,
    installEngineArtifactRoot,
    renderEngineArtifactManifest,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    getPermissions,
    removePathForcibly,
    setOwnerExecutable,
    setPermissions,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Info (arch, os)
import System.Process (proc, readCreateProcessWithExitCode)

data LinuxNativeEngineArtifact = LinuxNativeEngineArtifact
  { linuxNativeEngineAdapterId :: Text,
    linuxNativeEngineName :: Text,
    linuxNativeEngineArtifactKind :: Text,
    linuxNativeEngineSourceRef :: Text,
    linuxNativeEngineVersion :: Text,
    linuxNativeRuntimeVersion :: Text,
    linuxNativeEntrypoint :: Text,
    linuxNativeSmokeCommand :: Text
  }
  deriving (Eq, Show)

linuxNativeEngineBuildPlan :: [LinuxNativeEngineArtifact]
linuxNativeEngineBuildPlan =
  [ LinuxNativeEngineArtifact "llama-cpp-cli" "llama.cpp Linux runner" "native-binary" "github:ggml-org/llama.cpp" "pinned-by-manifest" "linux-native" "bin/llama-cli" "bin/llama-cli --smoke",
    LinuxNativeEngineArtifact "whisper-cpp-cli" "whisper.cpp Linux runner" "native-binary" "github:ggml-org/whisper.cpp" "pinned-by-manifest" "linux-native" "bin/whisper-cli" "bin/whisper-cli --smoke",
    LinuxNativeEngineArtifact "onnx-runtime-native" "ONNX Runtime Linux runner" "native-binary" "github:microsoft/onnxruntime" "pinned-by-manifest" "linux-native" "bin/onnx-runner" "bin/onnx-runner --smoke",
    LinuxNativeEngineArtifact "ctranslate2-native" "CTranslate2 Linux runner" "native-binary" "github:OpenNMT/CTranslate2" "pinned-by-manifest" "linux-native" "bin/ct2-runner" "bin/ct2-runner --smoke",
    LinuxNativeEngineArtifact "jvm-native" "Audiveris JVM Linux runner" "jvm-tool" "github:Audiveris/audiveris" "pinned-by-manifest" "linux-native-jvm" "bin/audiveris" "bin/audiveris --smoke"
  ]

linuxNativeEngineArtifactAdapterIds :: [Text]
linuxNativeEngineArtifactAdapterIds = map linuxNativeEngineAdapterId linuxNativeEngineBuildPlan

linuxNativeEngineImageRoot :: FilePath
linuxNativeEngineImageRoot = "/opt/infernix/engines"

linuxNativeEngineInstallRoot :: FilePath -> Text -> FilePath
linuxNativeEngineInstallRoot baseRoot adapterId =
  baseRoot </> Text.unpack adapterId

materializeLinuxNativeEngines :: IO ()
materializeLinuxNativeEngines = do
  unless (os == "linux") $
    ioError (userError linuxNativeLaneNotLinuxMessage)
  materializeLinuxNativeEnginesAt linuxNativeEngineImageRoot

materializeLinuxNativeEnginesAt :: FilePath -> IO ()
materializeLinuxNativeEnginesAt baseRoot =
  mapM_ (materializeLinuxNativeEngineArtifact baseRoot) linuxNativeEngineBuildPlan

materializeLinuxNativeEngineArtifact :: FilePath -> LinuxNativeEngineArtifact -> IO FilePath
materializeLinuxNativeEngineArtifact baseRoot artifact = do
  let installRoot = linuxNativeEngineInstallRoot baseRoot (linuxNativeEngineAdapterId artifact)
      tempRoot = engineArtifactTempRoot installRoot
      manifest = manifestForLinuxNativeEngineArtifact installRoot artifact
  removePathForcibly tempRoot
  createDirectoryIfMissing True tempRoot
  LazyByteString.writeFile (engineArtifactManifestPath tempRoot) (renderEngineArtifactManifest manifest)
  writeLinuxNativeRunner tempRoot artifact
  writeFile
    (tempRoot </> "README.txt")
    ( "Infernix Linux native engine artifact root for "
        <> Text.unpack (linuxNativeEngineAdapterId artifact)
        <> ". The current machine-independent artifact is a smoke wrapper; Wave I replaces it "
        <> "with the real engine payload and records real-output validation.\n"
    )
  validateLinuxNativeArtifact tempRoot artifact
  installEngineArtifactRoot installRoot tempRoot
  pure installRoot

manifestForLinuxNativeEngineArtifact :: FilePath -> LinuxNativeEngineArtifact -> EngineArtifactManifest
manifestForLinuxNativeEngineArtifact installRoot artifact =
  let digest = linuxNativeEngineArtifactDigest artifact
      digestSuffix = Text.drop 1 (Text.dropWhile (/= ':') digest)
   in EngineArtifactManifest
        { manifestAdapterId = linuxNativeEngineAdapterId artifact,
          manifestEngineName = linuxNativeEngineName artifact,
          manifestSubstrate = "linux-native",
          manifestArchitecture = linuxNativeArchitecture,
          manifestArtifactKind = linuxNativeEngineArtifactKind artifact,
          manifestSourceRef = linuxNativeEngineSourceRef artifact,
          manifestEngineVersion = linuxNativeEngineVersion artifact,
          manifestPythonVersion = Nothing,
          manifestRuntimeVersion = linuxNativeRuntimeVersion artifact,
          manifestDigest = digest,
          manifestMinioObjectKey =
            "engine-artifacts/linux/"
              <> linuxNativeArchitecture
              <> "/"
              <> linuxNativeEngineAdapterId artifact
              <> "/"
              <> digestSuffix
              <> ".tar.zst",
          manifestLocalInstallRoot = installRoot,
          manifestEntrypoint = linuxNativeEntrypoint artifact,
          manifestSmokeCommand = linuxNativeSmokeCommand artifact
        }

linuxNativeEngineArtifactDigest :: LinuxNativeEngineArtifact -> Text
linuxNativeEngineArtifactDigest artifact =
  let digestInput =
        Text.intercalate
          "\n"
          [ linuxNativeEngineAdapterId artifact,
            linuxNativeEngineName artifact,
            linuxNativeEngineArtifactKind artifact,
            linuxNativeEngineSourceRef artifact,
            linuxNativeEngineVersion artifact,
            linuxNativeRuntimeVersion artifact,
            linuxNativeEntrypoint artifact,
            linuxNativeSmokeCommand artifact
          ]
      digestBytes = SHA256.hashlazy (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digestBytes)

linuxNativeArchitecture :: Text
linuxNativeArchitecture =
  case arch of
    "x86_64" -> "amd64"
    "aarch64" -> "arm64"
    other -> Text.pack other

writeLinuxNativeRunner :: FilePath -> LinuxNativeEngineArtifact -> IO ()
writeLinuxNativeRunner tempRoot artifact = do
  let runnerPath = tempRoot </> Text.unpack (linuxNativeEntrypoint artifact)
  createDirectoryIfMissing True (takeDirectory runnerPath)
  writeFile runnerPath (linuxNativeRunnerScript artifact)
  permissions <- getPermissions runnerPath
  setPermissions runnerPath (setOwnerExecutable True permissions)

linuxNativeRunnerScript :: LinuxNativeEngineArtifact -> String
linuxNativeRunnerScript artifact =
  unlines
    [ "#!/usr/bin/bash",
      "set -eu",
      "adapter_id=" <> shellLiteral (Text.unpack (linuxNativeEngineAdapterId artifact)),
      "engine_name=" <> shellLiteral (Text.unpack (linuxNativeEngineName artifact)),
      "for arg in \"$@\"; do",
      "  case \"${arg}\" in",
      "    --smoke|--help)",
      "      printf '%s\\n' \"infernix linux native smoke ok: ${adapter_id}\"",
      "      exit 0",
      "      ;;",
      "  esac",
      "done",
      "printf '%s\\n' \"infernix native engine payload is not installed for ${adapter_id}; this image carries the materialized runner root and smoke wrapper only. Bake the real ${engine_name} payload before real inference.\" >&2",
      "exit 86"
    ]

validateLinuxNativeArtifact :: FilePath -> LinuxNativeEngineArtifact -> IO ()
validateLinuxNativeArtifact tempRoot artifact = do
  let manifestPath = engineArtifactManifestPath tempRoot
      runnerPath = tempRoot </> Text.unpack (linuxNativeEntrypoint artifact)
  manifestPresent <- doesFileExist manifestPath
  unless manifestPresent $
    ioError (userError ("engine artifact manifest was not written under " <> tempRoot))
  runnerPresent <- doesFileExist runnerPath
  unless runnerPresent $
    ioError (userError ("native engine runner was not written under " <> runnerPath))
  (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc runnerPath ["--smoke"]) ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("native engine smoke failed for " <> runnerPath <> "\n" <> stderrOutput))

shellLiteral :: String -> String
shellLiteral rawValue = "'" <> concatMap escapeCharacter rawValue <> "'"
  where
    escapeCharacter '\'' = "'\\''"
    escapeCharacter character = [character]

linuxNativeLaneNotLinuxMessage :: String
linuxNativeLaneNotLinuxMessage =
  "infernix internal materialize-linux-native-engines is Linux-only: it bakes image-owned "
    <> "native runner roots under /opt/infernix/engines/<adapterId>/ for the Linux substrate images."
