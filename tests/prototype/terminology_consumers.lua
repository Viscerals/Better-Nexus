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
-- normalization, untouched raw inputs and no side effect. RED before the
-- seam: Nexus.Localization is absent.
local L=assert(Nexus.Localization,'localization seam loaded before its consumers');checks=checks+1
local function same(a,b,seen)
 if type(a)~='table' or type(b)~='table' then return a==b end
 seen=seen or {};if seen[a] then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a)do if not same(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
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
 Nexus.Panel.SetStatus(code);check(Nexus.Panel._lastModel.status==english,'status-only update: '..code)
 Nexus.Panel.SetStatus(Nexus.UserText.Message(code));check(Nexus.Panel._lastModel.status==english,'reviewed English passed back to SetStatus stays exact: '..code)
 check(Nexus.Readout.Status({text=code})==english and Nexus.Readout.Status({text=code,level=12})=='Lv 12 - '..english,'Readout status line: '..code)
 check(Nexus.Readout.AutoHoldText(code)==english and Nexus.Readout.AutoHoldNote(code):find('Paused: '..english,1,true),'Readout Auto hold line: '..code)
end
check(L.Resolve('reason.list_preparing',{['reason.list_preparing']='Fixture list text'})=='Fixture list text','fixture candidate resolves only when injected')
local plain=H.Clone(Nexus.Panel._lastModel);plain.status='CURSOR_REQUIRED';plain.recommendation='CURSOR_REQUIRED'
assert(Nexus.Panel.Render(plain))
check(texts():find('This list is still being prepared',1,true) and not texts():find('Fixture list text',1,true),'the panel never selects an injected candidate')
check(L.Diagnostics().misses==before.misses,'the normal consumer path records no fallback')
check(#H.actions==before.actions and #H.sent==before.sent and H.popup==before.popup and #H.chat==before.chat,'no game action, Sync send, consent popup or chat line')
check(Nexus.RecomputeStats().autoEnabled==before.auto and same(Nexus.Store.Settings(),settings0),'Automation selection and settings unchanged')
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
 -- Side effects that presentation must not have: a game action, a Sync send
 -- through the harness network APIs or a packet admitted to the Sync
 -- transport, a chat line, a StaticPopup, the Auto consent warning, or a
 -- change of the Auto selection or of the settings. Only the harness and
 -- read-only accessors are read.
 check(type(Nexus.Sync.Stats())=='table' and type(Nexus.OverwriteWarning.IsOpen)=='function','fixture: the Sync transport counters and the consent warning state are readable')
 local function effects()
  return {actions=#H.actions,sent=#H.sent,queued=tonumber(Nexus.Sync.Stats().admittedPackets) or 0,
   chat=#H.chat,popup=H.popup,warning=Nexus.OverwriteWarning.IsOpen()==true,
   auto=Nexus.RecomputeStats().autoEnabled,settings=H.Clone(Nexus.Store.Settings())}
 end
 local function unchanged(a,b)
  return a.actions==b.actions and a.sent==b.sent and a.queued==b.queued and a.chat==b.chat
   and a.popup==b.popup and a.warning==b.warning and a.auto==b.auto and same(a.settings,b.settings)
 end
 local function packed(...)return {n=select('#',...),...} end
 -- A direct presentation call, enclosed: none of those effects may occur across it.
 local function quiet(label,fn,...)
  local before=effects()
  local result=packed(fn(...))
  check(unchanged(before,effects()),'no game action, send, queued packet, chat line, popup, Automation or settings change: '..label)
  return unpack(result,1,result.n)
 end
 -- The two presentation entry points the real runtime calls (Main's render
 -- and its onStatus), each call enclosed the same way and its raw input
 -- recorded; the real functions are called through. The runtime calls them
 -- inside pcall, so a violation is counted here and checked by the caller.
 local function instrument()
  local log={render={},status={},calls=0,loud=0}
  local render,setStatus=Nexus.Panel.Render,Nexus.Panel.SetStatus
  local function enclosed(fn,...)
   local before=effects()
   local result=packed(pcall(fn,...))
   log.calls=log.calls+1
   if not unchanged(before,effects())then log.loud=log.loud+1 end
   if not result[1] then error(result[2],0) end
   return unpack(result,2,result.n)
  end
  Nexus.Panel.Render=function(model,...)
   if type(model)=='table'then log.render[#log.render+1]={status=model.status,recommendation=model.recommendation}end
   return enclosed(render,model,...)
  end
  Nexus.Panel.SetStatus=function(value,...)log.status[#log.status+1]=value;return enclosed(setStatus,value,...)end
  function log.restore()Nexus.Panel.Render,Nexus.Panel.SetStatus=render,setStatus end
  return log
 end
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
  check(log.calls>0 and log.loud==0,'runtime wait: every presentation call the real runtime made was quiet')
  return log
 end
 local raws,message={},Nexus.UserText.Message
 Nexus.UserText.Message=function(value,...)raws[tostring(value)]=true;return message(value,...)end
 runtimeWait({{spellId=200001,quality=1},{spellId=200020,quality=0}})
 local m3,shown3=H.Clone(Nexus.Panel._lastModel),texts()
 runtimeWait({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200022,quality=1}},true)
 Nexus.UserText.Message=message
 check(raws['waiting: waiting for three-card board'] and raws['waiting: waiting for pending-pick count'],'runtime: the onStatus path receives the raw wait status bytes')
 check(raws['waiting for three-card board'] and raws['waiting for pending-pick count'],'runtime: the panel recommendation carries the raw planner reason')
 check(m3.status==W3 and m3.recommendation==W3 and shown3:find(W3,1,true) and not shown3:find('three-card',1,true),'runtime: the three-card wait reaches the panel model and fontstrings in English')
 check(Nexus.Panel._lastModel.status==WP and Nexus.Panel._lastModel.recommendation==WP and texts():find(WP,1,true),'runtime: an unavailable horizon waits; the pending-pick text keeps its exact lower-case bytes')
 check(#H.actions==acted and Nexus.RecomputeStats().autoEnabled==auto,'runtime: a wait performs nothing and leaves Automation as it was')
 local again=H.Clone(Nexus.Panel._lastModel);assert(quiet('re-render of the converted model',Nexus.Panel.Render,again))
 check(Nexus.Panel._lastModel.status==WP and Nexus.Panel._lastModel.recommendation==WP,'rendering the converted model again is stable')
 quiet('hide and reopen',function()Nexus.Panel.Hide();Nexus.Panel.Show()end)
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
 quiet('INJECTION: hide and reopen',function()Nexus.Panel.Hide();Nexus.Panel.Show()end)
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
 -- synchronously, outside the update loop: no time advances and no Sync,
 -- scheduler or lifecycle work runs, so a whole producer step is held to no
 -- side effect. The same steps run twice with the same runtime state, inputs
 -- and time: with the shipped English seam, then with the injected candidate
 -- pack. A first take step brings the runtime status, the logged board and
 -- the panel model to the same state before each run; the waits after it
 -- are compared. Raw producer behavior must be identical; only the
 -- presented bytes may differ.
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
  local run={time=H.now,misses=L.Diagnostics().misses,quiet={},presented={},planned={}}
  local policyDecide=Nexus.Policy.Decide
  Nexus.Policy.Decide=function(state,...)
   local action=policyDecide(state,...)
   run.planned[#run.planned+1]=type(action)=='table' and (tostring(action.type)..'|'..tostring(action.reason)) or 'none'
   return action
  end
  local log=instrument()
  run.quiet[1],run.start=explicitStep(start)
  run.startPlanned,run.planned,log.render,log.status=run.planned[1],{},{},{}
  for i,step in ipairs(controlSteps)do run.quiet[i+1],run.presented[i]=explicitStep(step.cards,step.noCount)end
  log.restore();Nexus.Policy.Decide=policyDecide
  run.render,run.status,run.calls,run.loud=log.render,log.status,log.calls,log.loud
  run.misses=L.Diagnostics().misses-run.misses
  return run
 end
 local english=controlled(false)
 local candidate=controlled(true)
 local held=true
 for i=1,#controlSteps+1 do held=held and english.quiet[i]==true and candidate.quiet[i]==true end
 check(held,'matched control: each explicit real runtime step ran with no game action, send, queued packet, chat line, popup, Automation or settings change, in English and with the candidate')
 check(english.calls>0 and english.loud==0 and candidate.loud==0 and english.calls==candidate.calls,'matched control: each presentation call inside those steps was quiet, as often in both runs')
 check(english.time==candidate.time and english.startPlanned==candidate.startPlanned and tostring(english.startPlanned):find('^take|')~=nil
  and english.start.status==candidate.start.status and english.start.recommendation==candidate.start.recommendation,
  'matched control: the same time and take start, presented alike, before both runs')
 local waits={'waiting for three-card board','waiting for pending-pick count','waiting for three-card board'}
 local planned,statuses,inputs={},{},{}
 for i,reason in ipairs(waits)do planned[i],statuses[i]='wait|'..reason,'waiting: '..reason;inputs[i]=english.render[i] and english.render[i].recommendation end
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
print('PASS terminology actual consumer checks='..checks..'; native rendering not asserted')
