-- Nexus Orb of Lost Memories controller: one owner, one Orb, one confirmed result.
-- Independent behavioral integration of supplied LoadoutPilot P103 MemoryMode.
Nexus=Nexus or {}
local M={};Nexus.OrbRuntime=M
local P=assert(Nexus.OrbPolicy);local B=assert(Nexus.GameAdapter.Orbs)
local config,run,approval,frame,configOwner
local advancing=false
local OFFER_TIMEOUT,RESULT_TIMEOUT=10,12
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function now() return GetTime and GetTime() or 0 end
local function integer(n,min,max) return type(n)=="number" and n==math.floor(n) and n>=(min or 0) and n<=(max or 1000000) end
local function owner()
    return Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
end
local function write(data)
    local store=Nexus.Store
    local key=store and store.CurrentOwnerKey and store.CurrentOwnerKey()
    if not key or type(NexusDB)~="table" or type(NexusDB.chars)~="table" or not NexusDB.chars[key] then
        return nil,"Local character data is not ready; no Orb action will be sent."
    end
    local o=owner();if not o or not o.UpdateStateV1 then return nil,"Local saved data is not ready." end
    local ok,detail=o.UpdateStateV1(function(s) s.orbRefinement=copy(data) end)
    if not ok then return nil,"Could not preserve Orb preferences/recovery state. No new action was sent." end
    return true
end
local function init()
    local key=Nexus.Store and Nexus.Store.CurrentOwnerKey and Nexus.Store.CurrentOwnerKey()
    local liveKey=key and type(NexusDB)=="table" and type(NexusDB.chars)=="table" and type(NexusDB.chars[key])=="table" and key or false
    if config and (configOwner==liveKey or (run and (run.running or run.pending or run.token))) then return end
    configOwner=liveKey
    local state=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
    local c=state and state.orbRefinement or {}
    config={name=c.name or "No Wishlist selected",entries=copy(c.entries or {}),sources=copy(c.sources or {}),
        excluded=copy(c.excluded or {}),recycle=c.recycle==true,maxOrbs=integer(c.maxOrbs,1,10000) and c.maxOrbs or 10,
        pending=copy(c.pending),fingerprint=c.fingerprint,selectedSlot=c.selectedSlot,origin=c.origin}
    run={state="IDLE",reason="Choose targets, review replaceable copies, then Start.",running=false,spent=0,reserved=0,limit=0,recent={}}
    if type(config.pending)=="table" then
        run.pending=copy(config.pending);run.pending.restored=true;run.pending.since=now()
        run.pending.refreshRequested=false;run.pending.baselineStamp=nil
        run.state="RECOVERY";run.reason="An earlier Orb action is unresolved. Nothing will restart. Recheck and resolve any native offer manually."
        run.spent=run.pending.spent or 0;run.reserved=run.pending.spendConfirmed and 0 or 1;run.limit=run.pending.limit or config.maxOrbs
    end
