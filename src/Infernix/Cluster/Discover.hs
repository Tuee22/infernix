{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster.Discover
  ( discoverChartClaimsFile,
    discoverChartImagesFile,
    discoverChartRoutesFile,
    discoverHarborOverlayImageRefsFile,
  )
where

import Control.Monad (when)
import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.List (nub, sort)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Data.Yaml qualified as Yaml
import Infernix.Types (PersistentClaim (..), RouteInfo (..))
import Text.Read (readMaybe)

discoverChartImagesFile :: FilePath -> IO [String]
discoverChartImagesFile renderedChartPath = do
  documents <- loadYamlDocuments renderedChartPath
  let discovered = sort . nub $ concatMap chartImageRefs documents
  if null discovered
    then failWith "discover-chart-images" "rendered chart did not contain any workload image references"
    else pure discovered

discoverChartClaimsFile :: FilePath -> IO [PersistentClaim]
discoverChartClaimsFile renderedChartPath = do
  documents <- loadYamlDocuments renderedChartPath
  discovered <- concatMapM chartClaimRows documents
  if null discovered
    then failWith "discover-chart-claims" "rendered chart did not contain any persistent claims"
    else pure (sortOnPersistentClaim discovered)

discoverChartRoutesFile :: FilePath -> IO [RouteInfo]
discoverChartRoutesFile renderedChartPath = do
  documents <- loadYamlDocuments renderedChartPath
  discovered <- concatMapM chartRouteRows documents
  if null discovered
    then failWith "discover-chart-routes" "rendered chart did not contain any HTTPRoute path inventory"
    else pure (List.sortOn path discovered)

discoverHarborOverlayImageRefsFile :: FilePath -> IO [String]
discoverHarborOverlayImageRefsFile overlayPath = do
  overlay <- loadSingleYamlDocument overlayPath
  pure . nub $
    concat
      [ maybe [] pure (overlayImageRef overlay ["service", "image"]),
        maybe [] pure (overlayImageRef overlay ["demo", "image"]),
        maybe [] pure (overlayImageRef overlay ["minio", "image"]),
        maybe [] pure (overlayImageRef overlay ["minio", "defaultInitContainers", "volumePermissions", "image"]),
        maybe [] pure (overlayImageRef overlay ["minio", "console", "image"]),
        maybe [] pure (overlayImageRef overlay ["minio", "clientImage"]),
        maybe [] pure (overlayScalarImageRef overlay ["pulsar", "defaultPulsarImageRepository"] ["pulsar", "defaultPulsarImageTag"])
      ]

loadYamlDocuments :: FilePath -> IO [Value]
loadYamlDocuments path = do
  payload <- ByteString.readFile path
  case Yaml.decodeAllEither' payload of
    Left err -> failWith "yaml" (show err)
    Right values -> pure values

loadSingleYamlDocument :: FilePath -> IO Value
loadSingleYamlDocument path = do
  documents <- loadYamlDocuments path
  case documents of
    [] -> pure Null
    firstDocument : _ -> pure firstDocument

chartImageRefs :: Value -> [String]
chartImageRefs document =
  sort . nub $
    podSpecImageRefs (podSpecFor document)
      <> customResourceImages document

podSpecFor :: Value -> Maybe Value
podSpecFor document =
  case lookupTextPath ["kind"] document of
    Just "Pod" -> lookupValuePath ["spec"] document
    Just "CronJob" -> lookupValuePath ["spec", "jobTemplate", "spec", "template", "spec"] document
    Just kindValue
      | kindValue `elem` workloadKinds -> lookupValuePath ["spec", "template", "spec"] document
    _ -> Nothing

workloadKinds :: [Text]
workloadKinds =
  [ "DaemonSet",
    "Deployment",
    "Job",
    "ReplicaSet",
    "ReplicationController",
    "StatefulSet"
  ]

podSpecImageRefs :: Maybe Value -> [String]
podSpecImageRefs =
  maybe [] imageRefsForPodSpec

imageRefsForPodSpec :: Value -> [String]
imageRefsForPodSpec podSpec =
  concatMap (containerImages podSpec) ["initContainers", "containers"]

containerImages :: Value -> Text -> [String]
containerImages podSpec containerKey =
  case lookupValuePath [containerKey] podSpec of
    Just (Array containers) ->
      [ Text.unpack imageRef
        | container <- Vector.toList containers,
          Just imageRef <- [lookupTextPath ["image"] container],
          not (Text.null imageRef)
      ]
    _ -> []

customResourceImages :: Value -> [String]
customResourceImages document =
  case lookupTextPath ["kind"] document of
    Just "PerconaPGCluster" ->
      [ Text.unpack imageRef
        | Just imageRef <-
            [ lookupTextPath ["spec", "image"] document,
              lookupTextPath ["spec", "proxy", "pgBouncer", "image"] document,
              lookupTextPath ["spec", "backups", "pgbackrest", "image"] document
            ],
          not (Text.null imageRef)
      ]
    _ -> []

chartClaimRows :: Value -> IO [PersistentClaim]
chartClaimRows document =
  case lookupTextPath ["kind"] document of
    Just "PersistentVolumeClaim" -> explicitClaimRows document
    Just "StatefulSet" -> statefulSetClaimRows document
    Just "PerconaPGCluster" -> validatePerconaPostgresqlCluster document >> pure []
    _ -> pure []

chartRouteRows :: Value -> IO [RouteInfo]
chartRouteRows document =
  case lookupTextPath ["kind"] document of
    Just "HTTPRoute" -> do
      routePathValue <-
        maybe
          (failWith "discover-chart-routes" "HTTPRoute is missing spec.rules[0].matches[0].path.value")
          pure
          (lookupTextPath ["spec", "rules", "0", "matches", "0", "path", "value"] document)
      purposeValue <-
        maybe
          (failWith "discover-chart-routes" "HTTPRoute is missing metadata.annotations.infernix.io/purpose")
          pure
          (lookupTextPath ["metadata", "annotations", "infernix.io/purpose"] document)
      pure [RouteInfo routePathValue purposeValue]
    _ -> pure []

explicitClaimRows :: Value -> IO [PersistentClaim]
explicitClaimRows document = do
  let storageClass = lookupTextPath ["spec", "storageClassName"] document
  case storageClass of
    Just "infernix-manual" -> pure ()
    _ ->
      failWith
        "discover-chart-claims"
        ("PersistentVolumeClaim uses unsupported storageClassName " <> show storageClass)
  metadata <- requireObject "metadata" (lookupValuePath ["metadata"] document)
  let releaseValue = deriveRelease metadata
      (workloadValue, ordinalValue, claimValue) = parseExplicitClaim metadata releaseValue
      requestedSize = maybe "5Gi" Text.unpack (lookupTextPath ["spec", "resources", "requests", "storage"] document)
      pvcNameValue = requireTextValue "name" (lookupTextFromObject "name" metadata)
      namespaceValue = maybe "default" Text.unpack (lookupTextFromObject "namespace" metadata)
  pure
    [ PersistentClaim
        { namespace = Text.pack namespaceValue,
          release = Text.pack releaseValue,
          workload = Text.pack workloadValue,
          ordinal = ordinalValue,
          claim = Text.pack claimValue,
          pvcName = Text.pack pvcNameValue,
          requestedStorage = Text.pack requestedSize
        }
    ]

statefulSetClaimRows :: Value -> IO [PersistentClaim]
statefulSetClaimRows document = do
  metadata <- requireObject "metadata" (lookupValuePath ["metadata"] document)
  let namespaceValue = maybe "default" Text.unpack (lookupTextFromObject "namespace" metadata)
      releaseValue = deriveRelease metadata
      statefulSetName = requireTextValue "name" (lookupTextFromObject "name" metadata)
      workloadValue = normalizeWorkloadName statefulSetName releaseValue
      replicas = fromMaybe 1 (lookupIntPath ["spec", "replicas"] document)
      templates =
        case lookupValuePath ["spec", "volumeClaimTemplates"] document of
          Just (Array values) -> Vector.toList values
          _ -> []
  concatMapM (templateClaims namespaceValue releaseValue workloadValue statefulSetName replicas) templates

templateClaims :: String -> String -> String -> String -> Int -> Value -> IO [PersistentClaim]
templateClaims namespaceValue releaseValue workloadValue statefulSetName replicas template = do
  let storageClass = lookupTextPath ["spec", "storageClassName"] template
      templateName = maybe "" Text.unpack (lookupTextPath ["metadata", "name"] template)
      claimValue = normalizeClaimName templateName workloadValue
      requestedSize = maybe "5Gi" Text.unpack (lookupTextPath ["spec", "resources", "requests", "storage"] template)
  case storageClass of
    Just "infernix-manual" -> pure ()
    _ ->
      failWith
        "discover-chart-claims"
        ( "StatefulSet volumeClaimTemplate "
            <> statefulSetName
            <> "/"
            <> templateName
            <> " uses unsupported storageClassName "
            <> show storageClass
        )
  pure
    [ PersistentClaim
        { namespace = Text.pack namespaceValue,
          release = Text.pack releaseValue,
          workload = Text.pack workloadValue,
          ordinal = ordinalValue,
          claim = Text.pack claimValue,
          pvcName = Text.pack (templateName <> "-" <> statefulSetName <> "-" <> show ordinalValue),
          requestedStorage = Text.pack requestedSize
        }
      | ordinalValue <- [0 .. replicas - 1]
    ]

validatePerconaPostgresqlCluster :: Value -> IO ()
validatePerconaPostgresqlCluster document = do
  let clusterName = maybe "<unnamed>" Text.unpack (lookupTextPath ["metadata", "name"] document)
      instances =
        case lookupValuePath ["spec", "instances"] document of
          Just (Array values) -> Vector.toList values
          _ -> []
      repos =
        case lookupValuePath ["spec", "backups", "pgbackrest", "repos"] document of
          Just (Array values) -> Vector.toList values
          _ -> []
      backupsEnabled = lookupBoolPath ["spec", "backups", "enabled"] document /= Just False
  mapM_ (validatePerconaInstance clusterName) instances
  when backupsEnabled (mapM_ (validatePerconaRepo clusterName) repos)

validatePerconaInstance :: String -> Value -> IO ()
validatePerconaInstance clusterName instanceValue = do
  let instanceName = maybe "<unnamed>" Text.unpack (lookupTextPath ["name"] instanceValue)
      storageClass = lookupTextPath ["dataVolumeClaimSpec", "storageClassName"] instanceValue
  case storageClass of
    Just "infernix-manual" -> pure ()
    _ ->
      failWith
        "discover-chart-claims"
        ( "PerconaPGCluster instance "
            <> clusterName
            <> "/"
            <> instanceName
            <> " uses unsupported dataVolumeClaimSpec.storageClassName "
            <> show storageClass
        )

validatePerconaRepo :: String -> Value -> IO ()
validatePerconaRepo clusterName repoValue = do
  let repoName = maybe "<unnamed>" Text.unpack (lookupTextPath ["name"] repoValue)
      storageClass = lookupTextPath ["volume", "volumeClaimSpec", "storageClassName"] repoValue
  case storageClass of
    Nothing -> pure ()
    Just "infernix-manual" -> pure ()
    _ ->
      failWith
        "discover-chart-claims"
        ( "PerconaPGCluster pgBackRest repo "
            <> clusterName
            <> "/"
            <> repoName
            <> " uses unsupported volumeClaimSpec.storageClassName "
            <> show storageClass
        )

overlayImageRef :: Value -> [Text] -> Maybe String
overlayImageRef overlay pathSegments = do
  imageValue <- lookupValuePath pathSegments overlay
  repository <- lookupTextPath ["repository"] imageValue
  tag <- lookupTextPath ["tag"] imageValue
  let registry = maybe "" Text.unpack (lookupTextPath ["registry"] imageValue)
      repositoryValue = Text.unpack repository
      tagValue = Text.unpack tag
  if null registry
    then pure (repositoryValue <> ":" <> tagValue)
    else pure (registry <> "/" <> repositoryValue <> ":" <> tagValue)

overlayScalarImageRef :: Value -> [Text] -> [Text] -> Maybe String
overlayScalarImageRef overlay repositoryPath tagPath = do
  repository <- lookupTextPath repositoryPath overlay
  tag <- lookupTextPath tagPath overlay
  pure (Text.unpack repository <> ":" <> Text.unpack tag)

deriveRelease :: KeyMap.KeyMap Value -> String
deriveRelease metadata =
  fromMaybeText
    (lookupLabel "infernix.io/release")
    (fromMaybeText (lookupLabel "release") (fromMaybeText (lookupLabel "app.kubernetes.io/instance") defaultRelease))
  where
    defaultRelease =
      takeWhile (/= '-') (requireTextValue "name" (lookupTextFromObject "name" metadata))
    lookupLabel labelName =
      lookupObjectFromObject "labels" metadata >>= lookupTextFromObject labelName

parseExplicitClaim :: KeyMap.KeyMap Value -> String -> (String, Int, String)
parseExplicitClaim metadata releaseValue =
  case (lookupLabel "infernix.io/workload", lookupLabel "infernix.io/ordinal", lookupLabel "infernix.io/claim") of
    (Just workloadValue, Just ordinalValue, Just claimValue) ->
      ( Text.unpack workloadValue,
        parseOrdinal (Text.unpack ordinalValue),
        Text.unpack claimValue
      )
    _ ->
      let nameValue = requireTextValue "name" (lookupTextFromObject "name" metadata)
          parts = splitDash nameValue
       in case reverse parts of
            claimValue : ordinalValue : rest
              | not (null claimValue),
                not (null rest),
                Just parsedOrdinal <- readMaybe ordinalValue,
                takeWhile (/= '-') nameValue == releaseValue ->
                  ( intercalateDash (reverse rest),
                    parsedOrdinal,
                    claimValue
                  )
            _ -> (normalizeWorkloadName nameValue releaseValue, 0, "data")
  where
    lookupLabel labelName =
      lookupObjectFromObject "labels" metadata >>= lookupTextFromObject labelName
    parseOrdinal rawOrdinal =
      case readMaybe rawOrdinal of
        Just value -> value
        Nothing ->
          error ("discover-chart-claims: invalid ordinal label " <> rawOrdinal)

normalizeWorkloadName :: String -> String -> String
normalizeWorkloadName nameValue releaseValue =
  let withoutRelease = stripPrefixOrSelf (releaseValue <> "-") nameValue
      doublePrefix = releaseValue <> "-pulsar-"
   in case stripPrefixMaybe doublePrefix withoutRelease of
        Just pulsarWorkload -> "pulsar-" <> pulsarWorkload
        Nothing -> withoutRelease

normalizeClaimName :: String -> String -> String
normalizeClaimName templateName workloadValue =
  case stripPrefixMaybe (workloadValue <> "-") templateName of
    Just claimSuffix -> claimSuffix
    Nothing ->
      case reverse (splitDash templateName) of
        lastSegment : _ | not (null lastSegment) -> lastSegment
        _ -> templateName

lookupValuePath :: [Text] -> Value -> Maybe Value
lookupValuePath [] value = Just value
lookupValuePath (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= lookupValuePath remainingSegments
lookupValuePath (segment : remainingSegments) (Array values) = do
  index <- readMaybe (Text.unpack segment)
  indexVector (Vector.toList values) index >>= lookupValuePath remainingSegments
lookupValuePath _ _ = Nothing

lookupTextPath :: [Text] -> Value -> Maybe Text
lookupTextPath pathSegments value =
  case lookupValuePath pathSegments value of
    Just (String textValue) -> Just textValue
    _ -> Nothing

lookupBoolPath :: [Text] -> Value -> Maybe Bool
lookupBoolPath pathSegments value =
  case lookupValuePath pathSegments value of
    Just (Bool boolValue) -> Just boolValue
    _ -> Nothing

lookupIntPath :: [Text] -> Value -> Maybe Int
lookupIntPath pathSegments value =
  case lookupValuePath pathSegments value of
    Just (Number scientificValue) -> toBoundedInteger scientificValue
    Just (String textValue) -> readMaybe (Text.unpack textValue)
    _ -> Nothing

lookupValueFromObject :: Text -> KeyMap.KeyMap Value -> Maybe Value
lookupValueFromObject keyName =
  KeyMap.lookup (Key.fromText keyName)

lookupTextFromObject :: Text -> KeyMap.KeyMap Value -> Maybe Text
lookupTextFromObject keyName objectValue =
  case lookupValueFromObject keyName objectValue of
    Just (String textValue) -> Just textValue
    _ -> Nothing

lookupObjectFromObject :: Text -> KeyMap.KeyMap Value -> Maybe (KeyMap.KeyMap Value)
lookupObjectFromObject keyName objectValue =
  case lookupValueFromObject keyName objectValue of
    Just (Object nestedObject) -> Just nestedObject
    _ -> Nothing

requireObject :: String -> Maybe Value -> IO (KeyMap.KeyMap Value)
requireObject labelName maybeValue =
  case maybeValue of
    Just (Object objectValue) -> pure objectValue
    _ -> failWith "yaml" ("missing object field " <> labelName)

requireTextValue :: String -> Maybe Text -> String
requireTextValue _ (Just textValue) = Text.unpack textValue
requireTextValue labelName Nothing = error ("yaml: missing text field " <> labelName)

sortOnPersistentClaim :: [PersistentClaim] -> [PersistentClaim]
sortOnPersistentClaim =
  List.sortOn
    ( \persistentClaim ->
        ( namespace persistentClaim,
          release persistentClaim,
          workload persistentClaim,
          ordinal persistentClaim,
          claim persistentClaim,
          pvcName persistentClaim
        )
    )

concatMapM :: (a -> IO [b]) -> [a] -> IO [b]
concatMapM _ [] = pure []
concatMapM action (value : remaining) = do
  current <- action value
  next <- concatMapM action remaining
  pure (current <> next)

indexVector :: [a] -> Int -> Maybe a
indexVector values index
  | index < 0 = Nothing
  | otherwise =
      case drop index values of
        value : _ -> Just value
        [] -> Nothing

stripPrefixMaybe :: String -> String -> Maybe String
stripPrefixMaybe prefix value =
  case Text.stripPrefix (Text.pack prefix) (Text.pack value) of
    Just stripped -> Just (Text.unpack stripped)
    Nothing -> Nothing

stripPrefixOrSelf :: String -> String -> String
stripPrefixOrSelf prefix value =
  fromMaybe value (stripPrefixMaybe prefix value)

splitDash :: String -> [String]
splitDash = map Text.unpack . Text.splitOn "-" . Text.pack

intercalateDash :: [String] -> String
intercalateDash = Text.unpack . Text.intercalate "-" . map Text.pack

fromMaybeText :: Maybe Text -> String -> String
fromMaybeText maybeValue fallbackValue =
  maybe fallbackValue Text.unpack maybeValue

failWith :: String -> String -> IO a
failWith prefix message =
  ioError (userError (prefix <> ": " <> message))
