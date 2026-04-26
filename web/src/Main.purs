module Main where

import Prelude

import Affjax.RequestBody as RequestBody
import Affjax.RequestHeader as RequestHeader
import Affjax.ResponseFormat as ResponseFormat
import Affjax.StatusCode (StatusCode(..))
import Affjax.Web as AXWeb
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Foldable (traverse_)
import Data.HTTP.Method (Method(..))
import Data.MediaType.Common (applicationJSON)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Effect.Ref as Ref
import Generated.Contracts
  ( ErrorResponse
  , ModelDescriptor
  , apiBasePath
  , errorResponseRecord
  , modelDescriptorRecord
  , runtimeMode
  )
import Infernix.Web.Workbench
  ( Publication
  , catalogCards
  , describeCompletedRequest
  , publicationSummary
  , selectedModel
  , selectionSummary
  )
import Simple.JSON as JSON
import Web.DOM.Document as Document
import Web.DOM.Element as Element
import Web.DOM.Node as Node
import Web.DOM.NonElementParentNode as NonElementParentNode
import Web.Event.Event as Event
import Web.Event.EventTarget as EventTarget
import Web.HTML (window)
import Web.HTML.Event.EventTypes as EventTypes
import Web.HTML.HTMLDocument as HTMLDocument
import Web.HTML.HTMLFormElement as HTMLFormElement
import Web.HTML.HTMLInputElement as HTMLInputElement
import Web.HTML.HTMLTextAreaElement as HTMLTextAreaElement
import Web.HTML.Window as Window

type AppState =
  { models :: Array ModelDescriptor
  , publication :: Maybe Publication
  , runtimeMode :: String
  , selectedModelId :: Maybe String
  }

type Refs =
  { document :: Document.Document
  , catalog :: Element.Element
  , catalogCount :: Element.Element
  , search :: HTMLInputElement.HTMLInputElement
  , inputText :: HTMLTextAreaElement.HTMLTextAreaElement
  , form :: HTMLFormElement.HTMLFormElement
  , inputLabel :: Element.Element
  , modelName :: Element.Element
  , modelEngine :: Element.Element
  , modelLane :: Element.Element
  , modelFamily :: Element.Element
  , modelArtifact :: Element.Element
  , modelNotes :: Element.Element
  , requestGuidance :: Element.Element
  , runtimeModeValue :: Element.Element
  , controlPlaneContext :: Element.Element
  , daemonLocation :: Element.Element
  , catalogSource :: Element.Element
  , edgePort :: Element.Element
  , apiUpstreamMode :: Element.Element
  , demoConfigPath :: Element.Element
  , routeList :: Element.Element
  , upstreamList :: Element.Element
  , selectionStatus :: Element.Element
  , requestStatus :: Element.Element
  , submitButton :: Element.Element
  , resultLabel :: Element.Element
  , resultOutput :: Element.Element
  , objectLinkContainer :: Element.Element
  }

main :: Effect Unit
main = do
  htmlDocument <- Window.document =<< window
  refs <- captureRefs htmlDocument
  stateRef <-
    Ref.new
      { models: []
      , publication: Nothing
      , runtimeMode
      , selectedModelId: Nothing
      }
  bindEvents stateRef refs
  renderAll stateRef refs
  launchAff_ do
    loadPublication stateRef refs
    loadCatalog stateRef refs

captureRefs :: HTMLDocument.HTMLDocument -> Effect Refs
captureRefs htmlDocument = do
  let document = HTMLDocument.toDocument htmlDocument
  catalog <- requireElement htmlDocument "catalog"
  catalogCount <- requireElement htmlDocument "catalog-count"
  search <- requireInput htmlDocument "search"
  inputText <- requireTextArea htmlDocument "inputText"
  form <- requireForm htmlDocument "inference-form"
  inputLabel <- requireElement htmlDocument "input-label"
  modelName <- requireElement htmlDocument "selected-model-name"
  modelEngine <- requireElement htmlDocument "selected-engine"
  modelLane <- requireElement htmlDocument "selected-lane"
  modelFamily <- requireElement htmlDocument "selected-family"
  modelArtifact <- requireElement htmlDocument "selected-artifact-type"
  modelNotes <- requireElement htmlDocument "selected-notes"
  requestGuidance <- requireElement htmlDocument "request-guidance"
  runtimeModeValue <- requireElement htmlDocument "runtime-mode"
  controlPlaneContext <- requireElement htmlDocument "control-plane-context"
  daemonLocation <- requireElement htmlDocument "daemon-location"
  catalogSource <- requireElement htmlDocument "catalog-source"
  edgePort <- requireElement htmlDocument "edge-port"
  apiUpstreamMode <- requireElement htmlDocument "api-upstream-mode"
  demoConfigPath <- requireElement htmlDocument "demo-config-path"
  routeList <- requireElement htmlDocument "route-list"
  upstreamList <- requireElement htmlDocument "upstream-list"
  selectionStatus <- requireElement htmlDocument "selection-status"
  requestStatus <- requireElement htmlDocument "request-status"
  submitButton <- requireElement htmlDocument "submit-button"
  resultLabel <- requireElement htmlDocument "result-label"
  resultOutput <- requireElement htmlDocument "result-output"
  objectLinkContainer <- requireElement htmlDocument "object-link-container"
  pure
    { document
    , catalog
    , catalogCount
    , search
    , inputText
    , form
    , inputLabel
    , modelName
    , modelEngine
    , modelLane
    , modelFamily
    , modelArtifact
    , modelNotes
    , requestGuidance
    , runtimeModeValue
    , controlPlaneContext
    , daemonLocation
    , catalogSource
    , edgePort
    , apiUpstreamMode
    , demoConfigPath
    , routeList
    , upstreamList
    , selectionStatus
    , requestStatus
    , submitButton
    , resultLabel
    , resultOutput
    , objectLinkContainer
    }

