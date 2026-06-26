-- | Phase 7 Sprint 7.26 — transport for the per-user Files view.
-- |
-- | All object HTTP is webapp-mediated (see
-- | [../documents/architecture/object_access_doctrine.md]). This module wraps
-- | the authenticated @GET /api/objects/list@ refresh and the
-- | @DELETE /api/objects@ action; download and preview reuse
-- | 'Infernix.Web.ArtifactTransport' bound to the same files root.
module Infernix.Web.FilesTransport
  ( refreshFilesList
  , bindFilesActions
  ) where

import Prelude

import Effect (Effect)
import Web.DOM.Element as Element

foreign import refreshFilesListImpl
  :: (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | @GET /api/objects/list@ with the operator bearer token. Calls the first
-- | continuation with the JSON array body, or the second with an error
-- | message.
refreshFilesList
  :: (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
refreshFilesList = refreshFilesListImpl

foreign import bindFilesActionsImpl
  :: Element.Element
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Bind a delegated click listener for @[data-role='file-delete']@ on the
-- | files root. On click it issues @DELETE /api/objects?key=…@ with the bearer
-- | token and calls the first continuation with the deleted object key, or the
-- | second with an error message.
bindFilesActions
  :: Element.Element
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
bindFilesActions = bindFilesActionsImpl
