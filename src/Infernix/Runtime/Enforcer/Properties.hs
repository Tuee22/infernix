module Infernix.Runtime.Enforcer.Properties
  ( runFiniteCgroupLimitParserProperties,
    runCgroupAvailabilityProperties,
  )
where

import Control.Exception (try)
import Control.Monad (forM_, void)
import Data.ByteString.Char8 qualified as ByteString
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf)
import Data.Word (Word64)
import Infernix.Runtime.Enforcer.Internal
  ( CgroupObservationFailure (..),
    CgroupObservationOperand (..),
    combineHostCgroupAvailabilityMib,
    parseFiniteMib,
    readCgroupMemoryAvailableMibWith,
    renderCgroupObservationFailure,
    withCgroupMemoryHeadroom,
  )
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Error (mkIOError, permissionErrorType)

runFiniteCgroupLimitParserProperties :: IO ()
runFiniteCgroupLimitParserProperties = do
  let expectedMib = 1024
      expectedBytes = toInteger expectedMib * bytesPerMib
      overflowingBytes = (toInteger (maxBound :: Int) + 1) * bytesPerMib
  assertEqual
    "an exact positive MiB limit is accepted"
    (Just expectedMib)
    (parseFiniteMib (" \t" <> show expectedBytes <> "\r\n"))
  mapM_
    ( \(label, rawLimit) ->
        assertEqual label Nothing (parseFiniteMib rawLimit)
    )
    [ ("one byte below the exact limit is rejected", show (expectedBytes - 1)),
      ("one byte above the exact limit is rejected", show (expectedBytes + 1)),
      ("the cgroup unlimited sentinel is rejected", "max"),
      ("malformed cgroup content is rejected", "1024MiB"),
      ("a zero-byte limit is rejected", "0"),
      ("a negative limit is rejected", "-1048576"),
      ("a MiB value above the Int domain is rejected", show overflowingBytes)
    ]
  putStrLn "finite cgroup-limit parser properties passed"

bytesPerMib :: Integer
bytesPerMib = 1048576

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  if actual == expected
    then pure ()
    else
      fail
        (label <> ": expected " <> show expected <> ", got " <> show actual)

