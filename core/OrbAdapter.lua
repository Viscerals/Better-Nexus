-- Nexus: Orb of Lost Memories game boundary.
-- EchoWeaver Orb mode: only the public OrbService and PerkService calls listed
-- in THIRD_PARTY.md. Capability detection is read-only; no speculative spend/selection.
Nexus = Nexus or {}
local A = assert(Nexus.GameAdapter, "OrbAdapter requires GameAdapter")
local O = {}
A.Orbs = O
local owner, ownerContext
local observations = { serial=0, grantedRef=nil, grantedSig=nil }
local selectionSerial,selection=0,nil
local watched={}
local MAX_ROWS = 512
local function integer(n, minimum)
    return type(n)=="number" and n==math.floor(n) and n<math.huge
        and n>-math.huge and n>=(minimum or 0)
end
local function copy(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function call(t,k,...)
    if type(t)~="table" or type(t[k])~="function" then return false,nil end
    return pcall(t[k],...)
end
-- Whether the client has received its build-slot data since it loaded. Until
-- the first build-slot reply the client keeps GetServerBuildSlots() nil and its
-- active slot at the load-time default 0 ("none"), which is no observation of
-- the server's slot. nil: this client cannot say (no getter), as before.
local function slotKnown(svc)
    if type(svc)~="table" or type(svc.GetServerBuildSlots)~="function" then return nil end
    local ok,slots=pcall(svc.GetServerBuildSlots)
    return ok and type(slots)=="table"
end
-- Every read: the Echo reconciliation only, not the five-second fallback
-- signature (GameAdapter.EchoActiveSlotGeneration). The reconciliation stays
-- for its effect: Echo changes (slot, owned, locked) are seen at this read.
local function ctx(pe,svc,orb)
    local active=A.EchoActiveSlotGeneration and A.EchoActiveSlotGeneration() or nil
    local owned=A.Owned and A.Owned() or {}
    return {pe=pe,svc=svc,orb=orb,guid=UnitGUID and UnitGUID("player"),
        generation=owned.generation,level=A.Level and A.Level(),
        active=active,slot=pe and pe.Perks and pe.Perks.serverActiveSlot,
        slotKnown=slotKnown(svc)}
end
local function same(a,b)
    return type(a)=="table" and type(b)=="table" and a.pe==b.pe and a.svc==b.svc
        and a.orb==b.orb and a.guid==b.guid and a.generation==b.generation
        and a.level==b.level and a.slot==b.slot
end
local function signature(counts)
    local keys={};for k in pairs(counts) do keys[#keys+1]=k end;table.sort(keys)
    local out={};for _,k in ipairs(keys) do out[#out+1]=k.."="..counts[k] end
    return table.concat(out,",")
end
local function readCounts(raw,cat)
    if type(raw)~="table" or getmetatable(raw) then return nil,"Echo ownership is unavailable." end
    local counts,rows,total={},0,0
    local function record(e)
        rows=rows+1;if rows>MAX_ROWS or type(e)~="table" or getmetatable(e) then return false end
        local id=tonumber(e.spellId);local n=e.stacks or e.stack or 1
        local c=id and cat.rows[id]
        local q=e.quality;if q==nil and c then q=c.quality end
        if not integer(id,1) or not c or not integer(q,0) or q>255
            or not integer(n,1) or n>85 then return false end
        total=total+n;if total>85 then return false end
        local k=tostring(id)..":"..tostring(q);counts[k]=(counts[k] or 0)+n
        return true
    end
    local keys=0
    for _,v in pairs(raw) do
        keys=keys+1;if keys>MAX_ROWS or type(v)~="table" then return nil,"Echo ownership has an unsupported shape." end
        if v.spellId~=nil then
            if not record(v) then return nil,"Echo ownership could not be verified." end
        else
            for _,e in pairs(v) do if not record(e) then return nil,"Echo ownership could not be verified." end end
        end
    end
    return counts,nil,total
end
local function hostPending(pe)
    local p=pe and pe.Perks
    if type(p)~="table" then return nil end
    return p.pendingSelectSpellId~=nil or p.pendingBanishIndex~=nil
        or p.pendingFreezeIndex~=nil or p.pendingReroll==true
        or p.pendingLockSpellId~=nil or p.pendingUnlockSpellId~=nil
end
-- Single owner of the OrbService known/pending classification for callers that
-- are not Orb mode (the ordinary-board gate). Read-only. Returns
-- capability, status, reason:
--   NO_ORB_SERVICE / ABSENT   explicit legacy capability: the client has no OrbService
--                             at all (no ProjectEbonhold table, or its OrbService is nil)
--   MISSING_STATE             an OrbService exists but has no IsStateKnown member: it
--                             cannot say whether its pending answer is authoritative
--   STATE_AWARE               the supported service: IsStateKnown and IsOfferPending
--   MALFORMED                 the OrbService value or one of its members has the wrong
--                             type, IsOfferPending is missing, or reading it throws
-- status IDLE (known AND not pending) is the only answer of an existing service
-- that permits ordinary mutation. UNKNOWN is never folded into not-pending: a
-- service that does not know its state, or cannot say so, cannot vouch for its
-- pending flag. (Until 2026-09-21 a service without IsStateKnown was permitted
-- as "PENDING_ONLY"; the user's R1 requirement names only a genuinely absent
-- OrbService as the legacy exception, so that permit was removed.)
function O.ServiceState()
    local pe=_G.ProjectEbonhold;local orb=nil
    if type(pe)=="table" then
        local okRead,value=pcall(function()return pe.OrbService end)
        if not okRead then return "MALFORMED","UNAVAILABLE","orb state unavailable" end
        orb=value
    end
    if orb==nil then return "NO_ORB_SERVICE","ABSENT" end
    if type(orb)~="table" then return "MALFORMED","UNAVAILABLE","orb state unavailable" end
    local okM,isKnown,isPending=pcall(function()return orb.IsStateKnown,orb.IsOfferPending end)
    if not okM or type(isPending)~="function"
        or (isKnown~=nil and type(isKnown)~="function") then
        return "MALFORMED","UNAVAILABLE","orb state unavailable"
    end
    if isKnown==nil then return "MISSING_STATE","UNAVAILABLE","orb state capability missing" end
    local capability="STATE_AWARE"
    do
        local okK,known=call(orb,"IsStateKnown")
        if not okK or type(known)~="boolean" then return capability,"INVALID","orb state unknown" end
        if not known then return capability,"UNKNOWN","orb state not yet known" end
    end
    local okP,pending=call(orb,"IsOfferPending")
    if not okP or type(pending)~="boolean" then return capability,"INVALID","orb state unknown" end
    if pending then return capability,"PENDING","Orb offer active -- manual action required" end
    return capability,"IDLE"
end
function O.Balance()
    local pe=_G.ProjectEbonhold;local orb=pe and pe.OrbService
    if type(orb)~="table" or type(orb.IsStateKnown)~="function" or type(orb.GetCharges)~="function" then
        return nil,"unsupported","The client does not expose the Orb balance capability."
    end
    local ok,known=call(orb,"IsStateKnown")
    if not ok or type(known)~="boolean" then return nil,"unknown","Orb balance state is unavailable." end
    if not known then return nil,"loading","Waiting for the server's Orb balance." end
    local read,n=call(orb,"GetCharges")
    if not read or not integer(n,0) then return nil,"unknown","Orb balance is unavailable or invalid." end
    return n,"confirmed"
end
function O.Read()
    local pe=_G.ProjectEbonhold;local svc=pe and pe.PerkService;local orb=pe and pe.OrbService
    for _,name in ipairs({"IsStateKnown","GetCharges","IsOfferPending","ConfirmSpend","RequestCharges"}) do
        if type(orb)~="table" or type(orb[name])~="function" then
            return nil,"Orb mode is unavailable: the client does not expose OrbService."..name.."."
        end
    end
    for _,name in ipairs({"GetGrantedPerks","GetLockedPerks","GetCurrentChoice","SelectPerk","RequestGrantedPerks"}) do
        if type(svc)~="table" or type(svc[name])~="function" then
            return nil,"Orb mode is unavailable: the client does not expose PerkService."..name.."."
        end
    end
    local okK,known=call(orb,"IsStateKnown");local okC,charges=call(orb,"GetCharges")
    local okP,pending=call(orb,"IsOfferPending")
    if not okK or not okC or not okP or type(known)~="boolean" or type(pending)~="boolean" then
        return nil,"The game's Orb state could not be read. No Orb will be spent."
    end
    if not known then return nil,"Waiting for the server's Orb balance. Use Recheck once it is available." end
    if not integer(charges,0) then return nil,"The server's Orb balance is invalid." end
    local cat=A.Catalog and A.Catalog();if not cat or type(cat.rows)~="table" then return nil,"The local Echo catalog is not ready." end
    local trusted=A.Owned and A.Owned();local locked=A.LockedOwned and A.LockedOwned()
    if not trusted or not trusted.synced or not locked or not locked.synced then
        return nil,"Waiting for current rolled and locked Echo data from the server."
    end
    local okG,rawG=call(svc,"GetGrantedPerks");local okL,rawL=call(svc,"GetLockedPerks")
    if not okG or not okL then return nil,"Echo ownership could not be read." end
    local granted,err,totalG=readCounts(rawG,cat);if not granted then return nil,err end
    local locks,errL,totalL=readCounts(rawL,cat);if not locks then return nil,errL end
    if totalG>79 or totalL>6 then return nil,"The current rolled/locked Echo counts exceed the supported limits." end
    local sig=signature(granted)
    if observations.grantedRef~=rawG or observations.grantedSig~=sig then
        observations.serial=observations.serial+1;observations.grantedRef=rawG;observations.grantedSig=sig
    end
    local okB,rawB=call(svc,"GetCurrentChoice")
    if not okB or (rawB~=nil and type(rawB)~="table") then return nil,"The current Echo choices are unavailable." end
    local board,parts={},{}
    for i,c in ipairs(rawB or {}) do
        if i>3 or type(c)~="table" or not integer(c.spellId,1) then return nil,"The current Echo offer is invalid." end
        local row=cat.rows[c.spellId];local q=c.quality or (row and row.quality)
        if not row or not integer(q,0) then return nil,"The current Echo offer has unknown quality." end
        board[i]={spellId=c.spellId,quality=q,index=i,selectable=c.selectable~=false}
        parts[i]=c.spellId..":"..q..":"..tostring(c.selectable~=false)
    end
    if #board~=0 and #board~=3 then return nil,"Waiting for the complete three-choice offer." end
    local opts=_G.ProjectEbonholdOptionsService
    if type(opts)~="table" or type(opts.GetSetting)~="function" then return nil,"Cannot verify the game's automatic Echo-choice setting." end
    local okAuto,auto=pcall(opts.GetSetting,opts,"autoAcceptLoadoutEchoes")
    if not okAuto or type(auto)~="boolean" then return nil,"Cannot verify the game's automatic Echo-choice setting." end
    local host=hostPending(pe);if host==nil then return nil,"Cannot verify pending game actions." end
    -- Use the existing Nexus / supplied integration discovery boundary.
    -- Missing optional availability information is unknown, never permission.
    local okD,discovered=call(svc,"GetDiscoveredEchoes")
    local discoveryKnown=pe.Perks and pe.Perks.discoveredEchoes~=nil and okD and type(discovered)=="table"
    local observed={}
    for k,n in pairs(granted) do if n>0 then observed[tonumber(k:match("^(%d+):"))]=true end end
    for k,n in pairs(locks) do if n>0 then observed[tonumber(k:match("^(%d+):"))]=true end end
    for _,c in ipairs(board) do observed[c.spellId]=true end
    -- Availability rows are built on first use, per read, for the IDs this read
    -- is asked about (targets, owned copies, offered cards), not for the whole
    -- catalog on every read. Each row uses exactly the rules below; nothing is
    -- carried over from an earlier read, so every action still reads fresh.
    local function buildRow(id,row)
        local raw=type(pe.PerkDatabase)=="table" and pe.PerkDatabase[id]
        -- The ordinary adapter deliberately retains its last complete catalog
        -- during source loss. Keep its group/requirement metadata, but require
        -- a matching live entry before this row can authorize an Orb action.
        local g=tonumber(row.groupId)
        local gated=(tonumber(row.requiredSpell) or 0)~=0
        local metadataKnown=type(raw)=="table"
            and tonumber(raw.requiredSpell or 0)==(tonumber(row.requiredSpell) or 0)
            and tonumber(raw.groupId or 0)==(tonumber(row.groupId) or 0)
        local learned=not gated or (discoveryKnown and (discovered[id]~=nil or observed[id]==true))
        local mask=tonumber(row.classMask or (raw and raw.classMask)) or 0
        local allowedClass=mask==0 or mask==1535 or (bit and bit.band and bit.band(mask,cat.playerMask or 0)~=0)
        local disabled,reason=false,nil
        if not metadataKnown then
            reason="The live Echo catalog entry is unavailable or changed. Wait for verified catalog data."
        elseif gated then
            if not discoveryKnown then reason="Echo discovery data or GetDiscoveredEchoes is unavailable."
            elseif not learned then reason="This Echo has not been discovered or observed."
            elseif type(svc.IsTomeEchoDisabled)~="function" then reason="PerkService.IsTomeEchoDisabled is unavailable."
            else
                local okDisabled,d=call(svc,"IsTomeEchoDisabled",id)
                if not okDisabled or type(d)~="boolean" then reason="PerkService.IsTomeEchoDisabled did not provide a known answer."
                elseif d then disabled=true;reason="The server reports that this Echo is disabled." end
            end
        end
        return {spellId=id,name=row.name or (GetSpellInfo and GetSpellInfo(id)) or ("Echo "..id),
            quality=row.quality or 0,maxStack=tonumber(row.maxStack) or 1,
            group=integer(g,1) and ("g:"..g) or ("s:"..id),available=allowedClass and learned and not disabled and not reason,
            sourceAvailable=metadataKnown,
            availabilityReason=reason or (not allowedClass and "This Echo is unavailable to this class." or nil)}
    end
    local catalogRows=cat.rows
    local rows=setmetatable({},{__index=function(t,id)
        local row=catalogRows[id]
        if type(row)~="table" then return nil end
        local built=buildRow(id,row);rawset(t,id,built);return built
    end})
    local s={known=true,charges=charges,offerPending=pending,board=board,boardKey=table.concat(parts,","),
        granted=granted,locked=locks,grantStamp=observations.serial,grantedKey=sig,lockedKey=signature(locks),
        hostPending=host,autoAccept=auto,catalog=rows,context=ctx(pe,svc,orb),at=GetTime and GetTime() or 0,
        selectionSerial=selectionSerial,selection=copy(selection),
        -- The Echo whose choice the game still holds unanswered (its own pick
        -- latch), or nil. Read only; used for the status text.
        selectInFlight=tonumber(pe.Perks.pendingSelectSpellId)}
    return s
end
function O.SameContext(a,b) return same(a,b) end
function O.SameOwner(a,b)
    return type(a)=="table" and type(b)=="table" and a.pe==b.pe and a.svc==b.svc
        and a.orb==b.orb and a.guid==b.guid and a.generation==b.generation and a.level==b.level
end
function O.Rebind(token,expected)
    if not owner or token~=owner then return nil,"This run no longer owns Orb actions." end
    local fresh,err=O.Read();if not fresh then return nil,err end
    if not O.SameOwner(ownerContext,fresh.context) or not expected or not same(expected.context,fresh.context)
        or fresh.offerPending or #fresh.board>0 or fresh.hostPending or A.InFlight() then
        return nil,"The original owner or a pending action prevents resuming."
    end
    ownerContext=fresh.context;return true
end
-- Observe native manual settlement without replacing any game handler.
-- The pending ID and exact visible offer tie this observation to a choice.
-- The observer is read-only. It serves the action owner, or, after a reload,
-- a passive recovery watcher that holds no action token and cannot mutate.
local watcherContext,watcherNotify
-- The owner's evidence sink and its immediate notification (OrbRuntime registers
-- both once at load; see O.CaptureSink). selfSelecting is true only while
-- O.Select itself calls SelectPerk: that pick is saved before the call, so it is
-- not captured again as an observation.
local captureSink,ownerNotify,capturePhase
local selfSelecting=false
-- The plain facts of one SelectPerk callback, read from the game's own tables the
-- moment it happens. No O.Read(): it needs the catalog, a synced ownership view
-- and an equal context, so it fails exactly when a loading screen or a server push
-- is under way. Everything returned is a number, a boolean or a short text.
-- NON-AUTHORITATIVE: the runtime keeps it as evidence, never as a selection.
local function rawBoard(perks)
    local raw=type(perks)=="table" and perks.currentChoice or nil
    if raw==nil then return "",{} end
    if type(raw)~="table" or getmetatable(raw) then return nil,nil end
    local cards,parts={},{}
    for i=1,4 do
        local c=raw[i]
        if c==nil then break end
        if i>3 or type(c)~="table" or getmetatable(c) or not integer(c.spellId,1) then return nil,nil end
        local q=integer(c.quality,0) and c.quality<=255 and c.quality or nil
        cards[i]={id=c.spellId,q=q,selectable=c.selectable~=false}
        parts[i]=c.spellId..":"..(q and tostring(q) or "?")
    end
    return table.concat(parts,","),cards
end
local function rawPick(svc,id)
    local pe=_G.ProjectEbonhold
    local perks=type(pe)=="table" and type(pe.Perks)=="table" and pe.Perks or nil
    local raw={id=integer(id,1) and id or nil}
    raw.board,raw.cards=rawBoard(perks)
    if perks then
        local latch=perks.pendingSelectSpellId
        raw.acc=latch~=nil and latch==id
        local slot=perks.serverActiveSlot
        if integer(slot,0) and slot<=65535 then raw.slot=slot==0 and 0 or slot end
    end
    raw.sk=slotKnown(svc)
    if raw.cards and raw.id then
        -- The quality is named only when exactly one card carries this Echo.
        local matches,quality=0,nil
        for _,c in ipairs(raw.cards) do if c.id==raw.id then matches=matches+1;quality=c.q end end
        raw.inb=matches>0
        if matches==1 then raw.q=quality end
    end
    local orb=type(pe)=="table" and pe.OrbService or nil
    local okP,pending=call(orb,"IsOfferPending")
    if okP and type(pending)=="boolean" then raw.op=pending end
    return raw
end
-- The contextual observation: needs a context, a successful read, an equal
-- context, an open three-card offer and the game's own pick latch holding this
-- Echo. Returns what it concluded: "ok" (the choice was recorded), "noctx" (no
-- owner or watcher context), "fail" (the read failed), "diff" (the context
-- differs), "state" (not a recordable pick).
local function observe(svc,id)
    local c=ownerContext or watcherContext
    if not c or c.svc~=svc then return "noctx" end
    local s=O.Read()
    if not s then return "fail" end
    if not same(c,s.context) then return "diff" end
    if not s.offerPending or #s.board~=3
        or type(c.pe.Perks)~="table" or c.pe.Perks.pendingSelectSpellId~=id then return "state" end
    local chosen
    for _,card in ipairs(s.board) do if card.spellId==id then
        local k=id..":"..card.quality
        if chosen and chosen~=k then return "state" end
        chosen=k
    end end
    if not chosen then return "state" end
    selectionSerial=selectionSerial+1
    -- onlyAction: the observed SelectPerk is the single host action in
    -- flight, so "host pending" at this moment is this very choice.
    local perks=c.pe.Perks
    local only=perks.pendingBanishIndex==nil and perks.pendingFreezeIndex==nil
        and perks.pendingReroll~=true and perks.pendingLockSpellId==nil and perks.pendingUnlockSpellId==nil
    selection={serial=selectionSerial,key=chosen,boardKey=s.boardKey,grantStamp=s.grantStamp,onlyAction=only}
    -- Event-driven observation: tell the passive watcher (after a reload), or
    -- the action owner's receipt, now, so that the record does not wait for the
    -- next timed read and a reload or logout in that gap cannot lose it.
    -- Read-only listeners; an error in them never reaches the game's call.
    if not owner and watcherNotify then pcall(watcherNotify)
    elseif owner and ownerNotify then pcall(ownerNotify) end
    return "ok"
end
local function watchChoices(svc)
    if watched[svc] then return true end
    if type(hooksecurefunc)~="function" or type(svc)~="table" or type(svc.SelectPerk)~="function" then return false end
    local ok=pcall(hooksecurefunc,svc,"SelectPerk",function(id)
        -- Nothing in this hook may reach the game's caller: the host function has
        -- already run, and its return values and errors are its own. An instance
        -- that a reload superseded (the harness keeps the old wrapper) is inert.
        if A.Orbs~=O then return end
        local raw
        if captureSink and not selfSelecting then
            local okR,r=pcall(rawPick,svc,id)
            if okR and type(r)=="table" then raw=r
            else raw={id=integer(id,1) and id or nil} end -- the read failed: the Echo id is still kept
            -- the lifecycle phase AT the callback, before anything below can change it
            if type(capturePhase)=="function" then
                local okP,phase,epoch=pcall(capturePhase)
                if okP then raw.ph,raw.ep=phase,epoch end
            end
        end
        local okO,status=pcall(observe,svc,id)
        if not okO then
            if Nexus.Errors and Nexus.Errors.Record then
                local okT,text=pcall(tostring,status)
                pcall(Nexus.Errors.Record,"OrbAdapter",okT and text or "unreadable error")
            end
            status="err"
        end
        if raw then raw.rd=status;pcall(captureSink,raw) end
    end)
    if ok then watched[svc]=true end
    return ok
end
-- The owner of the Orb receipt registers its evidence sink and its immediate
-- notification once, when it loads; the hook below reaches both.
function O.CaptureSink(sink,notify,phase)
    captureSink=type(sink)=="function" and sink or nil
    ownerNotify=type(notify)=="function" and notify or nil
    capturePhase=type(phase)=="function" and phase or nil
end
-- Install the hook now, without any read: a receipt that exists must not wait for
-- the first successful O.Read() before a pick can be seen. Idempotent; false
-- until the game's PerkService exists.
function O.CaptureStart()
    local pe=_G.ProjectEbonhold
    local svc=type(pe)=="table" and pe.PerkService or nil
    if type(svc)~="table" then return false end
    return watchChoices(svc)==true
end
-- Passive recovery watcher. It takes a snapshot that the caller just read, keeps
-- only its context, and installs the read-only choice observer. It never sets
-- the action owner, so Spend/Select/Rebind stay unavailable to the caller.
function O.Watch(s,notify)
    if type(s)~="table" or type(s.context)~="table" or type(s.context.svc)~="table" then
        return nil,"The current game state is unavailable."
    end
    if not watchChoices(s.context.svc) then
        watcherContext=nil;watcherNotify=nil
        return nil,"This client cannot observe a manual Echo choice."
    end
    watcherContext=s.context;watcherNotify=type(notify)=="function" and notify or nil;return true
end
function O.Unwatch() watcherContext=nil;watcherNotify=nil end
function O.IsOwned() return owner~=nil end
function O.Acquire(s)
    if owner then return nil,"Orb mode already owns an operation." end
    local fresh,err=O.Read();if not fresh then return nil,err end
    if not s or not same(s.context,fresh.context) or s.grantedKey~=fresh.grantedKey
        or s.lockedKey~=fresh.lockedKey or s.charges~=fresh.charges then return nil,"Your Echo state changed. Review the plan again." end
    if fresh.offerPending or #fresh.board>0 or fresh.hostPending or A.InFlight() then return nil,"Resolve the current Echo action first." end
    if fresh.autoAccept then return nil,"Turn off the game's automatic Echo acceptance before starting Orb mode." end
    if A.RivalDetected and A.RivalDetected() then return nil,"Disable the other Echo automation addon before using Orb mode." end
    owner={};ownerContext=fresh.context;selection=nil
    watchChoices(ownerContext.svc)
    return owner,fresh
end
function O.Release(token)
    if token~=owner then return false end
    owner=nil;ownerContext=nil;return true
end
local function validate(token)
    if not owner or token~=owner then return nil,"Orb action ownership is unavailable." end
    local s,err=O.Read();if not s then return nil,err end
    if not same(ownerContext,s.context) then return nil,"The character, loadout, or game service changed. Orb mode is paused." end
    if s.autoAccept or (A.RivalDetected and A.RivalDetected()) then return nil,"Another Echo picker may interfere. Orb mode is paused." end
    if A.DIAGNOSTIC_PASSIVE then return nil,"Actions are blocked in passive diagnostics." end
    return s
end
function O.Spend(token,key,expected,guard)
    local s,err=validate(token);if not s then return nil,"REJECTED",err end
    if s.offerPending or #s.board>0 or s.hostPending or A.InFlight() or s.charges<1 then
        return nil,"REJECTED","Another choice is pending or no Orbs remain."
    end
    if not expected or s.grantedKey~=expected.grantedKey or s.lockedKey~=expected.lockedKey
        or s.charges~=expected.charges or not (s.granted[key] and s.granted[key]>0) then
        return nil,"REJECTED","The approved source or balance changed before spending."
    end
    local id=tonumber(tostring(key):match("^(%d+):%d+$"));if not id then return nil,"REJECTED","Invalid source." end
    if guard and guard(s)~=true then return nil,"REJECTED","Assignment or source protection changed before submission. Resume only after reviewing the current assignment." end
    local ok,value=pcall(ownerContext.orb.ConfirmSpend,id,1)
    if not ok then return nil,"AMBIGUOUS","The spend call failed; its server outcome is unknown. No repeat will be sent." end
    if value==false then return nil,"REJECTED","The game refused the Orb spend." end
    return true,"SUBMITTED"
end
function O.Select(token,index,expectedBoard,id,guard)
    local s,err=validate(token);if not s then return nil,"REJECTED",err end
    local c=s.board[index]
    for _,other in ipairs(s.board) do
        if c and other.spellId==id and other.quality~=c.quality then
            return nil,"REJECTED","The ID-only choice interface cannot distinguish the offered qualities. Resolve the offer manually."
        end
    end
    if not s.offerPending or s.hostPending or not c or not c.selectable or c.spellId~=id
        or not s.catalog[id] or not s.catalog[id].available
        or s.boardKey~=expectedBoard then return nil,"REJECTED","The Orb offer changed or another action is pending." end
    if guard and guard(s)~=true then return nil,"REJECTED","The assigned target changed before selection. The original pending operation must be resolved." end
    selfSelecting=true
    local ok,v=pcall(ownerContext.svc.SelectPerk,id)
    selfSelecting=false
    if not ok or (v~=true and v~=false) then return nil,"AMBIGUOUS","The selection outcome is unknown. No selection will be repeated." end
    if v==false then return nil,"REJECTED","The game refused the Orb choice. Resolve the offer manually." end
    return true,"SUBMITTED",s.grantStamp
end
-- Passive transport observer (035) ---------------------------------------------
-- The audited client (the owner's installed bytes; the reporter's build is NOT
-- verified) delivers every server message through ONE CHAT_MSG_ADDON frame, keeps
-- one handler per opcode, and checks the prefix and the framing, not the sender or
-- the channel. This observer therefore never registers an opcode handler: it
-- listens to the same event in a frame of its own, which leaves the game's frame,
-- handlers, payloads, order and errors alone, and it sends nothing.
--
-- CAPTURE FIRST, EVALUATE LATER. The event handler only classifies and records
-- (class, ordinal, epoch, parsed numbers). It reads no game state, so nothing
-- depends on which frame runs first; whoever evaluates a record reads the game's
-- cache on a later pass, after the game's own handler has run.
--
-- CLASSES. Q: qualifying protocol evidence (opcode 1220 only): exact prefix, the
-- whisper channel, a sender equal to the player's own exact name (a known identity;
-- no cross-realm or short-name alias), a tab and a non-empty body, no segmentation,
-- exactly three fields, canonical bounded integers. A: admitted (sender and channel
-- pass) but not parsed or not qualifying. R: a relevant packet that the game's
-- dispatcher would still have accepted, rejected here (identity, sender or channel).
-- An R, and an A of opcode 1220, may have changed the game's cache, so the opcode
-- is TAINTED (bad[op]) until a later Q (1220) or A (other opcodes) replaces the cache.
-- A raw arrival is never proof of anything beyond "observed after refresh began":
-- the protocol carries no correlation, a local epoch rejects only local work, and an
-- older server reply that arrives later cannot be told from a newer one.
-- Native server sender and channel are NOT TESTED; that the convention (a whisper
-- from the player's own name, as EbonAPI's strict bridge requires) matches the real
-- server is a source-backed expectation, not proof. A mismatch rejects every reply
-- and the counters say so (rejects.sender, rejects.channel, rejects.identity).
local TRANSPORT_PREFIX="AAM0x9"
-- Opcodes whose packets change what Nexus reads from the game's cache: the offer
-- (16), the rolled and locked Echoes (18), the pick result (1000), the build-slot
-- data (540, 542) and the Orb charge reply (1220).
local TRANSPORT_OPS={[16]=true,[18]=true,[540]=true,[542]=true,[1000]=true,[1220]=true}
local TRANSPORT_RING,COUNT_CAP=48,1000000
local T={started=false,epoch=0,ord=0,ring={},requests=0,reqOrd=0,good={},bad={},
    counts={Q=0,A=0,R=0,echo=0,drop=0,other=0,seg=0},
    rejects={identity=0,sender=0,channel=0,segmented=0,third_absent=0,fields_extra=0,malformed=0,range=0,mixed=0}}
local function bump(t,k) t[k]=math.min((t[k] or 0)+1,COUNT_CAP) end
-- A canonical whole number: digits only (a leading minus only where signed), no
-- leading zero, no "-0", at most six digits.
local function canonical(text,signed)
    local negative,digits=false,text
    if signed and text:sub(1,1)=="-" then negative=true;digits=text:sub(2) end
    if digits=="" or digits:find("%D") then return nil,"malformed" end
    if #digits>1 and digits:sub(1,1)=="0" then return nil,"malformed" end
    if negative and digits=="0" then return nil,"malformed" end
    if #digits>6 then return nil,"range" end
    local n=tonumber(digits)
    return negative and -n or n
end
local function parseCharges(body)
    local fields={}
    for part in (body..","):gmatch("([^,]*),") do fields[#fields+1]=part end
    local nf=math.min(#fields,9)
    if #fields<3 then return nil,"third_absent",nf end
    if #fields>3 then return nil,"fields_extra",nf end
    local charges,why=canonical(fields[1],false);if not charges then return nil,why,nf end
    local delta;delta,why=canonical(fields[2],true);if not delta then return nil,why,nf end
    local pending;pending,why=canonical(fields[3],false);if not pending then return nil,why,nf end
    return {charges=charges,delta=delta,pending=pending},nil,nf
end
-- Segmented messages of the opcodes that are followed by arrival only (16, 18, 540, 542, 1000).
-- The game calls a handler only when EVERY fragment of a message has arrived (one assembly per
-- opcode and message id, whatever the sender of each fragment), so a fragment replaces nothing
-- in its cache. Only a COMPLETE message counts as an arrival that replaces what the game
-- cached; an assembly that includes a rejected fragment completes a mixed message and taints.
-- The game follows the FIRST fragment's total (a later fragment's own total is ignored, and a
-- forged fragment inside it is stored), and drops an assembly 15 s after its first fragment. Both are
-- mirrored; the expiry here runs before the lookup (the game's runs after it), so this can only
-- under-count a completion, never over-count one. The format allows 0xFFF fragments, so a large legitimate push is tracked in full.
-- At most SEG_ASSEMBLIES are tracked (the oldest is forgotten and never completes). A fragment
-- outside its assembly (index or total out of range) is an unqualified admitted packet: it taints.
-- Returns "partial", "complete", "mixed" or "range".
local SEG_MAX,SEG_ASSEMBLIES,SEG_EXPIRY=4095,8,15
local assemblies={map={},order={}}
local function segmentNote(op,mid,idxText,totalText,rejected)
    local idx=tonumber(idxText,16)
    local nowT=GetTime and GetTime() or 0
    for key,a in pairs(assemblies.map) do
        if nowT-a.t0>SEG_EXPIRY then
            assemblies.map[key]=nil
            for i,k in ipairs(assemblies.order) do if k==key then table.remove(assemblies.order,i);break end end
        end
    end
    local key=op..":"..mid
    local a=assemblies.map[key]
    local total=a and a.total or tonumber(totalText,16)
    if total<1 or total>SEG_MAX or idx<1 or idx>total then return "range" end
    if not a then
        a={total=total,got=0,parts={},bad=false,t0=nowT}
        assemblies.map[key]=a;assemblies.order[#assemblies.order+1]=key
        while #assemblies.order>SEG_ASSEMBLIES do assemblies.map[table.remove(assemblies.order,1)]=nil end
    end
    if not a.parts[idx] then a.parts[idx]=true;a.got=a.got+1 end
    if rejected then a.bad=true end
    if a.got~=a.total then return "partial" end
    assemblies.map[key]=nil
    for i,k in ipairs(assemblies.order) do if k==key then table.remove(assemblies.order,i);break end end
    return a.bad and "mixed" or "complete"
end
local function transportCapture(prefix,payload,dist,sender)
    if prefix~=TRANSPORT_PREFIX or type(payload)~="string" or payload=="" then return end
    local evt,rest=payload:match("^(%d+)\t(.*)$")
    -- The game drops what does not have this framing without a trace: it cannot
    -- change its cache, so it is only counted.
    if not evt then bump(T.counts,"drop");return end
    local op=tonumber(evt,10)
    if not TRANSPORT_OPS[op] then bump(T.counts,"other");return end
    -- The client's own empty request, echoed or not, and any empty 1220 body: the
    -- game's handler returns at once, so nothing changed and nothing is a reply.
    if op==1220 and rest=="" then bump(T.counts,"echo");return end
    -- The player's own exact name. A failing or unknown identity (also the client's own word for
    -- an unknown unit) never qualifies and is never a silent miss: the packet is still recorded.
    local okName,name=false,nil
    if type(UnitName)=="function" then okName,name=pcall(UnitName,"player") end
    local why
    if not okName or type(name)~="string" or name=="" or name:lower()=="unknown"
        or (type(UNKNOWNOBJECT)=="string" and name==UNKNOWNOBJECT) then why="identity"
    elseif type(sender)~="string" or sender~=name then why="sender"
    elseif dist~="WHISPER" then why="channel" end
    local rec={op=op,epoch=T.epoch}
    local mid,idxText,totalText=rest:match("^@(%x%x%x%x)\t(%x%x%x)/(%x%x%x)\t")
    if why then
        rec.cls="R";rec.why=why
        -- a rejected fragment still counts toward the game's assembly
        if mid and op~=1220 then segmentNote(op,mid,idxText,totalText,true) end
    elseif op~=1220 then
        rec.cls="A"
        if mid then
            local state=segmentNote(op,mid,idxText,totalText,false)
            if state=="partial" then bump(T.counts,"seg");return end
            if state=="mixed" then rec.cls="R";rec.why="mixed"
            elseif state=="range" then rec.why="range"
            else rec.seg=true end
        end
    elseif mid then rec.cls="A";rec.why="segmented"
    elseif evt~=tostring(op) then
        -- The game reads "01220" as 1220 (tonumber), so it reaches the same handler: it can change
        -- the cache, and it is never a qualifying reply.
        rec.cls="A";rec.why="malformed"
    else
        local parsed,reason,nf=parseCharges(rest)
        rec.nf=nf
        if parsed then rec.cls="Q";rec.charges,rec.delta,rec.pending=parsed.charges,parsed.delta,parsed.pending
        else rec.cls="A";rec.why=reason end
    end
    T.ord=T.ord+1
    rec.ord=T.ord
    bump(T.counts,rec.cls)
    if rec.why then bump(T.rejects,rec.why) end
    -- Any record with a reason (a rejection, or an admitted packet that cannot be trusted to have
    -- replaced the cache) taints the opcode; a later complete, qualifying record clears it.
    if rec.why then T.bad[op]=rec.ord else T.good[op]=rec.ord end
    T.ring[rec.ord]=rec
    T.ring[rec.ord-TRANSPORT_RING]=nil
end
local function transportEvent(event,prefix,payload,dist,sender)
    if event=="CHAT_MSG_ADDON" then transportCapture(prefix,payload,dist,sender)
    elseif event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_ENTERING_WORLD" then T.epoch=(T.epoch+1)%65536 end
end
-- Start the observer. Idempotent; true when it is listening.
function O.TransportStart()
    if T.started then return true end
    if type(CreateFrame)~="function" then return false,"The client cannot create a frame." end
    local ok,frame=pcall(CreateFrame,"Frame")
    if not ok or type(frame)~="table" then return false,"The observer frame could not be created." end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD");frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent",function(_,event,a,b,c,d)
        -- Never an error to the game, and a superseded instance is inert.
        if A.Orbs~=O then return end
        pcall(transportEvent,event,a,b,c,d)
    end)
    T.started=true
    return true
end
local function copyNumbers(t)
    local out={};for k,v in pairs(t) do out[k]=v end;return out
end
-- Numbers, booleans and short names only: no player, no sender, no payload text.
function O.TransportStatus()
    -- retained: how many records the ring holds now (never more than TRANSPORT_RING).
    local retained=0
    for _ in pairs(T.ring) do retained=retained+1 end
    return {started=T.started,epoch=T.epoch,ord=T.ord,counts=copyNumbers(T.counts),rejects=copyNumbers(T.rejects),
        good=copyNumbers(T.good),bad=copyNumbers(T.bad),requests=T.requests,reqOrd=T.reqOrd,retained=retained}
end
-- The relevant records that arrived after ordinal `since`, oldest first, or nil and
-- "overflow" when the bounded ring no longer covers them.
function O.TransportSince(since)
    if not integer(since,0) then return nil,"argument" end
    local first=math.max(1,T.ord-TRANSPORT_RING+1)
    if since<T.ord and since+1<first then return nil,"overflow" end
    local out={}
    for ord=since+1,T.ord do
        local rec=T.ring[ord]
        if not rec then return nil,"overflow" end
        out[#out+1]=copyNumbers(rec)
    end
    return out
end
function O.RequestRefresh()
    local pe=_G.ProjectEbonhold;local orb=pe and pe.OrbService;local svc=pe and pe.PerkService
    local a=type(orb)=="table" and type(orb.RequestCharges)=="function"
    local b=type(svc)=="table" and type(svc.RequestGrantedPerks)=="function"
    if not a or not b then return false,"The client cannot request an Orb/ownership refresh." end
    local okA=pcall(orb.RequestCharges);local okB=pcall(svc.RequestGrantedPerks)
    -- The mark is the arrival ordinal at this moment. It is not a correlation: a
    -- reply that arrives later is "observed after refresh began", nothing more. A request
    -- that was not sent has no mark.
    if not okA then return false end
    T.requests=math.min(T.requests+1,COUNT_CAP);T.reqOrd=T.ord
    return okB,nil,{ord=T.ord,n=T.requests,epoch=T.epoch}
end
