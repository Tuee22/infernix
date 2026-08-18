{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 8 Sprint 8.11 — the generated wire's enum-like unions that more than
-- one contract spells.
--
-- The system contract and the machine contract both name a daemon role, and a
-- role union spelled independently in two renderers is a drift generator of
-- exactly the kind Sprint 8.10 retired from the wire: two copies of one fact
-- that nothing forces to agree. Both renderers select from the values here, so
-- the alternative set, its rendered union type, and its decoder move together.
module Infernix.DhallSchema.Enums
  ( dhallEnumInterpretOptions,
    dhallEnumUnionType,
    dhallEnumValue,
    DhallDaemonRole (..),
    daemonRoleFromDhall,
    daemonRoleToDhall,
    daemonRoleAlternative,
    daemonRoleUnionType,
    renderDaemonRole,
  )
where

import Data.List (intercalate)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import GHC.Generics (Generic)
import Infernix.Types (DaemonRole (..))

-- | Interpret options for a Dhall union mirrored by a Haskell sum type.
--
-- Each mirror carries a type-specific Haskell constructor prefix, because
-- several of them name an alternative a domain type also names and Haskell has
-- one constructor namespace per module. The prefix is stripped here, so the
-- /wire/ alternative is exactly the suffix.
dhallEnumInterpretOptions :: Text -> Dhall.InterpretOptions
dhallEnumInterpretOptions constructorPrefix =
  Dhall.defaultInterpretOptions
    { Dhall.constructorModifier =
        \constructorName ->
          fromMaybe constructorName (Text.stripPrefix constructorPrefix constructorName)
    }

-- | The rendered spelling of an enum-only union. Both the value renderer and
-- every record-type annotation that contains the field select from one of these
-- values, so an annotation cannot drift from the value it annotates.
dhallEnumUnionType :: [String] -> String
dhallEnumUnionType alternatives =
  "< " <> intercalate " | " alternatives <> " >"

dhallEnumValue :: String -> String -> String
dhallEnumValue unionType alternative = unionType <> "." <> alternative

data DhallDaemonRole
  = DhallDaemonRoleCoordinator
  | DhallDaemonRoleEngine
  | DhallDaemonRoleWebapp
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DhallDaemonRole where
  autoWith _ = Dhall.genericAutoWith (dhallEnumInterpretOptions "DhallDaemonRole")

daemonRoleFromDhall :: DhallDaemonRole -> DaemonRole
daemonRoleFromDhall rawRole = case rawRole of
  DhallDaemonRoleCoordinator -> Coordinator
  DhallDaemonRoleEngine -> Engine
  DhallDaemonRoleWebapp -> Webapp

daemonRoleToDhall :: DaemonRole -> DhallDaemonRole
daemonRoleToDhall role = case role of
  Coordinator -> DhallDaemonRoleCoordinator
  Engine -> DhallDaemonRoleEngine
  Webapp -> DhallDaemonRoleWebapp

daemonRoleAlternative :: DaemonRole -> String
daemonRoleAlternative role = case role of
  Coordinator -> "Coordinator"
  Engine -> "Engine"
  Webapp -> "Webapp"

daemonRoleUnionType :: String
daemonRoleUnionType =
  dhallEnumUnionType (map daemonRoleAlternative [Coordinator, Engine, Webapp])

renderDaemonRole :: DaemonRole -> String
renderDaemonRole = dhallEnumValue daemonRoleUnionType . daemonRoleAlternative
