-- | Phase 4 Sprint 4.34: memory admission happens inside 'refineRuntimePlan',
-- and the only way in is a 'RuntimeObservation' filled from live enforcement
-- probes. Its constructor stays package internal, so a routing-only role cannot
-- manufacture an empty observation set and take an admission verdict on the
-- executing machine's behalf.
module Main (main) where

import Infernix.ExecutionPlan (RuntimeObservation (RuntimeObservation))

main :: IO ()
main = pure ()
