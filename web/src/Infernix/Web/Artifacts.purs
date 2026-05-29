-- | Phase 7 Sprint 7.11 — durable-context Artifacts view.
-- |
-- | Per-context artifact list plus per-user library. Uploads use a
-- | presigned PUT minted by @POST /api/objects/upload@; downloads use a
-- | presigned GET minted by @POST /api/objects/download@. Inline
-- | rendering goes through @\<img\>@ / @\<audio\>@ / @\<video\>@; PDFs
-- | get browser-native handling; text/JSON gets a bounded preview;
-- | MIDI, MusicXML, MXL notation, unknown, and generic binary all fall
-- | back to download-only.
-- |
-- | This module exposes the typed view-state container, the
-- | MIME-to-disposition classifier, the artifact-library upsert helper
-- | invoked when a 'ServerArtifactReady' frame arrives, the DOM
-- | renderer, and the typed 'ArtifactUploadRequest' builder the
-- | multipart upload helper hands to @/api/objects/upload@. The actual
-- | @XMLHttpRequest@ / @fetch@-based upload lands together with Sprint
-- | 7.15 Playwright E2E.
module Infernix.Web.Artifacts
  ( ArtifactEntry
  , ArtifactsViewState
  , ArtifactsRenderOptions
  , initialArtifactsViewState
  , dispositionFor
  , artifactEntryFromReady
  , recordArtifactReady
  , buildUploadRequest
  , artifactsForContext
  , handleArtifactsServerMessage
  , renderArtifactsView
  ) where

import Prelude

import Data.Array (filter, last, snoc)
import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String (Pattern(..), split, stripPrefix, stripSuffix)
import Effect (Effect)
import Generated.Contracts
  ( ArtifactKind(..)
  , ArtifactMimeType(..)
  , ArtifactRenderDisposition(..)
  , ArtifactUploadRequest(..)
  , ContextId(..)
  , ObjectRef(..)
  , WsServerMessage(..)
  )
import Web.DOM.Document as Document
import Web.DOM.Element as Element
import Web.DOM.Node as Node

type ArtifactEntry =
  { contextId :: ContextId
  , objectRef :: ObjectRef
  , kind :: ArtifactKind
  , mimeType :: String
  , disposition :: ArtifactRenderDisposition
  }

type ArtifactsViewState =
  { entries :: Array ArtifactEntry
  }

type ArtifactsRenderOptions =
  { activeContextId :: Maybe ContextId
  }

initialArtifactsViewState :: ArtifactsViewState
initialArtifactsViewState =
  { entries: [] }

-- | Mechanical mapping from a MIME type to the render disposition the
-- | Artifacts view should use. The Haskell @/api/objects/download@
-- | response already carries a typed disposition; this helper is the
-- | client-side fallback for artifacts surfaced through WS
-- | 'ServerArtifactReady' where only the MIME type is known.
dispositionFor :: String -> ArtifactRenderDisposition
dispositionFor mimeType
  | mimeType == "audio/midi" = DownloadOnly
  | mimeType == "audio/x-midi" = DownloadOnly
  | hasPrefix "image/" mimeType = RenderInline
  | hasPrefix "audio/" mimeType = RenderInline
  | hasPrefix "video/" mimeType = RenderInline
  | mimeType == "application/pdf" = BrowserNativePdf
  | mimeType == "application/json" = BoundedTextPreview
  | hasPrefix "text/" mimeType = BoundedTextPreview
  | otherwise = DownloadOnly

hasPrefix :: String -> String -> Boolean
hasPrefix prefix value = isJust (stripPrefix (Pattern prefix) value)

-- | Promote a 'ServerArtifactReady' frame into the local 'ArtifactEntry'
-- | the view-state list holds. MIME-typing is by convention extracted
-- | from the object key suffix; the supported flow is to derive the
-- | richer @ArtifactDownloadGrant.artifactDownloadGrantMimeType@ on
-- | the @/api/objects/download@ leg, but the WS notification is the
-- | first signal the SPA gets so we synthesise a best-effort MIME from
-- | the key for the initial render.
artifactEntryFromReady
  :: ContextId
  -> ObjectRef
  -> ArtifactKind
  -> ArtifactEntry
artifactEntryFromReady contextId ref kind =
  let mimeType = mimeFromObjectKey (objectKeyValue ref)
  in
    { contextId: contextId
    , objectRef: ref
    , kind: kind
    , mimeType: mimeType
    , disposition: dispositionFor mimeType
    }

