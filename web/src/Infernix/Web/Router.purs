-- | Phase 7 Sprint 7.10 — minimal SPA route table.
-- |
-- | The supported routes today are @/@ (Chat) and @/artifacts@
-- | (Artifacts library); both render under the durable-context shell.
-- | The router is intentionally non-reactive — switching routes is a
-- | full re-render rather than a router-managed component swap — so
-- | the SPA stays small and the back/forward stack honours the page
-- | reload contract from
-- | [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md).
module Infernix.Web.Router
  ( Route(..)
  , parseRoute
  , routePath
  ) where

import Prelude

data Route
  = RouteChat
  | RouteArtifacts
  | RouteFiles

derive instance eqRoute :: Eq Route

instance showRoute :: Show Route where
  show RouteChat = "RouteChat"
  show RouteArtifacts = "RouteArtifacts"
  show RouteFiles = "RouteFiles"

parseRoute :: String -> Route
parseRoute path = case path of
  "/artifacts" -> RouteArtifacts
  "/files" -> RouteFiles
  _ -> RouteChat

routePath :: Route -> String
routePath = case _ of
  RouteChat -> "/"
  RouteArtifacts -> "/artifacts"
  RouteFiles -> "/files"
