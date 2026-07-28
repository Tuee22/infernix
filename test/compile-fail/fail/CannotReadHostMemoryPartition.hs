module Main (main) where

import DesiredApi

forgedPartition :: HostMemoryPartition
forgedPartition =
  read
    "HostMemoryPartition { hostPartitionPhysicalMib = 1, hostPartitionVmReserveMib = 0, hostPartitionHeadroomMib = 0, hostPartitionInferenceCapacityMib = 1 }"

main :: IO ()
main = forgedPartition `seq` pure ()