-- | Exercise the same strict reader and decoder as production using independent
-- filesystem operands. The permission failure is injected at the read boundary
-- because the supported outer test process can run as root.
runCgroupAvailabilityProperties :: FilePath -> IO ()
runCgroupAvailabilityProperties root = do
  forM_
    [ ("occupied", "1073741824", Just "268435456", Just 768),
      ("round-after-subtraction", "1073741824", Just "1", Just 1023),
      ("nonintegral-maximum", "1073741825", Just "1", Just 1024),
      ("exhausted", "1073741824", Just "1073741824", Just 0),
      ("sub-mib-headroom", "1048576", Just "1048575", Just 0),
      ("zero-envelope", "0", Just "0", Just 0),
      ("whitespace", " 1073741824\n", Just " 268435456\t\n", Just 768),
      ("unlimited", "max\n", Nothing, Nothing)
    ]
    ( \(name, maximumValue, usageValue, expected) -> do
        (membershipPath, hierarchyRoot, _) <- createCgroupFixture root name (Just "0::/leaf\n") (Just maximumValue) usageValue
        actual <- readCgroupMemoryAvailableMibWith ByteString.readFile membershipPath hierarchyRoot
        assertEqual ("cgroup availability " <> name) (Right expected) actual
    )
  let overflow = show (toInteger (maxBound :: Word64) + 1)
  forM_
    [ ("missing-usage", Nothing, isReadFailure CgroupUsage),
      ("empty-usage", Just "", isInvalid CgroupUsage),
      ("malformed-usage", Just "23MiB", isInvalid CgroupUsage),
      ("negative-usage", Just "-1", isInvalid CgroupUsage),
      ("overflowing-usage", Just overflow, isInvalid CgroupUsage),
      ("hexadecimal-usage", Just "0x100", isInvalid CgroupUsage),
      ("contradictory-usage", Just "1073741825", isContradictory)
    ]
    ( \(name, usageValue, expectedFailure) -> do
        (membershipPath, hierarchyRoot, _) <- createCgroupFixture root name (Just "0::/leaf\n") (Just "1073741824") usageValue
        actual <- readCgroupMemoryAvailableMibWith ByteString.readFile membershipPath hierarchyRoot
        assertRefusal name expectedFailure actual
        assertNamedOperand name "memory.current" actual
    )
  forM_
    [ ("missing-maximum", Nothing),
      ("empty-maximum", Just ""),
      ("malformed-maximum", Just "broken"),
      ("negative-maximum", Just "-1"),
      ("overflowing-maximum", Just overflow),
      ("invalid-unlimited-sentinel", Just "MAX")
    ]
    ( \(name, maximumValue) -> do
        (membershipPath, hierarchyRoot, _) <- createCgroupFixture root name (Just "0::/leaf\n") maximumValue (Just "0")
        actual <- readCgroupMemoryAvailableMibWith ByteString.readFile membershipPath hierarchyRoot
        assertRefusal name (maximumFailure maximumValue) actual
        assertNamedOperand name "memory.max" actual
    )
  forM_
    [ ("missing-membership", Nothing),
      ("absent-unified-membership", Just "2:cpu:/leaf\n"),
      ("relative-membership", Just "0::leaf\n"),
      ("traversal-membership", Just "0::/leaf/../outside\n"),
      ("duplicate-membership", Just "0::/leaf\n0::/leaf\n")
    ]
    ( \(name, membership) -> do
        (membershipPath, hierarchyRoot, _) <- createCgroupFixture root name membership (Just "1073741824") (Just "0")
        actual <- readCgroupMemoryAvailableMibWith ByteString.readFile membershipPath hierarchyRoot
        assertRefusal name (membershipFailure membership) actual
    )
  (deniedMembership, deniedHierarchy, deniedUsage) <- createCgroupFixture root "denied-usage" (Just "0::/leaf\n") (Just "1073741824") (Just "0")
  let deniedReader path
        | path == deniedUsage = ioError (mkIOError permissionErrorType "cgroup usage control" Nothing (Just path))
        | otherwise = ByteString.readFile path
  denied <- readCgroupMemoryAvailableMibWith deniedReader deniedMembership deniedHierarchy
  assertRefusal "denied usage" (isReadFailure CgroupUsage) denied
  assertNamedOperand "denied usage" "memory.current" denied
  (directoryMembership, directoryHierarchy, directoryUsage) <- createCgroupFixture root "usage-directory" (Just "0::/leaf\n") (Just "1073741824") Nothing
  createDirectoryIfMissing True directoryUsage
  directoryResult <- readCgroupMemoryAvailableMibWith ByteString.readFile directoryMembership directoryHierarchy
  assertRefusal "usage read failure remains inside the strict read handler" (isReadFailure CgroupUsage) directoryResult
  (unlimitedMembership, unlimitedHierarchy, _) <- createCgroupFixture root "unlimited-read-inventory" (Just "0::/leaf\n") (Just "max") Nothing
  readsRef <- newIORef []
  let countedReader path = modifyIORef' readsRef (<> [path]) >> ByteString.readFile path
  unlimited <- readCgroupMemoryAvailableMibWith countedReader unlimitedMembership unlimitedHierarchy
  observedReads <- readIORef readsRef
  assertEqual "observed unlimited envelope" (Right Nothing) unlimited
  assertEqual "only finite envelopes require current usage" [unlimitedMembership, unlimitedHierarchy </> "leaf" </> "memory.max"] observedReads
  assertEqual "host availability narrows cgroup headroom" (Right 64) (combineHostCgroupAvailabilityMib 64 (Right (Just 768)))
  assertEqual "cgroup headroom narrows host availability" (Right 32) (combineHostCgroupAvailabilityMib 64 (Right (Just 32)))
  assertEqual "unlimited cgroup preserves observed host availability" (Right 64) (combineHostCgroupAvailabilityMib 64 (Right Nothing))
  assertEqual "exhausted cgroup admits no available memory" (Right 0) (combineHostCgroupAvailabilityMib 64 (Right (Just 0)))
  assertEqual "a cgroup read refusal survives host combination" denied (Just <$> combineHostCgroupAvailabilityMib 64 denied)
  forM_
    [ ("unobservable engine headroom", denied, void denied),
      ("insufficient engine headroom", Right (Just 31), Left (CgroupInsufficientHeadroom 32 31)),
      ("exhausted engine headroom", Right (Just 0), Left (CgroupInsufficientHeadroom 32 0)),
      ("exactly funded engine headroom", Right (Just 32), Right ()),
      ("unlimited engine envelope", Right Nothing, Right ())
    ]
    ( \(label, observation, expectedTerminal) -> do
        entered <- newIORef False
        terminal <- try (withCgroupMemoryHeadroom 32 (pure observation) (writeIORef entered True)) :: IO (Either CgroupObservationFailure ())
        actualEntry <- readIORef entered
        assertEqual (label <> " controls entry into the engine authority action") (expectedTerminal == Right ()) actualEntry
        assertEqual label expectedTerminal terminal
    )
  putStrLn "cgroup availability: strict filesystem, denied-read, malformed, overflow, contradiction, rounding, unlimited, and host-intersection controls passed"

