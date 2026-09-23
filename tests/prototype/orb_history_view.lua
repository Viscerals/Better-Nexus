-- The Orb history has to be readable without decoding a diagnostic sentence,
-- and it must never say more than the runtime recorded. Two layers are driven
-- here: the pure projection (Nexus.OrbHistory) against synthetic records, and
-- the real panel handlers against both synthetic records and one real run
-- through the real runtime with fake game services. No gameplay call, no
-- saved-data write and no ownership change may come from any log interaction.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function button(label,parent)
 for _,b in ipairs(H.frames)do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end
 end
 error('button not found: '..label)
end
local V=assert(Nexus.OrbHistory,'the projection module is loaded')

-- ---------------------------------------------------------------- projection
-- 1. Rarity comes from the addon's own Echo mapping, with the word always
-- present so colour is never the only cue, and an unlisted value stays unknown.
for quality,word in pairs({[0]='Common',[1]='Uncommon',[2]='Rare',[3]='Epic',[4]='Legendary'})do
 local rarity=V.Rarity(quality)
 check(rarity.label==word and rarity.known==true,'quality '..quality..' is '..word..': '..rarity.label)
 check(type(rarity.color)=='table' and #rarity.color==3,'quality '..quality..' has the addon colour')
end
check(V.Rarity(9).known==false and V.Rarity(9).label=='Unknown quality',
 'an unlisted quality stays explicitly unknown: '..V.Rarity(9).label)
check(V.Rarity(nil).known==false,'a missing quality stays explicitly unknown')
-- The Echo scale is its own: quality 2 is Rare here, not the WoW item colour
-- for 2, and no offset is applied anywhere in the mapping.
check(V.QUALITY_NAMES[2]=='Rare' and V.QUALITY_NAMES[4]=='Legendary',
 'the Echo quality scale is used directly, with no item-quality offset')
local id,quality=V.Identity('410002:2')
check(id==410002 and quality==2,'a recorded key is read, not guessed: '..tostring(id)..'/'..tostring(quality))
check(V.Identity('nonsense')==nil,'an unparsable key is not invented')

-- 2. Rows read recorded fields only.
local function view(entries,header)
 local run={sessionOnly=true,which='current',runId=7,startedAt=100,build='test',
  character='Tester-Realm',wishlist='Raid plan',limit=15,state='FINISHED',
  reason='Finished - limit reached',spent=15,reserved=0,revision=3,
  total=#entries,entries=entries,hasCurrent=true,hasPrevious=false}
 for k,v in pairs(header or {})do run[k]=v end
 return run
end
local confirmed={serial=1,ordinal=1,at=110,state='confirmed',sourceKey='410001:1',
 sourceName='Disposable A',sourceQuality=1,sourceCopies=3,
 offered={{spellId=410002,quality=2,name='Desired A'},{spellId=410003,quality=0,name='Disposable B'},
  {spellId=410004,quality=3,name='Desired B'}},
 selectedKey='410002:2',selectionKind='TARGET',selectionReason='needed target',
 obtained='410002:2',confirmedAt=115}
local fallback={serial=2,ordinal=2,at=120,state='confirmed',sourceKey='410005:0',
 sourceName='Protected low',sourceQuality=0,sourceCopies=1,recycle=true,
 offered={{spellId=410006,quality=3,name='Excess high'}},
 selectedKey='410006:3',selectionKind='RECYCLE',selectionReason='permitted recycle',
 obtained='410006:3'}
local pending={serial=3,ordinal=3,at=130,state='selected',sourceKey='410001:1',
 sourceName='Disposable A',sourceQuality=1,sourceCopies=2,
 offered={{spellId=410008,quality=1,name='Unsafe fallback'}},
 selectedKey='410008:1',selectionKind='TARGET',selectionReason='needed target'}
local refused={serial=4,ordinal=4,at=140,state='not sent',sourceKey='410003:0',
 sourceName='Disposable B',sourceQuality=0,
 reason='The receipt could not be saved; no Orb was requested.'}
local unknown={serial=5,ordinal=5,at=150,state='unknown',sourceKey='410007:2',
 sourceName='Permanent',sourceQuality=2,reason='The spend outcome remains unknown.'}
local bare={serial=6,ordinal=6,at=160,state='requested',sourceKey='999999:9'}
local rows=V.Rows(view({confirmed,fallback,pending,refused,unknown,bare}),nil)
check(#rows==6,'every recorded operation becomes one row: '..#rows)
check(rows[1].result.label=='Confirmed' and rows[1].result.confirmed==true,
 'a confirmed operation says Confirmed: '..rows[1].result.label)
check(rows[1].replacement.label=='Desired A' and rows[1].replacement.confirmed==true,
 'the confirmed replacement uses the recorded name: '..rows[1].replacement.label)
check(rows[1].replacement.rarity.label=='Rare','and its recorded rarity: '..rows[1].replacement.rarity.label)
check(rows[1].source.label=='Disposable A' and rows[1].source.rarity.label=='Uncommon',
 'the replaced Echo is named from the record: '..rows[1].source.label)
check(rows[1].reason.label=='Missing Wishlist target','a target choice says why: '..rows[1].reason.label)
check(rows[2].reason.label=='Reusable fallback','a recycle choice is a reusable fallback: '..rows[2].reason.label)
check(rows[2].reason.detail and rows[2].reason.detail:find('normal safety checks',1,true),
 'and it explains the rule instead of calling it an upgrade')
check(rows[2].reason.detail:find('upgrade',1,true)==nil
 and rows[2].reason.detail:find('wasted',1,true)==nil,
 'the fallback explanation claims neither an upgrade nor a wasted Orb')
-- A selected choice is not a received result.
check(rows[3].result.label=='Awaiting result' and rows[3].result.pending==true,
 'a selected but unconfirmed operation is pending: '..rows[3].result.label)
check(rows[3].replacement.proposed==true and rows[3].replacement.label:find('(proposed)',1,true),
 'and its replacement is labelled proposed: '..rows[3].replacement.label)
check(rows[3].replacement.confirmed~=true,'a proposed replacement is never marked confirmed')
check(rows[4].result.label=='Not sent' and rows[4].result.refused==true,
 'a refusal stays in the history: '..rows[4].result.label)
check(rows[4].replacement.label=='No replacement','and claims no replacement: '..rows[4].replacement.label)
check(rows[5].result.label=='Unconfirmed' and rows[5].result.unresolved==true,
 'an unknown outcome is unconfirmed, not a success: '..rows[5].result.label)
check(rows[6].reason.label=='Reason unavailable','an unrecorded reason says so: '..rows[6].reason.label)
check(rows[6].replacement.label=='Not recorded','and an unrecorded result says so: '..rows[6].replacement.label)
check(rows[6].source.label=='Unknown Echo (999999)',
 'an unresolvable name stays usable with its id: '..rows[6].source.label)
check(rows[6].source.rarity.label=='Unknown quality',
 'and an unlisted quality stays unknown: '..rows[6].source.rarity.label)

-- 3. Details show the actual recorded offers and nothing else.
local details=V.Details(confirmed,nil,100)
check(#details.offers==3,'the three actual offers are shown: '..#details.offers)
check(details.offers[1].selected==true and details.offers[1].confirmed==true,
 'the selected offer is marked, and it is the one that was received')
check(details.offers[2].selected==false and details.offers[3].selected==false,
 'the other offers are not marked as chosen')
check(details.eligibleSurplus==3,'the source event carries eligible surplus: '..tostring(details.eligibleSurplus))
check(details.sinceStart==10,'a relative time is used only when both ends were recorded: '..tostring(details.sinceStart))
check(details.toConfirm==5,'and the confirmation interval comes from two recorded stamps')
local noOffer=V.Details(refused,nil,100)
check(noOffer.offers==nil and noOffer.offersNote=='Offer not recorded',
 'a missing offer says so instead of being reconstructed: '..tostring(noOffer.offersNote))
check(V.Details(bare,nil,nil).sinceStart==nil,
 'one timestamp alone is never turned into a duration')

-- 4. The report carries the whole run in order, and only technical mode
-- exposes the identifiers.
local full=view({confirmed,fallback,pending,refused,unknown,bare})
local readable=V.Report(full,nil,false)
local technical=V.Report(full,nil,true)
for _,entry in ipairs(full.entries)do
 check(readable:find('\n'..entry.ordinal..'. ',1,true)~=nil,
  'the readable report contains operation '..entry.ordinal)
 check(technical:find('\n'..entry.ordinal..'. ',1,true)~=nil,
  'the technical report contains operation '..entry.ordinal)
end
check(readable:find('Confirmed.',1,true) and readable:find('Not sent.',1,true)
 and readable:find('Awaiting result.',1,true),
 'the readable report distinguishes confirmed, pending and not-sent operations')
check(readable:find('410002:2',1,true)==nil,'the readable report keeps raw keys out')
check(technical:find('410002:2',1,true)~=nil,'the technical report keeps the exact identity')
check(technical:find('eligible surplus=3',1,true)~=nil,
 'the technical report keeps the recorded surplus under its own name')
check(readable:find('copies used',1,true)==nil and technical:find('copies used',1,true)==nil,
 'eligible surplus is never presented as copies used')
check(readable:find('History clears on reload or logout',1,true)~=nil,
 'the report states that the history is session-only')
local empty=V.Report({sessionOnly=true,which='current'},nil,false)
check(empty:find('no run has been started',1,true)~=nil,'an empty history reports itself: '..empty)

-- --------------------------------------------------------------------- panel
-- 5. The real window renders a fixed row pool, pages correctly and never
-- creates one frame per recorded operation.
local function stub(total,build)
 local entries={}
 for index=1,total do
  entries[index]={serial=index,ordinal=index,at=100+index,state='confirmed',
   sourceKey='410001:1',sourceName='Disposable A',sourceQuality=1,sourceCopies=2,
   offered={{spellId=410002,quality=2,name='Desired A'},{spellId=410003,quality=0,name='Disposable B'},
    {spellId=410004,quality=3,name='Desired B'}},
   selectedKey='410002:2',selectionKind='TARGET',selectionReason='needed target',
   obtained='410002:2',confirmedAt=101+index}
 end
 return entries
end
local realRunLog=M.RunLog
local stubEntries,stubHeader=stub(15),{}
local function serveStub(which,from,count)
 if which=='previous' and not stubHeader.hasPrevious then
  return {sessionOnly=true,which='previous',hasCurrent=true,hasPrevious=false}
 end
 local all=which=='previous' and stubHeader.previousEntries or stubEntries
 local page={}
 local first=math.max(1,math.floor(tonumber(from) or 1))
 local last=count and math.min(#all,first+math.max(0,math.floor(count))-1) or #all
 for index=first,last do page[#page+1]=all[index] end
 local run=view(page,{which=which or 'current',total=#all,
  revision=stubHeader.revision or 3,
  hasPrevious=stubHeader.hasPrevious==true,runId=which=='previous' and 6 or 7})
 for k,v in pairs(stubHeader.fields or {})do run[k]=v end
 return run
end
M.RunLog=function(which,from,count) return serveStub(which,from,count) end
SlashCmdList.NEXUS('orbs')
local framesBefore=#H.frames
local log=Nexus.OrbPanel.ShowLog()
local framesFor15=#H.frames-framesBefore
check(log:IsShown(),'the history window opens')
check(#log.rows==8,'the row pool is fixed at eight rows: '..#log.rows)
check(log.page:GetText()=='Operations 1-8 of 15','the footer counts the whole run: '..log.page:GetText())
check(log.rows[1].source:GetText():find('Disposable A',1,true)~=nil,
 'the first row names the replaced Echo: '..log.rows[1].source:GetText())
check(log.rows[1].source:GetText():find('Uncommon',1,true)~=nil,
 'and states its rarity in words: '..log.rows[1].source:GetText())
check(log.rows[1].replacement:GetText():find('Desired A',1,true)~=nil,
 'and names the replacement: '..log.rows[1].replacement:GetText())
check(log.rows[1].result:GetText()=='Confirmed','and its result: '..log.rows[1].result:GetText())
check(log.rows[8]:IsShown() and log.rows[8].index:GetText()=='8.','eight rows are used on a full page')
check(not log.prev:IsEnabled(),'Previous is disabled on the first page')
check(log.next:IsEnabled(),'Next is enabled while pages remain')
button('Next',log):Click()
check(log.page:GetText()=='Operations 9-15 of 15','the second page continues the same run: '..log.page:GetText())
check(log.rows[7]:IsShown() and not log.rows[8]:IsShown(),'a short last page hides the unused rows')
check(not log.next:IsEnabled(),'Next is disabled on the last page')
check(log.prev:IsEnabled(),'Previous is enabled after the first page')
button('Previous',log):Click()
check(log.page:GetText()=='Operations 1-8 of 15','Previous returns to the first page')

-- A much larger history must not add frames.
stubEntries=stub(400)
button('Next',log):Click();button('Previous',log):Click()
check(log.page:GetText()=='Operations 1-8 of 400','a large history still pages eight at a time: '..log.page:GetText())
check(#H.frames-framesBefore==framesFor15,
 'four hundred operations allocate no extra frame: '..(#H.frames-framesBefore)..' vs '..framesFor15)

-- 6. Selecting a row opens its details, and paging clears them.
stubEntries=stub(15)
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.details:GetText():find('Select an operation',1,true)~=nil,
 'nothing is selected at first: '..log.details:GetText())
log.rows[2]:Click()
check(log.rows[2].highlight:IsShown(),'the selected row is highlighted')
local detailText=log.details:GetText()
check(detailText:find('Operation 2',1,true)~=nil,'the details name the operation: '..detailText)
check(detailText:find('Desired A',1,true) and detailText:find('Disposable B',1,true)
 and detailText:find('Desired B',1,true),'the details list the three recorded offers')
check(detailText:find('[received]',1,true)~=nil,
 'and mark the offer that was actually received: '..detailText)
check(detailText:find('Eligible surplus at selection',1,true)~=nil,
 'the details use the recorded surplus under its own name')
check(detailText:find('copies used',1,true)==nil,'and never call it copies used')
log.rows[3]:Click()
check(log.details:GetText():find('Operation 3',1,true)~=nil,'another row replaces the open details')
log.rows[3]:Click()
check(not log.rows[3].highlight:IsShown(),'clicking the open row again closes its details')
check(log.details:GetText():find('Select an operation',1,true)~=nil,
 'and the details area returns to its prompt: '..log.details:GetText())
log.rows[3]:Click()
check(not log.rows[2].highlight:IsShown() and log.rows[3].highlight:IsShown(),
 'only one operation is open at a time')
button('Next',log):Click()
check(log.details:GetText():find('Select an operation',1,true)~=nil,
 'changing page leaves no stale details: '..log.details:GetText())
for _,row in ipairs(log.rows)do check(not row.highlight:IsShown(),'and no stale highlight') end
button('Previous',log):Click()

-- 7. Run selection, empty history and disabled controls.
check(not log.current:IsEnabled(),'the current run is already shown, so its button is disabled')
check(not log.previous:IsEnabled(),'previous is disabled while no previous run exists')
stubHeader.hasPrevious=true;stubHeader.previousEntries=stub(3)
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.previous:IsEnabled(),'previous becomes available once a previous run exists')
button('Previous run',log):Click()
check(log.page:GetText()=='Operations 1-3 of 3','the previous run has its own operations: '..log.page:GetText())
check(log.header:GetText():find('Run 6',1,true)~=nil,'and its own run number: '..log.header:GetText())
check(log.current:IsEnabled() and not log.previous:IsEnabled(),'the selector states which run is shown')
button('Current run',log):Click()
check(log.header:GetText():find('Run 7',1,true)~=nil,'the current run comes back: '..log.header:GetText())
stubEntries={}
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.page:GetText()=='No operations recorded','an empty history says so: '..log.page:GetText())
check(not log.prev:IsEnabled() and not log.next:IsEnabled(),'and offers no paging')
stubEntries=stub(15)

-- 8. A long name and a pending result stay readable and honest on screen.
stubEntries[1].sourceName=string.rep('Extremely Long Echo Name ',8)
stubEntries[2].obtained=nil;stubEntries[2].state='selected'
stubEntries[3].state='not sent';stubEntries[3].obtained=nil;stubEntries[3].selectedKey=nil
stubEntries[3].reason='The adapter refused the request.'
stubEntries[4].sourceName=nil;stubEntries[4].sourceKey='777777:1'
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(#log.rows[1].source:GetText()<=60,'a long name is shortened for its cell: '..#log.rows[1].source:GetText())
check(log.rows[1].source:GetText():find('...',1,true)~=nil,
 'and says that it was shortened: '..log.rows[1].source:GetText())
check(log.rows[1].source:GetText():find('Extremely Long',1,true)~=nil,
 'while still showing the start of the recorded name')
log.rows[1]:GetScript('OnEnter')(log.rows[1])
check(log.rows[1].full:find('Extremely Long Echo Name Extremely',1,true)~=nil,
 'the whole recorded name stays available on hover: '..log.rows[1].full)
log.rows[1]:GetScript('OnLeave')(log.rows[1])
check(log.rows[2].result:GetText()=='Awaiting result','a pending row says so: '..log.rows[2].result:GetText())
check(log.rows[2].replacement:GetText():find('proposed',1,true)~=nil,
 'and marks its replacement as proposed: '..log.rows[2].replacement:GetText())
check(log.rows[3].result:GetText()=='Not sent','a refusal is visible: '..log.rows[3].result:GetText())
check(log.rows[4].source:GetText():find('Unknown Echo (777777)',1,true)~=nil,
 'an unresolvable name keeps its id: '..log.rows[4].source:GetText())
-- A selected choice that was never confirmed is marked selected, not received.
log.rows[2]:Click()
local pendingDetail=log.details:GetText()
check(pendingDetail:find('[selected]',1,true)~=nil,
 'a pending operation marks the selected offer: '..pendingDetail)
check(pendingDetail:find('[received]',1,true)==nil,
 'and claims nothing was received')
check(pendingDetail:find('Proposed source',1,true)~=nil,
 'and calls its source proposed, not consumed: '..pendingDetail)
log.rows[2]:Click()

-- 9. Copy report opens its own multiline view with the whole run.
local copyButton=button('Copy report',log)
copyButton:Click()
local copyView=assert(NexusOrbHistoryCopy,'Copy report opens its own view')
check(copyView:IsShown(),'the copy view opens')
check(copyView.editBox:GetMaxLetters()==0,'its field has no letter limit: '..tostring(copyView.editBox:GetMaxLetters()))
local copied=copyView.editBox:GetText()
check(#copied>500,'the whole run is offered for copying: '..#copied..' characters')
for index=1,15 do
 check(copied:find('\n'..index..'. ',1,true)~=nil,'the copied report contains operation '..index)
end
check(copied:find('Awaiting result.',1,true) and copied:find('Not sent.',1,true)
 and copied:find('Confirmed.',1,true),'and distinguishes pending, not-sent and confirmed')
check(copied:find('410002:2',1,true)==nil,'the readable report keeps raw keys out')
-- This client answers 1 or nil, never a boolean, so the handler must not
-- compare with true.
copyView.check.GetChecked=function(self) return self.checked and 1 or nil end
copyView.check:SetChecked(true);copyView.check:GetScript('OnClick')(copyView.check)
local technicalCopy=copyView.editBox:GetText()
check(technicalCopy:find('410002:2',1,true)~=nil,'technical mode exposes the exact identity')
check(technicalCopy:find('state=',1,true)~=nil,'and the recorded state fields')
check(#technicalCopy>#copied,'technical mode adds to the report instead of replacing it')
check(technicalCopy:find('\n15. ',1,true)~=nil,'and still ends with the last operation')
copyView.editBox:SetFocus()
check(copyView.editBox:HasFocus(),'the copy field can take focus for selection')
copyView.editBox:GetScript('OnEscapePressed')(copyView.editBox)
check(not copyView.editBox:HasFocus(),'Escape releases the keyboard')
copyView.editBox:SetFocus()
button('Clear focus',copyView):Click()
check(not copyView.editBox:HasFocus(),'Clear focus releases the keyboard')
button('Close',copyView):Click();check(not copyView:IsShown(),'the copy view closes')

-- 9a. An unsettled run warns about its unresolved operation, and the window
-- carries no gameplay control at all.
stubHeader.fields={reserved=1,state='PAUSED',spent=14}
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.warning:GetText():find('unresolved operation',1,true)~=nil,
 'an unresolved operation is stated in the header: '..log.warning:GetText())
check(log.header:GetText():find('Orbs used: 14 / 15',1,true)~=nil,
 'and the usage is the one the run recorded: '..log.header:GetText())
stubHeader.fields=nil
for _,forbidden in ipairs({'Start','Resume','Stop','Retry','Reroll','Pause','Start new run'})do
 local found=false
 for _,b in ipairs(H.frames)do
  if b.kind=='Button' and b:GetParent()==log and b:GetText()==forbidden then found=true end
 end
 check(not found,'the history window offers no '..forbidden..' control')
end

-- 9b. A partial history says so, new operations are announced instead of
-- moving the reader, and a hidden window does no work at all.
stubHeader.fields={truncated=true}
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.warning:GetText():find('reached its bound',1,true)~=nil,
 'a truncated history is stated, not hidden: '..log.warning:GetText())
check(log.page:GetText():find('bound',1,true)~=nil,
 'and the page line carries the bound too: '..log.page:GetText())
-- An unresolved operation must not hide the fact that recording stopped.
stubHeader.fields={truncated=true,reserved=1,state='PAUSED',spent=14}
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.warning:GetText():find('unresolved operation',1,true)~=nil
 and log.warning:GetText():find('reached its bound',1,true)~=nil,
 'an unsettled AND truncated run states both: '..log.warning:GetText())
stubHeader.fields=nil
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.note:GetText()=='History clears on reload or logout.',
 'the session-only note is visible: '..log.note:GetText())
stubEntries=stub(20)
log:GetScript('OnUpdate')(log,1)
check(log.page:GetText():find('Operations 1-8 of',1,true)==1,
 'new entries do not move the page the player is reading: '..log.page:GetText())
check(log.page:GetText():find(' of 20',1,true)~=nil,
 'while the total does show the new operations: '..log.page:GetText())
check(log.note:GetText():find('new operation',1,true)~=nil,
 'they are announced instead: '..log.note:GetText())
log:Hide()
stubEntries=stub(40)
log:GetScript('OnUpdate')(log,1)
check(log.page:GetText():find(' of 20',1,true)~=nil,
 'a hidden window renders nothing: '..log.page:GetText())
log=Nexus.OrbPanel.ShowLog()
check(log.page:GetText():find(' of 40',1,true)~=nil,
 'reopening reads the history again: '..log.page:GetText())
-- A recorded change at constant total must reach an open window: the runtime
-- moves its revision on every event, and the view keys on it.
stubEntries=stub(15)
stubHeader.revision=10
log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.rows[1].result:GetText()=='Confirmed','the first row starts confirmed')
button('Copy report',log):Click()
local staleCopy=NexusOrbHistoryCopy.editBox:GetText()
button('Close',NexusOrbHistoryCopy):Click()
stubEntries[1].state='selected';stubEntries[1].obtained=nil
stubHeader.revision=11
log:GetScript('OnUpdate')(log,1)
check(log.rows[1].result:GetText()=='Awaiting result',
 'the open window follows a recorded change at constant total: '..log.rows[1].result:GetText())
button('Copy report',log):Click()
check(NexusOrbHistoryCopy.editBox:GetText()~=staleCopy,
 'and the copied report is rebuilt instead of served stale')
button('Close',NexusOrbHistoryCopy):Click()
stubEntries=stub(15);stubHeader.revision=12
log:GetScript('OnUpdate')(log,1)

-- Only the visible page is read while the window refreshes.
local reads={}
local serve=M.RunLog
M.RunLog=function(which,from,count) reads[#reads+1]=count;return serve(which,from,count) end
log:Hide();log=Nexus.OrbPanel.ShowLog()
log:GetScript('OnUpdate')(log,1)
M.RunLog=serve
check(#reads>0,'the window did read the history')
for _,count in ipairs(reads)do
 check(count~=nil and count<=8,'every refresh read is bounded to the visible page: '..tostring(count))
end
stubEntries=stub(15)

-- 10. No log interaction may touch the run, the profile or ownership.
M.RunLog=realRunLog
log:Hide()
local spendsBefore=H.Count('orb-spend')
local statusBefore=M.Status()
local profileBefore=NexusDB and NexusDB.orbRunLog
log=Nexus.OrbPanel.ShowLog()
log.rows[1]:Click();button('Next',log):Click();button('Previous',log):Click()
button('Copy report',log):Click()
if NexusOrbHistoryCopy then button('Close',NexusOrbHistoryCopy):Click() end
button('Current run',log):Click()
local statusAfter=M.Status()
check(H.Count('orb-spend')==spendsBefore,'no Orb was spent by reading the history')
check(statusAfter.spent==statusBefore.spent and statusAfter.reserved==statusBefore.reserved,
 'no counter moved: '..statusAfter.spent..'/'..statusAfter.reserved)
check(statusAfter.state==statusBefore.state,'the run state is unchanged: '..tostring(statusAfter.state))
check((NexusDB and NexusDB.orbRunLog)==profileBefore,'no history was written to saved data')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Automation stays off')
log:Hide()

-- 11. One real run through the real runtime: the rows describe what actually
-- happened, and the details carry the offers the fake service really made.
H.OrbPlan({{spellId=410002,quality=2,stacks=4}})
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,4 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=10
H.Notify();A.Poll()
H.Approve(3,false,false)
for step=1,3 do
 for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
 check(M.Status().state=='WAIT_OFFER','step '..step..': the run requested its own Orb')
 H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410002,2)
end
log=Nexus.OrbPanel.ShowLog()
check(log.page:GetText()=='Operations 1-3 of 3','the real run records three operations: '..log.page:GetText())
check(log.rows[1].result:GetText()=='Confirmed','the first real operation is confirmed: '..log.rows[1].result:GetText())
check(log.rows[1].source:GetText():find('Disposable',1,true)~=nil,
 'the replaced Echo is the source the runtime recorded: '..log.rows[1].source:GetText())
check(log.rows[1].replacement:GetText():find('Desired A',1,true)~=nil,
 'and the replacement is the confirmed result: '..log.rows[1].replacement:GetText())
check(log.rows[1].reason:GetText()=='Missing Wishlist target',
 'with the reason the policy recorded: '..log.rows[1].reason:GetText())
log.rows[1]:Click()
local realDetails=log.details:GetText()
check(realDetails:find('Desired A',1,true) and realDetails:find('Unsafe fallback',1,true),
 'the details list the offers the service actually made: '..realDetails)
check(realDetails:find('[received]',1,true)~=nil,'and mark the one that was received')
check(realDetails:find('Eligible surplus at selection',1,true)~=nil,
 'and state the recorded surplus for that operation')
log:Hide()
check(M.Status().spent==3,'the real run still shows its own usage: '..M.Status().spent)
print('PASS orb_history_view: a readable Orb history that says only what the runtime recorded checks='..checks)
