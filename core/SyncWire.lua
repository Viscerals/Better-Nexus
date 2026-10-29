-- Nexus prototype: CTL-backed wire selection. Semantic authority remains in Sync.
-- Discovery/broadcast stays legacy-compatible. Directed packets use addon
-- whispers only after an explicit prefix handshake. A payload is sent once.
Nexus = Nexus or {}
local Wire={PREFIX="NEXUS_P1"}
Nexus.SyncWire=Wire
local peers,peerCount={},0
local pending,pendingCount={},0
local MAX_PEERS,MAX_HANDSHAKES=128,16
-- Thirty seconds covers the bounded 16-slot handshake queue at one slot/s.
-- A reply gets its own 30-second window only after immediate API submission.
local PEER_TTL,HANDSHAKE_COOLDOWN=900,60
local HANDSHAKE_TTL,OFFLINE_COOLDOWN,NOTICE_WINDOW=30,60,4
local generation,context,lastSweep,connected,handshakeAllowed=0,{},nil,nil,nil
local lastHandshake=-math.huge
local metrics={addonSent=0,legacySent=0,handshakeSent=0,rejected=0,bandwidthWait=0,combatWait=0,modeRefused=0}
local receiver,frame
local RemovePeer
local function Now() return type(GetTime)=="function" and GetTime() or 0 end
local function Combat()
    return (type(InCombatLockdown)=="function" and InCombatLockdown())
        or (type(UnitAffectingCombat)=="function" and UnitAffectingCombat("player"))
end
local function Name(value)
    if type(value)~="string" or value=="" or #value>96 or value:find("[%s%c|]") then return nil end
    return value
end
local function Local(name)
    local me,realm
    if type(UnitName)=="function" then me,realm=UnitName("player") end
    me=me or ""
    if not realm or realm=="" then
        realm=type(GetNormalizedRealmName)=="function" and GetNormalizedRealmName()
            or (type(GetRealmName)=="function" and GetRealmName()) or ""
    end
    realm=tostring(realm):gsub("%s+","")
    return name==me or (realm~="" and name==me.."-"..realm)
end
local function Peer(name)
    name=Name(name);if not name or Local(name) then return nil end
    local row=peers[name]
    if not row then
        if peerCount>=MAX_PEERS then
            local oldest,stamp
            -- Active cooldowns retain their bounded row until their deadline.
            -- If every slot is cooling down, refuse new discovery rather than
            -- evicting the guard and reopening an offline target.
            oldest,stamp=nil,nil
            for key,p in pairs(peers) do
                if not p.offlineUntil or Now()>=p.offlineUntil then
                    if not stamp or p.seen<stamp then oldest,stamp=key,p.seen end
                end
            end
            if not oldest then return nil end
            RemovePeer(oldest,"peer evicted")
        end
        row={seen=Now(),asked=-math.huge,addon=false};peers[name]=row;peerCount=peerCount+1
    end
    row.seen=Now();return row,name
end
local function Ctl()
    local ctl=_G.ChatThrottleLib or Nexus.ChatThrottleLib
    if type(ctl)~="table" or type(ctl.SendAddonMessage)~="function"
        or type(ctl.SendChatMessage)~="function" or type(ctl.UpdateAvail)~="function"
        or type(ctl.Prio)~="table" or type(ctl.MSG_OVERHEAD)~="number" then return nil end
    return ctl
end
local function HasAddonApi()
    return type(_G.SendAddonMessage)=="function"
        or (_G.C_ChatInfo and type(_G.C_ChatInfo.SendAddonMessage)=="function")
end
local function Room(bytes)
    if Combat() then metrics.combatWait=metrics.combatWait+1;return false,"combat" end
    local ctl=Ctl()
    if not ctl then return false,"CTL unavailable" end
    -- Keep packets in the bounded Nexus queue, not in a second uncancellable
    -- CTL queue. This also prevents queued Nexus bytes dispatching in combat.
    if ctl.bQueueing then metrics.bandwidthWait=metrics.bandwidthWait+1;return false,"CTL busy" end
    local ok,avail=pcall(ctl.UpdateAvail,ctl)
    if not ok or type(avail)~="number" or avail<=bytes+ctl.MSG_OVERHEAD then
        metrics.bandwidthWait=metrics.bandwidthWait+1;return false,"CTL bandwidth"
    end
    return true,ctl
