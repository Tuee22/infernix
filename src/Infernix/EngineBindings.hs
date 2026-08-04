{-# LANGUAGE OverloadedStrings #-}

module Infernix.EngineBindings
  ( canonicalEngineBindingForSelectedEngine,
    canonicalEngineBindingsForMode,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Types
  ( EngineAdapterType (..),
    EngineBinding (..),
    RuntimeMode (..),
  )

data SupportedAdapter
  = VllmPython
  | TransformersPython
  | DiffusersPython
  | PytorchPython
  | WhisperCpp
  | LlamaCpp
  | OnnxRuntime
  | CoreMl
  | CTranslate2
  | Mlx
  | Jvm

-- | Exact runtime-scoped engine names. Each choice maps to one of the Python
-- modules or native runner ids that the worker's closed dispatcher supports.
supportedEngineChoices :: RuntimeMode -> [(Text, SupportedAdapter)]
supportedEngineChoices runtimeMode =
  case runtimeMode of
    AppleSilicon ->
      [ ("Transformers + PyTorch MPS", TransformersPython),
        ("llama.cpp (Metal)", LlamaCpp),
        ("MLX / MLX-LM", Mlx),
        ("whisper.cpp (Metal)", WhisperCpp),
        ("CTranslate2 (CPU)", CTranslate2),
        ("PyTorch MPS", PytorchPython),
        ("PyTorch CPU", PytorchPython),
        ("Core ML", CoreMl),
        ("ONNX Runtime", OnnxRuntime),
        ("Diffusers on MPS", DiffusersPython),
        ("JVM", Jvm)
      ]
    LinuxCpu ->
      [ ("Transformers + PyTorch CPU", TransformersPython),
        ("llama.cpp", LlamaCpp),
        ("whisper.cpp", WhisperCpp),
        ("CTranslate2", CTranslate2),
        ("PyTorch CPU", PytorchPython),
        ("ONNX Runtime CPU", OnnxRuntime),
        ("JVM", Jvm)
      ]
    LinuxGpu ->
      [ ("vLLM", VllmPython),
        ("llama.cpp", LlamaCpp),
        ("whisper.cpp", WhisperCpp),
        ("CTranslate2", CTranslate2),
        ("PyTorch CUDA", PytorchPython),
        ("ONNX Runtime (CPU)", OnnxRuntime),
        ("Diffusers or ComfyUI", DiffusersPython),
        ("JVM", Jvm)
      ]

-- | The sole derivation of executable adapter metadata from a selected engine.
-- Unknown names and names from another runtime have no binding.
canonicalEngineBindingForSelectedEngine :: RuntimeMode -> Text -> Maybe EngineBinding
canonicalEngineBindingForSelectedEngine runtimeMode selectedEngineValue =
  bindingForSupportedAdapter selectedEngineValue
    <$> lookup selectedEngineValue (supportedEngineChoices runtimeMode)

canonicalEngineBindingsForMode :: RuntimeMode -> [EngineBinding]
canonicalEngineBindingsForMode runtimeMode =
  [ bindingForSupportedAdapter selectedEngineValue adapter
  | (selectedEngineValue, adapter) <- supportedEngineChoices runtimeMode
  ]

bindingForSupportedAdapter :: Text -> SupportedAdapter -> EngineBinding
bindingForSupportedAdapter selectedEngineValue adapter =
  let adapterId = supportedAdapterId adapter
      pythonNative = supportedAdapterIsPython adapter
      adapterType
        | pythonNative = PythonStdio
        | otherwise = NativeProcessRunner
      adapterLocator
        | pythonNative = "adapters/" <> adapterModuleName adapterId <> ".py"
        | otherwise = adapterId
      adapterEntrypoint
        | pythonNative = "adapter-" <> adapterId
        | otherwise = "runner-" <> adapterId
   in EngineBinding
        { engineBindingName = selectedEngineValue,
          engineBindingAdapterId = adapterId,
          engineBindingAdapterType = adapterType,
          engineBindingAdapterLocator = adapterLocator,
          engineBindingAdapterEntrypoint = adapterEntrypoint,
          engineBindingSetupEntrypoint = "setup-" <> adapterId,
          engineBindingProjectDirectory = "python",
          engineBindingPythonNative = pythonNative
        }
  where
    adapterModuleName = Text.replace "-" "_"

supportedAdapterId :: SupportedAdapter -> Text
supportedAdapterId adapter =
  case adapter of
    VllmPython -> "vllm-python"
    TransformersPython -> "transformers-python"
    DiffusersPython -> "diffusers-python"
    PytorchPython -> "pytorch-python"
    WhisperCpp -> "whisper-cpp-cli"
    LlamaCpp -> "llama-cpp-cli"
    OnnxRuntime -> "onnx-runtime-native"
    CoreMl -> "coreml-native"
    CTranslate2 -> "ctranslate2-native"
    Mlx -> "mlx-native"
    Jvm -> "jvm-native"

supportedAdapterIsPython :: SupportedAdapter -> Bool
supportedAdapterIsPython adapter =
  case adapter of
    VllmPython -> True
    TransformersPython -> True
    DiffusersPython -> True
    PytorchPython -> True
    WhisperCpp -> False
    LlamaCpp -> False
    OnnxRuntime -> False
    CoreMl -> False
    CTranslate2 -> False
    Mlx -> False
    Jvm -> False