bindEvents :: Ref.Ref AppState -> Refs -> Effect Unit
bindEvents stateRef refs = do
  searchListener <-
    EventTarget.eventListener \_ ->
      renderCatalog stateRef refs
  EventTarget.addEventListener EventTypes.input searchListener false (HTMLInputElement.toEventTarget refs.search)

  submitListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      launchAff_ (submitInference stateRef refs)
  EventTarget.addEventListener EventTypes.submit submitListener false (HTMLFormElement.toEventTarget refs.form)

loadPublication :: Ref.Ref AppState -> Refs -> Aff Unit
loadPublication stateRef refs = do
  response <- AXWeb.get ResponseFormat.string (apiBasePath <> "/publication")
  case response of
    Left _ ->
      liftEffect do
        Ref.modify_ (\state -> state { publication = Nothing }) stateRef
        renderPublication stateRef refs
    Right httpResponse ->
      case JSON.readJSON httpResponse.body of
        Left _ ->
          liftEffect do
            Ref.modify_ (\state -> state { publication = Nothing }) stateRef
            renderPublication stateRef refs
        Right publicationValue ->
          liftEffect do
            Ref.modify_ (\state -> state { publication = Just publicationValue }) stateRef
            renderPublication stateRef refs

loadCatalog :: Ref.Ref AppState -> Refs -> Aff Unit
loadCatalog stateRef refs = do
  response <- AXWeb.get ResponseFormat.string (apiBasePath <> "/models")
  case response of
    Left requestError ->
      liftEffect do
        Ref.modify_ (\state -> state { models = [], selectedModelId = Nothing }) stateRef
        setStatus refs.selectionStatus "status error" (AXWeb.printError requestError)
        renderAll stateRef refs
    Right httpResponse ->
      if statusCode httpResponse.status >= 400 then
        liftEffect do
          Ref.modify_ (\state -> state { models = [], selectedModelId = Nothing }) stateRef
          setStatus refs.selectionStatus "status error" ("Catalog request failed with " <> show (statusCode httpResponse.status))
          renderAll stateRef refs
      else
        case JSON.readJSON httpResponse.body of
          Left decodeError ->
            liftEffect do
              Ref.modify_ (\state -> state { models = [], selectedModelId = Nothing }) stateRef
              setStatus refs.selectionStatus "status error" ("Unable to decode catalog payload: " <> show decodeError)
              renderAll stateRef refs
          Right modelsValue ->
            liftEffect do
              Ref.modify_ (updateCatalog modelsValue) stateRef
              state <- Ref.read stateRef
              setStatus refs.selectionStatus "status success" ("Model catalog loaded for " <> state.runtimeMode)
              renderAll stateRef refs

