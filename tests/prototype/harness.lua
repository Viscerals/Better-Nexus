-- Synthetic WoW/Ebonhold harness for the independent prototype. No game access.
local H={now=1000,frames={},chat={},playerLevel=40,actions={},sent={},events=0}
local regionMethods={}
local function Region(kind,name,parent)
 local r={kind=kind,name=name,parent=parent,children={},regions={},scripts={},events={},points={},shown=true,text='',enabled=true,width=100,height=20,checked=false}
 setmetatable(r,{__index=function(t,k)
  if regionMethods[k] then return regionMethods[k] end
  if type(k)=='string' and k:match('^[A-Z]') then return function() end end
 end})
 if parent and parent.children then parent.children[#parent.children+1]=r end
 if name then _G[name]=r end
 return r
end
function regionMethods:GetName() return self.name end
function regionMethods:GetParent() return self.parent end
function regionMethods:SetParent(v) self.parent=v end
function regionMethods:GetObjectType() return self.kind end
function regionMethods:IsObjectType(k) return self.kind==k end
function regionMethods:SetScript(k,fn) self.scripts[k]=fn end
function regionMethods:GetScript(k) return self.scripts[k] end
function regionMethods:HookScript(k,fn) local old=self.scripts[k];self.scripts[k]=function(...) if old then old(...) end return fn(...) end end
function regionMethods:RegisterEvent(e) self.events[e]=true end
function regionMethods:UnregisterEvent(e) self.events[e]=nil end
function regionMethods:UnregisterAllEvents() self.events={} end
function regionMethods:SetMaxLetters(n) self.maxLetters=tonumber(n) or 0 end
function regionMethods:GetMaxLetters() return self.maxLetters or 0 end
-- A WoW EditBox holds at most maxLetters characters; anything longer is cut
-- when it is typed, pasted or set. 0 means no limit. The count is characters,
-- not bytes (bytes are SetMaxBytes, which is not modelled); the two are the
-- same for the ASCII wire values these tests carry.
local function editBoxText(box,value,userInput)
 local limit=tonumber(box.maxLetters) or 0
 if limit>0 and #value>limit then value=value:sub(1,limit) end
 box.text=value
 local changed=box.scripts and box.scripts.OnTextChanged
 -- The client passes isUserInput=false for a programmatic change.
 if changed then changed(box,userInput==true) end
end
function regionMethods:SetText(t) editBoxText(self,tostring(t or ''),false) end
function regionMethods:Insert(t) editBoxText(self,(self.text or '')..tostring(t or ''),true) end
function regionMethods:GetText() return self.text end
function regionMethods:SetFormattedText(fmt,...) editBoxText(self,string.format(fmt,...),false) end
function regionMethods:Show() local change=not self.shown; self.shown=true;if change and self.scripts.OnShow then self.scripts.OnShow(self) end end
function regionMethods:Hide() local change=self.shown;self.shown=false;if change and self.scripts.OnHide then self.scripts.OnHide(self) end end
-- Client widget booleans. By default the widget getters below answer Lua
-- booleans. The 3.3.5a client convention answers 1 or nil from IsShown,
-- IsVisible and GetChecked, and 1 or 0 from IsEnabled
-- (docs/UI_NATIVE_THEME_CORRECTION.md); the exact Ebonhold build-12340
-- returns are not verified here. A fixture selects that convention with
-- NEXUS_TEST_CLIENT_BOOLEANS='native' before loading this file, or at any
-- time with H.SetClientBooleans('native') / H.SetClientBooleans('lua'),
-- which applies to every existing and later frame. Mouse state is not
-- modelled here; a fixture that models IsMouseEnabled answers through
-- H.ClientBoolean so it follows the same convention.
local nativeBooleans=NEXUS_TEST_CLIENT_BOOLEANS=='native'
function H.SetClientBooleans(mode)
 assert(mode=='lua' or mode=='native','client boolean convention is lua or native')
 nativeBooleans=mode=='native'
end
function H.ClientBooleans() return nativeBooleans and 'native' or 'lua' end
function H.ClientBoolean(v)
 if nativeBooleans then if v then return 1 end return nil end
 return v and true or false
end
function regionMethods:IsShown()
 if nativeBooleans then return H.ClientBoolean(self.shown) end
 return self.shown
end
function regionMethods:IsVisible()
 local visible=self.shown and (not self.parent or self.parent:IsVisible())
 if nativeBooleans then return H.ClientBoolean(visible) end
 return visible
end
function regionMethods:Enable() self.enabled=true end
function regionMethods:Disable() self.enabled=false end
function regionMethods:IsEnabled()
 if nativeBooleans then if self.enabled then return 1 end return 0 end
 return self.enabled
end
function regionMethods:SetChecked(v) self.checked=v==true end
function regionMethods:GetChecked()
 if nativeBooleans then return H.ClientBoolean(self.checked) end
 return self.checked
end
function regionMethods:SetSize(w,h) self.width,self.height=w,h end
function regionMethods:SetWidth(v) self.width=v end
function regionMethods:SetHeight(v) self.height=v end
function regionMethods:GetWidth() return self.width end
function regionMethods:GetHeight() return self.height end
function regionMethods:GetEffectiveScale() return 1 end
function regionMethods:GetScale() return self.scale or 1 end
function regionMethods:SetScale(v) self.scale=v end
function regionMethods:SetPoint(...) self.points[#self.points+1]={...} end
function regionMethods:GetPoint(i) return unpack(self.points[i or 1] or {'CENTER',UIParent,'CENTER',0,0}) end
function regionMethods:GetNumPoints() return #self.points end
function regionMethods:ClearAllPoints() self.points={} end
function regionMethods:GetCenter() return 0,0 end
function regionMethods:GetTop() return 500 end
function regionMethods:GetBottom() return 0 end
function regionMethods:GetLeft() return 0 end
function regionMethods:GetRight() return self.width end
function regionMethods:GetFrameLevel() return self.frameLevel or 1 end
function regionMethods:SetFrameLevel(v) self.frameLevel=v end
function regionMethods:SetFrameStrata(v) self.strata=v end
function regionMethods:GetFrameStrata() return self.strata or 'MEDIUM' end
function regionMethods:SetValue(v) self.value=v end
function regionMethods:GetValue() return self.value or 0 end
function regionMethods:SetMinMaxValues(a,b) self.min,self.max=a,b end
function regionMethods:GetMinMaxValues() return self.min or 0,self.max or 100 end
function regionMethods:SetVerticalScroll(v) self.scroll=v end
function regionMethods:GetVerticalScroll() return self.scroll or 0 end
function regionMethods:GetVerticalScrollRange() return math.max(0,(self.scrollChild and self.scrollChild.height or 0)-self.height) end
function regionMethods:SetScrollChild(v) self.scrollChild=v end
function regionMethods:GetChildren() return unpack(self.children) end
function regionMethods:GetNumChildren() return #self.children end
function regionMethods:GetRegions() return unpack(self.regions) end
function regionMethods:CreateFontString(name) local r=Region('FontString',name,self);self.regions[#self.regions+1]=r;return r end
function regionMethods:CreateTexture(name) local r=Region('Texture',name,self);self.regions[#self.regions+1]=r;return r end
function regionMethods:SetTexture(v) self.texture=v end
function regionMethods:GetTexture() return self.texture end
function regionMethods:GetFont() return 'Fonts\\FRIZQT__.TTF',12,'' end
function regionMethods:GetStringWidth() return #self.text*6 end
function regionMethods:GetStringHeight() return 14 end
function regionMethods:HasFocus() return self.focused==true end
function regionMethods:SetFocus() self.focused=true end
function regionMethods:ClearFocus() self.focused=false end
function regionMethods:GetNumLines() return 1 end
-- GetMaxLetters used to answer 0 unconditionally, which hid every letter
-- limit a dialog or a caller had set. It now reports the real limit, set
-- above with SetMaxLetters.
function regionMethods:Click(button) if self.enabled and self.scripts.OnClick then return self.scripts.OnClick(self,button or 'LeftButton') end end
function CreateFrame(kind,name,parent) local f=Region(kind or 'Frame',name,parent);H.frames[#H.frames+1]=f;return f end
H.Region=Region
UIParent=Region('Frame','UIParent');Minimap=Region('Frame','Minimap',UIParent)
GameTooltip=Region('GameTooltip','GameTooltip',UIParent)
ChatFontNormal=Region('Font','ChatFontNormal');ChatFrame1=Region('Frame','ChatFrame1',UIParent)
DEFAULT_CHAT_FRAME={AddMessage=function(_,line) H.chat[#H.chat+1]=tostring(line) end}
UIErrorsFrame=DEFAULT_CHAT_FRAME
SlashCmdList={};UISpecialFrames={};StaticPopupDialogs={}
-- The client keeps a small pool of StaticPopup frames and reuses their edit
-- boxes. StaticPopup_Show applies a dialog's own maxLetters when it declares
-- one and leaves the previous limit in place when it does not, so a dialog
-- can inherit the limit and the handlers an earlier dialog installed on the
-- same box. That reuse is modelled here, because an import path that pastes a
-- long code cannot be tested against a stub that has no field at all.
H.popupPool={}
function StaticPopup_Show(which,a,b,data)
 local dialog=StaticPopupDialogs[which]
 local frame=H.popupPool[1]
 if not frame then
  frame=CreateFrame('Frame','NexusTestStaticPopup1',UIParent)
  frame.editBox=CreateFrame('EditBox',nil,frame)
  H.popupPool[1]=frame
 end
 frame.which,frame.data=which,data
 -- The client substitutes the show arguments into the dialog's text; a
 -- confirmation that cannot be read back cannot be tested for what it says.
 frame.arg1,frame.arg2=a,b
 frame.text=type(dialog)=='table' and dialog.text or nil
 if type(dialog)=='table' and dialog.maxLetters then
  frame.editBox:SetMaxLetters(dialog.maxLetters)
 end
 H.popup={which=which,data=data,frame=frame,editBox=frame.editBox,arg1=a,arg2=b}
 if type(dialog)=='table' and type(dialog.OnShow)=='function' then
  dialog.OnShow(frame,data)
 end
 return H.popup
end
function StaticPopup_Hide() H.popup=nil end
function H.AcceptPopup()
 local p=assert(H.popup)
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
function GetTime() return H.now end
function GetTimePreciseSec() return H.now end
-- The client's millisecond profiler. A fixture that must observe long-running
-- catalog work selects the supported no-clock pacing (one slice per update)
-- through startup_support.SingleSlicePacing, which sets this flag before the
-- runtime is loaded; every later boot in that test keeps the same pacing.
if NEXUS_TEST_NO_PROFILE_CLOCK then
 debugprofilestop=nil
else
 function debugprofilestop() return os.clock()*1000 end
end
function GetFramerate() return 60 end
GetFrameRate=GetFramerate
function UnitLevel() return H.playerLevel end
function UnitName() return 'PrototypeTester','Ebonhold' end
function UnitClass() return 'Mage','MAGE',8 end
function UnitGUID() return '0x0000000000000001' end
function GetRealmName() return 'Ebonhold' end
GetNormalizedRealmName=GetRealmName
function UnitExists() return false end
function UnitIsDeadOrGhost() return false end
function UnitIsPlayer() return true end
function UnitAffectingCombat() return H.combat==true end
function InCombatLockdown() return H.combat==true end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function GetCursorPosition() return 0,0 end
function GetBuildInfo() return '3.3.5','12340','Jun 24 2010',30300 end
function GetLocale() return 'enUS' end
function GetServerTime() return 1700000000+math.floor(H.now) end
date=os.date;time=function() return 1700000000+math.floor(H.now) end
function IsLoggedIn() return true end
function IsInGuild() return false end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function GetAddOnMetadata(addon,field) if field=='Version' then return '1.20.0-prototype' end end
function IsAddOnLoaded(name) return name=='ProjectEbonhold' end
function GetNumAddOns() return 2 end
function GetAddOnInfo(i) return i==1 and 'Nexus' or 'ProjectEbonhold','','',true,true end
function GetContainerNumSlots() return 0 end
function GetContainerItemLink() return nil end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetMouseFocus() return nil end
function ChatFrame_RemoveChannel() end
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_RemoveMessageEventFilter() end
function JoinTemporaryChannel(name) H.channel=name end
JoinChannelByName=JoinTemporaryChannel
function GetChannelList() return 1,H.channel or 'wrbuildssync' end
function GetChannelName() return 1,H.channel or 'wrbuildssync' end
function SendChatMessage(text,kind,lang,target) H.sent[#H.sent+1]={text=text,kind=kind,target=target,route='chat'};return true end
function SendAddonMessage(prefix,text,kind,target) H.sent[#H.sent+1]={prefix=prefix,text=text,kind=kind,target=target,route='addon'};return true end
function geterrorhandler() return function(err) error(err,0) end end
function hooksecurefunc(t,name,fn)
 if type(t)=='string' then t,name,fn=_G,t,name end
 local old=t[name];t[name]=function(...) local result=old and {old(...)} or {};fn(...);return unpack(result) end
end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
table.wipe=wipe
bit=bit or require('bit')
NUM_CHAT_WINDOWS=1;NUM_BAG_SLOTS=4
RAID_CLASS_COLORS={MAGE={r=.3,g=.7,b=1},PRIEST={r=1,g=1,b=1}}
function H.Advance(seconds,step)
 step=step or .05;local stop=H.now+seconds;local iterations=0
 while H.now<stop-1e-8 do
  H.now=math.min(stop,H.now+step);iterations=iterations+1;assert(iterations<300000,'advance bounded')
  local frames={};for i,f in ipairs(H.frames) do frames[i]=f end
  for _,f in ipairs(frames) do if f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f,step) end end
 end
end
function H.Fire(event,...)
 local frames={};for i,f in ipairs(H.frames) do frames[i]=f end
 for _,f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end end
 H.events=H.events+1
end
function H.Clone(v,seen)
 if type(v)~='table' then return v end;seen=seen or {};if seen[v] then return seen[v] end
 local t={};seen[v]=t;for k,c in pairs(v) do t[H.Clone(k,seen)]=H.Clone(c,seen) end;return t
end
H.db={};H.names={};H.granted={};H.locked={};H.discovered={};H.disabled={}
H.run={remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}
H.perks={serverBuildSlots={},serverActiveSlot=0};local P=H.perks;local S={}
function H.AddEcho(id,name,q,max,group)
 H.names[id]=name;H.db[id]={comment=name..' - '..({'Common','Uncommon','Rare','Epic','Legendary'})[(q or 0)+1],quality=q or 0,
 classMask=1535,maxStack=max or 1,minLevel=1,groupId=group or 0,requiredSpell=0,families={}}
end
for i=1,90 do H.AddEcho(200000+i,'Echo '..i,i%4,5) end
function GetSpellInfo(id) return H.names[tonumber(id)] end
function GetSpellTexture(id) return 'Interface\\Icons\\INV_Misc_QuestionMark' end
function S.GetCurrentChoice() return P.currentChoice end
function S.GetGrantedPerks() return H.granted end
function S.GetLockedPerks() return H.locked end
function S.GetActiveEchoLoadout() return H.wishlist end
function S.GetDiscoveredEchoes() return H.discovered end
function S.IsTomeEchoDisabled(id) return H.disabled[id]==true end
function S.RequestGrantedPerks()
 H.grantedRequests=(H.grantedRequests or 0)+1
 if not H.holdGrantedResponse and H.granted then H.granted=H.Clone(H.granted) end
end
function S.GetServerBuildSlots() return P.serverBuildSlots end
function S.GetServerActiveSlot() return P.serverActiveSlot end
function S.GetServerMaxSlots() return 5 end
function S.GetServerUnlockedSlots() return 5 end
function S.AreServerBuildSlotsEnabled() return true end
function S.CanActivateServerBuildSlot() return H.playerLevel==1 or H.playerLevel==80 end
function S.RequestServerBuildSlots() H.slotRequests=(H.slotRequests or 0)+1 end
function S.ActivateServerBuildSlot(id) H.actions[#H.actions+1]={'activate',id};return true end
function S.SaveServerBuildSlot(id,name) H.actions[#H.actions+1]={'save',id,name};return true end
function S.UploadServerBuildSlot(slot,name,ids)
 H.actions[#H.actions+1]={'upload',slot,name,H.Clone(ids)};return true
end
function S.GetPendingRollsCount() return H.pendingRolls or 40 end
function S.SelectPerk(id)
 if P.pendingSelectSpellId then return false end
 for _,c in ipairs(P.currentChoice or {}) do if c.spellId==id then
  P.pendingSelectSpellId=id;H.actions[#H.actions+1]={'take',id};return true end end
 return false
end
function S.BanishPerk(i)
 local c=(P.currentChoice or {})[i+1]
 if not c or c.isGuaranteed or P.pendingBanishIndex~=nil then return false end
 P.pendingBanishIndex=i;H.actions[#H.actions+1]={'banish',i};return true
end
function S.FreezePerk(i)
 local c=(P.currentChoice or {})[i+1]
 if not c or c.isGuaranteed or P.pendingFreezeIndex~=nil then return false end
 P.pendingFreezeIndex=i;H.actions[#H.actions+1]={'freeze',i};return true
end
function S.RequestReroll() if P.pendingReroll then return false end P.pendingReroll=true;H.actions[#H.actions+1]={'reroll'};return true end
function S.LockPerk(id) H.actions[#H.actions+1]={'lock',id};return true end
function S.UnlockPerk(id) H.actions[#H.actions+1]={'unlock',id};return true end
function S.ToggleTomeEcho(id) H.actions[#H.actions+1]={'toggle',id};return true end
local EJ={OnDataChanged=function() end,NotifyNewEcho=function() end}
local PU={Show=function() end,UpdateSinglePerk=function() end}
ProjectEbonhold={PerkDatabase=H.db,PerkService=S,Perks=P,PerkUI=PU,EchoJournal=EJ,
 PlayerRunService={GetCurrentData=function() return H.run end},Constants={ENABLE_BANISH_SYSTEM=true}}
local opts={autoAcceptLoadoutEchoes=false}
ProjectEbonholdOptionsService={GetSetting=function(_,k) return opts[k] end,SetSetting=function(_,k,v) opts[k]=v end}
H.service=S
function H.Notify() EJ.OnDataChanged() end
function H.Board(cards) P.currentChoice=H.Clone(cards);PU.Show(P.currentChoice) end
-- Unrelated integration fixtures model a player who already chose both
-- warning opt-outs. Use the real warning UI; do not bypass runtime gates.
-- Warning regressions opt out of this setup with keepOverwriteWarningPrompts.
function H.AcknowledgeOverwriteWarnings()
 local w=Nexus and Nexus.OverwriteWarning
 if not w then return end
 local outcome=w.EnsureOnboarding()
 local f=NexusOverwriteWarning
 if outcome=='pending' and f then
  -- Move only the external warning clock for this synthetic user's reading
  -- period. Do not advance lifecycle work or weaken any permission gate.
  local clock=GetTime
  GetTime=function()return clock()+5.01 end
  local update=f:GetScript('OnUpdate');if update then update(f,5.01)end
  if f.yes:IsEnabled()then f.suppress:SetChecked(true);f.yes:Click()end
  GetTime=clock
 end
 w.RequestAuto(H,function()return false end)
 f=NexusOverwriteWarning
 if f and f:IsShown() and f.yes:IsEnabled()then f.suppress:SetChecked(true);f.yes:Click()end
end
-- Test-support module loader for H.Boot (fresh boots repeat the whole TOC).
-- Every boot still runs every TOC file as a NEW function with fresh module
-- locals, a fresh private table and the current global environment, and the
-- first time a file's exact bytes are seen it is compiled by the real
-- loadfile. What is reused across boots is only immutable text: the file's
-- exact bytes and the bytecode the real compiler produced from them, which the
-- real loader turns into a new function each time. No live chunk, function
-- environment, module table, validation result or other result of running a
-- file is kept. A file whose bytes changed, or that cannot be read, is loaded
-- by loadfile itself, so its compile or read error is the real one.
--
-- Trusted footprint. The reuse path calls exactly these: the global loadfile
-- (a miss), loadstring (a hit), string.dump (a store), io.open, getmetatable
-- and the FILE methods read and close reached through the FILE metatable's
-- __index (reading the bytes). Their identities are captured once per process,
-- the first time this file runs, and only if each is a C builtin, each role is
-- a different function, loadfile and io.open answer an absent file with nil
-- and a message, and loadstring/string.dump round-trip a chunk; otherwise
-- nothing is ever reused in this process. On every load, reuse applies only
-- while every one of them, and the FILE metatable and its __index table, is
-- still that exact captured object, so a test or probe that replaces or wraps
-- any of them -- including with another C builtin, or by changing FILE read --
-- gets the plain loadfile(path) call, before any byte read is trusted. The
-- reader used is the captured read on a file whose metatable is the captured
-- one. Premise, not proven here: pcall, type, rawget and debug.getinfo
-- themselves are the runtime's own, and the first run of this file in a
-- process sees the runtime's own loader and reader. Bounded; process-wide so
-- that it survives this file being run again for each fresh harness.
local function Builtin(fn)
 if type(fn)~='function' or type(debug)~='table' or type(debug.getinfo)~='function' then return false end
 local ok,info=pcall(debug.getinfo,fn,'S')
 return ok and type(info)=='table' and info.what=='C'
end
local FOOTPRINT_FUNCTIONS={'loadfile','loadstring','dump','open','getmetatable','read','close'}
local FOOTPRINT={'loadfile','loadstring','dump','open','getmetatable','read','close','meta','index'}
-- The current objects in each footprint role, looked up the way the reuse path reaches them.
local function Footprint()
 local f={loadfile=loadfile,loadstring=loadstring,getmetatable=getmetatable,
  dump=type(string)=='table' and rawget(string,'dump') or nil,
  open=type(io)=='table' and rawget(io,'open') or nil}
 local stdout=type(io)=='table' and rawget(io,'stdout') or nil
 if type(getmetatable)=='function' and stdout~=nil then
  local ok,meta=pcall(getmetatable,stdout)
  if ok and type(meta)=='table' then
   f.meta=meta;f.index=rawget(meta,'__index')
   if type(f.index)=='table' then f.read=rawget(f.index,'read');f.close=rawget(f.index,'close') end
  end
 end
 return f
end
local function Capture()
 local f=Footprint()
 if type(f.meta)~='table' or type(f.index)~='table' then return false end
 local roles={}
 for _,k in ipairs(FOOTPRINT_FUNCTIONS) do
  if not Builtin(f[k]) or roles[f[k]] then return false end
  roles[f[k]]=true
 end
 local absent='tests/prototype/.nexus-harness-loader-absent-'..(tostring({}):gsub('%W',''))
 local okL,chunk,why=pcall(f.loadfile,absent)
 if not okL or chunk~=nil or type(why)~='string' then return false end
 local okO,handle,whyOpen=pcall(f.open,absent,'rb')
 if not okO or handle~=nil or type(whyOpen)~='string' then return false end
 local okS,probe=pcall(f.loadstring,'return 7')
 if not okS or type(probe)~='function' then return false end
 local okD,code=pcall(f.dump,probe)
 if not okD or type(code)~='string' then return false end
 local okR,again=pcall(f.loadstring,code)
 if not okR or type(again)~='function' then return false end
 local okRun,seven=pcall(again)
 if not okRun or seven~=7 then return false end
 return f
end
local LOADER_KEY,LOADER_MAX_ENTRIES,LOADER_MAX_BYTES='nexus.tests.prototype.harness_loader.v2',512,64*1024*1024
local loaderCache=nil
if type(package)=='table' and type(package.loaded)=='table' then
 loaderCache=package.loaded[LOADER_KEY]
 if type(loaderCache)~='table' then
  loaderCache={entries={},count=0,bytes=0,hits=0,misses=0,cold=0,trusted=Capture()}
  package.loaded[LOADER_KEY]=loaderCache
 end
end
-- The captured footprint while every role still holds its captured object, else nil.
local function Trusted()
 local t=loaderCache and loaderCache.trusted
 if type(t)~='table' then return nil end
 local now=Footprint()
 for _,k in ipairs(FOOTPRINT) do if now[k]~=t[k] then return nil end end
 return t
end
-- The exact bytes through the captured opener and reader, or nil.
local function ReadBytes(t,path)
 local ok,file=pcall(t.open,path,'rb')
 if not ok or file==nil then return nil end
 local okMeta,meta=pcall(t.getmetatable,file)
 if not okMeta or meta~=t.meta then return nil end
 local okRead,bytes=pcall(t.read,file,'*a')
 pcall(t.close,file)
 if okRead and type(bytes)=='string' then return bytes end
 return nil
end
local function Reusable() return Trusted()~=nil end
local function Forget(path)
 local old=loaderCache.entries[path]
 if old then
  loaderCache.entries[path]=nil
  loaderCache.count=loaderCache.count-1;loaderCache.bytes=loaderCache.bytes-old.size
 end
end
-- Returns exactly what loadfile(path) would: a new function, or nil and the error.
local function LoadModule(path)
 local t=Trusted()
 if not t then
  if loaderCache then loaderCache.cold=loaderCache.cold+1 end
  return loadfile(path)
 end
 local bytes=ReadBytes(t,path)
 local entry=bytes and loaderCache.entries[path]
 if entry and entry.source==bytes then
  local chunk=t.loadstring(entry.code,'@'..path)
  if type(chunk)=='function' then loaderCache.hits=loaderCache.hits+1;return chunk end
 end
 loaderCache.misses=loaderCache.misses+1
 Forget(path)
 local chunk,err=loadfile(path)
 if not chunk then return chunk,err end
 -- Kept only while the footprint is still the captured one and the bytes read
 -- before and after the real compile agree.
 if bytes and Trusted()==t and ReadBytes(t,path)==bytes then
  local okDump,code=pcall(t.dump,chunk)
  if okDump and type(code)=='string' then
   local size=#bytes+#code
   if loaderCache.count<LOADER_MAX_ENTRIES and loaderCache.bytes+size<=LOADER_MAX_BYTES then
    loaderCache.entries[path]={source=bytes,code=code,size=size}
    loaderCache.count=loaderCache.count+1;loaderCache.bytes=loaderCache.bytes+size
   end
  end
 end
 return chunk
end
H.LoadModule=LoadModule
function H.LoaderStats()
 local c=loaderCache or {}
 return {hits=c.hits or 0,misses=c.misses or 0,cold=c.cold or 0,entries=c.count or 0,bytes=c.bytes or 0,
  reusable=Reusable(),captured=type(c.trusted)=='table'}
end
function H.Boot()
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local path=line:gsub('\\','/')
   local chunk,err=LoadModule(path);assert(chunk,err);chunk('Nexus',{})
  end
 end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 H.Advance(20,.05)
 if not H.keepOverwriteWarningPrompts then H.AcknowledgeOverwriteWarnings()end
 return Nexus
end
return H
