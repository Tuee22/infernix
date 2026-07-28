{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

-- | The type-state and control-channel boundary for one bounded-command
-- supervision session.
--
-- The parent-side writer and wire requests live only in this module. Once a
-- raw handle is enclosed by 'AnchorControl', orchestration code can configure
-- a session, close it, or advance its opaque linear state; it cannot name a
-- request or write an early or repeated target-start gate.
module Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    AnchorControl,
    SupervisorCustodyEvidence,
    PinCustodyEvidence,
    SupervisorReadyEvidence,
    Session,
    SessionProgram,
    encloseAnchorControl,
    closeAnchorControl,
    readAnchorConfiguration,
    readAnchorPinCustodyAck,
    readAnchorSupervisorCustodyAck,
    readAnchorStartGate,
    observePinCustodyEvidence,
    observeSupervisorCustodyEvidence,
    observeSupervisorReadyEvidence,
    withCommandSession,
    awaitSupervisorReady,
    publishLease,
    startTarget,
    finishTarget,
    abandonSession,
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import Infernix.Cluster.Subprocess.Activity qualified as Activity
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity,
    readProcessBirthIdentity,
  )
import Numeric (readHex, showHex)
import System.IO (Handle, hClose, hFlush)
import System.Posix.Process (getProcessGroupIDOf)
import System.Timeout (timeout)

-- | Protocol milestones that must be crossed before a target may execute.
data CommandPhase
  = AnchorReady
  | SupervisorReady
  | LeaseDurable
  | TargetRunning

-- | The opaque parent-to-anchor control channel.
newtype AnchorControl = AnchorControl Handle

-- | Exact live-observation evidence for the supervisor and empty target-group
-- pin leader. The constructor is hidden.
data SupervisorReadyEvidence = SupervisorReadyEvidence

-- | Exact evidence that a provisional supervisor remains contained in the
-- anchor's process group. The constructor is hidden.
data SupervisorCustodyEvidence = SupervisorCustodyEvidence

-- | Exact evidence that both provisional helpers remain contained in the
-- anchor process group. The constructor is hidden.
data PinCustodyEvidence = PinCustodyEvidence

-- | Opaque authority for advancing one command session.
--
-- The region parameter is nominal and introduced only by
-- 'withCommandSession'. The phase parameter is also nominal so neither can be
-- changed with representational coercions.
data Session s (phase :: CommandPhase) = Session

type role Session nominal nominal

-- | An opaque, fully ordered session program. Its phase index is the phase at
-- which interpretation begins. Keeping transitions in this pure program
-- prevents a linear token from being returned through unrestricted 'IO'.
data SessionProgram s (phase :: CommandPhase) result where
  AwaitSupervisorReadyProgram ::
    IO SupervisorCustodyEvidence ->
    IO PinCustodyEvidence ->
    IO SupervisorReadyEvidence ->
    (Session s 'SupervisorReady %1 -> SessionProgram s 'SupervisorReady result) ->
    SessionProgram s 'AnchorReady result
  PublishLeaseProgram ::
    IO Activity.ActivityPublication ->
    (Session s 'LeaseDurable %1 -> SessionProgram s 'LeaseDurable result) ->
    SessionProgram s 'SupervisorReady result
  StartTargetProgram ::
    (Session s 'TargetRunning %1 -> SessionProgram s 'TargetRunning result) ->
    SessionProgram s 'LeaseDurable result
  FinishTargetProgram ::
    IO result ->
    SessionProgram s 'TargetRunning result
  AbandonSessionProgram ::
    IO result ->
    SessionProgram s phase result

type role SessionProgram nominal nominal representational

-- | Enclose the sole parent-side anchor writer.
encloseAnchorControl :: Handle -> AnchorControl
encloseAnchorControl = AnchorControl

-- | Close the control channel without exposing its handle.
closeAnchorControl :: AnchorControl -> IO ()
closeAnchorControl (AnchorControl handle) =
  hClose handle

-- | Decode the anchor's mandatory first request. A gate before configuration
-- fails closed inside this module.
readAnchorConfiguration ::
  (Aeson.FromJSON configuration) =>
  Handle ->
  IO configuration
readAnchorConfiguration handle = do
  request <- readAnchorRequest handle
  case request of
    ConfigureAnchor configuration ->
      case Aeson.fromJSON configuration of
        Aeson.Error failure ->
          ioError
            ( userError
                ("invalid bounded-command anchor configuration: " <> failure)
            )
        Aeson.Success parsed -> pure parsed
    OpenTargetGate ->
      ioError
        (userError "bounded-command anchor received gate authority before configuration")
    AcknowledgeSupervisorCustody ->
      ioError
        (userError "bounded-command anchor received custody authority before configuration")
    AcknowledgePinCustody ->
      ioError
        (userError "bounded-command anchor received pin custody before configuration")

