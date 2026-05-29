module Infernix.Web.DomEvents
  ( bindChatChrome
  ) where

import Prelude

import Effect (Effect)
import Web.DOM.Element as Element

bindChatChrome
  :: Element.Element
  -> Effect Unit
  -> Effect Unit
  -> Effect Unit
  -> (String -> String -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> String -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
bindChatChrome = bindChatChromeImpl

foreign import bindChatChromeImpl
  :: Element.Element
  -> Effect Unit
  -> Effect Unit
  -> Effect Unit
  -> (String -> String -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> String -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