end
local function fingerprint(entries)
    local parts={}
    for _,e in ipairs(entries or {}) do parts[#parts+1]=table.concat({e.spellId,e.quality,e.stacks or 1,e.locked==true and 1 or 0},":") end
    return table.concat(parts,",")
end
local function setState(state,reason) run.state=state;run.reason=reason end
local function changedConfig()
    approval=nil
    local ok,err=write(config);if not ok then return nil,err end
    return true
end
local function editable()
    init();return not run.running and not run.pending and run.state~="PAUSED" and run.state~="LIMIT"
end
local function savePending()
    if run.pending then
        local p=copy(run.pending);p.context=nil;p.beforeSnapshot=nil;p.token=nil
        p.spent=run.spent;p.limit=run.limit;p.since=nil;p.baselineStamp=nil
        config.pending=p
    else config.pending=nil end
    return write(config)
end
local function release()
    if run.token then B.Release(run.token);run.token=nil end
end
local function pause(reason)
    run.running=false;setState("PAUSED",reason)
end
local function terminal(state,reason)
    run.running=false;setState(state,reason)
    -- A spent-limit stop retains the paused run's ownership for an explicit
    -- increase + Resume. Stop releases it; no resource arrival resumes it.
    if not run.pending and state~="LIMIT" then release() end
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
    if not editable() then return nil,"Stop and settle the current Orb operation before changing targets." end
    local resolved,status=Nexus.GameAdapter.ResolveWishlistEvidence(candidate)
    if not resolved or status~="actionable" then return nil,"Open this Wishlist in the editor and confirm its permanent targets first." end
    local targets,err=P.Normalize(resolved.echoes);if not targets then return nil,err end
    config.entries=copy(resolved.echoes);config.name=resolved.name or "Wishlist"
    config.fingerprint=fingerprint(config.entries);config.selectedSlot=resolved.slot;config.origin="selected"
    config.sources={};config.excluded={}
    return changedConfig()
end
function M.UseAssignedWishlist()
    if not editable() then return nil,"Stop and settle the current Orb operation before changing targets." end
    local wl=Nexus.GameAdapter.Wishlist();if not wl then return nil,"Assign a resolved Wishlist first, or choose one in this panel." end
    local targets,err=P.Normalize(wl.entries);if not targets then return nil,err end
    config.entries=copy(wl.entries);config.name=wl.name;config.fingerprint=fingerprint(config.entries)
    config.selectedSlot=nil;config.origin="assigned";config.sources={};config.excluded={}
    return changedConfig()
end
function M.MoveTarget(index,delta)
    if not editable() then return nil,"Targets are fixed during this run." end
    local j=index+delta
    if not integer(index,1,#config.entries) or not integer(j,1,#config.entries) then return false end
    config.entries[index],config.entries[j]=config.entries[j],config.entries[index]
    -- Order is a user preference; comparison to original source remains multiset based.
    return changedConfig()
end
local function sameContent(a,b)
    local x,y={},{};for _,e in ipairs(a or {}) do x[#x+1]=fingerprint({e}) end
    for _,e in ipairs(b or {}) do y[#y+1]=fingerprint({e}) end
    table.sort(x);table.sort(y);return table.concat(x,",")==table.concat(y,",")
end
entriesStillMatch=function()
    if config.origin=="assigned" then
        local w=Nexus.GameAdapter.Wishlist();return w and sameContent(config.entries,w.entries) or false
    end
    if not config.selectedSlot then return true end
    for _,c in ipairs(Nexus.GameAdapter.GetWishlistCandidates()) do if c.slot==config.selectedSlot then
        local r,st=Nexus.GameAdapter.ResolveWishlistEvidence(c)
        return st=="actionable" and r and sameContent(config.entries,r.echoes) or false
    end end
    return false
end
function M.SetLimit(n)
    init();n=tonumber(n)
    if not integer(n,1,10000) then return nil,"Choose a whole-number Orb limit from 1 to 10,000." end
    if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"Use Increase limit while paused, or finish this run first." end
    config.maxOrbs=n;return changedConfig()
end
function M.SetRecycle(enabled)
    if not editable() then return nil,"Recycling permission is fixed during this run." end
    config.recycle=enabled==true;return changedConfig()
end
function M.SetSource(k,n)
    if not editable() then return nil,"Replaceable copies are fixed during this run." end
    local s,err=B.Read();if not s then return nil,err end
    local targets,e=P.Normalize(config.entries);if not targets then return nil,e end
    if not integer(n,0,79) then return nil,"Choose a valid source-copy count." end
    local available=0
    for _,r in ipairs(P.Sources(targets,s,config.excluded)) do if r.key==k then available=r.excess end end
    if n>available then return nil,"That would replace a protected or unavailable copy." end
    config.sources[k]=n>0 and n or nil;return changedConfig()
end
function M.Exclude(k,enabled)
    if not editable() then return nil,"Exclusions are fixed during this run." end
    if type(k)~="string" or not k:match("^%d+:%d+$") then return nil,"Choose an Echo first." end
    config.excluded[k]=enabled==true and true or nil
    if enabled then config.sources[k]=nil end
    return changedConfig()
end
function M.ClearExclusions()
    if not editable() then return nil,"Exclusions are fixed during this run." end
    config.excluded={};return changedConfig()
end
function M.SuggestSources()
    if not editable() then return nil,"Stop and settle the current run first." end
    local s,err=B.Read();if not s then return nil,err end
    local targets,e=P.Normalize(config.entries);if not targets then return nil,e end
    local proposed={};for _,r in ipairs(P.Sources(targets,s,config.excluded)) do proposed[r.key]=r.excess end
    config.sources=proposed;return changedConfig()
end
local function inspect()
    local targets,err=P.Normalize(config.entries);if not targets then return nil,err end
    local s,e=B.Read();if not s then return nil,e end
    local prog=P.Progress(targets,s)
    local sources=P.Sources(targets,s,config.excluded)
    return {targets=targets,s=s,progress=prog,sources=sources}
end
local function preflight()
    local m,err=inspect();if not m then return nil,err end
    if not entriesStillMatch() then return nil,"The selected Wishlist changed or is unavailable. Choose it again before starting." end
    if m.progress.rolledMissing==0 then
        return nil,m.progress.permanentMissing>0 and "Rolled targets are complete. Remaining permanent-slot targets cannot be changed by Orbs; no spend will start."
            or "All rolled targets are already complete. No Orbs are needed."
    end
    for _,t in ipairs(m.progress.items) do
        local r=m.s.catalog[t.spellId]
        if t.role=="rolled" and t.missing>0 and (not r or not r.available or r.quality~=t.quality) then return nil,"A missing target is currently unavailable: "..(r and r.name or t.spellId).."." end
    end
    if m.s.charges<1 then return nil,"No confirmed Orbs are available." end
    if m.s.autoAccept then return nil,"Turn off the game's automatic Echo acceptance first." end
    if m.s.hostPending or #m.s.board>0 or m.s.offerPending or Nexus.GameAdapter.InFlight() then return nil,"Resolve the current Echo action before starting Orb mode." end
    if Nexus.GameAdapter.RivalDetected() then return nil,"Disable the other Echo automation addon before starting Orb mode." end
    local capacity=0;local permitted={}
    for _,r in ipairs(m.sources) do
        local n=config.sources[r.key] or 0
        if not integer(n,0,r.excess) then return nil,"Your approved replaceable counts changed. Review them again." end
        if n>0 then permitted[r.key]=n;capacity=capacity+n end
    end
    for k,n in pairs(config.sources) do if n>0 and not permitted[k] then return nil,"An approved source is no longer safe. Review the replacement pool." end end
    if capacity<1 then return nil,"Choose at least one replaceable copy and approve it before starting." end
    m.permitted=permitted;m.capacity=capacity;return m
end
function M.Prepare(mode)
    init();if run.running or run.pending or run.state=="PAUSED" or run.state=="LIMIT" then return nil,"An Orb run is already active or unresolved. Stop/settle it before starting another." end
    local m,err=preflight();if not m then return nil,err end
    local limit=mode=="single" and 1 or config.maxOrbs
    approval={token={},model=m,entries=copy(config.entries),sources=copy(m.permitted),
        excluded=copy(config.excluded),recycle=config.recycle,limit=limit,created=now()}
    local listed={};for _,s in ipairs(m.sources) do if m.permitted[s.key] then
        listed[#listed+1]={name=s.name,spellId=s.spellId,quality=s.quality,copies=m.permitted[s.key],key=s.key}
    end end
    return {token=approval.token,limit=limit,charges=m.s.charges,sources=listed,targets=copy(m.progress.items),
        name=config.name,recycle=config.recycle,sourceCopies=m.capacity}
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

local function ensureFrame()
    if frame then frame:Show();return end
    frame=CreateFrame("Frame","NexusOrbRuntime",UIParent)
    frame:RegisterEvent("PLAYER_LOGOUT");frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:SetScript("OnEvent",function()
        init();if run.running or run.pending then
            run.running=false;setState("PAUSED","Session interrupted. Orb spending will not restart automatically.")
            if run.pending then savePending() else release() end
        end
    end)
    local elapsed=0
    frame:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+(dt or 0);if elapsed<.2 then return end;elapsed=0
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
    local m,err=preflight();if not m then return nil,err end
    if not sameContent(a.entries,config.entries) or not B.SameContext(a.model.s.context,m.s.context)
        or a.model.s.grantedKey~=m.s.grantedKey or a.model.s.lockedKey~=m.s.lockedKey
        or a.model.s.charges~=m.s.charges then approval=nil;return nil,"Echoes or resources changed while confirming. Review again." end
    local off,e=turnAutoOff();if not off then return nil,e end
    local tokenOwner,live=B.Acquire(m.s);if not tokenOwner then return nil,live end
    run={state="READY",running=true,reason="Approved. Preparing one Orb replacement.",token=tokenOwner,
        targets=copy(a.model.targets),entries=copy(config.entries),remaining=copy(a.sources),excluded=copy(a.excluded),
        recycle=a.recycle,limit=a.limit,spent=0,reserved=0,recent={},context=live.context}
    approval=nil;ensureFrame();M.Pump();return true
end
local function finishResult(s,p)
    if p.restored and not p.baselineStamp then p.baselineStamp=s.grantStamp;return false end
    local fresh=s.grantStamp>(p.restored and p.baselineStamp or p.selectionStamp or p.beforeStamp)
    if not fresh or s.offerPending or #s.board>0 or s.hostPending then return false end
    if s.lockedKey~=p.lockedKey then pause("Permanent Echoes changed during the operation. Resolve the result manually.");return false end
    if s.charges~=p.chargesBefore-1 then return false end
    local gained,status=P.SingleGain(p.before,p.removed,s.granted)
    if status=="WAIT" then return false end
    if status~="CONFIRMED" or (p.selectedKey and gained~=p.selectedKey) then
        pause("Echo ownership does not match the expected replacement. No further Orb will be spent.");return false
    end
    if not p.spendConfirmed then run.spent=run.spent+1;p.spendConfirmed=true;run.reserved=0 end
    run.recent[#run.recent+1]={removed=p.removed,obtained=gained,at=now()}
    while #run.recent>5 do table.remove(run.recent,1) end
    run.pending=nil
    local ok,err=savePending();if not ok then run.pending=p;pause(err);return false end
    if p.restored then terminal("STOPPED","Previous result confirmed. No spending restarted; review a new run explicitly.");return true end
    local progress=P.Progress(run.targets,s)
    run.recycleKey=nil
    if p.kind=="RECYCLE" and run.recycle then
        for _,r in ipairs(P.Sources(run.targets,s,run.excluded)) do if r.key==gained then run.recycleKey=gained end end
    end
    if progress.rolledMissing==0 then
        terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
            progress.permanentMissing==0 and "All selected targets are complete." or "Rolled targets are complete. Remaining permanent targets are unchanged; no more Orbs will be spent.")
    elseif not run.running then
        setState(run.state=="STOPPED" and "STOPPED" or "PAUSED","Last replacement confirmed; no next Orb will be spent until you explicitly continue.")
        if run.state=="STOPPED" then release() end
    elseif run.spent+run.reserved>=run.limit then terminal("LIMIT","The approved Orb limit was reached.")
    else setState("READY","Replacement confirmed. Preparing the next approved Orb.") end
    return true
end
function M.Pump()
    init();if advancing or (not run.running and not run.pending) then return end
    advancing=true
    local function step()
        local s,err=B.Read();if not s then pause(err);return end
        local p=run.pending
        if p and p.restored then
            if p.guid~=s.context.guid then pause("The earlier Orb action belongs to another character.");return end
            if not p.baselineStamp then p.baselineStamp=s.grantStamp end
            if finishResult(s,p) then return end
            setState("RECOVERY","An earlier action remains unresolved. Resolve the native offer, then Recheck; no new spend is allowed.")
            return
        end
        if run.context and not B.SameContext(run.context,s.context) then pause("Character, run, or loadout changed. The pending operation will not be replayed.");return end
        if p then
            if s.lockedKey~=p.lockedKey then pause("Permanent Echoes changed; no further Orb action will be submitted.");return end
            if not p.spendConfirmed and s.charges==p.chargesBefore-1 and s.offerPending then
                p.spendConfirmed=true;run.spent=run.spent+1;run.reserved=0
                local ok,e=savePending();if not ok then pause(e);return end
            elseif s.charges~=p.chargesBefore and s.charges~=p.chargesBefore-1 then
                pause("The Orb balance changed unexpectedly. No further action will be submitted.");return
            end
            if finishResult(s,p) then return end
            if not run.running then return end
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
                p.selectionStamp=s.grantStamp;p.since=now();p.refreshRequested=false
                local saved,e=savePending();if not saved then p.selectionAttempted=false;pause(e);return end
                local accepted,kind,reason=B.Select(run.token,decision.index,s.boardKey,decision.spellId)
                if not accepted then p.selectionAmbiguous=kind=="AMBIGUOUS";p.selectionRefused=kind=="REJECTED";savePending();pause(reason);return end
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
        if not run.running then return end
        if not entriesStillMatch() then pause("The selected Wishlist changed; review a new run before spending.");return end
        local progress=P.Progress(run.targets,s)
        if progress.rolledMissing==0 then
            terminal(progress.permanentMissing==0 and "COMPLETE" or "ROLLED_COMPLETE",
                progress.permanentMissing==0 and "All selected targets are complete." or "Rolled targets are complete; Orbs cannot change the remaining permanent targets.");return
        end
        for _,target in ipairs(progress.items) do
            local row=s.catalog[target.spellId]
            if target.role=="rolled" and target.missing>0 and (not row or not row.available or row.quality~=target.quality) then
                pause("A required target is no longer available. No next Orb will be spent.");return
            end
        end
        if run.spent+run.reserved>=run.limit then terminal("LIMIT","The approved Orb limit was reached.");return end
        if s.charges<1 then terminal("OUT_OF_ORBS","No Orbs remain. New resources will not restart this run automatically.");return end
        if s.offerPending or #s.board>0 or s.hostPending then pause("Another Echo action is active. Resolve it first.");return end
        if s.autoAccept then pause("Turn off the game's automatic Echo acceptance before continuing.");return end
        if Nexus.GameAdapter.RivalDetected() then pause("Another Echo picker is active. Disable it before continuing.");return end
        local source
        local safe=P.Sources(run.targets,s,run.excluded)
        for _,r in ipairs(safe) do if r.key==run.recycleKey then source=r;break end end
        if not source then for _,r in ipairs(safe) do if (run.remaining[r.key] or 0)>0 then source=r;break end end end
        if not source then terminal("NO_SOURCES","No approved safe source copies remain. Review a new run to change the pool.");return end
        local recycle=source.key==run.recycleKey
        p={before=copy(s.granted),lockedKey=s.lockedKey,removed=source.key,chargesBefore=s.charges,
            beforeStamp=s.grantStamp,since=now(),guid=s.context.guid,spendConfirmed=false}
        run.pending=p;run.reserved=1
        local ok,e=savePending();if not ok then run.pending=nil;run.reserved=0;pause(e);return end
        if not recycle then run.remaining[source.key]=math.max(0,(run.remaining[source.key] or 0)-1) end
        local accepted,kind,reason=B.Spend(run.token,source.key,s)
        if not accepted then
            if kind=="REJECTED" then
                if not recycle then run.remaining[source.key]=(run.remaining[source.key] or 0)+1 end
                run.pending=nil;run.reserved=0;savePending()
            else p.ambiguous=true;savePending() end
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
    if not run.pending then release() end;return true
end
function M.Resume()
    init();if run.state~="PAUSED" then return nil,"Only an explicitly paused run can resume." end
    if run.pending and (run.pending.restored or run.pending.selectionAttempted) then return nil,"The submitted result is still unresolved. Recheck or finish the native offer manually; no repeat is allowed." end
    local s,err=B.Read();if not s then return nil,err end
    if not run.context or not B.SameContext(run.context,s.context) or not entriesStillMatch() then return nil,"The original run no longer matches. Stop and review a new run after settlement." end
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
    run.limit=a.value;run.limitApproval=nil
    if run.pending then local ok,e=savePending();if not ok then return nil,e end end
    setState(run.pending and "PAUSED" or "PAUSED","Limit increased by confirmation. Press Resume explicitly; usage was not reset.")
    return true
end
function M.Recheck()
    init();if run.lastRecheck and now()-run.lastRecheck<3 then return nil,"Please wait before requesting another refresh." end
    run.lastRecheck=now()
    if run.pending and run.pending.restored and not run.pending.baselineStamp then
        local s=B.Read();if s then run.pending.baselineStamp=s.grantStamp end
    end
    local ok,err=B.RequestRefresh();if not ok then return nil,err end
    if run.pending then ensureFrame();M.Pump() end
    return true,"Requested an Orb/ownership refresh. No Orb or choice was submitted."
end
function M.BlocksOrdinary()
    if not config then
        local st=Nexus.Store and Nexus.Store.State and Nexus.Store.State()
        if not st then return false end
        if type(st.orbRefinement)=="table" and st.orbRefinement.pending then init() end
    end
    return run and (run.running or run.pending~=nil or (run.state=="PAUSED" or run.state=="LIMIT")) or false
end
function M.Status()
    init();local m,err=inspect()
    local r={state=run.state,reason=run.reason,error=err,running=run.running,pending=run.pending~=nil,
        spent=run.spent,reserved=run.reserved,limit=run.limit,config=copy(config),recent=copy(run.recent)}
    r.config.pending=nil
    if m then r.charges=m.s.charges;r.progress=copy(m.progress);r.sources=copy(m.sources);r.catalog=copy(m.s.catalog) end
    return r
end
