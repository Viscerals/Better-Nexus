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
local RECOVERY_LIMIT=2
-- Pacing only: local cached reads after this delay are not server freshness proof.
local WORLD_SETTLE=3
-- Passive recovery after a reload reads at the normal cadence while evidence can
-- still arrive soon, then at a slow cadence. It never submits anything.
local RECOVERY_FAST_WINDOW,RECOVERY_SLOW_INTERVAL=60,5
-- After a loading screen, how long the game may still hold this action's
-- choice before the status says so (its reply can still arrive late).
local HELD_CHOICE_DELAY=5
local SESSION_INTERRUPTED="Session interrupted. Orb spending will not restart automatically."
-- Continue is a bounded class, not an exit for every unresolved receipt.
local KEPT=" The record and its spending exposure are kept."
local NO_EXIT=" For the original no-choice class, Continue is available only after a reload for a client-observed spend with no usable recorded choice and no open offer, after a read-only check. Separately, a stopped attribution-ambiguous action needs its fresh distinct chosen gain actually owned. Both exits require a quiet read-only check and your confirmation. Open /nexus orbs for this record's eligibility and explanation. Nexus never continues by itself."
local UNOBSERVED=" This record contains no retained observation of one Orb fewer with this action's offer. That does not prove that the server spent nothing. Continue does not apply to this record. Start, Resume and reload cannot reconstruct the missing history; Recheck can collect current facts but cannot promise to settle it. Preserve the record; do not repeat the spend or clear its exposure."
-- The game's lifecycle as this owner's frame saw it (local facts only; they say
-- nothing about the server). epoch counts every loading transition (leave or
-- enter). phase: "l" between leaving and entering a world, "r" from entering (and
-- from this load) until a read succeeds, "w" afterwards. A phase is a label on the
-- evidence, never proof that the game is ready.
local life={epoch=0,phase="r"}
-- Session state of the continuation that must outlive the run table: M.Confirm replaces `run` when
-- a new run starts, and the late events after an archive (the data phase two needs) arrive during
-- that new run. serial: attempts counted; log: the last attempts; after: the archive entry that
-- late events are recorded on; reqMark: the latest Nexus refresh request; busy: a step is running.
local RS={serial=0}
-- Bounded recovery helpers (defined below; M.Confirm needs admission checks earlier).
local RC={}
-- Versioned receipt identity, not a different character or invented loadout.
-- Legacy owners cannot interpret this identity and therefore retain their
-- existing other/unknown-owner gate, including their explicit Continue gate.
local function receiptGuid(p)
    if p.attributionFormat~=nil then
        if p.attributionFormat==1 and p.guid==nil and type(p.attributionOwner)=="string"
            and p.attributionOwner~="" then return p.attributionOwner end
        return nil
    end
    return p.guid
end
function RC.active()
    local rc=run and run.rc
    return run and run.running and rc and rc.automatic and (rc.stage=="checking" or rc.stage=="ready")
end
-- Owned scalar phase only: compact rendering must not query active facades.
function RC.phase()
    local rc=run and run.rc;local stage=rc and rc.stage
    if rc and rc.automatic and run.state=="STOPPED" then return nil end
    if stage=="checking" or stage=="ready" or stage=="held" or stage=="refused" then return stage end
end
function RC.kind()
    local rc=run and run.rc
    if rc then return rc.automatic and "automatic" or "manual" end
end
local ensureFrame,heldChoiceHint,cleanEvidence
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function now() return GetTime and GetTime() or 0 end
-- Loading can finish before the first approved run creates its full receipt
-- owner. Retain pacing only from those events: no init, game read, receipt
-- journal or lifecycle epoch is manufactured by this lightweight observer.
RC.worldHoldUntil=0
do
    local left=false
    local hold=CreateFrame("Frame",nil,UIParent)
    hold:RegisterEvent("PLAYER_LEAVING_WORLD");hold:RegisterEvent("PLAYER_ENTERING_WORLD")
    hold:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_LEAVING_WORLD" then left=true
        elseif left then
            left=false;RC.worldHoldUntil=now()+WORLD_SETTLE
            if run then run.worldSettleUntil=math.max(run.worldSettleUntil or 0,RC.worldHoldUntil) end
        end
    end)
end
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
local function write(data,admission)
    local status=writeStatus()
    if status.mode~="durable" then return nil,writeRefusal(status) end
    local o=owner();if not o or not o.UpdateStateV1 then return nil,"Local saved data is not ready. No Orb action will be sent." end
    -- The authorized owner creates an absent row at this explicit write.
    local refused
    local ok=o.UpdateStateV1(function(s)
        refused=nil
        if admission then local valid,why=RC.spendCapacity(admission,s);if not valid then refused=why;return end end
        s.orbRefinement=copy(data)
    end)
    if refused then return nil,refused,"CAPACITY" end
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
        -- A saved file is data, not truth: the raw pick evidence is rebuilt from
        -- its known plain fields only (and bounded) before anything uses it.
        cleanEvidence(run.pending)
        -- See a pick from this moment on, without waiting for a successful read.
        if type(B.CaptureStart)=="function" then pcall(B.CaptureStart) end
        -- and listen to the game's replies passively (the strict check needs them)
        if type(B.TransportStart)=="function" then pcall(B.TransportStart) end
        run.state="RECOVERY";run.reason="An earlier Orb action is unresolved. Nothing will restart. Nexus is checking, read-only, whether its offer is still open."
        run.recovery={kind="CHECKING",observing=false}
        run.spent=run.pending.spent or 0;run.reserved=run.pending.spendConfirmed and 0 or 1;run.limit=run.pending.limit or config.maxOrbs or 0
        run.uncertain=integer(run.pending.uncertain,0,10000) and run.pending.uncertain or 0
        run.historyKnown=false -- Session-only totals cannot be reconstructed from one receipt.
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
        spent=0,reserved=0,uncertain=0,unconfirmedResults=0,revision=0}
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
    local changed=false
    for key,value in pairs(fields) do
        -- false clears a field: pairs() cannot carry a nil value.
        if value==false then value=nil end
        if entry[key]~=value then entry[key]=value;changed=true end
    end
    local log=logOwned()
    if log then
        local spent,reserved=run and run.spent or log.spent,run and run.reserved or log.reserved
        local uncertain,unconfirmed=run and run.uncertain or 0,run and run.unconfirmedResults or 0
        if log.spent~=spent or log.reserved~=reserved or log.uncertain~=uncertain
            or log.unconfirmedResults~=unconfirmed then changed=true end
        log.spent=spent;log.reserved=reserved;log.uncertain=uncertain;log.unconfirmedResults=unconfirmed
        if changed then logTouch(log) end
    end
end
local function logRun(state,reason)
    local log=logOwned()
    if not log then return end
    local spent,reserved=run and run.spent or log.spent,run and run.reserved or log.reserved
    local uncertain,unconfirmed=run and run.uncertain or 0,run and run.unconfirmedResults or 0
    local changed=log.state~=state or log.reason~=reason or log.spent~=spent or log.reserved~=reserved
        or log.uncertain~=uncertain or log.unconfirmedResults~=unconfirmed
    log.state=state;log.reason=reason
    log.spent=spent;log.reserved=reserved;log.uncertain=uncertain;log.unconfirmedResults=unconfirmed
    if changed then logTouch(log) end
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
-- Boundary evidence is never used by action, settlement or Continue gates.
-- Only a new, small receipt gets a durable journal. Existing/future fields are
-- kept untouched; restored receipts collect session-only evidence so a check's
-- receipt and content digest never move because of these diagnostics.
local JD_MAX=8
local JD_EVENTS={receipt=true,pre_call=true,spend_submitted=true,spend_ambiguous=true,spend_rejected=true,
    host_call=true,host_true=true,host_false=true,host_error=true,host_other=true,
    pick_call=true,pick_true=true,pick_false=true,pick_unknown=true,
    select_submitted=true,select_ambiguous=true,select_rejected=true,pick=true,read=true,leave=true,enter=true,logout=true}
local JD_REL={equal=true,one_below=true,lower=true,higher=true,unknown=true}
local JD_OWN={before=true,source_removed=true,neither=true,unknown=true}
local JD_KEYS={event=true,epoch=true,phase=true,charge=true,relation=true,owned=true,offer=true,pick=true,host=true}
local function journalEntry(e)
    if type(e)~="table" or getmetatable(e) then return nil end
    local n=0;for k in pairs(e) do n=n+1;if n>9 or not JD_KEYS[k] then return nil end end
    if not JD_EVENTS[e.event] or not integer(e.epoch,0,65535) or not (e.phase=="l" or e.phase=="r" or e.phase=="w")
        or not JD_REL[e.relation] or not JD_OWN[e.owned] then return nil end
    if e.charge~=nil and not integer(e.charge,0) then return nil end
    for _,k in ipairs({"offer","pick","host"}) do if type(e[k])~="boolean" and e[k]~="unknown" then return nil end end
    local out={};for k,v in pairs(e) do out[k]=v end;return out
end
local function journalList(list)
    if type(list)~="table" or getmetatable(list) then return nil end
    local n=0;for k in pairs(list) do n=n+1;if n>JD_MAX or not integer(k,1,JD_MAX) then return nil end end
    local out={};for i=1,n do local e=journalEntry(rawget(list,i));if not e then return nil end;out[i]=e end
    return out
end
local function journalMeasure(v,depth)
    depth=depth or 1
    if type(v)~="table" or getmetatable(v) or depth>5 then return nil end
    local edges,bytes=0,0
    for k,x in pairs(v) do
        edges=edges+1;bytes=bytes+#tostring(k)
        if type(x)=="table" then
            local e,b=journalMeasure(x,depth+1);if not e then return nil end;edges=edges+e;bytes=bytes+b
        elseif type(x)=="string" then bytes=bytes+#x
        elseif type(x)=="number" or type(x)=="boolean" then bytes=bytes+8
        else return nil end
        if edges>1200 or bytes>28672 then return nil end
    end
    return edges,bytes
end
local function journalBegin(p)
    run.boundary={mode="session_only",reason="receipt_budget",session={},dropped=0,captureFailures=0}
    -- Reserve for the journal, all three maximal raw picks, the remaining live
    -- receipt fields and the complete archive envelope, without raising limits.
    local e,b=journalMeasure(p)
    if not e or e+400>1200 or b+4096>6144 then return end
    local fits,_,withJournal=RC.receiptCapacity(p)
    if not fits or not withJournal then return end
    local state=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
    local archive=state and state.orbRecoveryArchive
    if archive~=nil then
        if type(archive)~="table" or getmetatable(archive) then run.boundary.reason="archive_shape";return end
        local n=0
        for k in pairs(archive) do n=n+1;if n>8 or not integer(k,1,8) then run.boundary.reason="archive_shape";return end end
        for i=1,n do
            local item=rawget(archive,i)
            if type(item)~="table" or getmetatable(item) or item.v~=1 or type(item.id)~="string"
                or type(item.cd)~="string" or type(item.receipt)~="table" then run.boundary.reason="archive_shape";return end
        end
        local ae,ab=journalMeasure(archive)
        if not ae or #archive>=8 or ab+b+4096>28672 then run.boundary.reason="archive_budget";return end
    end
    if p.boundaryJournal~=nil then run.boundary.reason="foreign_journal";return end
    p.boundaryJournal={};run.boundary.owner=p;run.boundary.journal=p.boundaryJournal;run.boundary.mode="durable";run.boundary.reason=nil
end
local function journalRelation(charges,before)
    if not integer(charges,0) or not integer(before,0) then return "unknown" end
    if charges==before then return "equal" end
    if charges==before-1 then return "one_below" end
    return charges<before-1 and "lower" or "higher"
end
local function journalOwned(s,p)
    if not s or not p or receiptGuid(p)~=s.context.guid or type(p.before)~="table" or type(p.removed)~="string" then return "unknown" end
    local before,removed=true,(p.before[p.removed] or 0)>0
    for k,n in pairs(p.before) do
        local actual=s.granted[k] or 0
        if actual~=n then before=false end
        if actual~=n-(k==p.removed and 1 or 0) then removed=false end
    end
    for k,n in pairs(s.granted) do
        if n~=(p.before[k] or 0) then before=false end
        if n~=(p.before[k] or 0)-(k==p.removed and 1 or 0) then removed=false end
    end
    return before and "before" or removed and "source_removed" or "neither"
