{ runtimeMode : Text
, edgePort : Integer
, configMapName : Text
, generatedPath : Text
, mountedPath : Text
, demo_ui : Bool
, daemonRole : Text
, coordinator :
    { role : Text
    , location : Text
    , memberId : Optional Text
    , request_topics : List Text
    , result_topic : Text
    , pulsarConnectionMode : Text
    }
, engineDaemons :
    List
      { role : Text
      , location : Text
      , memberId : Optional Text
      , request_topics : List Text
      , result_topic : Text
      , pulsarConnectionMode : Text
      }
, enginePools :
    List
      { id : Text
      , runtimeMode : Text
      , models : List Text
      , members : List Text
      , subscription : Text
      , maxInflightPerMember : Integer
      }
, engineMembers :
    List { id : Text, runtimeMode : Text, location : Text, pools : List Text }
, request_topics : List Text
, result_topic : Text
, models_bucket : Text
, model_bootstrap_topic : Text
, engines :
    List
      { engine : Text
      , adapterId : Text
      , adapterType : Text
      , adapterLocator : Text
      , adapterEntrypoint : Text
      , setupEntrypoint : Text
      , projectDirectory : Text
      , pythonNative : Bool
      }
, models :
    List
      { matrixRowId : Text
      , modelId : Text
      , displayName : Text
      , family : Text
      , description : Text
      , artifactType : Text
      , referenceModel : Text
      , downloadUrl : Text
      , selectedEngine : Text
      , requestShape : List { name : Text, label : Text, fieldType : Text }
      , runtimeMode : Text
      , runtimeLane : Text
      , requiresGpu : Bool
      , notes : Text
      }
}
