module Test.Main where

import Prelude

import Data.Array (any, length)
import Data.Identity (Identity(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (error, launchAff_, throwError)
import Generated.Contracts
  ( EngineBinding
  , ModelDescriptor
  , apiBasePath
  , engineBindingRecord
  , engines
  , maxInlineOutputLength
  , modelDescriptorRecord
  , models
  , requestTopics
  , resultTopic
  , runtimeMode
  )
import Infernix.Web.ArtifactsSpec as ArtifactsSpec
import Infernix.Web.ChatSpec as ChatSpec
import Infernix.Web.ContractsSpec as ContractsSpec
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (defaultConfig, evalSpecT)
import Test.Spec.Summary (successful)

main :: Effect Unit
main =
  launchAff_ do
    results <-
      un Identity $
        evalSpecT
          (defaultConfig { exit = false })
          [ consoleReporter ]
          do
      describe "generated contracts" do
        it "publish the active runtime constants" do
          apiBasePath `shouldEqual` "/api"
          maxInlineOutputLength `shouldEqual` 80
          requestTopics `shouldEqual` [ "persistent://infernix/demo/inference.request." <> runtimeMode ]
          resultTopic `shouldEqual` ("persistent://infernix/demo/inference.result." <> runtimeMode)
          length engines `shouldEqual` expectedEngineCount runtimeMode
          length models `shouldEqual` expectedModelCount runtimeMode
          any hasEngineMetadata engines `shouldEqual` true
          any hasModelMetadata models `shouldEqual` true

      ContractsSpec.spec
      ChatSpec.spec
      ArtifactsSpec.spec

    unless (successful results) do
      throwError (error "PureScript unit tests failed")

expectedModelCount :: String -> Int
expectedModelCount mode =
  case mode of
    "apple-silicon" -> 16
    "linux-cpu" -> 12
    "linux-gpu" -> 16
    _ -> 0

expectedEngineCount :: String -> Int
expectedEngineCount mode =
  case mode of
    "apple-silicon" -> 10
    "linux-cpu" -> 7
    "linux-gpu" -> 8
    _ -> 0

hasEngineMetadata :: EngineBinding -> Boolean
hasEngineMetadata binding =
  let bindingValue = engineBindingRecord binding
  in bindingValue.engine /= "" && bindingValue.adapterId /= "" && bindingValue.adapterType /= "" && bindingValue.adapterLocator /= ""

hasModelMetadata :: ModelDescriptor -> Boolean
hasModelMetadata model =
  let modelValue = modelDescriptorRecord model
  in modelValue.selectedEngine /= "" && modelValue.runtimeLane /= "" && modelValue.runtimeMode == runtimeMode
