module Infernix.DemoConfig
  ( materializeEmptyModelsDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeBuildMemoryCeilingFile,
    materializeHostManifestFile,
    materializeHostSecrets,
    restampMachineContractPin,
    observeAppleHostMemoryPartition,
    renderGeneratedDemoConfigPayload,
    renderModelListing,
    resolveInferenceMemoryBudget,
    stripDemoConfigBanner,
    validateDemoConfigFile,
    writeProjectConfigFile,
  )
where

import Infernix.DemoConfig.Internal
  ( materializeBuildMemoryCeilingFile,
    materializeEmptyModelsDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    materializeHostSecrets,
    observeAppleHostMemoryPartition,
    renderGeneratedDemoConfigPayload,
    renderModelListing,
    resolveInferenceMemoryBudget,
    restampMachineContractPin,
    stripDemoConfigBanner,
    writeProjectConfigFile,
  )
import Infernix.Substrate (decodeCompiledRuntimePlanFile)

-- | Validate a runtime config through the same compilation boundary used by
-- production routing and launch consumers.
validateDemoConfigFile :: FilePath -> IO ()
validateDemoConfigFile filePath = do
  compiledPlan <- decodeCompiledRuntimePlanFile filePath
  case compiledPlan of
    Left errors ->
      ioError
        (userError ("runtime config did not compile: " <> show errors))
    Right _ -> pure ()