end
-- The saved Sync mode (core/SyncModePolicy.lua) is the same decision the
-- queue admission uses. A mode refusal is not a combat, bandwidth or
-- transport condition and never suspends the wire.
local function ModeAllows(kind,metadata)
    local policy=Nexus.SyncModePolicy
    if not policy or type(policy.Allows)~="function" then return true end
    return policy.Allows(kind,metadata)
end
-- The whole-addon session pause (issue #171): no packet, handshake or inbound
-- admission while it holds. It is not Wire.suspended (an ambiguous-CTL fault).
local function SessionPaused() return Nexus.SessionPause and Nexus.SessionPause.IsPaused()==true end
local function DropPending(name)
    if pending[name] then pending[name]=nil;pendingCount=pendingCount-1 end
end
local function DropHandshakes()
    if pendingCount>0 then pending,pendingCount={},0 end
end
local function CancelOwners(name,reason)
    if type(context.onPeerRemoved)=="function" then context.onPeerRemoved(name,reason) end
end
RemovePeer=function(name,reason)
    DropPending(name)
    if peers[name] then peers[name]=nil;peerCount=peerCount-1 end
    CancelOwners(name,reason)
end
local function ResetScope(reason)
    generation=generation+1;DropHandshakes()
    for name,p in pairs(peers) do
        p.addon,p.confirmedAt,p.helloUntil,p.lastWhisperAt=false,nil,nil,nil
        p.asked,p.ackAt=-math.huge,nil
        CancelOwners(name,reason)
    end
end
local function CheckConnection()
    local actual=type(context.connected)~="function" or context.connected()==true
    local changed=connected~=nil and connected~=actual
    connected=actual
    if changed then ResetScope("connection changed") end
    return actual
end
local function ImmediateCallback(onSuccess)
    local receipt={open=true,complete=false,successful=false}
    local function Done(_,sent)
        -- Only callbacks completed inside the immediate CTL call can witness
        -- a submission. Deferred unsupported callbacks cannot renew authority.
        if not receipt.open then return end
        if receipt.complete then
            Wire.suspended=true;Wire.lastError="CTL duplicated immediate callback"
        end
        receipt.complete=true
        -- Preserve the first actual successful witness across a contradictory
        -- false callback. A false->true duplicate also consumes dispatched bytes.
        if sent~=false and not receipt.successful then
            receipt.successful=true;onSuccess()
        end
    end
    return receipt,Done
end
function Wire.Housekeep(force)
    local current=Now()
    -- Called behind readiness gates every frame. Check scope and bounded maps
    -- once per second; admission/dispatch also check their exact deadlines.
    if not force and lastSweep and current>=lastSweep and current-lastSweep<1 then return end
    lastSweep=current
    metrics.housekeepingSweeps=(metrics.housekeepingSweeps or 0)+1
    local isConnected=CheckConnection()
    local allowed=ModeAllows("handshake")==true
    if handshakeAllowed~=nil and handshakeAllowed~=allowed then
        -- Saved mode changes invalidate negotiation, but keep other queue policy
        -- and manual ownership decisions in their existing owners.
        generation=generation+1;DropHandshakes()
        for _,p in pairs(peers) do p.addon,p.helloUntil,p.lastWhisperAt=false,nil,nil end
    end
    handshakeAllowed=allowed
    for name,item in pairs(pending) do
        if current>=item.expiresAt or item.generation~=generation or not isConnected
            or not allowed then DropPending(name) end
    end
    for name,p in pairs(peers) do
        if p.helloUntil and current>=p.helloUntil then p.helloUntil=nil end
        if current-p.seen>=PEER_TTL and (not p.offlineUntil or current>=p.offlineUntil) then
            RemovePeer(name,"peer expired")
        end
    end
end
function Wire.IsPeerBlocked(name)
    local p=type(name)=="string" and peers[name]
    return (Name(name) and connected==false) or (p and (p.needsObservation==true or (p.offlineUntil and Now()<p.offlineUntil))) or false
end
function Wire.IsWhisperTargetBlocked(name)
    -- The explicit slash parser folds case. Match the full existing identity,
    -- preserving bare/qualified and realm distinctions; attribution and data
    -- routing continue to use their exact opaque transport names. Missing Sync
    -- channel membership does not block an ordinary diagnostic chat whisper.
    local identity=Nexus.Identity
    local key=identity and identity.PlayerKey(name,true)
    for peer,p in pairs(peers) do
        if (peer==name or (key and identity.PlayerKey(peer,true)==key))
            and (p.needsObservation==true or (p.offlineUntil and Now()<p.offlineUntil)) then return true end
    end
    return false
end
local function NoticeName(text)
    local format=_G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(text)~="string" or #text>512 or type(format)~="string" or #format>512 then return end
    local start,finish=format:find("%s",1,true)
    if not start or format:find("%s",finish+1,true) then return end
    -- Literal template fragments, anchored to the entire localized message.
    local function Escape(value) return (value:gsub("(%W)","%%%1")) end
    return Name(text:match("^"..Escape(format:sub(1,start-1)).."(.-)"
        ..Escape(format:sub(finish+1)).."$"))
end
function Wire.NoteOfflineNotice(text)
    Wire.Housekeep()
    local name=NoticeName(text)
    if not name or not CheckConnection() then return false end
    local p=peers[name]
    local current=Now()
    if not p or not p.lastWhisperAt or p.whisperGeneration~=generation
        or current<p.lastWhisperAt or current-p.lastWhisperAt>NOTICE_WINDOW then return false end
    p.addon,p.confirmedAt,p.helloUntil,p.lastWhisperAt=false,nil,nil,nil
    p.offlineUntil,p.needsObservation=current+OFFLINE_COOLDOWN,true
    DropPending(name);CancelOwners(name,"peer offline")
    metrics.offlineCancelled=(metrics.offlineCancelled or 0)+1
    return true
end
local function QueueHandshake(name,kind)
    -- Never accumulate a handshake the saved mode would refuse to send.
    if not ModeAllows("handshake") then
        if handshakeAllowed~=false then Wire.Housekeep(true) end
        DropHandshakes();return
    end
    if pending[name] then
        if kind=="ACK1" then pending[name].kind=kind end
        return
    end
    if pendingCount>=MAX_HANDSHAKES then return end
    pending[name]={kind=kind,expiresAt=Now()+HANDSHAKE_TTL,generation=generation}
    pendingCount=pendingCount+1
end
function Wire.ObservePeer(name)
    Wire.Housekeep()
    if not Name(name) or not CheckConnection() then return end
    local p,key=Peer(name)
    if p and p.offlineUntil and Now()<p.offlineUntil then return end
    if p and p.needsObservation then
        p.needsObservation,p.offlineUntil,p.asked=false,nil,-math.huge
    end
    if p and HasAddonApi() and Now()-p.asked>=HANDSHAKE_COOLDOWN
        and (not p.addon or Now()-(p.confirmedAt or 0)>PEER_TTL) then
        p.asked=Now();QueueHandshake(key,"HELLO1")
    end
end
local function Route(payload,metadata)
    local target=type(metadata)=="table" and Name(metadata.requester)
    local p=target and peers[target]
    local escaped=payload:gsub("|","||")
    -- A contextual DPS response to a short requester needs the native
    -- channel's owner provenance. Pin every chunk to that existing route:
    -- the addon size limit can otherwise move only its final short chunk.
    -- This selects transport only; it grants no receive/record authority.
    local transfer,requester,requestId,bucket=payload:match(
        "^WLD2|[^|]+|([^|]+)|[^|]+|[^|]+|([^|]+)|([^|]+)|([^|]+)$")
    local nativeDpsResponse = type(metadata)=="table"
        and metadata.dataKind=="D" and target and not target:find("-",1,true)
        and Nexus.Identity and Nexus.Identity.ValidPlayer(target)
        and type(metadata.requestId)=="string" and #metadata.requestId<=96
        and metadata.requestId:match("^c1%-[%w%._:@%+%-]+$")
        and type(metadata.bucket)=="number" and metadata.bucket>=1 and metadata.bucket<=8
        and metadata.bucket==math.floor(metadata.bucket)
        and type(metadata.transferId)=="string"
        and #metadata.transferId<=160 and not metadata.transferId:find("[%s%c|]")
        and Nexus.Identity.ValidWireText(metadata.transferId,160,false)
        and transfer==metadata.transferId and requester==target
        and requestId==metadata.requestId and bucket==tostring(metadata.bucket)
    -- The addon route needs this side's handshake reply. When the saved Sync
    -- mode refuses handshakes, the peer never confirms this side and would
    -- reject the whisper, so directed traffic keeps the legacy route.
    if not nativeDpsResponse and p and p.addon and Now()-(p.confirmedAt or 0)<=PEER_TTL and HasAddonApi()
        and ModeAllows("handshake")
        and #Wire.PREFIX+1+3+#escaped<=254 then
        return "addon",target,"P7:"..escaped
    end
    return "legacy",nil,escaped
end
-- The persistent reasons this wire cannot transmit now, or nil. Read-only:
-- unlike CanDispatch it counts nothing, so a scheduler may ask every frame.
-- Momentary CTL queueing or bandwidth waits are not reported; they clear
-- within ordinary send pacing.
function Wire.Blocked()
    if Wire.suspended then return "transport suspended" end
    local policy=Nexus.SyncModePolicy
    if policy and type(policy.Mode)=="function" and policy.Mode()=="off" then
        return policy.Text("off")
    end
    if Combat() then return "combat" end
    if not Ctl() then return "CTL unavailable" end
    return nil
end
function Wire.CanDispatch(payload,metadata)
    if SessionPaused() then return false,"session paused" end
    if type(metadata)=="table" and Wire.IsPeerBlocked(metadata.requester) then return false,"peer offline" end
    if Wire.suspended then return false,"transport suspended" end
    if type(payload)~="string" then return false,"invalid payload" end
    local allowed,why=ModeAllows("packet",metadata)
    if not allowed then return false,why end
    local route,_,text=Route(payload,metadata)
    return Room(#text+(route=="addon" and #Wire.PREFIX+1 or 0))
end
function Wire.SendPacket(payload,metadata,channel)
    if SessionPaused() then return false,"session paused" end
    if type(metadata)=="table" and Wire.IsPeerBlocked(metadata.requester) then return false,"peer offline" end
    if Wire.suspended then return false,"transport suspended" end
    if type(payload)~="string" then return false,"invalid payload" end
    -- Checked again at the actual submission, not only at admission.
    local allowed,why=ModeAllows("packet",metadata)
    if not allowed then metrics.modeRefused=metrics.modeRefused+1;return false,why end
    local route,target,text=Route(payload,metadata)
    local ready,ctl=Room(#text+(route=="addon" and #Wire.PREFIX+1 or 0))
    if not ready then return false,ctl end
    -- A cached passive sweep cannot authorize an actual submission. This read
    -- never joins/sends; a scope transition may cancel the selected packet,
    -- whose identity the Transport checks again after this call returns.
    if not CheckConnection() then return false,"channel unavailable" end
    if type(metadata)=="table" and Wire.IsPeerBlocked(metadata.requester) then return false,"peer offline" end
    local submittedGeneration=generation
    local receipt,Done=ImmediateCallback(function()
        if route=="addon" and CheckConnection() and generation==submittedGeneration then
            local p=peers[target]
            if p and not Wire.IsPeerBlocked(target) then p.lastWhisperAt,p.whisperGeneration=Now(),generation end
        end
    end)
    local priority=type(metadata)=="table" and metadata.queueClass=="control" and "NORMAL" or "BULK"
    local ok,err
    if route=="addon" then
        ok,err=pcall(ctl.SendAddonMessage,ctl,priority,Wire.PREFIX,text,"WHISPER",target,"Nexus.Data",Done,nil)
    else
        if not channel then return false,"channel unavailable" end
        ok,err=pcall(ctl.SendChatMessage,ctl,priority,"Nexus",text,"CHANNEL",nil,channel,"Nexus.Legacy",Done,nil)
    end
    receipt.open=false
    if not ok then
        if receipt.successful then
            -- The immediate callback already witnessed API dispatch. A later
            -- CTL exception must not turn those bytes into a retry.
            Wire.suspended=true;Wire.lastError="CTL failed after immediate dispatch"
            return true,"submitted to CTL; callback completed before error"
        end
        return false,"CTL send failed"
    end
    if not receipt.complete then
        -- Do not retry an ambiguously queued packet. An incompatible CTL is
        -- isolated until reload; return API-submitted only, never peer success.
        Wire.suspended=true;Wire.lastError="CTL violated immediate-dispatch contract; transport paused"
        return true,"submitted to CTL; dispatch unresolved"
    end
    if not receipt.successful then return false,"wire API refused" end
    local key=route=="addon" and "addonSent" or "legacySent"
    metrics[key]=metrics[key]+1
    return true,route
end
function Wire.PumpHandshake()
    Wire.Housekeep()
    -- Held, not dropped: each pending handshake keeps its own expiry.
    if SessionPaused() then return end
    if Wire.suspended or connected==false then return end
    if not ModeAllows("handshake") then
        if handshakeAllowed~=false then Wire.Housekeep(true) end
        DropHandshakes();return
    end
    if Combat() or Now()-lastHandshake<1 then return end
    local name,item=next(pending);if not name then return end
    local p=peers[name]
    if not p or Now()>=item.expiresAt or item.generation~=generation or Wire.IsPeerBlocked(name) then
        DropPending(name);return
    end
    local kind=item.kind
    local ready,ctl=Room(#Wire.PREFIX+1+#kind)
    if not ready or not HasAddonApi() then return end
    if not CheckConnection() then return end
    if Wire.IsPeerBlocked(name) or peers[name]~=p or item.generation~=generation then DropPending(name);return end
    lastHandshake=Now()
    local receipt,Done=ImmediateCallback(function()
        if CheckConnection() and peers[name]==p and item.generation==generation and not Wire.IsPeerBlocked(name) then
            p.lastWhisperAt,p.whisperGeneration=Now(),generation
        end
    end)
    local ok=pcall(ctl.SendAddonMessage,ctl,"NORMAL",Wire.PREFIX,kind,"WHISPER",name,"Nexus.Handshake",Done,nil)
    receipt.open=false
    if ok and not receipt.complete then Wire.suspended=true;Wire.lastError="CTL handshake unexpectedly queued" end
    if not ok and receipt.successful then Wire.suspended=true;Wire.lastError="CTL failed after immediate handshake" end
    DropPending(name)
    if receipt.successful and CheckConnection() and peers[name]==p and item.generation==generation
        and not Wire.IsPeerBlocked(name) then
        if kind=="HELLO1" then p.helloUntil,p.helloGeneration=Now()+HANDSHAKE_TTL,generation
        else p.addon,p.confirmedAt=true,Now() end
        metrics.handshakeSent=metrics.handshakeSent+1
    end
end
function Wire.Receive(prefix,text,distribution,sender)
    if prefix~=Wire.PREFIX or distribution~="WHISPER" or type(text)~="string"
        or #text>254-#Wire.PREFIX-1 or not Name(sender) or Local(sender) then return false end
    if SessionPaused() then return false end
    Wire.Housekeep()
    if not CheckConnection() then return false end
    if Wire.IsPeerBlocked(sender) then return false end
    if (text=="ACK1" or text=="HELLO1") and not ModeAllows("handshake") then
        if handshakeAllowed~=false then Wire.Housekeep(true) end
        DropHandshakes();return false
    end
    -- ACK1 has no nonce. It is accepted only in the current immediately sent
    -- HELLO window. A delayed reply inside a later same-peer window cannot be
    -- distinguished by this legacy protocol and is not authentication.
    if text=="ACK1" then
        local p=peers[sender]
        if not p or not p.helloUntil or Now()>=p.helloUntil or p.helloGeneration~=generation then return false end
        p.addon,p.confirmedAt,p.helloUntil,p.seen=true,Now(),nil,Now()
        return true
    end
    if text=="HELLO1" then
        local p,name=Peer(sender);if not p then return false end
        if Now()-(p.ackAt or -math.huge)>=HANDSHAKE_COOLDOWN then
            p.ackAt=Now();QueueHandshake(name,"ACK1")
        end
        return true
    end
    local p=peers[sender]
    if text:sub(1,3)~="P7:" or not p or not p.addon or Now()-(p.confirmedAt or 0)>PEER_TTL then
        metrics.rejected=metrics.rejected+1;return false
    end
    if type(receiver)~="function" then return false end
    -- Inbound validates sender, schema, ownership, correlation and content.
    return receiver(text:sub(4),sender)
end
function Wire.Stats()
    local out={policy="CTL immediate slots; addon whisper for negotiated directed traffic; legacy discovery",
        prefix=Wire.PREFIX,peers=peerCount,pendingHandshakes=pendingCount,available=Ctl()~=nil,
        suspended=Wire.suspended==true,lastError=Wire.lastError}
    for k,v in pairs(metrics) do out[k]=v end
    return out
end
function Wire.Init(fn,options)
    ResetScope("wire reset")
    receiver=fn;context=type(options)=="table" and options or {}
    generation=generation+1
    lastSweep,connected,handshakeAllowed=nil,nil,nil
    lastHandshake=-math.huge
    peers,peerCount,pending,pendingCount={},0,{},0
    Wire.suspended,Wire.lastError=false,nil
    if not frame then
        frame=CreateFrame("Frame")
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:SetScript("OnEvent",function(_,event,...)
            if event=="CHAT_MSG_ADDON" then
                local ok,err=pcall(Wire.Receive,...)
                if not ok then metrics.rejected=metrics.rejected+1;Wire.lastError="addon message rejected" end
            end
        end)
    end
    local register=_G.RegisterAddonMessagePrefix or (_G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix)
    if type(register)=="function" then pcall(register,Wire.PREFIX) end
end
