-- Nexus Orb of Lost Memories controller: one owner, one Orb, one confirmed result.
-- EchoWeaver Orb mode: source, target and fallback rules from logic/OrbPolicy.lua.
Nexus=Nexus or {}
local M={};Nexus.OrbRuntime=M
local P=assert(Nexus.OrbPolicy);local B=assert(Nexus.GameAdapter.Orbs)
local config,run,approval,frame,configOwner
-- The unapproved maximum draft. Memory only: it is never saved, and it is
-- rebuilt only when the preferences of another character or row load.
-- tracking=true: the draft follows the confirmed Orb balance, up to
-- TRACK_CAP (a suggestion ceiling only; typed limits keep 1-10,000).
-- text: what the player typed and has not saved yet (nil when nothing).
-- editFrom: the tracking flag before the current typing, for Escape.
local draft
local TRACK_CAP=1000
-- The finished run whose next-run draft was already created (memory only).
-- Later reviews of that draft do not create it again.
local preparedFor
local advancing=false
local passiveDepth=0
local OFFER_TIMEOUT,RESULT_TIMEOUT=10,12
-- Passive recovery after a reload reads at the normal cadence while evidence can
-- still arrive soon, then at a slow cadence. It never submits anything.
local RECOVERY_FAST_WINDOW,RECOVERY_SLOW_INTERVAL=60,5
-- After a loading screen, how long the game may still hold this action's
-- choice before the status says so (its reply can still arrive late).
local HELD_CHOICE_DELAY=5
local SESSION_INTERRUPTED="Session interrupted. Orb spending will not restart automatically."
local ensureFrame,heldChoiceHint
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function now() return GetTime and GetTime() or 0 end
local function integer(n,min,max) return type(n)=="number" and n==math.floor(n) and n>=(min or 0) and n<=(max or 1000000) end
local function owner()
    return Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
end
-- Why the current character's saved row cannot be written durably now. The
-- Store owner classifies it (Store.StateWriteStatus); nothing here creates or
-- changes data. "loading" is temporary; "unavailable" needs the named action.
local WRITE_REASON={
    identity="Your character identity is not known yet. Wait a moment, then try again.",
    lifecycle_loading="Local saved data is still loading. Wait a moment, then try again.",
    database="Local saved data is unavailable. /reload may restore it.",
    ["migration-marker"]="Saved data carries a storage migration marker this build does not support, so it is kept unchanged and read-only.",
    container="Local saved data is unavailable (no character container). /reload may restore it.",
    row="This character's saved data has an unsupported shape.",
    lifecycle="Local saved data could not be verified. /reload may restore it.",
}
local function writeStatus()
    local store=Nexus.Store
    if not (store and type(store.StateWriteStatus)=="function") then return {mode="unavailable",reason="lifecycle"} end
    local ok,status=pcall(store.StateWriteStatus)
    if not ok or type(status)~="table" then return {mode="unavailable",reason="lifecycle"} end
    return status
end
-- The actual saved and supported markers, never a guess about who wrote them.
local function savedFormatText(status)
    if status.format=="malformed" then
        return string.format("The saved data format marker is not a valid format number (%s%s). This build writes format %s. The data is kept unchanged and read-only.",
            tostring(status.markerType or "unknown type"),
            status.markerText and (" "..tostring(status.markerText)) or "",
            tostring(tonumber(status.supportedFormat) or "?"))
    end
    local saved,supported=tonumber(status.savedFormat),tonumber(status.supportedFormat)
    if not saved or not supported then return WRITE_REASON.lifecycle end
    if status.format=="unverified" then
        return string.format("Saved data format %d did not pass this build's check for format %d data (field: %s). This build writes format %d. The data is kept unchanged and read-only.",
            saved,saved,tostring(status.field or "unknown"),supported)
    end
    return string.format("Saved data format %d is not supported. This build writes format %d and reads formats %d to %d after a check. The data is kept unchanged and read-only.",
        saved,supported,tonumber(status.knownFirst) or 3,tonumber(status.knownLast) or 5)
end
local function writeRefusal(status)
    local key=status.reason
    if key=="saved-format" then
        return "Local character data is not ready: "..savedFormatText(status).." No Orb action will be sent."
    end
    if status.mode=="loading" and key=="lifecycle" then key="lifecycle_loading" end
    return "Local character data is not ready: "..(WRITE_REASON[key] or WRITE_REASON.lifecycle).." No Orb action will be sent."
