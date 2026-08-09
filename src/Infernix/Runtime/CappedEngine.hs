-- | The public inference-process boundary. Launching requires a
-- runtime-refined 'ExecutableModel' and a closed operation for the selected
-- engine family. Indexed grants, live enforcers, raw process specifications,
-- rendered environments, and process handles remain in the package-internal
-- kernel.
module Infernix.Runtime.CappedEngine
  ( EngineOutputStream (..),
    EngineOutcome (..),
    EngineExecutionAuthority,
    NativeArtifactCache,
    NativeArtifactInvocation,
    NativeArtifactLaunchOutcome (..),
    PythonWorkerLaunchOutcome (..),
    nativeArtifactCache,
    nativeArtifactInvocation,
    newEngineExecutionAuthority,
    runExecutableNativeArtifact,
    runExecutablePythonWorker,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    verifyNvidiaVramSampler,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
    withSerializedEngineExecution,
  )
where

import Infernix.Runtime.CappedEngine.Internal
  ( EngineExecutionAuthority,
    EngineOutcome (..),
    EngineOutputStream (..),
    NativeArtifactCache,
    NativeArtifactInvocation,
    NativeArtifactLaunchOutcome (..),
    PythonWorkerLaunchOutcome (..),
    nativeArtifactCache,
    nativeArtifactInvocation,
    newEngineExecutionAuthority,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    runExecutableNativeArtifact,
    runExecutablePythonWorker,
    verifyNvidiaVramSampler,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
    withSerializedEngineExecution,
  )
