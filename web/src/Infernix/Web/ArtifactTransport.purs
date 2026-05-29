module Infernix.Web.ArtifactTransport
  ( UploadedArtifact
  , bindArtifactTransport
  ) where

import Prelude

import Effect (Effect)
import Web.DOM.Element as Element

type UploadedArtifact =
  { contextId :: String
  , objectBucket :: String
  , objectKey :: String
  , mimeType :: String
  , displayName :: String
  }

bindArtifactTransport
  :: Element.Element
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
bindArtifactTransport = bindArtifactTransportImpl

foreign import bindArtifactTransportImpl
  :: Element.Element
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
