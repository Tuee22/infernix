-- |
-- Bounded descriptor space for the spawn kernels.
--
-- Every spawn kernel in this repository sets @close_fds = True@ so a child
-- inherits nothing but the standard streams the kernel hands it. That flag is
-- not free, and its cost is set by a resource the process does not otherwise
-- reason about.
--
-- @close_fds@ is unsupported by @posix_spawn@, so @process@ falls back to
-- fork\/exec, and in the forked child it runs
--
-- > for (int i = 3; i < get_max_fd(); i++) close(i);
--
-- where @get_max_fd@ is @sysconf(_SC_OPEN_MAX)@ — the /soft/ @RLIMIT_NOFILE@.
-- The loop is therefore linear in a limit that is inherited from whatever
-- started the process, and containerd hands a pod a soft limit of
-- @1073741816@.
--
-- Measured on the development host (Ubuntu 24.04, @process-1.6.26.1@), spawning
-- @\/bin\/true@ through the same public @System.Process@ API the kernels use:
--
-- +---------------------+---------------------------+
-- | soft @RLIMIT_NOFILE@| wall time to spawn        |
-- +=====================+===========================+
-- | 1024                | 0.9 ms                    |
-- +---------------------+---------------------------+
-- | 4096                | 1.8 ms                    |
-- +---------------------+---------------------------+
-- | 16384               | 4.9 ms                    |
-- +---------------------+---------------------------+
-- | 65536               | 17.5 ms                   |
-- +---------------------+---------------------------+
-- | 524288              | 130 ms                    |
-- +---------------------+---------------------------+
-- | 1073741816 (a pod)  | 313 s                     |
-- +---------------------+---------------------------+
--
-- The last row is a measurement, not an extrapolation: it was taken inside a
-- container started with the pod's own @--ulimit nofile=1073741816@. With
-- @close_fds = False@ the same spawn is 0.8 ms at every limit, so the whole
-- cost is the pre-@exec@ descriptor walk.
--
-- That is what stalled the NVIDIA footprint observer, whose sampling cadence is
-- 50 ms and whose total deadline is 5 s. It is not specific to that observer:
-- the capped-engine launch and the bounded-command self-exec anchor set the
-- same flag, and a bounded command performs three self-exec spawns, so an
-- unbounded descriptor space costs roughly a quarter-hour per bounded command
-- inside a pod.
--
-- The correction is to bound the resource rather than to weaken the isolation.
-- 'establishBoundedDescriptorSpace' lowers the soft limit to
-- 'spawnDescriptorLimitCeiling' as the first action of a process image, before
-- anything has opened a descriptor. Because a process cannot open a descriptor
-- numbered at or above its own soft limit, no descriptor above the bound can
-- ever exist afterwards, so the child's walk over @3 .. bound@ still closes the
-- entire descriptor space. The isolation property @close_fds@ provides is
-- preserved exactly; only its cost becomes bounded.
--
-- The bound is inherited across @fork@ and @exec@, so a self-exec anchor,
-- supervisor, pin, target, or engine child is bounded by its parent without
-- doing anything itself. 'requireBoundedDescriptorSpace' is the fail-closed
-- half: a spawn kernel calls it immediately before @createProcess@, so a
-- process image that never established the bound produces a loud, named error
-- instead of a five-minute stall that reads as a hang.
module Infernix.DescriptorSpace
  ( DescriptorSpaceBound,
    descriptorSpaceBoundLimit,
    establishBoundedDescriptorSpace,
    requireBoundedDescriptorSpace,
    spawnDescriptorLimitCeiling,
  )
where

import System.Posix.Resource
  ( Resource (ResourceOpenFiles),
    ResourceLimit (ResourceLimit, ResourceLimitInfinity, ResourceLimitUnknown),
    ResourceLimits (hardLimit, softLimit),
    getResourceLimit,
    setResourceLimit,
  )

-- | Evidence that this process image's descriptor space is small enough for a
-- @close_fds = True@ spawn to complete promptly.
--
-- The constructor is unexported: the only ways to obtain the evidence are to
-- establish the bound or to observe that it already holds.
newtype DescriptorSpaceBound = DescriptorSpaceBound Integer
  deriving (Eq, Show)

-- | The soft @RLIMIT_NOFILE@ the bound guarantees.
descriptorSpaceBoundLimit :: DescriptorSpaceBound -> Integer
descriptorSpaceBoundLimit (DescriptorSpaceBound limit) = limit

