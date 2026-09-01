module Test.Main where

import Prelude

import Data.Array (any, length)
import Data.Identity (Identity(..))
import Data.Newtype (un)
import Effect (Effect)
import Effect.Aff (error, launchAff_, throwError)
import Generated.Contracts
  ( ModelDescriptor
  , apiBasePath
  , maxInlineOutputLength
  , modelDescriptorRecord
  , models
  , runtimeMode
  )
import Infernix.Web.ArtifactsSpec as ArtifactsSpec
import Infernix.Web.AuthSpec as AuthSpec
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
          length models `shouldEqual` expectedModelCount runtimeMode
          any hasModelMetadata models `shouldEqual` true

      ContractsSpec.spec
      AuthSpec.spec
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

hasModelMetadata :: ModelDescriptor -> Boolean
hasModelMetadata model =
  let modelValue = modelDescriptorRecord model
  in modelValue.selectedEngine /= "" && modelValue.runtimeLane /= "" && modelValue.runtimeMode == runtimeMode