end
local function sameValue(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not sameValue(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function write(data)
    local status=writeStatus()
    if status.mode~="durable" then return nil,writeRefusal(status) end
    local o=owner();if not o or not o.UpdateStateV1 then return nil,"Local saved data is not ready. No Orb action will be sent." end
    -- The authorized owner creates an absent row at this explicit write.
    local ok=o.UpdateStateV1(function(s) s.orbRefinement=copy(data) end)
    if not ok then return nil,"Could not preserve Orb preferences/recovery state. No new action was sent." end
    -- UpdateStateV1 also returns true for its transient fallback. Only the same
    -- character's durable row holding exactly this data counts as preserved.
    local key=Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey()
    local row=key==status.ownerKey and type(NexusDB)=="table" and type(NexusDB.chars)=="table" and NexusDB.chars[key] or nil
    if type(row)~="table" or not sameValue(row.orbRefinement,data) then
        return nil,"Could not preserve Orb preferences/recovery state durably. No new action was sent."
    end
    return true
end
local function init()
    local key=Nexus.Store and Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey()
    -- The preferences in memory belong to one character AND its row state. A
    -- character without a row yet (created later by the owner at the first
    -- Orb write) must never share another character's in-memory preferences.
    local hasRow=key and type(NexusDB)=="table" and type(NexusDB.chars)=="table" and type(NexusDB.chars[key])=="table"
    local liveKey=key and (key..(hasRow and "#row" or "#none")) or false
    if config and (configOwner==liveKey or (run and (run.running or run.pending or run.token))) then return end
    -- The same character's row was just created (by an Orb write or another
    -- Store writer) and holds no other Orb data: the preferences and the
    -- finished run shown stay. Stored Orb data that differs (for example a
    -- receipt loaded from saved data) is loaded as before.
    if config and key and hasRow and configOwner==key.."#none" then
        local stored=NexusDB.chars[key].orbRefinement
        if stored==nil or sameValue(stored,config) then configOwner=liveKey;return end
    end
    configOwner=liveKey
    local state=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
    local c=state and state.orbRefinement or {}
    config={name=c.name or "No Wishlist selected",entries=copy(c.entries or {}),sources=copy(c.sources or {}),
        excluded=copy(c.excluded or {}),recycle=c.recycle==true,maxOrbs=integer(c.maxOrbs,1,10000) and c.maxOrbs or nil,
        pending=copy(c.pending),fingerprint=c.fingerprint,selectedSlot=c.selectedSlot,origin=c.origin}
    -- A saved maximum is kept as saved, whatever its value or origin. Only a
    -- genuinely absent (or unusable) one starts a draft that follows the
    -- confirmed balance. Nothing is written here.
    draft={tracking=config.maxOrbs==nil};preparedFor=nil
    run={state="IDLE",reason="Choose a maximum, then Start to use safe surplus copies for the assigned Wishlist.",running=false,spent=0,reserved=0,limit=0,recent={}}
    if type(config.pending)=="table" then
        run.pending=copy(config.pending);run.pending.restored=true;run.pending.since=now()
        run.pending.refreshRequested=false;run.pending.baselineStamp=nil;run.pending.recoverySerial=nil;run.pending.recoveryMatched=nil
        run.state="RECOVERY";run.reason="An earlier Orb action is unresolved. Nothing will restart. Nexus is checking, read-only, whether its offer is still open."
        run.recovery={kind="CHECKING",observing=false}
        run.spent=run.pending.spent or 0;run.reserved=run.pending.spendConfirmed and 0 or 1;run.limit=run.pending.limit or config.maxOrbs or 0
        -- Start the read-only recovery pump now. A manual choice made before the
        -- player opens the Orb window can then still be observed.
        run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW
        if ensureFrame then pcall(ensureFrame) end
    end
end
local function fingerprint(entries)
    local parts={}
    for _,e in ipairs(entries or {}) do parts[#parts+1]=table.concat({e.spellId,e.quality,e.stacks or 1,e.locked==true and 1 or 0},":") end
    return table.concat(parts,",")
end
local function setState(state,reason) run.state=state;run.reason=reason end
-- Session-only run log. It records what actually happened in this session's
-- current run and at most the preceding one: no SavedVariables history, no
-- reconstruction of older runs, and nothing here authorizes an action. It is
-- bounded by the run's own approved maximum.
local logs={current=nil,previous=nil}
local LOG_HARD_MAX=10000
-- Attempts that were never sent (a refused receipt write, an adapter refusal)
-- are recorded too, but they must never consume the room reserved for the
-- run's actual operations, or a later real spend would be dropped.
local LOG_ATTEMPT_ALLOWANCE=20
local function logNow() return now() end
local function logOwned()
    local log=logs.current
    if not log then return nil end
    -- A positive match only: a run rebuilt without an id (a lost saved row,
    -- a fresh session state) must not be able to write a finished run's
    -- header. M.Confirm assigns run.id before logBegin, so a live run always
    -- matches its own log.
    if not (run and run.id ~= nil and log.runId == run.id) then return nil end
    return log
end
local function logTouch(log)
    log.revision=(log.revision or 0)+1
end
local function logBegin(header)
    logs.previous=logs.current
    logs.current={runId=header.runId,startedAt=logNow(),build=header.build,
        character=header.character,wishlist=header.wishlist,limit=header.limit,
        state="READY",reason=header.reason,entries={},truncated=false,
        spent=0,reserved=0,revision=0}
end
local function logEntry(serial)
    local log=logOwned()
    if not log or not serial then return nil end
    for _,entry in ipairs(log.entries) do if entry.serial==serial then return entry end end
    local operations,attempts=0,0
    for _,entry in ipairs(log.entries) do
        if entry.state=="not sent" then attempts=attempts+1 else operations=operations+1 end
    end
    local bound=math.min(tonumber(log.limit) or LOG_HARD_MAX,LOG_HARD_MAX)
    if operations>=bound+LOG_ATTEMPT_ALLOWANCE then log.truncated=true;return nil end
    if attempts>=LOG_ATTEMPT_ALLOWANCE and operations>=bound then
        log.truncated=true;return nil
    end
    local entry={serial=serial,ordinal=#log.entries+1,at=logNow(),state="submitted"}
    log.entries[#log.entries+1]=entry
    logTouch(log)
    return entry
end
local function logUpdate(serial,fields)
    local entry=logEntry(serial)
    if not entry then return end
    for key,value in pairs(fields) do
        -- false clears a field: pairs() cannot carry a nil value.
        if value==false then entry[key]=nil else entry[key]=value end
    end
    local log=logOwned()
    if log then
        log.spent=run and run.spent or log.spent
        log.reserved=run and run.reserved or log.reserved
        logTouch(log)
    end
end
local function logRun(state,reason)
    local log=logOwned()
    if not log then return end
    log.state=state;log.reason=reason
    log.spent=run and run.spent or log.spent
    log.reserved=run and run.reserved or log.reserved
    logTouch(log)
end
local function changedConfig(before)
    approval=nil
    local ok,err=write(config)
    if not ok then
        -- Nothing was preserved, so the shown preferences must not change either.
        if type(before)=="table" then config=before end
        return nil,err
    end
    return true
end
local function editable()
    init();return not run.running and not run.pending and run.state~="PAUSED" and run.state~="LIMIT"
end
-- Refusal text while a restored receipt blocks Orb mode: say what can be done.
local function busyReason(subject,default)
    if run and run.pending and run.pending.restored and not run.running and M.BlockReason then
        return M.BlockReason(subject) or default
    end
    return default
end
local function savePending()
    if run.pending then
        local p=copy(run.pending);p.context=nil;p.beforeSnapshot=nil;p.token=nil
        p.spent=run.spent;p.limit=run.limit;p.since=nil;p.baselineStamp=nil;p.recoverySerial=nil;p.recoveryMatched=nil
        config.pending=p
    else config.pending=nil end
    return write(config)
end
local function release()
    if run.token then B.Release(run.token);run.token=nil end
end
local function pause(reason)
    run.running=false;run.pauseSerial=(run.pauseSerial or 0)+1;setState("PAUSED",reason)
    if run.pending and run.pending.logSerial then
        logUpdate(run.pending.logSerial,{state="paused",reason=reason})
    end
    logRun("PAUSED",reason)
end
local function terminal(state,reason)
    run.running=false;setState(state,reason)
    -- A spent-limit stop retains the paused run's ownership for an explicit
    -- increase + Resume. Stop releases it; no resource arrival resumes it.
    -- A settled completion (FINISHED) is not that case: it releases too.
    if not run.pending and state~="LIMIT" then release() end
    logRun(state,reason)
end
-- The approved maximum was reached AND the run is genuinely settled: the last
-- replacement is confirmed, its durable receipt is cleared, and there is no
-- pending action or spending exposure left. The run then ends through its own
-- owner: ownership is released, Stop is no longer needed, and the completed
-- usage and log stay visible. Anything unsettled keeps the previous LIMIT
-- behaviour, which retains its protections.
local function finishedLimit()
    return not run.pending and (run.reserved or 0)==0 and not config.pending
end
local function reachedLimit(fallbackReason)
    if finishedLimit() then
        terminal("FINISHED","Finished - limit reached. The approved maximum of "
            ..tostring(run.limit).." Orb(s) was used. Start a new run to continue.")
    else
        terminal("LIMIT",fallbackReason or "The approved Orb limit was reached.")
    end
end
local function entriesStillMatch()
    if not config.selectedSlot then return true end
    local choices=Nexus.GameAdapter.GetWishlistCandidates()
    for _,c in ipairs(choices) do
        if c.slot==config.selectedSlot then
            local resolved,st=Nexus.GameAdapter.ResolveWishlistEvidence(c)
            if st~="actionable" or not resolved then return false end
            return fingerprint(resolved.echoes)==config.fingerprint
        end
    end
    return false
end
function M.SelectWishlist(candidate)
    return nil,"Orb mode uses the assigned Wishlist. Change its assignment through My Builds or the Wishlist Editor."
end
function M.UseAssignedWishlist()
    if not editable() then return nil,busyReason("A change of Orb targets","Stop and settle the current Orb operation before changing targets.") end
    local a=Nexus.GameAdapter.AssignedWishlist()
    if a.state~="ready" then return nil,a.note or "Assign a resolved Wishlist through My Builds or the Wishlist Editor." end
    local targets,err=P.Normalize(a.entries);if not targets then return nil,err end
    local before=copy(config)
    config.entries=copy(a.entries);config.name=a.name;config.fingerprint=fingerprint(config.entries)
    config.selectedSlot=nil;config.origin="assigned";config.sources={}
    return changedConfig(before)
end
function M.MoveTarget(index,delta)
    return nil,"Target order follows the assigned Wishlist. Edit the Wishlist to change its targets."
end
local function sameContent(a,b)
    local function counts(entries)
        local out={}
        for _,e in ipairs(entries or {})do
            local key=tostring(e.spellId)..":"..tostring(e.quality)..":"..tostring(e.locked==true)
            out[key]=(out[key]or 0)+(tonumber(e.stacks)or 1)
        end
        return out
    end
    local x,y=counts(a),counts(b)
    for k,v in pairs(x)do if y[k]~=v then return false end end
    for k,v in pairs(y)do if x[k]~=v then return false end end
    return true
end
local function binding(a)
    return {owner=a.owner,activeSlot=a.activeSlot,identity=a.identity,entries=copy(a.entries)}
end
local function matches(a,b)
    return a and b and b.state=="ready" and a.owner==b.owner and a.activeSlot==b.activeSlot
        and a.identity==b.identity and sameContent(a.entries,b.entries)
end
local function assigned()
    local a=Nexus.GameAdapter.AssignedWishlist()
    if not run.running and not run.pending and not run.token then
        local entries=a.state=="ready" and a.entries or {}
        if not sameContent(config.entries,entries) then config.sources={} end
        config.entries=copy(entries);config.name=a.name or "No assigned Wishlist"
        config.selectedSlot=nil;config.origin="assigned"
    end
    return a
end
entriesStillMatch=function(current)
    local a=current or Nexus.GameAdapter.AssignedWishlist()
    if run.binding and (run.token or run.pending) then return matches(run.binding,a) end
    return a.state=="ready" and sameContent(config.entries,a.entries)
end
function M.SetLimit(n)
    init();n=tonumber(n)
    if not integer(n,1,10000) then return nil,"Choose a whole-number Orb limit from 1 to 10,000." end
    if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"Use Increase limit while paused, or finish this run first." end
    local before=copy(config);config.maxOrbs=n
    local ok,err=changedConfig(before)
    -- A saved typed maximum is the player's own amount: tracking stops.
    if ok then draft={tracking=false} end
    return ok,err
end
-- The tracked amount from the passive, bounded balance read (no request).
-- Only a confirmed balance counts; zero stays zero.
local function trackedLimit()
    local n,state,reason=B.Balance()
    if state=="confirmed" and integer(n,0) then return math.min(n,TRACK_CAP),state end
    return nil,state or "unknown",reason
end
-- Read-only view of the unapproved maximum draft. value is nil when the draft
-- follows a balance that is not confirmed, or when the typed text is not a
-- valid maximum.
function M.LimitDraft()
    init()
    local d={tracking=draft.tracking==true,text=draft.text,saved=config.maxOrbs,cap=TRACK_CAP}
    if d.tracking then d.value,d.balanceState,d.reason=trackedLimit()
    elseif draft.text~=nil then
        local n=tonumber(draft.text);d.value=integer(n,1,10000) and n or nil
    else d.value=config.maxOrbs end
    return d
end
-- The player typed into the maximum (including the same number, a partial
-- or an empty text): tracking stops and the text is kept in memory until it
-- is saved (Enter or Start) or cancelled (Escape). Nothing is written. An
-- unapproved preview is obsolete.
function M.EditLimitText(text)
    if not editable() then return nil,"The maximum is fixed during this run." end
    if draft.editFrom==nil then draft.editFrom=draft.tracking==true end
    draft.tracking=false;draft.text=tostring(text or "");approval=nil
    return true
end
-- Escape: the typed text is discarded and the draft is what it was before.
function M.CancelLimitEdit()
    init()
    if draft.editFrom~=nil then draft.tracking=draft.editFrom end
    draft.text=nil;draft.editFrom=nil
    return true
end
-- Max: the unapproved draft follows the confirmed balance again (up to
-- TRACK_CAP) until the player types another amount or starts. It is not a
-- snapshot. Checked again here; on refusal the draft is unchanged. Nothing is
-- written, started or approved.
function M.TrackBalance()
    if not editable() then return nil,"The maximum is fixed during this run. Nothing was changed." end
    local v=trackedLimit()
    if not v or v<1 then return nil,"Max needs a confirmed Orb balance above zero. Your maximum was not changed." end
    draft={tracking=true};approval=nil
    return true
end
-- The explicit preparation of a new run after a finished one: the new draft
-- follows the confirmed balance again. Only a settled FINISHED run qualifies.
function M.NewRunDraft()
    init()
    if run.running or run.pending or run.state~="FINISHED" then return nil,"Only a finished run can be followed by a new one." end
    -- Once per finished run: a later review of the same new-run draft keeps
    -- it as it is (a typed amount, or Max tracking).
    if preparedFor==run then return true end
    -- Checked before anything is replaced: a refusal changes nothing.
    local v=trackedLimit()
    if not v or v<1 then return nil,"A new run needs a confirmed Orb balance above zero. Your maximum was not changed." end
    draft={tracking=true};preparedFor=run;approval=nil
    return true
end
function M.SetRecycle(enabled)
    if not editable() then return nil,"Recycling permission is fixed during this run." end
    local before=copy(config);config.recycle=enabled==true;return changedConfig(before)
end
function M.SetSource(k,n)
    if not editable() then return nil,"Replaceable copies are fixed during this run." end
    local s,err=B.Read();if not s then return nil,err end
    local targets,e=P.Normalize(config.entries);if not targets then return nil,e end
    if not integer(n,0,79) then return nil,"Choose a valid source-copy count." end
    local available=0
    for _,r in ipairs(P.Sources(targets,s,config.excluded)) do if r.key==k then available=r.excess end end
    if n>available then return nil,"That would replace a protected or unavailable copy." end
    local before=copy(config);config.sources[k]=n>0 and n or nil;return changedConfig(before)
end
function M.Exclude(k,enabled)
    if not editable() then return nil,"Exclusions are fixed during this run." end
    if type(k)~="string" or not k:match("^%d+:%d+$") then return nil,"Choose an Echo first." end
    local before=copy(config)
    config.excluded[k]=enabled==true and true or nil
    if enabled then config.sources[k]=nil end
    return changedConfig(before)
end
function M.ClearExclusions()
    if not editable() then return nil,"Exclusions are fixed during this run." end
    local before=copy(config);config.excluded={};return changedConfig(before)
end
function M.SuggestSources()
    if not editable() then return nil,busyReason("A change of Orb sources","Stop and settle the current run first.") end
    local s,err=B.Read();if not s then return nil,err end
    local targets,e=P.Normalize(config.entries);if not targets then return nil,e end
    local proposed={};for _,r in ipairs(P.Sources(targets,s,config.excluded)) do proposed[r.key]=r.excess end
    local before=copy(config);config.sources=proposed;return changedConfig(before)
end
local function inspect()
    local assignment=assigned()
    if assignment.state~="ready" then return nil,assignment.note or "Assign a Wishlist before starting Orb mode.",assignment end
    local targets,err=P.Normalize(config.entries);if not targets then return nil,err,assignment end
    local s,e=B.Read();if not s then return nil,e,assignment end
    local prog=P.Progress(targets,s)
    local sources=P.Sources(targets,s,config.excluded)
    return {targets=targets,s=s,progress=prog,sources=sources,assignment=assignment}
end
-- `m` may be the read that the same display refresh already made. Actions
-- (Prepare, Confirm) always pass nothing and read fresh.
local function preflight(automatic,m)
    local status=writeStatus()
    if status.mode~="durable" then return nil,writeRefusal(status) end
    local err;if not m then m,err=inspect();if not m then return nil,err end end
    if not entriesStillMatch(m.assignment) then return nil,"The selected Wishlist changed or is unavailable. Choose it again before starting." end
    if m.progress.rolledMissing==0 then
        return nil,m.progress.permanentMissing>0 and "Rolled targets are complete. Remaining locked Echo targets cannot be changed by Orbs; no spend will start."
            or "All rolled targets are already complete. No Orbs are needed."
    end
    for _,t in ipairs(m.progress.items) do
        local r=m.s.catalog[t.spellId]
        if t.role=="rolled" and t.missing>0 and (not r or not r.available or r.quality~=t.quality) then return nil,"A missing target is currently unavailable: "..(r and r.name or t.spellId)..". "..(r and r.availabilityReason or "") end
    end
    if m.s.charges<1 then return nil,"No confirmed Orbs are available." end
    if m.s.autoAccept then return nil,"Turn off the game's automatic Echo acceptance first." end
    -- The same condition as before; the refusal names each cause that is
    -- actually present. While an action has no confirmed result (a live or
    -- watchdog-released latch, or the game still processing), a visible
    -- offer or choice is only reported: telling the player to choose or
    -- finish it could repeat an action that may already have been sent.
    local inFlight=Nexus.GameAdapter.InFlight()
    if m.s.hostPending or #m.s.board>0 or m.s.offerPending or inFlight then
        -- hostPending is any client latch (select, banish, freeze, reroll,
        -- lock, unlock), live or watchdog-released: one fact, one sentence.
        local latch=Nexus.GameAdapter.UnconfirmedLatch and Nexus.GameAdapter.UnconfirmedLatch()
        -- An automatic action whose latch already cleared can still wait for
        -- its result (submitted, uncertain or expired intent): the same fact.
        local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
        local unconfirmed=inFlight or latch or m.s.hostPending or intent~=nil
        local causes={}
        if unconfirmed then
            causes[#causes+1]="The last Echo action has no confirmed result yet."
            if m.s.offerPending then causes[#causes+1]="An Orb offer is shown." end
            if #m.s.board>0 then causes[#causes+1]="An Echo choice is shown." end
        else
            if m.s.offerPending then causes[#causes+1]="Finish the open Orb offer in the game window first." end
            if #m.s.board>0 then causes[#causes+1]="Choose the open Echo choice in the game window first." end
        end
        return nil,"Orb mode cannot start yet. "..table.concat(causes," ")
    end
    if Nexus.GameAdapter.RivalDetected() then return nil,"Disable the other Echo automation addon before starting Orb mode." end
    local capacity=0;local permitted={}
    for _,r in ipairs(m.sources) do
        local n=automatic and r.excess or (config.sources[r.key] or 0)
        if not integer(n,0,r.excess) then return nil,"Your approved replaceable counts changed. Review them again." end
        if n>0 then permitted[r.key]=n;capacity=capacity+n end
    end
    if not automatic then
        for k,n in pairs(config.sources) do if n>0 and not permitted[k] then return nil,"An approved source is no longer safe. Review the replacement pool." end end
    end
    if capacity<1 then return nil,"No safe surplus copies are available. Required and locked copies remain protected." end
    m.permitted=permitted;m.capacity=capacity;return m
end
function M.Prepare(mode,reviewed)
    init();if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,busyReason("A new Orb run","An Orb run is already active or unresolved. Stop/settle it before starting another.") end
    local automatic=mode=="assigned"
    local m,err=preflight(automatic);if not m then return nil,err end
    -- The reviewed amount, else the current draft: the tracked balance (up to
    -- TRACK_CAP), a valid typed amount, or the saved maximum. The preview
    -- returns it for review; Confirm refuses if the balance changed.
    local limit=mode=="single" and 1 or (reviewed or M.LimitDraft().value)
    if not integer(limit,1,10000) then return nil,"Choose a maximum, or press Max, before starting." end
    approval={token={},model=m,entries=copy(config.entries),sources=copy(m.permitted),
        excluded=copy(config.excluded),recycle=automatic or config.recycle,automatic=automatic,
        binding=binding(m.assignment),limit=limit,created=now()}
    local listed={};for _,s in ipairs(m.sources) do if m.permitted[s.key] then
        listed[#listed+1]={name=s.name,spellId=s.spellId,quality=s.quality,copies=m.permitted[s.key],key=s.key}
    end end
    return {token=approval.token,limit=limit,charges=m.s.charges,sources=listed,targets=copy(m.progress.items),
        name=config.name,recycle=approval.recycle,sourceCopies=m.capacity}
end
local function turnAutoOff()
    -- The master permission is SESSION state in AutomationRuntime, not a
    -- persisted 'auto' preference. Disable that actual owner before acquiring.
    if type(Nexus.DisableOrdinaryAutomation)~="function" then
        return nil,"The ordinary automation owner is not available; no Orb action will be sent."
    end
    local ok,disabled,reason=pcall(Nexus.DisableOrdinaryAutomation)
    if not ok or disabled~=true then return nil,reason or "Could not disable ordinary automation." end
    return true
end

ensureFrame=function()
    if frame then frame:Show();return end
    frame=CreateFrame("Frame","NexusOrbRuntime",UIParent)
    frame:RegisterEvent("PLAYER_LOGOUT");frame:RegisterEvent("PLAYER_LEAVING_WORLD");frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent",function()
        init()
        -- A restored receipt is already passive. Keep its recovery explanation.
        if run.pending and run.pending.restored and not run.running then return end
        if run.running or run.pending then
            run.running=false;setState("PAUSED",SESSION_INTERRUPTED);run.worldPausedAt=now()
            if run.pending then savePending() else release() end
        end
    end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+(dt or 0)
        local slow=run and run.pending and run.pending.restored and not run.running
            and now()>=(run.recoveryFastUntil or 0)
        if elapsed<(slow and RECOVERY_SLOW_INTERVAL or .2) then return end;elapsed=0
        local ok,err=pcall(M.Pump)
        if not ok then pause("Orb mode stopped after an internal error. Check diagnostics; no automatic repeat will be sent.")
            if Nexus.Errors and Nexus.Errors.Record then pcall(Nexus.Errors.Record,"OrbRuntime",tostring(err)) end
        end
        if run and not run.running and not run.pending then frame:Hide() end
    end)
end
function M.Confirm(token)
    init();local a=approval
    if not a or a.token~=token or now()-a.created>60 then return nil,"The confirmation expired. Review the plan again." end
    if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"An Orb run already owns this action." end
    local m,err=preflight(a.automatic);if not m then return nil,err end
    if not sameContent(a.entries,config.entries) or not B.SameContext(a.model.s.context,m.s.context)
        or not matches(a.binding,m.assignment)
        or a.model.s.grantedKey~=m.s.grantedKey or a.model.s.lockedKey~=m.s.lockedKey
        or a.model.s.charges~=m.s.charges then approval=nil;return nil,"Echoes or resources changed while confirming. Review again." end
    local off,e=turnAutoOff();if not off then return nil,e end
    local tokenOwner,live=B.Acquire(m.s);if not tokenOwner then return nil,live end
    run={state="READY",running=true,reason="Approved. Preparing one Orb replacement.",token=tokenOwner,
        targets=copy(a.model.targets),entries=copy(config.entries),remaining=copy(a.sources),excluded=copy(a.excluded),
        recycle=a.recycle,automatic=a.automatic,binding=copy(a.binding),name=config.name,
        limit=a.limit,spent=0,reserved=0,recent={},context=live.context}
    -- Counters and the log start only now, when a run is really authorized.
    run.id=(logs.current and (tonumber(logs.current.runId) or 0) or 0)+1
    local owner=writeStatus()
    logBegin({runId=run.id,limit=a.limit,wishlist=config.name,
        character=owner and owner.ownerKey or nil,
        build=type(Nexus.RuntimeBuildLabel)=="function" and Nexus.RuntimeBuildLabel() or nil,
        reason="Approved. Preparing one Orb replacement."})
    approval=nil;ensureFrame();M.Pump();return true
end
function M.Start(value,tracked)
    init()
    if tracked then
        -- The amount shown to the player while the draft follows the balance.
        -- It is approved as shown: never replaced by a newer balance read at
        -- the click, and not saved as a typed maximum. The existing fresh
        -- checks (Prepare, Confirm) still run.
        value=tonumber(value)
        if not draft.tracking then return nil,"The maximum changed. Review it, then press Start again." end
        if not integer(value,1,TRACK_CAP) then return nil,"Choose a maximum, or press Max, before starting." end
        local a,e=M.Prepare("assigned",value);if not a then return nil,e end
        return M.Confirm(a.token)
    end
    if value~=nil then local ok,e=M.SetLimit(value);if not ok then return nil,e end end
    local a,e=M.Prepare("assigned");if not a then return nil,e end
    return M.Confirm(a.token)
end
-- The receipt's loadout against the current read. UNKNOWN: the client has not
-- received its build-slot data since it loaded, so a slot of 0 is only its
-- load-time default, not an observed change. Nothing is decided or persisted
-- on it; the action waits for the server's slot. Any other slot in that state
-- came from the server's active-slot push and is an observation.
local function loadoutCheck(s,p)
    if p.loadoutChanged or p.originalSlot==nil then return "CHANGED" end
    if s.context.slotKnown==false then
        local slot=s.context.slot
        if slot~=nil and slot~=0 and slot~=p.originalSlot then return "CHANGED" end
        return "UNKNOWN"
    end
    if p.originalSlot~=s.context.slot then return "CHANGED" end
    return "SAME"
end
-- Read-only record of the settlement requirement that the last attempt did
-- not meet, for the status text. Session only; it authorizes nothing.
local function unmet(gate,detail)
    run.settleGate={gate=gate,detail=detail};return false
end
local function finishResult(s,p)
    run.settleGate=nil
    -- Ownership responses do not identify the originating loadout. Once that
    -- boundary changes, even an exact replacement delta can belong elsewhere.
    -- Keep this uncertainty across Recheck, return-to-slot, and reload.
    local loadout=loadoutCheck(s,p)
    if loadout=="UNKNOWN" then return unmet("loadout-unknown") end
    if loadout=="CHANGED" then
        if not p.loadoutChanged then p.loadoutChanged=true;savePending() end
        pause("The original loadout cannot be verified after a loadout change or an incomplete older receipt. Ownership responses do not identify the original loadout. Pending exposure is retained; no retry is allowed.")
        return unmet("loadout")
    end
    -- Neither a new table nor an Orb decrement proves a result. Require the
    -- original offer and a selection observed within that offer's lifecycle.
    if not p.offerKey or not p.selectionAttempted or not p.selectedKey
        or not (p.choiceMayHaveBeenSent or p.choiceObserved)
        or not p.offeredKeys or not p.offeredKeys[p.selectedKey] then return unmet("choice") end
    if p.restored and not p.baselineStamp then p.baselineStamp=s.grantStamp;return unmet("fresh") end
    local fresh=s.grantStamp>(p.restored and p.baselineStamp or p.selectionStamp or p.beforeStamp)
    if s.offerPending then return unmet("offer") end
    if s.hostPending then return unmet("host") end
    if #s.board>0 then return unmet("board") end
    if s.lockedKey~=p.lockedKey then pause("Locked Echoes changed during the operation. Resolve the result manually.");return unmet("locked") end
    -- The one-Orb decrement proves the spend. Once it was observed with this
    -- action's offer (spendConfirmed, kept in the receipt), the later total
    -- balance says nothing about this action: an Orb gained or spent afterwards
    -- must not hold it forever. The balance never settles it either; only the
    -- exact ownership result below does.
    if not p.spendConfirmed and s.charges~=p.chargesBefore-1 then
        return unmet("charges",{expected=p.chargesBefore-1,observed=s.charges})
    end
    local gained,status=P.SingleGain(p.before,p.removed,s.granted)
    if status=="WAIT" then return unmet("ownership") end
    if status=="CONFIRMED" and gained==p.removed then
        -- Even a source-removal observation followed by an equal-content
        -- snapshot can be a reordered stale response. The supported API has
        -- no correlated operation ID/revision for this same-quality outcome.
        if p.selectedKey==p.removed then
            pause("The same-ID, same-quality result is indistinguishable from stale ownership data. The client supplies no correlated completion evidence. Pending exposure is retained; no retry is allowed.")
        end
        return unmet("same-id")
    end
    -- exact: ownership already shows the recorded choice; only a response newer
    -- than the baseline is missing (recovery may ask for one, read-only).
    if not fresh then return unmet("fresh",{exact=status=="CONFIRMED" and gained==p.selectedKey}) end
    if status~="CONFIRMED" or (p.selectedKey and gained~=p.selectedKey) then
        pause("Echo ownership does not match the expected replacement. No further Orb will be spent.");return unmet("mismatch")
    end
    if not p.spendConfirmed then run.spent=run.spent+1;p.spendConfirmed=true;run.reserved=0 end
    run.recent[#run.recent+1]={removed=p.removed,obtained=gained,at=now()}
    while #run.recent>5 do table.remove(run.recent,1) end
    -- One confirmed result per operation, recorded once even when the receipt
    -- write is retried afterwards.
    logUpdate(p.logSerial,{obtained=gained,state="confirmed",
        confirmedAt=logNow(),reason=false})
    run.pending=nil
    local ok,err=savePending();if not ok then run.pending=p;pause(err);return false end
    if p.restored then
        run.recovery=nil;if type(B.Unwatch)=="function" then B.Unwatch() end
        terminal("STOPPED","Previous result confirmed. No spending restarted; review a new run explicitly.");return true
    end
    if run.targetChanged then
        setState(run.state=="STOPPED" and "STOPPED" or "PAUSED","Original replacement confirmed. Review the new assigned Wishlist, then Resume; usage is unchanged.")
        if run.state=="STOPPED" then release() end
        return true
    end
    local progress=P.Progress(run.targets,s)
    run.recycleKey=nil
    if p.kind=="RECYCLE" and run.recycle then
        for _,r in ipairs(P.Sources(run.targets,s,run.excluded)) do if r.key==gained then run.recycleKey=gained end end
    end
    if progress.rolledMissing==0 then
        terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
            progress.permanentMissing==0 and "All selected targets are complete." or "Rolled targets are complete. Remaining locked targets are unchanged; no more Orbs will be spent.")
    elseif run.spent+run.reserved>=run.limit and run.state~="STOPPED"
        and finishedLimit() then
        -- The approved maximum is reached and this result settled it. There is
        -- nothing left to resume, so a run the player had paused finishes here
        -- too, instead of asking for an increase or a Stop.
        reachedLimit()
    elseif not run.running then
        setState(run.state=="STOPPED" and "STOPPED" or "PAUSED","Last replacement confirmed; no next Orb will be spent until you explicitly continue.")
        if run.state=="STOPPED" then release() end
    elseif run.spent+run.reserved>=run.limit then reachedLimit()
    else setState("READY","Replacement confirmed. Preparing the next approved Orb.") end
    return true
end
local function observeLifecycle(s,p)
    local changed=false
    if s.offerPending and #s.board==3 then
        if p.offerKey and p.offerKey~=s.boardKey then
            pause("The pending Orb offer changed unexpectedly. Resolve the original operation manually.");return false
        end
        if not p.offerKey then
            p.offerKey=s.boardKey;p.offeredKeys={}
            local offered={}
            for _,c in ipairs(s.board) do
                p.offeredKeys[P.Key(c.spellId,c.quality)]=true
                offered[#offered+1]={spellId=c.spellId,quality=c.quality,name=c.name}
            end
            logUpdate(p.logSerial,{offered=offered,state="offered",
                reason="The actual offer was observed."})
            changed=true
        end
    end
    local sel=s.selection
    -- The adapter's observation serial restarts with each addon load. A restored
    -- receipt therefore uses the serial read at its first recovery observation.
    local floor=p.beforeSelectionSerial or 0
    if p.restored then floor=p.recoverySerial or math.huge end
    if sel and sel.serial>floor and sel.boardKey==p.offerKey then
        if p.selectedKey and p.selectedKey~=sel.key then
            pause(p.selectionRefused and not p.choiceMayHaveBeenSent
                and "A different Echo was chosen than the one Nexus had proposed for this Orb action. Nexus can confirm only the proposed Echo, so it cannot confirm this action. The record and its spending exposure are kept. No exit from this block exists yet; a settlement path is only a proposal and is not built."
                or "A different choice was submitted during the pending Orb action. Nexus cannot confirm this action. The record and its spending exposure are kept. No exit from this block exists yet; a settlement path is only a proposal and is not built.");return false
        end
        if not p.selectionAttempted then
            p.selectionAttempted=true;p.selectedKey=sel.key;p.selectionStamp=sel.grantStamp;changed=true
        end
        if not p.choiceObserved then p.choiceObserved=true;changed=true end
    end
    if changed then local ok,e=savePending();if not ok then pause(e);return false end end
    return true
end
-- Passive recovery after a reload ------------------------------------------
-- The restored receipt owns no action token. This path only reads, installs the
-- adapter's read-only choice observer, and records evidence. It never spends,
-- selects, retries, refunds, or erases. Settlement stays in finishResult and
-- keeps every requirement of the live path: the offer, a choice observed or
-- sent within that offer, one Orb, closed offer/host state, the exact ownership
-- delta, and a fresh ownership response.
local function sameCounts(a,b)
    for k,n in pairs(a) do if n~=0 and (b[k] or 0)~=n then return false end end
    for k,n in pairs(b) do if n~=0 and (a[k] or 0)~=n then return false end end
    return true
end
local function ownershipMatchesReceipt(s,p)
    if type(p.before)~="table" or type(p.removed)~="string" then return false end
    if sameCounts(s.granted,p.before) then return true end
    local after={};for k,n in pairs(p.before) do after[k]=n end
    if (after[p.removed] or 0)<1 then return false end
    after[p.removed]=after[p.removed]-1
    return sameCounts(s.granted,after)
end
local function hasChoiceEvidence(p)
    return p.offerKey~=nil and p.selectionAttempted==true and p.selectedKey~=nil
        and (p.choiceMayHaveBeenSent==true or p.choiceObserved==true)
        and type(p.offeredKeys)=="table" and p.offeredKeys[p.selectedKey]==true
end
local function exactResultOwnership(s,p)
    local gained,status=P.SingleGain(p.before,p.removed,s.granted)
    return status=="CONFIRMED" and gained~=nil
end
local recoveryChoiceEvent=false
local function onRecoveryChoice()
    -- Called by the adapter's read-only SelectPerk observer at the moment of a
    -- manual choice. One passive pump records the offer and the choice now, so
    -- the observation does not depend on the timed recovery reads.
    if not run or not run.pending or not run.pending.restored or run.running then return end
    run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW
    recoveryChoiceEvent=true
    pcall(M.Pump,true)
    recoveryChoiceEvent=false
end
local function recoverObserve(s,p)
    if p.recoverySerial==nil then p.recoverySerial=s.selectionSerial or 0 end
    -- finishResult owns the loadout-boundary pause. Nothing is observed or
    -- recorded across it: the watcher is bound to the original loadout only, as
    -- the live owner's context is.
    local loadout=loadoutCheck(s,p)
    if loadout~="SAME" then
        if type(B.Unwatch)=="function" then B.Unwatch() end
        return loadout=="UNKNOWN" and "LOADOUT_UNKNOWN" or "LOADOUT",false
    end
    local observing=type(B.Watch)=="function" and B.Watch(s,onRecoveryChoice)==true
    if s.lockedKey~=p.lockedKey then return "PERMANENT_CHANGED",observing end
    if s.offerPending and #s.board==3 then
        run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW
        local firstSeen=not p.offerKey
        local sameOffer=not firstSeen and p.offerKey==s.boardKey
        local oneOrb=s.charges==p.chargesBefore-1
        -- Order of events: the exact result ownership can arrive while the game
        -- still flags the offer as pending. A choice that the observer recorded
        -- on the offer that this session already matched is consumed first, as
        -- the live path does. It needs the same offer, the same one-Orb balance,
        -- and ownership that is either the receipt or its exact single gain.
        if sameOffer and p.recoveryMatched and oneOrb
            and (ownershipMatchesReceipt(s,p) or exactResultOwnership(s,p)) then
            if not observeLifecycle(s,p) then return "PAUSED",observing end
        end
        -- Recorded choice evidence is never discarded by a later classification.
        if sameOffer and oneOrb and hasChoiceEvidence(p) then return "WAIT_RESULT",observing end
        -- Tie an open offer to the saved action only on exact evidence: one Orb
        -- less than the receipt and ownership equal to the receipt, with or
        -- without the named source. A recorded offer must also be the same offer.
        if not oneOrb or not ownershipMatchesReceipt(s,p) or (firstSeen and p.selectionAttempted) then
            -- A choice made on an unmatched offer is never evidence for this action.
            p.recoveryMatched=nil;p.recoverySerial=math.max(p.recoverySerial,s.selectionSerial or 0)
            return "OFFER_UNMATCHED",observing
        end
        if firstSeen and s.hostPending then
            -- An offer first seen with a host action in flight is adopted only
            -- when that action is the choice the observer reports right now:
            -- same board, newer than every discarded observation, and the single
            -- host action. Any other host action waits.
            local sel=s.selection
            if not (recoveryChoiceEvent and sel and sel.onlyAction==true
                and sel.serial>p.recoverySerial and sel.boardKey==s.boardKey) then
                -- Not adopted. An observation made in this state is discarded.
                p.recoverySerial=math.max(p.recoverySerial,s.selectionSerial or 0)
                return "CHECKING",observing
            end
        end
        if not observeLifecycle(s,p) then return "PAUSED",observing end
        p.recoveryMatched=true
        if firstSeen and p.offerKey then
            p.offerSeenAfterReload=true
            if not p.spendConfirmed then p.spendConfirmed=true;run.spent=run.spent+1;run.reserved=0 end
            local ok,e=savePending();if not ok then pause(e);return "PAUSED",observing end
        end
        if hasChoiceEvidence(p) then return "WAIT_RESULT",observing end
        -- A proposed key that the adapter rejected before SelectPerk stays in the
        -- receipt. Only a manual choice of that same Echo can be confirmed.
        -- The kind stays OFFER_OPEN; `proposed` selects the truthful instruction.
        return "OFFER_OPEN",observing,(p.selectedKey~=nil and not p.choiceObserved and not p.choiceMayHaveBeenSent)
    end
    -- The matched offer can close between two reads. A choice that the observer
    -- recorded on that exact offer in this session is still consumed; any other
    -- unconsumed observation is discarded.
    if p.recoveryMatched and p.offerKey then
        if not observeLifecycle(s,p) then return "PAUSED",observing end
    end
    p.recoverySerial=math.max(p.recoverySerial,s.selectionSerial or 0)
    if hasChoiceEvidence(p) then return "WAIT_RESULT",observing end
    if s.offerPending or #s.board>0 or s.hostPending then return "CHECKING",observing end
    if (s.charges==p.chargesBefore or s.charges==p.chargesBefore-1) and ownershipMatchesReceipt(s,p) then
        return "WAIT_OFFER",observing
    end
    return "UNOBSERVABLE",observing
end
local NO_EXIT=" No exit from this block exists yet; a settlement path is only a proposal and is not built."
local KEPT=" The record and its spending exposure are kept."
local RECOVERY_TEXT={
    CHECKING="An earlier Orb action is unresolved. Another game action or an incomplete offer is visible. Nexus is waiting, read-only. Nothing will be sent.",
    OFFER_OPEN="The earlier Orb offer is still open. Choose an Echo in the game's offer window. Nexus will record that choice and wait for the matching result. Nexus will not choose or spend.",
    OFFER_OPEN_BLIND="The earlier Orb offer is still open, but this client cannot observe a manual choice. If you choose in the game, Nexus cannot confirm the earlier action afterwards."..KEPT..NO_EXIT,
    OFFER_OPEN_PROPOSED="The earlier Orb offer is still open. Before the reload Nexus proposed %s for it, and that call was refused before it reached the game. Nexus can confirm this action only if you choose that same Echo in the game's offer window. If you choose a different Echo, Nexus cannot confirm the action."..KEPT..NO_EXIT.." Nexus will not choose or spend.",
    OFFER_UNMATCHED="An Orb offer is open, but the Orb balance or rolled Echoes do not match the saved record of the earlier action. Nexus cannot confirm the earlier action from this offer. Resolve the offer in the game."..KEPT..NO_EXIT,
    WAIT_RESULT="A choice for the earlier Orb action is recorded. Nexus is waiting for a fresh ownership response that matches it exactly. Recheck requests one. Nothing will be sent.",
    WAIT_OFFER="The earlier Orb action is unresolved and no Orb offer is open. If the game opens an offer that matches the saved record and you choose in the game's offer window, Nexus records that choice at the moment you make it, unless another game action is in flight at that moment. Nexus cannot tell whether the game refused the spend."..KEPT,
    WAIT_OFFER_BLIND="The earlier Orb action is unresolved and no Orb offer is open. This client cannot observe a manual choice, so Nexus cannot confirm the earlier action if its offer opens later."..KEPT..NO_EXIT,
    PERMANENT_CHANGED="Locked Echoes changed since the earlier Orb action. Nexus cannot confirm that action."..KEPT..NO_EXIT,
    LOADOUT="The original loadout of the earlier Orb action cannot be verified. Nexus cannot confirm that action."..KEPT..NO_EXIT,
    LOADOUT_UNKNOWN="An earlier Orb action is unresolved. The game has not yet sent this character's build-slot data since it loaded, so Nexus cannot check the original loadout yet. Nexus is waiting, read-only, and records nothing until then: if an Orb offer is open, a choice made in it now cannot be recorded for the earlier action. Nothing will be sent.",
    UNOBSERVABLE="The earlier Orb action ended while Nexus could not observe it. The game gives no record of which choice belonged to it, so Nexus cannot confirm it, and Recheck cannot settle it. The record, its spending exposure, and the block on new Orb runs and ordinary rolling are kept. Nothing is retried, refunded or deleted."..NO_EXIT,
}
-- WAIT_RESULT names the settlement requirement that the last read did not
-- meet (run.settleGate), so the text does not promise that a fresh ownership
-- response settles an action that something else holds.
local WAIT_RESULT_GATE={
    ownership="A choice for the earlier Orb action is recorded. Echo ownership does not show the chosen Echo yet. Nexus is waiting for an ownership response that shows it. Recheck requests one. Nothing will be sent.",
    -- %s: the recorded Echo. Only that Echo can confirm the action, so the
    -- text names it while the recorded offer is open (for example after the
    -- /reload that ended a held game choice).
    offer="A choice for the earlier Orb action is recorded: %s. The game still reports its Orb offer as open. If you have not chosen in the game's offer window since the reload, choose %s there; a different Echo cannot confirm this action. Nexus then waits, read-only, for the matching result. Nexus will not choose or spend.",
    host="A choice for the earlier Orb action is recorded. Another game action is still in flight. Nexus is waiting, read-only, until it ends. Nothing will be sent.",
    board="A choice for the earlier Orb action is recorded, but an Echo choice is open in the game. Nexus checks the result only while no Echo choice is open; Recheck cannot close it. Taking an Echo from that choice changes your Echoes, and Nexus then cannot confirm the earlier action."..KEPT,
    charges="A choice for the earlier Orb action is recorded, but the Orb balance shown is %s and the record requires %s (one Orb less than before the action). Recheck asks the game for the current balance. While the balance differs, Nexus cannot confirm the action."..KEPT,
}
-- The first ownership read after a reload already showed the recorded choice,
-- and recovery asked the game once for a newer response (see M.Pump).
local WAIT_FRESH_ASKED="A choice for the earlier Orb action is recorded, and Echo ownership already shows the chosen Echo. Nexus needs an ownership response newer than its first read after the reload, and asked the game once for one. Recheck requests one more. No Orb and no choice will be sent."
local function recoveryReason(kind,observing,s,p,proposed)
    local gate=run.settleGate
    if kind=="WAIT_RESULT" and gate and gate.gate=="fresh" and gate.detail and gate.detail.exact and run.autoRefreshAt then
        return WAIT_FRESH_ASKED
    end
    if kind=="WAIT_RESULT" and gate and WAIT_RESULT_GATE[gate.gate] then
        local text=WAIT_RESULT_GATE[gate.gate]
        if gate.gate=="charges" then
            text=text:format(tostring(gate.detail and gate.detail.observed),tostring(gate.detail and gate.detail.expected))
        elseif gate.gate=="offer" then
            local id=p and tonumber(tostring(p.selectedKey):match("^(%d+):"))
            local row=id and s and s.catalog and s.catalog[id]
            local name=row and row.name or ("Echo "..tostring(p and p.selectedKey))
            text=text:format(name,name)
        end
        return text
    end
    if not observing and kind=="OFFER_OPEN" then return RECOVERY_TEXT.OFFER_OPEN_BLIND end
    if not observing and kind=="WAIT_OFFER" then return RECOVERY_TEXT.WAIT_OFFER_BLIND end
    if kind=="OFFER_OPEN" and proposed then
        local id=p and tonumber(tostring(p.selectedKey):match("^(%d+):"))
        local row=id and s and s.catalog and s.catalog[id]
        return RECOVERY_TEXT.OFFER_OPEN_PROPOSED:format(row and row.name or ("Echo "..tostring(p and p.selectedKey)))
    end
    return RECOVERY_TEXT[kind] or RECOVERY_TEXT.CHECKING
end
-- Truthful reason for callers that Orb mode blocks (ordinary rolling, build-slot
-- and permanent-slot changes). subject: what is blocked, e.g. "Ordinary rolling".
-- Text only: it changes no block.
local CAN_PROGRESS={CHECKING=true,UNREADABLE=true,WAIT_RESULT=true,LOADOUT_UNKNOWN=true}
local CAN_PROGRESS_OBSERVING={OFFER_OPEN=true,WAIT_OFFER=true}
function M.BlockReason(subject)
    subject=type(subject)=="string" and subject or "This action"
    if not run then return nil end
    local p=run.pending
    if p and p.restored and not run.running then
        local r=run.recovery or {}
        if CAN_PROGRESS[r.kind] or (CAN_PROGRESS_OBSERVING[r.kind] and r.observing) then
            return subject.." is blocked: an earlier Orb action is unresolved after a reload. Nexus only observes it and sends nothing. The block ends only when that action is confirmed. Open /nexus orbs for the current instruction."
        end
        return subject.." is blocked: an earlier Orb action cannot be confirmed. Nexus has no way to clear this block yet; a settlement path is only a proposal and is not built. Open /nexus orbs for details."
    end
    if run.running then return subject.." is paused: Orb refinement owns the current action." end
    if p then return subject.." is blocked: a submitted Orb action is unresolved. Finish its offer in the game; Nexus confirms it only from the matching result. If it cannot be confirmed, no exit from this block exists yet." end
    if run.state=="PAUSED" or run.state=="LIMIT" then return subject.." is blocked: an Orb run is paused. Press Stop in /nexus orbs to end that run." end
    return nil
end
-- A loading screen paused this run while the game still holds this action's
-- choice unanswered: the game's own latch then refuses every choice in its
-- offer window until a /reload. Say so, and name the recorded Echo, because
-- only that Echo can confirm the action afterwards. Text only: it changes no
-- state, requirement or block, and it replaces only the loading-screen text.
local HELD_CHOICE="The game is still waiting for its reply to the earlier Orb choice (%s), so its offer window cannot take a choice now. /reload ends that wait. After /reload, if the offer is still open, choose %s in the game's offer window; Nexus then waits for the matching result. A different Echo cannot confirm this action."..KEPT.." Nexus will not choose or spend."
heldChoiceHint=function(s,p)
    if run.running or run.state~="PAUSED" or not run.worldPausedAt then return end
    local id=p.selectedKey and tonumber(tostring(p.selectedKey):match("^(%d+):"))
    local row=id and s.catalog and s.catalog[id]
    local text=HELD_CHOICE:format(row and row.name or ("Echo "..tostring(p.selectedKey)),row and row.name or ("Echo "..tostring(p.selectedKey)))
    local held=id and p.selectionAttempted and (p.choiceMayHaveBeenSent or p.choiceObserved)
        and s.offerPending and s.selectInFlight==id and now()-run.worldPausedAt>=HELD_CHOICE_DELAY
    -- run.heldText: the exact hint shown, so it is withdrawn even if the Echo
    -- name read for it changes; any other pause reason is never replaced.
    if held and (run.reason==SESSION_INTERRUPTED or (run.heldText and run.reason==run.heldText)) then
        run.heldText=text;setState("PAUSED",text)
    elseif not held and run.heldText and run.reason==run.heldText then
        run.heldText=nil;setState("PAUSED",SESSION_INTERRUPTED)
    end
end
function M.Pump(passive)
    init();if advancing or (not run.running and not run.pending) then return end
    passive=passive==true or passiveDepth>0
    advancing=true
    local function step()
        local s,err=B.Read()
        local p=run.pending
        if not s and p and p.restored and not run.running then
            -- Passive recovery reads from addon load onward. A read that is not
            -- ready yet is not a pause reason that should outlive the loading.
            run.recovery={kind="UNREADABLE",observing=false}
            setState("RECOVERY","An earlier Orb action is unresolved. The current game state cannot be read yet: "..tostring(err).." Nothing will be sent. The record and its spending exposure are kept.")
            return
        end
        if not s then pause(err);return end
        -- Read before any check can pause, so the report never shows a stale value.
        run.pickInFlight=s.selectInFlight~=nil
        if p and p.restored then
            if p.guid~=s.context.guid then pause("The earlier Orb action belongs to another character.");return end
            if not p.baselineStamp then p.baselineStamp=s.grantStamp end
            local mark=run.pauseSerial
            local kind,observing,proposed=recoverObserve(s,p)
            if run.pauseSerial~=mark then run.recovery={kind="PAUSED",observing=observing};return end
            if finishResult(s,p) then return end
            if run.pauseSerial~=mark then run.recovery={kind="PAUSED",observing=observing};return end
            -- After a reload the player can choose before Nexus has read
            -- anything: the first ownership read then already shows the exact
            -- result and is not newer than the baseline. When that is the only
            -- missing requirement, ask the game ONCE per load for a newer
            -- ownership response: the read-only Recheck request. It sends no
            -- Orb and no choice, and settlement stays in finishResult.
            local gate=run.settleGate
            if gate and gate.gate=="fresh" and gate.detail and gate.detail.exact and not run.autoRefreshAt then
                run.autoRefreshAt=now();B.RequestRefresh()
            end
            run.recovery={kind=kind,observing=observing,proposed=proposed==true or nil,
                gate=kind=="WAIT_RESULT" and run.settleGate and copy(run.settleGate) or nil}
            setState("RECOVERY",recoveryReason(kind,observing,s,p,proposed))
            return
        end
        if run.context and not B.SameOwner(run.context,s.context) then pause("Character, run, or service changed. The pending operation will not be replayed.");return end
        local a=assigned()
        local displayTargets=a.state=="ready" and P.Normalize(a.entries)
        run.displayProgress=displayTargets and P.Progress(displayTargets,s) or nil
        if run.binding and (not matches(run.binding,a) or not B.SameContext(run.context,s.context)) then
            run.targetChanged=true
            if run.state~="STOPPED" then pause("The active loadout or assigned Wishlist changed. The original operation stays pending; Resume requires settlement and a resolved assignment.") end
        end
        if p then
            if loadoutCheck(s,p)~="SAME" then
                finishResult(s,p);return
            end
            if s.lockedKey~=p.lockedKey then pause("Locked Echoes changed; no further Orb action will be submitted.");return end
            if not observeLifecycle(s,p) then return end
            if not p.spendConfirmed and s.charges==p.chargesBefore-1 and s.offerPending then
                p.spendConfirmed=true;run.spent=run.spent+1;run.reserved=0
                local ok,e=savePending();if not ok then pause(e);return end
            elseif s.charges~=p.chargesBefore and s.charges~=p.chargesBefore-1 then
                pause("The Orb balance changed unexpectedly. No further action will be submitted.");return
            end
            if finishResult(s,p) then return end
            heldChoiceHint(s,p)
            if not run.running or passive then return end
            if not entriesStillMatch() then pause("The selected Wishlist changed; resolve the pending offer manually.");return end
            if p.selectionAttempted then
                setState("WAIT_RESULT","Waiting for a fresh server response confirming the selected replacement.")
            elseif s.offerPending and #s.board==3 and p.spendConfirmed and not s.hostPending then
                if p.ambiguous then pause("The spend outcome is now visible. Review the offer and press Resume, or resolve it manually.");return end
                local decisionState={catalog=s.catalog,granted=copy(s.granted),locked=s.locked}
                local original,afterRemoval={},{}
                for k,n in pairs(p.before) do original[k]=n;afterRemoval[k]=n end
                afterRemoval[p.removed]=math.max(0,(afterRemoval[p.removed] or 0)-1)
                local function equivalent(a,b)
                    for k,n in pairs(a) do if (b[k] or 0)~=n then return false end end
                    for k,n in pairs(b) do if (a[k] or 0)~=n then return false end end
                    return true
                end
                if equivalent(s.granted,original) then
                    decisionState.granted=afterRemoval
                elseif not equivalent(s.granted,afterRemoval) then
                    pause("Rolled Echoes changed outside the pending sacrifice; resolve the offer manually.");return
                end
                local decision,why=P.Decide(s.board,P.Progress(run.targets,decisionState),decisionState,run.recycle,run.excluded)
                if not decision then pause(why);return end
                p.selectionAttempted=true;p.selectedKey=decision.key;p.kind=decision.kind
            logUpdate(p.logSerial,{selectedKey=decision.key,selectionKind=decision.kind,
                selectionReason=decision.kind=="TARGET" and "needed target"
                    or decision.kind=="RECYCLE" and "permitted recycle"
                    or "permitted fallback",
                state="selected"})
                p.selectionStamp=s.grantStamp;p.since=now();p.refreshRequested=false
                local saved,e=savePending();if not saved then p.selectionAttempted=false;pause(e);return end
                local accepted,kind,reason=B.Select(run.token,decision.index,s.boardKey,decision.spellId,function()
                    return run.running and entriesStillMatch()
                end)
                -- An attempt rejected by the adapter before SelectPerk is not
                -- a selection lifecycle. Preserve the receipt, but never use
                -- its proposed key as proof that a choice was submitted.
                p.choiceMayHaveBeenSent=accepted==true or kind=="AMBIGUOUS"
                p.selectionAmbiguous=kind=="AMBIGUOUS";p.selectionRefused=kind=="REJECTED"
                local recorded,recordError=savePending();if not recorded then pause(recordError);return end
                if not accepted then pause(reason);return end
                setState("WAIT_RESULT","Choice sent; waiting for the confirmed replacement.")
            elseif not s.offerPending and #s.board>0 then
                pause("A different Echo choice appeared. Resolve it manually before continuing.");return
            else setState("WAIT_OFFER","One Orb requested; waiting for the actual offer and balance confirmation.") end
            local timeout=p.selectionAttempted and RESULT_TIMEOUT or OFFER_TIMEOUT
            if now()-(p.since or now())>=timeout then
                if not p.refreshRequested then
                    p.refreshRequested=true;p.since=now();B.RequestRefresh()
                else pause("No authoritative result arrived. Spending is paused; no action will be repeated.") end
            end
            return
        end
        if not run.running or passive then return end
        if not entriesStillMatch() then pause("The assigned Wishlist changed. Review it and Resume without resetting this run's usage.");return end
        local progress=P.Progress(run.targets,s)
        if progress.rolledMissing==0 then
            terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
                progress.permanentMissing==0 and "All selected targets are complete." or "Rolled targets are complete; Orbs cannot change the remaining locked targets.");return
        end
        for _,target in ipairs(progress.items) do
            local row=s.catalog[target.spellId]
            if target.role=="rolled" and target.missing>0 and (not row or not row.available or row.quality~=target.quality) then
                pause("A required target is no longer available. "..(row and row.availabilityReason or "").." No next Orb will be spent.");return
            end
        end
        -- Defensive duplicate: a settled limit is normally finished by the
        -- settlement above, and Resume refuses at the limit, so this is the
        -- last line rather than the usual path. It applies the same test.
        if run.spent+run.reserved>=run.limit then reachedLimit();return end
        if s.charges<1 then terminal("OUT_OF_ORBS","No Orbs remain. New resources will not restart this run automatically.");return end
        if s.offerPending or #s.board>0 or s.hostPending then pause("Another Echo action is active. Resolve it first.");return end
        if s.autoAccept then pause("Turn off the game's automatic Echo acceptance before continuing.");return end
        if Nexus.GameAdapter.RivalDetected() then pause("Another Echo picker is active. Disable it before continuing.");return end
        local source
        local safe=P.Sources(run.targets,s,run.excluded)
        for _,r in ipairs(safe) do if r.key==run.recycleKey then source=r;break end end
        if not source then for _,r in ipairs(safe) do if run.automatic or (run.remaining[r.key] or 0)>0 then source=r;break end end end
        if not source then terminal("NO_SOURCES","No safe surplus source copies remain. Required and locked copies stay protected.");return end
        local recycle=source.key==run.recycleKey
        run.opSerial=(run.opSerial or 0)+1
        p={before=copy(s.granted),lockedKey=s.lockedKey,removed=source.key,chargesBefore=s.charges,
            originalSlot=s.context.slot,logSerial=run.opSerial,
            beforeStamp=s.grantStamp,beforeSelectionSerial=s.selectionSerial,since=now(),guid=s.context.guid,spendConfirmed=false}
        logUpdate(run.opSerial,{sourceKey=source.key,sourceName=source.name,
            sourceQuality=source.quality,sourceCopies=source.excess,
            recycle=source.key==run.recycleKey,state="requested",
            reason="One Orb requested for this source copy."})
        run.pending=p;run.reserved=1
        local previousReceipt=config.pending
        local ok,e=savePending()
        if not ok then
            -- Nothing was sent. The unsaved receipt must not stay in the
            -- preferences, where a later successful write would persist it.
            config.pending=previousReceipt
            logUpdate(run.opSerial,{state="not sent",
                reason="The receipt could not be saved; no Orb was requested."})
            run.pending=nil;run.reserved=0;pause(e);return
        end
        if not recycle and not run.automatic then run.remaining[source.key]=math.max(0,(run.remaining[source.key] or 0)-1) end
        local accepted,kind,reason=B.Spend(run.token,source.key,s,function(live)
            if not run.running or not entriesStillMatch() then return false end
            for _,r in ipairs(P.Sources(run.targets,live,run.excluded))do if r.key==source.key and r.excess>0 then return true end end
            return false
        end)
        if not accepted then
            if kind=="REJECTED" then
                if not recycle and not run.automatic then run.remaining[source.key]=(run.remaining[source.key] or 0)+1 end
                logUpdate(p.logSerial,{state="not sent",reason=reason})
                run.pending=nil;run.reserved=0;savePending()
            else
                p.ambiguous=true;savePending()
                logUpdate(p.logSerial,{state="unknown",reason=reason})
            end
            pause(reason);return
        end
        run.recycleKey=nil
        setState("WAIT_OFFER","One Orb requested; waiting for the actual offer.")
    end
    local ok,err=pcall(step);advancing=false
    if not ok then pause("Orb mode encountered an internal error. No automatic repeat will be sent.");error(err,0) end
end
function M.Pause()
    init();if not run.running then return false end
    run.running=false;setState("PAUSED",run.pending and "Paused. An accepted spend cannot be undone; the native offer remains available." or "Paused before the next spend.")
    return true
end
function M.Stop()
    init();approval=nil;run.running=false;setState("STOPPED",run.pending and "Stopped. A submitted operation may still finish; resolve any pending offer manually." or "Stopped. No further Orb will be spent.")
    if not run.pending then release() end
    logRun("STOPPED",run.reason)
    return true
end

-- Read-only, bounded view. `which` selects the run, `from`/`count` select the
-- rows the caller will actually render; without them the whole run is copied,
-- which only the explicit Copy action needs. It starts no work and authorizes
-- nothing. The history is session-only and does not survive a reload.
function M.RunLog(which,from,count)
    init()
    local log=which=="previous" and logs.previous or logs.current
    if not log then return {sessionOnly=true,which=which or "current"} end
    local view={sessionOnly=true,which=which or "current",runId=log.runId,
        startedAt=log.startedAt,build=log.build,character=log.character,
        wishlist=log.wishlist,limit=log.limit,increased=log.increased,
        state=log.state,reason=log.reason,spent=log.spent,reserved=log.reserved,
        truncated=log.truncated,revision=log.revision,total=#log.entries,
        entries={}}
    local first=math.max(1,math.floor(tonumber(from) or 1))
    local last=count and math.min(#log.entries,first+math.max(0,math.floor(count))-1)
        or #log.entries
    for index=first,last do
        view.entries[#view.entries+1]=copy(log.entries[index])
    end
    view.hasPrevious=logs.previous~=nil
    view.hasCurrent=logs.current~=nil
    return view
end
function M.Resume()
    init();if run.state~="PAUSED" then return nil,"Only an explicitly paused run can resume." end
    if run.pending and (run.pending.restored or run.pending.selectionAttempted) then return nil,"The submitted result is still unresolved. Recheck or finish the native offer manually; no repeat is allowed." end
    local s,err=B.Read();if not s then return nil,err end
    if not run.context or not B.SameOwner(run.context,s.context) then return nil,"The original character/run/service no longer matches. This run cannot resume." end
    local a=assigned()
    if run.pending and (run.targetChanged or not matches(run.binding,a) or not B.SameContext(run.context,s.context)) then
        return nil,"The original operation must settle before Resume can adopt a changed assignment. Pending exposure is retained."
    end
    if not run.pending then
        if a.state~="ready" then return nil,a.note or "Wait for the assigned Wishlist to resolve." end
        local targets,why=P.Normalize(a.entries);if not targets then return nil,why end
        local rebound,reason=B.Rebind(run.token,s);if not rebound then return nil,reason end
        run.context=s.context;run.binding=binding(a);run.targets=targets;run.entries=copy(a.entries);run.name=a.name
        config.entries=copy(a.entries);config.name=a.name;run.targetChanged=nil;run.recycleKey=nil
    end
    if run.pending and run.pending.ambiguous then
        if not run.pending.spendConfirmed then return nil,"The spend outcome remains unknown. No action will be repeated." end
        run.pending.ambiguous=nil
    end
    if not run.pending and run.spent+run.reserved>=run.limit then return nil,"The approved limit is reached. Confirm an increased limit or stop." end
    if not run.token then return nil,"This run no longer owns the action. Stop and approve a new run after settlement." end
    local off,e=turnAutoOff();if not off then return nil,e end
    run.running=true;setState(run.pending and "WAIT_OFFER" or "READY","Resuming the approved run without resetting its usage.")
    ensureFrame();M.Pump();return true
end
function M.PrepareLimitIncrease(value)
    init();value=tonumber(value)
    if run.running or (run.state~="PAUSED" and run.state~="LIMIT") or not run.token
        or not integer(value,1,10000) or value<=run.limit or not run.context then
        return nil,"Pause the active run first, then choose a higher whole-number limit. Stopped/completed runs require new approval."
    end
    local token={};run.limitApproval={token=token,value=value,at=now()};return {token=token,limit=value,old=run.limit,spent=run.spent,reserved=run.reserved}
end
function M.ConfirmLimit(token)
    init();local a=run.limitApproval
    if not a or token~=a.token or now()-a.at>60 or run.running or not run.token or (run.state~="PAUSED" and run.state~="LIMIT") then return nil,"Review the increased limit again." end
    run.limit=a.value
    local log=logOwned()
    if log then log.limit=a.value;log.increased=true;logTouch(log) end;run.limitApproval=nil
    if run.pending then local ok,e=savePending();if not ok then return nil,e end end
    setState(run.pending and "PAUSED" or "PAUSED","Limit increased by confirmation. Press Resume explicitly; usage was not reset.")
    return true
end
function M.Recheck()
    init();if run.lastRecheck and now()-run.lastRecheck<3 then return nil,"Please wait before requesting another refresh." end
    run.lastRecheck=now()
    if run.pending and run.pending.restored then run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW end
    if run.pending and run.pending.restored and not run.pending.baselineStamp then
        local s=B.Read();if s then run.pending.baselineStamp=s.grantStamp end
    end
    -- A refresh can invoke synchronous notifications. All nested Pump calls
    -- remain passive until this handler returns, including ready offers.
    passiveDepth=passiveDepth+1
    local success,ok,err=pcall(function()
        local refreshed,why=B.RequestRefresh()
        if run.pending then ensureFrame();M.Pump(true) end
        return refreshed,why
    end)
    passiveDepth=passiveDepth-1
    if not success then return nil,"The read-only refresh failed; no new action was requested." end
    if not ok then return nil,err end
    return true,"Requested an Orb/ownership refresh. No Orb or choice was submitted."
end
-- Read-only view of the unresolved Orb action for the support report: scalars
-- only, no names. It writes nothing and authorizes nothing. Like
-- BlocksOrdinary, its init() can start the read-only recovery of a saved
-- receipt that nothing had loaded yet.
function M.RecoveryView()
    if not config then
        local st=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
        if not (type(st)=="table" and type(st.orbRefinement)=="table" and st.orbRefinement.pending) then return {pending=false} end
    end
    init()
    local p=run and run.pending
    if not p then return {pending=false,state=run and run.state} end
    local gate=run.settleGate
    return {pending=true,restored=p.restored==true,state=run.state,
        recovery=p.restored and run.recovery and run.recovery.kind or nil,gate=gate and gate.gate or nil,
        spendConfirmed=p.spendConfirmed==true,choiceSent=p.choiceMayHaveBeenSent==true,choiceObserved=p.choiceObserved==true,
        selectedKey=p.selectedKey,removed=p.removed,loadoutChanged=p.loadoutChanged==true,
        pickInFlight=run.pickInFlight,autoRefresh=run.autoRefreshAt~=nil}
end
function M.BlocksOrdinary()
    if not config then
        local st=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
        if not st then return false end
        if type(st.orbRefinement)=="table" and st.orbRefinement.pending then init() end
    end
    return run and (run.running or run.pending~=nil or (run.state=="PAUSED" or run.state=="LIMIT")) or false
end
-- Display snapshot. One adapter read per call (plus passive balance reads for
-- the balance line and the maximum draft); it authorizes nothing (every
-- action reads again). detail=true adds the source list for Advanced.
function M.Status(detail)
    init();local m,err,failed=inspect();local a=m and m.assignment or failed or assigned()
    local r={state=run.state,reason=run.reason,error=err,running=run.running,pending=run.pending~=nil,
        spent=run.spent,reserved=run.reserved,limit=run.limit,config=copy(config),recent=copy(run.recent),
        assignment=copy(a),targetChanged=run.targetChanged,operationName=run.name,
        recovery=run.pending and run.pending.restored and copy(run.recovery) or nil}
    r.config.name=a.name or "No assigned Wishlist";r.config.entries=copy(a.entries or {})
    r.config.pending=nil
    r.charges,r.balanceState,r.balanceReason=B.Balance()
    r.limitDraft=M.LimitDraft()
    if m then
        r.charges=m.s.charges;r.progress=P.Progress(assert(P.Normalize(a.entries)),m.s)
        r.sourceCount=#m.sources
        if detail~=false then r.sources=copy(m.sources) end
        -- Read-only view of the same read's catalog rows, copied per row on access.
        local rows=m.s.catalog
        r.catalog=setmetatable({},{__index=function(_,id) return copy(rows[id]) end})
        run.displayProgress=copy(r.progress)
    end
    local status=writeStatus()
    r.persistence={mode=status.mode,reason=status.reason,rowPresent=status.rowPresent}
    local can,why
    if status.mode~="durable" then why=writeRefusal(status)
    elseif m then can,why=preflight(true,m)
    else why=err end
    r.canStart=not run.running and not run.pending and run.state~="PAUSED" and run.state~="LIMIT" and can~=nil
    r.startReason=why
    r.canResume=run.state=="PAUSED" and not (run.pending and (run.targetChanged or run.pending.restored or run.pending.selectionAttempted))
    return r
end
function M.CompactStatus()
    init();if run.limit==0 and not run.pending then return nil end
    local remaining=run.displayProgress and run.displayProgress.rolledMissing
    return {state=run.state,running=run.running,pending=run.pending~=nil,spent=run.spent,reserved=run.reserved,
        limit=run.limit,remaining=remaining,reason=run.reason,
        canResume=run.state=="PAUSED" and not (run.pending and (run.targetChanged or run.pending.restored or run.pending.selectionAttempted))}
end