-- | Consume the one custody acknowledgement that must precede supervisor
-- detachment from the anchor group.
readAnchorSupervisorCustodyAck :: Handle -> IO ()
readAnchorSupervisorCustodyAck handle = do
  request <- readAnchorRequest handle
  case request of
    AcknowledgeSupervisorCustody -> pure ()
    ConfigureAnchor _ ->
      ioError
        (userError "bounded-command anchor received duplicate configuration")
    OpenTargetGate ->
      ioError
        (userError "bounded-command anchor received target gate before supervisor custody")
    AcknowledgePinCustody ->
      ioError
        (userError "bounded-command anchor received pin custody before supervisor custody")

-- | Consume the one pin-custody acknowledgement that must precede either
-- provisional helper detaching from the anchor group.
readAnchorPinCustodyAck :: Handle -> IO ()
readAnchorPinCustodyAck handle = do
  request <- readAnchorRequest handle
  case request of
    AcknowledgePinCustody -> pure ()
    ConfigureAnchor _ ->
      ioError
        (userError "bounded-command anchor received duplicate configuration")
    AcknowledgeSupervisorCustody ->
      ioError
        (userError "bounded-command anchor received duplicate supervisor custody")
    OpenTargetGate ->
      ioError
        (userError "bounded-command anchor received target gate before pin custody")

-- | Consume the one permitted post-configuration gate request. A duplicate
-- configuration fails closed.
readAnchorStartGate :: Handle -> IO ()
readAnchorStartGate handle = do
  request <- readAnchorRequest handle
  case request of
    ConfigureAnchor _ ->
      ioError
        (userError "bounded-command anchor received duplicate configuration")
    OpenTargetGate -> pure ()
    AcknowledgeSupervisorCustody ->
      ioError
        (userError "bounded-command anchor received duplicate supervisor custody")
    AcknowledgePinCustody ->
      ioError
        (userError "bounded-command anchor received duplicate pin custody")

-- | Re-observe a provisional supervisor while it is still contained in the
-- exact anchor process group.
observeSupervisorCustodyEvidence ::
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO SupervisorCustodyEvidence
observeSupervisorCustodyEvidence
  anchorProcessId
  anchorProcessGroup
  anchorBirthIdentity
  supervisorProcessId
  supervisorProcessGroup
  supervisorBirthIdentity = do
    validateLeader
      "anchor"
      anchorProcessId
      anchorProcessGroup
      anchorBirthIdentity
    unless
      ( supervisorProcessId /= anchorProcessId
          && supervisorProcessGroup == anchorProcessGroup
      )
      (ioError (userError "bounded-command provisional supervisor is outside anchor custody"))
    validateExactProcess
      "provisional supervisor"
      supervisorProcessId
      supervisorProcessGroup
      supervisorBirthIdentity
    pure SupervisorCustodyEvidence

-- | Re-observe a provisional pin while it remains contained with the
-- provisional supervisor in the exact anchor process group.
observePinCustodyEvidence ::
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO PinCustodyEvidence
observePinCustodyEvidence
  anchorProcessId
  anchorProcessGroup
  anchorBirthIdentity
  supervisorProcessId
  supervisorProcessGroup
  supervisorBirthIdentity
  pinProcessId
  pinProcessGroup
  pinBirthIdentity = do
    validateLeader
      "anchor"
      anchorProcessId
      anchorProcessGroup
      anchorBirthIdentity
    unless
      ( supervisorProcessId /= anchorProcessId
          && supervisorProcessGroup == anchorProcessGroup
      )
      (ioError (userError "bounded-command provisional supervisor escaped anchor custody"))
    validateExactProcess
      "provisional supervisor"
      supervisorProcessId
      supervisorProcessGroup
      supervisorBirthIdentity
    unless
      ( pinProcessId /= anchorProcessId
          && pinProcessId /= supervisorProcessId
          && pinProcessGroup == anchorProcessGroup
      )
      (ioError (userError "bounded-command provisional pin is outside anchor custody"))
    validateExactProcess
      "provisional pin"
      pinProcessId
      pinProcessGroup
      pinBirthIdentity
    pure PinCustodyEvidence

-- | Re-observe the supervisor and target-group pin identities reported by the
-- isolated helper before minting supervisor-ready evidence. The target is not
-- forked until after the later durable start authority is spent.
observeSupervisorReadyEvidence ::
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO SupervisorReadyEvidence
observeSupervisorReadyEvidence
  supervisorProcessId
  supervisorProcessGroup
  supervisorBirthIdentity
  targetGroupLeaderProcessId
  targetProcessGroup
  targetGroupLeaderBirthIdentity = do
    validateLeader
      "supervisor"
      supervisorProcessId
      supervisorProcessGroup
      supervisorBirthIdentity
    validateLeader
      "target-group leader"
      targetGroupLeaderProcessId
      targetProcessGroup
      targetGroupLeaderBirthIdentity
    pure SupervisorReadyEvidence

