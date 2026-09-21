-- Nexus prototype: CTL-backed wire selection. Semantic authority remains in Sync.
-- Discovery/broadcast stays legacy-compatible. Directed packets use addon
-- whispers only after an explicit prefix handshake. A payload is sent once.
Nexus = Nexus or {}
local Wire={PREFIX="NEXUS_P1"}
Nexus.SyncWire=Wire
local peers,peerCount={},0
local pending,pendingCount={},0
local MAX_PEERS,MAX_HANDSHAKES=128,16
local PEER_TTL,HANDSHAKE_COOLDOWN=900,60
local lastHandshake=-math.huge
local metrics={addonSent=0,legacySent=0,handshakeSent=0,rejected=0,bandwidthWait=0,combatWait=0}
local receiver,frame
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
            for key,p in pairs(peers) do
                if not stamp or p.seen<stamp then oldest,stamp=key,p.seen end
            end
            if oldest then peers[oldest]=nil;peerCount=peerCount-1 end
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
local function QueueHandshake(name,kind)
    if pending[name] then
        if kind=="ACK1" then pending[name]=kind end
        return
    end
    if pendingCount>=MAX_HANDSHAKES then return end
    pending[name]=kind;pendingCount=pendingCount+1
end
function Wire.ObservePeer(name)
    local p,key=Peer(name)
    if p and HasAddonApi() and Now()-p.asked>=HANDSHAKE_COOLDOWN
        and (not p.addon or Now()-(p.confirmedAt or 0)>PEER_TTL) then
        p.asked=Now();QueueHandshake(key,"HELLO1")
    end
end
local function Route(payload,metadata)
    local target=type(metadata)=="table" and Name(metadata.requester)
    local p=target and peers[target]
    local escaped=payload:gsub("|","||")
    if p and p.addon and Now()-(p.confirmedAt or 0)<=PEER_TTL and HasAddonApi()
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
    if Combat() then return "combat" end
    if not Ctl() then return "CTL unavailable" end
    return nil
end
function Wire.CanDispatch(payload,metadata)
    if Wire.suspended then return false,"transport suspended" end
    if type(payload)~="string" then return false,"invalid payload" end
    local route,_,text=Route(payload,metadata)
    return Room(#text+(route=="addon" and #Wire.PREFIX+1 or 0))
end
function Wire.SendPacket(payload,metadata,channel)
    if Wire.suspended then return false,"transport suspended" end
    if type(payload)~="string" then return false,"invalid payload" end
    local route,target,text=Route(payload,metadata)
    local ready,ctl=Room(#text+(route=="addon" and #Wire.PREFIX+1 or 0))
    if not ready then return false,ctl end
    local complete,successful=false,false
    local function Done(_,sent) complete=true;successful=sent~=false end
    local priority=type(metadata)=="table" and metadata.queueClass=="control" and "NORMAL" or "BULK"
    local ok,err
    if route=="addon" then
        ok,err=pcall(ctl.SendAddonMessage,ctl,priority,Wire.PREFIX,text,"WHISPER",target,"Nexus.Data",Done,nil)
    else
        if not channel then return false,"channel unavailable" end
        ok,err=pcall(ctl.SendChatMessage,ctl,priority,"Nexus",text,"CHANNEL",nil,channel,"Nexus.Legacy",Done,nil)
    end
    if not ok then return false,"CTL send failed" end
    if not complete then
        -- Do not retry an ambiguously queued packet. An incompatible CTL is
        -- isolated until reload; return API-submitted only, never peer success.
        Wire.suspended=true;Wire.lastError="CTL violated immediate-dispatch contract; transport paused"
        return true,"submitted to CTL; dispatch unresolved"
    end
    if not successful then return false,"wire API refused" end
    local key=route=="addon" and "addonSent" or "legacySent"
    metrics[key]=metrics[key]+1
    return true,route
end
function Wire.PumpHandshake()
    if Wire.suspended or Combat() or Now()-lastHandshake<1 then return end
    local name,kind=next(pending);if not name then return end
    local ready,ctl=Room(#Wire.PREFIX+1+#kind)
    if not ready or not HasAddonApi() then return end
    lastHandshake=Now()
    local complete=false
    local ok=pcall(ctl.SendAddonMessage,ctl,"NORMAL",Wire.PREFIX,kind,"WHISPER",name,"Nexus.Handshake",function() complete=true end,nil)
    if ok and not complete then Wire.suspended=true;Wire.lastError="CTL handshake unexpectedly queued" end
    pending[name]=nil;pendingCount=pendingCount-1
    if ok then metrics.handshakeSent=metrics.handshakeSent+1 end
end
function Wire.Receive(prefix,text,distribution,sender)
    if prefix~=Wire.PREFIX or distribution~="WHISPER" or type(text)~="string"
        or #text>254-#Wire.PREFIX-1 or not Name(sender) or Local(sender) then return false end
    local p,name=Peer(sender);if not p then return false end
    if text=="HELLO1" or text=="ACK1" then
        p.addon,p.confirmedAt=true,Now()
        if text=="HELLO1" and Now()-(p.ackAt or -math.huge)>=HANDSHAKE_COOLDOWN then
            p.ackAt=Now();QueueHandshake(name,"ACK1")
        end
        return true
    end
    if text:sub(1,3)~="P7:" or not p.addon or Now()-(p.confirmedAt or 0)>PEER_TTL then
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
function Wire.Init(fn)
    receiver=fn
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
