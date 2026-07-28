{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.LinuxNative
  ( LinuxNativeEngineArtifact,
    linuxNativeEngineAdapterId,
    linuxNativeEngineArtifactAdapterIds,
    linuxNativeEngineBuildPlan,
    linuxNativeEngineImageRoot,
    linuxNativeEngineInstallRoot,
    manifestForLinuxNativeEngineArtifact,
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
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths)
import Infernix.Engines.Artifact
  ( EngineArtifactManifest (..),
    currentArtifactRecipeFingerprint,
    engineArtifactGenerationFingerprint,
    engineArtifactTempRoot,
    linuxArtifactRuntimeExpectation,
    parseNativeArtifactIdentity,
  )
import Infernix.Engines.Artifact.Target
  ( NativeArtifactTarget,
    NativeArtifactTargetEvidence,
    nativeArtifactTarget,
    nativeArtifactTargetFingerprint,
  )
import Infernix.Engines.Provisioning qualified as Provisioning
import System.FilePath ((</>))
import System.Info (arch, os)

data LinuxNativeEngineArtifact = LinuxNativeEngineArtifact
  { linuxNativeEngineAdapterId :: Text,
    linuxNativeEngineName :: Text,
    linuxNativeEngineArtifactKind :: Text,
    linuxNativeEngineSourceRef :: Text,
    linuxNativeEngineVersion :: Text,
    linuxNativeRuntimeVersion :: Text
  }
  deriving (Eq, Show)

linuxNativeEngineBuildPlan :: [LinuxNativeEngineArtifact]
linuxNativeEngineBuildPlan =
  [ LinuxNativeEngineArtifact
      "llama-cpp-cli"
      "llama.cpp Linux runner"
      "native-binary"
      "github:ggml-org/llama.cpp"
      "pinned-by-manifest"
      "linux-native",
    LinuxNativeEngineArtifact
      "whisper-cpp-cli"
      "whisper.cpp Linux runner"
      "native-binary"
      "github:ggml-org/whisper.cpp"
      "pinned-by-manifest"
      "linux-native",
    LinuxNativeEngineArtifact
      "onnx-runtime-native"
      "ONNX Runtime Linux runner"
      "native-binary"
      "github:microsoft/onnxruntime"
      "pinned-by-manifest"
      "linux-native",
    LinuxNativeEngineArtifact
      "ctranslate2-native"
      "CTranslate2 Linux runner"
      "native-binary"
      "github:OpenNMT/CTranslate2"
      "pinned-by-manifest"
      "linux-native",
    LinuxNativeEngineArtifact
      "jvm-native"
      "Audiveris JVM Linux runner"
      "jvm-tool"
      "github:Audiveris/audiveris"
      "pinned-by-manifest"
      "linux-native-jvm"
  ]

linuxNativeEngineArtifactAdapterIds :: [Text]
linuxNativeEngineArtifactAdapterIds =
  map linuxNativeEngineAdapterId linuxNativeEngineBuildPlan

linuxNativeEngineImageRoot :: FilePath
linuxNativeEngineImageRoot = "/opt/infernix/engines"

linuxNativeEngineInstallRoot :: FilePath -> Text -> FilePath
linuxNativeEngineInstallRoot baseRoot adapterId =
  baseRoot </> Text.unpack adapterId

materializeLinuxNativeEngines :: Paths -> IO ()
materializeLinuxNativeEngines paths = do
  unless (os == "linux") $
    ioError (userError linuxNativeLaneNotLinuxMessage)
  materializeLinuxNativeEnginesAt paths linuxNativeEngineImageRoot

materializeLinuxNativeEnginesAt :: Paths -> FilePath -> IO ()
materializeLinuxNativeEnginesAt paths baseRoot = do
  environment <- Subprocess.clusterSubprocessEnv paths
  Provisioning.withEngineProvisioningSession paths baseRoot environment $ \writer grant ->
    mapM_
      (materializeLinuxNativeEngineArtifact writer grant baseRoot)
      linuxNativeEngineBuildPlan

materializeLinuxNativeEngineArtifact ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  FilePath ->
  LinuxNativeEngineArtifact ->
  Provisioning.ProvisioningSession s FilePath
materializeLinuxNativeEngineArtifact writer grant baseRoot artifact = do
  let installRoot =
        linuxNativeEngineInstallRoot
          baseRoot
          (linuxNativeEngineAdapterId artifact)
      tempRoot = engineArtifactTempRoot installRoot
  identity <-
    maybe
      ( Provisioning.failProvisioningSession
          ( "closed Linux native build plan omitted artifact identity for "
              <> Text.unpack (linuxNativeEngineAdapterId artifact)
          )
      )
      pure
      (parseNativeArtifactIdentity (linuxNativeEngineAdapterId artifact))
  target <-
    either
      Provisioning.failProvisioningSession
      pure
      (nativeArtifactTarget identity "linux-native" linuxNativeArchitecture)
  deadline <-
    either
      Provisioning.failProvisioningSession
      pure
      (Provisioning.mkProvisioningDeadline linuxNativeActivationTimeoutMicros)
  Provisioning.provisioningReconcileArtifactRoot writer installRoot
  Provisioning.provisioningCreateDirectory writer tempRoot
  Provisioning.provisioningWriteFile
    writer
    (tempRoot </> "README.txt")
    ( "Infernix Linux native engine metadata for "
        <> Text.unpack (linuxNativeEngineAdapterId artifact)
        <> ". The executable and its immutable runtime closure are image-owned, "
        <> "selected by the closed Haskell target catalog, and bound below by exact "
        <> "file-identity and digest evidence.\n"
    )
  Provisioning.completeLinuxCandidate
    writer
    grant
    deadline
    identity
    target
    Provisioning.RequireImagePayload
    installRoot
    tempRoot
    ( Provisioning.mkLinuxManifestBuilder
        ( manifestForLinuxNativeEngineArtifactWithDigest
            installRoot
            artifact
            target
        )
    )
  pure installRoot

linuxNativeActivationTimeoutMicros :: Int
linuxNativeActivationTimeoutMicros = 30 * 1000 * 1000

manifestForLinuxNativeEngineArtifact ::
  FilePath ->
  NativeArtifactTargetEvidence ->
  LinuxNativeEngineArtifact ->
  Either String EngineArtifactManifest
manifestForLinuxNativeEngineArtifact installRoot targetEvidence artifact = do
  target <- linuxNativeTargetForArtifact artifact
  manifestForLinuxNativeEngineArtifactWithDigest
    installRoot
    artifact
    target
    targetEvidence
    (linuxNativeEngineArtifactDigest artifact target)

manifestForLinuxNativeEngineArtifactWithDigest ::
  FilePath ->
  LinuxNativeEngineArtifact ->
  NativeArtifactTarget ->
  NativeArtifactTargetEvidence ->
  Text ->
  Either String EngineArtifactManifest
manifestForLinuxNativeEngineArtifactWithDigest
  installRoot
  artifact
  target
  targetEvidence
  digest = do
    let digestSuffix = Text.drop 1 (Text.dropWhile (/= ':') digest)
    identity <-
      maybe
        ( Left
            ( "closed Linux native build plan omitted artifact identity for "
                <> Text.unpack (linuxNativeEngineAdapterId artifact)
            )
        )
        Right
        (parseNativeArtifactIdentity (linuxNativeEngineAdapterId artifact))
    recipeFingerprint <-
      currentArtifactRecipeFingerprint
        identity
        linuxArtifactRuntimeExpectation
    generationFingerprint <-
      engineArtifactGenerationFingerprint
        "linux-native"
        digest
        recipeFingerprint
        (nativeArtifactTargetFingerprint target)
        (Just targetEvidence)
    pure
      EngineArtifactManifest
        { manifestAdapterId = linuxNativeEngineAdapterId artifact,
          manifestEngineName = linuxNativeEngineName artifact,
          manifestSubstrate = "linux-native",
          manifestArchitecture = linuxNativeArchitecture,
          manifestArtifactKind = linuxNativeEngineArtifactKind artifact,
          manifestSourceRef = linuxNativeEngineSourceRef artifact,
          manifestEngineVersion = linuxNativeEngineVersion artifact,
          manifestPythonVersion = Nothing,
          manifestRuntimeVersion = linuxNativeRuntimeVersion artifact,
          manifestResolvedProvenance = [],
          manifestRecipeFingerprint = recipeFingerprint,
          manifestDigest = digest,
          manifestGenerationFingerprint = generationFingerprint,
          manifestMinioObjectKey =
            "engine-artifacts/linux/"
              <> linuxNativeArchitecture
              <> "/"
              <> linuxNativeEngineAdapterId artifact
              <> "/"
              <> digestSuffix
              <> ".tar.zst",
          manifestLocalInstallRoot = installRoot,
          manifestTargetContractFingerprint =
            nativeArtifactTargetFingerprint target,
          manifestImageTargetEvidence = Just targetEvidence
        }

linuxNativeTargetForArtifact ::
  LinuxNativeEngineArtifact ->
  Either String NativeArtifactTarget
linuxNativeTargetForArtifact artifact = do
  identity <-
    maybe
      ( Left
          ( "closed Linux native build plan omitted artifact identity for "
              <> Text.unpack (linuxNativeEngineAdapterId artifact)
          )
      )
      Right
      (parseNativeArtifactIdentity (linuxNativeEngineAdapterId artifact))
  nativeArtifactTarget identity "linux-native" linuxNativeArchitecture

linuxNativeEngineArtifactDigest ::
  LinuxNativeEngineArtifact ->
  NativeArtifactTarget ->
  Text
linuxNativeEngineArtifactDigest artifact target =
  let digestInput =
        Text.intercalate
          "\n"
          [ linuxNativeEngineAdapterId artifact,
            linuxNativeEngineName artifact,
            linuxNativeEngineArtifactKind artifact,
            linuxNativeEngineSourceRef artifact,
            linuxNativeEngineVersion artifact,
            linuxNativeRuntimeVersion artifact,
            nativeArtifactTargetFingerprint target
          ]
      digestBytes =
        SHA256.hashlazy
          (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digestBytes)

linuxNativeArchitecture :: Text
linuxNativeArchitecture =
  case arch of
    "x86_64" -> "amd64"
    "aarch64" -> "arm64"
    other -> Text.pack other

linuxNativeLaneNotLinuxMessage :: String
linuxNativeLaneNotLinuxMessage =
  "infernix internal materialize-linux-native-engines is Linux-only: it binds "
    <> "image-owned native targets under /opt/infernix to exact metadata roots "
    <> "under /opt/infernix/engines/<adapterId>/."
