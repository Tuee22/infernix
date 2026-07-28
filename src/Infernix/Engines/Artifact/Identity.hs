{-# LANGUAGE OverloadedStrings #-}

-- | Package-internal closed identity for every native runner artifact.
module Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    parseNativeArtifactIdentity,
    nativeArtifactAdapterId,
    nativeArtifactEntrypoint,
    nativeArtifactSmokeArguments,
    nativeArtifactSmokeCommand,
  )
where

import Data.Text (Text)

data NativeArtifactIdentity
  = LlamaCppArtifact
  | WhisperCppArtifact
  | CTranslate2Artifact
  | OnnxRuntimeArtifact
  | MlxArtifact
  | CoreMlArtifact
  | JvmArtifact
  deriving (Eq, Show)

parseNativeArtifactIdentity :: Text -> Maybe NativeArtifactIdentity
parseNativeArtifactIdentity adapterId =
  case adapterId of
    "llama-cpp-cli" -> Just LlamaCppArtifact
    "whisper-cpp-cli" -> Just WhisperCppArtifact
    "ctranslate2-native" -> Just CTranslate2Artifact
    "onnx-runtime-native" -> Just OnnxRuntimeArtifact
    "mlx-native" -> Just MlxArtifact
    "coreml-native" -> Just CoreMlArtifact
    "jvm-native" -> Just JvmArtifact
    _ -> Nothing

nativeArtifactAdapterId :: NativeArtifactIdentity -> Text
nativeArtifactAdapterId identity =
  case identity of
    LlamaCppArtifact -> "llama-cpp-cli"
    WhisperCppArtifact -> "whisper-cpp-cli"
    CTranslate2Artifact -> "ctranslate2-native"
    OnnxRuntimeArtifact -> "onnx-runtime-native"
    MlxArtifact -> "mlx-native"
    CoreMlArtifact -> "coreml-native"
    JvmArtifact -> "jvm-native"

nativeArtifactEntrypoint :: NativeArtifactIdentity -> FilePath
nativeArtifactEntrypoint identity =
  case identity of
    LlamaCppArtifact -> "bin/llama-cli"
    WhisperCppArtifact -> "bin/whisper-cli"
    CTranslate2Artifact -> "bin/ct2-runner"
    OnnxRuntimeArtifact -> "bin/onnx-runner"
    MlxArtifact -> "bin/mlx-runner"
    CoreMlArtifact -> "bin/coreml-runner"
    JvmArtifact -> "bin/audiveris"

nativeArtifactSmokeArguments :: NativeArtifactIdentity -> [String]
nativeArtifactSmokeArguments _identity = ["--smoke"]

nativeArtifactSmokeCommand :: NativeArtifactIdentity -> String
nativeArtifactSmokeCommand identity =
  unwords
    ( nativeArtifactEntrypoint identity
        : nativeArtifactSmokeArguments identity
    )
