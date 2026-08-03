{-# LANGUAGE OverloadedStrings #-}

-- | Package-internal closed identity for every native runner artifact.
module Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    parseNativeArtifactIdentity,
    nativeArtifactAdapterId,
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

-- The @bin\/*@ wrapper entrypoint and its uniform @--smoke@ command are
-- deliberately absent. Generated shell wrappers were retired on the Apple side
-- and the Linux lane was the last consumer of the wrapper-shaped contract; the
-- supported spelling of a runner is now the closed direct-target catalog in
-- "Infernix.Engines.Artifact.Target", which names an installed relative path or
-- an absolute image path together with the leading arguments that target needs.