createCgroupFixture :: FilePath -> String -> Maybe String -> Maybe String -> Maybe String -> IO (FilePath, FilePath, FilePath)
createCgroupFixture root name membership maximumValue usageValue = do
  let fixtureRoot = root </> name
      membershipPath = fixtureRoot </> "proc-cgroup"
      hierarchyRoot = fixtureRoot </> "hierarchy"
      leaf = hierarchyRoot </> "leaf"
      usagePath = leaf </> "memory.current"
  createDirectoryIfMissing True leaf
  writeOptional membershipPath membership
  writeOptional (leaf </> "memory.max") maximumValue
  writeOptional usagePath usageValue
  pure (membershipPath, hierarchyRoot, usagePath)
  where
    writeOptional path = maybe (pure ()) (ByteString.writeFile path . ByteString.pack)

isReadFailure :: CgroupObservationOperand -> CgroupObservationFailure -> Bool
isReadFailure expected (CgroupReadFailure actual _ _) = expected == actual
isReadFailure _ _ = False

isInvalid :: CgroupObservationOperand -> CgroupObservationFailure -> Bool
isInvalid expected (CgroupInvalidObservation actual _ _) = expected == actual
isInvalid _ _ = False

isContradictory :: CgroupObservationFailure -> Bool
isContradictory CgroupUsageExceedsMaximum {} = True
isContradictory _ = False

maximumFailure :: Maybe String -> CgroupObservationFailure -> Bool
maximumFailure Nothing = isReadFailure CgroupMaximum
maximumFailure (Just _) = isInvalid CgroupMaximum

membershipFailure :: Maybe String -> CgroupObservationFailure -> Bool
membershipFailure Nothing = isReadFailure CgroupMembership
membershipFailure (Just _) = isInvalid CgroupMembership

assertRefusal :: (Show a) => String -> (CgroupObservationFailure -> Bool) -> Either CgroupObservationFailure a -> IO ()
assertRefusal label expected result =
  case result of
    Left failure | expected failure -> pure ()
    _ -> fail (label <> ": expected the named observation refusal, got " <> show result)

assertNamedOperand :: (Show a) => String -> String -> Either CgroupObservationFailure a -> IO ()
assertNamedOperand label operand result =
  case result of
    Left failure | operand `isInfixOf` renderCgroupObservationFailure failure -> pure ()
    _ -> fail (label <> ": refusal must name " <> operand <> ", got " <> show result)
