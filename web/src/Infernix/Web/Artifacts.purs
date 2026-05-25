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
-- | invoked when a 'ServerArtifactReady' frame arrives, and the typed
-- | 'ArtifactUploadRequest' builder the multipart upload helper hands
-- | to @/api/objects/upload@. The DOM-level renderer and the actual
-- | @XMLHttpRequest@ / @fetch@-based upload land together with Sprint
-- | 7.15 Playwright E2E.
module Infernix.Web.Artifacts
  ( ArtifactEntry
  , ArtifactsViewState
  , initialArtifactsViewState
  , dispositionFor
  , artifactEntryFromReady
  , recordArtifactReady
  , buildUploadRequest
  , artifactsForContext
  , handleArtifactsServerMessage
  ) where

import Prelude

import Data.Array (filter, snoc)
import Data.String (Pattern(..), stripPrefix, stripSuffix)
import Data.Maybe (isJust)
import Generated.Contracts
  ( ArtifactKind
  , ArtifactMimeType(..)
  , ArtifactRenderDisposition(..)
  , ArtifactUploadRequest(..)
  , ContextId(..)
  , ObjectRef(..)
  , WsServerMessage(..)
  )

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
