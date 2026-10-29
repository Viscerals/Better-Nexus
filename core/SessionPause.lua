-- Nexus: core/SessionPause.lua
-- Whole-addon session pause (issue #171). One memory-only barrier that the
-- existing owners read at their own authority and submission gates: ordinary
-- Auto, the game adapter, Orb mode, Sync/share transport and DPS capture.
--
-- It is not a setting. Nothing here is saved, and a reload or logout starts
-- unpaused. Pausing does not turn Auto OFF, change permissions, hide the HUD,
-- leave a channel or change the saved Sync mode. Resume removes only this
-- barrier: it sends, steps, approves and resumes nothing itself; each owner
-- revalidates on its own later turn. An action already sent may still finish.
--
-- Load and the read methods create, initialize, read or schedule nothing.

Nexus = Nexus or {}

local M = {}
Nexus.SessionPause = M

local REASON = "session_pause"
-- paused: the barrier. epoch: actual paused/unpaused transitions so far, so
-- an owner can tell that work it prepared or a capture it began crossed a
-- pause, even a Pause and Resume between two of its turns.
local paused, epoch = false, 0

local function Status()
    return { paused = paused, epoch = epoch, reason = paused and REASON or nil }
end

function M.IsPaused()
    return paused
end

function M.Status()
    return Status()
end

function M.Pause()
    if paused then return Status() end
    -- The barrier first: every owner gate reads it from here on.
    paused = true
    epoch = epoch + 1
    -- Bounded hold of an Orb run that is actually running, through its own
    -- existing Pause. It creates no Orb owner and keeps the run's receipt,
    -- token, maximum and accounting. Global Resume never resumes it.
    local orb = Nexus.OrbRuntime
    if type(orb) == "table" and type(orb.HoldForSessionPause) == "function" then
        local ok, err = pcall(orb.HoldForSessionPause)
        if not ok and type(Nexus.Errors) == "table" and type(Nexus.Errors.Record) == "function" then
            pcall(Nexus.Errors.Record, "SessionPause.OrbHold", err)
        end
    end
    return Status()
end

function M.Resume()
    if not paused then return Status() end
    paused = false
    epoch = epoch + 1
    return Status()
end
