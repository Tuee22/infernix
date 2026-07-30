-- | Public shared-reader side of engine materialization locking.
--
-- The exclusive interpreter and its writer authority live in the Cabal-hidden
-- @Infernix.Engines.MaterializationLock.Internal@ module. Production writers
-- enter through the indexed provisioning session instead of receiving a raw
-- lock token.
-- The validated lease description plus its pure accessor are public: a lease
-- value names a generation, it does not carry authority over one. Authority
-- still comes only from acquiring a lock around it.
module Infernix.Engines.MaterializationLock
  ( ArtifactGenerationLease,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    withTryArtifactGenerationReadLock,
    withTryEngineArtifactReadLock,
  )
where

import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationLease,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    withTryArtifactGenerationReadLock,
    withTryEngineArtifactReadLock,
  )
