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
 assert(quiet('earlier #123 distinct status Render',Nexus.Panel.Render,distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP Render stores a distinct status before SetStatus: '..code)
 check(quiet('earlier #123 raw status',Nexus.Panel.SetStatus,code)==true and Nexus.Panel._lastModel.status==english,'GUARD raw SetStatus updates to exact English: '..code)
 check(quiet('earlier #123 repeated raw status',Nexus.Panel.SetStatus,code)==false and Nexus.Panel._lastModel.status==english,'GUARD repeated SetStatus reports no update: '..code)
 assert(quiet('earlier #123 independent distinct status Render',Nexus.Panel.Render,distinct))
 check(Nexus.Panel._lastModel.status==prior and prior~=english,'SETUP independent Render before onStatus double conversion: '..code)
 check(quiet('earlier #123 English SetStatus',Nexus.Panel.SetStatus,Nexus.UserText.Message(code))==true and Nexus.Panel._lastModel.status==english,'GUARD onStatus double conversion updates exact English: '..code)
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
  ['reason.saved_data_reading']='Reading your saved data'}
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
 check(Row(menu,'enUS') and text:find('Only six messages are translated: five status messages and the Banish/Reroll/Freeze count row',1,true) and text:find('other Nexus text stays English',1,true) and not text:find('three status messages',1,true),'English and the partial six-message result are listed')
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
