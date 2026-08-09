{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.BuildMemory
  ( AddressSpaceEnforcement (..),
    BuildMemoryBound,
    enforcedAddressCeilingMib,
  )

-- Sprint 6.49: a bound established on a lane that installs no address-space
-- ceiling must not be usable where an enforced ceiling is required. Darwin
-- aliases RLIMIT_AS to the advisory RLIMIT_RSS and rejects every finite ceiling
-- written against it, so there is no such number to return there; only the
-- promoted 'AddressSpaceEnforcement' index can reject this.
claimUnenforcedAddressSpace :: BuildMemoryBound 'AddressSpaceUnavailable -> Int
claimUnenforcedAddressSpace = enforcedAddressCeilingMib

main :: IO ()
main = pure ()
