module Infernix.ProcessIdentity
  ( ProcessBirthIdentity (..),
    dropInheritedProcessIdentity,
    parseProcessBirthIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
    renderProcessBirthIdentity,
  )
where

import Infernix.ProcessIdentity.Internal
