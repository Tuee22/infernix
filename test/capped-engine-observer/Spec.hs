{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Main (main) where

import Control.Concurrent
  ( forkFinally,
    newEmptyMVar,
    putMVar,
    takeMVar,
    throwTo,
  )
import Control.Exception
  ( AsyncException (ThreadKilled),
    SomeException,
    displayException,
    fromException,
    try,
  )
import Control.Monad (forM_, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.DescriptorSpace (establishBoundedDescriptorSpace)
import Infernix.Runtime.CappedEngine.Cleanup
  ( runCappedEngineCleanup,
    withCappedEngineCleanupBoundary,
  )
import Infernix.Runtime.CappedEngine.FixedObserver
  ( FixedObserverKernelTest,
    NvidiaComputeApp (..),
    nvidiaComputeAppGroupBytes,
    parseFootprintPhysicalBytes,
    parseNvidiaComputeApps,
    parseNvidiaDeviceTotalMib,
    parseTopProcessGroupMembers,
    runFixedObserverFixtureModeIfRequested,
    runFixedObserverKernelTest,
  )
import Infernix.Runtime.CappedEngine.OutputCapture
  ( BoundedCapture (..),
    readBoundedCapture,
  )
import System.Exit (ExitCode (ExitSuccess), exitFailure)
import System.IO (hClose)
import System.Posix.IO (createPipe, fdToHandle)
import System.Posix.Types (CPid)

-- The startup probe runs the public Apple tools, so only the Apple branch of
-- 'observerProbeTest' below can call it.
#if defined(darwin_HOST_OS)
import Infernix.Runtime.CappedEngine.FixedObserver
  ( probePhysicalFootprintObserver,
  )
#endif

main :: IO ()
main = do
  -- Test images spawn self-exec children through the same close_fds
  -- kernels the production binary uses, so they bound their descriptor
  -- space first. See "Infernix.DescriptorSpace".
  _ <- establishBoundedDescriptorSpace
  handledFixture <- runFixedObserverFixtureModeIfRequested
  unless handledFixture $ do
    parserTests
    nvidiaParserTests
    boundedCaptureTests
    cleanupBoundaryTests
    forM_ allKernelTests $ \testCase -> do
      result <- runFixedObserverKernelTest testCase
      case result of
        Right () -> pure ()
        Left reason ->
          failTest
            ( show testCase
                <> " failed: "
                <> Text.unpack reason
            )
    observerProbeTest
    putStrLn "capped-engine fixed public-tool observer tests passed"

cleanupBoundaryTests :: IO ()
cleanupBoundaryTests = do
  closeCount <- newIORef (0 :: Int)
  reapCount <- newIORef (0 :: Int)
  cleanupResult <-
    try @SomeException
      ( runCappedEngineCleanup
          [ ioError (userError "injected kill failure"),
            atomicModifyIORef' closeCount (\count -> (count + 1, ()))
          ]
          ( atomicModifyIORef' reapCount (\count -> (count + 1, ()))
              >> pure ExitSuccess
          )
      )
  case cleanupResult of
    Left failure ->
      unless ("injected kill failure" `isInfixOf` displayException failure) $
        failTest "synchronous cleanup failure lost its primary diagnostic"
    Right () ->
      failTest "injected synchronous cleanup failure unexpectedly succeeded"
  assertEqual
    "later pipe cleanup still runs after an earlier cleanup failure"
    1
    =<< readIORef closeCount
  assertEqual
    "reap still runs after an earlier cleanup failure"
    1
    =<< readIORef reapCount

  combinedResult <-
    try @SomeException
      ( withCappedEngineCleanupBoundary
          (pure ())
          ( \() ->
              runCappedEngineCleanup
                []
                (ioError (userError "injected reap failure"))
          )
          (\() -> ioError (userError "injected primary failure"))
      )
  case combinedResult of
    Left failure ->
      unless
        ( "injected primary failure" `isInfixOf` displayException failure
            && "injected reap failure" `isInfixOf` displayException failure
        )
        (failTest "cleanup aggregation did not preserve primary and reap diagnostics")
    Right () ->
      failTest "combined primary and reap failure unexpectedly succeeded"

  actionEntered <- newEmptyMVar
  actionBlock <- newEmptyMVar
  asyncCleanupRan <- newEmptyMVar
  asyncResult <- newEmptyMVar
  actionThread <-
    forkFinally
      ( withCappedEngineCleanupBoundary
          (pure ())
          (\() -> putMVar asyncCleanupRan ())
          ( \() -> do
              putMVar actionEntered ()
              takeMVar actionBlock
          )
      )
      (putMVar asyncResult)
  takeMVar actionEntered
  throwTo actionThread ThreadKilled
  takeMVar asyncCleanupRan
  cancellationResult <- takeMVar asyncResult
  case cancellationResult of
    Left failure ->
      assertEqual
        "asynchronous primary remains asynchronously classified after cleanup"
        (Just ThreadKilled)
        (fromException failure :: Maybe AsyncException)
    Right () ->
      failTest "asynchronously cancelled cleanup region unexpectedly completed"

boundedCaptureTests :: IO ()
boundedCaptureTests = do
  completedPayload <- captureFixture 128 (ByteString8.pack "bounded output")
  assertEqual
    "bounded capture retains a complete strict payload"
    (BoundedCaptureCompleted (ByteString8.pack "bounded output"))
    completedPayload

  overflowCount <- newIORef (0 :: Int)
  let captureLimit = 128
      oversizedPayload = ByteString.replicate (captureLimit + 73) 65
  exceededPayload <-
    captureFixtureWithOverflow
      captureLimit
      (atomicModifyIORef' overflowCount (\count -> (count + 1, ())))
      oversizedPayload
  assertEqual
    "bounded capture retains only its fixed prefix"
    (BoundedCaptureExceeded (ByteString.take captureLimit oversizedPayload))
    exceededPayload
  assertEqual
    "bounded capture invokes the overflow terminator exactly once"
    1
    =<< readIORef overflowCount

  (readerFd, writerFd) <- createPipe
  readerHandle <- fdToHandle readerFd
  writerHandle <- fdToHandle writerFd
  captureEntered <- newEmptyMVar
  captureResult <- newEmptyMVar
  captureThread <-
    forkFinally
      ( do
          putMVar captureEntered ()
          readBoundedCapture 128 (pure ()) readerHandle
      )
      (putMVar captureResult)
  takeMVar captureEntered
  throwTo captureThread ThreadKilled
  cancelledResult <- takeMVar captureResult
  case cancelledResult of
    Left failure ->
      assertEqual
        "blocked bounded capture remains asynchronously cancellable"
        (Just ThreadKilled)
        (fromException failure :: Maybe AsyncException)
    Right _ ->
      failTest "blocked bounded capture unexpectedly survived cancellation"
  hClose readerHandle
  hClose writerHandle

captureFixture :: Int -> ByteString -> IO BoundedCapture
captureFixture maximumBytes =
  captureFixtureWithOverflow maximumBytes (pure ())

captureFixtureWithOverflow ::
  Int ->
  IO () ->
  ByteString ->
  IO BoundedCapture
captureFixtureWithOverflow maximumBytes onOverflow payload = do
  (readerFd, writerFd) <- createPipe
  readerHandle <- fdToHandle readerFd
  writerHandle <- fdToHandle writerFd
  writerResult <- newEmptyMVar
  _ <-
    forkFinally
      (ByteString.hPut writerHandle payload >> hClose writerHandle)
      (putMVar writerResult)
  result <- readBoundedCapture maximumBytes onOverflow readerHandle
  hClose readerHandle
  assertWriterCompleted =<< takeMVar writerResult
  pure result

assertWriterCompleted :: Either SomeException () -> IO ()
assertWriterCompleted result =
  case result of
    Right () -> pure ()
    Left failure ->
      failTest ("bounded capture fixture writer failed: " <> show failure)

observerProbeTest :: IO ()
#if defined(darwin_HOST_OS)
observerProbeTest = do
  observerProbe <- probePhysicalFootprintObserver
  case observerProbe of
    Left reason ->
      failTest
        ( "the fixed Apple physical-footprint observer startup probe failed: "
            <> Text.unpack reason
        )
    Right physicalBytes ->
      unless (physicalBytes > 0) $
        failTest "the fixed Apple physical-footprint observer reported zero bytes"
#else
observerProbeTest = pure ()
#endif

allKernelTests :: [FixedObserverKernelTest]
allKernelTests = [minBound .. maxBound]

parserTests :: IO ()
parserTests = do
  assertEqual
    "top parser returns every exact process-group member"
    (Right [pid 42, pid 43])
    ( parseTopProcessGroupMembers
        (pid 42)
        validTopOutput
    )
  assertLeft
    "top parser rejects a group without its exact leader"
    ( parseTopProcessGroupMembers
        (pid 42)
        "PID PGRP MEM\n43 42 8K\n"
    )
  assertLeft
    "top parser rejects duplicate process rows"
    ( parseTopProcessGroupMembers
        (pid 42)
        "PID PGRP MEM\n42 42 8K\n42 42 8K\n"
    )
  assertLeft
    "top parser rejects malformed memory columns"
    ( parseTopProcessGroupMembers
        (pid 42)
        "PID PGRP MEM\n42 42 unknown\n"
    )
  assertLeft
    "top parser rejects kernel PID zero in the requested group"
    ( parseTopProcessGroupMembers
        (pid 42)
        "PID PGRP MEM\n42 42 8K\n0 42 128M\n"
    )
  assertLeft
    "top parser rejects repeated headers"
    ( parseTopProcessGroupMembers
        (pid 42)
        "PID PGRP MEM\n42 42 8K\nPID PGRP MEM\n"
    )
  assertEqual
    "footprint parser returns exact phys_footprint bytes"
    (Right 1704296)
    (parseFootprintPhysicalBytes validFootprintOutput)
  assertLeft
    "footprint parser rejects peak-only output"
    (parseFootprintPhysicalBytes "phys_footprint_peak: 1704296 B\n")
  assertLeft
    "footprint parser rejects duplicate physical-footprint fields"
    ( parseFootprintPhysicalBytes
        "phys_footprint: 1 B\nphys_footprint: 2 B\n"
    )
  assertLeft
    "footprint parser rejects zero physical footprint"
    (parseFootprintPhysicalBytes "phys_footprint: 0 B\n")
  assertLeft
    "footprint parser rejects Word64 overflow"
    ( parseFootprintPhysicalBytes
        "phys_footprint: 18446744073709551616 B\n"
    )
  assertLeft
    "footprint parser rejects non-byte units"
    (parseFootprintPhysicalBytes "phys_footprint: 10 K\n")

-- | Phase 6 Sprint 6.44 — the fixed NVIDIA observer's parsers. The valid
-- payloads are the exact shapes @nvidia-smi ... --format=csv,noheader,nounits@
-- produced on the supported CUDA host, including the space after each comma.
nvidiaParserTests :: IO ()
nvidiaParserTests = do
  assertEqual
    "compute-app parser returns every pid and its MiB"
    (Right [NvidiaComputeApp (pid 473) 1008, NvidiaComputeApp (pid 512) 64])
    (parseNvidiaComputeApps "473, 1008\n512, 64\n")
  assertEqual
    "compute-app parser treats an empty payload as no compute application"
    (Right [])
    (parseNvidiaComputeApps "")
  assertEqual
    "compute-app parser ignores trailing blank lines"
    (Right [NvidiaComputeApp (pid 473) 1008])
    (parseNvidiaComputeApps "473, 1008\n\n")
  assertLeft
    "compute-app parser rejects a row that is not a pid,mib pair"
    (parseNvidiaComputeApps "473\n")
  assertLeft
    "compute-app parser rejects a non-decimal memory quantity"
    (parseNvidiaComputeApps "473, [N/A]\n")
  assertLeft
    "compute-app parser rejects a non-decimal pid"
    (parseNvidiaComputeApps "not-a-pid, 1008\n")
  assertLeft
    "compute-app parser rejects pid zero"
    (parseNvidiaComputeApps "0, 1008\n")
  assertLeft
    "compute-app parser rejects a repeated pid"
    (parseNvidiaComputeApps "473, 1008\n473, 64\n")

  assertEqual
    "device-memory parser returns the exact total MiB"
    (Right 32607)
    (parseNvidiaDeviceTotalMib "32607\n")
  assertLeft
    "device-memory parser rejects an absent device"
    (parseNvidiaDeviceTotalMib "")
  assertLeft
    "device-memory parser rejects a zero total"
    (parseNvidiaDeviceTotalMib "0\n")
  assertLeft
    "device-memory parser rejects a multi-device host"
    (parseNvidiaDeviceTotalMib "32607\n32607\n")
  assertLeft
    "device-memory parser rejects a non-decimal total"
    (parseNvidiaDeviceTotalMib "[N/A]\n")

  assertEqual
    "group attribution sums only the members' device memory"
    (Right (1008 * 1024 * 1024))
    ( nvidiaComputeAppGroupBytes
        [pid 473]
        [NvidiaComputeApp (pid 473) 1008, NvidiaComputeApp (pid 900) 4096]
    )
  assertEqual
    "group attribution of a member with no compute context is zero, not a loss"
    (Right 0)
    (nvidiaComputeAppGroupBytes [pid 473] [])
  assertLeft
    "group attribution rejects a MiB quantity that overflows its byte conversion"
    ( nvidiaComputeAppGroupBytes
        [pid 473]
        [NvidiaComputeApp (pid 473) maxBound]
    )

validTopOutput :: ByteString
validTopOutput =
  ByteString8.unlines
    [ "Processes: 4 total, 1 running, 3 sleeping",
      "Load Avg: 1.00, 1.00, 1.00",
      "PID PGRP MEM",
      "44 44 1M",
      "43 42 8K",
      "42 42 12M",
      "0 0 128M"
    ]

validFootprintOutput :: ByteString
validFootprintOutput =
  ByteString8.unlines
    [ "======================================================================",
      "fixture [42]: 64-bit    Footprint: 1687912 B (16384 bytes per page)",
      "======================================================================",
      "",
      "Auxiliary data:",
      "    phys_footprint: 1704296 B",
      "    phys_footprint_peak: 1704296 B"
    ]

pid :: Integer -> CPid
pid = fromIntegral

assertEqual ::
  (Eq value, Show value) =>
  String ->
  value ->
  value ->
  IO ()
assertEqual label expected actual =
  unless (actual == expected) $
    failTest
      ( label
          <> ": expected "
          <> show expected
          <> ", got "
          <> show actual
      )

assertLeft :: String -> Either Text value -> IO ()
assertLeft label result =
  case result of
    Left _ -> pure ()
    Right _ -> failTest (label <> ": expected rejection")

failTest :: String -> IO value
failTest message = do
  putStrLn ("FAIL: " <> message)
  exitFailure
