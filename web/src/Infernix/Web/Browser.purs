module Infernix.Web.Browser
  ( currentOrigin
  , bindDashboardRefresh
  , clearStoredActiveContext
  , installForceWebSocketClose
  , newUuid
  , readStoredActiveContext
  , scheduleEffect
  , writeStoredActiveContext
  ) where

import Effect (Effect)
import Prelude (Unit)

foreign import currentOrigin :: Effect String

-- | Bind the application dashboard refresh action to browser focus and
-- | visibility restoration. The action itself owns state and transport.
foreign import bindDashboardRefresh :: Effect Unit -> Effect Unit

foreign import readStoredActiveContext :: Effect String

foreign import writeStoredActiveContext :: String -> String -> Effect Unit

foreign import clearStoredActiveContext :: Effect Unit

foreign import installForceWebSocketClose :: Effect Unit -> Effect Unit

foreign import newUuid :: Effect String

foreign import scheduleEffect :: Int -> Effect Unit -> Effect Unit
