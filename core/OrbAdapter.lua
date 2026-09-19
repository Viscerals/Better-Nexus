-- Nexus: Orb of Lost Memories game boundary.
-- Independent integration of the public calls observed in supplied LoadoutPilot
-- 1.3.6/P103. Capability detection is read-only; no speculative spend/selection.
Nexus = Nexus or {}
local A = assert(Nexus.GameAdapter, "OrbAdapter requires GameAdapter")
local O = {}
A.Orbs = O
local owner, ownerContext
local observations = { serial=0, grantedRef=nil, grantedSig=nil }
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
local function ctx(pe,svc,orb)
    local s=A.AutomationSignature and A.AutomationSignature() or {}
    local owned=A.Owned and A.Owned() or {}
    return {pe=pe,svc=svc,orb=orb,guid=UnitGUID and UnitGUID("player"),
        generation=owned.generation,level=A.Level and A.Level(),
        active=s.activeSlot,slot=pe and pe.Perks and pe.Perks.serverActiveSlot}
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
        return nil,"Waiting for current rolled and permanent Echo data from the server."
    end
    local okG,rawG=call(svc,"GetGrantedPerks");local okL,rawL=call(svc,"GetLockedPerks")
    if not okG or not okL then return nil,"Echo ownership could not be read." end
    local granted,err,totalG=readCounts(rawG,cat);if not granted then return nil,err end
    local locks,errL,totalL=readCounts(rawL,cat);if not locks then return nil,errL end
    if totalG>79 or totalL>6 then return nil,"The current rolled/permanent Echo counts exceed the supported limits." end
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
    local rows={}
    for id,row in pairs(cat.rows) do
        local raw=pe.PerkDatabase and pe.PerkDatabase[id]
        local g=raw and tonumber(raw.groupId)
        local learned=not raw or not raw.requiredSpell or raw.requiredSpell==0
            or (type(IsSpellKnown)=="function" and IsSpellKnown(raw.requiredSpell))
        local mask=tonumber(row.classMask or (raw and raw.classMask)) or 0
        local allowedClass=mask==0 or mask==1535 or (bit and bit.band and bit.band(mask,cat.playerMask or 0)~=0)
        local disabled=false
        if type(svc.IsTomeEchoDisabled)=="function" then
            local okD,d=call(svc,"IsTomeEchoDisabled",id)
            if not okD then return nil,"Cannot verify Echo availability." end
            disabled=d==true
        end
        rows[id]={spellId=id,name=row.name or (GetSpellInfo and GetSpellInfo(id)) or ("Echo "..id),
            quality=row.quality or 0,maxStack=tonumber(row.maxStack) or 1,
            group=integer(g,1) and ("g:"..g) or ("s:"..id),available=allowedClass and learned and not disabled}
    end
    local s={known=true,charges=charges,offerPending=pending,board=board,boardKey=table.concat(parts,","),
        granted=granted,locked=locks,grantStamp=observations.serial,grantedKey=sig,lockedKey=signature(locks),
        hostPending=host,autoAccept=auto,catalog=rows,context=ctx(pe,svc,orb),at=GetTime and GetTime() or 0}
    return s
end
function O.SameContext(a,b) return same(a,b) end
function O.IsOwned() return owner~=nil end
function O.Acquire(s)
    if owner then return nil,"Orb mode already owns an operation." end
    local fresh,err=O.Read();if not fresh then return nil,err end
    if not s or not same(s.context,fresh.context) or s.grantedKey~=fresh.grantedKey
        or s.lockedKey~=fresh.lockedKey or s.charges~=fresh.charges then return nil,"Your Echo state changed. Review the plan again." end
    if fresh.offerPending or #fresh.board>0 or fresh.hostPending or A.InFlight() then return nil,"Resolve the current Echo action first." end
    if fresh.autoAccept then return nil,"Turn off the game's automatic Echo acceptance before starting Orb mode." end
    if A.RivalDetected and A.RivalDetected() then return nil,"Disable the other Echo automation addon before using Orb mode." end
    owner={};ownerContext=fresh.context;return owner,fresh
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
function O.Spend(token,key,expected)
    local s,err=validate(token);if not s then return nil,"REJECTED",err end
    if s.offerPending or #s.board>0 or s.hostPending or A.InFlight() or s.charges<1 then
        return nil,"REJECTED","Another choice is pending or no Orbs remain."
    end
    if not expected or s.grantedKey~=expected.grantedKey or s.lockedKey~=expected.lockedKey
        or s.charges~=expected.charges or not (s.granted[key] and s.granted[key]>0) then
        return nil,"REJECTED","The approved source or balance changed before spending."
    end
    local id=tonumber(tostring(key):match("^(%d+):%d+$"));if not id then return nil,"REJECTED","Invalid source." end
    local ok,value=pcall(ownerContext.orb.ConfirmSpend,id,1)
    if not ok then return nil,"AMBIGUOUS","The spend call failed; its server outcome is unknown. No repeat will be sent." end
    if value==false then return nil,"REJECTED","The game refused the Orb spend." end
    return true,"SUBMITTED"
end
function O.Select(token,index,expectedBoard,id)
    local s,err=validate(token);if not s then return nil,"REJECTED",err end
    local c=s.board[index]
    if not s.offerPending or s.hostPending or not c or not c.selectable or c.spellId~=id
        or not s.catalog[id] or not s.catalog[id].available
        or s.boardKey~=expectedBoard then return nil,"REJECTED","The Orb offer changed or another action is pending." end
    local ok,v=pcall(ownerContext.svc.SelectPerk,id)
    if not ok or (v~=true and v~=false) then return nil,"AMBIGUOUS","The selection outcome is unknown. No selection will be repeated." end
    if v==false then return nil,"REJECTED","The game refused the Orb choice. Resolve the offer manually." end
    return true,"SUBMITTED",s.grantStamp
end
function O.RequestRefresh()
    local pe=_G.ProjectEbonhold;local orb=pe and pe.OrbService;local svc=pe and pe.PerkService
    local a=type(orb)=="table" and type(orb.RequestCharges)=="function"
    local b=type(svc)=="table" and type(svc.RequestGrantedPerks)=="function"
    if not a or not b then return false,"The client cannot request an Orb/ownership refresh." end
    local okA=pcall(orb.RequestCharges);local okB=pcall(svc.RequestGrantedPerks)
    return okA and okB
end