-- | Append a new artifact entry to the per-user library, replacing any
-- | existing entry that points at the same bucket+key pair.
recordArtifactReady
  :: ArtifactEntry
  -> ArtifactsViewState
  -> ArtifactsViewState
recordArtifactReady entry state =
  let existing = filter (not <<< sameRef entry) state.entries
  in state { entries = snoc existing entry }

sameRef :: ArtifactEntry -> ArtifactEntry -> Boolean
sameRef a b =
  objectKeyValue a.objectRef == objectKeyValue b.objectRef
    && objectBucketValue a.objectRef == objectBucketValue b.objectRef

objectKeyValue :: ObjectRef -> String
objectKeyValue (ObjectRef record) = record.objectKey

objectBucketValue :: ObjectRef -> String
objectBucketValue (ObjectRef record) = record.objectBucket

-- | Surface artifacts for one specific context; the per-user library
-- | view ignores 'contextId' and renders the full list.
artifactsForContext :: ContextId -> ArtifactsViewState -> Array ArtifactEntry
artifactsForContext (ContextId contextIdRecord) state =
  filter
    ( \entry ->
        let ContextId other = entry.contextId
        in other.unContextId == contextIdRecord.unContextId
    )
    state.entries

-- | Build a typed @ArtifactUploadRequest@ from the SPA-side form. The
-- | supported flow is to @POST /api/objects/upload@ with this body, then
-- | use the returned @presignedUrl@ for the actual @PUT@ to MinIO.
buildUploadRequest
  :: ContextId
  -> String
  -> String
  -> ArtifactUploadRequest
buildUploadRequest contextId mimeType displayName =
  ArtifactUploadRequest
    { artifactUploadRequestContextId: contextId
    , artifactUploadRequestMimeType: ArtifactMimeType { unArtifactMimeType: mimeType }
    , artifactUploadRequestDisplayName: displayName
    }

-- | Pattern-match the WS frame variants this view cares about. The Chat
-- | view handler delegates to this helper when it sees a
-- | 'ServerArtifactReady'; other frames are no-ops for the Artifacts
-- | view-state.
handleArtifactsServerMessage
  :: WsServerMessage
  -> ArtifactsViewState
  -> ArtifactsViewState
handleArtifactsServerMessage message state =
  case message of
    ServerArtifactReady record ->
      let entry =
            artifactEntryFromReady
              record.serverArtifactReadyContextId
              record.serverArtifactReadyObjectRef
              record.serverArtifactReadyKind
      in recordArtifactReady entry state
    _ -> state

-- | Heuristic MIME-from-key. The supported authoritative source is
-- | @ArtifactDownloadGrant.artifactDownloadGrantMimeType@; this helper
-- | only gives the WS-driven initial render something to work with
-- | before the download grant arrives.
mimeFromObjectKey :: String -> String
mimeFromObjectKey key =
  if endsWith ".png" key then "image/png"
  else if endsWith ".jpg" key || endsWith ".jpeg" key then "image/jpeg"
  else if endsWith ".gif" key then "image/gif"
  else if endsWith ".webp" key then "image/webp"
  else if endsWith ".wav" key then "audio/wav"
  else if endsWith ".mp3" key then "audio/mpeg"
  else if endsWith ".ogg" key then "audio/ogg"
  else if endsWith ".mp4" key then "video/mp4"
  else if endsWith ".webm" key then "video/webm"
  else if endsWith ".pdf" key then "application/pdf"
  else if endsWith ".json" key then "application/json"
  else if endsWith ".txt" key || endsWith ".md" key then "text/plain"
  else if endsWith ".mid" key || endsWith ".midi" key then "audio/midi"
  else if endsWith ".xml" key || endsWith ".musicxml" key then "application/vnd.recordare.musicxml+xml"
  else if endsWith ".mxl" key then "application/vnd.recordare.musicxml"
  else "application/octet-stream"

endsWith :: String -> String -> Boolean
endsWith suffix value = isJust (stripSuffix (Pattern suffix) value)

-- | Render the Artifacts surface into an existing container. Download
-- | grants and direct MinIO PUT wiring are handled by the shell; this
-- | function emits stable data attributes for those handlers and draws
-- | the inline/download disposition the view state already knows.
renderArtifactsView
  :: Document.Document
  -> Element.Element
  -> ArtifactsRenderOptions
  -> ArtifactsViewState
  -> Effect Unit
