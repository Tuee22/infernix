module Infernix.CLI
  ( main,
  )
where

import Data.List (intercalate)
import qualified Data.Text as Text
import Infernix.Cluster
import Infernix.Models
import Infernix.Service
import Infernix.Types (ModelDescriptor (..))
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.Process (callProcess)

main :: IO ()
main = getArgs >>= dispatch

dispatch :: [String] -> IO ()
dispatch args = case args of
  [] -> putStrLn helpText
  ["--help"] -> putStrLn helpText
  ["service"] -> runService Nothing
  ["service", "--port", port] -> runService (Just (read port))
  ["cluster", "up"] -> clusterUp
  ["cluster", "down"] -> clusterDown
  ["cluster", "status"] -> clusterStatus
  "kubectl" : kubectlArgs -> runKubectlCompat kubectlArgs
  ["docs", "check"] -> callProcess "python3" ["tools/docs_check.py"]
  ["test", "lint"] -> runLint
  ["test", "unit"] -> do
    callProcess "cabal" ["test", "infernix-unit"]
    callProcess "npm" ["--prefix", "web", "run", "test:unit"]
  ["test", "integration"] -> callProcess "cabal" ["test", "infernix-integration"]
  ["test", "e2e"] -> callProcess "npm" ["--prefix", "web", "run", "test:e2e"]
  ["test", "all"] -> do
    runLint
    callProcess "cabal" ["test", "infernix-unit"]
    callProcess "npm" ["--prefix", "web", "run", "test:unit"]
    callProcess "cabal" ["test", "infernix-integration"]
    callProcess "npm" ["--prefix", "web", "run", "test:e2e"]
  ["internal", "generate-web-contracts", outputDir] -> writeGeneratedContracts outputDir
  _ -> do
    putStrLn helpText
    exitFailure

runLint :: IO ()
runLint = do
  callProcess "python3" ["tools/lint_check.py"]
  callProcess "python3" ["tools/docs_check.py"]
  callProcess "cabal" ["build", "all"]

writeGeneratedContracts :: FilePath -> IO ()
writeGeneratedContracts outputDir = do
  let generatedDir = outputDir </> "Generated"
      outputFile = generatedDir </> "contracts.js"
  createDirectoryIfMissing True generatedDir
  writeFile outputFile (renderContractsModule allModels)

renderContractsModule :: [ModelDescriptor] -> String
renderContractsModule models =
  unlines
    [ "export const apiBasePath = '/api';",
      "export const maxInlineOutputLength = 80;",
      "export const models = [",
      intercalate ",\n" (map renderModel models),
      "];"
    ]
  where
    renderModel model =
      "  { modelId: "
        <> show (Text.unpack (modelId model))
        <> ", displayName: "
        <> show (Text.unpack (displayName model))
        <> ", family: "
        <> show (Text.unpack (family model))
        <> ", description: "
        <> show (Text.unpack (description model))
        <> ", requestShape: [{ name: 'inputText', label: 'Input Text', fieldType: 'text' }] }"

helpText :: String
helpText =
  unlines
    [ "infernix",
      "",
      "Commands:",
      "  infernix service [--port PORT]",
      "  infernix cluster up",
      "  infernix cluster down",
      "  infernix cluster status",
      "  infernix kubectl ...",
      "  infernix test lint",
      "  infernix test unit",
      "  infernix test integration",
      "  infernix test e2e",
      "  infernix test all",
      "  infernix docs check"
    ]
