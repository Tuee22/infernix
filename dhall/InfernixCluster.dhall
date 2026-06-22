{ pulsar :
    { httpBaseUrl : Text
    , wsBaseUrl : Text
    , adminUrl : Text
    , serviceUrl : Text
    , tenant : Text
    , namespace : Text
    , systemNamespace : Text
    }
, minio :
    { endpoint : Text
    , presignPublicEndpoint : Text
    , region : Text
    , presignExpirySeconds : Natural
    , modelsBucket : Text
    , demoArtifactsBucket : Text
    }
, keycloak :
    { baseUrl : Text, realmName : Text, clientId : Text, jwksUrl : Text }
, demoBackend :
    { bindHost : Text
    , port : Natural
    , bridgeMode : Text
    , publicationStatePath : Text
    , demoConfigPath : Text
    }
, engine :
    { modelCacheRoot : Text
    , modelCacheQuotaBytes : Natural
    , commandOverrides : List { mapKey : Text, mapValue : Text }
    }
, coordinator :
    { catalogSource : Text, controlPlaneContext : Text, daemonLocation : Text }
}
