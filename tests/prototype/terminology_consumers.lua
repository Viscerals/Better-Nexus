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
print('PASS terminology actual consumer checks='..checks..'; native rendering not asserted')
