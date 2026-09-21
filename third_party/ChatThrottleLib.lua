-- ChatThrottleLib compatibility embedding for Nexus experimental prototype.
-- Based on Mikk's public-domain ChatThrottleLib v21 byte-scheduling design.
-- Provenance: WoWUIDev/Ace3, commit 5f34ac009746e4cc16cc867ea743efa01997c0a7,
-- AceComm-3.0/ChatThrottleLib.lua (2009-08-07).
-- This is a documented compact compatibility adaptation, NOT a byte-identical
-- upstream release. It preserves priority rings, bandwidth and callback API.
-- It reuses an existing compatible global CTL. Otherwise its derivative stays
-- private to Nexus and does not impersonate/replace the global library. No modern C_ChatInfo or
-- Enum dependency is introduced on the WoW 3.3.5/Lua 5.1 path.
-- LICENSE: Public Domain. See THIRD_PARTY.md in the source distribution.
Nexus = Nexus or {}
local previous = _G.ChatThrottleLib
if previous ~= nil then
    if type(previous) == "table" and type(previous.SendAddonMessage)=="function"
        and type(previous.SendChatMessage)=="function" and type(previous.UpdateAvail)=="function"
        and type(previous.Prio)=="table" and type(previous.MAX_CPS)=="number"
        and type(previous.MSG_OVERHEAD)=="number" then
        Nexus.ChatThrottleLib = previous
    else
        Nexus.ChatThrottleLibUnavailable = "An incompatible global ChatThrottleLib is already loaded"
    end
    return
end
if type(CreateFrame)~="function" or type(GetTime)~="function" then return end
local CTL={version=21,NexusCompatRevision=1,MAX_CPS=800,MSG_OVERHEAD=40,BURST=4000,MIN_FPS=20,
    avail=0,nTotalSent=0,nBypass=0,Prio={}}
Nexus.ChatThrottleLib=CTL
local bypass=false
local ringMethods={}
local function Ring() return setmetatable({}, {__index=ringMethods}) end
local function Add(ring,p)
    if ring.pos then p.prev=ring.pos.prev;p.prev.next=p;p.next=ring.pos;ring.pos.prev=p
    else p.next=p;p.prev=p;ring.pos=p end
end
local function Remove(ring,p)
    p.next.prev=p.prev;p.prev.next=p.next
    if ring.pos==p then ring.pos=p.next;if ring.pos==p then ring.pos=nil end end
    p.prev,p.next=nil,nil
end
ringMethods.Add=Add
ringMethods.Remove=Remove
for _,name in ipairs({"ALERT","NORMAL","BULK"}) do
    CTL.Prio[name]={ByName={},Ring=Ring(),avail=0,nTotalSent=0}
end
CTL.Frame=CreateFrame("Frame")
CTL.Frame:Hide()
CTL.LastAvailUpdate=GetTime()
CTL.HardThrottlingBeginTime=GetTime()
CTL.OnUpdateDelay=0
function CTL:UpdateAvail()
    local now=GetTime()
    local elapsed=math.max(0,now-self.LastAvailUpdate)
    local gain=self.MAX_CPS*elapsed
    local fps=type(GetFramerate)=="function" and GetFramerate() or 60
    if now-self.HardThrottlingBeginTime<5 then
        self.avail=math.min(self.avail+gain*.1,self.MAX_CPS*.5);self.bChoking=true
    elseif fps<self.MIN_FPS then
        self.avail=math.min(self.MAX_CPS,self.avail+gain*.5);self.bChoking=true
    else self.avail=math.min(self.BURST,self.avail+gain);self.bChoking=false end
    self.avail=math.max(self.avail,-self.MAX_CPS*2)
    self.LastAvailUpdate=now
    return self.avail
end
local function Call(msg)
    bypass=true
    local ok,result=pcall(msg.f,unpack(msg,1,msg.n))
    bypass=false
    if not ok then
        if type(geterrorhandler)=="function" then pcall(geterrorhandler(),result) end
        return false
    end
    return result~=false
