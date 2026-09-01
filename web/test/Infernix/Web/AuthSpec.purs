module Infernix.Web.AuthSpec
  ( spec
  ) where

import Prelude

import Infernix.Web.Auth (tokenHasAdminRole)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec =
  describe "application admin state" do
    it "derives the admin dimension from the in-memory access token" do
      tokenHasAdminRole adminToken `shouldEqual` true

    it "keeps non-admin and malformed access tokens outside the admin state" do
      tokenHasAdminRole userToken `shouldEqual` false
      tokenHasAdminRole "not-a-jwt" `shouldEqual` false
      tokenHasAdminRole "" `shouldEqual` false

adminToken :: String
adminToken =
  "header.eyJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiaW5mZXJuaXgtYWRtaW4iXX19.signature"

userToken :: String
userToken =
  "header.eyJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsib2ZmbGluZV9hY2Nlc3MiXX19.signature"