-- | The largest soft @RLIMIT_NOFILE@ a spawn kernel will spawn into.
--
-- 16384 costs 4.9 ms of pre-@exec@ descriptor walk, which the 50 ms observer
-- sampling cadence absorbs alongside a ~27 ms @nvidia-smi@ query. The next
-- round value up, 65536, costs 17.5 ms and does not leave that cadence enough
-- room. Nothing this platform runs — a Pulsar consumer, a Warp listener, a
-- model-staging client — comes within two orders of magnitude of 16384 open
-- descriptors.
spawnDescriptorLimitCeiling :: Integer
spawnDescriptorLimitCeiling = 16384

-- | Lower this process image's soft @RLIMIT_NOFILE@ to
-- 'spawnDescriptorLimitCeiling' if it is not already at or below it.
--
-- Call this before the process opens its first descriptor — for the one
-- @infernix@ executable that means before the internal self-exec dispatch,
-- because those images spawn too. The soft limit is only ever lowered, never
-- raised, so a host that already imposes a tighter limit keeps it. The hard
-- limit is written back unchanged, so the bound is not privileged and can be
-- established by an unprivileged process.
--
-- Fails closed: if the limit cannot be observed as bounded after the write,
-- the process image refuses to continue rather than proceeding to a spawn that
-- would appear to hang.
establishBoundedDescriptorSpace :: IO DescriptorSpaceBound
establishBoundedDescriptorSpace = do
  limits <- getResourceLimit ResourceOpenFiles
  case boundedSoftLimit (softLimit limits) of
    Just alreadyBounded -> pure (DescriptorSpaceBound alreadyBounded)
    Nothing -> do
      target <- resolveTargetSoftLimit (hardLimit limits)
      setResourceLimit
        ResourceOpenFiles
        limits {softLimit = ResourceLimit target}
      confirmed <- getResourceLimit ResourceOpenFiles
      case boundedSoftLimit (softLimit confirmed) of
        Just bounded -> pure (DescriptorSpaceBound bounded)
        Nothing ->
          ioError
            ( userError
                ( "the open-file soft limit is still "
                    <> renderResourceLimit (softLimit confirmed)
                    <> " after lowering it to "
                    <> show target
                    <> "; a close_fds spawn from this process image would walk "
                    <> "that many descriptors before exec"
                )
            )

-- | Observe the bound immediately before a @close_fds = True@ spawn.
--
-- The label names the spawning kernel so an unbounded process image is
-- attributable from one line of output. This is a @getrlimit(2)@ call and is
-- cheap enough for the observer's 50 ms sampling cadence.
requireBoundedDescriptorSpace :: String -> IO DescriptorSpaceBound
requireBoundedDescriptorSpace label = do
  limits <- getResourceLimit ResourceOpenFiles
  case boundedSoftLimit (softLimit limits) of
    Just bounded -> pure (DescriptorSpaceBound bounded)
    Nothing ->
      ioError
        ( userError
            ( label
                <> " refused to spawn into an unbounded descriptor space: the "
                <> "open-file soft limit is "
                <> renderResourceLimit (softLimit limits)
                <> ", above the ceiling of "
                <> show spawnDescriptorLimitCeiling
                <> " this process image establishes at startup. Every spawn "
                <> "kernel sets close_fds = True, and the child closes each "
                <> "descriptor from 3 up to that soft limit before exec, which "
                <> "is 313 s per spawn at a containerd pod's 1073741816. Call "
                <> "establishBoundedDescriptorSpace before the first spawn in "
                <> "this process image."
            )
        )

-- | The soft limit as a bounded integer, or 'Nothing' when it exceeds the
-- ceiling or cannot be represented.
boundedSoftLimit :: ResourceLimit -> Maybe Integer
boundedSoftLimit limit =
  case limit of
    ResourceLimit value
      | value <= spawnDescriptorLimitCeiling -> Just value
    _ -> Nothing

-- | The soft limit to write, given the hard limit that caps it.
--
-- An unknown hard limit is fail-closed rather than guessed: writing a soft
-- limit without knowing the ceiling it must respect can only be wrong.
resolveTargetSoftLimit :: ResourceLimit -> IO Integer
resolveTargetSoftLimit hard =
  case hard of
    ResourceLimitInfinity -> pure spawnDescriptorLimitCeiling
    ResourceLimit value -> pure (min spawnDescriptorLimitCeiling value)
    ResourceLimitUnknown ->
      ioError
        ( userError
            ( "the open-file hard limit is not representable, so the soft "
                <> "limit cannot be bounded without risking a raise"
            )
        )

renderResourceLimit :: ResourceLimit -> String
renderResourceLimit limit =
  case limit of
    ResourceLimit value -> show value
    ResourceLimitInfinity -> "unlimited"
    ResourceLimitUnknown -> "unknown"
