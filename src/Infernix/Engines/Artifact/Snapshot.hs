-- | Allocation-bounded helpers for descriptor-backed artifact snapshots.
-- Constructors and descriptor operations remain in the Artifact kernel.
module Infernix.Engines.Artifact.Snapshot
  ( collectBoundedDirectoryEntries,
  )
where

import Data.List qualified as List

collectBoundedDirectoryEntries ::
  Int ->
  IO FilePath ->
  IO [FilePath]
collectBoundedDirectoryEntries remainingEntryBudget readNext
  | remainingEntryBudget < 0 =
      ioError (userError "engine artifact directory entry budget is negative")
  | otherwise =
      List.sort <$> readEntries remainingEntryBudget []
  where
    readEntries remaining entries = do
      entryName <- readNext
      if null entryName
        then pure entries
        else
          if entryName `elem` [".", ".."]
            then readEntries remaining entries
            else
              if remaining == 0
                then
                  ioError
                    ( userError
                        "engine artifact snapshot exceeds its remaining entry budget"
                    )
                else readEntries (remaining - 1) (entryName : entries)