renderArtifactsView document container options state = do
  clearChildren container
  shell <- createElement document "section" "artifacts-view"
  upload <- renderUploadPanel document options
  scoped <- renderArtifactList document "Context artifacts" (scopedEntries options state)
  library <- renderArtifactList document "Artifact library" state.entries
  appendElement shell upload
  appendElement shell scoped
  appendElement shell library
  appendElement container shell

renderUploadPanel :: Document.Document -> ArtifactsRenderOptions -> Effect Element.Element
renderUploadPanel document options = do
  panel <- createElement document "form" "artifact-upload-panel"
  Element.setAttribute "data-role" "artifact-upload" panel
  case options.activeContextId of
    Just contextId ->
      Element.setAttribute "data-context-id" (contextIdRawValue contextId) panel
    Nothing ->
      Element.setAttribute "aria-disabled" "true" panel
  title <- textElement document "h2" "artifacts-section-title" "Upload"
  fileInput <- createElement document "input" "artifact-file-input"
  Element.setAttribute "type" "file" fileInput
  Element.setAttribute "name" "artifact-file" fileInput
  mimeInput <- createElement document "input" "artifact-mime-input"
  Element.setAttribute "name" "artifact-mime" mimeInput
  Element.setAttribute "placeholder" "MIME type" mimeInput
  displayInput <- createElement document "input" "artifact-display-name-input"
  Element.setAttribute "name" "artifact-display-name" displayInput
  Element.setAttribute "placeholder" "Display name" displayInput
  progress <- createElement document "progress" "artifact-upload-progress"
  Element.setAttribute "max" "100" progress
  Element.setAttribute "value" "0" progress
  status <- textElement document "p" "artifact-upload-status" ""
  submit <- textElement document "button" "artifact-upload-button" "Upload"
  Element.setAttribute "type" "submit" submit
  appendElement panel title
  appendElement panel fileInput
  appendElement panel mimeInput
  appendElement panel displayInput
  appendElement panel progress
  appendElement panel status
  appendElement panel submit
  pure panel

renderArtifactList
  :: Document.Document
  -> String
  -> Array ArtifactEntry
  -> Effect Element.Element
renderArtifactList document title entries = do
  section <- createElement document "section" "artifact-list-section"
  header <- textElement document "h2" "artifacts-section-title" title
  list <- createElement document "div" "artifact-list"
  appendElement section header
  if entries == [] then do
    empty <- textElement document "p" "artifact-empty-state" "No artifacts."
    appendElement list empty
  else
    traverse_ (appendArtifactEntry document list) entries
  appendElement section list
  pure section

appendArtifactEntry :: Document.Document -> Element.Element -> ArtifactEntry -> Effect Unit
appendArtifactEntry document list entry = do
  card <- createElement document "article" ("artifact-entry " <> dispositionClass entry.disposition)
  Element.setAttribute "data-object-bucket" (objectBucketValue entry.objectRef) card
  Element.setAttribute "data-object-key" (objectKeyValue entry.objectRef) card
  Element.setAttribute "data-context-id" (contextIdRawValue entry.contextId) card
  Element.setAttribute "data-mime-type" entry.mimeType card
  Element.setAttribute "data-display-name" (objectDisplayName entry.objectRef) card
  Element.setAttribute "data-render-disposition" (dispositionTag entry.disposition) card
  title <- textElement document "h3" "artifact-title" (kindLabel entry.kind <> " - " <> objectKeyValue entry.objectRef)
  metadata <- textElement document "p" "artifact-metadata" (entry.mimeType <> " - " <> dispositionLabel entry.disposition)
  preview <- renderArtifactPreview document entry
  actions <- renderArtifactActions document entry
  appendElement card title
  appendElement card metadata
  appendElement card preview
  appendElement card actions
  appendElement list card

