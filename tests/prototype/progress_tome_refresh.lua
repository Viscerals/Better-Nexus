-- Real lifecycle provider + Progress renderer; synthetic service only.
-- Proposed contract: semantic changes refresh held-visible expanded details;
-- hidden/collapsed pages stay lazy. Local mirror reads prove no server freshness.
Nexus,NexusDB,WishlistRealizerDB=nil,nil,nil
local H=dofile('tests/prototype/harness.lua')
local IDS={300001,300002,300003,300004}
local SETS={{1,2},{2,3},{1,4}}
local NAMES={'A','B','C'}
H.playerLevel=80;wipe(H.db)
H.AddEcho(200001,'Common Baseline',1,1,0)
for i,id in ipairs(IDS) do
 H.AddEcho(id,'Refresh Echo '..i,1,1,0);H.db[id].requiredSpell=777000+i
 H.names[777000+i]='Tome of Refresh Echo '..i
 H.discovered[id]=true;H.disabled[id]=false
end
H.perks.discoveredEchoes=H.discovered
H.perks.serverActiveSlot=1;H.perks.serverBuildSlots={}
for slot=1,3 do
 H.perks.serverBuildSlots[slot]={name='Refresh Saved '..NAMES[slot],verified=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
 local entries={{spellId=200001,quality=1,stacks=1,locked=false}}
 for _,n in ipairs(SETS[slot]) do entries[#entries+1]={spellId=IDS[n],quality=1,stacks=1,locked=false} end
 H.perks.serverBuildSlots[100+slot]={name='Refresh Plan '..NAMES[slot],verified=false,echoes=entries}
end
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 IsOfferPending=function()return false end,GetCharges=function()return 0 end,
 RequestCharges=function()end,ConfirmSpend=function()error('display must not spend')end}
-- Each accepted request waits0.9s, then a real mirrored answer/notification.
local calls,waiting={},{}
local rawToggle=H.service.ToggleTomeEcho
H.service.ToggleTomeEcho=function(id)
 local before=H.disabled[id]==true;local ok=rawToggle(id)
 if ok then
  calls[#calls+1]={id=id,at=H.now,want=not before}
  waiting[#waiting+1]={id=id,due=H.now+.9,want=not before}
 end
 return ok
end
local mirror=CreateFrame('Frame',nil,UIParent)
mirror:SetScript('OnUpdate',function()
 for i=#waiting,1,-1 do
  local r=waiting[i]
  if H.now>=r.due then H.disabled[r.id]=r.want;table.remove(waiting,i);H.Notify() end
 end
end)
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:SetSize(570,450)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
local installedProvider,rawInstall
local fire=H.Fire
H.Fire=function(event,...)
 if event=='ADDON_LOADED' and Nexus and Nexus.JournalTab then
  rawInstall=Nexus.JournalTab.TryInstall
  Nexus.JournalTab.TryInstall=function(fn,...)
   installedProvider=fn;return rawInstall(fn,...)
  end
 end
 return fire(event,...)
end
H.Boot();H.Fire=fire
if rawInstall then Nexus.JournalTab.TryInstall=rawInstall end
local A=Nexus.GameAdapter
local checks,failures,guardFailures=0,{},{}
local function expect(v,msg,guard)
 checks=checks+1
 if not v then
  local list=guard and guardFailures or failures;list[#list+1]=msg
  print((guard and 'GUARD_MISS ' or 'RED_MISS ')..msg)
 end
end
local function setup(v,msg)assert(v,'SETUP: '..msg)end
local function up(fn,key)
 for i=1,255 do local name,v=debug.getupvalue(fn,i);if not name then break end;if name==key then return v end end
end
local function runtime()
 local a=up(Nexus.RecomputeStats,'Automation')
 local ensure=a and up(a,'EnsureAutomationRuntime')
 return ensure and up(ensure,'AutomationRuntime')
end
for slot=1,3 do local ok,why=A.SetLoadoutWishlist(slot,100+slot);setup(ok,'prebind '..slot..': '..tostring(why))end
H.Notify();A.Poll();H.Advance(.4,.05)
SlashCmdList.NEXUS('auto');H.Advance(.4,.05)
setup(Nexus.RecomputeStats().autoEnabled and Nexus.Store.Settings().autoDisable,'AutoON and tome permission')
setup(#calls==0,'level80 fixture sent no tome request')
local runtime0=runtime()
setup(type(runtime0)=='table' and installedProvider==runtime0.JournalData,'actual cached runtime provider installed')
local observationCalls=0
local observeFn=A.TomeStateObservation
debug.sethook(function()
 local info=debug.getinfo(2,'f')
 if info and info.func==observeFn then observationCalls=observationCalls+1 end
end,'c')
-- The Progress page's own control: the main panel's Play section has a
-- Show/Hide details button with the same label.
local function button(text)
 local child=assert(NexusJournalScroll and NexusJournalScroll.scrollChild,'SETUP: real Progress child')
 for _,r in ipairs(H.frames) do if r.kind=='Button' and r.parent==child and r:IsVisible() and r:GetText()==text then return r end end
end
local function ui(label,fn)
 local actions,sent=#H.actions,#H.sent;fn()
 expect(#H.actions==actions and #H.sent==sent,label..' sends no gameplay/network action',true)
end
local function rows()
 local child=assert(NexusJournalScroll and NexusJournalScroll.scrollChild,'SETUP: real Progress child')
 local out,duplicates={},0
 for _,r in ipairs(H.frames) do
  if r.parent==child and r.label and r.status and r.tome and r:IsVisible() then
   if out[r.tome.leverId] then duplicates=duplicates+1 end
   out[r.tome.leverId]=r
  end
 end
 return out,duplicates
end
local function display(label,guard)
 local shown,duplicates=rows();local parts={}
 expect(duplicates==0,label..' has no duplicate/pending lever row',guard)
 for i,id in ipairs(IDS) do
  local lever=777000+i
  local wanted=H.disabled[id] and 'Disabled' or 'Enabled'
  local got=shown[lever] and shown[lever].status:GetText() or '<missing>'
  parts[#parts+1]=lever..':'..got..'/actual='..wanted
  expect(got==wanted,label..' displayed '..lever..' '..got..' matches confirmed '..wanted,guard)
 end
 print('DISPLAY '..label..' {'..table.concat(parts,',')..'} observations='..observationCalls)
end
local function native(slot,label)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll();H.Advance(6,.05)
 local enabled={};for _,n in ipairs(SETS[slot]) do enabled[IDS[n]]=true end
 local assigned=A.AssignedWishlist();local disabled=A.DisabledLevers()
 expect(A.Slots().activeSlot==slot and A.SelectedSavedBuild()==slot,label..' native/selected identity',true)
 expect(assigned.state=='ready' and assigned.name=='Refresh Plan '..NAMES[slot] and assigned.activeSlot==slot,label..' assignment identity',true)
 for i,id in ipairs(IDS) do
  expect((H.disabled[id]==true)==(not enabled[id]),label..' actual mirror '..id,true)
  expect((enabled[id] and disabled[777000+i]==nil) or (not enabled[id] and disabled[777000+i]=='confirmed'),label..' confirmed lever '..i,true)
 end
 expect(next(Nexus.Store.State().tomeTogglePending)==nil and #waiting==0,label..' delayed requests fully confirmed',true)
 expect(runtime()==runtime0,label..' cached runtime retained',true)
 print('STATE '..label..' native='..slot..' assigned='..assigned.name..' accepted='..#calls..' pendingEmpty='..tostring(next(Nexus.Store.State().tomeTogglePending)==nil))
end
H.playerLevel=1;H.Fire('PLAYER_LEVEL_UP',1);H.Notify()
native(1,'initial-A')
ui('open actual Progress details',function()
 journal:Show();assert(NexusJournalTab):Click()
 assert(button('Show details'),'SETUP: real Show details'):Click()
end)
setup(NexusJournalPanel:IsVisible(),'real Progress details visible')
display('initial-A',true)
for _,slot in ipairs({2,3,1}) do
 native(slot,'held-'..NAMES[slot]);display('held-'..NAMES[slot],false)
end
-- Hide details: no new provider tome work for an automatic invalidation.
ui('collapse details',function()assert(button('Hide details')):Click()end)
local before=observationCalls
native(2,'collapsed-B')
expect(observationCalls==before,'collapsed change adds zero page tome observations',true)
local collapsed=rows();expect(next(collapsed)==nil,'collapsed tome pool hidden',true)
print('CONTROL collapsed additionalObservations='..(observationCalls-before))
ui('show details',function()assert(button('Show details')):Click()end);display('reopened-B',true)
-- IsShown can remain true for a parent-hidden Progress panel.
ui('hide host journal',function()journal:Hide()end)
before=observationCalls
native(3,'hidden-C')
expect(observationCalls==before,'hidden change adds zero page tome observations',true)
print('CONTROL hidden additionalObservations='..(observationCalls-before)..' panelShown='..tostring(NexusJournalPanel:IsShown())..' panelVisible='..tostring(NexusJournalPanel:IsVisible()))
ui('reopen real Progress',function()journal:Show();NexusJournalTab:Click()end);display('reopened-C',true)
H.Advance(.8,.05);before=observationCalls
local actions=#H.actions;H.Notify();A.Poll();H.Advance(2,.05)
expect(observationCalls==before,'equivalent notification and idle add zero page observations',true)
expect(#H.actions==actions,'equivalent notification/idle send no gameplay action',true)
for i=2,#calls do expect(calls[i].at-calls[i-1].at>=.5-1e-6,'accepted request spacing '..i,true)end
-- The real row hover owns the tooltip. Reusing its pooled row must not
-- leave the earlier tome's text visible, nor dismiss an unrelated tooltip.
function GameTooltip:SetOwner(owner)self._testOwner=owner;self._testLines={}end
function GameTooltip:GetOwner()return self._testOwner end
function GameTooltip:IsOwned(owner)return self._testOwner==owner end
function GameTooltip:AddLine(line)self._testLines[#self._testLines+1]=tostring(line)end
local shown=rows();local hovered=assert(shown[777002],'SETUP: displayed tooltip row')
assert(hovered:GetScript('OnEnter'),'SETUP: real tome hover')(hovered)
setup(GameTooltip:IsShown() and GameTooltip:GetOwner()==hovered,'owned tome tooltip visible')
native(2,'tooltip-rebind-B')
ui('explicit page refresh',function()Nexus.JournalTab.Refresh()end)
expect(not GameTooltip:IsShown(),'pooled tome tooltip closes before row rebind',false)
local unrelated=CreateFrame('Button',nil,journal)
GameTooltip:SetOwner(unrelated,'ANCHOR_RIGHT');GameTooltip:AddLine('Unrelated tooltip');GameTooltip:Show()
ui('unrelated-tooltip page refresh',function()Nexus.JournalTab.Refresh()end)
expect(GameTooltip:IsShown() and GameTooltip:GetOwner()==unrelated and GameTooltip._testLines[1]=='Unrelated tooltip',
 'page refresh preserves an unrelated tooltip',true)

debug.sethook()
print('RESULT checks='..checks..' redFailures='..#failures..' guardFailures='..#guardFailures..' accepted='..#calls..' observationCalls='..observationCalls..' cachedRuntime=true delay=.9')
assert(#guardFailures==0,'GUARD FAILURES:\n'..table.concat(guardFailures,'\n'))
assert(#failures==0,'HELD-OPEN PROGRESS CONTRACT FAILURES:\n'..table.concat(failures,'\n'))
print('PASS visible expanded Progress refreshes on semantic change; hidden/collapsed stay lazy')