end
function CTL:Enqueue(priority,queueName,msg)
    local p=self.Prio[priority]
    local pipe=p.ByName[queueName]
    if not pipe then pipe={name=queueName};p.ByName[queueName]=pipe;Add(p.Ring,pipe) end
    pipe[#pipe+1]=msg;self.bQueueing=true;self.Frame:Show()
end
function CTL:Despool(p)
    while p.Ring.pos and p.avail>p.Ring.pos[1].nSize do
        local pipe=p.Ring.pos
        local msg=table.remove(pipe,1)
        if #pipe==0 then Remove(p.Ring,pipe);p.ByName[pipe.name]=nil
        else p.Ring.pos=pipe.next end
        p.avail=p.avail-msg.nSize
        local sent=Call(msg)
        if sent then p.nTotalSent=p.nTotalSent+msg.nSize;self.nTotalSent=self.nTotalSent+msg.nSize end
        if msg.callbackFn then pcall(msg.callbackFn,msg.callbackArg,sent) end
    end
end
function CTL:Submit(priority,prefix,text,kind,destination,queueName,callback,arg,fn,args,n,size)
    if not self.Prio[priority] or type(prefix)~="string" or type(text)~="string"
        or type(fn)~="function" then error("ChatThrottleLib: invalid send arguments",3) end
    if callback~=nil and type(callback)~="function" then error("ChatThrottleLib: invalid callback",3) end
    if size>255 then error("ChatThrottleLib: message exceeds 255 bytes",3) end
    size=size+self.MSG_OVERHEAD
    local msg={f=fn,n=n,nSize=size,callbackFn=callback,callbackArg=arg}
    for i=1,n do msg[i]=args[i] end
    if not self.bQueueing and size<self:UpdateAvail() then
        self.avail=self.avail-size
        local sent=Call(msg)
        if sent then self.Prio[priority].nTotalSent=self.Prio[priority].nTotalSent+size;self.nTotalSent=self.nTotalSent+size end
        if callback then callback(arg,sent) end
        return sent
    end
    self:Enqueue(priority,queueName or (prefix..kind..tostring(destination or "")),msg)
    return nil
end
function CTL:SendChatMessage(priority,prefix,text,kind,language,destination,queueName,callback,arg)
    return self:Submit(priority,prefix,text,kind or "SAY",destination,queueName,callback,arg,
        _G.SendChatMessage,{text,kind or "SAY",language,destination},4,#text)
end
function CTL:SendAddonMessage(priority,prefix,text,kind,destination,queueName,callback,arg)
    local fn=_G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage or _G.SendAddonMessage
    return self:Submit(priority,prefix,text,kind or "PARTY",destination,queueName,callback,arg,
        fn,{prefix,text,kind or "PARTY",destination},4,#prefix+#text+1)
end
function CTL.OnUpdate(_,elapsed)
    CTL.OnUpdateDelay=CTL.OnUpdateDelay+(elapsed or 0)
    if CTL.OnUpdateDelay<.08 then return end;CTL.OnUpdateDelay=0
    if CTL:UpdateAvail()<0 then return end
    local active=0
    for _,p in pairs(CTL.Prio) do if p.Ring.pos or p.avail<0 then active=active+1 end end
    if active==0 then
        for _,p in pairs(CTL.Prio) do CTL.avail=CTL.avail+p.avail;p.avail=0 end
        CTL.bQueueing=false;CTL.Frame:Hide();return
    end
    local share=CTL.avail/active;CTL.avail=0
    for _,p in pairs(CTL.Prio) do
        if p.Ring.pos or p.avail<0 then p.avail=p.avail+share;CTL:Despool(p) end
    end
end
CTL.Frame:SetScript("OnUpdate",CTL.OnUpdate)
CTL.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
CTL.Frame:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_ENTERING_WORLD" then CTL.HardThrottlingBeginTime=GetTime();CTL.avail=0 end
end)
local function Notice(prefix,text,destination)
    if bypass then return end
    local size=#tostring(prefix or "")+#tostring(text or "")+#tostring(destination or "")+CTL.MSG_OVERHEAD
    CTL.avail=CTL.avail-size;CTL.nBypass=CTL.nBypass+size
end
if type(hooksecurefunc)=="function" then
    if type(_G.SendChatMessage)=="function" then
        hooksecurefunc("SendChatMessage",function(text,kind,lang,dest) Notice("",text,dest) end)
    end
    if type(_G.SendAddonMessage)=="function" then
        hooksecurefunc("SendAddonMessage",function(prefix,text,kind,dest) Notice(prefix,text,dest) end)
    elseif _G.C_ChatInfo and type(_G.C_ChatInfo.SendAddonMessage)=="function" then
        hooksecurefunc(_G.C_ChatInfo,"SendAddonMessage",function(prefix,text,kind,dest) Notice(prefix,text,dest) end)
    end
    CTL.securelyHooked=true
end