submitInference :: Ref.Ref AppState -> Refs -> Aff Unit
submitInference stateRef refs = do
  inputValue <- liftEffect (HTMLTextAreaElement.value refs.inputText)
  state <- liftEffect (Ref.read stateRef)
  case state.selectedModelId of
    Nothing ->
      liftEffect do
        setStatus refs.requestStatus "status error" "No model selected."
        setText refs.resultOutput "No result yet."
        clearChildren refs.objectLinkContainer
    Just selectedModelIdValue -> do
      liftEffect do
        setStatus refs.requestStatus "status muted" "Submitting request…"
        setText refs.objectLinkContainer ""
      response <-
        AXWeb.request
          ( AXWeb.defaultRequest
              { method = Left POST
              , url = apiBasePath <> "/inference"
              , headers = [ RequestHeader.ContentType applicationJSON ]
              , content =
                  Just
                    ( RequestBody.string
                        ( JSON.writeJSON
                            { requestModelId: selectedModelIdValue
                            , inputText: inputValue
                            }
                        )
                    )
              , responseFormat = ResponseFormat.string
              }
          )
      case response of
        Left requestError ->
          liftEffect do
            setStatus refs.requestStatus "status error" (AXWeb.printError requestError)
            setText refs.resultOutput "No result yet."
            clearChildren refs.objectLinkContainer
        Right httpResponse ->
          if statusCode httpResponse.status >= 400 then
            liftEffect do
              let errorMessage = decodeErrorMessage httpResponse.body
              setStatus refs.requestStatus "status error" errorMessage
              setText refs.resultOutput "No result yet."
              clearChildren refs.objectLinkContainer
          else
            case JSON.readJSON httpResponse.body of
              Left decodeError ->
                liftEffect do
                  setStatus refs.requestStatus "status error" ("Unable to decode inference result: " <> show decodeError)
                  setText refs.resultOutput "No result yet."
                  clearChildren refs.objectLinkContainer
              Right inferenceResult ->
                liftEffect do
                  let summary = describeCompletedRequest inferenceResult (selectedModel state.models state.selectedModelId)
                  setStatus refs.requestStatus "status success" summary.statusText
                  setText refs.resultLabel summary.resultLabel
                  setText refs.resultOutput summary.outputText
                  renderObjectLink refs summary.objectHref summary.objectLinkLabel

renderAll :: Ref.Ref AppState -> Refs -> Effect Unit
renderAll stateRef refs = do
  renderCatalog stateRef refs
  renderPublication stateRef refs

renderCatalog :: Ref.Ref AppState -> Refs -> Effect Unit
renderCatalog stateRef refs = do
  state <- Ref.read stateRef
  query <- HTMLInputElement.value refs.search
  let
    visibleModels = catalogCards state.models query state.selectedModelId
    noResultsMessage =
      if query == "" && state.models == [] then
        "Live catalog unavailable."
      else
        "No models match \"" <> query <> "\"."
  setText refs.catalogCount (show (length visibleModels) <> " visible / " <> show (length state.models) <> " total")
  setText refs.runtimeModeValue state.runtimeMode
  clearChildren refs.catalog
  if visibleModels == [] then
    appendMessage refs.document refs.catalog noResultsMessage
  else
    traverse_ (appendCatalogCard stateRef refs) visibleModels
  renderSelectionDetails state refs

renderSelectionDetails :: AppState -> Refs -> Effect Unit
renderSelectionDetails state refs = do
  let summary = selectionSummary (selectedModel state.models state.selectedModelId)
  setText refs.modelName summary.name
  setText refs.modelEngine summary.engine
  setText refs.modelLane summary.lane
  setText refs.modelFamily summary.familyLabel
  setText refs.modelArtifact summary.artifactType
  setText refs.modelNotes summary.notes
  setText refs.inputLabel summary.inputLabel
  HTMLTextAreaElement.setPlaceholder summary.placeholder refs.inputText
  setText refs.requestGuidance summary.requestGuidance
  setText refs.submitButton summary.submitLabel
  setText refs.resultLabel summary.resultLabel

renderPublication :: Ref.Ref AppState -> Refs -> Effect Unit
renderPublication stateRef refs = do
  state <- Ref.read stateRef
  let summary = publicationSummary state.publication state.runtimeMode
  setText refs.runtimeModeValue summary.runtimeMode
  setText refs.controlPlaneContext summary.controlPlaneContext
  setText refs.daemonLocation summary.daemonLocation
  setText refs.catalogSource summary.catalogSource
  setText refs.edgePort summary.edgePort
  setText refs.apiUpstreamMode summary.apiUpstreamMode
  setText refs.demoConfigPath summary.demoConfigPath
  renderList refs.document refs.routeList (\route -> route.path <> " -> " <> route.purpose) summary.routes
  renderList refs.document refs.upstreamList (\upstream -> upstream.id <> " -> " <> upstream.healthStatus <> " via " <> upstream.targetSurface <> " (" <> upstream.durableBackendState <> ")") summary.upstreams

appendCatalogCard :: Ref.Ref AppState -> Refs -> { modelId :: String, displayName :: String, description :: String, family :: String, artifactType :: String, selectedEngine :: String, isActive :: Boolean } -> Effect Unit
appendCatalogCard stateRef refs card = do
  button <- Document.createElement "button" refs.document
  Element.setAttribute "type" "button" button
  Element.setClassName
    (if card.isActive then "catalog-item active" else "catalog-item")
    button
  setText button (card.displayName <> " · " <> card.modelId <> " · " <> card.family <> " · " <> card.artifactType <> " · " <> card.selectedEngine <> " · " <> card.description)
  listener <-
    EventTarget.eventListener \_ -> do
      Ref.modify_ (\state -> state { selectedModelId = Just card.modelId }) stateRef
      setStatus refs.selectionStatus "status success" (card.displayName <> " selected on " <> card.selectedEngine)
      renderCatalog stateRef refs
  EventTarget.addEventListener EventTypes.click listener false (Element.toEventTarget button)
  Node.appendChild (Element.toNode button) (Element.toNode refs.catalog)

