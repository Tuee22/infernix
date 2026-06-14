let DaemonConfig =
      { role : Text
      , location : Text
      , memberId : Optional Text
      , request_topics : List Text
      , result_topic : Text
      , host_batch_topic : Optional Text
      , pulsarConnectionMode : Text
      }

let EnginePool =
      { id : Text
      , runtimeMode : Text
      , models : List Text
      , members : List Text
      , subscription : Text
      , maxInflightPerMember : Integer
      }

let EngineMember =
      { id : Text
      , runtimeMode : Text
      , location : Text
      , pools : List Text
      }

let EngineBinding =
      { engine : Text
      , adapterId : Text
      , adapterType : Text
      , adapterLocator : Text
      , adapterEntrypoint : Text
      , setupEntrypoint : Text
      , projectDirectory : Text
      , pythonNative : Bool
      }

let RequestField =
      { name : Text
      , label : Text
      , fieldType : Text
      }

let ModelDescriptor =
      { matrixRowId : Text
      , modelId : Text
      , displayName : Text
      , family : Text
      , description : Text
      , artifactType : Text
      , referenceModel : Text
      , downloadUrl : Text
      , selectedEngine : Text
      , requestShape : List RequestField
      , runtimeMode : Text
      , runtimeLane : Text
      , requiresGpu : Bool
      , notes : Text
      }

in  { runtimeMode : Text
    , edgePort : Integer
    , configMapName : Text
    , generatedPath : Text
    , mountedPath : Text
    , demo_ui : Bool
    , daemonRole : Text
    , coordinator : DaemonConfig
    , engine : Optional DaemonConfig
    , engineDaemons : List DaemonConfig
    , enginePools : List EnginePool
    , engineMembers : List EngineMember
    , request_topics : List Text
    , result_topic : Text
    , models_bucket : Text
    , model_bootstrap_topic : Text
    , engines : List EngineBinding
    , models : List ModelDescriptor
    }
