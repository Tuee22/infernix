module Infernix.Lint.Proto
  ( runProtoLint,
  )
where

import Control.Monad (forM_, unless)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

requiredProtoFiles :: [(FilePath, String, [String])]
requiredProtoFiles =
  [ ( "proto/infernix/runtime/inference.proto",
      "package infernix.runtime;",
      [ "message RequestField",
        "message CatalogEntry",
        "message EngineBinding",
        "message GeneratedCatalog",
        "message InferenceRequest",
        "message WorkerRequest",
        "message WorkerResponse",
        "message ResultPayload",
        "message InferenceResult",
        "message ErrorResponse"
      ]
    ),
    ( "proto/infernix/manifest/runtime_manifest.proto",
      "package infernix.manifest;",
      [ "message ModelMaterialization",
        "message RuntimeCacheEntry",
        "message RuntimeManifest"
      ]
    ),
    ( "proto/infernix/api/inference_service.proto",
      "package infernix.api;",
      [ "message ListCatalogRequest",
        "message ListCatalogResponse",
        "message GetModelRequest",
        "message SubmitInferenceRequest",
        "message GetInferenceResultRequest",
        "service InferenceService"
      ]
    )
  ]

runProtoLint :: IO ()
runProtoLint = do
  paths <- discoverPaths
  forM_ requiredProtoFiles $ \(relativePath, packageLine, requiredSymbols) -> do
    let fullPath = repoRoot paths </> relativePath
    exists <- doesFileExist fullPath
    unless exists $
      ioError (userError ("missing required proto file: " <> relativePath))
    contents <- readFile fullPath
    unless ("syntax = \"proto3\";" `elem` lines contents) $
      ioError (userError (relativePath <> " must declare syntax = \"proto3\";"))
    unless (packageLine `elem` lines contents) $
      ioError (userError (relativePath <> " is missing package declaration " <> packageLine))
    forM_ requiredSymbols $ \requiredSymbol ->
      unless (elemSubstring requiredSymbol contents) $
        ioError (userError (relativePath <> " is missing required symbol: " <> requiredSymbol))

elemSubstring :: String -> String -> Bool
elemSubstring needle haystack =
  any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (expected : expectedRest) (actual : actualRest) =
  expected == actual && prefixOf expectedRest actualRest

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_ : rest) = value : tails rest