-- | Configure the anchor and introduce a fresh command-session region.
--
-- The configuration write and the fixed gate write are both interpreted in
-- this module. Callers never receive a request constructor or writer.
withCommandSession ::
  (Aeson.ToJSON configuration) =>
  Word64 ->
  AnchorControl ->
  configuration ->
  (forall s. Session s 'AnchorReady %1 -> SessionProgram s 'AnchorReady result) ->
  IO result
withCommandSession deadline control configuration body = do
  writeAnchorRequestBefore
    deadline
    control
    (ConfigureAnchor (Aeson.toJSON configuration))
  runSessionProgram deadline control (body Session)

-- | Wait until the isolated anchor has created the supervisor and reported
-- its exact birth identity.
awaitSupervisorReady ::
  IO SupervisorCustodyEvidence ->
  IO PinCustodyEvidence ->
  IO SupervisorReadyEvidence ->
  Session s 'AnchorReady %1 ->
  (Session s 'SupervisorReady %1 -> SessionProgram s 'SupervisorReady result) ->
  SessionProgram s 'AnchorReady result
awaitSupervisorReady observeSupervisorCustody observePinCustody transition Session =
  AwaitSupervisorReadyProgram
    observeSupervisorCustody
    observePinCustody
    transition

-- | Durably publish the exact anchor and supervisor identities.
publishLease ::
  IO Activity.ActivityPublication ->
  Session s 'SupervisorReady %1 ->
  (Session s 'LeaseDurable %1 -> SessionProgram s 'LeaseDurable result) ->
  SessionProgram s 'SupervisorReady result
publishLease transition Session =
  PublishLeaseProgram transition

-- | Spend the durable-lease authority. Interpreting this transition emits the
-- fixed target-start gate through the enclosed control channel.
startTarget ::
  Session s 'LeaseDurable %1 ->
  (Session s 'TargetRunning %1 -> SessionProgram s 'TargetRunning result) ->
  SessionProgram s 'LeaseDurable result
startTarget Session =
  StartTargetProgram

-- | Consume a running session while awaiting its terminal kernel outcome.
finishTarget ::
  IO result ->
  Session s 'TargetRunning %1 ->
  SessionProgram s 'TargetRunning result
finishTarget transition Session =
  FinishTargetProgram transition

-- | Consume a session at any phase while executing the kernel's mandatory
-- cleanup path.
abandonSession ::
  IO result ->
  Session s phase %1 ->
  SessionProgram s phase result
abandonSession cleanup Session =
  AbandonSessionProgram cleanup

runSessionProgram ::
  Word64 ->
  AnchorControl ->
  SessionProgram s phase result ->
  IO result
runSessionProgram deadline control program =
  case program of
    AwaitSupervisorReadyProgram
      observeSupervisorCustody
      observePinCustody
      transition
      next -> do
        _supervisorCustodyEvidence <- observeSupervisorCustody
        writeAnchorRequestBefore
          deadline
          control
          AcknowledgeSupervisorCustody
        _pinCustodyEvidence <- observePinCustody
        writeAnchorRequestBefore
          deadline
          control
          AcknowledgePinCustody
        _readyEvidence <- transition
        runSessionProgram deadline control (next Session)
    PublishLeaseProgram planPublication next -> do
      publication <-
        runActionBeforeDeadline deadline planPublication
      _durableEvidence <-
        runActionBeforeDeadline
          deadline
          (Activity.publishActivityPublication publication)
      runSessionProgram deadline control (next Session)
    StartTargetProgram next -> do
      writeAnchorRequestBefore deadline control OpenTargetGate
      runSessionProgram deadline control (next Session)
    FinishTargetProgram transition ->
      transition
    AbandonSessionProgram cleanup ->
      cleanup

data AnchorRequest
  = ConfigureAnchor !Aeson.Value
  | AcknowledgeSupervisorCustody
  | AcknowledgePinCustody
  | OpenTargetGate

instance Aeson.ToJSON AnchorRequest where
  toJSON request =
    case request of
      ConfigureAnchor configuration ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("configure" :: String),
            "plan" Aeson..= configuration
          ]
      OpenTargetGate ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("open-target-gate" :: String)
          ]
      AcknowledgeSupervisorCustody ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("acknowledge-supervisor-custody" :: String)
          ]
      AcknowledgePinCustody ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("acknowledge-pin-custody" :: String)
          ]