renderArtifactPreview :: Document.Document -> ArtifactEntry -> Effect Element.Element
renderArtifactPreview document entry =
  case entry.disposition of
    RenderInline
      | hasPrefix "image/" entry.mimeType ->
          mediaElement document "img" "artifact-preview-image" entry
      | hasPrefix "audio/" entry.mimeType ->
          mediaElement document "audio" "artifact-preview-audio" entry
      | hasPrefix "video/" entry.mimeType ->
          mediaElement document "video" "artifact-preview-video" entry
      | otherwise ->
          textElement document "p" "artifact-preview-placeholder" "Inline preview waits for a download grant."
    BrowserNativePdf ->
      mediaElement document "iframe" "artifact-preview-pdf" entry
    BoundedTextPreview ->
      textElement document "pre" "artifact-preview-text" "Preview waits for a download grant."
    DownloadOnly ->
      textElement document "p" "artifact-preview-download-only" "Download-only artifact."

mediaElement :: Document.Document -> String -> String -> ArtifactEntry -> Effect Element.Element
mediaElement document tagName classNameValue entry = do
  elementValue <- createElement document tagName classNameValue
  Element.setAttribute "data-object-bucket" (objectBucketValue entry.objectRef) elementValue
  Element.setAttribute "data-object-key" (objectKeyValue entry.objectRef) elementValue
  when (tagName == "audio" || tagName == "video") do
    Element.setAttribute "controls" "controls" elementValue
  when (tagName == "img") do
    Element.setAttribute "alt" (objectKeyValue entry.objectRef) elementValue
  pure elementValue

renderArtifactActions :: Document.Document -> ArtifactEntry -> Effect Element.Element
renderArtifactActions document entry = do
  actions <- createElement document "div" "artifact-actions"
  download <- textElement document "button" "artifact-download-button" "Download"
  Element.setAttribute "type" "button" download
  Element.setAttribute "data-role" "artifact-download" download
  Element.setAttribute "data-object-bucket" (objectBucketValue entry.objectRef) download
  Element.setAttribute "data-object-key" (objectKeyValue entry.objectRef) download
  Element.setAttribute "data-context-id" (contextIdRawValue entry.contextId) download
  Element.setAttribute "data-mime-type" entry.mimeType download
  Element.setAttribute "data-display-name" (objectDisplayName entry.objectRef) download
  appendElement actions download
  pure actions

scopedEntries :: ArtifactsRenderOptions -> ArtifactsViewState -> Array ArtifactEntry
scopedEntries options state =
  case options.activeContextId of
    Just contextId -> artifactsForContext contextId state
    Nothing -> []

kindLabel :: ArtifactKind -> String
kindLabel kind =
  case kind of
    ArtifactKindUpload -> "Upload"
    ArtifactKindGenerated -> "Generated"

dispositionLabel :: ArtifactRenderDisposition -> String
dispositionLabel disposition =
  case disposition of
    RenderInline -> "inline"
    DownloadOnly -> "download"
    BoundedTextPreview -> "text preview"
    BrowserNativePdf -> "PDF"

dispositionClass :: ArtifactRenderDisposition -> String
dispositionClass disposition =
  case disposition of
    RenderInline -> "inline"
    DownloadOnly -> "download-only"
    BoundedTextPreview -> "text-preview"
    BrowserNativePdf -> "pdf"

dispositionTag :: ArtifactRenderDisposition -> String
dispositionTag disposition =
  case disposition of
    RenderInline -> "RenderInline"
    DownloadOnly -> "DownloadOnly"
    BoundedTextPreview -> "BoundedTextPreview"
    BrowserNativePdf -> "BrowserNativePdf"

contextIdRawValue :: ContextId -> String
contextIdRawValue (ContextId inner) = inner.unContextId

objectDisplayName :: ObjectRef -> String
objectDisplayName objectRef =
  let key = objectKeyValue objectRef
  in fromMaybe key (last (split (Pattern "/") key))

createElement :: Document.Document -> String -> String -> Effect Element.Element
createElement document tagName classNameValue = do
  elementValue <- Document.createElement tagName document
  Element.setClassName classNameValue elementValue
  pure elementValue

textElement :: Document.Document -> String -> String -> String -> Effect Element.Element
textElement document tagName classNameValue textValue = do
  elementValue <- createElement document tagName classNameValue
  setText elementValue textValue
  pure elementValue

appendElement :: Element.Element -> Element.Element -> Effect Unit
appendElement parent child =
  void (Node.appendChild (Element.toNode child) (Element.toNode parent))

setText :: Element.Element -> String -> Effect Unit
setText elementValue textValue =
  Node.setTextContent textValue (Element.toNode elementValue)

clearChildren :: Element.Element -> Effect Unit
clearChildren elementValue =
  Node.setTextContent "" (Element.toNode elementValue)
