-- | Authenticated transport for the application-owned administrator overview.
-- | The personal dashboard reuses the Files view's scoped object listing; this
-- | module owns only the separately authorized cluster-wide overview request.
module Infernix.Web.DashboardTransport
  ( refreshAdminOverview
  ) where

import Effect (Effect)
import Prelude (Unit)

foreign import refreshAdminOverviewImpl
  :: (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

refreshAdminOverview
  :: (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
refreshAdminOverview = refreshAdminOverviewImpl
