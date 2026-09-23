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
function regionMethods:IsShown() return self.shown end
function regionMethods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function regionMethods:Enable() self.enabled=true end
function regionMethods:Disable() self.enabled=false end
function regionMethods:IsEnabled() return self.enabled end
function regionMethods:SetChecked(v) self.checked=v==true end
function regionMethods:GetChecked() return self.checked end
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
 frame.text=type(dialog)=='table' and dialog.text or nil
 if type(dialog)=='table' and dialog.maxLetters then
  frame.editBox:SetMaxLetters(dialog.maxLetters)
 end
 H.popup={which=which,data=data,frame=frame,editBox=frame.editBox}
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
function H.Boot()
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local path=line:gsub('\\','/')
   local chunk,err=loadfile(path);assert(chunk,err);chunk('Nexus',{})
  end
 end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 H.Advance(20,.05)
 return Nexus
end
return H