end
local function journalAppend(list,entry,d)
    if list[#list] and sameValue(list[#list],entry) then return false end
    -- The first two provenance entries stay. Only the recent six are evicted.
    if #list>=JD_MAX then table.remove(list,3);d.dropped=math.min((d.dropped or 0)+1,999) end
    list[#list+1]=entry;return true
end
local function journalFlag(v) if type(v)=="boolean" then return v end;return "unknown" end
local function journalCapture(event,s,p)
        local d=run.boundary
        if not d then
            local why=p.boundaryJournal~=nil and not journalList(p.boundaryJournal) and "foreign_journal"
                or p.restored and "restored_receipt" or "older_receipt"
            d={mode="session_only",reason=why,session={},dropped=0,captureFailures=0}
            run.boundary=d
        end
        if d.owner==p and p.boundaryJournal~=d.journal then
            d.owner=nil;d.mode="session_only";d.reason="foreign_journal"
        end
        local rel=journalRelation(s and s.charges,p.chargesBefore)
        local own=journalOwned(s,p)
        local charge=s and integer(s.charges,0) and s.charges or nil
        local offer,pick,host=journalFlag(s and s.offerPending),journalFlag(s and s.selectInFlight~=nil),journalFlag(s and s.hostPending)
        local last=d.lastRead
        local sampledAt=s and s.at
        if type(sampledAt)~="number" or sampledAt~=sampledAt or sampledAt<0 or sampledAt==math.huge then sampledAt=nil end
        if event=="read" then d.lastReadAt=sampledAt end
        -- Stable recovery/live reads do not allocate a diagnostic row, replace
        -- the snapshot or dirty saved data. Comparisons use the existing read.
        if event=="read" and last and last.epoch==life.epoch and last.phase==life.phase
            and last.charge==charge and last.relation==rel and last.owned==own
            and last.offer==offer and last.pick==pick and last.host==host then return end
        local entry={event=event,epoch=life.epoch,phase=life.phase,charge=s and integer(s.charges,0) and s.charges or nil,
            relation=rel,owned=own,offer=offer,pick=pick,host=host}
        if event=="read" then d.lastRead=entry end
        if s then d.snapshot={chargesBefore=integer(p.chargesBefore,0) and p.chargesBefore or nil,
            chargesNow=integer(s.charges,0) and s.charges or nil,chargeRelation=rel,ownedRelation=own,
            offerPresent=entry.offer,pickInFlight=entry.pick,hostPending=entry.host,epoch=life.epoch,phase=life.phase,at=sampledAt} end
        local list=d.owner==p and not p.restored and p.boundaryJournal or d.session
        if journalAppend(list,entry,d) and d.owner==p and not p.restored then d.unsaved=true end
end
local function journalNote(event,s,p)
    if not p or not JD_EVENTS[event] then return end
    local ok=pcall(journalCapture,event,s,p)
    if not ok then
        if run.boundary then run.boundary.captureFailures=math.min((run.boundary.captureFailures or 0)+1,999) end
    end
end
local function savePending(admission)
    if run.pending then
        local p=copy(run.pending);p.context=nil;p.beforeSnapshot=nil;p.token=nil
        p.spent=run.spent;p.limit=run.limit
        if not p.restored then p.uncertain=(run.uncertain or 0)>0 and run.uncertain or nil end
        if p.attributionAmbiguous or p.attributionChoices or (p.uncertain or 0)>0 then
            if p.attributionFormat==nil then
                p.attributionFormat=1;p.attributionOwner=p.guid;p.guid=nil
            end
        end
        p.since=nil;p.baselineStamp=nil;p.recoverySerial=nil;p.recoveryMatched=nil
        config.pending=p
    else config.pending=nil end
    local d=run.boundary
    local owns=run.pending and d and d.owner==run.pending and run.pending.boundaryJournal==d.journal and not run.pending.restored
    if not owns then return write(config,admission) end
    -- The original receipt is the mandatory write, with ONLY our visit-owned
    -- metadata omitted. A genuine mandatory failure gets no retry and no host
    -- call. Foreign/restored fields never take this path.
    local original=copy(config);original.pending.boundaryJournal=nil
    local priorWritten=d.persistedCount or 0
    d.persisted=nil;d.persistedCount=0
    local ok,err,code=write(original,admission)
    if not ok then d.captureFailures=math.min((d.captureFailures or 0)+1,999);return ok,err,code end
    -- One optional attempt at this existing persistence boundary. A diagnostic
    -- refusal/error cannot turn a verified original receipt into a no-send gate.
    -- It never retries a failed mandatory write, and polling still makes no save.
    local valid=journalList(d.journal)
    local goodCall,good=false,false
    if valid then goodCall,good=pcall(write,config,admission) end
    if goodCall and good then
        d.unsaved=nil;d.persisted=true;d.persistedCount=#d.journal
    else
        d.captureFailures=math.min((d.captureFailures or 0)+1,999)
        d.priorWrittenOmitted=math.min((d.priorWrittenOmitted or 0)+priorWritten,999)
        d.mode="session_only";d.reason=valid and "write_refused" or "invalid_journal"
        d.session=valid or {};d.owner=nil;d.journal=nil;d.unsaved=true
        run.pending.boundaryJournal=nil;config.pending.boundaryJournal=nil
    end
    return true
end
-- Raw pick evidence that the store refused when it was seen is kept in memory
-- (run.pickDirty) and saved at the next pass or lifecycle event. Never fatal, and
-- it changes no run state. Returns true when nothing is left unsaved.
local function flushEvidence()
    if not (run and run.pickDirty) then return true end
    if not run.pending then run.pickDirty=nil;return true end
    local okCall,ok=pcall(savePending)
    if okCall and ok then run.pickDirty=nil end
    return okCall and ok==true
end
local function release()
    if run.token then B.Release(run.token);run.token=nil end
end
local function pause(reason)
    local state=run.state=="STOPPED" and "STOPPED" or run.completed or "PAUSED"
    run.running=false;run.pauseSerial=(run.pauseSerial or 0)+1;setState(state,reason)
    if run.rc and run.rc.automatic and (run.rc.stage=="checking" or run.rc.stage=="ready") then
        run.rc.stage="held";run.rc.step=nil;run.rc.token=nil
    end
    if run.pending and run.pending.logSerial then
        logUpdate(run.pending.logSerial,{state=state=="STOPPED" and "unknown" or "paused",reason=reason})
    end
    logRun(state,reason)
end
local function terminal(state,reason)
    if state=="COMPLETE" or state=="ROLLED_COMPLETE" then run.completed=state end
    run.running=false;setState(state,reason)
    if run.rc and run.rc.automatic and (run.rc.stage=="checking" or run.rc.stage=="ready") then
        run.rc.stage="held";run.rc.step=nil;run.rc.token=nil
    end
    -- A spent-limit stop retains the paused run's ownership for an explicit
    -- increase + Resume. Stop releases it; no resource arrival resumes it.
    -- A settled completion (FINISHED) is not that case: it releases too.
    if not run.pending and state~="LIMIT" then release() end
    logRun(state,reason)
end
-- At the maximum the current receipt must be settled or explicitly archived
-- before ownership can be released. Archived uncertain exposure still counts;
-- the completion text distinguishes it from observed consumption.
local function finishedLimit()
    return not run.pending and (run.reserved or 0)==0 and not config.pending
end
local function reachedLimit(fallbackReason)
    if finishedLimit() then
        local reason=(run.unconfirmedResults or 0)>0
            and ("Finished - approved Orb exposure limit reached. "..(run.unconfirmedResults or 0).." Orb outcome(s) remain unconfirmed. Start a new run to continue.")
            or ("Finished - limit reached. The approved maximum of "..tostring(run.limit).." Orb(s) was used. Start a new run to continue.")
        terminal("FINISHED",reason)
    else
        terminal("LIMIT",fallbackReason or "The approved Orb limit was reached.")
    end
end
-- Defined below (after `binding`/`matches`): whether the assigned Wishlist
-- still matches the run's targets. The former selected-slot body here was
-- overwritten by that definition before any caller ran.
local entriesStillMatch
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
    if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"The maximum cannot change during a run. Stop this run, then start a new run with a higher maximum." end
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
-- A refusal also returns the stage code of its site (readiness diagnostics only).
-- `display` is true only for M.Status: a display-only read (B.Read("display"),
-- see OrbAdapter O.Read). Every action path calls inspect() and reads in full.
local function readState(...)
    local ok,s,err,stage=pcall(B.Read,...)
    if not ok then
        -- This is an actual failed observation, unlike an earlier assignment
        -- or target refusal. Never reuse its pre-failure empty-choice fact.
        if run.postRecovery then RC.postUnknown() end
        if type(Nexus.Errors)=="table" and type(Nexus.Errors.Record)=="function" then
            pcall(Nexus.Errors.Record,"OrbRuntime.StateRead",s)
        end
        return nil,"The current Orb state could not be read. No new action was sent.","state"
    end
    return s,err,stage
end
local function inspect(display)
    local assignment=assigned()
    if assignment.state~="ready" then return nil,assignment.note or "Assign a Wishlist before starting Orb mode.",assignment,"assignment" end
    local targets,err=P.Normalize(config.entries);if not targets then return nil,err,assignment,"targets" end
    local s,e,stage
    if display then s,e,stage=readState("display") else s,e,stage=readState() end
    if not s then return nil,e,assignment,stage end
    local prog=P.Progress(targets,s)
    local sources=P.Sources(targets,s,config.excluded)
    return {targets=targets,s=s,progress=prog,sources=sources,assignment=assignment}
end
-- `m` may be the read that the same display refresh already made. Actions
-- (Prepare, Confirm) always pass nothing and read fresh.
local function preflight(automatic,m,display)
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
    local room,why,list=RC.spendCapacity(nil)
    if not room then return nil,why end
    for _,e in ipairs(list) do if not RC.knownLate(e) then return nil,RC.HISTORY_UNVERIFIED end end
    m.history=RC.historySet(list);m.historyCount=#list
    -- Only the source key differs in these prospective receipts. The longest
    -- approved key bounds all of them without rereading the same archive.
    local longest
    for key in pairs(permitted) do if not longest or #key>#longest then longest=key end end
    local bounded,why
    if display then bounded,why=RC.displayCapacity(longest,m.s,list)
    else bounded,why=RC.receiptCapacity(RC.newReceipt(longest,m.s,1,#list>0)) end
    if not bounded then return nil,why end
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
        binding=binding(m.assignment),limit=limit,created=now(),history=m.history,
        historyToken=#m.history>0 and {} or nil}
    local listed={};for _,s in ipairs(m.sources) do if m.permitted[s.key] then
        listed[#listed+1]={name=s.name,spellId=s.spellId,quality=s.quality,copies=m.permitted[s.key],key=s.key}
    end end
    return {token=approval.token,limit=limit,charges=m.s.charges,sources=listed,targets=copy(m.progress.items),
        name=config.name,recycle=approval.recycle,sourceCopies=m.capacity,
        historyCount=m.historyCount,historyRisk=m.historyCount>0 and RC.HISTORY_RISK or nil,
        historyAcknowledgment=approval.historyToken}
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
    frame:SetScript("OnEvent",function(_,event)
        init()
        if event=="PLAYER_LOGOUT" then run.historyBaseline=nil;RS.historyReview=nil end
        local classifiedEntry=event=="PLAYER_ENTERING_WORLD" and life.phase=="l"
        if event=="PLAYER_LEAVING_WORLD" then life.epoch=(life.epoch+1)%65536;life.phase="l"
        elseif event=="PLAYER_ENTERING_WORLD" then life.epoch=(life.epoch+1)%65536;life.phase="r" end
        journalNote(event=="PLAYER_LEAVING_WORLD" and "leave" or event=="PLAYER_ENTERING_WORLD" and "enter" or "logout",nil,run.pending)
        -- Evidence that could not be saved when it was seen is saved now: a
        -- reload or a logout follows these events.
        flushEvidence()
        if event=="PLAYER_LEAVING_WORLD" and run.pending then
            run.heldReceipt=run.pending;run.heldSince=now();run.heldText=nil;run.heldPriorReason=nil
        end
        if classifiedEntry then
            run.worldSettleUntil=now()+WORLD_SETTLE
            if run.pending and not run.pending.restored then
                run.pending.since=now();run.pending.refreshRequested=false
            end
        end
        -- A lifecycle event alone preserves an untouched restored receipt. New
        -- observed ambiguity may separately migrate its legacy owner envelope.
        if run.pending and run.pending.restored and not run.running then return end
        if run.completed then if run.pending then savePending() end;return end
        -- A loading screen does not revoke this session's approved run. Keep
        -- its owner and reconcile the current action after entering; logout
        -- still ends authorization, and explicit Pause/Stop never sets this.
        if run.running and (event=="PLAYER_LEAVING_WORLD" or classifiedEntry) then
            run.worldRecovering=true;run.worldPausedAt=now()
            setState("WAIT_WORLD","Loading interrupted the approved Orb run. Waiting to reconcile the current choice; no action is repeated.")
            logRun("WAIT_WORLD",run.reason)
            if run.pending then savePending() end
            return
        end
        if run.state=="STOPPED" or run.state=="PAUSED" then
            if run.pending then savePending() end
            return
        end
        if run.running or run.pending then
            run.worldRecovering=nil;pause(SESSION_INTERRUPTED);run.worldPausedAt=now()
            if run.pending then savePending() else release() end
        end
    end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+(dt or 0)
        local slow=run and ((run.pending and run.pending.restored and not run.running
            and now()>=(run.recoveryFastUntil or 0)) or (RS.after and not run.pending))
        if elapsed<(slow and RECOVERY_SLOW_INTERVAL or .2) then return end;elapsed=0
        local ok,err=pcall(M.Pump)
        if not ok then pause("Orb mode stopped after an internal error. Check diagnostics; no automatic repeat will be sent.")
            if Nexus.Errors and Nexus.Errors.Record then pcall(Nexus.Errors.Record,"OrbRuntime",tostring(err)) end
        end
        if run and not run.running and not run.pending and not RS.after then frame:Hide() end
    end)
end
function M.Confirm(token,representedHistory)
    init();local a=approval
    -- Late events that arrived before this new run belong to the old action, not to the run.
    if RS.after then pcall(RC.late) end
    if not a or a.token~=token or now()-a.created>60 then return nil,"The confirmation expired. Review the plan again." end
    if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"An Orb run already owns this action." end
    local m,err=preflight(a.automatic);if not m then return nil,err end
    if not sameContent(a.entries,config.entries) or not B.SameContext(a.model.s.context,m.s.context)
        or not matches(a.binding,m.assignment)
        or a.model.s.grantedKey~=m.s.grantedKey or a.model.s.lockedKey~=m.s.lockedKey
        or a.model.s.charges~=m.s.charges then approval=nil;return nil,"Echoes or resources changed while confirming. Review again." end
    if not sameValue(a.history,m.history) then approval=nil;return nil,RC.HISTORY_CHANGED end
    if a.historyToken and representedHistory~=a.historyToken then return nil,RC.HISTORY_REQUIRED end
    local off,e=turnAutoOff();if not off then return nil,e end
    local tokenOwner,live=B.Acquire(m.s);if not tokenOwner then return nil,live end
    -- Observe from approved Confirm, so a pre-check framed send cannot be
    -- mistaken for an incoming empty response when its echo arrives later.
    if type(B.StartChoiceObserver)=="function" then pcall(B.StartChoiceObserver) end
    run={state="READY",running=true,reason="Approved. Preparing one Orb replacement.",token=tokenOwner,
        targets=copy(a.model.targets),entries=copy(config.entries),remaining=copy(a.sources),excluded=copy(a.excluded),
        recycle=a.recycle,automatic=a.automatic,binding=copy(a.binding),name=config.name,
        limit=a.limit,spent=0,reserved=0,uncertain=0,recoveries=0,unconfirmedResults=0,historyKnown=true,recent={},context=live.context,
        worldSettleUntil=math.max(run.worldSettleUntil or 0,RC.worldHoldUntil),
        historyBaseline={owner=Nexus.Store.CurrentOwnerKey(),guid=live.context.guid,entries=copy(a.history)}}
    -- Counters and the log start only now, when a run is really authorized.
    run.id=(logs.current and (tonumber(logs.current.runId) or 0) or 0)+1
    local owner=writeStatus()
    logBegin({runId=run.id,limit=a.limit,wishlist=config.name,
        character=owner and owner.ownerKey or nil,
        build=type(Nexus.RuntimeBuildLabel)=="function" and Nexus.RuntimeBuildLabel() or nil,
        reason="Approved. Preparing one Orb replacement."})
    approval=nil;ensureFrame();M.Pump();return true
end
function M.Start(value,tracked,representedHistory)
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
        local represented=RC.represented(a,representedHistory)
        if a.historyCount>0 and not represented then return nil,RC.HISTORY_REQUIRED end
        return M.Confirm(a.token,represented and a.historyAcknowledgment or nil)
    end
    if value~=nil then local ok,e=M.SetLimit(value);if not ok then return nil,e end end
    local a,e=M.Prepare("assigned");if not a then return nil,e end
    local represented=RC.represented(a,representedHistory)
    if a.historyCount>0 and not represented then return nil,RC.HISTORY_REQUIRED end
    return M.Confirm(a.token,represented and a.historyAcknowledgment or nil)
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
-- Support visibility only: it decides nothing and no rule reads it. Why loadoutCheck
-- answers CHANGED for this read, named when the hold is FIRST set and kept as an
-- annotation of that moment: a short name and the slot seen then. A hold that was set
-- without one (an earlier build) is never given a cause from a later read, and an
-- original slot that is missing is never filled in.
-- A bound far above any slot id in use (saved builds are few; designed Wishlist slots start at 100).
-- It is not a product limit. A larger value is reported as unreadable. No rule reads it.
local MAX_SLOT=65535
local LOADOUT_CAUSES={NO_ORIGINAL_SLOT=true,SLOT_DIFFERS=true,SLOT_PUSHED=true,SLOT_DIFFERS_UNVERIFIED=true}
-- A whole number in range, with -0 written as 0.
local function slotValue(n)
    if integer(n,0,MAX_SLOT) then return n==0 and 0 or n end
    return nil
end
-- The client clock in whole seconds, 2000-01-01 to 2100-01-01 (UTC), or nil: a missing, failing or
-- implausible clock records no time and changes nothing else. The same bounds are checked again in
-- core/SupportReport.lua (clockText); change both together.
local MIN_EPOCH,MAX_EPOCH=946684800,4102444800
local function epochValue(n) return integer(n,MIN_EPOCH,MAX_EPOCH) and n or nil end
local function wallClock()
    if type(time)~="function" then return nil end
    local ok,t=pcall(time)
    return ok and epochValue(t) or nil
end
local function loadoutChangeCause(s,p)
    if p.originalSlot==nil then return "NO_ORIGINAL_SLOT" end
    local known,slot=s.context.slotKnown,s.context.slot
    -- slotKnown false: a slot pushed before the build-slot data. nil: the client
    -- cannot report slot data, so the compared slot may be its load-time default.
    if known==false then return "SLOT_PUSHED",slot end
    if known==nil then return "SLOT_DIFFERS_UNVERIFIED",slot end
    return "SLOT_DIFFERS",slot
end
-- Raw pick evidence (035) ----------------------------------------------------
-- What the game's SelectPerk callback showed at the moment of a manual pick, saved
-- with the receipt (receipt.picks, at most PICK_MAX entries, the earliest are kept)
-- before any fallible read. It is EVIDENCE: no rule reads it. It is never a
-- selection, it fills no settlement gate (hasChoiceEvidence, finishResult and
-- observeLifecycle ignore it), and a held, unmatched, context-poor or unreadable
-- observation stays only this. Each entry holds numbers, booleans and short texts:
--   id  the Echo the callback named           q   its quality when exactly one card carries it
--   board the raw board "id:q,id:q,id:q"      inb the Echo was on that board
--   m   the board against the recorded offer: offer (exact), ids (same Echoes, quality unreadable),
--       other, none (no readable board), norec (no recorded offer)
--   acc the game's own pick latch held this Echo after the call
--   op  OrbService.IsOfferPending() then      slot, sk  the active slot and whether slot data was received
--   rd  what the contextual observer concluded: ok (recorded), noctx, fail, diff, state, err
--   u   the receipt's own selection fields name this Echo (the immediate pass recorded it)
--   ph, ep  the lifecycle phase and loading epoch (see `life`)    at  client clock    c  identical callbacks merged
-- A load, a loading screen and a reload change nothing here: a local epoch label
-- says when Nexus saw the callback, not whether the server has finished anything.
local PICK_MAX,PICK_COUNT_MAX=3,999
local PICK_RD={ok=true,noctx=true,fail=true,diff=true,state=true,err=true}
local PICK_M={offer=true,ids=true,other=true,none=true,norec=true}
local PICK_PHASE={w=true,l=true,r=true}
local function pickInt(n,min,max) if integer(n,min,max) then return n==0 and 0 or n end return nil end
local function pickBool(v) if v==true or v==false then return v end return nil end
local function pickBoard(v)
    if type(v)=="string" and #v<=40 and v:find("^[%d:%?,]*$") then return v end
    return nil
end
local function cleanPick(e)
    if type(e)~="table" then return nil end
    local out={id=pickInt(e.id,1,2147483647),q=pickInt(e.q,0,255),board=pickBoard(e.board),
        m=PICK_M[e.m] and e.m or nil,acc=pickBool(e.acc),op=pickBool(e.op),slot=pickInt(e.slot,0,MAX_SLOT),
        sk=pickBool(e.sk),rd=PICK_RD[e.rd] and e.rd or nil,u=pickBool(e.u),inb=pickBool(e.inb),
        ph=PICK_PHASE[e.ph] and e.ph or nil,ep=pickInt(e.ep,0,65535),at=epochValue(e.at),
        c=pickInt(e.c,1,PICK_COUNT_MAX) or 1}
    if not out.id and not out.board then return nil end
    return out
end
cleanEvidence=function(p)
    local list={}
    if type(p.picks)=="table" then
        for i=1,PICK_MAX do local e=cleanPick(p.picks[i]);if e then list[#list+1]=e end end
    end
    p.picks=#list>0 and list or nil
    p.pickSeen=pickInt(p.pickSeen,1,PICK_COUNT_MAX)
    p.pickDropped=pickInt(p.pickDropped,1,PICK_COUNT_MAX)
end
local function pickSame(a,b)
    for _,k in ipairs({"id","q","board","m","acc","op","slot","sk","rd","u","inb","ph","ep"}) do
        if a[k]~=b[k] then return false end
    end
    return true
end
-- The raw board against the recorded offer, for the evidence label only.
local function pickRelation(raw,p)
    if not p.offerKey then return "norec" end
    local cards=raw.cards
    if type(cards)~="table" or #cards==0 then return "none" end
    local parts,ids,exact={},{},true
    for i,c in ipairs(cards) do
        ids[i]=tostring(c.id)
        if c.q==nil then exact=false else parts[i]=c.id..":"..c.q..":"..tostring(c.selectable==true) end
    end
    if exact and table.concat(parts,",")==p.offerKey then return "offer" end
    local recorded={}
    for id in tostring(p.offerKey):gmatch("(%d+):%d+:%a+") do recorded[#recorded+1]=id end
    if not exact and table.concat(ids,",")==table.concat(recorded,",") then return "ids" end
    return "other"
end
-- Called by the adapter's hook for every manual SelectPerk callback, after the
-- contextual observer ran. Never throws to the game and never sends anything.
local function onPickRaw(raw)
    if Nexus.OrbRuntime~=M or type(raw)~="table" then return end
    init()
    local p=run and run.pending
    if not p then return end
    local entry=cleanPick({id=raw.id,q=raw.q,board=raw.board,m=pickRelation(raw,p),acc=raw.acc,op=raw.op,
        slot=raw.slot,sk=raw.sk,rd=raw.rd,inb=raw.inb,ph=PICK_PHASE[raw.ph] and raw.ph or life.phase,
        ep=pickInt(raw.ep,0,65535) or life.epoch,at=wallClock(),c=1})
    if not entry then return end
    entry.u=entry.id~=nil and entry.q~=nil and p.choiceObserved==true and p.selectedKey==entry.id..":"..entry.q or false
    local list=type(p.picks)=="table" and p.picks or {}
    p.pickSeen=math.min((tonumber(p.pickSeen) or 0)+1,PICK_COUNT_MAX)
    local merged=false
    for _,e in ipairs(list) do
        if pickSame(e,entry) then e.c=math.min((e.c or 1)+1,PICK_COUNT_MAX);e.at=entry.at or e.at;merged=true;break end
    end
    if not merged then
        if #list<PICK_MAX then list[#list+1]=entry
        else p.pickDropped=math.min((tonumber(p.pickDropped) or 0)+1,PICK_COUNT_MAX) end
    end
    p.picks=list
    journalNote("pick",nil,p)
    -- Saved at once, for a reload or a logout that follows. A refusal, or a store that throws,
    -- keeps it in memory (reported as unsaved) for the next pass and changes nothing else.
    run.pickDirty=true
    local okCall,ok=pcall(savePending)
    if okCall and ok then run.pickDirty=nil end
end
-- A pick that passed every contextual check is recorded by the same pass the
-- restored receipt already gets: a passive pump, now, not at the next timed read.
local function onOwnerChoice()
    if Nexus.OrbRuntime~=M or not (run and run.pending) or run.pending.restored then return end
    pcall(M.Pump,true)
end

-- Read-only record of the settlement requirement that the last attempt did
-- not meet, for the status text. Session only; it authorizes nothing.
local function unmet(gate,detail)
    run.settleGate={gate=gate,detail=detail};return false
end
function RC.pendingComplete(s)
    if run.state~="STOPPED" and run.targets then
        local progress=P.Progress(run.targets,s)
        if progress.rolledMissing==0 then
            terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
                "The observed rolled targets are complete. The last Orb outcome is unresolved; its receipt and exposure are retained. Open Orbs to review whether its explicit checked Continue is eligible. No further Orb will be sent.")
            return true
        end
    end
    return false
end
function RC.resultHold(s,p)
    logUpdate(p.logSerial,{state="unknown",reason="Ownership shows progress, but an earlier unconfirmed attempt could have caused it."})
    RC.pendingComplete(s)
    return unmet("attribution")
end
local function finishResult(s,p)
    run.settleGate=nil
    -- Ownership responses do not identify the originating loadout. Once that
    -- boundary changes, even an exact replacement delta can belong elsewhere.
    -- Keep this uncertainty across Recheck, return-to-slot, and reload.
    local loadout=loadoutCheck(s,p)
    if loadout=="UNKNOWN" then return unmet("loadout-unknown") end
    if loadout=="CHANGED" then
        if not p.loadoutChanged then
            p.loadoutChanged=true
            local cause,seen=loadoutChangeCause(s,p)
            p.loadoutCause=cause;p.loadoutObservedSlot=slotValue(seen);p.loadoutObservedAt=wallClock()
            savePending()
        end
        pause("The original loadout cannot be verified after a loadout change or an incomplete older receipt. Ownership responses do not identify the original loadout. Pending exposure is retained; no retry is allowed.")
        return unmet("loadout")
    end
    -- Neither a new table nor an Orb decrement proves a result. Require the
    -- original offer and a selection observed within that offer's lifecycle.
    if not p.offerKey or not p.selectionAttempted or not p.selectedKey
        or not (p.choiceMayHaveBeenSent or p.choiceObserved)
        or not p.offeredKeys or not p.offeredKeys[p.selectedKey] then
        -- Completion is about actual owned targets, even before this attempt
        -- has a recorded choice. It cannot erase or confirm the current receipt.
        if s.lockedKey==p.lockedKey and RC.archivedDelta(p,s) then
            if not p.attributionAmbiguous then
                p.attributionAmbiguous=true
                local ok,err=savePending();if not ok then pause(err);return false end
            end
            return RC.resultHold(s,p)
        end
        if s.lockedKey==p.lockedKey then RC.pendingComplete(s) end
        return unmet("choice")
    end
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
            if not RC.active() and not RC.pendingComplete(s) then pause("The same-ID, same-quality result is indistinguishable from stale ownership data. The client supplies no correlated completion evidence. Pending exposure is retained; no retry is allowed.") end
        end
        return unmet("same-id")
    end
    -- exact: ownership already shows the recorded choice; only a response newer
    -- than the baseline is missing (recovery may ask for one, read-only).
    if not fresh then return unmet("fresh",{exact=status=="CONFIRMED" and gained==p.selectedKey}) end
    local explained=(status~="CONFIRMED" or gained~=p.selectedKey) and RC.archivedDelta(p,s)
    if (status~="CONFIRMED" or gained~=p.selectedKey) and not explained then
        if not RC.active() and not RC.pendingComplete(s) then pause("Echo ownership does not match the expected replacement. No further Orb will be spent.") end
        return unmet("mismatch")
    end
    local changed,historyError=RC.ambiguity(p,s)
    if historyError then
        if changed then local ok,err=savePending();if not ok then pause(err);return false end end
        pause("Retained Orb history cannot be verified. The receipt and its exposure are kept; no result can be attributed.");return unmet("history")
    end
    if explained and not p.attributionAmbiguous then p.attributionAmbiguous=true;changed=true end
    if changed then local ok,err=savePending();if not ok then pause(err);return false end end
    if p.attributionAmbiguous then
        return RC.resultHold(s,p)
    end
    if not p.spendConfirmed then run.spent=run.spent+1;p.spendConfirmed=true;run.reserved=0 end
    run.recent[#run.recent+1]={removed=p.removed,obtained=gained,at=now()}
    while #run.recent>5 do table.remove(run.recent,1) end
    -- One confirmed result per operation, recorded once even when the receipt
    -- write is retried afterwards.
    logUpdate(p.logSerial,{obtained=gained,state="confirmed",
        confirmedAt=logNow(),reason=run.historyBaseline and #run.historyBaseline.entries>0
            and "Matching ownership replacement observed under the acknowledged current-state baseline; no server action correlation." or false})
    run.pending=nil;run.snap=nil
    if run.rc and run.rc.automatic then run.rc=nil end
    local ok,err=savePending();if not ok then run.pending=p;pause(err);return false end
    RC.clearHeld(p)
    if p.restored then
        run.recovery=nil;if type(B.Unwatch)=="function" then B.Unwatch() end
        terminal("STOPPED","Previous result confirmed. No spending restarted; review a new run explicitly.");return true
    end
    -- Completion ended this approval even if its final receipt was still
    -- unresolved. Settling it releases ownership; neither a changed target
    -- nor a later ownership snapshot may turn the terminal run into Resume.
    if run.completed then
        terminal(run.state=="STOPPED" and "STOPPED" or run.completed,
            "Last replacement confirmed. This Orb run already ended; no spending restarted. Review current targets before approving a new run."
                ..(run.completed=="ROLLED_COMPLETE" and " Orbs cannot change the remaining locked targets." or ""))
        return true
    end
    if run.targetChanged then
        setState(run.state=="STOPPED" and "STOPPED" or "PAUSED",run.historyBaseline and #run.historyBaseline.entries>0
            and "Matching ownership observed under the acknowledged baseline; no server action correlation. Review the new assigned Wishlist before any further approval; usage is unchanged."
            or "Original replacement confirmed. Review the new assigned Wishlist, then Resume; usage is unchanged.")
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
    elseif run.spent+run.reserved+(run.uncertain or 0)>=run.limit and run.state~="STOPPED"
        and finishedLimit() then
        -- The approved maximum is reached and this result settled it. There is
        -- nothing left to resume, so a run the player had paused finishes here
        -- too, instead of asking for an increase or a Stop.
        reachedLimit()
    elseif not run.running then
        setState(run.state=="STOPPED" and "STOPPED" or "PAUSED",run.historyBaseline and #run.historyBaseline.entries>0
            and "Matching ownership observed under the acknowledged baseline; no server action correlation. No next Orb will be spent until you explicitly continue."
            or "Last replacement confirmed; no next Orb will be spent until you explicitly continue.")
        if run.state=="STOPPED" then release() end
    elseif run.spent+run.reserved+(run.uncertain or 0)>=run.limit then reachedLimit()
    else setState("READY",run.historyBaseline and #run.historyBaseline.entries>0
        and "Matching ownership observed under the acknowledged baseline; no server action correlation. Preparing the next approved Orb."
        or "Replacement confirmed. Preparing the next approved Orb.") end
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
                and "A different Echo was chosen than the one Nexus had proposed for this Orb action. Nexus can confirm only the proposed Echo, so it cannot confirm this action. The record and its spending exposure are kept."..NO_EXIT
                or "A different choice was submitted during the pending Orb action. Nexus cannot confirm this action. The record and its spending exposure are kept."..NO_EXIT);return false
        end
        if not p.selectionAttempted then
            p.selectionAttempted=true;p.selectedKey=sel.key;p.selectionStamp=sel.grantStamp;changed=true
        end
        if not p.choiceObserved then p.choiceObserved=true;changed=true end
    end
    -- A history refusal does not discard a genuine observed choice. Result
    -- settlement and any next action independently refuse unknown history.
    local ambiguous=RC.ambiguity(p,s)
    if ambiguous then changed=true end
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
-- A recorded choice alone is never abandonable. This narrow explicit exit
-- requires the actual distinct chosen gain, fresh ownership and original loadout.
-- It proves current ownership, not which uncertain action produced that gain.
function RC.attributionExit(p,s,a)
    if not p or type(p.before)~="table" or p.attributionAmbiguous~=true or not s or not hasChoiceEvidence(p)
        or p.selectedKey==p.removed or loadoutCheck(s,p)~="SAME"
        or receiptGuid(p)~=s.context.guid or s.lockedKey~=p.lockedKey then return false end
    if not RC.memory(receiptGuid(p),p) then return false end
    if not p.restored and (not run.context or not B.SameContext(run.context,s.context)
        or not matches(run.binding,a or assigned())) then return false end
    local stamp
    if p.restored then stamp=p.baselineStamp else stamp=p.selectionStamp or p.beforeStamp end
    local gained,status=P.SingleGain(p.before,p.removed,s.granted)
    return type(stamp)=="number" and s.grantStamp>stamp
        and (s.granted[p.selectedKey] or 0)>(p.before[p.selectedKey] or 0)
        and ((status=="CONFIRMED" and gained==p.selectedKey) or RC.archivedDelta(p,s,true))
        and (p.spendConfirmed==true or s.charges==p.chargesBefore or s.charges==p.chargesBefore-1)
end
function RC.sameChoice(a,b)
    if receiptGuid(a)~=receiptGuid(b) then return false end
    for _,k in ipairs({"lockedKey","originalSlot","offerKey","selectedKey","selectionAttempted",
        "choiceMayHaveBeenSent","choiceObserved","spendConfirmed","attributionAmbiguous"}) do
        if a[k]~=b[k] then return false end
    end
    return sameValue(a.offeredKeys,b.offeredKeys)
end
function RC.clearHeld(p)
    if run.heldReceipt~=p then return end
    run.heldReceipt=nil;run.heldSince=nil;run.heldText=nil;run.heldPriorReason=nil
end
function RC.owedResume(p,s)
    local rc=run.rc
    local owedRefusal=rc and (rc.refusal=="loading_transition" or rc.refusal=="no_empty_choice_reply"
        or rc.refusal=="no_ownership" or rc.refusal=="balance_mismatch"
        or rc.refusal=="late_choice" or rc.refusal=="pending_positive"
        or rc.refusal=="offer_or_action" or rc.refusal=="no_reply"
        or rc.refusal=="state_changed" or rc.refusal=="reply_changed")
    if not (rc and rc.automatic and (rc.stage=="held" or (rc.stage=="refused" and owedRefusal))
        and p and not p.restored and not p.selectionAttempted and p.spendConfirmed==true and s) then return false end
    local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
    return s.offerPending and #s.board==3 and s.boardKey==p.offerKey and s.charges==p.chargesBefore-1
        and s.lockedKey==p.lockedKey and loadoutCheck(s,p)=="SAME" and ownershipMatchesReceipt(s,p)
        and not s.hostPending and s.selectInFlight==nil and not Nexus.GameAdapter.InFlight() and intent==nil
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
        -- A spend already confirmed with this offer does not need the balance
        -- to stay one Orb less (see finishResult): the same recorded offer then
        -- still belongs to the action, and the status names the recorded Echo.
        if sameOffer and (oneOrb or p.spendConfirmed) and hasChoiceEvidence(p) then return "WAIT_RESULT",observing end
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
-- Player-confirmed continuation and bounded live recovery ------------------------
-- The original class is a restored receipt whose spend this client observed, no usable recorded
-- outcome (hasChoiceEvidence is false) and the original offer gone. The player may choose
-- to Continue with an UNCONFIRMED outcome. Continue never settles the old action, never
-- claims a verified Echo result, never refunds, repeats or chooses, never changes the spent
-- count, the run limit or the configured maximum, and sends nothing but the read-only
-- refresh that Recheck already sends. Nothing starts it: only ContinueBegin and
-- ContinueConfirm, called by the player's own clicks, do. The separate live
-- session path below adds an explicit empty-choice response and a two-check
-- allowance; it never restores authorization from a saved receipt.
--
-- THE CHECK (a session-only state machine in run.rc, driven by the passive recovery pump):
--   it needs the passive transport observer (no observer, no Continue: there is no fallback
--   to the game's local pending flag, which is a default, an optimistic count or an omitted
--   field and proves nothing); it asks the game for a refresh, waits for the first charge
--   reply observed after that request began, asks again, and waits for the second; each
--   reply must QUALIFY (see OrbAdapter: exact prefix, whisper, the player's own exact name,
--   three canonical fields), carry an explicit third field equal to 0 and the same balance,
--   and the balance must equal the game's own cache; an ownership push must have been
--   observed after the first request and the game's ownership view must have been replaced.
--   Requests are serialized: the second goes out only after the first reply was observed,
--   and none goes out while an earlier Nexus request has no observed reply, unless that request went
--   unanswered for the whole wait and was given up (a refusal ends the wait). The whole time:
--   an empty board, no pending Orb offer, no pick, no host action, no in-flight action, no
--   Nexus intent; the balance, the rolled and locked Echoes and the slot unchanged; no
--   rejected relevant packet, no choice or pick-result packet, no loading transition.
--   A wait that ends can only REFUSE. A fixed time is never proof of anything.
-- WHAT IT CANNOT SHOW. The protocol has no correlation. A reply is "observed after the refresh
--   began", nothing more. A local epoch rejects local timers, closures and already-observed
--   replies; it cannot identify an older server reply that arrives later. Two such arrivals
--   detect a change; they do NOT prove that no older answer is still on its way, and the
--   texts say so. The owner accepts this residual risk for phase one.
-- THE ARCHIVE. A confirmed Continue moves the saved receipt, unchanged, into the character
--   row's own key orbRecoveryArchive (an array of at most ARCHIVE_MAX entries; a key an
--   older build leaves alone, unlike anything inside orbRefinement) and clears the pending
--   receipt in ONE synchronous store mutation, then verifies the row. Capacity, a malformed
--   or newer-format archive, a receipt too large, a refused or unverified write: refuse,
--   never evict, never repair, never delete. An entry has an idempotent identifier (a digest
--   of what identifies the receipt) and a content digest, so repeating the confirmation adds
--   nothing. The entry keeps apart: the intent (what Nexus intended), the observed (raw pick
--   evidence, inside the receipt), and the resolution (UNCONFIRMED, no confidence).
local ARCHIVE_KEY="orbRecoveryArchive"
local ARCHIVE_MAX,ARCHIVE_EDGES,ENTRY_BYTES,ARCHIVE_BYTES=8,1200,6144,28672
local AUTO_ARCHIVE_MAX,AUTO_ARCHIVE_BYTES=ARCHIVE_MAX-2,ARCHIVE_BYTES-2*ENTRY_BYTES
-- Seconds the check waits for ONE observed answer before it refuses. It only ends a wait.
local RC_WAIT=15
local RC_CONSENT,RC_POLICY=1,"TWO_OBSERVED"
local RC_LATE_MAX,RC_LATE_COUNT=4,99
local RC_LATE_BYTES,RC_LATE_EDGES=512,32
local RC_LATE_KINDS={rejected=true,choice_push=true,pick_result=true,pending_positive=true,reply_unqualified=true,events_lost=true}
M.CONTINUE_WAIT=RC_WAIT
-- A short digest of a canonical text (not a security hash; an identifier only).
local function digest(text)
    local a,b,h=1,0,0
    for i=1,#text do
        local c=text:byte(i)
        a=(a+c)%65521;b=(b+a)%65521;h=(h*31+c)%2147483647
    end
    return string.format("%04x%04x%08x",a,b,h)
end
local function canon(v,out)
    local kind=type(v)
    if kind=="table" then
        local keys={}
        for k in pairs(v) do keys[#keys+1]=k end
        table.sort(keys,function(x,y)
            local tx,ty=type(x),type(y)
            if tx~=ty then return tx<ty end
            if tx=="number" or tx=="string" then return x<y end
            return tostring(x)<tostring(y) -- booleans and anything else: a total order that cannot throw
        end)
        out[#out+1]="{"
        for _,k in ipairs(keys) do
            out[#out+1]=(type(k)=="number" and "#" or "$")..tostring(k).."=";canon(v[k],out);out[#out+1]=";"
        end
        out[#out+1]="}"
    elseif kind=="string" then out[#out+1]="s"..#v..":"..v
    elseif kind=="number" then out[#out+1]=string.format("n%.17g",v)
    elseif kind=="boolean" then out[#out+1]=v and "T" or "F"
    else out[#out+1]="?" end
end
local function canonText(v) local out={};canon(v,out);return table.concat(out) end
-- What identifies the spend this receipt records: constant from its creation, so the
-- identifier survives the later fields (offer, evidence, flags) and a repeated archive.
function RC.identity(p)
    if type(p)~="table" then return nil end
    return digest(canonText({removed=p.removed,chargesBefore=p.chargesBefore,before=p.before,
        lockedKey=p.lockedKey,originalSlot=p.originalSlot,logSerial=p.logSerial,beforeStamp=p.beforeStamp}))
end
-- Edges, bytes and the deepest level of a plain table.
local function measure(v,level)
    level=level or 1
    local edges,bytes,depth=0,0,level
    if type(v)~="table" then return 0,0,level end
    for k,x in pairs(v) do
        edges=edges+1;bytes=bytes+#tostring(k)
        local kind=type(x)
        if kind=="string" then bytes=bytes+#x
        elseif kind=="number" or kind=="boolean" then bytes=bytes+8
        elseif kind=="table" then
            local e,b,d=measure(x,level+1)
            edges=edges+e;bytes=bytes+b;depth=math.max(depth,d)
        end
    end
    return edges,bytes,depth
end
-- Automatic continuation leaves two entries and two worst-case entry byte
-- budgets available for the explicit Continue path. Existing records are never
-- rewritten or evicted; manual Continue still has the original finite caps.
-- Reserve the complete bounded late-evidence envelope inside existing caps.
-- Existing annotations consume their reservation; opaque fields are measured too.
function RC.entryBudget(entry)
    local edges,bytes,depth=measure(entry)
    local annotation={late=entry.late,lateN=entry.lateN}
    local usedEdges,usedBytes=measure(annotation)
    return edges+math.max(0,RC_LATE_EDGES-usedEdges),
        bytes+math.max(0,RC_LATE_BYTES-usedBytes),depth,bytes
end
function RC.retainedBudget(entry)
    local _,budget,depth,actual=RC.entryBudget(entry)
    return math.max(actual,math.min(ENTRY_BYTES,budget)),actual
end
function RC.autoCapacity(list,bytes,adding)
    local total=bytes or 0
    for _,e in ipairs(list) do total=total+RC.retainedBudget(e) end
    if #list+(adding and 1 or 0)>AUTO_ARCHIVE_MAX or total>AUTO_ARCHIVE_BYTES
        or (not adding and (#list>=AUTO_ARCHIVE_MAX or total>=AUTO_ARCHIVE_BYTES)) then return false end
    return true
end
-- The archive of a character row: "ok" with the list, "full", "future" (an entry from a newer
-- format: it is not touched) or "malformed". Reading changes nothing.
local function archiveOf(row)
    local a
    if type(row)=="table" then a=row[ARCHIVE_KEY] end
    if a==nil then return "ok",{} end
    if type(a)~="table" or getmetatable(a) then return "malformed" end
    local n=0
    for k in pairs(a) do
        if type(k)~="number" or k<1 or k~=math.floor(k) then return "malformed" end
        n=n+1
    end
    if n~=#a then return "malformed" end
    for i=1,#a do
        local e=a[i]
        if type(e)~="table" or getmetatable(e) or type(e.v)~="number" then return "malformed" end
        if e.v>1 then return "future" end
        if e.v~=1 or type(e.id)~="string" or type(e.cd)~="string" or type(e.receipt)~="table" then return "malformed" end
    end
    if #a>=ARCHIVE_MAX then return "full",a end
    return "ok",a
end
-- The archive state from the Store's read copy (never the live row).
function RC.archiveInfo()
    local state=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
    local st,list=archiveOf(state)
    -- Only a validated contiguous supported container supplies a record count.
    -- Present malformed/future values are unreadable, not absent or empty;
    -- Lua's length of a sparse table is not an established retained count.
    local count="invalid"
    if type(state)=="table" then
        if state[ARCHIVE_KEY]==nil then count=0
        elseif (st=="ok" or st=="full") and integer(#list,0,99) then count=#list
        elseif st=="future" then
            -- Counting established outer rows does not interpret their future
            -- payload or permit Continue. Check every row, including ones the
            -- version refusal did not reach, and never use sparse-table length.
            local raw=state[ARCHIVE_KEY];local n,valid=0,true
            for k,e in pairs(raw) do
                n=n+1
                if n>99 or not integer(k,1,99) or type(e)~="table" or getmetatable(e)
                    or not integer(e.v,1) or (e.v==1 and (type(e.id)~="string" or type(e.cd)~="string" or type(e.receipt)~="table")) then
                    valid=false;break
                end
            end
            if valid then for i=1,n do if rawget(raw,i)==nil then valid=false;break end end end
            if valid then count=n end
        end
    end
    return st,list or {},count
end
-- Rebuild bounded attribution memory from this owner's retained archive. It
-- outlives approvals and reloads without conferring any action authority.
-- Unknown history is a refusal, never an empty history or a repair operation.
function RC.memory(guid,p,row)
    local st,list
    if row then st,list=archiveOf(row) else st,list=RC.archiveInfo() end
    if st~="ok" and st~="full" then return nil end
    if #list>ARCHIVE_MAX then return nil end
    local baseline=p and not p.restored and run.historyBaseline or nil
    local slot=p and "receipt" or "review"
    local cached=RC.memoryCaches and RC.memoryCaches[slot]
    -- Store.State is a per-content defensive snapshot. Its nested values are
    -- still writable by readers, so compare the archive to our private copy as
    -- well. This avoids canonicalization/allocations without trusting identity.
    -- Atomic writes always provide their actual row and bypass this cache.
    if not row and cached and cached.guid==guid and cached.baseline==baseline
        and cached.owner==Nexus.Store.CurrentOwnerKey() and sameValue(cached.archive,list) then
        RC.memoryCache=not cached.invalid and cached or nil
        if cached.invalid then return nil end
        return cached.attempts,cached.list
    end
    -- Bound every entry before retaining even a negative content verdict.
    -- An oversized, deep or non-plain archive is never kept by this cache.
    local total=0
    for _,e in ipairs(list) do
        local edges,bytes=journalMeasure(e)
        if not edges or bytes>ENTRY_BYTES then return nil end
        local _,_,depth=measure(e);total=total+bytes
        if depth>4 or total>ARCHIVE_BYTES then return nil end
    end
    -- Validate and retain our own list and nested entries. A reader can keep
    -- and edit an older public snapshot even after Store invalidates it.
    if not row then list=copy(list) end
    local function invalid()
        if not row then
            RC.memoryCaches=RC.memoryCaches or {}
            RC.memoryCaches[slot]={guid=guid,baseline=baseline,owner=Nexus.Store.CurrentOwnerKey(),archive=list,invalid=true}
            RC.memoryCache=nil
        end
        return nil
    end
    local attempts={}
    for _,e in ipairs(list) do
        if (e.kind~="AUTO_UNCONFIRMED" and e.kind~="ACK_UNCONFIRMED")
            or type(e.resolution)~="table" or e.resolution.outcome~="UNCONFIRMED" or e.resolution.confidence~="NONE" then return invalid() end
        local p=e.receipt;local who=receiptGuid(p)
        if type(who)~="string" or type(p.removed)~="string" or not p.removed:match("^%d+:%d+$")
            or type(p.before)~="table" or not integer(p.before[p.removed],1)
            or (p.selectedKey~=nil and (type(p.selectedKey)~="string" or not p.selectedKey:match("^%d+:%d+$"))) then return invalid() end
        for k,v in pairs(p.before) do
            if type(k)~="string" or not k:match("^%d+:%d+$") or not integer(v,0) then return invalid() end
        end
        if e.id~=RC.identity(p) or e.cd~=digest(canonText(p)) then return invalid() end
        if who==guid then
            attempts[#attempts+1]={removed=p.removed,selected=hasChoiceEvidence(p) and p.selectedKey or nil,entry=e}
        end
    end
    if baseline then
        if baseline.owner~=Nexus.Store.CurrentOwnerKey() or baseline.guid~=guid then return nil end
        local covered={}
        for _,old in ipairs(baseline.entries) do
            local found
            for _,e in ipairs(list) do
                if sameValue(old,RC.historyEntry(e)) and RC.knownLate(e) then found=e;break end
            end
            if not found then return nil end
            covered[found]=true
        end
        local effective={}
        for _,a in ipairs(attempts) do if not covered[a.entry] then effective[#effective+1]=a end end
        attempts=effective
    end
    if not row then
        cached={guid=guid,baseline=baseline,owner=Nexus.Store.CurrentOwnerKey(),
            archive=list,attempts=attempts,list=list}
        RC.memoryCaches=RC.memoryCaches or {}
        RC.memoryCaches[slot]=cached;RC.memoryCache=cached
    end
    return attempts,list
end
RC.HISTORY_RISK="unconfirmed; Start accepts current Echoes baseline; late results may arrive."
RC.HISTORY_REQUIRED="Review the displayed unconfirmed-history baseline before approving a new Orb run."
RC.HISTORY_CHANGED="Retained Orb history changed. Review the new baseline before starting."
RC.HISTORY_UNVERIFIED="Retained Orb history cannot be verified. No new Orb action was sent."
function RC.historyEntry(e)
    local out=copy(e);out.late=nil;out.lateN=nil;return out
end
function RC.historySet(list)
    local cached=RC.memoryCache
    if cached and cached.list==list and cached.history then return cached.history end
    local out={};for _,e in ipairs(list) do out[#out+1]=RC.historyEntry(e) end
    if cached and cached.list==list then cached.history=out end
    return out
end
function RC.knownLate(e)
    if e.lateN~=nil and not integer(e.lateN,0,RC_LATE_COUNT) then return false end
    if e.late==nil then return true end
    if type(e.late)~="table" or getmetatable(e.late) or #e.late>RC_LATE_MAX then return false end
    local n=0
    for k,v in pairs(e.late) do
        n=n+1;if not integer(k,1,RC_LATE_MAX) or type(v)~="table" or getmetatable(v) or not RC_LATE_KINDS[v.k] then return false end
        for field,x in pairs(v) do
            if field=="k" then
            elseif field=="nr" then if type(x)~="boolean" then return false end
            elseif field=="w" then if type(x)~="string" or #x>64 then return false end
            elseif field=="ep" or field=="ch" or field=="pd" then if not integer(x,0) then return false end
            else return false end
        end
    end
    return n==#e.late
end
-- One complete capped exit, plus remaining optional growth of every old entry.
function RC.newReceipt(key,s,serial,acknowledged)
    local p={before=copy(s.granted),lockedKey=s.lockedKey,removed=key,chargesBefore=s.charges,
        originalSlot=s.context.slot,logSerial=serial,beforeStamp=s.grantStamp,
        beforeSelectionSerial=s.selectionSerial,since=now(),guid=s.context.guid,spendConfirmed=false}
    if acknowledged then p.attributionFormat=1;p.attributionOwner=p.guid;p.guid=nil end
    return p
end
-- Display capacity reuses only the byte/shape verdict for the same validated
-- archive and complete prospective receipt inputs. Actions never use it.
function RC.displayCapacity(key,s,list)
    local cached=RC.displayCapacityCache
    if cached and cached.list==list and cached.key==key and cached.granted==s.grantedKey
        and cached.locked==s.lockedKey and cached.guid==s.context.guid and cached.slot==s.context.slot
        and cached.charges==s.charges and cached.stamp==s.grantStamp and cached.selection==s.selectionSerial then
        return cached.bounded,cached.why
    end
    local bounded,why=RC.receiptCapacity(RC.newReceipt(key,s,1,#list>0))
    RC.displayCapacityCache={list=list,key=key,granted=s.grantedKey,locked=s.lockedKey,
        guid=s.context.guid,slot=s.context.slot,charges=s.charges,stamp=s.grantStamp,
        selection=s.selectionSerial,bounded=bounded,why=why}
    return bounded,why
end
function RC.receiptCapacity(p)
    -- 400 edges / 4096 bytes bound the supported journal (8 flat rows),
    -- three raw picks, offer/choice/loadout fields and archive envelope.
    -- Add the full 32-edge / 512-byte optional late envelope reservation.
    local base=copy(p);base.since=nil;base.boundaryJournal=nil
    local edges,bytes=journalMeasure(base)
    if not edges then
        return nil,"This Orb receipt cannot reserve its complete bounded exit record. No new Orb action was sent."
    end
    if edges+400+RC_LATE_EDGES<=ARCHIVE_EDGES and bytes+4096+RC_LATE_BYTES<=ENTRY_BYTES then return true,nil,true end
    -- The optional eight-row journal already consumes part of the established
    -- 400-edge / 4096-byte future envelope. When it cannot fit, reserve the same
    -- mandatory envelope with that journal omitted and keep diagnostics in
    -- session memory. These are the longest valid values of every journal field.
    local budget=RC.journalMaximum
    if not budget then
        local peak={boundaryJournal={}}
        for i=1,JD_MAX do peak.boundaryJournal[i]={event="select_ambiguous",epoch=65535,phase="w",charge=1000000,
            relation="one_below",owned="source_removed",offer="unknown",pick="unknown",host="unknown"} end
        local e,b=journalMeasure(peak);budget={edges=e,bytes=b};RC.journalMaximum=budget
    end
    if edges+400-budget.edges+RC_LATE_EDGES<=ARCHIVE_EDGES
        and bytes+4096-budget.bytes+RC_LATE_BYTES<=ENTRY_BYTES then return true,nil,false end
    return nil,"This Orb receipt cannot reserve its complete bounded exit record. No new Orb action was sent."
end
function RC.spendCapacity(p,row)
    local _,list=RC.memory(p and receiptGuid(p) or (run.context and run.context.guid),p,row)
    if not list then return nil,RC.HISTORY_UNVERIFIED end
    local cached=not row and RC.memoryCache
    local total=cached and cached.list==list and cached.retainedBytes
    if not total then
        total=ENTRY_BYTES
        for _,e in ipairs(list) do total=total+RC.retainedBudget(e) end
        if cached and cached.list==list then cached.retainedBytes=total end
    end
    if #list>=ARCHIVE_MAX or total>ARCHIVE_BYTES then
        return nil,"Retained Orb history has no reserved space for another unresolved outcome. No new Orb action was sent; ordinary rolling remains available."
    end
    if p then local bounded,why=RC.receiptCapacity(p);if not bounded then return nil,why end end
    return true,nil,list
end
function RC.represented(plan,fact)
    if plan.historyCount==0 then return true end
    local reviewed=RS.historyReview;local a=approval
    return reviewed and fact==reviewed.token and a and sameValue(reviewed.history,a.history)
        and reviewed.charges==a.model.s.charges and reviewed.granted==a.model.s.grantedKey
        and reviewed.locked==a.model.s.lockedKey and B.SameContext(reviewed.context,a.model.s.context)
        and matches(reviewed.binding,a.model.assignment)
end
function RC.review(m)
    local old=RS.historyReview
    if not old or not sameValue(old.history,m.history) or old.charges~=m.s.charges
        or old.granted~=m.s.grantedKey or old.locked~=m.s.lockedKey
        or not B.SameContext(old.context,m.s.context) or not matches(old.binding,m.assignment) then
        RS.historyReview={token={},history=copy(m.history),charges=m.s.charges,
            granted=m.s.grantedKey,locked=m.s.lockedKey,context=m.s.context,binding=binding(m.assignment)}
    end
    return RS.historyReview.token
end
function RC.ambiguity(p,s)
    local history=RC.memory(receiptGuid(p),p)
    if not history then
        local changed=not p.attributionAmbiguous;p.attributionAmbiguous=true
        return changed,"history"
    end
    local changed=false
    -- Persist possible targets before a target is chosen. Observed and own
    -- selections then share exactly the same decision, also after a reload.
    for _,a in ipairs(history) do if a.removed==p.removed then
        if not a.selected then
            if not p.attributionAmbiguous then p.attributionAmbiguous=true;changed=true end
        elseif not p.selectedKey then
            if not p.attributionChoices then p.attributionChoices={} end
            if not p.attributionChoices[a.selected] then p.attributionChoices[a.selected]=true;changed=true end
        elseif a.selected==p.selectedKey and not p.attributionAmbiguous then p.attributionAmbiguous=true;changed=true end
    end end
    if p.selectedKey and p.attributionChoices and p.attributionChoices[p.selectedKey] and not p.attributionAmbiguous then
        p.attributionAmbiguous=true;changed=true
    end
    return changed
end
-- Match whole snapshot deltas to a nonempty subset of at most eight retained
-- attempts. Pair/source evidence explains uncertainty only; it never confirms
-- any archived or current operation. Source-only receipts may explain positive
-- gains only after their actual removal is present in the snapshot.
function RC.archivedDelta(p,s,currentGain)
    if type(p)~="table" or type(p.before)~="table" then return false end
    if sameCounts(p.before,s.granted) then return false end
    local history=RC.memory(receiptGuid(p),p)
    if not history or #history==0 then return false end
    local slot=currentGain and "gain" or "normal"
    RC.deltaCache=RC.deltaCache or {}
    local cached=RC.deltaCache[slot]
    if cached and cached.receipt==p and cached.history==history and cached.granted==s.grantedKey
        and cached.removed==p.removed and cached.selected==p.selectedKey
        and sameValue(cached.before,p.before) then return cached.result end
    local keys,changes,unknownSources={},{},{}
    for k in pairs(p.before) do keys[k]=true end
    for k in pairs(s.granted) do keys[k]=true end
    keys[p.removed]=true;if p.selectedKey then keys[p.selectedKey]=true end
    for _,a in ipairs(history) do
        changes[a.removed]=0;keys[a.removed]=true
        if a.selected then changes[a.selected]=0;keys[a.selected]=true
        else unknownSources[a.removed]=0 end
    end
    local unknown=0
    local function matchesDelta(mode)
        if mode==2 and (not p.selectedKey or p.selectedKey==p.removed) then return false end
        local sum=0
        for k in pairs(keys) do
            local expected=(p.before[k] or 0)+(changes[k] or 0)
            if mode>0 and k==p.removed then expected=expected-1 end
            if mode==2 and k==p.selectedKey then expected=expected+1 end
            if expected<0 then return false end
            local delta=(s.granted[k] or 0)-expected
            if delta<0 then return false end
            local sources=unknownSources[k] or 0
            -- Source-only uncertainty needs an observable net removal. A
            -- zero-net historical result cannot explain this receipt's change.
            if sources>0 and delta>=sources then return false end
            sum=sum+delta
        end
        return sum==unknown
    end
    local result=false;local floor=math.floor
    for mask=1,2^#history-1 do
        for k in pairs(changes) do changes[k]=0 end
        for k in pairs(unknownSources) do unknownSources[k]=0 end
        unknown=0;local n=mask
        for _,a in ipairs(history) do
            if n%2==1 then
                changes[a.removed]=changes[a.removed]-1
                if a.selected then changes[a.selected]=changes[a.selected]+1
                else unknown=unknown+1;unknownSources[a.removed]=(unknownSources[a.removed] or 0)+1 end
            end
            n=floor(n/2)
        end
        if currentGain then
            if matchesDelta(2) then result=true;break end
        elseif matchesDelta(0) or matchesDelta(1) or matchesDelta(2) then result=true;break end
    end
    if s.grantedKey then RC.deltaCache[slot]={receipt=p,history=history,granted=s.grantedKey,
        removed=p.removed,selected=p.selectedKey,before=copy(p.before),result=result} end
    return result
end
local function liveRow()
    local status=writeStatus()
    if status.mode~="durable" then return nil,status end
    local key=Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey()
    local row=key==status.ownerKey and type(NexusDB)=="table" and type(NexusDB.chars)=="table" and NexusDB.chars[key] or nil
    if type(row)~="table" then return nil,status end
    return row,status
end
local function slotOf(s) return slotValue(s.context.slot) end
local function relation(charges,before)
    if not integer(before,0) then return "unknown" end
    if charges==before-1 then return "one_below" end
    if charges==before then return "equal" end
    if charges<before-1 then return "lower" end
    return "higher"
end
-- The facts that must not move between the start of the check, its end and the confirmation.
local function baseOf(s)
    return {charges=s.charges,granted=s.grantedKey,locked=s.lockedKey,slot=slotOf(s),slotKnown=s.context.slotKnown}
end
local function sameBase(a,b)
    return a.charges==b.charges and a.granted==b.granted and a.locked==b.locked and a.slot==b.slot and a.slotKnown==b.slotKnown
end
local function firstAfter(rc,ord)
    for _,r in ipairs(rc.seen) do if r.ord>ord then return r end end
    return nil
end
-- Why the player cannot start a check (or nil), from what the last passive read showed.
function RC.eligible(p,snap)
    if not p then return false,"no_receipt" end
    local attribution=snap and snap.attribution==true
    if not p.restored and not attribution then return false,"not_restored" end
    if run.running then return false,"running" end
    if p.spendConfirmed~=true and not attribution then return false,"spend_unconfirmed" end
    if hasChoiceEvidence(p) and not attribution then return false,"choice_recorded" end
    if type(snap)~="table" then return false,"unreadable" end
    if receiptGuid(p)~=snap.guid then return false,"other_character" end
    if snap.open then return false,"offer_open" end
    local st=type(B.TransportStatus)=="function" and B.TransportStatus() or nil
    if not (st and st.started) then
        local okT,started=false,false
        if type(B.TransportStart)=="function" then okT,started=pcall(B.TransportStart) end
        if not (okT and started==true) then return false,"no_observer" end
    end
    return true,nil
end
local function noteAttempt(rc,outcome,reason)
    local log=RS.log or {}
    RS.log=log
    log[#log+1]={n=rc.serial,outcome=outcome,reason=reason,step=rc.step,ep=rc.life,
        replies=#rc.seen,req=rc.req2 and 2 or (rc.req1 and 1 or 0),
        r1=rc.r1 and {ord=rc.r1.ord,nf=rc.r1.nf,pd=rc.r1.pending,ch=rc.r1.charges,dl=rc.r1.delta} or nil,
        r2=rc.r2 and {ord=rc.r2.ord,nf=rc.r2.nf,pd=rc.r2.pending,ch=rc.r2.charges,dl=rc.r2.delta} or nil,
        lo=rc.lo,slot=rc.base and rc.base.slot,orig=rc.orig,rel=rc.rel,balance=rc.base and rc.base.charges,
        fpC=rc.base and rc.base.granted and digest(rc.base.granted),fpL=rc.base and rc.base.locked and digest(rc.base.locked),
        rid=rc.rid,v=RC_CONSENT,policy=rc.automatic and "SESSION_BOUNDED_TWO" or RC_POLICY,ph=life.phase}
    while #log>4 do table.remove(log,1) end
end
function RC.refuse(rc,reason)
    if rc.stage=="refused" and rc.refusal==reason then return end
    rc.stage="refused";rc.refusal=reason;rc.token=nil;rc.step=nil
    if rc.automatic then
        local why=RC.liveReason(reason)
        pause("Bounded Orb recovery stopped. "..why.." The outcome is still unconfirmed; its record and exposure are kept. No spend or choice was repeated.")
        if not rc.admitted and run.rc==rc then
            if reason=="own_choice_request" or reason=="choice_request_failed" or reason=="no_choice_observer" then
                run.recoveryCapabilityRefused=reason
            end
            run.rc=nil;run.recoveryUnavailable={receipt=run.pending,reason=reason}
        end
    end
    -- A request that went unanswered for the whole wait is given up: the next check may send its own.
    -- (A late answer to it is indistinguishable from an answer to the next request: arrival order is not a
    -- correlation, the limit stated in the check's notes at the top of this block.)
    if reason=="no_reply" then RS.reqMark=nil end
    noteAttempt(rc,"refused",reason)
end
-- Is an earlier Nexus refresh request still without any observed charge reply (this epoch)?
function RC.outstanding()
    local m=RS.reqMark
    if type(m)~="table" or type(B.TransportStatus)~="function" then return false end
    if m.epoch~=B.TransportStatus().epoch then return false end
    local list=B.TransportSince(m.ord)
    if not list then return false end
    for _,r in ipairs(list) do if r.op==1220 then return false end end
    return true
end
local function requestRefresh(withChoice)
    local ok,why,mark=B.RequestRefresh(withChoice)
    if type(mark)=="table" then mark.at=now();RS.reqMark=mark end
    return ok,why,mark
end
local TAINT_AT_BEGIN={16,540,542,1000}
local TAINT_FINAL={1220,18,16,540,542,1000}
local function tainted(st,ops)
    for _,op in ipairs(ops) do
        if st.bad[op] and st.bad[op]>(st.good[op] or 0) then return op end
    end
    return nil
end
-- Every condition that must hold at every step, and again at the confirmation. Returns a
-- refusal code or nil. It reads the game's cache only now, on a pass after the packets arrived.
function RC.check(s,p,rc,a)
    if not s then return "unreadable" end
    if rc.attribution or rc.automatic then a=a or assigned() end
    local st=B.TransportStatus()
    if life.epoch~=rc.life or st.epoch~=rc.tepoch then return "loading_transition" end
    if not st.started then return "no_observer" end
    if not p or run.pending~=p or RC.identity(p)~=rc.rid then return "receipt_changed" end
    if rc.automatic then
        if not s then return "unreadable" end
        if p.restored or not run.running or not run.token or loadoutCheck(s,p)~="SAME" then return "receipt_changed" end
        if s.autoAccept then return "auto_accept" end
        if not st.choiceObserver or st.ownFramed~=rc.ownFramed then return "own_choice_request" end
        if rc.req1 and st.ownBare~=rc.req1.ownBare then return "own_choice_request" end
    elseif run.running or (rc.attribution and not RC.attributionExit(p,s,a))
        or (not rc.attribution and (not p.restored or p.spendConfirmed~=true or hasChoiceEvidence(p))) then return "receipt_changed" end
    -- The packets first: they name the cause precisely (a reply with a pending offer also
    -- opens the game's own local flag, and must not be reported as "something is open").
    local list=B.TransportSince(rc.scanned)
    if not list then return "transport_overflow" end
    for _,r in ipairs(list) do
        rc.scanned=r.ord
        if r.epoch~=rc.tepoch then return "loading_transition" end
        if r.cls=="R" then return "rejected_packet" end
        if r.op==16 then
            if rc.automatic and r.cls=="A" and r.emptyChoice==true and not r.seg and not r.why
                and rc.req1 and r.ord>rc.req1.ord then rc.emptyChoice=r.ord
            else return "late_choice" end
        end
        if r.op==1000 then return "late_result" end
        if r.op==18 then
            if rc.req1 and r.ord>rc.req1.ord then rc.seen18=true end
        elseif r.op==1220 then
            if r.cls~="Q" then return "reply_unqualified" end
            if r.pending>0 then return "pending_positive" end
            -- a reply that reports a change in the count is not a quiet answer
            if r.delta~=0 then return "reply_changed" end
            local first=rc.seen[1]
            if first and r.charges~=first.charges then return "reply_changed" end
            rc.seen[#rc.seen+1]={ord=r.ord,charges=r.charges,delta=r.delta,pending=r.pending,nf=r.nf,epoch=r.epoch}
        end
    end
    if not s then return "unreadable" end
    if receiptGuid(p)~=s.context.guid then return "receipt_changed" end
    local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
    if s.offerPending or #s.board>0 or s.hostPending or s.selectInFlight~=nil
        or Nexus.GameAdapter.InFlight() or intent~=nil then return "offer_or_action" end
    if s.choiceShape~="checked" and s.choiceShape~="unknown" then return "choice_unreadable" end
    if rc.automatic and Nexus.GameAdapter.RivalDetected() then return "rival" end
    if not sameBase(baseOf(s),rc.base) then return "state_changed" end
    if rc.context and not B.SameContext(rc.context,s.context) then return "receipt_changed" end
    if rc.binding and not sameValue(rc.binding,binding(a)) then return "receipt_changed" end
    return nil
end
local function refusalOf(reason) return reason end
-- One step of the check. Called by the passive recovery pass; never sends anything but the
-- read-only refresh.
local function advanceStep(s,p,a)
    local rc=run and run.rc
    if not rc or (rc.stage~="checking" and rc.stage~="ready") then return end
    local reason=RC.check(s,p,rc,a)
    if reason then return RC.refuse(rc,reason) end
    if rc.stage=="ready" then return end
    run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW
    local t=now()
    if rc.step=="req1" then
        if RC.outstanding() then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_reply") end
            return
        end
        local ok,why,mark=requestRefresh(rc.automatic)
        if not ok or type(mark)~="table" then
            if rc.automatic and not rc.admitted then
                if why=="own_choice_request" or why=="choice_request_failed" or why=="no_choice_observer" then
                    run.recoveryCapabilityRefused=why
                end
                if not run.running or run.rc~=rc then return end
                run.rc=nil;run.recoveryUnavailable={receipt=p,reason=why or "request_failed"}
                if type(mark)=="table" then p.refreshRequested=true;p.since=t end
                setState(p.selectionAttempted and "WAIT_RESULT" or "WAIT_OFFER",RC.liveReason(why))
                return
            end
            return RC.refuse(rc,why or "request_failed")
        end
        if rc.automatic and not rc.admitted then
            if not run.running or run.rc~=rc then return end
            rc.admitted=true;run.recoveries=(run.recoveries or 0)+1
        end
        rc.req1=mark;rc.step="wait1";rc.stepAt=t
        return
    end
    if rc.step=="wait1" then
        rc.r1=firstAfter(rc,rc.req1.ord)
        if not rc.r1 then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_reply") end
            return
        end
        rc.step="req2";rc.stepAt=t
    end
    if rc.step=="req2" then
        -- also before the second request: a request of the player's (Recheck) may be unanswered
        if RC.outstanding() then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_reply") end
            return
        end
        -- The choice was requested once at req1. Do not create another
        -- unanswered choice query while accepting its earlier response.
        local ok,why,mark=requestRefresh()
        if not ok or type(mark)~="table" then return RC.refuse(rc,why or "request_failed") end
        rc.req2=mark;rc.step="wait2";rc.stepAt=t
        return
    end
    if rc.step=="wait2" then
        rc.r2=firstAfter(rc,rc.req2.ord)
        if not rc.r2 then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_reply") end
            return
        end
        rc.step="settle";rc.stepAt=t
    end
    if rc.step=="settle" then
        -- The game's own cache must show what was observed (the evaluation reads it only now,
        -- after the game's handler had its turn), and its ownership view must have been
        -- replaced after the first request began.
        if s.charges~=rc.r2.charges then return RC.refuse(rc,"balance_mismatch") end
        if not (rc.seen18 and s.grantStamp>rc.stamp0) then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_ownership") end
            return
        end
        if rc.automatic and not rc.emptyChoice then
            if t-rc.stepAt>RC_WAIT then RC.refuse(rc,"no_empty_choice_reply") end
            return
        end
        if tainted(B.TransportStatus(),TAINT_FINAL) then return RC.refuse(rc,"observer_tainted") end
        rc.token={serial=rc.serial,v=RC_CONSENT}
        rc.stage="ready";rc.step=nil;rc.stepAt=t
        noteAttempt(rc,"ready",nil)
    end
end
-- One step at a time: a synchronous pass inside a request must not send it twice.
function RC.advance(s,p,a)
    if RS.busy then return end
    RS.busy=true
    local ok,err=pcall(advanceStep,s,p,a)
    RS.busy=nil
    if not ok then error(err,0) end
end
-- An active check cannot go on without a read.
function RC.unreadable()
    local rc=run and run.rc
    if rc and (rc.stage=="checking" or rc.stage=="ready") then RC.refuse(rc,"unreadable") end
end
-- The text of each state. Plain statements: what was observed, what Continue does, and what
-- stays uncertain. None of it says a result was verified.
local RC_INTRO="An earlier Orb action has a spend observed by this client (one Orb fewer with its offer; the game reports no server confirmation of it) and no recorded outcome, and its offer is gone. Continue lets you go on without that outcome. First Nexus checks the game's current state read-only: it asks the game twice for the Orb count (and for your Echoes) and waits for each answer. No spend and no choice is sent, only those read-only questions. You then confirm, or cancel."
local RC_CHECKING="Checking the game's current state. Nexus asked the game for the Orb count (and for your Echoes) and waits for an answer observed after that request began; it asks a second time after the first. No spend and no choice is sent, only these read-only questions. Any change in the game, or a loading screen, cancels this check."
local RC_CONFIRM="Continue with an unconfirmed Orb outcome? The earlier Orb action counts %d of its approved %d Orb(s) as spent. Nexus did not see which Echo, if any, you received, and the game gives no way to check. If you continue: the spent count stays; the original record is saved unchanged; nothing is refunded, repeated or chosen; Nexus stops blocking rolling; a new Orb run needs its own approval and every normal check. Risk you accept: Nexus cannot prove that the server is finished with the old action. Two answers that arrived after Nexus asked do not prove that no older answer is still on its way. A late result would show up as an ordinary change, and Nexus will not link it to the old record."
local RC_DONE="Continued with an unconfirmed outcome. The earlier Orb action is saved unchanged in the archive. Observed spend stays counted and unknown spend exposure stays unknown. Nothing was refunded, repeated or chosen. A new Orb run needs its own approval and every normal check."
local RC_REFUSALS={
    no_receipt="There is no unresolved Orb action.",
    archive_reserved="Automatic recovery history limit reached. Two entry slots and their space are reserved for explicit recovery; existing records are retained.",
    no_empty_choice_reply="No usable empty-choice answer was observed. The choice remains unknown; the pending record and exposure are retained.",
    auto_accept="The game automatic acceptance setting changed. Automatic recovery stopped with its pending record retained.",
    own_choice_request="This client cannot distinguish its own choice request from an empty answer. Automatic recovery stopped with its record retained.",
    choice_unreadable="The current Echo choice is unreadable. Automatic recovery stopped with its record retained.",
    rival="Another Echo picker is active. Automatic recovery stopped with its record retained.",
    not_restored="This action belongs to this session. Explicit Continue requires either passive recovery after reload or a stopped attribution-ambiguous action with a fresh exact distinct chosen gain actually owned.",
    running="An Orb run is active. Pause or stop it first.",
    spend_unconfirmed="Continue is not available for this record."..UNOBSERVED,
    choice_recorded="A choice is recorded for the earlier Orb action. Wait for its matching result. An attribution-ambiguous action has an explicit exit only when fresh ownership shows its exact distinct chosen gain; the flag alone supplies no exit.",
    unreadable="The game's current state cannot be read right now. Nothing was changed. Try again in a moment.",
    other_character="The earlier Orb action belongs to another character.",
    offer_open="An Orb or Echo offer is open in the game. Finish it in the game first; Continue starts only when no offer is open.",
    no_observer="This client does not let Nexus observe the game's replies, so Continue is not available. Nothing was changed.",
    observer_tainted="A game packet that Nexus could not accept may have changed the game's cached offer or slot. A reload usually clears it. Nothing was changed.",
    loading_transition="A loading screen started or ended, so this check was cancelled. Nothing was changed. Start the check again once the game is ready.",
    receipt_changed="The earlier Orb action's record changed, so this check was cancelled. Nothing was changed.",
    offer_or_action="Something is open or in progress in the game (an offer, a choice or an action). Nothing was changed. Finish it, then check again.",
    state_changed="Your Orb count, Echoes or loadout changed during the check, so it was cancelled. Nothing was changed. Check again when nothing is changing.",
    transport_overflow="Too many game messages arrived during the check. Nothing was changed. Check again.",
    rejected_packet="A game message that Nexus could not accept arrived during the check, so it was cancelled. Nothing was changed.",
    late_choice="The game sent an Echo offer during the check. Resolve it in the game. Nothing was changed.",
    late_result="The game sent a pick result during the check, so it was cancelled. Nothing was changed. Check again.",
    reply_unqualified="An answer about the Orb count was missing a field, malformed or not accepted, so the check cannot show that no Orb offer is pending. Nothing was changed.",
    pending_positive="The game reports Orb offer(s) still pending. Resolve them in the game's offer window. No spend and no choice was sent.",
    reply_changed="An answer about the Orb count reported a change, or two answers disagree, so the check was cancelled. Nothing was changed. Check again.",
    balance_mismatch="The answer about the Orb count does not match what the game shows, so the check was cancelled. Nothing was changed.",
    no_reply="No answer was observed in time. Nothing was changed. Use Check in the Continue window to check again.",
    no_ownership="No fresh answer about your Echoes was observed in time. Nothing was changed. Use Check in the Continue window to check again.",
    request_failed="The required refresh requests did not all complete. Partial replies do not allow recovery; the pending record is retained.",
    refresh_unavailable="This client cannot request the required Orb count and Echo ownership refresh.",
    charge_refresh_failed="The Orb count refresh raised an error. The check stopped and the pending record is retained.",
    ownership_refresh_failed="The Echo ownership refresh failed after the Orb count was requested. That outstanding request is retained; no later query was sent.",
    choice_query_unavailable="This client cannot request the current Echo choice; no recovery was authorized.",
    choice_request_failed="The Echo choice request raised an error; the pending record is retained.",
    no_choice_observer="The outgoing Echo choice request cannot be observed safely; no recovery was authorized.",
    archive_full="The saved list of continued Orb actions is full. Nothing was changed and nothing was deleted.",
    archive_future="The saved list of continued Orb actions was written by a newer version and is kept unchanged. Nothing was changed.",
    archive_malformed="The saved list of continued Orb actions is not readable and is kept unchanged. Nothing was changed.",
    entry_too_large="The record of the earlier Orb action is too large to archive. Nothing was changed.",
    write_failed="The record could not be saved safely. Nothing was changed. Try again.",
    stale_token="This confirmation is no longer current. Nothing was changed.",
    not_ready="The check is not ready to confirm. Nothing was changed.",
}
function RC.archiveExitRefusal()
    local state=RC.archiveInfo()
    if state~="ok" then return RC_REFUSALS["archive_"..state] end
end
function RC.text(rc,eligibleReason)
    if rc and rc.stage=="done" then return RC_DONE end
    if rc and rc.stage=="refused" then return RC_REFUSALS[rc.refusal] or RC_REFUSALS.write_failed end
    if (rc and rc.attribution) or (not eligibleReason and run.snap and run.snap.attribution and not run.running) then
        local text="Your fresh Echo ownership shows the distinct chosen gain, but an earlier unconfirmed action could have caused it. This action remains UNCONFIRMED. Explicit Continue ends this old run and archives its original receipt unchanged, with confidence NONE. "
            .."Observed spent Orbs stay counted; unknown spend exposure stays unknown, without a refund or another charge. No spend, choice or automatic Resume is sent. Ordinary rolling is released only after the checked archive saves. A new Orb run needs new approval. "
            .."The check asks read-only for the Orb count and Echoes twice and requires quiet unchanged state. Those arrivals do not prove that no older reply is still on its way. "
        if rc and rc.stage=="ready" then return text.."Confirm this unconfirmed exit?" end
        if rc and rc.stage=="checking" then return text.."Checking; wait for both observed answers." end
        return text.."Choose Check, then explicitly confirm, or cancel."
    end
    if rc and rc.stage=="ready" then return RC_CONFIRM:format(tonumber(run.spent) or 0,tonumber(run.limit) or 0) end
    if rc and rc.stage=="checking" then return RC_CHECKING end
    if eligibleReason then return RC_REFUSALS[eligibleReason] end
    return RC_INTRO
end
function RC.liveReason(reason)
    local causes={
        no_reply="No usable charge answer was observed in time.",no_ownership="No usable Echo ownership answer was observed in time.",
        no_empty_choice_reply="No usable empty-choice answer was observed; the choice remains unknown.",
        own_choice_request="This client cannot distinguish its own choice request from an empty answer.",
        no_choice_observer="The outgoing choice request cannot be observed safely.",no_observer="The game reply observer is unavailable.",
        choice_query_unavailable="This client cannot request the current Echo choice.",choice_request_failed="The current Echo choice request raised an error.",
        charge_refresh_failed="The Orb count refresh raised an error.",ownership_refresh_failed="The Echo refresh failed after the Orb count was requested.",
        refresh_unavailable="The Orb count or Echo refresh is unavailable.",auto_accept="The game's automatic Echo acceptance is no longer known off.",
        archive_reserved="Automatic recovery history capacity is reserved: two of eight entries and their space remain for explicit recovery. Waiting or reload does not free this finite space.",
        archive_full="The eight-entry recovery archive is full. Waiting or reload does not free space; retained records are not evicted.",archive_future="A newer recovery archive format is retained unchanged.",
        archive_malformed="The recovery archive is unreadable and retained unchanged.",write_failed="The pending record cannot be saved durably.",
        loading_transition="A loading transition cancelled the check.",late_choice="An Echo offer arrived; finish that offer in the game, or use Resume if it is offered for this unchosen action.",
        pending_positive="The game reports a pending Orb offer; finish it in the game.",offer_or_action="An offer, native choice latch or other game action is active; finish it in the game.",
        late_result="A pick result arrived during the check.",state_changed="The Orb balance, Echoes or loadout changed during the check.",
        reply_changed="The observed Orb answers changed or disagreed.",observer_tainted="An unusable game packet prevents a quiet check.",
        rejected_packet="An unusable game packet arrived during the check.",transport_overflow="The bounded reply history overflowed.",
        unreadable="The current game state cannot be read.",receipt_changed="The action record or its owner changed.",
        choice_unreadable="The current Echo choice is unreadable.",rival="Another Echo picker is active.",
        entry_too_large="The unresolved record exceeds the finite archive entry limits.",balance_mismatch="The answer differs from the current Orb balance.",
        reply_unqualified="The Orb answer cannot establish that no offer is pending.",request_failed="The required refresh could not complete.",
    }
    return (causes[reason] or "The current game state could not be verified.")
        .." No automatic retry is available for this check. Wait for the actual result, resolve any native offer, or Stop. A reload keeps passive recovery; open Orbs to see whether explicit Continue is eligible."
end
-- The player starts the check. Idempotent while one is running.
function M.ContinueBegin()
    init()
    local p=run.pending
    local rc=run.rc
    if rc and rc.automatic and run.running then return nil,"not_restored" end
    if p and p.attributionAmbiguous and not run.running then
        local astate=RC.archiveInfo()
        if astate~="ok" then return nil,"archive_"..astate end
    end
    if rc and (rc.stage=="checking" or rc.stage=="ready") and run.pending and RC.identity(p)==rc.rid then return true,rc.stage end
    local okR,s=pcall(B.Read)
    if not okR or not s then
        if p and p.restored then run.rc={serial=RS.serial,stage="refused",refusal="unreadable",seen={}} end
        return nil,"unreadable"
    end
    local attribution=RC.attributionExit(p,s)
    local ok,reason=RC.eligible(p,{guid=s.context.guid,open=s.offerPending or #s.board>0,attribution=attribution})
    if not ok then
        if p and not (rc and rc.automatic) then run.rc={serial=RS.serial,stage="refused",refusal=reason,seen={}} end
        return nil,reason
    end
    local function early(code)
        RS.serial=RS.serial+1
        if not (rc and rc.automatic) then run.rc={serial=RS.serial,stage="refused",refusal=code,seen={}} end
        return nil,code
    end
    local row=select(1,liveRow())
    local astate=row and archiveOf(row) or nil
    if row==nil then return early("write_failed") end
    if astate~="ok" then return early("archive_"..astate) end
    local st=B.TransportStatus()
    if tainted(st,TAINT_AT_BEGIN) then return early("observer_tainted") end
    RS.serial=RS.serial+1
    rc={serial=RS.serial,stage="checking",step="req1",life=life.epoch,tepoch=st.epoch,scanned=st.ord,
        at=now(),stepAt=now(),seen={},stamp0=s.grantStamp,rid=RC.identity(p),base=baseOf(s),orig=slotValue(p.originalSlot),
        lo=loadoutCheck(s,p),rel=relation(s.charges,p.chargesBefore),attribution=attribution,
        context=s.context,binding=attribution and binding(assigned()) or nil}
    run.rc=rc
    run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW
    ensureFrame()
    RC.advance(s,p)
    return true,run.rc.stage
end
function M.ContinueCancel()
    init()
    local rc=run.rc
    if rc and rc.automatic then return false end
    if rc and (rc.stage=="checking" or rc.stage=="ready" or rc.stage=="refused") then
        if rc.stage~="refused" then noteAttempt(rc,"cancelled",nil) end
        run.rc=nil
    end
    return true
end
-- What the owner can read about Continue: eligibility, the stage, the token the player
-- confirms, the text, and the archive. Read-only; it reads no game state (the recovery pass
-- keeps the last snapshot) and changes nothing.
function M.ContinueView()
    init()
    local p=run.pending
    local rc=run.rc
    local liveRecovery=rc and rc.automatic==true and (run.running or not (run.snap and run.snap.attribution))
    local liveStage=liveRecovery and rc.stage or nil
    if liveRecovery then rc=nil end
    -- A check whose receipt is gone or is another one is over (the recovery pass may not run
    -- again for it): it must not show as running.
    if rc and (rc.stage=="checking" or rc.stage=="ready") and (not p or RC.identity(p)~=rc.rid) then
        RC.refuse(rc,"receipt_changed")
    end
    local ok,reason=RC.eligible(p,run.snap)
    local astate,_,count=RC.archiveInfo()
    if p and p.attributionAmbiguous and not run.running and astate~="ok" then ok=false;reason="archive_"..astate end
    local v={eligible=ok,reason=reason,liveRecovery=liveRecovery,liveStage=liveStage,stage=rc and rc.stage or "idle",step=rc and rc.step or nil,
        liveRefusal=liveRecovery and run.rc.refusal or nil,
        refusal=rc and rc.refusal or nil,token=rc and rc.stage=="ready" and rc.token or nil,
        archive={state=astate,count=count,capacity=ARCHIVE_MAX},explanation=p~=nil and not run.running and (p.restored==true or ok)}
    if rc and rc.stage=="ready" then
        v.facts={charges=rc.base.charges,recorded=p and p.chargesBefore,relation=rc.rel,replies=#rc.seen}
    end
    v.text=RC.text(rc,not ok and reason or nil)
    return v
end
-- The entry that the archive keeps. Plain data; no name, no identity, no raw packet.
local function buildEntry(saved,p,s,rc)
    local pickN,pickMatching,pickUsed=0,0,0
    if type(saved.picks)=="table" then
        for _,e in ipairs(saved.picks) do
            pickN=pickN+1
            if type(e)=="table" then
                if e.m=="offer" then pickMatching=pickMatching+1 end
                if e.u==true then pickUsed=pickUsed+1 end
            end
        end
    end
    local st=B.TransportStatus()
    local function reply(r) return {ord=r.ord,charges=r.charges,delta=r.delta,pending=r.pending,nf=r.nf,epoch=r.epoch} end
    local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
    local entry={v=1,id=RC.identity(saved),cd=digest(canonText(saved)),kind="ACK_UNCONFIRMED",at=wallClock(),
        receipt=saved,spent=saved.spent,limit=saved.limit,
        intent={key=saved.selectedKey,sent=saved.choiceMayHaveBeenSent==true,observed=saved.choiceObserved==true},
        observed={picks=pickN,matching=pickMatching,used=pickUsed},
        resolution={outcome="UNCONFIRMED",confidence="NONE"},
        consent={v=RC_CONSENT,policy=rc.automatic and "SESSION_BOUNDED_TWO" or RC_POLICY,serial=rc.serial},
        pre={req1=rc.req1.ord,req2=rc.req2.ord,r1=reply(rc.r1),r2=reply(rc.r2),extra=math.max(0,#rc.seen-2),
            balance=s.charges,rel=relation(s.charges,saved.chargesBefore),slot=slotOf(s),slotKnown=s.context.slotKnown,
            origSlot=slotValue(saved.originalSlot),lo=loadoutCheck(s,p),
            fpC=digest(s.grantedKey),fpL=digest(s.lockedKey),
            offer=s.offerPending==true,board=#s.board,host=s.hostPending==true,
            flight=Nexus.GameAdapter.InFlight()==true,intent=intent~=nil,
            ph=life.phase,ep=life.epoch,tep=rc.tepoch,
            -- counters of the strict path since the load, and the note that arrival order is no correlation
            obs={Q=st.counts.Q,A=st.counts.A,R=st.counts.R,note="uncorrelated",
                identity=st.rejects.identity,sender=st.rejects.sender,channel=st.rejects.channel,
                segmented=st.rejects.segmented,third_absent=st.rejects.third_absent,
                fields_extra=st.rejects.fields_extra,malformed=st.rejects.malformed,range=st.rejects.range}},
        post={balance=s.charges,fpC=digest(s.grantedKey),fpL=digest(s.lockedKey),slot=slotOf(s),ord=st.ord}}
    return entry
end
-- Move the saved receipt into the archive and clear the pending receipt in ONE store
-- mutation, then verify the row. Nothing changes unless every precondition holds.
function RC.archive(rc,s,p)
    if run.pickDirty then return nil,"write_failed" end
    local row=liveRow()
    if not row then return nil,"write_failed" end
    local saved=type(row.orbRefinement)=="table" and row.orbRefinement.pending or nil
    if type(saved)~="table" or RC.identity(saved)~=rc.rid then return nil,"receipt_changed" end
    -- The saved receipt must still be what the session knows and what the consent text said: the
    -- class, the spent count and the limit (a save that failed earlier can leave it behind).
    if saved.spent~=run.spent or saved.limit~=run.limit
        or (not rc.automatic and not rc.attribution and (saved.spendConfirmed~=true or hasChoiceEvidence(saved)))
        or (rc.attribution and (not RC.sameChoice(saved,p) or saved.attributionAmbiguous~=true
            or not hasChoiceEvidence(saved) or not RC.attributionExit(p,s))) then
        return nil,"receipt_changed"
    end
    local astate,list=archiveOf(row)
    if astate=="future" then return nil,"archive_future" end
    if astate=="malformed" then return nil,"archive_malformed" end
    local entry=buildEntry(copy(saved),p,s,rc)
    if rc.attribution then entry.uncertain=run.reserved or 0;entry.observed.gain=true end
    if rc.automatic then
        entry.kind="AUTO_UNCONFIRMED";entry.uncertain=run.reserved or 0
        entry.pre.emptyChoice=rc.emptyChoice
    end
    -- Existing explicit receipts keep their original raw exit limits. The
    -- future late-evidence reserve is an admission rule for automatic work,
    -- not a new reason to strand a legacy receipt whose exit still fits.
    local edges,bytes,depth=measure(entry)
    if rc.automatic then edges,bytes,depth=RC.entryBudget(entry) end
    if edges>ARCHIVE_EDGES or bytes>ENTRY_BYTES or depth>4 then return nil,"entry_too_large" end
    local exists=false
    for _,e in ipairs(list) do if e.id==entry.id and e.cd==entry.cd then exists=true end end
    if not exists then
        if astate=="full" then return nil,"archive_full" end
        local total=bytes
        for _,e in ipairs(list) do
            local _,retained=measure(e)
            total=total+(rc.automatic and RC.retainedBudget(e) or retained)
        end
        if total>ARCHIVE_BYTES then return nil,"archive_full" end
        if rc.automatic and not RC.autoCapacity(list,bytes,true) then return nil,"archive_reserved" end
    end
    local o=owner()
    if not o or type(o.UpdateStateV1)~="function" then return nil,"write_failed" end
    -- Only the pending receipt is cleared, in place: every other saved field (also one this build does
    -- not know) stays exactly as it is.
    local previousArchive,previousOrb=copy(row[ARCHIVE_KEY]),copy(row.orbRefinement)
    local expectedOrb=copy(previousOrb);expectedOrb.pending=nil
    local written=false;local atomicRefusal
    local okCall,okUpdate=pcall(o.UpdateStateV1,function(r)
        written=false;atomicRefusal=nil
        -- Revalidate the same pending and archive in the actual atomic write.
        -- A changed row is refused before either field is touched.
        if not sameValue(r[ARCHIVE_KEY],previousArchive) or not sameValue(r.orbRefinement,previousOrb) then
            atomicRefusal="receipt_changed";return
        end
        local read,current=pcall(B.Read)
        local finalReason
        if read then finalReason=RC.check(current,p,rc) else finalReason="unreadable" end
        if life.phase~="w" then finalReason="loading_transition" end
        if finalReason then atomicRefusal=finalReason;return end
        local a=r[ARCHIVE_KEY]
        if a==nil then a={} end
        if rc.automatic and not exists and not RC.autoCapacity(a,bytes,true) then
            atomicRefusal="archive_reserved";return
        end
        if not exists then a[#a+1]=copy(entry) end
        r[ARCHIVE_KEY]=a
        if type(r.orbRefinement)=="table" then r.orbRefinement.pending=nil end
        written=true
    end)
    if atomicRefusal then return nil,atomicRefusal end
    local after=liveRow()
    local good=okCall and okUpdate and written and after==row and type(after.orbRefinement)=="table"
        and after.orbRefinement.pending==nil and sameValue(after.orbRefinement,expectedOrb)
    if good then
        local found=false
        for _,e in ipairs(after[ARCHIVE_KEY] or {}) do
            if type(e)=="table" and e.id==entry.id and e.cd==entry.cd and (exists or sameValue(e,entry)) then found=true end
        end
        good=found
    end
    if not good then
        -- Put back what was there. A refusal leaves the row as it was.
        pcall(o.UpdateStateV1,function(r) r[ARCHIVE_KEY]=previousArchive;r.orbRefinement=previousOrb end)
        return nil,"write_failed"
    end
    return true,entry
end
-- This session's approved run may accept two uncertain outcomes. Every check
-- uses the same quiet charge/ownership proof as Continue plus an explicit
-- empty-choice reply observed after asking. It never resubmits an old command.
-- A reload never reconstructs this authorization.
function RC.beginLive(s,p,a)
    if run.recoveryCapabilityRefused then return false,run.recoveryCapabilityRefused end
    if (run.recoveries or 0)>=RECOVERY_LIMIT then
        pause("The two automatic Orb recoveries for this approved run are used. The last outcome remains unresolved; its record and exposure are kept. Stop, then use explicit Continue if its observed-gain check is eligible, or reload for passive recovery.");return true
    end
    local available,why=B.RecoveryAvailable()
    if not available then return false,why or "no_choice_observer" end
    if not B.StartChoiceObserver() then return false,"no_choice_observer" end
    local ok,started=pcall(B.TransportStart)
    if not ok or started~=true then return false,"no_observer" end
    local st=B.TransportStatus()
    local row=liveRow();local astate,list=archiveOf(row)
    if not row or run.pickDirty then return false,"write_failed" end
    if astate~="ok" then return false,"archive_"..astate end
    if tainted(st,TAINT_AT_BEGIN) then return false,"observer_tainted" end
    if s.choiceShape~="checked" and s.choiceShape~="unknown" then return false,"choice_unreadable" end
    if st.ownFramedAt and now()-st.ownFramedAt<=RC_WAIT then return false,"own_choice_request" end
    if not RC.autoCapacity(list,ENTRY_BYTES,true) then return false,"archive_reserved" end
    RS.serial=RS.serial+1
    run.rc={automatic=true,serial=RS.serial,stage="checking",step="req1",life=life.epoch,tepoch=st.epoch,
        scanned=st.ord,at=now(),stepAt=now(),seen={},stamp0=s.grantStamp,rid=RC.identity(p),ownFramed=st.ownFramed,
        base=baseOf(s),context=s.context,binding=binding(a or assigned()),
        orig=slotValue(p.originalSlot),lo=loadoutCheck(s,p),rel=relation(s.charges,p.chargesBefore)}
    setState("RECOVERY","Checking the current choice before a bounded Orb recovery. The last outcome is unconfirmed; no command is repeated.")
    logRun("RECOVERY",run.reason)
    RC.advance(s,p,a)
    return true
end
function RC.live(s,p,a)
    local rc=run.rc
    if not rc or not rc.automatic then return false end
    if not run.running then return false end
    RC.advance(s,p,a)
    if rc.stage~="ready" then return true end
    local reason=RC.check(s,p,rc,a)
    if reason then RC.refuse(rc,reason);return true end
    local ok,entry=RC.archive(rc,s,p)
    if not ok then RC.refuse(rc,entry);return true end
    -- Preserve unknown spend exposure separately from observed one-Orb
    -- decrements. Neither an archive nor a later success proves this result.
    run.uncertain=(run.uncertain or 0)+(run.reserved or 0)
    run.unconfirmedResults=(run.unconfirmedResults or 0)+1
    logUpdate(p.logSerial,{state="unknown",reason="Retained without a confirmed result after a bounded recovery."})
    -- Retain the validated choice permission through the next actual spend.
    -- Start scanning at the last checked arrival, not after the archive write:
    -- a callback during that write may already have invalidated the quiet state.
    run.postRecovery={life=rc.life,tepoch=rc.tepoch,scanned=rc.scanned,choice=true,
        ownBare=rc.req1.ownBare,ownFramed=rc.ownFramed,charges=s.charges,
        locked=s.lockedKey,context=s.context,binding=copy(run.binding)}
    config.pending=nil;run.pending=nil;run.snap=nil;run.reserved=0;run.rc=nil;run.recycleKey=nil;run.settleGate=nil
    RC.clearHeld(p)
    run.recoveryNotice="Recovered past "..run.unconfirmedResults.." unconfirmed Orb outcome(s). Earlier results may still arrive. All attempts remain within your approved maximum; completion uses your observed Echoes."
    setState("READY",run.recoveryNotice)
    logRun("READY",run.reason)
    return true
end
-- A quiet recovery check is not a reusable permission after newer activity.
-- This session-only permit ends at the next submitted command; it is never
-- saved, never starts another query and never renews exposure/source allowances.
function RC.postUnknown()
    local p=run.postRecovery;if not p then return end
    p.choice=false
    -- Unknown is not classification. Keep the last classified ordinal so a
    -- later successful read must still examine every intervening event.
end
function RC.postCheck(s,a)
    local p=run.postRecovery;if not p then return true end
    if p.revoked then return false,p.revoked,true end
    local function revoke(reason) p.revoked=reason;return false,reason,true end
    if not matches(p.binding,a or assigned()) or not B.SameContext(p.context,s.context)
        or s.charges~=p.charges or s.lockedKey~=p.locked then
        return revoke("The approved recovery context, balance or locked Echoes changed before the next Orb. Stop and review a new run.")
    end
    local st=B.TransportStatus()
    if type(st)~="table" then error("Recovery status unavailable") end
    if life.epoch~=p.life or st.epoch~=p.tepoch then
        return revoke("Loading invalidated the recovery check before the next Orb. Stop and review a new run.")
    end
    if not st.started or not st.choiceObserver or st.ownBare~=p.ownBare or st.ownFramed~=p.ownFramed then
        return revoke("A newer choice request or changed observer invalidated the recovery check. Stop and review a new run.")
    end
    local list=B.TransportSince(p.scanned)
    if type(list)~="table" then return revoke("Recovery observations were lost before the next Orb. Stop and review a new run.") end
    for _,e in ipairs(list) do
        p.scanned=e.ord
        if e.epoch~=p.tepoch then return revoke("A newer loading epoch invalidated the recovery check.") end
        if e.op==16 then
            -- A newer exact empty reply can replace an uncertain choice fact;
            -- all other current guards must still pass below.
            p.choice=e.cls=="A" and e.emptyChoice==true and not e.seg and not e.why
        elseif e.op==1000 then p.choice=false
        elseif e.cls=="R" or (e.op==1220 and (e.cls~="Q" or e.pending~=0 or e.delta~=0 or e.charges~=p.charges)) then
            return revoke("New game state could not preserve the recovery check. Stop and review a new run.")
        end
    end
    local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
    if s.choiceShape=="invalid" or s.offerPending or #s.board>0 or s.hostPending or s.selectInFlight~=nil
        or Nexus.GameAdapter.InFlight() or intent~=nil or s.autoAccept or Nexus.GameAdapter.RivalDetected() then p.choice=false end
    if p.choice then return true end
    return false,"Recovery needs a fresh empty-choice reply after newer activity. Resolve any open offer in the game, or Stop and approve a new run. No new Orb is sent."
end
function RC.postReady(s,a)
    if not run.postRecovery then return true end
    local ok,ready,reason,fatal=pcall(RC.postCheck,s,a)
    if not ok then
        RC.postUnknown();ready=false
        reason="Recovery observations are unavailable. Resolve any open offer in the game, or Stop and approve a new run. No new Orb is sent."
    end
    if ready then run.postRecovery.waitSince=nil;run.postRecoveryHeld=nil;return true end
    local p=run.postRecovery;p.waitSince=p.waitSince or now();run.postRecoveryHeld=true
    if fatal or now()-p.waitSince>=RC_WAIT then pause(reason)
    else setState("RECOVERY",reason) end
    return false,reason
end
function M.ContinueConfirm(token)
    init()
    local rc=run.rc
    if rc and rc.automatic then return nil,"not_restored" end
    if rc and rc.stage=="done" and token~=nil and rc.doneToken==token then return true,"already" end
    if not rc or type(token)~="table" or rc.token~=token then return nil,"stale_token" end
    if rc.stage~="ready" then return nil,"not_ready" end
    local p=run.pending
    local okR,s=pcall(B.Read)
    if not okR then s=nil end
    local reason=RC.check(s,p,rc)
    if not reason and life.phase~="w" then reason="loading_transition" end
    if reason then RC.refuse(rc,reason);return nil,reason end
    local ok,result=RC.archive(rc,s,p)
    if not ok then
        -- A refused or unverified save keeps the check: the same token can be confirmed again.
        if result=="archive_full" or result=="archive_future" or result=="archive_malformed"
            or result=="entry_too_large" or result=="receipt_changed" then RC.refuse(rc,result) end
        return nil,result
    end
    -- The saved side is done; now the session side.
    config.pending=nil
    if rc.attribution then
        run.uncertain=(run.uncertain or 0)+(run.reserved or 0)
        run.unconfirmedResults=(run.unconfirmedResults or 0)+1
        logUpdate(p.logSerial,{state="unknown",reason="Observed gain retained with attribution unconfirmed by explicit consent."})
    end
    run.reserved=0
    run.pending=nil;run.snap=nil;run.recovery=nil;run.settleGate=nil;run.autoRefreshAt=nil;run.pickDirty=nil
    RC.clearHeld(p)
    if type(B.Unwatch)=="function" then B.Unwatch() end
    local st=B.TransportStatus()
    -- Late events are recorded on this entry for the rest of the session, also during a new run. If the
    -- same receipt was archived before, its earlier late events are kept and counted on.
    local after={id=result.id,cd=result.cd,key=Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey(),
        ord=st.ord,n=0,list={},charges=s.charges}
    local rowNow=liveRow()
    for _,e in ipairs(rowNow and type(rowNow[ARCHIVE_KEY])=="table" and rowNow[ARCHIVE_KEY] or {}) do
        if type(e)=="table" and e.id==result.id and e.cd==result.cd then
            after.n=pickInt(e.lateN,0,RC_LATE_COUNT) or 0
            for i=1,RC_LATE_MAX do
                local l=type(e.late)=="table" and e.late[i]
                if type(l)=="table" and RC_LATE_KINDS[l.k] then
                    after.list[#after.list+1]={k=l.k,ep=pickInt(l.ep,0,65535),ch=pickInt(l.ch,0,10000000),
                        pd=pickInt(l.pd,0,10000000),w=type(l.w)=="string" and #l.w<=24 and l.w:find("^[%a_]+$") and l.w or nil,
                        nr=l.nr==true or nil}
                end
            end
        end
    end
    RS.after=after
    approval=nil
    rc.stage="done";rc.doneToken=token;rc.token=nil;rc.step=nil
    noteAttempt(rc,"archived",nil)
    terminal("STOPPED",RC_DONE)
    return true,"archived"
end
-- Late events after the archive: bounded, recorded on the archive entry, never linked to the
-- old receipt and never acted on. The recovery frame ticks slowly for this while the session lasts.
function RC.late()
    local a=RS.after
    if not a then return end
    -- another character's session: its entry is not in this row
    local key=Nexus.Store and Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey()
    if key~=a.key then return end
    -- a new run's own offers and replies are recorded too (the data is wanted), flagged as such
    local newRun=(run.running or run.pending~=nil) or nil
    local list=B.TransportSince(a.ord)
    if not list then
        -- more packets than the ring holds arrived between two looks: some events are lost, and said so
        a.ord=B.TransportStatus().ord
        a.n=math.min(a.n+1,RC_LATE_COUNT);a.dirty=true
        if #a.list<RC_LATE_MAX then a.list[#a.list+1]={k="events_lost",nr=newRun} end
        list={}
    end
    if #list>0 then
        a.ord=list[#list].ord
        for _,r in ipairs(list) do
            local k
            if r.cls=="R" then k="rejected"
            elseif r.op==16 then k="choice_push"
            elseif r.op==1000 then k="pick_result"
            elseif r.op==1220 and r.cls=="Q" and r.pending>0 then k="pending_positive"
            elseif r.op==1220 and r.cls~="Q" then k="reply_unqualified" end
            if k then
                a.n=math.min(a.n+1,RC_LATE_COUNT);a.dirty=true
                if #a.list<RC_LATE_MAX then
                    a.list[#a.list+1]={k=k,ep=r.epoch,ch=r.charges,pd=r.pending,w=r.why,nr=newRun}
                end
            end
        end
    end
    if a.dirty then
        local o=owner()
        local row=liveRow()
        if o and row then
            local done,held=false,false
            local ok=pcall(o.UpdateStateV1,function(r)
                done=false;held=false
                for _,e in ipairs(type(r[ARCHIVE_KEY])=="table" and r[ARCHIVE_KEY] or {}) do
                    if type(e)=="table" and e.id==a.id and e.cd==a.cd then
                        -- Future envelope/annotation fields are never discarded to
                        -- make optional diagnostics fit. Legacy entries may lack reserve.
                        local candidate=copy(e)
                        if (e.late~=nil and (type(e.late)~="table" or getmetatable(e.late)))
                            or (e.lateN~=nil and not integer(e.lateN,0,RC_LATE_COUNT)) then
                            held=true;return
                        end
                        candidate.late=copy(e.late or {})
                        for i,v in ipairs(a.list) do
                            if candidate.late[i]==nil then candidate.late[i]=copy(v) end
                        end
                        candidate.lateN=math.max(a.n,e.lateN or 0)
                        local edges,bytes,depth=measure(candidate)
                        local total=bytes
                        local reservedTotal=RC.retainedBudget(candidate)
                        for _,other in ipairs(r[ARCHIVE_KEY]) do
                            if other~=e then
                                local reserve,actual=RC.retainedBudget(other)
                                total=total+actual;reservedTotal=reservedTotal+reserve
                            end
                        end
                        if edges>ARCHIVE_EDGES or bytes>ENTRY_BYTES or depth>4 or total>ARCHIVE_BYTES
                            or (run.pending and not run.pending.restored and reservedTotal+ENTRY_BYTES>ARCHIVE_BYTES) then
                            held=true;return
                        end
                        e.late=candidate.late;e.lateN=candidate.lateN;done=true
                    end
                end
            end)
            if ok and (done or held) then a.dirty=nil;a.capacityHeld=held or nil end
        end
    end
end
-- The player-facing text of a refusal code that ContinueBegin or ContinueConfirm returned (never the raw code).
function M.ContinueReason(code)
    return type(code)=="string" and RC_REFUSALS[code] or "Nothing was changed."
end
-- Shared owned-data projection: counts and plain summaries, no receipt,
-- runtime initialization, game observation, transport read or saved write.
local function archiveView()
    local astate,list,count=RC.archiveInfo()
    local out={state=astate,count=count,capacity=ARCHIVE_MAX,entries={}}
    -- Preserve presence without returning malformed raw values: nil is an
    -- absent fact; the bounded constant marks a present unreadable fact.
    local function numberFact(value,lo,hi)
        if value==nil then return nil end
        return pickInt(value,lo,hi) or "invalid"
    end
    local function codeFact(value,first,second)
        if value==nil then return nil end
        return (value==first or value==second) and value or "invalid"
    end
    local function childFact(parent,key,first,second)
        if parent==nil then return nil end
        if type(parent)~="table" or getmetatable(parent) then return "invalid" end
        return codeFact(parent[key],first,second)
    end
    for i,e in ipairs(list) do
        if i>ARCHIVE_MAX then break end
        local consentVersion
        if e.consent~=nil then
            if type(e.consent)=="table" then consentVersion=numberFact(e.consent.v,1,1)
            else consentVersion="invalid" end
        end
        local late
        if e.late~=nil then
            late="invalid"
            -- Validate the rows, not just array keys. The independent seen
            -- counter is projected below and cannot erase valid kept rows.
            if RC.knownLate({late=e.late}) then late=#e.late end
        end
        out.entries[#out.entries+1]={id=type(e.id)=="string" and e.id:sub(1,16) or nil,kind=codeFact(e.kind,"ACK_UNCONFIRMED","AUTO_UNCONFIRMED"),
            spent=numberFact(e.spent,0,100000),limit=numberFact(e.limit,0,100000),
            uncertain=numberFact(e.uncertain,0,100000),
            confidence=childFact(e.resolution,"confidence","NONE"),
            consentVersion=consentVersion,
            consentPolicy=childFact(e.consent,"policy","SESSION_BOUNDED_TWO","TWO_OBSERVED"),
            late=late,lateN=numberFact(e.lateN,0,RC_LATE_COUNT),
            outcome=childFact(e.resolution,"outcome","UNCONFIRMED")}
    end
    return out
end
function M.Archive()
    init();return archiveView()
end
function M.ArchiveDiagnostics()
    return archiveView()
end
-- The last attempts of this session, for the support report. Plain numbers and codes.
function M.ContinueLog()
    init()
    local out={}
    for i,e in ipairs(RS.log or {}) do out[i]=copy(e) end
    return out
end
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
    UNOBSERVABLE="The earlier Orb action could not be linked to an observed result. The game gives no record of which choice belonged to it, so Nexus cannot confirm it, and Recheck cannot settle it. The record, its spending exposure, and the block on new Orb runs and ordinary rolling are kept. Nothing is retried, refunded or deleted.",
}
-- WAIT_RESULT names the settlement requirement that the last read did not
-- meet (run.settleGate), so the text does not promise that a fresh ownership
-- response settles an action that something else holds.
local WAIT_RESULT_GATE={
    attribution="Your Echoes show the recorded gain, but an earlier unconfirmed attempt could have caused it. This action cannot be confirmed. Its record and exposure are kept. Stop, then open Orbs for the explicit checked Continue exit, or use that exit during passive recovery after reload. No spending restarts.",
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
        if gate.gate=="attribution" then
            local refusal=RC.archiveExitRefusal()
            if refusal then
                text="Your Echoes show the recorded gain, but it cannot be attributed to this action. Continue is unavailable. "
                    ..refusal..KEPT.." No spending restarts."
            end
        elseif gate.gate=="charges" then
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
    local text=RECOVERY_TEXT[kind] or RECOVERY_TEXT.CHECKING
    if kind=="UNOBSERVABLE" then return text..(p and p.spendConfirmed==true and NO_EXIT or UNOBSERVED) end
    return text
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
    if p and run.snap and run.snap.attribution then
        local refusal=RC.archiveExitRefusal()
        if refusal then
            return subject.." is blocked: the observed gain cannot be attributed to this action. Continue is unavailable. "
                ..refusal..KEPT
        end
        local nextStep=run.running and "Stop this Orb run first, then open" or "Open"
        return subject.." is blocked: the observed gain cannot be attributed to this action. "..nextStep.." /nexus orbs for its explicit checked Continue exit. The record is kept until that check passes and you confirm; no spending restarts."
    end
    if p and p.restored and not run.running then
        local r=run.recovery or {}
        if CAN_PROGRESS[r.kind] or (CAN_PROGRESS_OBSERVING[r.kind] and r.observing) then
            return subject.." is blocked: an earlier Orb action is unresolved after a reload. Nexus only observes it and sends nothing. The block ends when that action is confirmed or, if this record retains an observation of this spend and has no usable recorded choice, and no offer is open, when Continue's read-only check passes and you confirm it. Open /nexus orbs for the current instruction."
        end
        return subject.." is blocked: an earlier Orb action cannot be confirmed. If this record retains an observation of this spend and has no usable recorded choice, and no offer is open, Continue in /nexus orbs ends this block after its read-only check passes and your confirmation; Nexus does not clear it by itself. Open /nexus orbs for details."
    end
    if run.running then return subject.." is paused: Orb refinement owns the current action." end
    if p then return subject.." is blocked: a submitted Orb action is unresolved. Finish its offer in the game; Nexus confirms it only from the matching result. If it cannot be confirmed, reload the game: Continue in /nexus orbs may then apply." end
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
    if (not run.running and run.state~="PAUSED") or run.heldReceipt~=p or not run.heldSince then return end
    local id=p.selectedKey and tonumber(tostring(p.selectedKey):match("^(%d+):"))
    local row=id and s.catalog and s.catalog[id]
    local text=HELD_CHOICE:format(row and row.name or ("Echo "..tostring(p.selectedKey)),row and row.name or ("Echo "..tostring(p.selectedKey)))
    local held=id and p.selectionAttempted and (p.choiceMayHaveBeenSent or p.choiceObserved)
        and s.offerPending and s.selectInFlight==id and now()-run.heldSince>=HELD_CHOICE_DELAY
    if run.running then
        if held then
            if not run.heldText then run.heldPriorReason=run.reason end
            run.heldText=text;setState("WAIT_RESULT",text)
        elseif run.heldText then run.heldText=nil end
        return
    end
    -- run.heldText: the exact hint shown, so it is withdrawn even if the Echo
    -- name read for it changes; any other pause reason is never replaced.
    if held and (run.reason==SESSION_INTERRUPTED or run.reason==run.loadingPauseReason or (run.heldText and run.reason==run.heldText)) then
        if not run.heldText then run.heldPriorReason=run.reason end
        run.heldText=text;setState("PAUSED",text)
    elseif not held and run.heldText and run.reason==run.heldText then
        run.heldText=nil;setState("PAUSED",run.heldPriorReason or run.reason);run.heldPriorReason=nil
    end
end
function M.Pump(passive)
    init()
    -- After a Continue, late game events are recorded on the archive entry (bounded, never acted on).
    if RS.after then pcall(RC.late) end
    if advancing or (not run.running and not run.pending) then return end
    passive=passive==true or passiveDepth>0
    if run.pending then
        -- Install the pick hook if the game's PerkService appeared after the load,
        -- and save pick evidence that the store refused earlier. Neither reads the
        -- game and neither changes any run state.
        if not run.captureOn and type(B.CaptureStart)=="function" then
            local okC,started=pcall(B.CaptureStart);run.captureOn=okC and started==true
        end
        flushEvidence()
    end
    advancing=true
    local observed
    local function step()
        if life.phase=="l" then return end
        local s,err=readState()
        observed=s
        if not s and run.postRecovery then RC.postUnknown() end
        if not s and run.worldRecovering and run.running then
            if now()-(run.worldPausedAt or now())<RESULT_TIMEOUT then return end
            run.worldRecovering=nil;pause("The game state is still unavailable after loading. No Orb action was repeated. Recheck, then Resume when readable.");return
        end
        if s then run.worldRecovering=nil end
        if s and life.phase=="r" then life.phase="w" end
        local p=run.pending
        if p then journalNote("read",s,p) end
        if not s and p and p.restored and not run.running then
            -- Passive recovery reads from addon load onward. A read that is not
            -- ready yet is not a pause reason that should outlive the loading.
            run.recovery={kind="UNREADABLE",observing=false}
            setState("RECOVERY","An earlier Orb action is unresolved. The current game state cannot be read yet: "..tostring(err).." Nothing will be sent. The record and its spending exposure are kept.")
            RC.unreadable()
            return
        end
        if not s then pause(err);return end
        -- Read before any check can pause, so the report never shows a stale value.
        run.pickInFlight=s.selectInFlight~=nil
        -- The slot this read saw (session only, never saved), for the support view.
        run.slotRead={slot=s.context.slot,slotKnown=s.context.slotKnown}
        if p and p.restored then
            -- What the last passive read showed, for the Continue view (the check reads again itself).
            run.snap={guid=s.context.guid,open=s.offerPending==true or #s.board>0,attribution=RC.attributionExit(p,s)}
            if receiptGuid(p)~=s.context.guid then pause("The earlier Orb action belongs to another character or an unsupported receipt format.");return end
            if not p.baselineStamp then p.baselineStamp=s.grantStamp end
            local mark=run.pauseSerial
            local kind,observing,proposed=recoverObserve(s,p)
            if run.pauseSerial~=mark then run.recovery={kind="PAUSED",observing=observing};RC.advance(s,p);return end
            if finishResult(s,p) then return end
            if run.pauseSerial~=mark then run.recovery={kind="PAUSED",observing=observing};RC.advance(s,p);return end
            -- After a reload the player can choose before Nexus has read
            -- anything: the first ownership read then already shows the exact
            -- result and is not newer than the baseline. When that is the only
            -- missing requirement, ask the game ONCE per load for a newer
            -- ownership response: the read-only Recheck request. It sends no
            -- Orb and no choice, and settlement stays in finishResult.
            local gate=run.settleGate
            if gate and gate.gate=="fresh" and gate.detail and gate.detail.exact and not run.autoRefreshAt then
                run.autoRefreshAt=now();requestRefresh()
            end
            run.recovery={kind=kind,observing=observing,proposed=proposed==true or nil,
                gate=kind=="WAIT_RESULT" and run.settleGate and copy(run.settleGate) or nil}
            setState("RECOVERY",recoveryReason(kind,observing,s,p,proposed))
            RC.advance(s,p)
            return
        end
        if run.context and not B.SameOwner(run.context,s.context) then pause("Character, run, or service changed. The pending operation will not be replayed.");return end
        local a=assigned()
        local displayTargets=a.state=="ready" and P.Normalize(a.entries)
        run.displayProgress=displayTargets and P.Progress(displayTargets,s) or nil
        if run.binding and (not matches(run.binding,a) or not B.SameContext(run.context,s.context)) then
            if not run.targetChanged or run.running then
                run.targetChanged=true
                if run.state~="STOPPED" then pause("The active loadout or assigned Wishlist changed. The original operation stays pending; Resume requires settlement and a resolved assignment.") end
            end
        end
        if p then
            run.snap={guid=s.context.guid,open=s.offerPending==true or #s.board>0,attribution=RC.attributionExit(p,s,a)}
            if loadoutCheck(s,p)~="SAME" then
                finishResult(s,p);return
            end
            if s.lockedKey~=p.lockedKey then pause("Locked Echoes changed; no further Orb action will be submitted.");return end
            if not observeLifecycle(s,p) then return end
            if not p.spendConfirmed and s.charges==p.chargesBefore-1 and s.offerPending then
                p.spendConfirmed=true;run.spent=run.spent+1;run.reserved=0
                local ok,e=savePending();if not ok then pause(e);return end
            elseif s.charges~=p.chargesBefore and s.charges~=p.chargesBefore-1 then
                -- Before the one-Orb decrement was seen with this action's
                -- offer, the spend outcome is unknown: hold. Once it was
                -- (spendConfirmed), a later balance change says nothing about
                -- this action (finishResult): pause continuation once and let
                -- the exact ownership result below settle it. The balance
                -- never settles it.
                if not p.spendConfirmed then
                    pause("The Orb balance changed unexpectedly. No further action will be submitted.");return
                end
                if run.running then pause("The Orb balance changed unexpectedly. No further action will be submitted.") end
            end
            if finishResult(s,p) then return end
            if not run.running and run.rc and not run.rc.automatic then RC.advance(s,p,a) end
            if not passive and now()>=(run.worldSettleUntil or 0) and RC.live(s,p,a) then return end
            if not run.running then heldChoiceHint(s,p) end
            if not run.running or passive then return end
            if now()<(run.worldSettleUntil or 0) then
                setState("WAIT_WORLD","Waiting briefly after loading before acting. Cached data is not proof of a fresh server answer.");return
            end
            if not entriesStillMatch(a) then pause("The selected Wishlist changed; resolve the pending offer manually.");return end
            if p.selectionAttempted then
                setState("WAIT_RESULT",p.attributionAmbiguous
                    and (run.settleGate and run.settleGate.gate=="attribution" and WAIT_RESULT_GATE.attribution
                        or "An earlier unconfirmed attempt may match this source and choice. The current result is not confirmed. Its record and exposure remain counted; no command will be repeated.")
                    or "Waiting for a fresh server response confirming the selected replacement.")
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
                -- Save this ambiguity BEFORE submitting the choice, so a
                -- failed later receipt write or reload cannot lose it.
                RC.ambiguity(p,s)
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
                journalNote(accepted==true and "select_submitted" or kind=="REJECTED" and "select_rejected" or "select_ambiguous",nil,p)
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
            heldChoiceHint(s,p)
            local timeout=p.selectionAttempted and RESULT_TIMEOUT or OFFER_TIMEOUT
            if now()-(p.since or now())>=timeout then
                local intent=Nexus.PendingIntentState and Nexus.PendingIntentState()
                local unavailable=run.recoveryUnavailable and run.recoveryUnavailable.receipt==p and run.recoveryUnavailable
                local available,absent=B.RecoveryAvailable()
                if not unavailable and not available then
                    run.recoveryUnavailable={receipt=p,reason=absent or "no_choice_observer"};unavailable=run.recoveryUnavailable
                end
                if not unavailable and available and not s.offerPending and #s.board==0 and not s.hostPending and not s.selectInFlight
                    and not Nexus.GameAdapter.InFlight() and intent==nil then
                    local begun,why=RC.beginLive(s,p,a)
                    if begun then return end
                    run.recoveryUnavailable={receipt=p,reason=why};unavailable=run.recoveryUnavailable
                end
                if not p.refreshRequested then
                    if RC.outstanding() then p.refreshRequested=true;p.since=now()
                    else p.refreshRequested=true;p.since=now();requestRefresh() end
                else
                    pause((run.heldReceipt==p and s.offerPending and s.selectInFlight~=nil and run.heldText)
                        or (unavailable and RC.liveReason(unavailable.reason))
                        or "No authoritative result arrived. Spending is paused; no action will be repeated.")
                end
            end
            return
        end
        if not run.running or passive or now()<(run.worldSettleUntil or 0) then return end
        if not entriesStillMatch(a) then pause("The assigned Wishlist changed. Review it and Resume without resetting this run's usage.");return end
        local progress=P.Progress(run.targets,s)
        if progress.rolledMissing==0 then
            terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
                progress.permanentMissing==0 and "All selected targets are complete." or "Rolled targets are complete; Orbs cannot change the remaining locked targets.");return
        end
        if run.spent+run.reserved+(run.uncertain or 0)>=run.limit then reachedLimit();return end
        if s.charges<1 then terminal("OUT_OF_ORBS","No Orbs remain. New resources will not restart this run automatically.");return end
        if not RC.postReady(s,a) then return end
        for _,target in ipairs(progress.items) do
            local row=s.catalog[target.spellId]
            if target.role=="rolled" and target.missing>0 and (not row or not row.available or row.quality~=target.quality) then
                pause("A required target is no longer available. "..(row and row.availabilityReason or "").." No next Orb will be spent.");return
            end
        end
        -- Defensive duplicate: a settled limit is normally finished by the
        -- settlement above, and Resume refuses at the limit, so this is the
        -- last line rather than the usual path. It applies the same test.
        if run.spent+run.reserved+(run.uncertain or 0)>=run.limit then reachedLimit();return end
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
        p=RC.newReceipt(source.key,s,run.opSerial,run.historyBaseline and #run.historyBaseline.entries>0)
        local room,capacityReason=RC.spendCapacity(p)
        if not room then terminal("STOPPED",capacityReason);return end
        local _,historyError=RC.ambiguity(p,s)
        if historyError then pause("Retained Orb history cannot be verified. No new Orb action was sent.");return end
        logUpdate(run.opSerial,{sourceKey=source.key,sourceName=source.name,
            sourceQuality=source.quality,sourceCopies=source.excess,
            recycle=source.key==run.recycleKey,state="requested",
            reason="One Orb requested for this source copy."})
        run.pending=p;run.snap=nil;run.reserved=1
        -- Only this newly created receipt may own a durable diagnostic field.
        -- A failed diagnostic preparation cannot prevent the unchanged spend checks.
        local journalOk=pcall(journalBegin,p)
        if not journalOk and run.boundary then run.boundary.captureFailures=math.min((run.boundary.captureFailures or 0)+1,999) end
        journalNote("receipt",s,p);journalNote("pre_call",s,p)
        local previousReceipt=config.pending
        local ok,e,admissionCode=savePending(p)
        if not ok then
            -- Nothing was sent. The unsaved receipt must not stay in the
            -- preferences, where a later successful write would persist it.
            config.pending=previousReceipt
            logUpdate(run.opSerial,{state="not sent",
                reason="The receipt could not be saved; no Orb was requested."})
            run.pending=nil;run.snap=nil;run.reserved=0
            if admissionCode=="CAPACITY" then terminal("STOPPED",e) else pause(e) end
            return
        end
        if not recycle and not run.automatic then run.remaining[source.key]=math.max(0,(run.remaining[source.key] or 0)-1) end
        local capacityRefused=false
        local accepted,kind,reason,boundaryStatus=B.Spend(run.token,source.key,s,function(live)
            local guardAssignment=assigned()
            if not run.running or not entriesStillMatch(guardAssignment) then return false end
            local safe=false
            for _,r in ipairs(P.Sources(run.targets,live,run.excluded))do if r.key==source.key and r.excess>0 then safe=true;break end end
            if not safe then return false end
            -- Last owner check inside the adapter, after assignment/source
            -- evaluation and its fresh native read, immediately before host call.
            -- Capacity authority comes from the actual current row, never the
            -- cached read projection, at the final host boundary.
            local key=Nexus.Store.CurrentOwnerKey()
            local row=type(NexusDB)=="table" and type(NexusDB.chars)=="table" and NexusDB.chars[key]
            local room,why
            if type(row)=="table" then room,why=RC.spendCapacity(p,row) end
            if not room then capacityRefused=true;return false,why or RC.HISTORY_UNVERIFIED end
            return RC.postCheck(live,guardAssignment)
        end)
        if accepted or kind=="AMBIGUOUS" then run.postRecovery=nil;run.postRecoveryHeld=nil
        elseif kind=="REJECTED" and (boundaryStatus=="CHOICE_INVALID" or boundaryStatus=="GUARD_ERROR"
            or boundaryStatus=="VALIDATION_ERROR" or boundaryStatus=="READ_UNAVAILABLE") then RC.postUnknown()
        elseif kind=="REJECTED" and boundaryStatus=="HOST_FALSE" and run.postRecovery then
            -- This typed Adapter fact follows host_call. A host
            -- refusal consumes the one-use permit; pre-host refusals do not.
            run.postRecovery.revoked="The game refused the Orb spend after the recovery permit was used. Stop and review a new run."
        end
        journalNote(accepted==true and "spend_submitted" or kind=="REJECTED" and "spend_rejected" or "spend_ambiguous",nil,p)
        if not accepted then
            if kind=="REJECTED" then
                if not recycle and not run.automatic then run.remaining[source.key]=(run.remaining[source.key] or 0)+1 end
                logUpdate(p.logSerial,{state="not sent",reason=reason})
                run.pending=nil;run.snap=nil;run.reserved=0
                local cleared,clearReason=savePending()
                if not cleared then run.pending=p;run.snap=nil;run.reserved=1;pause(clearReason);return end
                if capacityRefused then terminal("STOPPED",reason);return end
                if run.state=="STOPPED" then release();return end
            else
                p.ambiguous=true;savePending()
                logUpdate(p.logSerial,{state="unknown",reason=reason})
            end
            if run.postRecoveryHeld and run.running then return end
            pause(reason);return
        end
        run.recycleKey=nil
        setState("WAIT_OFFER","One Orb requested; waiting for the actual offer.")
    end
    local ok,err=pcall(step);advancing=false
    -- Publish only completed observations, including the refusal/held state
    -- reached by this pump. Compact views never need a preceding full Status.
    local rc=run.rc;local p=run.pending
    if ok and observed and p and rc and rc.automatic and rc.admitted then
        run.resumeOwed={receipt=p,check=rc,stage=rc.stage,refusal=rc.refusal,
            pause=run.pauseSerial,epoch=life.epoch,allowed=RC.owedResume(p,observed)}
    else run.resumeOwed=nil end
    if not ok then pause("Orb mode encountered an internal error. No automatic repeat will be sent.");error(err,0) end
end
function M.Pause()
    init();if not run.running then return false end
    run.running=false;setState("PAUSED",run.pending and "Paused. A submitted spend may still finish; the native offer remains available." or "Paused before the next spend.")
    run.loadingPauseReason=run.reason
    logRun("PAUSED",run.reason)
    if run.rc and run.rc.automatic and (run.rc.stage=="checking" or run.rc.stage=="ready") then run.rc.stage="held";run.rc.step=nil;run.rc.token=nil end
    return true
end
function M.Stop()
    init();approval=nil;run.running=false;setState("STOPPED",run.pending and "Stopped. A submitted operation may still finish; resolve any pending offer manually." or "Stopped. No further Orb will be spent.")
    run.worldRecovering=nil
    if run.rc and run.rc.automatic and (run.rc.stage=="checking" or run.rc.stage=="ready") then run.rc.stage="held";run.rc.step=nil;run.rc.token=nil end
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
        uncertain=log.uncertain or 0,unconfirmedResults=log.unconfirmedResults or 0,
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
    local s,err=readState();if not s then if run.postRecovery then RC.postUnknown() end;return nil,err end
    if run.postRecovery then
        local ok,ready,why=pcall(RC.postCheck,s)
        if not ok then RC.postUnknown();return nil,"Recovery observations cannot be classified. Resolve any open offer in the game, or Stop and approve a new run." end
        if not ready then return nil,why end
    end
    local owed=RC.owedResume(run.pending,s)
    if run.pending and (run.pending.restored or run.pending.selectionAttempted or (run.rc and run.rc.automatic and run.rc.admitted and not owed)) then
        return nil,"The submitted result is unresolved. Wait for its actual result or finish a native offer manually. Stop or reload for passive recovery and its explicit Continue eligibility; no repeat is allowed."
    end
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
    if not run.pending and run.spent+run.reserved+(run.uncertain or 0)>=run.limit then return nil,"The approved maximum is reached. Stop, then start a new run with a higher maximum." end
    if not run.token then return nil,"This run no longer owns the action. Stop and approve a new run after settlement." end
    local off,e=turnAutoOff();if not off then return nil,e end
    if owed or (run.rc and run.rc.automatic and not run.rc.admitted) then run.rc=nil end
    run.running=true;setState(run.pending and "WAIT_OFFER" or "READY","Resuming the approved run without resetting its usage.")
    ensureFrame();M.Pump();return true
end
function M.PrepareLimitIncrease(value)
    init();value=tonumber(value)
    if run.completed or run.running or (run.state~="PAUSED" and run.state~="LIMIT") or not run.token
        or not integer(value,1,10000) or value<=run.limit or not run.context then
        return nil,"Pause the active run first, then choose a higher whole-number limit. Stopped/completed runs require new approval."
    end
    local token={};run.limitApproval={token=token,value=value,at=now()};return {token=token,limit=value,old=run.limit,spent=run.spent,reserved=run.reserved}
end
function M.ConfirmLimit(token)
    init();local a=run.limitApproval
    if run.completed or not a or token~=a.token or now()-a.at>60 or run.running or not run.token or (run.state~="PAUSED" and run.state~="LIMIT") then return nil,"Review the increased limit again." end
    run.limit=a.value
    local log=logOwned()
    if log then log.limit=a.value;log.increased=true;logTouch(log) end;run.limitApproval=nil
    if run.pending then local ok,e=savePending();if not ok then return nil,e end end
    setState(run.pending and "PAUSED" or "PAUSED","Limit increased by confirmation. Press Resume explicitly; usage was not reset.")
    return true
end
function M.Recheck()
    init();if run.lastRecheck and now()-run.lastRecheck<3 then return nil,"Please wait before requesting another refresh." end
    if type(B.TransportStart)=="function" then pcall(B.TransportStart) end
    local ownershipOnly=false
    if RC.outstanding() then
        if not RS.reqMark.at or now()-RS.reqMark.at<RC_WAIT then
            ownershipOnly=true
        else
            -- The bounded unanswered wait is given up, never called a result.
            RS.reqMark=nil
        end
    end
    run.lastRecheck=now()
    if run.pending and run.pending.restored then run.recoveryFastUntil=now()+RECOVERY_FAST_WINDOW end
    if run.pending and run.pending.restored and not run.pending.baselineStamp then
        local s=B.Read();if s then run.pending.baselineStamp=s.grantStamp end
    end
    -- A refresh can invoke synchronous notifications. All nested Pump calls
    -- remain passive until this handler returns, including ready offers.
    passiveDepth=passiveDepth+1
    local success,ok,err=pcall(function()
        local refreshed,why
        if ownershipOnly then refreshed,why=B.RequestOwnershipRefresh()
        else refreshed,why=requestRefresh() end
        if run.pending then ensureFrame();M.Pump(true) end
        return refreshed,why
    end)
    passiveDepth=passiveDepth-1
    if not success then return nil,"The read-only refresh failed; no new action was requested." end
    if not ok then return nil,RC_REFUSALS[err] or err end
    return true,ownershipOnly
        and "The earlier Orb count request remains pending. Requested Echo ownership only; no duplicate Orb count request was sent. No Orb or choice was submitted."
        or "Requested an Orb/ownership refresh. No Orb or choice was submitted."
end
-- Read-only view of the unresolved Orb action for the support report: scalars
-- only, no names. It writes nothing and authorizes nothing. Like
-- BlocksOrdinary, its init() can start the read-only recovery of a saved
-- receipt that nothing had loaded yet.
-- Passive session facts only. Unlike recovery/Continue views this never
-- initializes a runtime or inspects saved state. Unknown is not no receipt.
function M.RunnerView()
    return {initialized=config~=nil,state=run and run.state,
        running=run and run.running,pending=run and run.pending~=nil,
        uncertain=run and (run.uncertain or 0),reserved=run and run.reserved,historyKnown=run and run.historyKnown~=false,
        recoveries=run and run.historyKnown~=false and (run.recoveries or 0) or nil,
        unconfirmedResults=run and run.historyKnown~=false and (run.unconfirmedResults or 0) or nil,
        lifecycleObserved=frame~=nil,epoch=frame and life.epoch or nil,phase=frame and life.phase or nil}
end
function M.RecoveryView()
    if not config then
        local st=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
        if not (type(st)=="table" and type(st.orbRefinement)=="table" and st.orbRefinement.pending) then return {pending=false} end
    end
    init()
    local p=run and run.pending
    if not p then return {pending=false,state=run and run.state} end
    local gate=run.settleGate
    -- The loadout facts. Every saved value is checked on the way out: only a known cause name,
    -- small whole numbers (a slot, a clock time in range) and booleans are ever returned.
    local read=run.slotRead
    local check=read and loadoutCheck({context=read},p) or nil
    local nowKnown -- true, false, or nil when the client cannot say (false must survive)
    if read and type(read.slotKnown)=="boolean" then nowKnown=read.slotKnown end
    local cause,seen,seenAt
    if p.loadoutChanged==true and type(p.loadoutCause)=="string" and LOADOUT_CAUSES[p.loadoutCause] then
        cause=p.loadoutCause;seen=slotValue(p.loadoutObservedSlot);seenAt=epochValue(p.loadoutObservedAt)
    end
    local originalState=p.originalSlot==nil and "absent" or (slotValue(p.originalSlot)~=nil and "recorded" or "unreadable")
    -- What the saved record ALONE shows unmet. The live loadout check of the last read is returned
    -- separately (loadoutCheck). hasChoiceEvidence is stricter than the settlement gate for a
    -- damaged record; this is display only.
    local unmetNow={}
    if p.loadoutChanged or p.originalSlot==nil then unmetNow[#unmetNow+1]="loadout" end
    if not hasChoiceEvidence(p) then unmetNow[#unmetNow+1]="choice" end
    -- Raw pick evidence: counts only (see the evidence section above). No Echo id.
    local pickMatching,pickUsed,pickStored=0,0,0
    if type(p.picks)=="table" then
        for _,e in ipairs(p.picks) do
            pickStored=pickStored+1
            if e.m=="offer" then pickMatching=pickMatching+1 end
            if e.u==true then pickUsed=pickUsed+1 end
        end
    end
    return {pending=true,restored=p.restored==true,state=run.state,
        rawPicks=pickStored,rawPickCallbacks=pickInt(p.pickSeen,0,PICK_COUNT_MAX) or 0,
        rawPickDropped=pickInt(p.pickDropped,0,PICK_COUNT_MAX) or 0,rawPickMatching=pickMatching,rawPickUsed=pickUsed,
        rawPickUnsaved=run.pickDirty==true,
        recovery=p.restored and run.recovery and run.recovery.kind or nil,gate=gate and gate.gate or nil,
        -- The receipt field spendConfirmed (kept for saved-data compatibility)
        -- records the one-Orb decrement this client saw with the offer. No
        -- server reply names a spend, so the passive view calls it observed.
        spendObserved=p.spendConfirmed==true,choiceSent=p.choiceMayHaveBeenSent==true,choiceObserved=p.choiceObserved==true,
        selectedKey=p.selectedKey,removed=p.removed,loadoutChanged=p.loadoutChanged==true,
        pickInFlight=run.pickInFlight,autoRefresh=run.autoRefreshAt~=nil,
        originalSlot=originalState=="recorded" and slotValue(p.originalSlot) or nil,originalSlotState=originalState,
        slotRead=read~=nil,slotNow=read and slotValue(read.slot) or nil,
        slotNowKnown=nowKnown,
        loadoutCheck=check,loadoutCause=cause,loadoutSeenSlot=cause and seen or nil,loadoutSeenAt=cause and seenAt or nil,
        offerRecorded=p.offerKey~=nil,unmet=unmetNow}
end
function M.BlocksOrdinary()
    if not config then
        local st=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
        if not st then return false end
        if type(st.orbRefinement)=="table" and st.orbRefinement.pending then init() end
    end
    return run and (run.running or run.pending~=nil or (run.state=="PAUSED" or run.state=="LIMIT")) or false
end
-- The last normal Orb window read (M.Status), for the support report: one
-- bounded snapshot of fixed codes, whole numbers and booleans, each checked as
-- it is recorded. Memory only: never saved, nothing reads the game for it and
-- nothing decides from it.
local readiness=nil
local READINESS_CODES={
    stage={ok=true,assignment=true,targets=true,capability=true,state=true,balance_loading=true,
        balance_invalid=true,catalog=true,trust_owned=true,trust_locked=true,trust_both=true,call=true,
        granted_unavailable=true,granted_shape=true,granted_verify=true,locked_unavailable=true,
        locked_shape=true,locked_verify=true,limits=true,choice=true,auto_accept=true,host=true},
    assignment={ready=true,unassigned=true,restoring=true,loading=true,unavailable=true},
    rejection={none=true,absent=true,not_table=true,unreadable=true,invalid_value=true,
        conflicting_alias=true,cycle=true,depth=true,over_cap=true,scalar_leaf=true},
}
local function observeReadiness(stage,a,progress)
    local codes=READINESS_CODES
    local function flag(v) if type(v)=="boolean" then return v end return nil end
    local function count(v) if integer(v,0) then return v end return nil end
    local t=now()
    local o={at=type(t)=="number" and t==t and t>-math.huge and t<math.huge and t or nil,
        stage=type(stage)=="string" and codes.stage[stage] and stage or "unknown",
        assignment="unknown",roles="unknown",progress=progress and "available" or "unavailable"}
    -- Recorded first: this read happened, whatever below cannot be recorded.
    readiness=o
    if type(progress)=="table" then
        o.rolledMissing=count(progress.rolledMissing);o.permanentMissing=count(progress.permanentMissing)
    end
    local state=type(a)=="table" and a.state
    if type(state)=="string" and codes.assignment[state] then
        o.assignment=state
        if state~="ready" then o.roles="none"
        else
            -- The role rule of logic/Strategy.lua, on the Wishlist's own rows.
            local entries=type(a.wishlist)=="table" and a.wishlist.entries
            if type(entries)=="table" then
                o.roles="untyped"
                for _,e in ipairs(entries) do
                    if type(e)=="table" and not e.designTarget and (type(e.locked)=="boolean"
                        or e.sourceRole=="ordinary" or e.sourceRole=="locked") then o.roles="explicit";break end
                end
            end
        end
    end
    -- The ownership trust facts at this read, from the adapter's passive view.
    local ok,trust=pcall(function()
        local adapter=Nexus.GameAdapter
        local view=adapter and type(adapter.OwnershipTrustView)=="function" and adapter.OwnershipTrustView() or nil
        if type(view)~="table" then return nil end
        local why=view.lockedRejection
        return {ownedSynced=flag(view.ownedSynced),ownedConfirmed=flag(view.ownedConfirmed),
            ownedArmed=flag(view.ownedArmed),ownedFresh=flag(view.ownedFresh),ownedGhost=flag(view.ownedGhost),
            ownedGeneration=count(view.ownedGeneration),ownedTotal=count(view.ownedTotal),
            lockedSynced=flag(view.lockedSynced),lockedCopies=count(view.lockedCopies),
            lockedRejection=type(why)=="string" and codes.rejection[why] and why or nil,
            -- The serial of the locked read this observation saw (GameAdapter.LockedShapeView).
            lockedSerial=integer(view.lockedSerial,1,9999999) and view.lockedSerial or nil}
    end)
    if ok and type(trust)=="table" then for k,v in pairs(trust) do o[k]=v end end
end
-- Read-only copy of that snapshot for the support report: a new table on each
-- call. It reads nothing, initializes nothing and authorizes nothing. `age` is
-- the whole seconds since that read; every other fact is as it was then.
function M.ReadinessView()
    local o=readiness
    if not o then return {observed=false} end
    local v={observed=true}
    for k,x in pairs(o) do v[k]=x end
    -- GetTime() counts milliseconds; half of one keeps float noise in the
    -- subtraction from costing a whole second.
    local t=now()
    local age=type(t)=="number" and type(o.at)=="number" and math.floor(t-o.at+0.0005) or nil
    v.age=integer(age,0) and age or nil
    return v
end
-- Detached, bounded evidence only. No init, game read, write or action is made
-- for this support view; missing older/reloaded history is explicitly unknown.
function M.BoundaryDiagnostics()
    local p=run and run.pending;local d=run and run.boundary
    local saved=p and journalList(p.boundaryJournal) or nil
    local reason
    if d then reason=d.reason
    elseif p then if not saved then reason=p.boundaryJournal~=nil and "foreign_journal" or "older_receipt" end
    else reason="no_receipt" end
    local t
    if type(GetTime)=="function" then local ok,value=pcall(GetTime);if ok then t=value end end
    local function age(at)
        if type(t)=="number" and t==t and t<math.huge and type(at)=="number" and t>=at then return math.floor(t-at) end
    end
    return {observed=d~=nil or saved~=nil,receiptPresent=p~=nil,mode=d and d.mode or saved and "retained" or "unavailable",
        reason=reason,
        retained=saved and #saved or 0,durableRetained=p and (p.restored and saved and #saved or d and d.persistedCount) or 0,
        sessionRetained=d and #d.session or 0,
        priorWrittenOmitted=d and d.priorWrittenOmitted or 0,
        dropped=d and d.dropped or 0,captureFailures=d and d.captureFailures or 0,
        unsaved=p and d and d.unsaved==true or false,persisted=p and d and d.persisted==true or false,
        epoch=life.epoch,phase=life.phase,lifecycleObserved=frame~=nil,
        snapshotAge=age(d and d.snapshot and d.snapshot.at),lastReadAge=age(d and d.lastReadAt),
        receiptJournal=saved or {},sessionJournal=d and copy(d.session) or {},
        snapshot=d and copy(d.snapshot) or nil}
end
-- The exact comparison scalars used by OrbAdapter SameOwner/SameContext,
-- without reading/reconciling Echoes. OwnershipTrustView exposes the same
-- ownedGeneration that OrbAdapter.ctx takes from A.Owned().generation.
-- Only a paused Resume affordance asks for this view; it grants no authority.
local function resumeDisplayContext()
    local a=Nexus.GameAdapter;local pe=_G.ProjectEbonhold
    if type(pe)~="table" or type(pe.PerkService)~="table"
        or type(pe.OrbService)~="table" or type(pe.Perks)~="table"
        or type(a.OwnershipTrustView)~="function" or type(a.Level)~="function"
        or type(UnitGUID)~="function" then return nil end
    local ok,trust=pcall(a.OwnershipTrustView)
    local okGuid,guid=pcall(UnitGUID,"player")
    local okLevel,level=pcall(a.Level)
    if not ok or type(trust)~="table" or not integer(trust.ownedGeneration,0)
        or not okGuid or type(guid)~="string" or guid==""
        or not okLevel or not integer(level,1) then return nil end
    return {pe=pe,svc=pe.PerkService,orb=pe.OrbService,guid=guid,
        generation=trust.ownedGeneration,level=level,slot=pe.Perks.serverActiveSlot}
end
-- Display-only structural Resume guards: never rebind/adopt targets, turn Auto
-- off or advance the run. Actual Resume still performs every fresh action check.
-- Pending work keeps its original assignment/context; a settled run may adopt
-- a different ready, valid assignment only on the explicit action.
local function resumeOffered(a,s)
    if run.state~="PAUSED" or not run.token or not run.context then return false end
    if run.postRecovery then
        local permit=run.postRecovery
        if permit.revoked or not permit.choice or type(B.TransportCursor)~="function" then return false end
        local ok,ordinal,epoch=pcall(B.TransportCursor)
        if not ok or not integer(ordinal,0) or ordinal~=permit.scanned or epoch~=permit.tepoch then return false end
    end
    local p=run.pending
    local rc=run.rc
    local owed=true
    if p and rc and rc.automatic and rc.admitted then
        if s then owed=RC.owedResume(p,s)
        else
            local hint=run.resumeOwed
            owed=hint and hint.receipt==p and hint.check==rc and hint.stage==rc.stage
                and hint.refusal==rc.refusal and hint.pause==run.pauseSerial and hint.epoch==life.epoch
                and hint.allowed==true and type(B.OwedDisplayClear)=="function" and B.OwedDisplayClear()
        end
    end
    if p and (run.targetChanged or p.restored or p.selectionAttempted
        or not owed
        or (p.ambiguous and not p.spendConfirmed)) then return false end
    a=a or assigned()
    if p then
        if not matches(run.binding,a) then return false end
    elseif a.state~="ready" or not P.Normalize(a.entries)
        or run.spent+run.reserved+(run.uncertain or 0)>=run.limit then return false end
    -- Reuse Status's context; compact-only reads use passive scalars, not the
    -- adapter read. SameOwner/SameContext do not compare display-only `active`.
    local context=s and s.context or resumeDisplayContext()
    if not context or not B.SameOwner(run.context,context) then return false end
    return not p or B.SameContext(run.context,context)
end
-- Display snapshot. One adapter read per call (plus passive balance reads for
-- the balance line and the maximum draft). History review returns the current
-- acknowledgment token; every action still reads again. detail=true adds the source list.
-- The read is display-only (NX-02): its Echo reconciliation may be reused for
-- under 1 s, so its context generation is non-authoritative; every shown
-- field is read fresh.
function M.Status(detail)
    if type(Nexus.GameAdapter.InvalidateChoiceObservation)=="function" then
        pcall(Nexus.GameAdapter.InvalidateChoiceObservation)
    end
    init();local m,err,failed,stage=inspect(true);local a=m and m.assignment or failed or assigned()
    local resumeRead=m and m.s
    if run.postRecovery and run.state=="PAUSED" then
        if resumeRead then
            local ok=pcall(RC.postCheck,resumeRead,a)
            if not ok then RC.postUnknown() end
        elseif stage~="assignment" and stage~="targets" then
            -- Assignment/target refusals precede the state read; only a
            -- failed state observation can erase its retained choice fact.
            RC.postUnknown()
        end
    end
    -- A held run inspects its approved targets, while this view shows the
    -- current assignment. Separately valid rolled/locked inputs can project
    -- a combined target that the Orb policy refuses. Keep the held receipt
    -- readable; the display refusal must not replace or settle that receipt.
    local shownTargets
    if m then
        shownTargets,err=P.Normalize(a.entries)
        if not shownTargets then m=nil;stage="targets" end
    end
    local r={state=run.state,reason=run.reason,error=err,running=run.running,pending=run.pending~=nil,recoveryPhase=RC.phase(),recoveryKind=RC.kind(),
        spent=run.spent,reserved=run.reserved,limit=run.limit,config=copy(config),recent=copy(run.recent),
        uncertain=run.uncertain or 0,historyKnown=run.historyKnown~=false,
        recoveries=run.historyKnown~=false and (run.recoveries or 0) or nil,
        unconfirmedResults=run.historyKnown~=false and (run.unconfirmedResults or 0) or nil,recoveryNotice=run.recoveryNotice,
        assignment=copy(a),targetChanged=run.targetChanged,operationName=run.name,
        recovery=run.pending and run.pending.restored and copy(run.recovery) or nil}
    r.config.name=a.name or "No assigned Wishlist";r.config.entries=copy(a.entries or {})
    r.config.pending=nil
    r.charges,r.balanceState,r.balanceReason=B.Balance()
    r.limitDraft=M.LimitDraft()
    if m then
        r.charges=m.s.charges;r.progress=P.Progress(shownTargets,m.s)
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
    elseif m and not run.running and not run.pending and run.state~="PAUSED" and run.state~="LIMIT" then
        can,why=preflight(true,m,true)
    elseif m then why=run.reason
    else why=err end
    r.canStart=not run.running and not run.pending and run.state~="PAUSED" and run.state~="LIMIT" and can~=nil
    r.startReason=why
    if can and #can.history>0 then
        r.historyCount=#can.history;r.historyRisk=RC.HISTORY_RISK;r.historyReview=RC.review(can)
    end
    r.canResume=resumeOffered(a,resumeRead)
    -- Memory-only bookkeeping of this read; a failure in it changes nothing
    -- shown or allowed.
    pcall(observeReadiness,m and "ok" or stage,a,r.progress)
    return r
end
function M.CompactStatus()
    init();if run.limit==0 and not run.pending then return nil end
    local remaining=run.displayProgress and run.displayProgress.rolledMissing
    return {state=run.state,running=run.running,pending=run.pending~=nil,recoveryPhase=RC.phase(),recoveryKind=RC.kind(),spent=run.spent,reserved=run.reserved,
        uncertain=run.uncertain or 0,historyKnown=run.historyKnown~=false,
        unconfirmedResults=run.historyKnown~=false and (run.unconfirmedResults or 0) or nil,
        recoveries=run.historyKnown~=false and (run.recoveries or 0) or nil,
        limit=run.limit,remaining=remaining,reason=run.reason,
        canResume=resumeOffered()}
end
-- The adapter's hook reaches the evidence sink and the immediate notification.
if type(B.CaptureSink)=="function" then B.CaptureSink(onPickRaw,onOwnerChoice,function() return life.phase,life.epoch end) end
if type(B.BoundarySink)=="function" then B.BoundarySink(function(event,s)
    if Nexus.OrbRuntime==M and run and run.pending then journalNote(event,s,run.pending) end
end) end
-- Default-off diagnostic dispatcher. The collector preserves callback arity,
-- returns and errors; no timing/heap read is added while it is disabled.
do
    local status=M.Status
    function M.Status(...)
        local perf=Nexus.Performance
        if perf and type(perf.MeasureDiagnostic)=="function" then return perf.MeasureDiagnostic("orb.status",status,...) end
        return status(...)
    end
end
