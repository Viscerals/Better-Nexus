-- Real normal consumers. Only input data and game/UI surfaces are synthetic.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2;H.Boot()
local A=Nexus.GameAdapter;local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local function texts()
 local out={}
 for _,f in ipairs(H.frames)do
  if f.IsVisible and f:IsVisible()then
   local value=f:GetText();if type(value)=='string'then out[#out+1]=value end
   for _,r in ipairs(f.regions or {})do if r:IsShown()then
    value=r:GetText();if type(value)=='string'then out[#out+1]=value end
   end end
  end
 end
 return table.concat(out,'\n')
end
assert(A.SetFirstLoadoutWishlistIdentity('Review target',{{spellId=200001,quality=1,stacks=2}}))
SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('reroll off');Nexus.Panel.Show()
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
H.Notify();H.Advance(.5)
check(texts():find('Take a needed Echo',1,true) and not texts():find('(EchoWeaver)',1,true),'T19 actual policy -> runtime -> Panel fontstring')
local rawLabels={
 {'Freeze wanted Echo before search (EchoWeaver)','Freeze a needed Echo'},
 {'Banish to find Wishlist targets (EchoWeaver)','Banish to find Wishlist targets'},
 {'Reroll: no requested Echo on board (EchoWeaver)','Reroll: no requested Echo'},
 {'Take available filler (EchoWeaver)','outside the Wishlist'},
 {'Take filler; search unavailable (EchoWeaver)','no permitted Banish or Reroll action'},
 {'Wishlist complete; take filler (EchoWeaver)','Wishlist complete'},
 {'waiting: unsynced','Waiting for current Echo data'},
 {'waiting for owned-state sync','Waiting for current Echo data'},
 {'waiting for owned-echo sync','Waiting for current Echo data'},
 {'armed (guaranteed queue live)','no future offer is assumed'},
 {'Activate did not guarantee -- treating as unarmed','no future guarantee is assumed'},
 {'tight horizon: take guaranteed','few selections remain'},
 {'bracket fishing: reroll filler guarantee','enabled policy'},
 {'drain guaranteed queue','no future offer is assumed'},
 {'disabling off-wishlist tome lever 12345','Echo-availability control #12345'},
 {'ROOT_MUTATION_PENDING','Saving is still in progress'},
 {'MISSING_REVIEW_CODE','Details: MISSING_REVIEW_CODE'},
 {'payload changed','Reopen it and review'},
}
for _,case in ipairs(rawLabels)do
 local model=H.Clone(Nexus.Panel._lastModel);model.recommendation=case[1];model.status=case[1]
 assert(Nexus.Panel.Render(model))
 check(texts():find(case[2],1,true),'actual recommendation consumer: '..case[1])
 check(model.recommendation==case[1],'raw producer remains unchanged')
 check(Nexus.Panel._lastModel.status:find(case[2],1,true),'normal status model maps same producer')
end
for _,annotation in ipairs({'banked','returns later'})do
 local model=H.Clone(Nexus.Panel._lastModel)
 model.cards={{text=Nexus.Readout.CardLine({name='Echo',quality=1,isGuaranteed=true},annotation,12)}}
 model.recommendation='Take'
 assert(Nexus.Panel.Render(model))
 check(texts():find(annotation=='banked' and 'Held offer' or 'a later offer is not guaranteed',1,true),'T26 actual card fontstring')
 check(texts():find('[Guaranteed offer]',1,true),'current guaranteed offer is distinct from prediction')
end
check(Nexus.Readout.QueueLines({entries={{name='Echo',wanted=true}}},1)[1]:find('(predicted)',1,true),'queue remains a prediction')
-- Issue #123: the three status reasons through the localization seam in the
-- normal panel/readout consumers: exact English bytes, repeated
-- normalization and untouched raw inputs. An absent pre-seam module is a
-- setup fact, not a behavioral RED for the guards below. Non-effect checks
-- cover these synchronous calls; no deferred or Orb/resource claim is made.
local L=assert(Nexus.Localization,'localization seam loaded before its consumers');checks=checks+1
local function same(a,b,seen)
 if type(a)~='table' or type(b)~='table' then return a==b end
 seen=seen or {};if seen[a] then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a)do if not same(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local state0=H.Clone(Nexus.Store.State())
check(state0.loadoutWishlists[1] and state0.firstRunWishlist and state0.firstRunWishlist.assignmentId==state0.loadoutWishlists[1].assignmentId and state0.firstRunWishlist.key==state0.loadoutWishlists[1].key and #state0.firstRunWishlist.echoes>0,'SETUP real nonempty adapter-assigned state before localization calls')
-- Positive control on the real non-StaticPopup consent owner and frame.
-- The harness user opted out at boot; lift only that synthetic saved opt-out
-- so a pending request can remain open during the synchronous calls below.
local warning=assert(Nexus.OverwriteWarning);local warningOwner={};local accepted=0
local savedAutoWarning=NexusDB.overwriteWarnings.auto
NexusDB.overwriteWarnings.auto=nil
check(not warning.RequestAuto(warningOwner,function()accepted=accepted+1 end) and warning.IsOpen() and NexusOverwriteWarning:IsShown(),'SETUP actual overwrite warning is open and visible')
check(not warning.CancelAuto({}) and warning.IsOpen() and NexusOverwriteWarning:IsShown(),'SETUP another owner cannot close the pending warning')
local settings0=H.Clone(Nexus.Store.Settings())
local before={actions=#H.actions,sent=#H.sent,chat=#H.chat,popup=H.popup,auto=Nexus.RecomputeStats().autoEnabled,misses=L.Diagnostics().misses}
for _,case in ipairs({
 {'ROOT_MUTATION_PENDING','reason.save_in_progress','Saving is still in progress; wait for its final result'},
 {'CURSOR_REQUIRED','reason.list_preparing','This list is still being prepared'},
 {'STORE_PENDING','reason.saved_data_reading','Reading your saved data'},
})do
 local code,english=case[1],case[3]
 check(L.Text(case[2])==english,'seam English base: '..case[2])
 local model=H.Clone(Nexus.Panel._lastModel);model.status=code;model.recommendation=code
 local pristine=H.Clone(model)
 assert(Nexus.Panel.Render(model))
 check(same(model,pristine),'Render leaves the raw model and reason untouched: '..code)
 check(Nexus.Panel._lastModel.status==english and Nexus.Panel._lastModel.recommendation==english,'committed panel model has the exact English: '..code)
 check(texts():find(english,1,true) and not texts():find(code,1,true),'actual panel fontstring shows the English, not the code: '..code)
 local again=H.Clone(Nexus.Panel._lastModel);assert(Nexus.Panel.Render(again))
 check(Nexus.Panel._lastModel.status==english and Nexus.Panel._lastModel.recommendation==english,'rendering converted text again is stable: '..code)
 -- Arrange a distinct legitimate status through Render, never SetStatus.
 local distinct=H.Clone(Nexus.Panel._lastModel)
 distinct.status=code=='ROOT_MUTATION_PENDING' and 'STORE_PENDING' or 'ROOT_MUTATION_PENDING'
 local prior=code=='ROOT_MUTATION_PENDING' and 'Reading your saved data' or 'Saving is still in progress; wait for its final result'
 assert(Nexus.Panel.Render(distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP Render stores a distinct status before SetStatus: '..code)
 check(Nexus.Panel.SetStatus(code)==true and Nexus.Panel._lastModel.status==english,'GUARD raw SetStatus updates to exact English: '..code)
 check(Nexus.Panel.SetStatus(code)==false and Nexus.Panel._lastModel.status==english,'GUARD repeated SetStatus reports no update: '..code)
 assert(Nexus.Panel.Render(distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP independent Render before onStatus double conversion: '..code)
 check(Nexus.Panel.SetStatus(Nexus.UserText.Message(code))==true and Nexus.Panel._lastModel.status==english,'GUARD onStatus double conversion updates exact English: '..code)
 check(Nexus.Readout.Status({text=code})==english and Nexus.Readout.Status({text=code,level=12})=='Lv 12 - '..english,'Readout status line: '..code)
 check(Nexus.Readout.AutoHoldText(code)==english and Nexus.Readout.AutoHoldNote(code):find('Paused: '..english,1,true),'Readout Auto hold line: '..code)
end
check(L.Resolve('reason.list_preparing',{['reason.list_preparing']='Fixture list text'})=='Fixture list text','fixture candidate resolves only when injected')
local plain=H.Clone(Nexus.Panel._lastModel);plain.status='CURSOR_REQUIRED';plain.recommendation='CURSOR_REQUIRED'
assert(Nexus.Panel.Render(plain))
check(texts():find('This list is still being prepared',1,true) and not texts():find('Fixture list text',1,true),'the panel never selects an injected candidate')
check(L.Diagnostics().misses==before.misses,'the normal consumer path records no fallback')
check(#H.actions==before.actions and #H.sent==before.sent and H.popup==before.popup and #H.chat==before.chat,'synchronous consumers cause no observed game action, Sync send, StaticPopup or chat')
check(Nexus.RecomputeStats().autoEnabled==before.auto and same(Nexus.Store.Settings(),settings0),'Automation selection and settings unchanged')
check(same(Nexus.Store.State(),state0),'GUARD full detached state preserves assigned Wishlists and related identities')
check(warning.IsOpen() and NexusOverwriteWarning:IsShown() and accepted==0,'GUARD actual pending consent remains open/visible and unaccepted')
check(not warning.CancelAuto({}) and warning.IsOpen() and NexusOverwriteWarning:IsShown(),'GUARD pending consent still belongs to original owner')
check(warning.CancelAuto(warningOwner) and not warning.IsOpen() and not NexusOverwriteWarning:IsShown() and accepted==0,'GUARD original owner can cancel the unchanged warning')
NexusDB.overwriteWarnings.auto=savedAutoWarning
Nexus.WishlistEditor.Show();check(texts():find('Build Library',1,true),'T01 actual Wishlist navigation')
Nexus.CommunityBuilds.Show();check(texts():find('Build Library',1,true),'T01 actual library navigation/title')
-- Real projection Detail and its normal renderer, with fixture read dependencies.
local owner=Nexus.Store.CurrentOwnerKey()
local record={id='review-record',title='Review fixture',author='PrototypeTester',realm='Ebonhold',
 ownerKey=owner,ownerVerified=true,class='MAGE',echoes={{spellId=200001,quality=1,stacks=1}},lockedEchoes={}}
local records={}
for _,id in ipairs({'saved','shared','locked','copy'})do records[id]=H.Clone(record);records[id].id=id end
records.saved.importedSavedBuild=true;records.shared.importedSavedBuild=true;records.shared.publishedBuildId='published'
records.locked.autoDps=true
local projection=Nexus.CommunityInternals.Projection.New({
 builds=function()return {}end,buildsCurrent=function()return true end,
 loadBuild=function(id)return records[id]end,savedProjection=function(b)return b end})
local function find(value,needle,seen)
 if (type(value)~='function' and type(value)~='table')or seen[value]then return end
 seen[value]=true
 if type(value)=='function'then
  for i=1,100 do local name,v=debug.getupvalue(value,i);if not name then break end
   if name==needle then return v end
   if name~='_ENV'then local got=find(v,needle,seen);if got then return got end end
  end
 else for k,v in pairs(value)do if k~='_G' then local got=find(v,needle,seen);if got then return got end end end end
end
local renderDetail=assert(find(Nexus.CommunityBuilds.Refresh,'RefreshDetailPanel',{}))
for i=1,100 do local name=debug.getupvalue(renderDetail,i);if not name then break end
 if name=='EnsureCommunityProjection'then debug.setupvalue(renderDetail,i,function()return projection end)end
end
local dp=assert(NexusCommunityBuildsFrame._detailPanel)
for _,case in ipairs({{'saved','Share Build','server Saved Build'},{'shared','Update Shared Build','Shared.'},
 {'locked','Copy into Editor','Echo list is read-only'},{'copy','Copy into Editor','You own this build'}})do
 local detail,e=projection.Detail(case[1],{ownerKey=owner,ownedBySpell={}});check(detail,e or 'real projection exists')
 renderDetail(case[1])
 check(dp.lockBtn:GetText()==case[2],'projected action reaches actual button')
 check(dp.editState:GetText():find(case[3],1,true),'projected edit status reaches actual fontstring')
end
-- Empty evidence remains refused rather than weakening the guard to render a request.
records.empty=H.Clone(record);records.empty.echoes=nil
check(not projection.Detail('empty',{ownerKey=owner}),'T38 absent full list remains subject to evidence guard')
-- Real Journal provider and actual fontstrings retain supported-activation wording.
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
assert(Nexus.JournalTab.TryInstall(function()return {sections={{title='Tome levers',lines={'lever 12345: disable'}}}}end))
NexusJournalTab:Click();Nexus.JournalTab.Refresh()
-- The provider sections sit behind the page's own Show details button.
for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetText()=='Show details' then b:Click() end end
check(texts():find("server's supported level and state",1,true),'T47 actual Journal note')
check(texts():find('Echo availability controls',1,true) and texts():find('Echo-availability control #12345',1,true),'T28 Journal producer -> fontstrings')
check(not texts():find('level-1-only',1,true),'incorrect categorical level claim absent')
-- Issue #123, optional language packs through the real preference, the real
-- ... menu (EasyMenu capture), a durable Store write, reloads and the ordinary
-- UserText -> Panel/Readout display path. Actual TOC boots of synthetic saved
-- data (format5_support); no player data and no native payload. Technical
-- checks only: no linguistic acceptance and no native rendering is claimed.
do
 ProjectEbonholdEchoJournal,ProjectEbonholdEchoJournalScroll,ProjectEbonholdEchoJournalTab1=nil,nil,nil
 local F=dofile('tests/prototype/format5_support.lua')
 local IDS={'frFR','deDE','esES','plPL','ptBR','ruRU'}
 local COHORT={{'ROOT_MUTATION_PENDING','reason.save_in_progress','Saving is still in progress; wait for its final result'},
  {'CURSOR_REQUIRED','reason.list_preparing','This list is still being prepared'},
  {'STORE_PENDING','reason.saved_data_reading','Reading your saved data'}}
 local penv={};local pchunk=setfenv and setfenv(assert(loadfile('data/LocalizationPacks.lua')),penv) or assert(loadfile('data/LocalizationPacks.lua','t',penv));pchunk()
 local PACKS=assert(penv.Nexus and penv.Nexus.LocalizationPacks,'pack data');checks=checks+1
 local function Want(id,case)return id=='enUS' and case[3] or PACKS[id].entries[case[2]] end
 local writes
 local function CountWriter()
  writes={n=0}
  local owner=Nexus.MainInternals.StoreAuthorityOwner;local original=owner.UpdateSettingsV1
  owner.UpdateSettingsV1=function(...)writes.n=writes.n+1;return original(...)end
 end
 local function LanguageMenu()
  local items;EasyMenu=function(list)items=list end
  NexusPanel._menuBtn:Click()
  local found,rows=nil,0
  for _,item in ipairs(items or {})do
   if type(item.text)=='string' and item.text:find('^Language')then found=found or item;rows=rows+1 end
  end
  return found,rows
 end
 local function Row(menu,id)
  local name=id=='enUS' and 'English' or PACKS[id].name
  for _,row in ipairs(menu and menu.menuList or {})do
   if type(row.text)=='string' and row.func and row.text:sub(1,#name)==name then return row end
  end
 end
 local function MenuText(menu)
  local out={}
  for _,row in ipairs(menu and menu.menuList or {})do out[#out+1]=tostring(row.text)end
  return table.concat(out,'\n')
 end
 local function Effects()
  return F.Serialize({actions=#H.actions,sent=#H.sent,popup=H.popup~=nil,
   auto=Nexus.RecomputeStats().autoEnabled==true,
   option=ProjectEbonholdOptionsService:GetSetting('autoAcceptLoadoutEchoes')==true,
   chars=NexusDB.chars,warnings=NexusDB.overwriteWarnings,ledger=NexusDB.accountCharacters,
   top=NexusDB.genUnknownTopLevel,archive=NexusDB.nexusNativeRecoveryArchiveF5})
 end
 local function RootWithout()
  local settings=NexusDB.settings;local value=rawget(settings,'uiLanguage')
  settings.uiLanguage=nil;local text=F.Serialize(NexusDB);settings.uiLanguage=value
  return text
 end
 local function Expect(id,label)
  check(Nexus.Localization.ActiveLanguage()==id,label..': active language is '..id..' ('..tostring(Nexus.Localization.ActiveLanguage())..')')
  for _,case in ipairs(COHORT)do
   local want=Want(id,case)
   check(Nexus.UserText.Message(case[1])==want and Nexus.UserText.Message(want)==want,label..': UserText shows the active text, stable when normalized again: '..case[1])
   check(Nexus.Readout.Status({text=case[1],level=12})=='Lv 12 - '..want,label..': the readout status line: '..case[1])
   local model={status=case[1],recommendation=case[1],cards={},auto=false,level=40,version=Nexus.VERSION,
    progress={wishlistName='Language review',total=2,owned=0,missing={},shed={},unknownTomes={},toLock={}}}
   Nexus.Panel.Show();assert(Nexus.Panel.Render(model))
   check(model.status==case[1] and model.recommendation==case[1],label..': the raw reason stays the input: '..case[1])
   check(Nexus.Panel._lastModel.status==want and NexusPanel._rollRec:GetText()==want and NexusPanel._rollArea:IsShown(),label..': the panel fontstring shows it: '..case[1])
  end
 end
 -- A. English default: an absent preference, nothing added at start-up; menu reads write nothing.
 H=F.Boot(F.Database({version=2}))
 check(Nexus.StartupStatus().coreReady==true and Nexus.MainInternals.SavedRootReadOnlyV1()==nil,'fixture: a writable saved root started')
 check(rawget(NexusDB.settings,'uiLanguage')==nil,'English default: start-up adds no language preference')
 Expect('enUS','English default')
 CountWriter()
 local effects,settings0,chat0=Effects(),F.Serialize(NexusDB.settings),#H.chat
 Nexus.Panel.Show()
 local menu,rows=LanguageMenu()
 check(menu and rows==1 and menu.hasArrow and type(menu.menuList)=='table','the ... menu has exactly one Language row with a submenu')
 local text=MenuText(menu)
 check(Row(menu,'enUS') and text:find('three status messages',1,true) and text:find('other Nexus text stays English',1,true),'English and the partial result are listed')
 for _,id in ipairs(IDS)do
  check(Row(menu,id) and not Row(menu,id).disabled,'the chooser lists '..id..' by its own name, enabled')
  check(not text:find(id,1,true) and not menu.text:find(id,1,true),'no internal language ID is shown: '..id)
 end
 check(text:find('reload',1,true) and not text:lower():find('fully',1,true) and not text:find('Changes unavailable',1,true),'the reload requirement, no full-support claim, no refusal')
 check(Row(menu,'enUS').checked==true and Row(menu,'enUS').text:find('active',1,true),'English is the active and saved choice')
 NexusPanel._menuBtn.scripts.OnEnter(NexusPanel._menuBtn);NexusPanel._menuBtn.scripts.OnLeave(NexusPanel._menuBtn)
 local status=Nexus.Panel.LanguageStatus()
 check(status.active=='enUS' and status.saved=='enUS' and status.pending==false and status.refusal==nil,'status: English active, nothing pending, changes available')
 check(writes.n==0 and F.Serialize(NexusDB.settings)==settings0 and Effects()==effects and #H.chat==chat0,'opening, hovering, closing and status reads write and print nothing')
 Row(menu,'enUS').func()
 check(writes.n==0 and F.Serialize(NexusDB.settings)==settings0,'choosing English while English is the default writes nothing')
 -- B. An explicit supported change writes only settings.uiLanguage; the
 -- active language stays until a reload.
 local settingsTable,before=NexusDB.settings,RootWithout()
 Row(menu,'frFR').func()
 check(writes.n==1 and NexusDB.settings==settingsTable and rawget(NexusDB.settings,'uiLanguage')=='frFR','one durable write through the Store owner sets frFR in the same settings table')
 check(RootWithout()==before,'nothing else changed: other and unknown settings, schema markers, rows, ledger, bundle')
 check(Effects()==effects,'no game action, Sync send, consent popup, assignment or client option change')
 status=Nexus.Panel.LanguageStatus()
 check(status.active=='enUS' and status.saved=='frFR' and status.pending==true,'status: English stays active, French is saved and pending')
 Expect('enUS','French chosen, before reload')
 menu=LanguageMenu()
 check(Row(menu,'frFR').checked==true and Row(menu,'frFR').text:find('reload',1,true) and Row(menu,'enUS').text:find('active',1,true) and menu.text:find('reload',1,true),'the menu shows the active and the pending choice')
 Row(menu,'frFR').func()
 check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='frFR','choosing the stored ID again is a no-op')
 check(Nexus.Localization.InitializeActiveLanguage('frFR')=='enUS','a second initialization does not switch the session')
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(3,.05)
 Expect('enUS','after another world entry')
 check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='frFR','world entry neither writes nor switches the language')
 -- C. The user-requested reload applies the saved choice; then each pack in turn.
 H=F.Reload();CountWriter()
 Expect('frFR','French after reload')
 status=Nexus.Panel.LanguageStatus()
 check(rawget(NexusDB.settings,'uiLanguage')=='frFR' and status.saved=='frFR' and status.pending==false and writes.n==0,'after reload: the saved choice is active, kept and not pending')
 for i=2,#IDS do
  Nexus.Panel.Show();menu=LanguageMenu()
  Row(menu,IDS[i]).func()
  check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')==IDS[i] and Nexus.Panel.LanguageStatus().pending==true,IDS[i]..' chosen and pending')
  Expect(IDS[i-1],IDS[i]..' chosen, before reload')
  H=F.Reload();CountWriter()
  Expect(IDS[i],IDS[i]..' after reload')
 end
 Nexus.Panel.Show();menu=LanguageMenu();Row(menu,'enUS').func()
 check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='enUS','an explicit English choice is saved')
 Expect('ruRU','English chosen, before reload')
 H=F.Reload();CountWriter()
 Expect('enUS','English after reload')
 -- D. An unsupported saved value is shown as English and kept as saved; an
 -- explicit English choice may replace it.
 for _,raw in ipairs({'xxXX','frfr',42})do
  NexusDB.settings.uiLanguage=raw
  H=F.Reload();CountWriter()
  Expect('enUS','unsupported saved value '..tostring(raw))
  Nexus.Panel.Show();menu=LanguageMenu();status=Nexus.Panel.LanguageStatus()
  check(rawget(NexusDB.settings,'uiLanguage')==raw and writes.n==0 and status.saved=='enUS' and status.pending==false and status.savedUnsupported==true,'unsupported '..tostring(raw)..': kept as saved, English shown, reads write nothing')
  check(MenuText(menu):find('English is shown',1,true) and Row(menu,'enUS').checked==true,'the menu says the saved value is not offered')
 end
 Row(menu,'enUS').func()
 check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='enUS','an explicit English choice replaces an unsupported saved value')
 -- E. A capacity-refused start-up keeps saved data unchanged: a valid saved
 -- choice is active, and a change is refused before the writer.
 do
  local db=F.Database({version=2})
  db.settings.uiLanguage='deDE';db.communityBuilds={}
  for i=1,2049 do db.communityBuilds['cap-'..i]={} end
  H=F.Boot(db);CountWriter()
  local s=Nexus.StartupStatus()
  check(s.coreReady==true and s.reason=='ROOT_SLOT_LIMIT','fixture: a capacity-refused start-up with local tools ready ('..tostring(s.reason)..')')
  Expect('deDE','capacity-refused session')
  local saved=F.Serialize(NexusDB)
  Nexus.Panel.Show();menu=LanguageMenu()
  check(Row(menu,'frFR').disabled==true and MenuText(menu):find('Changes unavailable',1,true),'capacity refusal: every choice is disabled with its reason')
  local r=Nexus.Panel.ChooseLanguage('frFR')
  check(r.state=='refused' and r.reason=='capacity' and writes.n==0 and F.Serialize(NexusDB)==saved,'capacity refusal: refused before the writer, root unchanged')
 end
 -- A settings replacement under the admitted root has not itself been
 -- admitted. Opening the real menu and clicking must preserve both tables.
 do
  H=F.Boot(F.Database({version=2}));CountWriter()
  local admitted=NexusDB.settings
  check(NexusDB.authorityBundle.storeData.settings==admitted,'fixture: original settings are admitted')
  NexusDB.settings={uiLanguage='enUS',unknown={keep=true}}
  local replacement=NexusDB.settings;local frozen=F.Serialize(NexusDB)
  Nexus.Panel.Show();menu=LanguageMenu()
  local r=Nexus.Panel.ChooseLanguage('frFR')
  check(Row(menu,'frFR').disabled==true and r.state=='refused' and r.reason=='drift' and writes.n==0,'replaced settings: disabled and refused before the writer')
  check(NexusDB.settings==replacement and NexusDB.authorityBundle.storeData.settings==admitted and F.Serialize(NexusDB)==frozen,'replaced settings: both identities and the whole root stay unchanged')
  NexusDB.settings=admitted
  r=Nexus.Panel.ChooseLanguage('frFR')
  check(r.state=='saved' and writes.n==1 and admitted.uiLanguage=='frFR','restoring the admitted settings permits a durable choice')
 end
 -- The real Store writer can return session if authority changes at its
 -- boundary. The real menu must keep the durable preference separate from
 -- that detached projection, including an earlier durable pending choice.
 for _,prior in ipairs({false,'frFR'})do
  H=F.Boot(F.Database({version=2}));CountWriter()
  Nexus.Panel.Show();menu=LanguageMenu()
  if prior then Row(menu,prior).func() end
  local saved=prior or 'enUS';local calls=writes.n
  local effects=Effects()
  local owner=Nexus.MainInternals.StoreAuthorityOwner;local original=owner.UpdateSettingsV1
  local mode,frozen
  owner.UpdateSettingsV1=function(key,value)
   NexusDB.settingsVersion=6 -- authority drift at the actual writer boundary
   frozen=F.Serialize(NexusDB)
   local result=original(key,value);mode=result and result.mode
   return result
  end
  menu=LanguageMenu();Row(menu,'ruRU').func()
  check(mode=='session' and writes.n==calls+1 and Nexus.Store.Settings().uiLanguage=='ruRU','fixture: actual writer changed the detached session projection')
  check(rawget(NexusDB.settings,'uiLanguage')==(prior or nil) and F.Serialize(NexusDB)==frozen and Effects()==effects,'session result: saved preference, whole root and game effects stay unchanged')
  local status=Nexus.Panel.LanguageStatus()
  check(status.saved==saved and status.pending==(prior~=false) and status.sessionOnly==true and status.active=='enUS','session result: status describes the durable choice, not the detached projection')
  menu=LanguageMenu()
  check(Row(menu,saved).checked==true and Row(menu,'ruRU').checked==false and not Row(menu,'ruRU').text:find('saved',1,true),'session result: reopening the real menu does not label the session choice saved')
  check(MenuText(menu):find('The last choice was not saved',1,true) and (not prior or Row(menu,prior).text:find('saved, applies after reload',1,true)),'session result: truthful notice preserves any earlier durable pending choice')
  check(writes.n==calls+1 and F.Serialize(NexusDB)==frozen,'session result: repeated status/menu reads invoke no writer')
  H=F.Reload();CountWriter()
  Expect(saved,'session choice discarded after reload')
  check(Nexus.Panel.LanguageStatus().pending==false and writes.n==0 and F.Serialize(NexusDB)==frozen,'reload: only the original saved choice survives, with no write')
 end
 -- F. Early start-up, authority drift and a Store the session was not initialized with.
 do
  local early
  H=F.Boot(F.Database({version=2}),nil,function()
   local owner=Nexus.MainInternals.StoreAuthorityOwner;local original,n=owner.UpdateSettingsV1,0
   owner.UpdateSettingsV1=function(...)n=n+1;return original(...)end
   local settings=F.Serialize(NexusDB.settings)
   local rows=Nexus.Panel.LanguageMenuItems(function(fn)return fn end)
   local result=Nexus.Panel.ChooseLanguage('frFR')
   early={menu={menuList=rows},result=result,writes=n,same=F.Serialize(NexusDB.settings)==settings}
   owner.UpdateSettingsV1=original
  end)
  check(early.menu and Row(early.menu,'frFR').disabled==true and MenuText(early.menu):find('Nexus is still starting',1,true),'early start-up: choices are shown disabled with the reason')
  check(early.result.state=='refused' and early.result.reason=='startup' and early.writes==0 and early.same,'early start-up: a choice is refused and nothing is written')
  Expect('enUS','after the early refusal')
  CountWriter()
  local internals=Nexus.MainInternals;local realOwner,foreign=internals.StoreAuthorityOwner,0
  internals.StoreAuthorityOwner={owner={},UpdateSettingsV1=function()foreign=foreign+1;return {mode='durable'}end}
  local r=Nexus.Panel.ChooseLanguage('frFR')
  internals.StoreAuthorityOwner=realOwner
  check(r.state=='refused' and r.reason=='authority' and foreign==0 and writes.n==0,'another Store owner: refused, its writer never called')
  local current=NexusDB;NexusDB=F.Database({version=2});local other=F.Serialize(NexusDB)
  r=Nexus.Panel.ChooseLanguage('frFR')
  check(r.state=='refused' and r.reason=='drift' and writes.n==0 and F.Serialize(NexusDB)==other,'a replaced saved root: refused, neither root written')
  NexusDB=current;NexusDB.settingsVersion=6
  local frozen=F.Serialize(NexusDB)
  Nexus.Panel.Show();menu=LanguageMenu()
  r=Nexus.Panel.ChooseLanguage('frFR')
  check(Row(menu,'frFR').disabled==true and r.state=='refused' and r.reason=='read-only' and writes.n==0 and F.Serialize(NexusDB)==frozen,'a root that became read-only: disabled, refused, unchanged')
  NexusDB.settingsVersion=2
  r=Nexus.Panel.ChooseLanguage('plPL')
  check(r.state=='saved' and r.pending==true and writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='plPL','control: with the authority current again the choice is saved and pending')
  local oldOwner=Nexus.MainInternals.StoreAuthorityOwner
  dofile('core/Store.lua')
  local freshOwner=Nexus.MainInternals.StoreAuthorityOwner;local freshWriter,freshCalls=freshOwner.UpdateSettingsV1,0
  freshOwner.UpdateSettingsV1=function(...)freshCalls=freshCalls+1;return freshWriter(...)end
  check(freshOwner~=oldOwner and freshOwner.owner==Nexus.Store,'fixture: a reloaded Store module with its own writer')
  r=Nexus.Panel.ChooseLanguage('ruRU')
  check(r.state=='refused' and r.reason=='authority' and freshCalls==0 and writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='plPL','the session Store cannot use another Store module\'s writer')
 end
end
print('PASS terminology actual consumer checks='..checks..'; native rendering not asserted')
