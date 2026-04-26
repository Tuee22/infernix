module Infernix.Web.Workbench
  ( ApiUpstream
  , CatalogCard
  , CompletedRequestSummary
  , Publication
  , PublicationSummary
  , PublicationUpstream
  , RouteInfo
  , SelectionSummary
  , catalogCards
  , describeCompletedRequest
  , filterModels
  , publicationSummary
  , selectedModel
  , selectionSummary
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array (filter, find, head)
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CodeUnits (contains)
import Data.String.Common (toLower, trim)
import Data.String.Pattern (Pattern(..))
import Generated.Contracts
  ( InferenceResult
  , ModelDescriptor
  , ModelDescriptorRecord
  , inferenceResultRecord
  , modelDescriptorRecord
  )

type CatalogCard =
  { modelId :: String
  , displayName :: String
  , description :: String
  , family :: String
  , artifactType :: String
  , selectedEngine :: String
  , isActive :: Boolean
  }

type SelectionSummary =
  { name :: String
  , engine :: String
  , lane :: String
  , familyLabel :: String
  , artifactType :: String
  , notes :: String
  , inputLabel :: String
  , placeholder :: String
  , requestGuidance :: String
  , submitLabel :: String
  , resultLabel :: String
  }

type CompletedRequestSummary =
  { statusText :: String
  , resultLabel :: String
  , outputText :: String
  , objectHref :: Maybe String
  , objectLinkLabel :: Maybe String
  }

type RouteInfo =
  { path :: String
  , purpose :: String
  }

type ApiUpstream =
  { mode :: String
  , host :: Maybe String
  , port :: Maybe Int
  }

type PublicationUpstream =
  { id :: String
  , routePrefix :: Maybe String
  , targetSurface :: String
  , healthStatus :: String
  , durableBackendState :: String
  }

type Publication =
  { runtimeMode :: Maybe String
  , controlPlaneContext :: Maybe String
  , daemonLocation :: Maybe String
  , catalogSource :: Maybe String
  , edgePort :: Maybe Int
  , apiUpstream :: Maybe ApiUpstream
  , demoConfigPath :: Maybe String
  , generatedDemoConfigPath :: Maybe String
  , mountedDemoConfigPath :: Maybe String
  , routes :: Maybe (Array RouteInfo)
  , upstreams :: Maybe (Array PublicationUpstream)
  }

type PublicationSummary =
  { runtimeMode :: String
  , controlPlaneContext :: String
  , daemonLocation :: String
  , catalogSource :: String
  , edgePort :: String
  , apiUpstreamMode :: String
  , demoConfigPath :: String
  , routes :: Array RouteInfo
  , upstreams :: Array PublicationUpstream
  }

selectedModel :: Array ModelDescriptor -> Maybe String -> Maybe ModelDescriptor
selectedModel models selectedModelId =
  find (\model -> Just (modelDescriptorRecord model).modelId == selectedModelId) models

filterModels :: Array ModelDescriptor -> String -> Array ModelDescriptor
filterModels models query =
  if normalized == "" then models else filter matches models
  where
  normalized = toLower (trim query)

  matches model =
    let modelValue = modelDescriptorRecord model
    in anyContains [ modelValue.modelId, modelValue.displayName, modelValue.family ]

  anyContains = foldr (\value matched -> matched || contains (Pattern normalized) (toLower value)) false

catalogCards :: Array ModelDescriptor -> String -> Maybe String -> Array CatalogCard
catalogCards models query selectedModelId =
  map toCard (filterModels models query)
  where
  toCard model =
    let modelValue = modelDescriptorRecord model
    in
    { modelId: modelValue.modelId
    , displayName: modelValue.displayName
    , description: modelValue.description
    , family: modelValue.family
    , artifactType: modelValue.artifactType
    , selectedEngine: modelValue.selectedEngine
    , isActive: Just modelValue.modelId == selectedModelId
    }

selectionSummary :: Maybe ModelDescriptor -> SelectionSummary
selectionSummary maybeModel =
  case maybeModel of
    Nothing ->
      { name: "No model selected"
      , engine: "No engine"
      , lane: "No runtime lane"
      , familyLabel: "No workload family"
      , artifactType: "No artifact type"
      , notes: "No notes"
      , inputLabel: "Input Text"
      , placeholder: "Type a request payload"
      , requestGuidance: "Select a model to load family-specific request guidance."
      , submitLabel: "Run Inference"
      , resultLabel: "Result payload"
      }
    Just model ->
      let
        modelValue = modelDescriptorRecord model
        familyView = familyPresentation modelValue.family
      in
        { name: modelValue.displayName
        , engine: modelValue.selectedEngine
        , lane: modelValue.runtimeLane
        , familyLabel: familyView.familyLabel
        , artifactType: modelValue.artifactType
        , notes: modelValue.notes
        , inputLabel: inputLabelForModel modelValue
        , placeholder: familyView.placeholder
        , requestGuidance: familyView.requestGuidance
        , submitLabel: familyView.submitLabel
        , resultLabel: familyView.resultLabel
        }

describeCompletedRequest :: InferenceResult -> Maybe ModelDescriptor -> CompletedRequestSummary
describeCompletedRequest result maybeModel =
  { statusText: "Completed request " <> resultValue.requestId <> " on " <> selectedEngineValue
  , resultLabel: familyView.resultLabel
  , outputText: fromMaybe defaultOutput resultValue.payload.inlineOutput
  , objectHref: map (\objectRef -> "/objects/" <> objectRef) resultValue.payload.objectRef
  , objectLinkLabel: map (const familyView.objectLinkLabel) resultValue.payload.objectRef
  }
  where
  resultValue = inferenceResultRecord result

  familyView =
    familyPresentation case maybeModel of
      Just model -> (modelDescriptorRecord model).family
      Nothing -> ""

  selectedEngineValue =
    if trim resultValue.selectedEngine == "" then fromMaybe "the active engine" ((_.selectedEngine <<< modelDescriptorRecord) <$> maybeModel) else resultValue.selectedEngine

  defaultOutput =
    case resultValue.payload.objectRef of
      Just objectRef -> "Stored object reference: " <> objectRef
      Nothing -> "No result yet."

publicationSummary :: Maybe Publication -> String -> PublicationSummary
publicationSummary maybePublication fallbackRuntimeMode =
  { runtimeMode: fromMaybe fallbackRuntimeMode (maybePublication >>= _.runtimeMode)
  , controlPlaneContext: fromMaybe "Unavailable" (maybePublication >>= _.controlPlaneContext)
  , daemonLocation: fromMaybe "Unavailable" (maybePublication >>= _.daemonLocation)
  , catalogSource: fromMaybe "Unavailable" (maybePublication >>= _.catalogSource)
  , edgePort:
      case maybePublication >>= _.edgePort of
        Just portValue -> show portValue
        Nothing -> "Not published"
  , apiUpstreamMode: fromMaybe "Unavailable" (maybePublication >>= (_.apiUpstream >>> map _.mode))
  , demoConfigPath:
      fromMaybe "Unavailable"
        ( maybePublication >>= \publication ->
            publication.demoConfigPath
              <|> publication.generatedDemoConfigPath
              <|> publication.mountedDemoConfigPath
        )
  , routes: fromMaybe [] (maybePublication >>= _.routes)
  , upstreams: fromMaybe [] (maybePublication >>= _.upstreams)
  }

inputLabelForModel :: ModelDescriptorRecord -> String
inputLabelForModel model =
  case head model.requestShape of
    Just field -> field.label
    Nothing -> "Input Text"

type FamilyPresentation =
  { familyLabel :: String
  , placeholder :: String
  , requestGuidance :: String
  , submitLabel :: String
  , resultLabel :: String
  , objectLinkLabel :: String
  }

familyPresentation :: String -> FamilyPresentation
familyPresentation family =
  case family of
    "llm" ->
      { familyLabel: "Text generation"
      , placeholder: "Ask for an answer, rewrite, or summary."
      , requestGuidance: "This lane accepts free-form prompts and returns generated text."
      , submitLabel: "Generate Text"
      , resultLabel: "Generated text"
      , objectLinkLabel: "Open large text output"
      }
    "speech" ->
      { familyLabel: "Speech transcription"
      , placeholder: "Describe the transcript or spoken phrase to process."
      , requestGuidance: "Speech rows present the request as a transcription job and return transcript-oriented output."
      , submitLabel: "Transcribe Speech"
      , resultLabel: "Transcript"
      , objectLinkLabel: "Open large transcript output"
      }
    "audio" ->
      { familyLabel: "Audio workflow"
      , placeholder: "Describe the audio transformation or generation request."
      , requestGuidance: "Audio rows render workflow guidance rather than generic text-generation copy."
      , submitLabel: "Run Audio Flow"
      , resultLabel: "Audio workflow output"
      , objectLinkLabel: "Open large audio workflow output"
      }
    "music" ->
      { familyLabel: "Music workflow"
      , placeholder: "Describe the composition, style, or music task to run."
      , requestGuidance: "Music rows frame the request as a composition or music workflow."
      , submitLabel: "Run Music Flow"
      , resultLabel: "Music workflow output"
      , objectLinkLabel: "Open large music workflow output"
      }
    "image" ->
      { familyLabel: "Image prompt"
      , placeholder: "Describe the image concept, scene, or edit request."
      , requestGuidance: "Image rows keep the same API but present prompt language that matches visual generation tasks."
      , submitLabel: "Render Image Prompt"
      , resultLabel: "Image workflow output"
      , objectLinkLabel: "Open large image output"
      }
    "video" ->
      { familyLabel: "Video prompt"
      , placeholder: "Describe the scene, motion, or shot sequence to generate."
      , requestGuidance: "Video rows treat the request as a shot or sequence prompt and label results accordingly."
      , submitLabel: "Render Video Prompt"
      , resultLabel: "Video workflow output"
      , objectLinkLabel: "Open large video output"
      }
    _ ->
      { familyLabel: "Tool workflow"
      , placeholder: "Describe the tool or structured workflow request."
      , requestGuidance: "Tool rows keep one request field while presenting tool-oriented workflow copy."
      , submitLabel: "Run Tool Flow"
      , resultLabel: "Tool workflow output"
      , objectLinkLabel: "Open large tool output"
      }