instance Aeson.FromJSON AnchorRequest where
  parseJSON =
    Aeson.withObject "AnchorRequest" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (2 :: Int)) $
        fail "unsupported bounded-command anchor-request version"
      request <- value Aeson..: "request"
      case request :: String of
        "configure" -> ConfigureAnchor <$> value Aeson..: "plan"
        "acknowledge-supervisor-custody" -> pure AcknowledgeSupervisorCustody
        "acknowledge-pin-custody" -> pure AcknowledgePinCustody
        "open-target-gate" -> pure OpenTargetGate
        _ -> fail "unknown bounded-command anchor request"

maximumAnchorFrameBytes :: Int
maximumAnchorFrameBytes = 67108864

readAnchorRequest ::
  Handle ->
  IO AnchorRequest
readAnchorRequest handle = do
  encoded <- readFrameHandle handle
  either
    ( \failure ->
        ioError
          ( userError
              ("invalid bounded-command anchor request frame: " <> failure)
          )
    )
    pure
    (Aeson.eitherDecodeStrict' encoded)

writeAnchorRequestBefore ::
  Word64 ->
  AnchorControl ->
  AnchorRequest ->
  IO ()
writeAnchorRequestBefore deadline (AnchorControl handle) request =
  runActionBeforeDeadline
    deadline
    (writeFrameHandle handle (LazyByteString.toStrict (Aeson.encode request)))

writeFrameHandle ::
  Handle ->
  ByteString.ByteString ->
  IO ()
writeFrameHandle handle payload
  | ByteString.length payload > maximumAnchorFrameBytes =
      ioError (userError "bounded-command protocol frame exceeds its size limit")
  | otherwise = do
      let rawLength = showHex (ByteString.length payload) ""
          header =
            ByteString8.pack
              (replicate (8 - length rawLength) '0' <> rawLength <> "\n")
      ByteString.hPut handle header
      ByteString.hPut handle payload
      hFlush handle

readFrameHandle :: Handle -> IO ByteString.ByteString
readFrameHandle handle = do
  header <- readHandleExactly handle 9
  let (hexLength, newline) = ByteString8.splitAt 8 header
      parsedLength =
        case readHex (ByteString8.unpack hexLength) of
          [(value, "")] -> Just value
          _ -> Nothing
  frameLength <-
    case (parsedLength, newline) of
      (Just value, suffix)
        | suffix == ByteString8.pack "\n",
          value >= 0,
          value <= maximumAnchorFrameBytes ->
            pure value
      _ ->
        ioError (userError "invalid bounded-command protocol frame header")
  readHandleExactly handle frameLength

readHandleExactly ::
  Handle ->
  Int ->
  IO ByteString.ByteString
readHandleExactly handle requestedBytes =
  go requestedBytes []
  where
    go remaining chunks
      | remaining <= 0 = pure (ByteString.concat (reverse chunks))
      | otherwise = do
          contents <- ByteString.hGet handle remaining
          if ByteString.null contents
            then
              ioError (userError "truncated bounded-command protocol frame")
            else
              go
                (remaining - ByteString.length contents)
                (contents : chunks)

runActionBeforeDeadline :: Word64 -> IO value -> IO value
runActionBeforeDeadline deadline action = do
  remaining <- remainingDeadlineMicros deadline
  if remaining <= 0
    then deadlineExpired
    else timeout remaining action >>= maybe deadlineExpired pure
  where
    deadlineExpired =
      ioError (userError "bounded-command attempt deadline expired")

remainingDeadlineMicros :: Word64 -> IO Int
remainingDeadlineMicros deadline = do
  now <- getMonotonicTimeNSec
  pure
    ( if now >= deadline
        then 0
        else
          fromIntegral
            (min (fromIntegral (maxBound :: Int)) ((deadline - now) `div` 1000))
    )

validateLeader ::
  String ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO ()
validateLeader label processId processGroup birthIdentity = do
  unless
    (validProcessId processId && processGroup == processId)
    (ioError (userError ("invalid bounded-command " <> label <> " identity")))
  validateGroupMember label processId processGroup birthIdentity

validateExactProcess ::
  String ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO ()
validateExactProcess =
  validateGroupMember

validateGroupMember ::
  String ->
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO ()
validateGroupMember label processId processGroup birthIdentity = do
  unless
    (validProcessId processId && validProcessId processGroup)
    (ioError (userError ("invalid bounded-command " <> label <> " identity")))
  observedBirthIdentityBefore <-
    readProcessBirthIdentity processId
  observedProcessGroup <-
    getProcessGroupIDOf (fromIntegral processId)
  observedBirthIdentityAfter <-
    readProcessBirthIdentity processId
  unless
    ( observedBirthIdentityBefore == Just birthIdentity
        && observedBirthIdentityAfter == Just birthIdentity
        && fromIntegral observedProcessGroup == processGroup
    )
    ( ioError
        (userError ("bounded-command cannot verify reported " <> label <> " identity"))
    )

validProcessId :: Integer -> Bool
validProcessId processId =
  processId > 0 && processId <= 2147483647