renderList :: forall a. Document.Document -> Element.Element -> (a -> String) -> Array a -> Effect Unit
renderList document container renderItem items = do
  clearChildren container
  traverse_ appendItem items
  where
  appendItem item = do
    listItem <- Document.createElement "li" document
    setText listItem (renderItem item)
    Node.appendChild (Element.toNode listItem) (Element.toNode container)

renderObjectLink :: Refs -> Maybe String -> Maybe String -> Effect Unit
renderObjectLink refs maybeHref maybeLabel = do
  clearChildren refs.objectLinkContainer
  case maybeHref of
    Nothing -> pure unit
    Just href -> do
      anchor <- Document.createElement "a" refs.document
      Element.setAttribute "href" href anchor
      setText anchor (fromMaybe "Open large output" maybeLabel)
      Node.appendChild (Element.toNode anchor) (Element.toNode refs.objectLinkContainer)

appendMessage :: Document.Document -> Element.Element -> String -> Effect Unit
appendMessage document container message = do
  paragraph <- Document.createElement "p" document
  Element.setClassName "muted" paragraph
  setText paragraph message
  Node.appendChild (Element.toNode paragraph) (Element.toNode container)

requireElement :: HTMLDocument.HTMLDocument -> String -> Effect Element.Element
requireElement htmlDocument elementId = do
  maybeElement <- NonElementParentNode.getElementById elementId (HTMLDocument.toNonElementParentNode htmlDocument)
  case maybeElement of
    Just elementValue -> pure elementValue
    Nothing -> throw ("Missing required element #" <> elementId)

requireInput :: HTMLDocument.HTMLDocument -> String -> Effect HTMLInputElement.HTMLInputElement
requireInput htmlDocument elementId = do
  elementValue <- requireElement htmlDocument elementId
  case HTMLInputElement.fromElement elementValue of
    Just inputValue -> pure inputValue
    Nothing -> throw ("Element #" <> elementId <> " is not an input element")

requireTextArea :: HTMLDocument.HTMLDocument -> String -> Effect HTMLTextAreaElement.HTMLTextAreaElement
requireTextArea htmlDocument elementId = do
  elementValue <- requireElement htmlDocument elementId
  case HTMLTextAreaElement.fromElement elementValue of
    Just textAreaValue -> pure textAreaValue
    Nothing -> throw ("Element #" <> elementId <> " is not a textarea element")

requireForm :: HTMLDocument.HTMLDocument -> String -> Effect HTMLFormElement.HTMLFormElement
requireForm htmlDocument elementId = do
  elementValue <- requireElement htmlDocument elementId
  case HTMLFormElement.fromElement elementValue of
    Just formValue -> pure formValue
    Nothing -> throw ("Element #" <> elementId <> " is not a form element")

setStatus :: Element.Element -> String -> String -> Effect Unit
setStatus elementValue classNameValue message =
  Element.setClassName classNameValue elementValue *> setText elementValue message

setText :: Element.Element -> String -> Effect Unit
setText elementValue message =
  Node.setTextContent message (Element.toNode elementValue)

clearChildren :: Element.Element -> Effect Unit
clearChildren elementValue =
  Node.setTextContent "" (Element.toNode elementValue)

decodeErrorMessage :: String -> String
decodeErrorMessage payload =
  case JSON.readJSON payload of
    Right (errorValue :: ErrorResponse) -> (errorResponseRecord errorValue).message
    Left _ -> "Request failed"

statusCode :: StatusCode -> Int
statusCode (StatusCode value) = value

updateCatalog :: Array ModelDescriptor -> AppState -> AppState
updateCatalog modelsValue state =
  let
    nextRuntimeMode = fromMaybe state.runtimeMode ((_.runtimeMode <<< modelDescriptorRecord) <$> head modelsValue)
    nextSelection =
      case state.selectedModelId of
        Just selectedId
          | hasModelId selectedId modelsValue -> Just selectedId
        _ -> (_.modelId <<< modelDescriptorRecord) <$> head modelsValue
  in
    state
      { models = modelsValue
      , runtimeMode = nextRuntimeMode
      , selectedModelId = nextSelection
      }

hasModelId :: String -> Array ModelDescriptor -> Boolean
hasModelId selectedId modelsValue =
  case selectedModel modelsValue (Just selectedId) of
    Just _ -> true
    Nothing -> false
