{-# LANGUAGE OverloadedStrings #-}

-- | Phase 8 Sprint 8.11 — the checks that hold the system contract and the
-- machine contract together.
--
-- The two contracts answer different questions. The system contract
-- (@./infernix.dhall@) says what the platform runs — the substrate mode and the
-- pool graph, with each pool carrying its own model descriptors — and every
-- machine holds it identically. The machine contract (the @machine@ block of
-- @./infernix-host.dhall@) describes one box: the role it defaults to, the
-- engine member identities it may adopt, its model-cache quota, and the content
-- digest of the system contract it was generated against.
--
-- Be precise about what this module buys. Both checks here are __local__: they
-- prove that this machine's manifest matches this machine's copy of the system
-- contract, and neither can see another machine's copy. That is a real
-- reduction in blast radius — several silent disagreement axes collapse into
-- one — and it is not detection across a fleet. The cross-machine half is the
-- contract digest registered in the Pulsar topic's own properties
-- ('Infernix.Runtime.Pulsar'), because the broker is the only place N machines
-- meet.
module Infernix.MachineContract
  ( SystemContractDigest,
    systemContractDigestText,
    canonicalSystemContractText,
    digestSystemContract,
    digestSystemContractFile,
    MachinePinOutcome (..),
    classifyMachinePin,
    requireMachineContractPair,
    requireDeclaredMachine,
    resolveMachineMemberId,
  )
where

import Control.Monad (when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.List (intercalate, sort, sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.HostConfig (HostConfig, HostMachineContract (..), MachineNode (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.Substrate.Internal (decodeSubstrateConfigFile)
import Infernix.Types
import System.Directory (doesFileExist)

-- | The content digest of one generated system contract. The constructor is
-- hidden so a digest can only come from bytes this binary actually hashed; a
-- digest parsed out of a manifest stays 'Text' and is compared against a minted
-- one rather than substituted for it.
newtype SystemContractDigest = SystemContractDigest Text
  deriving (Eq, Show)

systemContractDigestText :: SystemContractDigest -> Text
systemContractDigestText (SystemContractDigest value) = value

-- | The canonical rendering of the facts a fleet must agree on.
--
-- The digest covers this projection rather than the generated file's bytes, and
-- the reason is a defect the live cohort found rather than a preference. One
-- deployment legitimately holds the same contract as more than one payload: the
-- operator's repo-root file names its own absolute @generatedPath@, and the
-- published cluster mirror is rendered for the pods that mount it. Hashing the
-- text made those two the /same contract with two digests/, so the Apple host
-- engine and the cluster coordinator refused each other on a deployment where
-- nothing disagreed.
--
-- What is in here is exactly what the configuration doctrine calls a system
-- fact: the substrate mode, the topic names, the object bucket, and the pool
-- graph — pool identity, subscription type, member identity, and each pool's
-- models with the properties routing and admission decide on. What is
-- deliberately out is everything a machine may legitimately hold differently:
-- file paths, the ConfigMap name, the demo-UI flag, and the inference memory
-- budget, which is per-machine by construction.
--
-- Every list is sorted, so two machines that agree on the graph agree on the
-- digest whatever order their generators produced.
canonicalSystemContractText :: DemoConfig -> Text
canonicalSystemContractText config =
  Text.unlines
    ( [ "runtimeMode " <> runtimeModeId (configRuntimeMode config),
        "modelsBucket " <> modelsBucket config,
        "modelBootstrapTopic " <> modelBootstrapTopic config,
        "resultTopic " <> resultTopic config
      ]
        <> ["requestTopic " <> topicValue | topicValue <- sort (requestTopics config)]
        <> concatMap poolLines (sortOn enginePoolId (enginePools config))
    )
  where
    poolLines pool =
      [ "pool "
          <> enginePoolId pool
          <> " "
          <> consumerSubscriptionTypeId (enginePoolSubscriptionType pool)
      ]
        <> [ "poolMember " <> enginePoolId pool <> " " <> memberIdValue
           | memberIdValue <- sort (enginePoolMemberIds pool)
           ]
        <> [ "poolModel "
               <> enginePoolId pool
               <> " "
               <> modelId model
               <> " "
               <> selectedEngine model
               <> " "
               <> (if requiresGpu model then "gpu" else "cpu")
               <> " "
               <> Text.pack (show (executionContextLength (modelExecutionShape model)))
               <> " "
               <> Text.pack (show (executionCacheElementWidth (modelExecutionShape model)))
               <> " "
               <> downloadUrl model
           | model <- sortOn modelId (poolModels pool)
           ]
    poolModels pool =
      [model | model <- models config, modelId model `elem` enginePoolModelIds pool]

digestSystemContract :: DemoConfig -> SystemContractDigest
digestSystemContract config =
  SystemContractDigest
    ( "sha256:"
        <> TextEncoding.decodeUtf8
          (Base16.encode (SHA256.hash (TextEncoding.encodeUtf8 (canonicalSystemContractText config))))
    )

-- | Digest the system contract a generated file describes.
digestSystemContractFile :: FilePath -> IO SystemContractDigest
digestSystemContractFile filePath =
  digestSystemContract <$> decodeSubstrateConfigFile filePath

-- | The three states of the local pin, kept distinct on purpose.
--
-- A manifest that pins nothing is /absent/, not /disagreeing/: the image
-- default describes no machine, so treating it as a mismatch would report a
-- fleet disagreement that has not happened. Only 'MachinePinDisagrees' is a
-- disagreement, and only it names two digests.
data MachinePinOutcome
  = MachinePinAgrees
  | MachinePinUndeclared
  | MachinePinDisagrees Text Text
  deriving (Eq, Show)

classifyMachinePin :: HostConfig -> SystemContractDigest -> MachinePinOutcome
classifyMachinePin hostConfig observedDigest =
  case HostConfig.hostMachine hostConfig of
    ImageDefaultMachine -> MachinePinUndeclared
    DeclaredMachine node
      | machineSystemContractDigest node == systemContractDigestText observedDigest ->
          MachinePinAgrees
      | otherwise ->
          MachinePinDisagrees
            (machineSystemContractDigest node)
            (systemContractDigestText observedDigest)

-- | Fail closed when the machine contract and the system contract on disk are
-- not the pair they were generated as.
--
-- The check runs against the canonical generated pair at their canonical paths.
-- A daemon may still be pointed at a different operational payload — the
-- cluster mounts a published system contract into its pods — and that payload is
-- covered by the broker-registered digest instead, which is the only check that
-- can see more than one machine.
requireMachineContractPair :: HostConfig -> FilePath -> IO ()
requireMachineContractPair hostConfig systemContractPath = do
  systemContractPresent <- doesFileExist systemContractPath
  when systemContractPresent $ do
    observedDigest <- digestSystemContractFile systemContractPath
    case classifyMachinePin hostConfig observedDigest of
      MachinePinAgrees -> pure ()
      MachinePinUndeclared -> pure ()
      MachinePinDisagrees pinnedDigest observedText ->
        ioError
          ( userError
              ( unlines
                  [ "machine contract is pinned to a different system contract",
                    "  system contract: " <> systemContractPath,
                    "  pinned digest:   " <> Text.unpack pinnedDigest,
                    "  observed digest: " <> Text.unpack observedText,
                    "The machine contract pins the system contract it was generated"
                      <> " against, so this machine is paired with a contract it has"
                      <> " never seen. No `.dhall` is version-controlled: re-run"
                      <> " `infernix init --force` to regenerate the pair."
                  ]
              )
          )

-- | Require a real machine contract. The image default describes no machine, so
-- a daemon started against it is refused by name rather than adopting a role and
-- an identity nothing declared.
requireDeclaredMachine :: HostConfig -> IO MachineNode
requireDeclaredMachine hostConfig =
  case HostConfig.hostMachine hostConfig of
    DeclaredMachine node -> pure node
    ImageDefaultMachine ->
      ioError
        ( userError
            ( unlines
                [ "host manifest declares no machine contract",
                  "The image-default manifest is byte identical in every image and"
                    <> " therefore describes no machine: it carries no role, no member"
                    <> " identity, and no system-contract pin.",
                  "Run `infernix init` to create this machine's"
                    <> " ./infernix.dhall and ./infernix-host.dhall."
                ]
            )
        )

-- | Resolve which declared member identity this engine process is.
--
-- Identity is declared, never discovered. One declared member needs no
-- selection; more than one requires @--engine-name@ to name one of them, and a
-- name outside the declared set is refused rather than adopted.
resolveMachineMemberId :: MachineNode -> Maybe Text -> Either String Text
resolveMachineMemberId node requestedMemberId =
  case (machineMembers node, requestedMemberId) of
    ([], _) ->
      Left
        ( "this machine contract declares no engine member identity;"
            <> " re-run `infernix init` to regenerate it"
        )
    ([onlyMember], Nothing) -> Right onlyMember
    ([onlyMember], Just requested)
      | requested == onlyMember -> Right onlyMember
      | otherwise -> Left (unknownMember requested [onlyMember])
    (declaredMembers, Nothing) ->
      Left
        ( "this machine contract declares "
            <> show (length declaredMembers)
            <> " engine member identities ("
            <> renderMembers declaredMembers
            <> "); pass `--engine-name` to name which one this process is"
        )
    (declaredMembers, Just requested)
      | requested `elem` declaredMembers -> Right requested
      | otherwise -> Left (unknownMember requested declaredMembers)
  where
    unknownMember requested declaredMembers =
      "engine member "
        <> show (Text.unpack requested)
        <> " is not declared by this machine contract; it declares "
        <> renderMembers declaredMembers
    renderMembers = intercalate ", " . map (show . Text.unpack)
