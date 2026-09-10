{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RoleAnnotations #-}

-- | Closed lifecycle syntax. Constructors and the interpreter are hidden from
-- library consumers. No instruction accepts IO, a mutable reference, a child
-- action, or a caller-selected lock path.
module Infernix.Cluster.LifecycleProgram.Internal
  ( LifecycleSession (..),
    LifecycleProgram (..),
    LifecycleOperation (..),
    finishLifecycle,
    observeLifecycle,
    lifecycleOperatorUp,
    lifecycleOperatorDown,
    lifecycleHarnessUp,
    lifecycleHarnessDown,
    lifecycleHarnessGpuEngine,
  )
where

import Data.Text (Text)
import Infernix.Types (ClusterState, RuntimeMode)

data LifecycleSession s = LifecycleSession

type role LifecycleSession nominal

data LifecycleOperation
  = OperatorUp (Maybe RuntimeMode)
  | OperatorDown (Maybe RuntimeMode)
  | HarnessUp (Maybe RuntimeMode)
  | HarnessDown (Maybe RuntimeMode)
  | HarnessGpuEngine (Maybe Text)

data LifecycleProgram s result where
  FinishLifecycle :: result -> LifecycleProgram s result
  ObserveLifecycle ::
    (Maybe ClusterState -> LifecycleSession s %1 -> LifecycleProgram s result) ->
    LifecycleProgram s result
  PerformLifecycle ::
    LifecycleOperation ->
    (LifecycleSession s %1 -> LifecycleProgram s result) ->
    LifecycleProgram s result

type role LifecycleProgram nominal representational

finishLifecycle :: result -> LifecycleSession s %1 -> LifecycleProgram s result
finishLifecycle result LifecycleSession = FinishLifecycle result

observeLifecycle ::
  LifecycleSession s %1 ->
  (Maybe ClusterState -> LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
observeLifecycle LifecycleSession = ObserveLifecycle

performLifecycle ::
  LifecycleSession s %1 ->
  LifecycleOperation ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
performLifecycle LifecycleSession = PerformLifecycle

lifecycleOperatorUp ::
  LifecycleSession s %1 ->
  Maybe RuntimeMode ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
lifecycleOperatorUp session mode = performLifecycle session (OperatorUp mode)

lifecycleOperatorDown ::
  LifecycleSession s %1 ->
  Maybe RuntimeMode ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
lifecycleOperatorDown session mode = performLifecycle session (OperatorDown mode)

lifecycleHarnessUp ::
  LifecycleSession s %1 ->
  Maybe RuntimeMode ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
lifecycleHarnessUp session mode = performLifecycle session (HarnessUp mode)

lifecycleHarnessDown ::
  LifecycleSession s %1 ->
  Maybe RuntimeMode ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
lifecycleHarnessDown session mode = performLifecycle session (HarnessDown mode)

lifecycleHarnessGpuEngine ::
  LifecycleSession s %1 ->
  Maybe Text ->
  (LifecycleSession s %1 -> LifecycleProgram s result) ->
  LifecycleProgram s result
lifecycleHarnessGpuEngine session engine = performLifecycle session (HarnessGpuEngine engine)
