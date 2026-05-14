module Test.Main where

import Prelude

import Data.Array (any, head, length)
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (error, launchAff_, throwError)
import Generated.Contracts
  ( EngineBinding
  , InferenceResult(..)
  , ModelDescriptor
  , RequestFieldRecord
  , ResultPayload(..)
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
import Infernix.Web.Workbench
  ( catalogCards
  , describeCompletedRequest
  , filterModels
  , publicationSummary
  , selectionSummary
  )
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (defaultConfig, evalSpecT)
import Test.Spec.Summary (successful)
import Data.Newtype (un)

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
          requestTopics `shouldEqual` [ "persistent://public/default/inference.request." <> runtimeMode ]
          resultTopic `shouldEqual` ("persistent://public/default/inference.result." <> runtimeMode)
          length engines `shouldEqual` expectedEngineCount runtimeMode
          length models `shouldEqual` expectedModelCount runtimeMode
          any hasEngineMetadata engines `shouldEqual` true
          any hasModelMetadata models `shouldEqual` true

      describe "workbench view model" do
        it "filters and preserves catalog order" do
          any (\model -> (modelDescriptorRecord model).modelId == "llm-qwen25-safetensors") (filterModels models "qwen") `shouldEqual` true
          let firstModelId = (_.modelId <<< modelDescriptorRecord <$> head models)
          map _.modelId (catalogCards models "" firstModelId) `shouldEqual` map (_.modelId <<< modelDescriptorRecord) models

        it "renders the selected model and result framing" do
          case head models of
            Nothing -> length models `shouldEqual` 0
            Just firstModel -> do
              let firstModelValue = modelDescriptorRecord firstModel
              (selectionSummary (Just firstModel)).inputLabel `shouldEqual` firstFieldLabel firstModelValue.requestShape
              (selectionSummary (Just firstModel)).artifactType `shouldEqual` firstModelValue.artifactType
              publicationSummary
                ( Just
                    { runtimeMode: Just runtimeMode
                    , controlPlaneContext: Just "host-native"
                    , daemonLocation: Just "cluster-pod"
                    , inferenceDispatchMode: Just "pulsar-bridge-to-host-daemon"
                    , catalogSource: Just "generated-build-root"
                    , edgePort: Just 9090
                    , apiUpstream: Just { mode: "cluster-demo", host: Just "infernix-demo.platform.svc.cluster.local", port: Just 80 }
                    , demoConfigPath: Just "/tmp/infernix-substrate.dhall"
                    , generatedDemoConfigPath: Nothing
                    , mountedDemoConfigPath: Nothing
                    , routes: Just [ { path: "/api", purpose: "Demo API" } ]
                    , upstreams: Just [ { id: "demo", routePrefix: Just "/", healthStatus: "ready", targetSurface: "cluster-resident demo surface", durableBackendState: "generated web bundle and Haskell demo daemon" } ]
                    }
                )
                runtimeMode
                `shouldEqual`
                  { runtimeMode
                  , controlPlaneContext: "host-native"
                  , daemonLocation: "cluster-pod"
                  , inferenceDispatchMode: "pulsar-bridge-to-host-daemon"
                  , catalogSource: "generated-build-root"
                  , edgePort: "9090"
                  , apiUpstreamMode: "cluster-demo"
                  , demoConfigPath: "/tmp/infernix-substrate.dhall"
                  , routes: [ { path: "/api", purpose: "Demo API" } ]
                  , upstreams: [ { id: "demo", routePrefix: Just "/", healthStatus: "ready", targetSurface: "cluster-resident demo surface", durableBackendState: "generated web bundle and Haskell demo daemon" } ]
                  }
              publicationSummary Nothing runtimeMode
                `shouldEqual`
                  { runtimeMode
                  , controlPlaneContext: "Unavailable"
                  , daemonLocation: "Unavailable"
                  , inferenceDispatchMode: "Unavailable"
                  , catalogSource: "Unavailable"
                  , edgePort: "Not published"
                  , apiUpstreamMode: "Unavailable"
                  , demoConfigPath: "Unavailable"
                  , routes: []
                  , upstreams: []
                  }
              let completedRequest =
                    describeCompletedRequest
                      ( InferenceResult
                          { requestId: "req-1"
                          , resultModelId: firstModelValue.modelId
                          , matrixRowId: firstModelValue.matrixRowId
                          , runtimeMode: runtimeMode
                          , selectedEngine: firstModelValue.selectedEngine
                          , status: "completed"
                          , payload: ResultPayload { inlineOutput: Nothing, objectRef: Just "results/req-1.txt" }
                          , createdAt: "2026-04-26T00:00:00Z"
                          }
                      )
                      (Just firstModel)
              completedRequest.statusText `shouldEqual` ("Completed request req-1 on " <> firstModelValue.selectedEngine)
              completedRequest.resultLabel `shouldEqual` (selectionSummary (Just firstModel)).resultLabel
              completedRequest.outputText `shouldEqual` "Stored object reference: results/req-1.txt"
              completedRequest.objectHref `shouldEqual` Just "/objects/results/req-1.txt"

    unless (successful results) do
      throwError (error "PureScript unit tests failed")

expectedModelCount :: String -> Int
expectedModelCount mode =
  case mode of
    "apple-silicon" -> 15
    "linux-cpu" -> 12
    "linux-gpu" -> 16
    _ -> 0

expectedEngineCount :: String -> Int
expectedEngineCount mode =
  case mode of
    "apple-silicon" -> 12
    "linux-cpu" -> 10
    "linux-gpu" -> 10
    _ -> 0

hasEngineMetadata :: EngineBinding -> Boolean
hasEngineMetadata binding =
  let bindingValue = engineBindingRecord binding
  in bindingValue.engine /= "" && bindingValue.adapterId /= "" && bindingValue.adapterType /= "" && bindingValue.adapterLocator /= ""

hasModelMetadata :: ModelDescriptor -> Boolean
hasModelMetadata model =
  let modelValue = modelDescriptorRecord model
  in modelValue.selectedEngine /= "" && modelValue.runtimeLane /= "" && modelValue.runtimeMode == runtimeMode

firstFieldLabel :: Array RequestFieldRecord -> String
firstFieldLabel fields =
  case head fields of
    Just field -> field.label
    Nothing -> "Input Text"
