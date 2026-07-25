module Infernix.ExecutionPlan.Internal
  ( RawRuntimeConfig (..),
  )
where

import Infernix.Types (DemoConfig)

-- | The untrusted result of decoding generated configuration.  The constructor
-- lives in this non-exposed module so production consumers cannot manufacture
-- or inspect raw configuration; 'Infernix.Substrate' is the decoding boundary
-- and 'Infernix.ExecutionPlan.compileRuntimePlan' is the validation boundary.
newtype RawRuntimeConfig = RawRuntimeConfig DemoConfig
