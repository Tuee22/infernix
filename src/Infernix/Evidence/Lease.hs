-- | Opaque region-indexed evidence. Acquisition and payload access belong to
-- the package-private domain implementation. A phantom region alone does not
-- contain ordinary IO; public protected operations own their effect runner.
module Infernix.Evidence.Lease (Lease) where

import Infernix.Evidence.Lease.Internal (Lease)
