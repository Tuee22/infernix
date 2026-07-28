{-# LANGUAGE OverloadedStrings #-}

-- | Single source of truth for native artifact materialization inputs.
--
-- Provisioning command constructors consume the exact pins exported here,
-- while artifact manifests fingerprint the same catalog plus the closed
-- runner and materializer policy revisions.
module Infernix.Engines.Artifact.Recipe
  ( ApplePythonRecipe (..),
    pinnedPipRequirement,
    pinnedPythonRequirements,
    audiverisVersion,
    audiverisDmgFileName,
    audiverisDmgUrl,
    audiverisDmgDigest,
    audiverisDmgSize,
    nativeArtifactRecipeFingerprint,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    nativeArtifactAdapterId,
  )
import Infernix.Engines.Artifact.Target
  ( nativeArtifactTarget,
    nativeArtifactTargetFingerprint,
  )

data ApplePythonRecipe
  = CTranslate2PythonRecipe
  | OnnxRuntimePythonRecipe
  | MlxPythonRecipe
  | CoreMlPythonRecipe
  deriving (Eq, Show)

pinnedPipRequirement :: String
pinnedPipRequirement = "pip==26.1.2"

pinnedPythonRequirements :: ApplePythonRecipe -> [String]
pinnedPythonRequirements recipe =
  case recipe of
    CTranslate2PythonRecipe ->
      [ "ctranslate2==4.8.1",
        "faster-whisper==1.2.1",
        "soundfile==0.14.0"
      ]
    OnnxRuntimePythonRecipe ->
      [ "mido==1.3.3",
        "numpy==2.5.1",
        "onnxruntime==1.28.0",
        "scipy==1.18.0",
        "soundfile==0.14.0"
      ]
    MlxPythonRecipe ->
      [ "mlx==0.32.0",
        "mlx-lm==0.29.1",
        "transformers==4.57.6"
      ]
    CoreMlPythonRecipe ->
      [ "setuptools==80.10.2",
        "basic-pitch==0.4.0",
        "coremltools==9.0",
        "mlx==0.32.0",
        "python-coreml-stable-diffusion @ git+https://github.com/apple/ml-stable-diffusion.git@e12202c1f6405b83918b58a5d097cd61e3e1f702"
      ]

audiverisVersion :: String
audiverisVersion = "5.10.2"

audiverisDmgFileName :: FilePath
audiverisDmgFileName = "Audiveris-5.10.2-macosx-arm64.dmg"

audiverisDmgUrl :: String
audiverisDmgUrl =
  "https://github.com/Audiveris/audiveris/releases/download/5.10.2/"
    <> audiverisDmgFileName

audiverisDmgDigest :: Text
audiverisDmgDigest =
  "sha256:727c46b4ca4766349be1f582b67cc5aa0d7306113dcf4a18be169d75959f4288"

audiverisDmgSize :: Integer
audiverisDmgSize = 72638739

nativeArtifactRecipeFingerprint ::
  NativeArtifactIdentity ->
  Text ->
  Text ->
  Either String Text
nativeArtifactRecipeFingerprint identity substrate architecture = do
  target <-
    nativeArtifactTarget identity substrate architecture
  laneInputs <-
    maybe
      ( Left
          ( "closed native artifact identity has no recipe for "
              <> Text.unpack substrate
              <> "/"
              <> Text.unpack architecture
              <> "/"
              <> Text.unpack (nativeArtifactAdapterId identity)
          )
      )
      Right
      (nativeArtifactLaneRecipeInputs identity substrate architecture)
  let recipeBytes =
        TextEncoding.encodeUtf8
          ( Text.intercalate
              "\0"
              ( [ "infernix-engine-artifact-recipe-v3",
                  "adapter=" <> nativeArtifactAdapterId identity,
                  "direct-target=" <> nativeArtifactTargetFingerprint target
                ]
                  <> laneInputs
                  <> [""]
              )
          )
      digest = SHA256.hash recipeBytes
  pure
    ( "sha256:"
        <> TextEncoding.decodeUtf8 (Base16.encode digest)
    )

nativeArtifactLaneRecipeInputs ::
  NativeArtifactIdentity ->
  Text ->
  Text ->
  Maybe [Text]
nativeArtifactLaneRecipeInputs identity substrate architecture =
  case (substrate, architecture) of
    ("apple-silicon", "arm64") ->
      ( [ "lane=apple-silicon/arm64",
          "materializer-revision=apple-headless-materializer-v6",
          "runner-revision=apple-direct-target-v1",
          "activation-policy=fsynced-sibling-rename-v2",
          "provenance-policy=resolved-package-or-copied-closure-v3",
          "runtime-policy=candidate-local-no-global-fallback-v3"
        ]
          <>
      )
        <$> appleRecipePins identity
    ("linux-native", laneArchitecture)
      | laneArchitecture `elem` ["amd64", "arm64"] ->
          ( [ "lane=linux-native/" <> laneArchitecture,
              "materializer-revision=linux-image-artifact-v4",
              "runner-revision=linux-direct-target-v1",
              "activation-policy=fsynced-sibling-rename-v2",
              "payload-policy=image-baked-require-native-payload-no-fallback-v2",
              "provenance-policy=image-build-lock-plus-payload-sha256-v2"
            ]
              <>
          )
            <$> linuxRecipePins identity
    _ -> Nothing

appleRecipePins :: NativeArtifactIdentity -> Maybe [Text]
appleRecipePins identity =
  case nativeArtifactAdapterId identity of
    "llama-cpp-cli" ->
      Just
        [ "upstream=homebrew:llama.cpp",
          "closure-policy=copied-macho-closure-destination-sha256-dyld-audit-v2"
        ]
    "whisper-cpp-cli" ->
      Just
        [ "upstream=homebrew:whisper-cpp",
          "closure-policy=copied-macho-closure-destination-sha256-dyld-audit-v2"
        ]
    "ctranslate2-native" ->
      pythonRecipePins CTranslate2PythonRecipe
    "onnx-runtime-native" ->
      pythonRecipePins OnnxRuntimePythonRecipe
    "mlx-native" ->
      pythonRecipePins MlxPythonRecipe
    "coreml-native" ->
      pythonRecipePins CoreMlPythonRecipe
    "jvm-native" ->
      Just
        [ "audiveris-version=" <> Text.pack audiverisVersion,
          "audiveris-dmg=" <> Text.pack audiverisDmgFileName,
          "audiveris-dmg-digest=" <> audiverisDmgDigest,
          "audiveris-dmg-size=" <> Text.pack (show audiverisDmgSize),
          "audiveris-source=" <> Text.pack audiverisDmgUrl
        ]
    _ -> Nothing
  where
    pythonRecipePins recipe =
      Just
        ( ("pip=" <> Text.pack pinnedPipRequirement)
            : map (("requirement=" <>) . Text.pack) (pinnedPythonRequirements recipe)
        )

linuxRecipePins :: NativeArtifactIdentity -> Maybe [Text]
linuxRecipePins identity =
  case nativeArtifactAdapterId identity of
    "llama-cpp-cli" ->
      Just ["upstream=github:ggml-org/llama.cpp", "pin-policy=image-build-manifest"]
    "whisper-cpp-cli" ->
      Just ["upstream=github:ggml-org/whisper.cpp", "pin-policy=image-build-manifest"]
    "ctranslate2-native" ->
      Just ["upstream=github:OpenNMT/CTranslate2", "pin-policy=image-build-manifest"]
    "onnx-runtime-native" ->
      Just ["upstream=github:microsoft/onnxruntime", "pin-policy=image-build-manifest"]
    "jvm-native" ->
      Just ["upstream=github:Audiveris/audiveris", "pin-policy=image-build-manifest"]
    _ -> Nothing
