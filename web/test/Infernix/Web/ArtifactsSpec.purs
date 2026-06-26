-- | Phase 7 Sprint 7.13 — view-model tests for the durable-context
-- | Artifacts view. Patch application is mechanical, so this spec
-- | exercises exactly that surface plus the MIME-to-disposition
-- | classifier the view delegates to.
module Infernix.Web.ArtifactsSpec
  ( spec
  ) where

import Prelude

import Data.Array (length)
import Generated.Contracts
  ( ArtifactKind(..)
  , ArtifactRenderDisposition(..)
  , ArtifactUploadRequest(..)
  , ContextId(..)
  , ObjectRef(..)
  )
import Infernix.Web.Artifacts
  ( artifactEntryFromReady
  , artifactsForContext
  , buildUploadRequest
  , dispositionFor
  , initialArtifactsViewState
  , recordArtifactReady
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "ArtifactsView dispositionFor" do
    it "renders images inline" do
      dispositionFor "image/png" `shouldEqual` RenderInline
      dispositionFor "image/jpeg" `shouldEqual` RenderInline

    it "renders audio inline (HTML5 audio element)" do
      dispositionFor "audio/wav" `shouldEqual` RenderInline
      dispositionFor "audio/mpeg" `shouldEqual` RenderInline

    it "renders video inline (HTML5 video element)" do
      dispositionFor "video/mp4" `shouldEqual` RenderInline

    it "delegates PDFs to the browser-native viewer" do
      dispositionFor "application/pdf" `shouldEqual` BrowserNativePdf

    it "previews JSON and text within a bounded text view" do
      dispositionFor "application/json" `shouldEqual` BoundedTextPreview
      dispositionFor "text/plain" `shouldEqual` BoundedTextPreview

    it "renders MIDI, MusicXML, and ZIP archives in the browser" do
      dispositionFor "audio/midi" `shouldEqual` RenderMidi
      dispositionFor "audio/x-midi" `shouldEqual` RenderMidi
      dispositionFor "application/vnd.recordare.musicxml+xml" `shouldEqual` RenderMusicXml
      dispositionFor "application/vnd.recordare.musicxml" `shouldEqual` RenderMusicXml
      dispositionFor "application/zip" `shouldEqual` RenderZipStems

    it "downloads unknown MIME types by default" do
      dispositionFor "application/octet-stream" `shouldEqual` DownloadOnly
      dispositionFor "application/x-mystery" `shouldEqual` DownloadOnly

  describe "ArtifactsView library upsert" do
    it "appends a new artifact entry" do
      let cid = ContextId { unContextId: "c-1" }
      let ref = ObjectRef
            { objectBucket: "infernix-demo-objects"
            , objectKey: "users/u/contexts/c-1/generated/out.png"
            }
      let entry = artifactEntryFromReady cid ref ArtifactKindGenerated
      let state = recordArtifactReady entry initialArtifactsViewState
      length state.entries `shouldEqual` 1
      entry.mimeType `shouldEqual` "image/png"
      entry.disposition `shouldEqual` RenderInline

    it "replaces an existing entry that points at the same object" do
      let cid = ContextId { unContextId: "c-1" }
      let ref = ObjectRef
            { objectBucket: "infernix-demo-objects"
            , objectKey: "users/u/contexts/c-1/generated/out.png"
            }
      let entry1 = artifactEntryFromReady cid ref ArtifactKindGenerated
      let entry2 = artifactEntryFromReady cid ref ArtifactKindUpload
      let state =
            recordArtifactReady entry2
              (recordArtifactReady entry1 initialArtifactsViewState)
      length state.entries `shouldEqual` 1

    it "scopes artifactsForContext to the requested contextId" do
      let c1 = ContextId { unContextId: "c-1" }
      let c2 = ContextId { unContextId: "c-2" }
      let ref1 = ObjectRef
            { objectBucket: "infernix-demo-objects"
            , objectKey: "users/u/contexts/c-1/generated/a.png"
            }
      let ref2 = ObjectRef
            { objectBucket: "infernix-demo-objects"
            , objectKey: "users/u/contexts/c-2/generated/b.png"
            }
      let state =
            recordArtifactReady (artifactEntryFromReady c2 ref2 ArtifactKindGenerated)
              ( recordArtifactReady (artifactEntryFromReady c1 ref1 ArtifactKindGenerated)
                  initialArtifactsViewState
              )
      length (artifactsForContext c1 state) `shouldEqual` 1
      length (artifactsForContext c2 state) `shouldEqual` 1

  describe "ArtifactsView buildUploadRequest" do
    it "captures the typed contextId, MIME, and display name" do
      let cid = ContextId { unContextId: "c-1" }
      case buildUploadRequest cid "image/png" "out.png" of
        ArtifactUploadRequest record -> do
          record.artifactUploadRequestDisplayName `shouldEqual` "out.png"
