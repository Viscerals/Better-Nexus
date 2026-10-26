-- Real normal consumers. Only input data and game/UI surfaces are synthetic.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2;H.Boot()
local A=Nexus.GameAdapter;local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local V=dofile('tests/prototype/view_regression_support.lua')
local observer
local function quiet(label,fn,...)
 observer=observer or V.PresentationObserver(H)
 return observer.Quiet(label,fn,...)
end

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
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
 check(texts():find(case[2],1,true),'actual recommendation consumer: '..case[1])
 check(model.recommendation==case[1],'raw producer remains unchanged')
 check(Nexus.Panel._lastModel.status:find(case[2],1,true),'normal status model maps same producer')
end
for _,annotation in ipairs({'banked','returns later'})do
 local model=H.Clone(Nexus.Panel._lastModel)
 model.cards={{text=Nexus.Readout.CardLine({name='Echo',quality=1,isGuaranteed=true},annotation,12)}}
 model.recommendation='Take'
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
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
 check(quiet('earlier #123 Text',L.Text,case[2])==english,'seam English base: '..case[2])
 local model=H.Clone(Nexus.Panel._lastModel);model.status=code;model.recommendation=code
 local pristine=H.Clone(model)
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
 check(same(model,pristine),'Render leaves the raw model and reason untouched: '..code)
 check(Nexus.Panel._lastModel.status==english and Nexus.Panel._lastModel.recommendation==english,'committed panel model has the exact English: '..code)
 check(texts():find(english,1,true) and not texts():find(code,1,true),'actual panel fontstring shows the English, not the code: '..code)
 local again=H.Clone(Nexus.Panel._lastModel);assert(quiet('earlier #123 copied Render',Nexus.Panel.Render,again))
 check(Nexus.Panel._lastModel.status==english and Nexus.Panel._lastModel.recommendation==english,'rendering converted text again is stable: '..code)
 -- Arrange a distinct legitimate status through Render, never SetStatus.
 local distinct=H.Clone(Nexus.Panel._lastModel)
 distinct.status=code=='ROOT_MUTATION_PENDING' and 'STORE_PENDING' or 'ROOT_MUTATION_PENDING'
 local prior=code=='ROOT_MUTATION_PENDING' and 'Reading your saved data' or 'Saving is still in progress; wait for its final result'
 assert(quiet('earlier #123 distinct Render',Nexus.Panel.Render,distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP Render stores a distinct status before SetStatus: '..code)
 -- The raw status-only update (status-only update) shares this guard: the
 -- same call and the same exact-English predicate, plus its true return.
 check(quiet('earlier #123 raw status',Nexus.Panel.SetStatus,code)==true and Nexus.Panel._lastModel.status==english,'GUARD raw SetStatus updates to exact English (status-only update): '..code)
 check(quiet('earlier #123 repeated raw status',Nexus.Panel.SetStatus,code)==false and Nexus.Panel._lastModel.status==english,'GUARD repeated SetStatus reports no update: '..code)
 quiet('earlier #123 English SetStatus',Nexus.Panel.SetStatus,Nexus.UserText.Message(code));check(Nexus.Panel._lastModel.status==english,'reviewed English passed back to SetStatus stays exact: '..code)
 assert(quiet('earlier #123 independent distinct Render',Nexus.Panel.Render,distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP independent Render before onStatus double conversion: '..code)
 check(quiet('earlier #123 onStatus double conversion',Nexus.Panel.SetStatus,Nexus.UserText.Message(code))==true and Nexus.Panel._lastModel.status==english,'GUARD onStatus double conversion updates exact English: '..code)
 check(quiet('earlier #123 Readout status',Nexus.Readout.Status,{text=code})==english and quiet('earlier #123 leveled Readout status',Nexus.Readout.Status,{text=code,level=12})=='Lv 12 - '..english,'Readout status line: '..code)
 check(quiet('earlier #123 Auto hold text',Nexus.Readout.AutoHoldText,code)==english and quiet('earlier #123 Auto hold note',Nexus.Readout.AutoHoldNote,code):find('Paused: '..english,1,true),'Readout Auto hold line: '..code)
end
check(L.Resolve('reason.list_preparing',{['reason.list_preparing']='Fixture list text'})=='Fixture list text','fixture candidate resolves only when injected')
local plain=H.Clone(Nexus.Panel._lastModel);plain.status='CURSOR_REQUIRED';plain.recommendation='CURSOR_REQUIRED'
assert(quiet('earlier #123 raw plain Render',Nexus.Panel.Render,plain))
check(texts():find('This list is still being prepared',1,true) and not texts():find('Fixture list text',1,true),'the panel never selects an injected candidate')
check(L.Diagnostics().misses==before.misses,'the normal consumer path records no fallback')
check(#H.actions==before.actions and #H.sent==before.sent and H.popup==before.popup and #H.chat==before.chat,'synchronous consumers cause no observed game action, Sync send, StaticPopup or chat')
check(Nexus.RecomputeStats().autoEnabled==before.auto and same(Nexus.Store.Settings(),settings0),'Automation selection and settings unchanged')
check(same(Nexus.Store.State(),state0),'GUARD full detached state preserves assigned Wishlists and related identities')
check(warning.IsOpen() and NexusOverwriteWarning:IsShown() and accepted==0,'GUARD actual pending consent remains open/visible and unaccepted')
check(not warning.CancelAuto({}) and warning.IsOpen() and NexusOverwriteWarning:IsShown(),'GUARD pending consent still belongs to original owner')
check(warning.CancelAuto(warningOwner) and not warning.IsOpen() and not NexusOverwriteWarning:IsShown() and accepted==0,'GUARD original owner can cancel the unchanged warning')
NexusDB.overwriteWarnings.auto=savedAutoWarning
-- Issue #142 first cohort: the two planner wait reasons from the real
-- EchoWeaver planner and the real runtime (onStatus -> Panel.SetStatus, and
-- the recommendation through Panel.Render), with repeated normalization. The
-- raw producer bytes and the zero/unavailable horizon contract are unchanged.
do
 local W3,WP='Waiting for the next three Echo choices','waiting for pending-pick count'
 local EW=assert(Nexus.EchoWeaver)
 local plan={advisorOnly=false,requestedCounts={[200001]=1}}
 local owned={synced=true,bySpell={}}
 local two={cards={{spellId=200001,quality=1},{spellId=200020,quality=0}}}
 local three={cards={{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}}}
 local function decide(board,horizon)return EW.DecideNexus({plan=plan,owned=owned,board=board,horizon=horizon,level=40})end
 local r=decide(two,5)
 check(r.type=='wait' and r.reason=='waiting for three-card board' and r.planner=='echoweaver','planner: the raw three-card wait')
 for _,h in ipairs({1.5,-1,'3'})do
  r=decide(three,h)
  check(r.type=='wait' and r.reason=='waiting for pending-pick count','planner: the raw pending-pick wait for horizon '..tostring(h))
 end
 r=decide(three,nil)
 check(r.type=='wait' and r.reason=='waiting for pending-pick count','planner: an unavailable horizon is a wait, never a zero')
 r=decide(three,0)
 check(r.reason~='waiting for pending-pick count','planner: a zero horizon stays a valid count')
 local acted,auto=#H.actions,Nexus.RecomputeStats().autoEnabled
 -- Snapshot only the named modeled effect classes. The observer captures
 -- live admissions without calling the diagnostic Sync.Stats inside a step.
 local effects=observer.Snapshot
 local unchanged=V.Same
 local instrument=observer.Instrument
 -- A real poll-driven runtime wait. H.Advance also runs unrelated existing
 -- work (Sync session and transport, scheduler, catalog checks) that may
 -- legitimately send or print, so the whole window is held only to no game
 -- action, Auto selection or settings change (Auto is OFF); each
 -- presentation call the runtime makes inside it is enclosed. The matched
 -- control below holds a whole producer step to no side effect.
 local pending=H.service.GetPendingRollsCount
 local function runtimeWait(cards,noCount)
  local whole,log=effects(),instrument()
  if noCount then H.service.GetPendingRollsCount=function()return nil end end
  H.Board(cards);H.Notify();H.Advance(.6)
  H.service.GetPendingRollsCount=pending
  log.restore()
  local after=effects()
  check(whole.actions==after.actions and whole.auto==after.auto and same(whole.settings,after.settings),'runtime wait: no game action, Auto selection or settings change')
  check(log.calls>0 and log.loud==0 and log.errors==0,'runtime wait: every presentation call the real runtime made was quiet')
  return log
 end
 local raws,message={},Nexus.UserText.Message
 Nexus.UserText.Message=function(value,...)raws[tostring(value)]=true;return message(value,...)end
 runtimeWait({{spellId=200001,quality=1},{spellId=200020,quality=0}})
 local m3,shown3=H.Clone(Nexus.Panel._lastModel),texts()
 runtimeWait({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200022,quality=1}},true)
 Nexus.UserText.Message=message
 check(raws['waiting: waiting for three-card board'] and raws['waiting: waiting for pending-pick count'],'message hook: raw wait status appears during conversion')
 check(raws['waiting for three-card board'] and raws['waiting for pending-pick count'],'message hook: raw planner reason appears, including prefix recursion')
 check(m3.status==W3 and m3.recommendation==W3 and shown3:find(W3,1,true) and not shown3:find('three-card',1,true),'runtime: the three-card wait reaches the panel model and fontstrings in English')
 check(Nexus.Panel._lastModel.status==WP and Nexus.Panel._lastModel.recommendation==WP and texts():find(WP,1,true),'runtime: an unavailable horizon waits; the pending-pick text keeps its exact lower-case bytes')
 check(#H.actions==acted and Nexus.RecomputeStats().autoEnabled==auto,'runtime: a wait performs nothing and leaves Automation as it was')
 local again=H.Clone(Nexus.Panel._lastModel);assert(quiet('re-render of the converted model',Nexus.Panel.Render,again))
 check(Nexus.Panel._lastModel.status==WP and Nexus.Panel._lastModel.recommendation==WP,'rendering the converted model again is stable')
 quiet('hide',Nexus.Panel.Hide);quiet('reopen',Nexus.Panel.Show)
 check(texts():find(WP,1,true) and not texts():find('waiting: ',1,true),'reopen: the same text and no prefix accumulation')
 local prior=H.Clone(Nexus.Panel._lastModel);prior.status='ROOT_MUTATION_PENDING';assert(quiet('render of a distinct previous status',Nexus.Panel.Render,prior))
 check(Nexus.Panel._lastModel.status=='Saving is still in progress; wait for its final result','a distinct previous status is committed by a real render')
 check(quiet('status-only update from the raw three-card wait',Nexus.Panel.SetStatus,'waiting: waiting for three-card board')==true and Nexus.Panel._lastModel.status==W3,'SetStatus from the raw three-card wait replaces the distinct status')
 check(quiet('status-only update from the raw pending-pick wait',Nexus.Panel.SetStatus,'waiting: waiting for pending-pick count')==true and Nexus.Panel._lastModel.status==WP,'SetStatus presents the raw pending-pick wait, the runtime onStatus input, once')
 check(quiet('status-only update with the equal converted status',Nexus.Panel.SetStatus,WP)==false and Nexus.Panel._lastModel.status==WP,'an equal converted status is a stable no-op')
 check(Nexus.UserText.Message('pending-pick count')=='Waiting for the remaining-choice count' and Nexus.UserText.Message(WP)==WP,'the older pending-pick mapping stays distinct')
 -- INJECTION EVIDENCE only: a test wrapper passes a non-shipped fixture pack
 -- into the real Text; this is not active-language startup or chooser evidence.
 local seam=Nexus.Localization
 local function inject(pack)
  local wrap={};for key,value in pairs(seam)do wrap[key]=value end
  wrap.Text=function(key)return seam.Text(key,pack)end
  Nexus.Localization=wrap
 end
 -- Valid candidate texts holding bytes a legacy rewrite matches (ARMED,
 -- TARGET:), braces, percent bytes and UTF-8. The pack is complete: every
 -- other reviewed key holds its exact English, including the save status of
 -- the distinct-status step below, so no fallback is expected in this block.
 local C3='ARMED fixture wait {3} 100% %% Caf\195\169'
 local CP='TARGET: fixture count {n} %d \226\128\148 encore'
 local SAVE='Saving is still in progress; wait for its final result'
 local complete={['reason.wait_three_choices']=C3,['reason.wait_pending_pick_count']=CP,
  ['reason.save_in_progress']=SAVE,['reason.list_preparing']='This list is still being prepared',
  ['reason.saved_data_reading']='Reading your saved data',
  ['panel.button.my_builds']='My Builds',
  ['panel.tooltip.open_my_builds']='Open My Builds',
  ['panel.tooltip.my_builds_destination']='Open the server My Builds page. Choosing a different Saved Build there changes the active loadout.',
  ['panel.button.assign_wishlist']='Assign Wishlist',
  ['panel.tooltip.assignment_heading']='Assign Wishlist',
  ['panel.tooltip.assignment_chooser']='Opens the Echo Journal with its Wishlist chooser for this loadout. Nothing is assigned until you choose a Wishlist there.',
  ['panel.button.create_wishlist']='Create Wishlist',
  ['panel.tooltip.create_wishlist_heading']='Import or create a wishlist',
  ['panel.tooltip.create_wishlist_source']='Paste a wishlist string or build one directly in Nexus.',
  ['panel.tooltip.create_wishlist_draft']='This opens the Wishlist editor with a draft. Nothing is saved or assigned until you press Create & assign or Create unassigned there.',
  ['panel.heading.locked_targets']='LOCKED TARGETS',
  ['panel.tooltip.locked_remaining']='Locked targets remaining',
  ['panel.tooltip.locked_plan']='These targets are planned for your locked Echo slots (a plan designs at most six target copies).',
  ['panel.tooltip.locked_acquire']='Acquire the exact requested Echo and quality first.',
  ['panel.tooltip.locked_placement']='Owned copies still need to be placed in locked Echo slots.',
  ['panel.tooltip.locked_not_freeze']='Current locked Echo slots and card Freeze are separate.',
  ['panel.tooltip.locked_acquire_list']='Still need to acquire:',
  ['panel.tooltip.open_wishlist_editor']='Click to open Wishlist Editor',
  ['panel.heading.progress']='PROGRESS',
  ['panel.heading.still_needed']='STILL NEEDED',
  ['panel.heading.extra_copies']='EXTRA COPIES'}
 local function exact(text,label)
  local m,shown=Nexus.Panel._lastModel,texts()
  check(m.status==text and m.recommendation==text and shown:find(text,1,true)~=nil,label)
  local menu=assert(NexusPanel._menuBtn)
  local lines,ok=quiet('exact runtime menu hover',V.TooltipLines,assert(menu:GetScript('OnEnter')),menu)
  local found=false;for _,line in ipairs(lines)do if line=='Status: '..text then found=true end end
  check(ok and found,label..' (actual menu Status line)')
  check(not shown:find('Guaranteed current offer',1,true) and not shown:find('WISHLIST:',1,true)
   and not shown:find('waiting: ',1,true),label..' (no legacy rewrite, no prefix)')
 end
 local fx={actions=#H.actions,auto=Nexus.RecomputeStats().autoEnabled,diag=L.Diagnostics()}
 inject(complete)
 -- The real runtime: the raw planner reason reaches Panel.Render as the
 -- recommendation and, through onStatus, Panel.SetStatus as the status line.
 local received=runtimeWait({{spellId=200001,quality=1},{spellId=200023,quality=0}})
 local rendered=received.render[#received.render]
 check(received.status[#received.status]=='waiting: waiting for three-card board','the runtime onStatus hands Panel its raw status line; Panel presents it')
 check(rendered~=nil and rendered.recommendation=='waiting for three-card board','the runtime hands Panel.Render the raw planner reason as its recommendation')
 exact(C3,'INJECTION: the runtime three-card wait shows exactly the candidate bytes')
 local copy=H.Clone(Nexus.Panel._lastModel);local pristine=H.Clone(copy)
 assert(quiet('INJECTION: render of a copied presented model',Nexus.Panel.Render,copy))
 assert(quiet('INJECTION: render of the committed model',Nexus.Panel.Render,Nexus.Panel._lastModel))
 check(same(copy,pristine),'Render leaves a copied presented model untouched')
 exact(C3,'INJECTION: a copied presented model and the committed model render again unchanged')
 check(quiet('INJECTION: the real HUD refresh',Nexus.RefreshHudView)==true,'the real HUD refresh renders its raw input again')
 exact(C3,'INJECTION: the HUD refresh presents its raw input once')
 quiet('INJECTION: hide',Nexus.Panel.Hide);quiet('INJECTION: reopen',Nexus.Panel.Show)
 exact(C3,'INJECTION: hide and reopen keep the exact bytes')
 runtimeWait({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200024,quality=1}},true)
 exact(CP,'INJECTION: the runtime pending-pick wait shows exactly the candidate bytes')
 copy=H.Clone(Nexus.Panel._lastModel);assert(quiet('INJECTION: render of a copied pending-pick model',Nexus.Panel.Render,copy))
 exact(CP,'INJECTION: the pending-pick candidate survives a copied-model render')
 runtimeWait({{spellId=200001,quality=1},{spellId=200025,quality=0}})
 exact(C3,'INJECTION: the three-card wait again, without prefix accumulation')
 check(#H.actions==fx.actions and Nexus.RecomputeStats().autoEnabled==fx.auto,'the waits performed nothing and left Automation as it was')
 check(quiet('INJECTION: status-only update with a distinct status',Nexus.Panel.SetStatus,'ROOT_MUTATION_PENDING')==true and Nexus.Panel._lastModel.status==SAVE,'a distinct status from the complete pack')
 check(quiet('INJECTION: status-only update from the raw wait',Nexus.Panel.SetStatus,'waiting: waiting for three-card board')==true and Nexus.Panel._lastModel.status==C3,'SetStatus presents the raw wait status once')
 local legacy=H.Clone(Nexus.Panel._lastModel);legacy.status='TARGET: fixture';legacy.recommendation='MISSING_REVIEW_CODE'
 assert(quiet('INJECTION: render of a raw legacy reason',Nexus.Panel.Render,legacy));copy=H.Clone(Nexus.Panel._lastModel)
 assert(quiet('INJECTION: render of the copied legacy model',Nexus.Panel.Render,copy))
 check(Nexus.Panel._lastModel.status=='WISHLIST: fixture'
  and Nexus.Panel._lastModel.recommendation=='This action is not available yet. Check the status or diagnostics. Details: MISSING_REVIEW_CODE',
  'a raw legacy reason gets its reviewed mapping once; a raw unsupported code keeps its detail')
 -- Matched producer control. Nexus.RefreshPanel runs one explicit real
 -- automation step (the planner, Main's render and the onStatus path)
 -- synchronously, outside the update loop: no time advances outside the update loop; its legitimate logging/maintenance is allowed. A whole explicit producer step is compared in the
 -- listed effect classes. The same steps run twice with the same runtime state, inputs
 -- and time: with the shipped English seam, then with the injected candidate
 -- pack. A first take step brings the runtime status, the logged board and
 -- the panel model to the same state before each run; the waits after it
 -- are compared. The full Policy inputs and raw Render models are compared; fixture
 -- H.Board delivery precedes the explicit RefreshPanel observation window.
 local start={{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}}
 local controlSteps={
  {cards={{spellId=200001,quality=1},{spellId=200026,quality=0}}},
  {cards={{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200027,quality=1}},noCount=true},
  {cards={{spellId=200001,quality=1},{spellId=200028,quality=0}}},
 }
 local function explicitStep(cards,noCount)
  if noCount then H.service.GetPendingRollsCount=function()return nil end end
  H.Board(cards)
  local before=effects()
  local stepped=Nexus.RefreshPanel()
  local after=effects()
  H.service.GetPendingRollsCount=pending
  local m=Nexus.Panel._lastModel
  return stepped==true and unchanged(before,after),{status=m.status,recommendation=m.recommendation,shown=texts()}
 end
 local function controlled(useCandidate)
  if useCandidate then inject(complete) else Nexus.Localization=seam end
  local run={time=H.now,misses=L.Diagnostics().misses,quiet={},presented={},planned={},policyInputs={}}
  local policyDecide=Nexus.Policy.Decide
  Nexus.Policy.Decide=function(state,...)
   run.policyInputs[#run.policyInputs+1]=H.Clone(state)
   local action=policyDecide(state,...)
   run.planned[#run.planned+1]=type(action)=='table' and (tostring(action.type)..'|'..tostring(action.reason)) or 'none'
   return action
  end
  local log=instrument()
  run.quiet[1],run.start=explicitStep(start)
  run.startPlanned,run.planned,log.render,log.status=run.planned[1],{},{},{}
  run.policyInputs={}
  for i,step in ipairs(controlSteps)do run.quiet[i+1],run.presented[i]=explicitStep(step.cards,step.noCount)end
  log.restore();Nexus.Policy.Decide=policyDecide
  run.render,run.status,run.calls,run.loud,run.errors=log.render,log.status,log.calls,log.loud,log.errors
  run.misses=L.Diagnostics().misses-run.misses
  return run
 end
 local english=controlled(false)
 local candidate=controlled(true)
 local held=true
 for i=1,#controlSteps+1 do held=held and english.quiet[i]==true and candidate.quiet[i]==true end
 check(held,'matched control: each explicit real runtime step ran with no game action, send, queued packet, chat line, popup, Automation or settings change, in English and with the candidate')
 check(english.calls>0 and english.loud==0 and candidate.loud==0 and english.errors==0 and candidate.errors==0 and english.calls==candidate.calls,'matched control: each presentation call inside those steps was quiet, as often in both runs')
 check(english.time==candidate.time and english.startPlanned==candidate.startPlanned and tostring(english.startPlanned):find('^take|')~=nil
  and english.start.status==candidate.start.status and english.start.recommendation==candidate.start.recommendation,
  'matched control: the same time and take start, presented alike, before both runs')
 local waits={'waiting for three-card board','waiting for pending-pick count','waiting for three-card board'}
 local planned,statuses,inputs={},{},{}
 for i,reason in ipairs(waits)do planned[i],statuses[i]='wait|'..reason,'waiting: '..reason;inputs[i]=english.render[i] and english.render[i].recommendation end
 check(same(english.policyInputs,candidate.policyInputs),'matched control: full Policy inputs are equal')
 check(same(english.planned,planned) and same(candidate.planned,planned),'matched control: identical raw planner decisions')
 check(same(english.status,statuses) and same(candidate.status,statuses),'matched control: identical raw onStatus inputs')
 check(#english.render==#waits and same(inputs,waits) and same(english.render,candidate.render),'matched control: identical raw Render inputs carrying the raw planner reasons')
 for i,want in ipairs({{W3,C3},{WP,CP},{W3,C3}})do
  for which,run in ipairs({english,candidate})do
   local p,text=run.presented[i],want[which]
   check(p.status==text and p.recommendation==text and p.shown:find(text,1,true)~=nil
    and not p.shown:find('Guaranteed current offer',1,true) and not p.shown:find('WISHLIST:',1,true)
    and not p.shown:find('waiting: ',1,true),'matched control step '..i..': '..(which==1 and 'English' or 'the candidate')..' presents exactly its own bytes')
  end
 end
 check(english.misses==0 and candidate.misses==0,'matched control: neither run records a fallback')
 check(L.Diagnostics().misses==fx.diag.misses,'the complete pack records no unexpected fallback')
 Nexus.Localization=seam
 check(Nexus.UserText.Message('waiting for three-card board')==W3,'real seam restored with its exact English')
 assert(quiet('restore real English committed display',Nexus.Panel.Render,H.Clone(Nexus.Panel._lastModel)))
 exact(W3,'restored seam re-presents the committed raw source in English')
end
-- #142 reviewed Unicode at the actual visible menu boundary, versus raw text.
do
 Nexus.Panel.Show()
 local V=dofile('tests/prototype/view_regression_support.lua')
 local seam=Nexus.Localization
 local want='Fixture Cafe'..string.char(0xCC,0x81)..' ARMED TARGET: 10% {count}'
 local pack={['reason.save_in_progress']=want}
 local admitted,source=seam.Resolve('reason.save_in_progress',pack)
 check(admitted==want and source=='candidate','SETUP: combining Unicode is admitted by the reviewed text contract')
 local wrapped={};for k,v in pairs(seam)do wrapped[k]=v end
 wrapped.Text=function(key)return seam.Text(key,pack)end
 Nexus.Localization=wrapped
 local function visible(wantLine,label)
  local menu=assert(NexusPanel._menuBtn,'SETUP: actual menu exists')
  local lines,ok,err=quiet('actual menu hover',V.TooltipLines,assert(menu:GetScript('OnEnter')),menu)
  check(ok,'actual menu tooltip succeeds: '..tostring(err))
  local found=false;for _,line in ipairs(lines)do if line==wantLine then found=true end end
  check(found,label)
 end
 local prior=H.Clone(Nexus.Panel._lastModel)
 prior.status='CURSOR_REQUIRED';prior.recommendation='CURSOR_REQUIRED'
 assert(quiet('distinct previous Render',Nexus.Panel.Render,prior))
 check(Nexus.Panel._lastModel.status~=want,'SETUP: distinct prior status established by Render')
 check(quiet('localized raw status',Nexus.Panel.SetStatus,'ROOT_MUTATION_PENDING')==true,'raw SetStatus replaces the distinct rendered state')
 visible('Status: '..want,'NFD localized status survives the actual menu hover byte for byte')
 local model=H.Clone(Nexus.Panel._lastModel);model.recommendation='ROOT_MUTATION_PENDING'
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
 check(texts():find(want,1,true),'NFD localized recommendation reaches a real FontString')
 visible('Status: '..want,'owned copy re-presents NFD status once')
 model=H.Clone(Nexus.Panel._lastModel);model.status=want;model._nexusPanelPresentation=nil
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
 visible('Status: status unavailable','untrusted raw combining text retains the Identity gate')

 -- An unrelated producer's generic field is retained and never consumed.
 model=H.Clone(Nexus.Panel._lastModel);model._nexusPanelPresentation=nil
 model.status='ROOT_MUTATION_PENDING';model.recommendation='ROOT_MUTATION_PENDING'
 model.presentation={raw={status='FOREIGN'},text={status='ROOT_MUTATION_PENDING'}}
 assert(quiet('foreign producer record',Nexus.Panel.Render,model))
 check(Nexus.Panel._lastModel.status==want and same(Nexus.Panel._lastModel.presentation,model.presentation),'generic producer presentation is retained but ignored')
 local touched=0
 local trap={__index=function()touched=touched+1;error('record __index')end,__tostring=function()touched=touched+1;error('record __tostring')end}
 local malformed={
  {version=1,raw={status={},recommendation='ROOT_MUTATION_PENDING'},text={status='ROOT_MUTATION_PENDING',recommendation='ROOT_MUTATION_PENDING'}},
  {version=1,raw={},text={status='ROOT_MUTATION_PENDING',recommendation='ROOT_MUTATION_PENDING'}},
  setmetatable({version=1},trap),
  {version=1,raw=setmetatable({},trap),text={}},
  {version=1,raw={},text=setmetatable({},trap)},
 }
 for _,record in ipairs(malformed)do
  model=H.Clone(Nexus.Panel._lastModel);model.status='ROOT_MUTATION_PENDING';model.recommendation='ROOT_MUTATION_PENDING'
  model._nexusPanelPresentation=record
  assert(quiet('malformed owned record',Nexus.Panel.Render,model))
  check(Nexus.Panel._lastModel.status==want and Nexus.Panel._lastModel.recommendation==want,'malformed record cannot blank or stringify the raw input')
 end
 check(touched==0,'record/subtable validation invokes no metamethod')
 -- Same visible output, different raw origin: a no-layout SetStatus still
 -- updates provenance. A later copied render proves which raw value survived.
 Nexus.Localization=seam
 local english='Saving is still in progress; wait for its final result'
 model=H.Clone(Nexus.Panel._lastModel);model._nexusPanelPresentation=nil
 model.status=english;model.recommendation='ROOT_MUTATION_PENDING'
 assert(quiet('equal-output raw setup',Nexus.Panel.Render,model))
 local stats=Nexus.Panel.RenderStats()
 check(quiet('equal-output new raw provenance',Nexus.Panel.SetStatus,'ROOT_MUTATION_PENDING')==false,'equal-output SetStatus retains its false return')
 check(same(stats,Nexus.Panel.RenderStats()),'equal-output SetStatus performs no layout or status update')
 Nexus.Localization=wrapped
 assert(quiet('equal-output copied re-presentation',Nexus.Panel.Render,H.Clone(Nexus.Panel._lastModel)))
 visible('Status: '..want,'equal-output SetStatus keeps the new raw origin for a copied render')
 -- Actual raw restoration paths, through Panel's public entry points. The
 -- first real render seeds roll content; the next reserves an empty Auto gap.
 model=H.Clone(Nexus.Panel._lastModel);model.auto=true
 model.progress={wishlistName='Review target',total=12,owned=0,activeSlot=1,toLock={}}
 model.orbGuidance=nil;model.paused=nil;model.effective=nil
 model.cards={{text='fixture'}};model.recommendation='ROOT_MUTATION_PENDING';model.status='ROOT_MUTATION_PENDING'
 assert(quiet('Auto content before reservation',Nexus.Panel.Render,model))
 model=H.Clone(Nexus.Panel._lastModel);model.cards={};model.recommendation=''
 assert(quiet('reserve empty Auto gap',Nexus.Panel.Render,model))
 check(NexusPanel._rollArea:IsShown(),'SETUP: assigned unfinished Auto gap reserves the roll block')
 quiet('release reserved gap through SetAuto OFF',Nexus.Panel.SetAuto,false)
 check(Nexus.Panel._lastModel.auto==false,'real reserved-gap release committed Auto OFF')
 visible('Status: '..want,'reserved Auto release restores raw NFD status once')
 model=H.Clone(Nexus.Panel._lastModel);model.recommendation='ROOT_MUTATION_PENDING'
 assert(quiet('refused-click setup',Nexus.Panel.Render,model))
 check(quiet('refused Auto-click re-presentation',Nexus.Panel.NoteAutoClick,false,true,false)==true,'refused Auto click re-renders the assigned model')
 visible('Status: '..want,'refused Auto-click restores raw NFD status once')
 check(NexusPanel._rollRec:GetText():find(want,1,true)~=nil,'refused Auto-click preserves the candidate recommendation FontString')
 for _,bad in ipairs({'unsafe|cffffffff','unsafe\nline',string.rep('x',257),string.char(255)})do
  pack['reason.save_in_progress']=bad
  model=H.Clone(Nexus.Panel._lastModel);model.status='ROOT_MUTATION_PENDING'
  assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
  visible('Status: Saving is still in progress; wait for its final result','invalid localized candidate falls back before tooltip: '..#bad)
 end
 Nexus.Localization=seam
 model=H.Clone(Nexus.Panel._lastModel);model.status='ROOT_MUTATION_PENDING';model.recommendation='ROOT_MUTATION_PENDING'
 assert(quiet('direct raw/committed Render',Nexus.Panel.Render,model))
 visible('Status: Saving is still in progress; wait for its final result','real English menu display restored')
end


Nexus.WishlistEditor.Show();check(NexusEditorFrame:IsShown() and texts():find('Explore',1,true),'T01 actual Wishlist navigation to Explore')
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
-- A Saved Build mirror's projected Share action is on its own visible Share
-- button and Copy is hidden there; an ordinary build keeps Copy on its button.
for _,case in ipairs({{'saved','Share Build...',{'server Saved Build'},true},
 {'shared','Update Shared Build...',{'Shared listing saved on this client','receipt by other players is not confirmed'},true},
 {'locked','Copy into Editor',{'Echo list is read-only'}},{'copy','Copy into Editor',{'You own this build'}}})do
 local detail,e=projection.Detail(case[1],{ownerKey=owner,ownedBySpell={}});check(detail,e or 'real projection exists')
 renderDetail(case[1])
 local mirror=case[4]==true
 local action,other
 if mirror then action,other=dp.shareBtn,dp.lockBtn else action,other=dp.lockBtn,dp.shareBtn end
 local projected=detail and (mirror and detail.shareText or detail.actionText)
 check(action and action:IsShown() and action:GetText()==projected and action:GetText()==case[2],'projected action reaches actual visible button')
 check(other and not other:IsShown(),mirror and 'a mirror offers no draft Copy' or 'an ordinary build offers no Saved Build Share')
 for _,needle in ipairs(case[3])do check(dp.editState:GetText():find(needle,1,true),'projected edit status reaches actual fontstring') end
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
  {'STORE_PENDING','reason.saved_data_reading','Reading your saved data'},
  {'waiting for three-card board','reason.wait_three_choices','Waiting for the next three Echo choices'},
  {'waiting for pending-pick count','reason.wait_pending_pick_count','waiting for pending-pick count'}}
 -- Issue #142: the row the real Readout shows for banish 0, reroll unknown and
 -- freeze 7 under each active language (literal expectations).
 local CHARGES={enUS='B:0 R:? F:7',frFR='Ban:0 Rel:? Gel:7',deDE='Verb:0 Neu:? Einfr:7',esES='Dest:0 Rel:? Cong:7',
  plPL='Wygn:0 Przel:? Zamr:7',ptBR='Banir:0 Rolar:? Cong:7',
  ruRU='\208\152\208\183\208\179:0 \208\159\208\181\209\128:? \208\151\208\176\208\188:7'}
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
 -- Review F3: the eight choices the real Language submenu offers, Automatic
 -- and the seven manual packs, in this literal order. Choices finds each by
 -- its visible name whether or not its row carries a click; checkable counts
 -- every choice row (the title and the notices are not checkable).
 local CHOICES={'automatic','enUS','frFR','deDE','esES','plPL','ptBR','ruRU'}
 local function Choices(menu)
  local found,count,checkable={},0,0
  for _,row in ipairs(menu and menu.menuList or {})do
   if type(row)=='table' and not row.notCheckable and not row.isTitle then
    checkable=checkable+1
    local text,id=tostring(row.text),nil
    if text:sub(1,11)=='Automatic (' then
     id='automatic'
    else
     for i=2,#CHOICES do
      local name=CHOICES[i]=='enUS' and 'English' or PACKS[CHOICES[i]].name
      if text:sub(1,#name)==name then id=CHOICES[i] end
     end
    end
    if id and not found[id] then found[id]=row;count=count+1 end
   end
  end
  return found,count,checkable
 end
 -- The checked choices in CHOICES order, joined ('' when none is checked).
 local function CheckedChoices(found)
  local out={}
  for _,id in ipairs(CHOICES)do if found[id] and found[id].checked==true then out[#out+1]=id end end
  return table.concat(out,',')
 end
 -- A refused menu: all eight offered choices present and visibly disabled,
 -- the Automatic row without a click, and the reason row naming the refusal.
 local function RefusedChoices(menu,reason,label)
  local found,count,checkable=Choices(menu)
  check(count==8 and checkable==8,label..': all eight offered choices are listed ('..count..' found in '..checkable..' choice rows)')
  for _,id in ipairs(CHOICES)do
   check(found[id]~=nil and found[id].disabled==true,label..': the '..id..' choice is present and visibly disabled')
  end
  check(found.automatic.func==nil,label..': the refused Automatic row carries no click')
  check(MenuText(menu):find('Changes unavailable: '..reason..'.',1,true)~=nil,label..': the menu names the refusal: '..reason)
  return found
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
  local slots={banish={known=true,value=0},reroll={known=false},freeze={known=true,value=7}}
  check(Nexus.Readout.ChargesLine({banish=0,freeze=7})==CHARGES[id] and Nexus.Readout.ChargesLine({banish=0,freeze=7,trustworthy=false})==CHARGES[id]..' ~',label..': the real Readout charge row of the active language; known 0 is 0 and unknown is ?')
  check(Nexus.Localization.Format('readout.charge_counts',slots,{})=='B:0 R:? F:7',label..': an explicit {} pack still gives the English row')
 end
 -- A. Automatic default (issue #141): an absent preference, nothing added at
 -- start-up; the actual menu checks Automatic and shows English; reads and
 -- an Automatic click write nothing. Then explicit English, its no-op
 -- control, and Automatic again through the same private writer.
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
 check(Row(menu,'enUS') and text:find('other Nexus text stays English',1,true) and not text:find('three status messages',1,true),'English and the bounded coverage note are listed (#143: its exact wording is checked after the Panel consumer cohort below)')
 for _,id in ipairs(IDS)do
  check(Row(menu,id) and not Row(menu,id).disabled,'the chooser lists '..id..' by its own name, enabled')
  check(not text:find(id,1,true) and not menu.text:find(id,1,true),'no internal language ID is shown: '..id)
 end
 check(text:find('reload',1,true) and not text:lower():find('fully',1,true) and not text:find('Changes unavailable',1,true),'the reload requirement, no full-support claim, no refusal')
 local function Auto(m)
  for _,row in ipairs(m and m.menuList or {})do
   if type(row.text)=='string' and row.text:sub(1,11)=='Automatic (' and not row.notCheckable then return row end
  end
 end
 check(Auto(menu) and Auto(menu).checked==true and Auto(menu).text:find('English',1,true) and not Auto(menu).disabled and Row(menu,'enUS').checked~=true and Row(menu,'enUS').text:find('active',1,true) and rawget(NexusDB.settings,'uiLanguage')==nil,'EXPECT #141: the actual ... menu checks Automatic (showing English) as the default preference while no preference is saved; English is the active language, not a saved manual choice')
 check(text:find('Nexus does not read the game',1,true) and not text:find('English is shown',1,true),'the menu says Automatic reads no game language, without the unsupported-value notice')
 NexusPanel._menuBtn.scripts.OnEnter(NexusPanel._menuBtn);NexusPanel._menuBtn.scripts.OnLeave(NexusPanel._menuBtn)
 local status=Nexus.Panel.LanguageStatus()
 check(status.active=='enUS' and status.saved=='enUS' and status.pending==false and status.refusal==nil,'status: English active, nothing pending, changes available')
 check(writes.n==0 and F.Serialize(NexusDB.settings)==settings0 and Effects()==effects and #H.chat==chat0,'opening, hovering, closing and status reads write and print nothing')
 check(status.automatic==true and status.activeAutomatic==true and status.preferencePending==false and status.savedUnsupported==false and status.automaticLanguage=='enUS','status: Automatic is the saved and the session preference, and it shows English')
 Auto(menu).func()
 check(writes.n==0 and F.Serialize(NexusDB.settings)==settings0 and rawget(NexusDB.settings,'uiLanguage')==nil and Effects()==effects,'choosing Automatic while no preference is saved is a truthful no-op: no write and no field added')
 -- An explicit English choice is a manual preference, saved once through the
 -- exact private writer though English already shows. Its repeat is the
 -- original manual-English no-op control.
 Row(menu,'enUS').func()
 status=Nexus.Panel.LanguageStatus()
 check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='enUS' and Effects()==effects,'an explicit English choice while Automatic is the default writes the manual enUS preference once, with no game action, send, popup, Auto or client option change')
 check(status.active=='enUS' and status.saved=='enUS' and status.pending==false and status.automatic==false and status.activeAutomatic==true and status.preferencePending==true,'status: manual English is saved and pending as a preference; the session keeps its Automatic start; the shown language does not change')
 menu=LanguageMenu()
 check(Row(menu,'enUS').checked==true and Auto(menu).checked~=true and Row(menu,'enUS').text:find('saved, applies after reload',1,true) and Auto(menu).text:find('in use',1,true) and menu.text:find('after reload',1,true),'the menu tells the saved manual English from the Automatic session')
 local manualSettings=F.Serialize(NexusDB.settings)
 Row(menu,'enUS').func()
 check(writes.n==1 and F.Serialize(NexusDB.settings)==manualSettings,'choosing English while English is the saved manual preference writes nothing')
 menu=LanguageMenu();Auto(menu).func()
 status=Nexus.Panel.LanguageStatus()
 check(writes.n==2 and rawget(NexusDB.settings,'uiLanguage')=='automatic','choosing Automatic over the manual English saves the Automatic value through the same owned writer')
 check(status.automatic==true and status.saved=='enUS' and status.pending==false and status.preferencePending==false and status.savedUnsupported==false,'status: the saved Automatic value is the session preference again and is not unsupported')
 menu=LanguageMenu()
 check(Auto(menu).checked==true and Row(menu,'enUS').checked~=true and not Auto(menu).text:find('saved, applies',1,true) and not MenuText(menu):find('English is shown',1,true),'the menu checks Automatic again')
 Auto(menu).func()
 check(writes.n==2 and rawget(NexusDB.settings,'uiLanguage')=='automatic' and Effects()==effects,'choosing the saved Automatic again is a no-op; no choice caused a game action, send, popup, Auto or client option change')
 writes.n=0 -- the frFR scenario below counts its own writes on this same writer
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
  -- Review F3: the same oversized root through the real registered menu.
  -- Its known durable preference is the manual deDE, not the Automatic
  -- default: all eight offered choices are disabled, only deDE is checked,
  -- and a direct Automatic submit is refused for capacity before the writer.
  local effects=Effects()
  local status=Nexus.Panel.LanguageStatus()
  check(status.refusal=='capacity' and status.active=='deDE' and status.saved=='deDE' and status.preference=='deDE'
   and status.automatic==false and status.activeAutomatic==false and status.pending==false and status.preferencePending==false
   and status.savedUnsupported==false and select(3,Nexus.Localization.ActiveLanguage())==false,
   'capacity refusal: the status and the session start name the durable manual deDE, not the Automatic default')
  menu=LanguageMenu()
  local found=RefusedChoices(menu,'saved data is kept unchanged after a shared-data capacity refusal','capacity refusal')
  check(CheckedChoices(found)=='deDE','capacity refusal: only the durable manual deDE is checked; Automatic is not')
  r=Nexus.Panel.ChooseLanguage('automatic')
  check(r.state=='refused' and r.reason=='capacity' and writes.n==0 and F.Serialize(NexusDB)==saved and Effects()==effects,
   'capacity refusal: a direct Automatic submit is refused before the writer; the whole root and game effects are unchanged')
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
  -- Review F3: the drifted session's real menu offers all eight choices,
  -- each disabled. It checks the admitted saved preference (absent, so
  -- Automatic), never the unadmitted replacement's enUS, and a direct
  -- Automatic submit is refused for drift before the writer.
  local effects=Effects()
  local status=Nexus.Panel.LanguageStatus()
  check(status.refusal=='drift' and status.preference=='automatic' and status.automatic==true and status.savedUnsupported==false,'replaced settings: the status reads the admitted saved source and refuses for drift')
  local found=RefusedChoices(menu,'the saved data changed since start-up; reload first','replaced settings')
  check(CheckedChoices(found)=='automatic','replaced settings: Automatic, the admitted absent preference, is the only checked choice')
  r=Nexus.Panel.ChooseLanguage('automatic')
  check(r.state=='refused' and r.reason=='drift' and writes.n==0 and Effects()==effects,'replaced settings: a direct Automatic submit is refused before the writer')
  check(NexusDB.settings==replacement and NexusDB.authorityBundle.storeData.settings==admitted and F.Serialize(NexusDB)==frozen,'replaced settings: after the Automatic refusal both identities and the whole root stay unchanged')
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
  check((prior and Row(menu,prior).checked==true and Auto(menu).checked~=true or not prior and Auto(menu).checked==true and Row(menu,'enUS').checked~=true) and Row(menu,'ruRU').checked==false and not Row(menu,'ruRU').text:find('saved',1,true),'session result: reopening the real menu checks the durable preference (Automatic while none was saved), never the session choice')
  check(MenuText(menu):find('The last choice was not saved',1,true) and (not prior or Row(menu,prior).text:find('saved, applies after reload',1,true)),'session result: truthful notice preserves any earlier durable pending choice')
  check(writes.n==calls+1 and F.Serialize(NexusDB)==frozen,'session result: repeated status/menu reads invoke no writer')
  H=F.Reload();CountWriter()
  Expect(saved,'session choice discarded after reload')
  check(Nexus.Panel.LanguageStatus().pending==false and writes.n==0 and F.Serialize(NexusDB)==frozen,'reload: only the original saved choice survives, with no write')
 end
 -- G. Issue #141: Automatic through real row clicks, the exact private
 -- writer and serialized synthetic reloads (F.Reload: an offline module
 -- reload, not a client reload). Before each boot a mock client fact says
 -- frFR (GetLocale); Nexus never uses it and Automatic stays English. This
 -- proves the offline preference and menu behaviour only, not native
 -- automatic-language integration. Nothing here asks for a reload.
 do
  local reloads,realReload=0,ReloadUI
  ReloadUI=function()reloads=reloads+1 end
  local function ClientFact()GetLocale=function()return 'frFR' end end
  H=F.Boot(F.Database({version=2}),ClientFact);CountWriter()
  check(GetLocale()=='frFR' and rawget(NexusDB.settings,'uiLanguage')==nil,'SETUP #141: no saved preference, and a mock client fact that suggests frFR')
  Expect('enUS','Automatic beside a mock frFR client fact')
  check(select(3,Nexus.Localization.ActiveLanguage())==true,'the session started on Automatic')
  Nexus.Panel.Show();local menu=LanguageMenu()
  NexusPanel._menuBtn.scripts.OnEnter(NexusPanel._menuBtn);NexusPanel._menuBtn.scripts.OnLeave(NexusPanel._menuBtn)
  menu=LanguageMenu()
  check(writes.n==0 and rawget(NexusDB.settings,'uiLanguage')==nil,'opening, hovering and closing the menu without a click (cancel) write nothing')
  local effects=Effects()
  Row(menu,'deDE').func()
  local status=Nexus.Panel.LanguageStatus()
  check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='deDE' and status.automatic==false and status.pending==true and status.preferencePending==true and status.active=='enUS' and Effects()==effects,'a manual deDE choice is saved while the mock client fact suggests frFR; English stays active')
  H=F.Reload(ClientFact);CountWriter()
  Expect('deDE','manual deDE after reload; the mock frFR client fact is not used')
  status=Nexus.Panel.LanguageStatus()
  check(status.automatic==false and status.activeAutomatic==false and status.pending==false and status.preferencePending==false and writes.n==0,'after reload manual deDE is the session preference')
  Nexus.Panel.Show();menu=LanguageMenu()
  check(Row(menu,'deDE').checked==true and Auto(menu).checked~=true and Nexus.Panel.LanguageMenuLabel()=='Language: Deutsch','the menu checks the manual deDE')
  effects=Effects()
  Auto(menu).func()
  status=Nexus.Panel.LanguageStatus()
  check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='automatic' and Effects()==effects,'manual deDE -> Automatic: one durable write of the Automatic value')
  check(status.automatic==true and status.saved=='enUS' and status.active=='deDE' and status.pending==true and status.preferencePending==true,'status: Automatic is saved and pending; deDE is still the active language, never called Automatic')
  Nexus.Panel.Hide();Nexus.Panel.Show();menu=LanguageMenu()
  check(Auto(menu).checked==true and Auto(menu).text:find('saved, applies after reload',1,true) and not Auto(menu).text:find('in use',1,true) and Row(menu,'deDE').text:find('active',1,true) and Row(menu,'deDE').checked~=true and Nexus.Panel.LanguageMenuLabel()=='Language: Deutsch (new choice after reload)','reopened: the pending Automatic preference beside the active deDE')
  Expect('deDE','Automatic pending, reopened panel')
  check(Nexus.Localization.InitializeActiveLanguage('automatic')=='deDE','a later initialization does not switch the session')
  H=F.Reload(ClientFact);CountWriter()
  Expect('enUS','saved Automatic after reload; the mock frFR client fact is not used')
  status=Nexus.Panel.LanguageStatus()
  check(rawget(NexusDB.settings,'uiLanguage')=='automatic' and status.automatic==true and status.activeAutomatic==true and status.pending==false and status.preferencePending==false and status.savedUnsupported==false and writes.n==0,'after reload Automatic is the session preference, kept as saved, with no write')
  check(Nexus.Panel.LanguageMenuLabel()=='Language: Automatic (English)','the menu label names Automatic and the English it shows')
  Nexus.Panel.Show();menu=LanguageMenu();Auto(menu).func()
  check(writes.n==0,'choosing the saved Automatic again writes nothing')
  Row(menu,'enUS').func()
  check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='enUS','Automatic -> explicit English saves the manual enUS value though both show English')
  H=F.Reload(ClientFact);CountWriter()
  Expect('enUS','explicit English after reload')
  status=Nexus.Panel.LanguageStatus()
  check(rawget(NexusDB.settings,'uiLanguage')=='enUS' and status.automatic==false and status.activeAutomatic==false and status.preferencePending==false and select(3,Nexus.Localization.ActiveLanguage())==false,'explicit English survives the reload as a manual preference, apart from Automatic')
  Nexus.Panel.Show();menu=LanguageMenu()
  check(Row(menu,'enUS').checked==true and Auto(menu).checked~=true and Nexus.Panel.LanguageMenuLabel()=='Language: English','the menu checks the manual English, not Automatic')
  H.Fire('PLAYER_ENTERING_WORLD');H.Advance(3,.05)
  Expect('enUS','explicit English after another world entry')
  check(writes.n==0 and rawget(NexusDB.settings,'uiLanguage')=='enUS','world entry writes nothing and never turns a manual English into Automatic')
  -- Unsupported saved values stay exactly as saved and are never Automatic,
  -- until an explicit Automatic choice replaces one through the same writer.
  for _,raw in ipairs({'xxXX',42,'AUTOMATIC',{keep='raw'}})do
   NexusDB.settings.uiLanguage=raw
   H=F.Reload(ClientFact);CountWriter()
   local label='unsupported '..F.Serialize(raw)
   Expect('enUS',label)
   status=Nexus.Panel.LanguageStatus()
   check(F.Serialize(rawget(NexusDB.settings,'uiLanguage'))==F.Serialize(raw) and status.savedUnsupported==true and status.automatic==false and status.activeAutomatic==false and writes.n==0,label..': kept exactly as saved, not Automatic, English shown, no write')
   Nexus.Panel.Show();menu=LanguageMenu()
   check(Auto(menu).checked~=true and MenuText(menu):find('English is shown',1,true),label..': the menu never calls it Automatic and says English is shown')
  end
  Auto(menu).func()
  status=Nexus.Panel.LanguageStatus()
  check(writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='automatic' and status.savedUnsupported==false and status.automatic==true and status.pending==false,'an explicit Automatic choice replaces the unsupported value through the same owned durable write')
  -- An Automatic choice keeps the session-only, read-only, drift, owner and
  -- invalid-input refusals of every other choice.
  H=F.Boot(F.Database({version=2,mutate=function(d)d.settings.uiLanguage='frFR' end}),ClientFact);CountWriter()
  Expect('frFR','manual frFR beside a mock frFR client fact')
  local owner=Nexus.MainInternals.StoreAuthorityOwner;local original=owner.UpdateSettingsV1
  local mode,frozen
  owner.UpdateSettingsV1=function(key,value)
   NexusDB.settingsVersion=6 -- authority drift at the actual writer boundary
   frozen=F.Serialize(NexusDB)
   local result=original(key,value);mode=result and result.mode
   return result
  end
  Nexus.Panel.Show();menu=LanguageMenu();Auto(menu).func()
  owner.UpdateSettingsV1=original
  status=Nexus.Panel.LanguageStatus()
  check(mode=='session' and writes.n==1 and Nexus.Store.Settings().uiLanguage=='automatic' and rawget(NexusDB.settings,'uiLanguage')=='frFR' and F.Serialize(NexusDB)==frozen,'a session-only Automatic result changes only the detached projection; the saved manual frFR stays')
  check(status.sessionOnly==true and status.automatic==false and status.saved=='frFR' and status.active=='frFR' and status.refusal=='read-only','status keeps the durable manual frFR and says the Automatic choice was not saved')
  menu=LanguageMenu()
  check(Row(menu,'frFR').checked==true and Auto(menu).checked~=true and Auto(menu).disabled==true and Auto(menu).func==nil and not Auto(menu).text:find('saved',1,true) and MenuText(menu):find('The last choice was not saved',1,true),'the menu never labels the session-only Automatic saved, and a refused Automatic row cannot submit')
  local r=Nexus.Panel.ChooseLanguage('automatic')
  check(r.state=='refused' and r.reason=='read-only' and writes.n==1 and F.Serialize(NexusDB)==frozen,'the read-only root refuses an Automatic choice before the writer')
  H=F.Reload(ClientFact);CountWriter()
  Expect('frFR','the session-only Automatic choice is discarded after reload')
  H=F.Boot(F.Database({version=2,mutate=function(d)d.settings.uiLanguage='enUS' end}),ClientFact);CountWriter()
  local internals=Nexus.MainInternals;local realOwner,foreign=internals.StoreAuthorityOwner,0
  internals.StoreAuthorityOwner={owner={},UpdateSettingsV1=function()foreign=foreign+1;return {mode='durable'}end}
  r=Nexus.Panel.ChooseLanguage('automatic')
  internals.StoreAuthorityOwner=realOwner
  check(r.state=='refused' and r.reason=='authority' and foreign==0 and writes.n==0,'another Store owner: an Automatic choice is refused and its writer never called')
  local current=NexusDB;NexusDB=F.Database({version=2});local other=F.Serialize(NexusDB)
  r=Nexus.Panel.ChooseLanguage('automatic')
  local otherAfter=F.Serialize(NexusDB);NexusDB=current
  check(r.state=='refused' and r.reason=='drift' and writes.n==0 and otherAfter==other and rawget(NexusDB.settings,'uiLanguage')=='enUS','a replaced saved root: an Automatic choice is refused, neither root written')
  for i,bad in ipairs({'Automatic','AUTOMATIC','auto','',42,true,{}})do
   r=Nexus.Panel.ChooseLanguage(bad)
   check(r.state=='refused' and r.reason=='invalid' and writes.n==0,'a near-miss of the Automatic value is not a choice #'..i)
  end
  r=Nexus.Panel.ChooseLanguage('automatic')
  check(r.state=='saved' and r.automatic==true and r.resolved=='enUS' and r.pending==false and r.preferencePending==true and writes.n==1 and rawget(NexusDB.settings,'uiLanguage')=='automatic','control: with the authority current the Automatic choice is saved; English is already shown, and the preference applies after a reload')
  local said=Nexus.Panel.LanguageResultText(r)
  check(said:find('Automatic (English)',1,true) and said:find('does not read the game',1,true) and said:find('next interface reload or login',1,true),'the result names Automatic and the English it shows, without claiming a game language')
  check(reloads==0,'no choice, read or reopen asked for a reload')
  ReloadUI=realReload
 end
 -- F. Early start-up, authority drift and a Store the session was not initialized with.
 do
  local early
  H=F.Boot(F.Database({version=2}),nil,function(h)
   local owner=Nexus.MainInternals.StoreAuthorityOwner;local original,n=owner.UpdateSettingsV1,0
   owner.UpdateSettingsV1=function(...)n=n+1;return original(...)end
   local settings,root=F.Serialize(NexusDB.settings),F.Serialize(NexusDB)
   local actions,sent,popup=#h.actions,#h.sent,h.popup
   -- Review F2/F3: start-up has not initialized the language yet, so these
   -- reads and submits use the Panel fallback; nothing here drives start-up.
   local _,initialized=Nexus.Localization.ActiveLanguage()
   local status=Nexus.Panel.LanguageStatus()
   local rows=Nexus.Panel.LanguageMenuItems(function(fn)return fn end)
   local result=Nexus.Panel.ChooseLanguage('frFR')
   local automatic=Nexus.Panel.ChooseLanguage('automatic')
   early={menu={menuList=rows},status=status,result=result,automatic=automatic,writes=n,initialized=initialized,
    same=F.Serialize(NexusDB.settings)==settings,root=F.Serialize(NexusDB)==root,
    quiet=#h.actions==actions and #h.sent==sent and h.popup==popup}
   owner.UpdateSettingsV1=original
  end)
  check(early.menu and Row(early.menu,'frFR').disabled==true and MenuText(early.menu):find('Nexus is still starting',1,true),'early start-up: choices are shown disabled with the reason')
  check(early.result.state=='refused' and early.result.reason=='startup' and early.writes==0 and early.same,'early start-up: a choice is refused and nothing is written')
  -- Review F2/F3: before the lifecycle's status callback exists the Panel
  -- fallback knows the active language and the startup refusal but not the
  -- saved preference. All eight offered choices are shown disabled,
  -- Automatic carries no click, and a direct Automatic submit is refused
  -- for startup with no writer, settings, root, action, send or popup.
  check(early.initialized==false,'SETUP early start-up: the language is not initialized yet, so no lifecycle status callback exists')
  local found=RefusedChoices(early.menu,'Nexus is still starting','early start-up')
  check(early.automatic.state=='refused' and early.automatic.reason=='startup' and early.writes==0 and early.same and early.root and early.quiet,'early start-up: a direct Automatic submit is refused and nothing is written, sent or shown')
  local fallback=early.status
  check(fallback.active=='enUS' and fallback.refusal=='startup' and fallback.pending==false and fallback.automaticPreference=='automatic' and fallback.automaticLanguage=='enUS' and #fallback.languages==7,'early start-up: the fallback keeps the active English, the startup refusal, the Automatic value and every installed language')
  check(fallback.saved==nil and fallback.preference==nil and fallback.automatic==nil and fallback.savedUnsupported==nil,'EXPECT F2 early start-up: the fallback leaves the saved preference unknown, never a saved English ('..tostring(fallback.saved)..')')
  check(CheckedChoices(found)=='','EXPECT F2 early start-up: with the saved preference unknown no Automatic or manual row is checked ('..CheckedChoices(found)..')')
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
  -- Review F2: a status callback that fails, or gives no table, is never
  -- accepted. Nexus.Panel.Init is the existing public callback seam; this
  -- replacement lasts only to the end of the scenario (the next block boots
  -- the addon again). The fallback keeps the active English and the startup
  -- refusal and leaves the saved plPL unknown: every choice is disabled,
  -- none is checked and nothing is written.
  local effects,root=Effects(),F.Serialize(NexusDB)
  local failing={{'a failing status callback',function()error('fixture: the status callback failed',0)end},
   {'a status callback without a table',function()return 'not a status table' end}}
  for _,case in ipairs(failing)do
   Nexus.Panel.Init({LanguageStatus=case[2]})
   local status=Nexus.Panel.LanguageStatus()
   local found=RefusedChoices({menuList=Nexus.Panel.LanguageMenuItems(function(fn)return fn end)},'Nexus is still starting',case[1])
   check(status.active=='enUS' and status.refusal=='startup' and status.saved==nil and status.preference==nil and status.automatic==nil and CheckedChoices(found)=='',case[1]..': the fallback keeps the active English and leaves the saved preference unknown, with no row checked')
   local refused=Nexus.Panel.ChooseLanguage('automatic')
   check(refused.state=='refused' and refused.reason=='startup' and freshCalls==0 and writes.n==1 and F.Serialize(NexusDB)==root and Effects()==effects,case[1]..': a direct Automatic submit is refused; no writer, root or game effect')
  end
 end
 -- R. Review F1/F3: future-format (6) saved roots, kept read-only, through
 -- actual TOC boots and the real Language menu. The read-only projection
 -- adopts only an exact language ID or the exact Automatic value; any other
 -- present saved value stays in the root exactly as saved and is
 -- unsupported: English, not Automatic. The module's third ActiveLanguage
 -- result must agree with the lifecycle status, every offered choice is
 -- refused before the writer and the whole root stays byte for byte. The
 -- older read-only fixture counts seven clickable rows; these controls count
 -- all eight offered choices. Offline synthetic data only: a native
 -- SavedVariables round trip is NOT_RUN.
 do
  local NOTICE='The saved language is not offered by this build; English is shown.'
  local CASES={
   {label='absent (healthy control)',saved='enUS',active='enUS',preference='automatic',automatic=true,unsupported=false,checked='automatic'},
   {label='exact saved automatic',value='automatic',projection='automatic',saved='enUS',active='enUS',preference='automatic',automatic=true,unsupported=false,checked='automatic'},
   {label='valid manual frFR (control)',value='frFR',projection='frFR',saved='frFR',active='frFR',preference='frFR',automatic=false,unsupported=false,checked='frFR'},
   {label='near-case esEs',value='esEs',saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
   {label='numeric 42',value=42,saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
   {label='upper AUTOMATIC',value='AUTOMATIC',saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
   {label='future pack itIT',value='itIT',saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
   {label='false',value=false,saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
   {label='plain table',value={keep='raw'},saved='enUS',active='enUS',preference=false,automatic=false,unsupported=true,checked='enUS'},
  }
  for _,case in ipairs(CASES)do
   local value,label=case.value,'read-only '..case.label
   local db=F.Database({version=6,mutate=function(d)d.settings.uiLanguage=assert(loadstring('return '..F.Serialize(value)))()end})
   local input=F.Serialize(db)
   H=F.Boot(db);CountWriter()
   check(Nexus.StartupStatus().coreReady==true and Nexus.MainInternals.SavedRootReadOnlyV1()=='future','SETUP '..label..': a ready session over a future-format saved root')
   check(F.Serialize(rawget(NexusDB.settings,'uiLanguage'))==F.Serialize(value) and Nexus.Store.Settings().uiLanguage==case.projection,'SETUP '..label..': the saved value is kept as saved and the read-only projection holds '..tostring(case.projection))
   Expect(case.active,label)
   local status=Nexus.Panel.LanguageStatus()
   check(status.active==case.active and status.saved==case.saved and status.pending==false and status.preferencePending==false
    and status.refusal=='read-only' and status.preference==case.preference and status.automatic==case.automatic
    and status.activeAutomatic==case.automatic and status.savedUnsupported==case.unsupported,
    'GUARD '..label..': the lifecycle status tells the saved preference and the session start truthfully')
   local id,initialized,automatic=Nexus.Localization.ActiveLanguage()
   check(id==case.active and initialized==true and automatic==case.automatic,
    'EXPECT F1 '..label..': the module '..(case.automatic and 'starts' or 'does not start')..' on Automatic, as the lifecycle status says (third result '..tostring(automatic)..')')
   local effects=Effects()
   Nexus.Panel.Show();menu=LanguageMenu()
   local found=RefusedChoices(menu,'this saved data is kept read-only by this build',label)
   check(CheckedChoices(found)==case.checked,label..': the menu checks '..case.checked..' and nothing else ('..CheckedChoices(found)..')')
   check((found.automatic.text:find(' - in use',1,true)~=nil)==case.automatic and (MenuText(menu):find(NOTICE,1,true)~=nil)==case.unsupported,
    label..': Automatic is in use only for an Automatic start; the unsupported notice only for an unsupported saved value')
   local r=Nexus.Panel.ChooseLanguage('automatic')
   check(r.state=='refused' and r.reason=='read-only' and writes.n==0,label..': a direct Automatic submit is refused before the writer')
   check(F.Serialize(NexusDB)==input and Nexus.Store.Settings().uiLanguage==case.projection and Effects()==effects,
    label..': the whole saved root stays byte for byte, the projection is unchanged and there is no game effect')
  end
 end
end

-- Issue #143 Panel consumer cohort: 21 static meanings at the 24 mapped
-- Panel calls, through the real TOC, the real Localization copy, the real
-- Panel widgets, their registered hovers and the existing navigation
-- callbacks. The English pass boots the shipped data unsubstituted: the
-- real 27-key English base (holding the 21 meanings) and the six real
-- packs. FIXTURE SUBSTITUTION, not shipped data, in the candidate and
-- fallback passes only: F.fileHooks, right after each data file loads,
-- re-sets the 21 English texts to the same bytes and swaps the frFR entries
-- of the 21 meanings (and its charge template) for test-only candidates, or
-- the deDE ones for invalid or absent entries; the real Localization checks
-- and copies them, and the prior hooks are restored after each boot. It is
-- no production setter and no linguistic review. The real-pack GUARD boots
-- each unchanged pack and checks its charge row and hover; it is not
-- widget coverage of every real draft text. Technical offline checks with
-- offline font models, not all of #143 or the UI: fluent and native review,
-- native fit, tooltips and clicks are NOT TESTED.
do
 local F=dofile('tests/prototype/format5_support.lua')
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 local KEYS={
  {'panel.button.my_builds','My Builds'},
  {'panel.tooltip.open_my_builds','Open My Builds'},
  {'panel.tooltip.my_builds_destination','Open the server My Builds page. Choosing a different Saved Build there changes the active loadout.'},
  {'panel.button.assign_wishlist','Assign Wishlist'},
  {'panel.tooltip.assignment_heading','Assign Wishlist'},
  {'panel.tooltip.assignment_chooser','Opens the Echo Journal with its Wishlist chooser for this loadout. Nothing is assigned until you choose a Wishlist there.'},
  {'panel.button.create_wishlist','Create Wishlist'},
  {'panel.tooltip.create_wishlist_heading','Import or create a wishlist'},
  {'panel.tooltip.create_wishlist_source','Paste a wishlist string or build one directly in Nexus.'},
  {'panel.tooltip.create_wishlist_draft','This opens the Wishlist editor with a draft. Nothing is saved or assigned until you press Create & assign or Create unassigned there.'},
  {'panel.heading.locked_targets','LOCKED TARGETS'},
  {'panel.tooltip.locked_remaining','Locked targets remaining'},
  {'panel.tooltip.locked_plan','These targets are planned for your locked Echo slots (a plan designs at most six target copies).'},
  {'panel.tooltip.locked_acquire','Acquire the exact requested Echo and quality first.'},
  {'panel.tooltip.locked_placement','Owned copies still need to be placed in locked Echo slots.'},
  {'panel.tooltip.locked_not_freeze','Current locked Echo slots and card Freeze are separate.'},
  {'panel.tooltip.locked_acquire_list','Still need to acquire:'},
  {'panel.tooltip.open_wishlist_editor','Click to open Wishlist Editor'},
  {'panel.heading.progress','PROGRESS'},
  {'panel.heading.still_needed','STILL NEEDED'},
  {'panel.heading.extra_copies','EXTRA COPIES'},
 }
 local EN,CAND={},{}
 for i,row in ipairs(KEYS)do
  EN[row[1]]=row[2]
  local out={string.format('\195\137preuve %02d \226\128\148 ',i)};local n=#out[1]
  while n+13<=250 do out[#out+1]='d\195\169velopp\195\169e ';n=n+13 end
  out[#out+1]='fin';CAND[row[1]]=table.concat(out)
 end
 local function ENT(key)return EN[key]end
 local function CANDT(key)return CAND[key]end
 local BAD={'|cffff0000Fixture','Fixture\nline','Fixture\1control',string.rep('x',257),'Fixture \237\160\128','   ',''}
 local FILL=string.rep('pr\195\169cis\195\169ment ',12)..'fin'
 local LONGCHARGE='Bannissements:{banish} Relances:{reroll} Gels:{freeze} \226\128\148 '..FILL
 local LONGROW='Bannissements:0 Relances:? Gels:7 \226\128\148 '..FILL
 local function Hooks(mode)
  local hooks={}
  hooks['data\\LocalizationEnglish.lua']=function()
   local base={};for key,text in pairs(Nexus.LocalizationEnglish)do base[key]=text end
   for _,row in ipairs(KEYS)do base[row[1]]=row[2] end
   Nexus.LocalizationEnglish=base
  end
  hooks['data\\LocalizationPacks.lua']=function()
   local packs={}
   for id,pack in pairs(Nexus.LocalizationPacks)do
    local entries={};for key,text in pairs(pack.entries)do entries[key]=text end
    packs[id]={name=pack.name,entries=entries}
   end
   for i,row in ipairs(KEYS)do
    if mode=='candidate' then packs.frFR.entries[row[1]]=CAND[row[1]]
    elseif mode=='fallback' then packs.deDE.entries[row[1]]=i%2==1 and BAD[((i-1)/2)%#BAD+1] or nil end
   end
   if mode=='candidate' then packs.frFR.entries['readout.charge_counts']=LONGCHARGE end
   Nexus.LocalizationPacks=packs
  end
  return hooks
 end
 local log
 local function Boot(language,mode)
  local db=F.Database({version=2});db.settings.uiLanguage=language
  local prior=F.fileHooks;F.fileHooks=mode and Hooks(mode) or nil
  -- A new harness measures with its own defaults until G.UseFont. Also drop
  -- the synthetic NexusFontNormal an earlier G.UseFont left: it still answers
  -- GetFont from the previous harness's font model, so without this reset the
  -- default font model (runtime font scale 1) would not apply again.
  log={};G.model=nil;NexusFontNormal=nil
  local ok,booted=pcall(F.Boot,db,function()
   local methods=G.RegionMethods();local set=methods.SetText
   -- MODEL, this block only (the harness has no template button text; see
   -- wishlist_menu_label_layout): a Button draws its text with one FontString
   -- of its own (GetFontString), made here on first use and anchored at the
   -- button's centre; Button:SetText sets that FontString's text. Until its
   -- owner sizes it, the FontString is as wide as its text in the active font
   -- model (else the harness default) and one model line tall, however small
   -- the button is, and it wraps unless SetWordWrap(false). Not modelled:
   -- per-state font objects, the pushed text offset, SetFormattedText, drawn
   -- clipping or ellipsis, and native font measurement.
   methods.GetFontString=function(self)
    if self.kind~='Button' then return nil end
    local label=rawget(self,'_fixtureLabel')
    if not label then
     label=self:CreateFontString()
     label.width,label.height,label.text=nil,nil,self.text
     label.GetWidth=function(fs)return fs.width or fs:GetStringWidth()end
     label.GetHeight=function(fs)return fs.height or (G.model and G.model.line or 14)end
     label:SetPoint('CENTER',self,'CENTER',0,0)
     rawset(self,'_fixtureLabel',label)
    end
    return label
   end
   methods.SetText=function(self,text,...)
    log[#log+1]={self,text}
    local result=set(self,text,...)
    local label=rawget(self,'_fixtureLabel')
    if label then label.text=self.text end
    return result
   end
   methods.SetWordWrap=function(self,value)self.wordWrap=value end
  end)
  F.fileHooks=prior
  if not ok then error(booted,0)end
  H=booted
  check(F.fileHooks==nil and Nexus.StartupStatus().coreReady==true and Nexus.Localization.ActiveLanguage()==(language or 'enUS'),'SETUP #143: real TOC boot ready with '..(language or 'enUS')..' active; prior fixture hooks restored')
  Nexus.Panel.Show()
  check(Nexus.LayoutMetrics.RuntimeMetrics()==1,'SETUP #143: the fresh boot measures at runtime font scale 1 (the default font model; no synthetic font object kept from an earlier harness)')
 end
 local P={}
 local function Child(i)return NexusPanel.children[i]end
 local function Region(i)return NexusPanel.regions[i]end
 local function Sets(widget)
  local out={};for _,entry in ipairs(log)do if entry[1]==widget then out[#out+1]=entry[2] end end;return out
 end
 local function Lines(owner)
  local lines,saved={},rawget(GameTooltip,'AddLine')
  rawset(GameTooltip,'AddLine',function(_,text,r,g,b,wrap)lines[#lines+1]={text,r,g,b,wrap}end)
  local ok,err=pcall(owner:GetScript('OnEnter'),owner)
  rawset(GameTooltip,'AddLine',saved)
  local leave=owner:GetScript('OnLeave');if leave then leave(owner)end
  assert(ok,err)
  return lines
 end
 local function Setup()
  return {status='STORE_PENDING',recommendation='',cards={},auto=false,level=40,version=Nexus.VERSION,
   progress={},assignment={state='unassigned'}}
 end
 -- M7: Main captures the character into model.character. This synthetic
 -- active model supplies that captured fact, which the My Builds hover
 -- words as its Character line (Tips).
 local function Active()
  return {status='STORE_PENDING',recommendation='Take',cards={{text='Fixture card'}},auto=false,level=40,
   version=Nexus.VERSION,charges={banish=0,freeze=7},character='PrototypeTester',
   progress={wishlistName='Fixture plan',total=12,owned=3,activeSlot=1,unknownTomes={},
    missing={'Echo 1 (Rare:x2)','Echo 2'},shed={'Echo 3'},toLock={'Echo 80','Gl\195\164nzend Echo'}}}
 end
 local BULLET='  \226\128\162 '
 local function Tips(T)
  local editor={T('panel.tooltip.open_wishlist_editor'),0.4,0.8,1}
  return {
   assign={{T('panel.tooltip.assignment_heading'),1,1,1},{T('panel.tooltip.assignment_chooser'),0.9,0.9,0.9,true}},
   create={{T('panel.tooltip.create_wishlist_heading'),1,1,1},{T('panel.tooltip.create_wishlist_source'),0.9,0.9,0.9,true},
    {T('panel.tooltip.create_wishlist_draft'),0.75,0.75,0.75,true}},
   switch={{T('panel.tooltip.open_my_builds'),1,1,1},{T('panel.tooltip.my_builds_destination'),0.75,0.75,0.75,true},{' '},
    {'Character: PrototypeTester',0.85,0.85,0.85,true},{'Destination: Saved Build 1 - active in the game',0.85,0.85,0.85,true},
    {'Wishlist: Fixture plan',0.85,0.85,0.85,true}},
   lock={{T('panel.tooltip.locked_remaining'),1,1,1},{T('panel.tooltip.locked_plan'),0.9,0.9,0.9,true},
    {T('panel.tooltip.locked_acquire'),0.9,0.9,0.9,true},{T('panel.tooltip.locked_placement'),0.9,0.9,0.9,true},
    {T('panel.tooltip.locked_not_freeze'),0.9,0.9,0.9,true},{' '},{T('panel.tooltip.locked_acquire_list'),0.85,0.6,1},
    {BULLET..'Echo 80',0.85,0.7,1},{BULLET..'Gl\195\164nzend Echo',0.85,0.7,1},{' '},editor},
   need={{'Still needed this run',1,1,1},{'These wishlist Echoes have not been obtained yet.',0.9,0.9,0.9,true},{' '},
    {'When your wishlist Echoes are not on the board,',0.75,0.75,0.75,true},
    {'Nexus may take an off-Wishlist Echo when no eligible',0.75,0.75,0.75,true},
    {'target or search action is available. A later run may',0.75,0.75,0.75,true},
    {'improve the result; replacement is not guaranteed.',0.75,0.75,0.75,true},{' '},
    {'Missing Echoes:',1,0.65,0.25},{BULLET..'Echo 1',0.9,0.9,0.9},{'      Rare:x2',0.7,0.7,0.7},
    {BULLET..'Echo 2',0.9,0.9,0.9},{' '},editor},
  }
 end
 -- The three mapped buttons through their actual FontStrings and hovers
 -- (offline font models only; native fit, tooltips and clicks are NOT
 -- TESTED). A label holds its button text and keeps one line (SetWordWrap(false),
 -- at most the button height and at least one model line or that height)
 -- inside its resolved button box less the 6 px end caps on each side that
 -- the Wishlist editor's candidate buttons keep (115 px buttons, 103 px
 -- labels). Whether the client shortens it is the model text width against
 -- that label width; each case states it as a literal.
 local BUTTONS={assign='panel.button.assign_wishlist',create='panel.button.create_wishlist',switch='panel.button.my_builds'}
 local CAP=6
 local function Bounded(button,text,shortened,tag)
  local label=button:GetFontString()
  local line=G.model and G.model.line or 14
  local box=G.Rect(button,NexusPanel)
  check(label and label:GetText()==text and button:GetText()==text and label.wordWrap==false
   and label:GetHeight()<=button:GetHeight() and label:GetHeight()>=math.min(line,button:GetHeight())
   and G.Inside(G.Rect(label,NexusPanel),{box[1]+CAP,box[2],box[3]-CAP,box[4]})
   and (label:GetStringWidth()>label:GetWidth())==shortened,
   tag..': its actual FontString is one line inside the '..button:GetWidth()..'x'..button:GetHeight()
    ..' button less the end caps, '..(shortened and 'shortened there by the client' or 'whole'))
 end
 -- A button's actual registered hover as the tooltip receives it. clears: a
 -- synthetic SetOwner that drops every line added before it (an adversarial
 -- control; no native clearing or routing is claimed).
 local function Tooltip(button,clears)
  local lines,owners={},{}
  local add,own=rawget(GameTooltip,'AddLine'),rawget(GameTooltip,'SetOwner')
  rawset(GameTooltip,'AddLine',function(_,text,r,g,b,wrap)lines[#lines+1]={text,r,g,b,wrap}end)
  rawset(GameTooltip,'SetOwner',function(_,owner,anchor)
   owners[#owners+1]={owner,anchor}
   if clears then for i=#lines,1,-1 do lines[i]=nil end end
  end)
  GameTooltip:Hide()
  local ok,err=pcall(button:GetScript('OnEnter'),button)
  local shown=GameTooltip:IsShown()
  rawset(GameTooltip,'AddLine',add);rawset(GameTooltip,'SetOwner',own)
  assert(ok,err)
  local leave=button:GetScript('OnLeave');if leave then leave(button)end
  return lines,owners,shown==true and not GameTooltip:IsShown()
 end
 -- A mapped button's own hover with the plain and the clearing tooltip:
 -- exactly the wanted lines, the tooltip taken once, by the button itself at
 -- its existing ANCHOR_TOP, shown, and hidden again by its own leave.
 local function Hover(button,want,tag)
  for _,clears in ipairs({false,true})do
   local lines,owners,cycle=Tooltip(button,clears)
   check(same(lines,want) and #owners==1 and owners[1][1]==button and owners[1][2]=='ANCHOR_TOP' and cycle,
    tag..(clears and ' (synthetic SetOwner that clears earlier lines)' or ''))
  end
 end
 -- The complete label first, then every original line in its order, colour and wrap.
 local function WithLabel(T,tips,which)
  local out={{T(BUTTONS[which]),1,1,1,true}}
  for _,line in ipairs(tips[which])do out[#out+1]=line end
  return out
 end
 local function Verify(T,tag,recovered,bounded)
  local tips=Tips(T)
  assert(Nexus.Panel.Render(Setup()))
  local assign,create=Child(P.assign),Child(P.create)
  check(assign:IsShown() and create:IsShown() and assign:GetText()==T('panel.button.assign_wishlist')
   and create:GetText()==T('panel.button.create_wishlist'),tag..': the actual setup buttons show Assign Wishlist and Create Wishlist')
  for _,which in ipairs({'assign','create'})do
   local button=which=='assign' and assign or create
   local label=button:GetFontString()
   check(label and label:GetText()==T(BUTTONS[which]),'SETUP MODEL '..tag..': the '..BUTTONS[which]..' text is also the text of the button FontString')
   if bounded then Bounded(button,T(BUTTONS[which]),recovered,tag..': '..BUTTONS[which]) end
   Hover(button,recovered and WithLabel(T,tips,which) or tips[which],tag..': the actual '..BUTTONS[which]..' hover keeps its exact ordered lines, colours and wrap (nothing assigned until a choice; a draft, both save actions named)'
    ..(recovered and (which=='assign' and ', after the complete long label (a long label with a short body)' or ', after the complete label') or ', with no added line'))
  end
  assert(Nexus.Panel.Render(Active()))
  local switch,lock=NexusPanel._switchBtn,NexusPanel.toLockLabel
  check(switch:GetText()==T('panel.button.my_builds') and Region(P.progress):GetText()==T('panel.heading.progress')
   and Region(P.still):GetText()==T('panel.heading.still_needed') and Region(P.extra):GetText()==T('panel.heading.extra_copies')
   and lock:IsShown() and lock:GetText()==T('panel.heading.locked_targets'),tag..': My Builds, PROGRESS, STILL NEEDED, EXTRA COPIES and the lazily created LOCKED TARGETS')
  -- #143: while LOCKED TARGETS is shortened, its row's own hover shows the
  -- complete heading FIRST, then the 11 lines of Tips in their order.
  if recovered then table.insert(tips.lock,1,{T('panel.heading.locked_targets'),1,1,1,true}) end
  -- SUPPORTING PROBE, isolated from the plain-model check below (it reads
  -- tips.lock and changes no expectation): the actual locked-target row
  -- through the real Tooltip helper with its synthetic clearing SetOwner (no
  -- native clearing is claimed). There a hover that takes the tooltip a
  -- second time loses every line added before it, so this ownership and
  -- safety-line check runs ahead of the retained ordering check.
  do
   local lines,owners,cycle=Tooltip(NexusPanel.toLockHit,true)
   check(same(lines,tips.lock) and #owners==1 and owners[1][1]==NexusPanel.toLockHit
    and owners[1][2]=='ANCHOR_RIGHT' and cycle,tag..': SUPPORTING PROBE: with a synthetic SetOwner that clears earlier lines, the actual locked-target row takes the tooltip once (ANCHOR_RIGHT), shows and hides it, and keeps all 11 locked-target lines'
    ..(recovered and ', after the complete heading' or ', with no added heading'))
  end
  check(same(Lines(NexusPanel.toLockHit),tips.lock),tag..': the locked-target hover keeps six copies, the exact Echo and quality, ownership versus placement, locked slots versus Freeze, the untranslated names and the editor link')
  check(same(Lines(Child(P.need)),tips.need),tag..': the Still needed hover keeps its lines, the untranslated names and the shared editor link')
  local switchLabel=switch:GetFontString()
  check(switchLabel and switchLabel:GetText()==T('panel.button.my_builds'),'SETUP MODEL '..tag..': the My Builds text is also the text of the button FontString')
  if bounded then Bounded(switch,T('panel.button.my_builds'),recovered,tag..': panel.button.my_builds') end
  Hover(switch,recovered and WithLabel(T,tips,'switch') or tips.switch,tag..': the My Builds hover keeps its consequence, then the destination lines with the player and Wishlist names unchanged'
   ..(recovered and ', after the complete label' or ', with no added line'))
  for _,w in ipairs({{switch,'panel.button.my_builds',2},{Region(P.still),'panel.heading.still_needed',2},
   {Region(P.progress),'panel.heading.progress',1},{Region(P.extra),'panel.heading.extra_copies',1},
   {lock,'panel.heading.locked_targets',1},{assign,'panel.button.assign_wishlist',1},{create,'panel.button.create_wishlist',1}})do
   local sets,all=Sets(w[1]),true
   for _,value in ipairs(sets)do all=all and value==T(w[2]) end
   check(all and #sets>=w[3],tag..': every creation and render-reset SetText of '..w[2]..' shows it ('..#sets..' calls)')
  end
  check(NexusPanel._chargesText:IsShown() and NexusPanel._chargesText:GetWidth()==72,tag..': the compact charge row is shown in its 72 px box')
 end
 local function Effects()
  local id,initialized=Nexus.Localization.ActiveLanguage()
  return {db=F.Serialize(NexusDB),settings=H.Clone(Nexus.Store.Settings()),language=id,initialized=initialized,
   actions=#H.actions,sent=#H.sent,chat=#H.chat,popup=H.popup,auto=Nexus.RecomputeStats().autoEnabled,
   readOnly=Nexus.MainInternals.SavedRootReadOnlyV1(),warning=Nexus.OverwriteWarning.IsOpen()}
 end
 -- Narrow spies on the two existing destinations; nothing is opened, assigned or saved.
 local function Navigate()
  local journal,editor=Nexus.JournalTab,Nexus.WishlistEditor
  local openBuilds,show,calls=journal.OpenBuilds,editor.Show,{}
  journal.OpenBuilds=function(...)
   local shape={n=select('#',...)};for i=1,shape.n do shape[i]=type((select(i,...)))end
   calls[#calls+1]={'builds',shape};return true
  end
  editor.Show=function(...)calls[#calls+1]={'editor',select('#',...)}end
  local ok,err=pcall(function()
   NexusPanel._switchBtn:Click();Child(P.assign):Click();Child(P.create):Click()
   NexusPanel.toLockHit:GetScript('OnMouseUp')(NexusPanel.toLockHit)
   Child(P.need):GetScript('OnMouseUp')(Child(P.need))
  end)
  journal.OpenBuilds,editor.Show=openBuilds,show
  assert(ok,err)
  return calls
 end
 -- English: the shipped reviewed English base and the real packs, no hooks.
 Boot(nil,nil)
 for _,row in ipairs(KEYS)do
  check(Nexus.Localization.Kind(row[1])=='text' and Nexus.Localization.Text(row[1])==row[2],'SETUP FIXTURE: the real Localization copied the real reviewed English '..row[1])
 end
 local misses=Nexus.Localization.Diagnostics().misses
 assert(Nexus.Panel.Render(Setup()))
 for i,c in ipairs(NexusPanel.children)do
  if c.kind=='Button' and c:GetText()=='Assign Wishlist' then P.assign=i
  elseif c.kind=='Button' and c:GetText()=='Create Wishlist' then P.create=i end
 end
 assert(Nexus.Panel.Render(Active()))
 for i,r in ipairs(NexusPanel.regions)do
  local text=r:GetText()
  if text=='PROGRESS' then P.progress=i elseif text=='STILL NEEDED' then P.still=i elseif text=='EXTRA COPIES' then P.extra=i end
 end
 for i,c in ipairs(NexusPanel.children)do
  if c.kind=='Frame' and c~=NexusPanel.toLockHit and c:GetScript('OnEnter') and c:GetScript('OnMouseUp') then
   local first=Lines(c)[1];if first and first[1]=='Still needed this run' then P.need=i end
  end
 end
 check(P.assign and P.create and P.progress and P.still and P.extra and P.need,'SETUP #143: the real setup buttons, headings and Still needed hover were found')
 -- CONTROL on a synthetic button of this test, not a Panel widget: the real
 -- OneLineLabel owner hook runs after a button's own hover and takes the
 -- tooltip again. With the clearing SetOwner only the complete label is
 -- left, so the control tells a hover that keeps its body from one whose
 -- body a later SetOwner replaces.
 do
  local probe=CreateFrame('Button',nil,UIParent)
  probe:SetSize(68,19);probe:SetText(CAND['panel.button.my_builds'])
  probe:SetScript('OnEnter',function(self)GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:AddLine('Probe body',1,1,1);GameTooltip:Show()end)
  probe:SetScript('OnLeave',function()GameTooltip:Hide()end)
  local label=probe:GetFontString();label:SetWidth(56)
  Nexus.LayoutMetrics.OneLineLabel(label,probe,19,'ANCHOR_TOP')
  local full={CAND['panel.button.my_builds'],1,1,1,true}
  local plain,owners=Tooltip(probe,false)
  local cleared=Tooltip(probe,true)
  check(#owners==2 and same(plain,{{'Probe body',1,1,1},full}) and same(cleared,{full}),'CONTROL #143: the clearing SetOwner exposes an owner hook that replaces a button hover body with its label')
  probe:Hide()
 end
 local effects=Effects()
 Verify(ENT,'#143 English',false)
 check(NexusPanel._chargesText:GetText()=='B:0 R:? F:7','GUARD #143 English: the charge row shows 0, unknown and 7')
 check(Nexus.Localization.Diagnostics().misses==misses,'GUARD #143 English: the mapped calls record no fallback while the reviewed English is present')
 -- Both game-page routes now defer closing Plan until the game's button is
 -- available. The visible UI still reaches the same destinations once each.
 local NAV={{'builds',{n=2,'boolean','function'}},{'builds',{n=2,'boolean','function'}},{'editor',0},{'editor',0},{'editor',0}}
 local navEnglish=Navigate()
 check(same(navEnglish,NAV),'GUARD #143 English: the existing navigation callbacks reach the same destinations once each, with the same signatures')
 check(same(Effects(),effects),'GUARD #143 English: renders, hovers and navigation change no saved root, setting, language, action, send, chat, popup, consent or Auto')
 -- M7 missing-fact control: the My Builds hover words only the character
 -- Main captured into the model (model.character). Contrasting synthetic
 -- sources are set first: a counting live UnitName with another name, a
 -- stale previous model name committed by a real render and shown by the
 -- actual hover, and the Panel destination cache holding a third name. A
 -- model without the fact then keeps every other line unchanged, shows no
 -- Character line and no stale, cached or live name, and its hovers make no
 -- UnitName read. Hooks are restored on every path; nothing native is claimed.
 do
  local before=Effects()
  local tips=Tips(ENT)
  check(#tips.switch==6 and same(tips.switch[4],{'Character: PrototypeTester',0.85,0.85,0.85,true}),'SETUP #143 missing character: the positive My Builds expectation holds the captured character row fourth')
  local without={tips.switch[1],tips.switch[2],tips.switch[3],tips.switch[5],tips.switch[6]}
  local stale={tips.switch[1],tips.switch[2],tips.switch[3],{'Character: StaleModelName',0.85,0.85,0.85,true},tips.switch[5],tips.switch[6]}
  local P,switch=Nexus.Panel,NexusPanel._switchBtn
  local liveName,prior,reads=UnitName,P.CachedDestinationCharacter(),0
  local ok,err=pcall(function()
   UnitName=function()reads=reads+1;return 'LiveFallbackName','Ebonhold' end
   P.ObserveDestinationCharacter('CachedFixtureName','capture')
   check(P.CachedDestinationCharacter()=='CachedFixtureName' and UnitName('player')=='LiveFallbackName','SETUP #143 missing character: a contrasting live UnitName and a cached destination name are available')
   local named=Active();named.character='StaleModelName'
   assert(P.Render(named))
   check(P._lastModel.character=='StaleModelName','SETUP #143 missing character: a real render commits a stale previous model name')
   Hover(switch,stale,'SETUP #143 missing character: the actual My Builds hover shows the stale previous model name before the control')
   local missing=Active();missing.character=nil
   assert(P.Render(missing))
   check(missing.character==nil and P._lastModel.character==nil,'#143 missing character: the committed model holds no character; none is manufactured from the stale model, the cache or UnitName')
   reads=0
   Hover(switch,without,'#143 missing character: the actual My Builds hover keeps its consequence, destination and Wishlist lines in order, colour and wrap, with no Character line')
   local lines=Tooltip(switch,false)
   local leaked
   for _,line in ipairs(lines)do
    local text=tostring(line[1])
    if text:find('^Character') then leaked=text end
    for _,name in ipairs({'PrototypeTester','LiveFallbackName','StaleModelName','CachedFixtureName'})do
     if text:find(name,1,true) then leaked=text end
    end
   end
   check(#lines==#without and leaked==nil and reads==0,'#143 missing character: the emitted hover lines name no character (live, stale, cached or captured) and the hovers made no UnitName read ('..tostring(leaked)..', '..reads..' reads)')
  end)
  UnitName=liveName
  P.ObserveDestinationCharacter(prior,'capture')
  if not ok then error(err,0) end
  check(UnitName==liveName and P.CachedDestinationCharacter()==prior,'#143 missing character: the live UnitName and the destination cache are restored')
  assert(P.Render(Active()))
  Hover(switch,tips.switch,'#143 missing character: after the control the captured character row is shown again')
  check(same(Effects(),before),'#143 missing character: renders and hovers change no saved root, setting, language, action, send, chat, popup, consent or Auto')
 end
 -- Candidate: frFR holds distinct long accented candidates for all 21 meanings.
 Boot('frFR','candidate')
 local LZ=Nexus.Localization
 for _,row in ipairs(KEYS)do
  local text,source=LZ.Text(row[1])
  check(text==CAND[row[1]] and source=='candidate' and (LZ.Text(row[1],{}))==row[2] and (LZ.Resolve(row[1]))==row[2],
   'SETUP FIXTURE: the real Localization copied the frFR candidate; {} forces English and Resolve stays pure: '..row[1])
 end
 check(LZ.Format('readout.charge_counts',{banish={known=true,value=0},reroll={known=false},freeze={known=true,value=7}})==LONGROW,'SETUP FIXTURE: the long valid charge template was copied')
 effects=Effects();misses=LZ.Diagnostics().misses
 local message,fed=Nexus.UserText.Message,{}
 Nexus.UserText.Message=function(value,...)fed[#fed+1]=value;return message(value,...)end
 Verify(CANDT,'#143 candidate',true,true)
 for _,h in ipairs({{'_progressLabelHit',P.progress,'panel.heading.progress'},{'_needLabelHit',P.still,'panel.heading.still_needed'},
  {'_shedLabelHit',P.extra,'panel.heading.extra_copies'}})do
  local hit,label=NexusPanel[h[1]],Region(h[2])
  check(hit and hit:IsShown() and label.wordWrap==false and same(Lines(hit),{{CAND[h[3]],1,1,1,true}}),'#143 candidate: '..h[3]..' is one line and its actual hover recovers the complete heading')
 end
 check(NexusPanel.toLockLabel.wordWrap==false,'#143 candidate: LOCKED TARGETS is one line; its own row hover recovered it above')
 local uiScale=rawget(UIParent,'GetEffectiveScale')
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double})do
  for _,ui in ipairs({1,0.64})do
   G.UseFont(model);rawset(UIParent,'GetEffectiveScale',function()return ui end)
   check(Nexus.LayoutMetrics.RuntimeMetrics()==model.size/12,'SETUP #143 fit, '..model.name..', UI scale '..ui..': the runtime font scale is the stated model size over 12 ('..model.size..'/12)')
   local tag='#143 fit, '..model.name..', UI scale '..ui
   assert(Nexus.Panel.Render(Setup()))
   local layout=NexusPanel._responsiveLayout
   local assign,create=Child(P.assign),Child(P.create)
   check(NexusPanel:GetWidth()==272 and layout.boxes.setupAssign.w==146 and assign:GetWidth()==146 and assign:GetHeight()==layout.boxes.setupAssign.h
    and create:GetWidth()==146 and create:GetHeight()==layout.boxes.setupCreate.h and assign:GetText()==CAND['panel.button.assign_wishlist']
    and create:GetText()==CAND['panel.button.create_wishlist'],tag..': the setup buttons keep their fixed boxes and the selected text')
   local tips=Tips(CANDT)
   for _,which in ipairs({'assign','create'})do
    local button=which=='assign' and assign or create
    Bounded(button,CAND[BUTTONS[which]],true,tag..': '..BUTTONS[which])
    Hover(button,WithLabel(CANDT,tips,which),tag..': the actual '..BUTTONS[which]..' hover recovers the complete label, then every original line')
   end
   assert(Nexus.Panel.Render(Active()))
   layout=NexusPanel._responsiveLayout
   local box,panel=layout.boxes,{0,0,NexusPanel:GetWidth(),NexusPanel:GetHeight()}
   local switch=NexusPanel._switchBtn
   check(NexusPanel:GetWidth()==272 and switch:GetWidth()==68 and switch:GetHeight()==19 and switch:GetText()==CAND['panel.button.my_builds'],tag..': My Builds keeps its 68x19 box and the selected text')
   Bounded(switch,CAND['panel.button.my_builds'],true,tag..': panel.button.my_builds')
   Hover(switch,WithLabel(CANDT,tips,'switch'),tag..': the actual My Builds hover recovers the complete label, then its consequence and destination lines')
   for _,h in ipairs({{Region(P.progress),box.progressHeader,'panel.heading.progress',NexusPanel._progressLabelHit},
    {Region(P.still),box.needed,'panel.heading.still_needed',NexusPanel._needLabelHit},
    {Region(P.extra),box.shed,'panel.heading.extra_copies',NexusPanel._shedLabelHit},
    {NexusPanel.toLockLabel,box.toLock,'panel.heading.locked_targets',NexusPanel.toLockHit}})do
    local label=h[1]
    check(label:GetText()==CAND[h[3]] and label.wordWrap==false and label:GetWidth()==h[2].w and label:GetHeight()==layout.small
     and G.Inside(G.Rect(label,NexusPanel),panel) and Nexus.LayoutMetrics.Shortened(label),tag..': '..h[3]..' stays one line in its unchanged layout box, shortened there')
    if h[4]==NexusPanel.toLockHit then
     -- #143: the locked-target row owns its hover alone. Through the real
     -- Tooltip helper with the plain and the synthetic clearing SetOwner (no
     -- native clearing is claimed): one SetOwner by the actual row at
     -- ANCHOR_RIGHT, shown and hidden again, the complete heading FIRST, then
     -- the 11 lines of the independent Tips(CANDT).lock.
     local body=Tips(CANDT).lock
     local want={{CAND[h[3]],1,1,1,true}}
     for _,line in ipairs(body)do want[#want+1]=line end
     for _,clears in ipairs({false,true})do
      local lines,owners,cycle=Tooltip(h[4],clears)
      check(#body==11 and same(lines,want) and #owners==1 and owners[1][1]==h[4] and owners[1][2]=='ANCHOR_RIGHT' and cycle,
       tag..': the actual hover of '..h[3]..' takes the tooltip once, recovers the complete heading first, then keeps all 11 locked-target lines'
       ..(clears and ' (synthetic SetOwner that clears earlier lines)' or ''))
     end
    else
     local lines=Lines(h[4])
     check(same(lines[#lines],{CAND[h[3]],1,1,1,true}),tag..': the actual hover of '..h[3]..' recovers the complete text')
    end
   end
   local charges=NexusPanel._chargesText
   check(charges:IsShown() and charges:GetText()==LONGROW and charges:GetWidth()==72 and charges:GetHeight()==layout.small
    and Nexus.LayoutMetrics.Shortened(charges) and G.Inside(G.Rect(charges,NexusPanel),G.Rect(NexusPanel._rollArea,NexusPanel)),tag..': the long valid charge row stays in its unchanged 72 px box')
   local lines=Lines(NexusPanel._chargesHover)
   check(same(lines[1],{'Charges',1,1,1}) and same(lines[2],{LONGROW,1,1,1,true}),tag..': the actual charge hover recovers the complete row')
  end
 end
 rawset(UIParent,'GetEffectiveScale',uiScale)
 local frames=#H.frames
 local warm={}
 for _,button in ipairs({NexusPanel._switchBtn,Child(P.assign),Child(P.create)})do
  warm[#warm+1]={button,button:GetFontString(),#button.regions,#button.children,button:GetScript('OnEnter'),button:GetScript('OnLeave')}
 end
 for i=1,3 do
  local model=Active();model.progress.owned=3+i;model.progress.missing={'Echo 1 (Rare:x2)','Echo '..(10+i)}
  local pristine=H.Clone(model)
  assert(Nexus.Panel.Render(model));assert(Nexus.Panel.Render(H.Clone(Nexus.Panel._lastModel)))
  check(same(model,pristine),'#143 candidate: Render leaves the raw model untouched ('..i..')')
 end
 Nexus.Panel.Hide();Nexus.Panel.Show()
 Lines(NexusPanel._switchBtn);Lines(NexusPanel.toLockHit);Lines(NexusPanel._chargesHover)
 check(#H.frames==frames and NexusPanel._switchBtn:GetText()==CAND['panel.button.my_builds'] and Region(P.still):GetText()==CAND['panel.heading.still_needed']
  and NexusPanel.toLockLabel:GetText()==CAND['panel.heading.locked_targets'],'#143 candidate: changed models, copied re-renders, hovers and reopen reuse warm widgets and keep the selected text')
 local reused=true
 for _,w in ipairs(warm)do
  reused=reused and w[2]~=nil and w[1]:GetFontString()==w[2] and #w[1].regions==w[3] and #w[1].children==w[4]
   and w[1]:GetScript('OnEnter')==w[5] and w[1]:GetScript('OnLeave')==w[6]
 end
 check(reused,'#143 candidate: repeated layouts, hovers and reopen keep each mapped button with its one FontString, the same regions and children and its own registered OnEnter and OnLeave; no label, frame or hook is added')
 Bounded(NexusPanel._switchBtn,CAND['panel.button.my_builds'],true,'#143 candidate after reuse: panel.button.my_builds')
 Hover(NexusPanel._switchBtn,WithLabel(CANDT,Tips(CANDT),'switch'),'#143 candidate after reuse: the actual My Builds hover gives the complete label once, then its own lines')
 for _,w in ipairs({{NexusPanel._switchBtn,'panel.button.my_builds'},{Region(P.progress),'panel.heading.progress'},
  {Region(P.still),'panel.heading.still_needed'},{Region(P.extra),'panel.heading.extra_copies'},{NexusPanel.toLockLabel,'panel.heading.locked_targets'},
  {Child(P.assign),'panel.button.assign_wishlist'},{Child(P.create),'panel.button.create_wishlist'}})do
  local sets,all=Sets(w[1]),true
  for _,value in ipairs(sets)do all=all and value==CAND[w[2]] end
  check(all and #sets>=1,'#143 candidate: every SetText of '..w[2]..' kept the selected text: no English reset, double conversion or markup')
 end
 check(same(Navigate(),navEnglish),'#143 candidate: identical navigation destinations, signatures and counts under the selected language')
 Nexus.UserText.Message=message
 local fedSelected=false
 for _,value in ipairs(fed)do for _,text in pairs(CAND)do if value==text then fedSelected=true end end end
 check(#fed>0 and not fedSelected,'#143 candidate: UserText.Message receives only raw producer text, never a selected Panel text')
 check(LZ.InitializeActiveLanguage('deDE')=='frFR' and LZ.ActiveLanguage()=='frFR','GUARD #143: the fixed session keeps its language')
 check(LZ.Diagnostics().misses==misses,'#143 candidate: the mapped calls record no fallback')
 check(same(Effects(),effects),'#143 candidate: renders, hovers, reopen and navigation change no saved root, setting, language, action, send, chat, popup, consent or Auto')
 -- Fallback: deDE without valid entries for the 21 meanings shows reviewed English.
 Boot('deDE','fallback')
 LZ=Nexus.Localization
 local refused
 for _,row in ipairs(LZ.Diagnostics().packs.rows)do if row.id=='deDE' then refused=row.rejected end end
 check(refused==11,'SETUP FIXTURE: the real Localization refused the eleven invalid deDE entries at load')
 for _,row in ipairs(KEYS)do
  local text,source,reason=LZ.Text(row[1])
  check(text==row[2] and source=='base' and reason=='missing_candidate','SETUP FIXTURE: a missing or refused deDE entry falls back to reviewed English: '..row[1])
 end
 local diagnostics=LZ.Diagnostics()
 Verify(ENT,'#143 fallback',false,true)
 for _,h in ipairs({'_progressLabelHit','_needLabelHit','_shedLabelHit'})do
  check(same(Lines(NexusPanel[h]),{}),'#143 fallback: a reviewed English heading that fits adds no hover line ('..h..')')
 end
 local after=LZ.Diagnostics()
 check(after.byReason.unknown_key==diagnostics.byReason.unknown_key and after.byReason.invalid_key==diagnostics.byReason.invalid_key
  and after.byReason.missing_candidate>diagnostics.byReason.missing_candidate,'#143 fallback: only missing-candidate fallbacks, never a raw key, blank or unavailable status')
 -- Fitting-English control at every font model and both UI scales, with
 -- literal expectations from the visible characters at each model width
 -- against the 56 px and 134 px label bounds: My Builds (9) and the setup
 -- labels (15) fit the default face and 0.75; with the 16 px face only My
 -- Builds is shortened; at 2.0 all three are. A label that fits adds no
 -- hover line; a shortened one adds only its complete label, first.
 local FITS={{G.MODELS.default,true,true},{G.MODELS.px16,false,true},{G.MODELS.small,true,true},{G.MODELS.double,false,false}}
 local scaled=rawget(UIParent,'GetEffectiveScale')
 for _,fit in ipairs(FITS)do
  for _,ui in ipairs({1,0.64})do
   G.UseFont(fit[1]);rawset(UIParent,'GetEffectiveScale',function()return ui end)
   check(Nexus.LayoutMetrics.RuntimeMetrics()==fit[1].size/12,'SETUP #143 English fit, '..fit[1].name..', UI scale '..ui..': the runtime font scale is the stated model size over 12 ('..fit[1].size..'/12)')
   local tag='#143 English fit, '..fit[1].name..', UI scale '..ui
   local tips=Tips(ENT)
   assert(Nexus.Panel.Render(Setup()))
   for _,which in ipairs({'assign','create'})do
    local button=which=='assign' and Child(P.assign) or Child(P.create)
    Bounded(button,EN[BUTTONS[which]],not fit[3],tag..': '..BUTTONS[which])
    Hover(button,fit[3] and tips[which] or WithLabel(ENT,tips,which),tag..': the actual '..BUTTONS[which]..' hover'..(fit[3] and ' adds no line' or ' adds only the complete label, first'))
   end
   assert(Nexus.Panel.Render(Active()))
   Bounded(NexusPanel._switchBtn,EN['panel.button.my_builds'],not fit[2],tag..': panel.button.my_builds')
   Hover(NexusPanel._switchBtn,fit[2] and tips.switch or WithLabel(ENT,tips,'switch'),tag..': the actual My Builds hover'..(fit[2] and ' adds no line' or ' adds only the complete label, first'))
  end
 end
 rawset(UIParent,'GetEffectiveScale',scaled)
 -- GUARD: the real charge rows of the six real packs, unchanged (no fixture).
 local ROWS={frFR='Ban:0 Rel:? Gel:7',deDE='Verb:0 Neu:? Einfr:7',esES='Dest:0 Rel:? Cong:7',plPL='Wygn:0 Przel:? Zamr:7',
  ptBR='Banir:0 Rolar:? Cong:7',ruRU='\208\152\208\183\208\179:0 \208\159\208\181\209\128:? \208\151\208\176\208\188:7'}
 for _,id in ipairs({'frFR','deDE','esES','plPL','ptBR','ruRU'})do
  Boot(id,nil)
  assert(Nexus.Panel.Render(Active()))
  -- #143 GUARD with the real copied pack: the actual locked-target row
  -- through the real Tooltip helper with its synthetic clearing SetOwner (no
  -- native clearing is claimed), against this pack's own input entries in the
  -- independent Tips shape with the untranslated names: one SetOwner by the
  -- row, all 11 lines, and the complete heading first only while the actual
  -- heading is wider than its box.
  local entries,lock=Nexus.LocalizationPacks[id].entries,NexusPanel.toLockLabel
  local lockBody,lockWant=Tips(function(key)return entries[key]end).lock,{}
  if lock:IsShown() and lock:GetStringWidth()>lock:GetWidth() then lockWant[1]={entries['panel.heading.locked_targets'],1,1,1,true} end
  for _,line in ipairs(lockBody)do lockWant[#lockWant+1]=line end
  local lockLines,lockOwners,lockCycle=Tooltip(NexusPanel.toLockHit,true)
  check(#lockBody==11 and lock:GetText()==entries['panel.heading.locked_targets'] and same(lockLines,lockWant) and #lockOwners==1
   and lockOwners[1][1]==NexusPanel.toLockHit and lockOwners[1][2]=='ANCHOR_RIGHT' and lockCycle,
   'GUARD #143 real '..id..': the actual locked-target row takes the tooltip once and keeps all 11 locked-target lines in the pack text'
   ..(#lockWant>#lockBody and ', after the complete heading' or ', with no added heading'))
  local charges=NexusPanel._chargesText
  check(charges:IsShown() and charges:GetText()==ROWS[id] and charges:GetWidth()==72 and charges:GetHeight()==NexusPanel._responsiveLayout.small,'GUARD #143 real '..id..' pack: Panel._chargesText shows 0, unknown and 7 in its unchanged 72 px box')
  local want={{'Charges',1,1,1},{ROWS[id],1,1,1,true}}
  for _,line in ipairs(Nexus.Readout.ChargesLegend())do want[#want+1]={line,0.85,0.85,0.85,true}end
  check(same(Lines(NexusPanel._chargesHover),want),'GUARD #143 real '..id..': the actual _chargesHover carries the complete row and the unchanged English legend')
 end
 -- The explicit coverage-literal exception, checked last so a pre-binding
 -- Panel first fails on its mapped consumers above.
 local SCOPE='Only selected main-panel labels and tooltips, status messages and the compact charge-count row are translated; other Nexus text stays English. Translations are drafts pending fluent and native review.'
 local easy,items=EasyMenu,nil
 local before=Effects()
 EasyMenu=function(list)items=list end
 NexusPanel._menuBtn:Click()
 EasyMenu=easy
 local language,found,stale
 for _,item in ipairs(items or {})do if type(item.text)=='string' and item.text:find('^Language')then language=item end end
 for _,row in ipairs(language and language.menuList or {})do
  if row.text==SCOPE and row.disabled==true and row.notCheckable==true then found=true end
  if tostring(row.text):find('six messages',1,true)then stale=true end
 end
 check(found and not stale and same(Effects(),before),'#143: the actual Language menu states the bounded coverage exactly, without the six-message claim, and opening it writes nothing')
end

print('PASS terminology actual consumer checks='..checks..'; native rendering not asserted')
