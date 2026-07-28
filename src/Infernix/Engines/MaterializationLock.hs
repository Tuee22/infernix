-- | Public shared-reader side of engine materialization locking.
--
-- The exclusive interpreter and its writer authority live in the Cabal-hidden
-- @Infernix.Engines.MaterializationLock.Internal@ module. Production writers
-- enter through the indexed provisioning session instead of receiving a raw
-- lock token.
module Infernix.Engines.MaterializationLock
  ( ArtifactGenerationLease,
    withTryArtifactGenerationReadLock,
    withTryEngineArtifactReadLock,
  )
where

import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationLease,
    withTryArtifactGenerationReadLock,
    withTryEngineArtifactReadLock,
  )
