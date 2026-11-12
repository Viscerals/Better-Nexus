-- M2 (UX-02): with the Auto selection OFF, the HUD says the player chooses,
-- marks exactly the one card the runtime's recommendation takes and names it
-- in an unstepped recommendation; stepped recommendations keep their own
-- names; no card is guessed when the target is not definite (none, or the
-- same Echo offered twice); no marker survives a new board. Auto ON, paused
-- and waiting headings and texts are unchanged, and a selected-but-held Auto
-- is never shown as OFF. The compact charges row formats only charge facts
-- the model itself carries; unknown is "?", never 0.
-- EXPECT: behaviour added in M2 (fails on the accepted M1 cut). GUARD:
-- unchanged behaviour (Auto ON body/cards exactly as hud_roll_footprint pins
-- them, no actor call with Auto OFF, no service read from rendering).
-- SETUP: fixture state. Real TOC boot, runtime, policy and Panel; synthetic
-- boards and saved data only. Direct Panel.Render calls use a copy of the
-- runtime's own last model with one field changed (consumer coverage only).
-- R6 is the producer control (M2-charge): real harness run data -> the
-- runtime's single Adapter.Charges read per decision -> panel model -> Main
-- view model -> Panel, with read/request/action counts held to a measured
-- baseline. Its EXPECTs fail on the M2 partial cut, which has the consumer
-- but no producer (no charges line from a real decision).
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_manual_recommendation')
local H,A,observer
local PLAN={}
for i=1,12 do PLAN[#PLAN+1]={spellId=200000+i,quality=i%4,stacks=1} end

-- opt (optional): plan, a synthetic plan in place of PLAN; before(H), run on
-- the fresh harness before its boot (synthetic catalog names).
local function Boot(opt)
 opt=opt or {}
 local plan=opt.plan or PLAN
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Synthetic plan',verified=true,echoes=plan}}
 if opt.before then opt.before(H) end
 H.Boot();A=Nexus.GameAdapter
 assert(A.SetLoadoutWishlistIdentity(1,'Synthetic plan',plan),'assign the plan')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide() end
 Nexus.Panel.Show();H.Advance(.5)
 observer=V.PresentationObserver(H)
end
local function Plain(t) return V.Plain(t) end
-- The HUD's roll area as the player sees it: heading, the shown choices (in
-- order), body and the charges line. Only shown widgets count: a hidden card
-- row keeps its last text but is not on screen. The Play offer cards (Claude
-- Design full UI) replace the shown rows with the same current choices; each
-- shown card is read from its visible name, quality and tag lines. A choice
-- carries the manual (Auto OFF) Take marker when its shown row starts ">> "
-- or its shown card's tag is the Wishlist pick (ux_automation_scope's
-- ManualMarker). facts[i] keeps a card's visible lines apart. freezes[i]:
-- the shown choice is visibly identified as a Freeze target (its shown row
-- starts "[Freeze] " or its shown card's tag starts "> Freeze"), which is
-- never the Take marker.
local function View()
 local f=NexusPanel
 local cards,marks,facts,freezes={},{},{},{}
 local tag=Nexus.Readout and Nexus.Readout.OFFER_PICK_TAG
 -- Only what is visible: a hidden roll area shows no card at all.
 if f._rollArea:IsVisible() then
  for _,r in ipairs(f._rollArea.regions or {}) do
   if r.kind=='FontString' and r~=f._rollStatus and r~=f._rollRec and r~=f._chargesText
    and r:IsShown() and Plain(r:GetText() or '')~='' then
    local text=Plain(r:GetText())
    cards[#cards+1]=text;marks[#cards]=text:find('^>> ')~=nil
    freezes[#cards]=text:find('^%[Freeze%] ')~=nil
    facts[#cards]={row=text}
   end
  end
  for _,card in ipairs(f._offerCards or {}) do
   if card:IsShown() then
    local name,quality,shown=Plain(card.name:GetText() or ''),Plain(card.quality:GetText() or ''),Plain(card.tag:GetText() or '')
    local parts={}
    for _,text in ipairs({name,quality,shown}) do if text~='' then parts[#parts+1]=text end end
    cards[#cards+1]=table.concat(parts,' ')
    marks[#cards]=type(tag)=='string' and shown==tag
    freezes[#cards]=shown:find('^> Freeze')~=nil
    facts[#cards]={name=name,quality=quality,tag=shown}
   end
  end
 end
 local charges=f._chargesText
 return {head=Plain(f._rollStatus:GetText() or ''),body=Plain(f._rollRec:GetText() or ''),cards=cards,marks=marks,
  facts=facts,freezes=freezes,charges=charges and charges:IsShown() and Plain(charges:GetText() or '') or nil,roll=f._rollArea:IsShown()}
end
local function Marked(v)
 local n,at=0,nil
 for i=1,3 do if v.marks[i] then n=n+1;at=i end end
 return n,at
end
local function Frozen(v)
 local n,at=0,nil
 for i=1,3 do if v.freezes[i] then n=n+1;at=i end end
 return n,at
end
-- A shown choice is this Echo at this quality: its visible card name and
-- quality lines, or a shown row's "Name (Quality)" text.
local function Shows(v,i,name,quality)
 local f=v.facts[i]
 if not f then return false end
 if f.row then return f.row:find(name..' ('..quality..')',1,true)~=nil end
 return f.name==name and f.quality==quality
end
local function Offer(cards) H.Board(cards);H.Notify();H.Advance(1.2) end
local function Acts(kind) local n=0;for _,a in ipairs(H.actions) do if not kind or a[1]==kind then n=n+1 end end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Render(change)
 local model=H.Clone(Nexus.Panel._lastModel)
 change(model)
 assert(observer.Quiet('direct Render',Nexus.Panel.Render,model)~=false,'render')
 return View(),model
end
-- Count disclosure (approved main-panel design: "Counts stay behind Details",
-- the compact charges among them). The charges are counts: with Details
-- closed, as the panel opens, View().charges is nil (no row is shown) although
-- the model carries the facts; the row and its hover are the open Details
-- view's. The charge scenarios (R5, R6, R9) therefore observe the closed
-- panel first, run their format, hover and producer checks with Details
-- open, and observe the closed panel again afterwards.
-- Details is the panel's own memory-only state (Panel._playDetails, what its
-- Details control toggles): setting it saves nothing and runs no refresh
-- step, so the measured read, request and action counts are untouched; the
-- next render shows it. WithDetails puts it back as it was, also when its
-- part raises, so no later scenario part runs with Details left open.
-- Redraw renders the committed model again, unchanged (consumer redraw only:
-- no decision, read or request), to show the panel in the current state.
local function WithDetails(fn)
 local P=Nexus.Panel
 local was=P._playDetails
 P._playDetails=true
 local ok,err=pcall(fn)
 P._playDetails=was
 if not ok then error(err,0) end
end
local function Redraw() return (Render(function() end)) end

C.scenario('R1 Auto OFF, unstepped Take: you choose, one marked card, named target',function()
 Boot()
 C.setup(not Auto(),'R1: fixture: Auto is OFF')
 local acts=Acts()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local v=View()
 local m=Nexus.Panel._lastModel
 print('OBSERVED','R1 head=['..v.head..'] body=['..v.body..'] cards=['..table.concat(v.cards,' | ')..']')
 C.setup(v.roll and #v.cards==3 and m and m.cards and m.cards[1] and m.cards[1].highlight==true
  and not m.cards[2].highlight and not m.cards[3].highlight,'R1: fixture: the runtime marks card 1 as its Take target')
 C.expect(v.head:find('Auto OFF',1,true)~=nil and v.head:find('you choose',1,true)~=nil and v.head:find('Slot 1',1,true)~=nil
  and not v.head:find('active',1,true),'R1: the heading says Auto OFF, you choose, and claims no active rolling',v.head)
 local n,at=Marked(v)
 C.expect(n==1 and at==1 and Shows(v,1,'Echo 1','Uncommon'),'R1: exactly the chosen card is marked',table.concat(v.cards,' | '))
 C.expect(v.body:find('Take a needed Echo',1,true)~=nil and v.body:find('Echo 1 (Uncommon)',1,true)~=nil,
  'R1: the unstepped recommendation names its target and keeps its reason',v.body)
 C.guard(Acts()==acts and not Auto(),'R1: Auto OFF performs nothing; the recommendation only shows')
 -- A2 changing choice: the next board's target is card 3; no stale marker.
 Offer({{spellId=200060,quality=1},{spellId=200061,quality=2},{spellId=200003,quality=3}})
 v=View()
 n,at=Marked(v)
 C.expect(n==1 and at==3 and not v.marks[1] and Shows(v,3,'Echo 3','Epic'),'R1: the marker follows the new board; none stays on the old position',
  table.concat(v.cards,' | '))
 C.expect(v.body:find('Echo 3 (Epic)',1,true)~=nil and not v.body:find('Echo 1',1,true),'R1: the body names the new target only',v.body)
 -- The same Echo offered twice: both are the target; no card is guessed.
 Offer({{spellId=200002,quality=2},{spellId=200002,quality=2},{spellId=200062,quality=0}})
 v=View()
 m=Nexus.Panel._lastModel
 n=Marked(v)
 C.setup(m.cards[1].highlight==true and m.cards[2].highlight==true,'R1: fixture: two identical offers are both the Take target')
 C.expect(v.head:find('you choose',1,true)~=nil and n==0 and not v.body:find('(Rare)',1,true),
  'R1: with two equal targets no card is marked and none is named',v.body)
 -- No needed offer: Reroll/Banish name no card; nothing is marked.
 Offer({{spellId=200070,quality=1},{spellId=200071,quality=2},{spellId=200072,quality=3}})
 v=View()
 n=Marked(v)
 C.expect(v.head:find('you choose',1,true)~=nil and n==0,'R1: a recommendation with no Take target marks no card',v.body)
 C.guard(v.body~='' and not v.body:find(': Echo',1,true),'R1: its reason is shown without a guessed target',v.body)
 C.guard(Acts()==acts and not Auto(),'R1: across every board, Auto OFF performed nothing')
end)

C.scenario('R2 stepped recommendations keep their own names; no Take: no marker',function()
 Boot()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local acts=Acts()
 local stepped='1. Freeze Echo 5\n2. Take Echo 1'
 local v=Render(function(m) m.recommendation=stepped end)
 C.guard(v.body==Plain(stepped),'R2: a stepped recommendation is shown exactly as the runtime names it',v.body)
 C.expect(v.head:find('you choose',1,true)~=nil,'R2: the Auto OFF heading applies to stepped recommendations too',v.head)
 v=Render(function(m) for _,c in ipairs(m.cards) do c.highlight=nil end end)
 C.guard(Marked(v)==0,'R2: without a runtime target no card is marked (no first-card default)')
 C.guard(Acts()==acts,'R2: rendering performs nothing')
end)

C.scenario('R3 Auto ON unchanged; held Auto is never labelled OFF',function()
 Boot()
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 C.setup(Auto(),'R3: fixture: Auto is ON')
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local v=View()
 C.guard(v.body=='Take a needed Echo' and #v.cards==3 and v.cards[1]:find('Echo 1 ',1,true)==1 and Marked(v)==0,
  'R3: with Auto ON the body and card rows are exactly as before (no marker, no added name)',v.body..' | '..(v.cards[1] or ''))
 C.guard(not v.head:find('Auto OFF',1,true),'R3: the Auto ON heading never says OFF',v.head)
 -- Selected but held: the paused heading, never OFF, no marker.
 local held=Render(function(m) m.auto=true;m.paused='waiting for current Echo data';m.effective={state='paused'} end)
 C.guard(held.head=='Auto ON — paused' and Marked(held)==0,'R3: a held Auto shows its paused heading, not OFF, and no marker',held.head)
 local waiting=Render(function(m) m.auto=true;m.paused='waiting';m.effective={state='waiting',hold=true} end)
 C.guard(waiting.head=='Auto waiting' and not waiting.head:find('OFF',1,true),'R3: a waiting Auto is named as the wait',waiting.head)
end)

C.scenario('R4 no Echo choice: the plain line, no marker, no action',function()
 Boot()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local acts=Acts()
 H.Board({});H.Notify();H.Advance(.6)
 local v=View()
 C.guard(Marked(v)==0 and (not v.roll or v.body=='' or v.body=='No Echo choice is showing.' or v.head=='Roll status'),
  'R4: with no choice on screen, no card is marked and no old recommendation is shown',v.head..' | '..v.body)
 C.guard(Acts()==acts and not Auto(),'R4: nothing is performed')
end)

C.scenario('R5 compact charges: only supplied facts; unknown is not zero; no service read',function()
 Boot()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local reads=0
 local charges=A.Charges
 A.Charges=function(...) reads=reads+1;return charges(...) end
 local acts,sent=Acts(),#H.sent
 local closed,closedModel=Render(function(m) m.charges={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true} end)
 C.expect(Nexus.Panel._playDetails~=true and closed.charges==nil and not NexusPanel._chargesHover:IsShown()
  and type(closedModel.charges)=='table' and closedModel.charges.banish==2,
  'R5: with Details closed the supplied charges are carried by the model and not shown: no row and no hover',tostring(closed.charges))
 WithDetails(function()
 local v=Render(function(m) m.charges={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true} end)
 C.expect(v.charges=='B:2 R:1 F:0','R5: supplied charges are shown compactly',v.charges)
 v=Render(function(m) m.charges={banish=0,reroll=0,freeze=0,trustworthy=false,arrived=false} end)
 C.expect(v.charges=='B:? R:? F:?','R5: charges the game has not reported are unknown, not 0',v.charges)
 v=Render(function(m) m.charges={banish=3,reroll=nil,freeze=1,trustworthy=false,arrived=true} end)
 C.expect(v.charges=='B:3 R:? F:1 ~','R5: a missing count is unknown and untrusted counts are marked estimated',v.charges)
 v=Render(function(m) m.charges=nil end)
 C.guard(v.charges==nil,'R5: without charge facts in the model no charges line is shown')
 C.guard(reads==0 and Acts()==acts and #H.sent==sent,'R5: rendering charges reads no charge service and performs or sends nothing')
 A.Charges=charges
 local R=Nexus.Readout
 C.expect(R.ChargesLine and R.ChargesLine({banish=1,reroll=2,freeze=3})=='B:1 R:2 F:3'
  and R.ChargesLine(nil)=='' and R.ChargesLine({banish=-1,reroll=0/0,freeze=1/0})=='B:? R:? F:?',
  'R5: the formatter keeps only finite non-negative counts')
 -- Issue #142: the row is rendered by the named template. INJECTION EVIDENCE
 -- only: a test wrapper passes a non-shipped fixture pack into the real
 -- formatter; this is not active-language startup or chooser evidence.
 local seam=Nexus.Localization
 C.setup(type(seam)=='table' and type(seam.Format)=='function','R5: fixture: the localization seam has the formatter')
 local wrap={}
 for key,value in pairs(seam or {}) do wrap[key]=value end
 wrap.Format=function(key,arguments) return seam.Format(key,arguments,{['readout.charge_counts']='G:{freeze} R:{reroll} B:{banish}'}) end
 local supplied={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true}
 local function Fresh(c) Render(function(x) x.charges=nil end);return Render(function(x) x.charges=c end) end
 Nexus.Localization=wrap
 local v1,m1=Fresh(H.Clone(supplied))
 local committed1=H.Clone(Nexus.Panel._lastModel.charges)
 local v2=Render(function(x) x.charges=H.Clone(supplied) end)
 Nexus.Localization=seam
 local switched=Render(function(x)x.charges=H.Clone(supplied)end)
 C.guard(switched.charges=='B:2 R:1 F:0','R5: unchanged counts refresh after presentation changes without a clearing render',switched.charges)
 Nexus.Localization=wrap
 local est=Fresh({banish=2,reroll=nil,freeze=0,trustworthy=false,arrived=true})
 local unk=Fresh({banish=5,reroll=5,freeze=5,trustworthy=false,arrived=false})
 Nexus.Localization=seam
 local back=Fresh(H.Clone(supplied))
 -- Issue #143 boundary, made explicit. The Panel now shows its reviewed
 -- labels through Nexus.Localization.Text, a TOC-loaded core module it
 -- requires (the chosen direct route has no fallback of its own). The charge
 -- row keeps Readout's own optional formatter, which is what this no-seam
 -- case characterizes. So the case is split: Readout.ChargesLine runs with
 -- no Localization module at all, and the actual Panel renders with the real
 -- seam's Text and IsText but no Format. Both take the real Readout fallback
 -- (it needs a Format function); nothing is stubbed or normalized.
 local bareInput=H.Clone(supplied)
 Nexus.Localization=nil
 local bare=Nexus.Readout.ChargesLine(bareInput)
 local bareEstimate=Nexus.Readout.ChargesLine({banish=2,reroll=nil,freeze=0,trustworthy=false,arrived=true})
 local bareUnknown=Nexus.Readout.ChargesLine({banish=5,reroll=5,freeze=5,trustworthy=false,arrived=false})
 local bareModule=Nexus.Localization
 Nexus.Localization=seam
 local noFormat={}
 for key,value in pairs(seam or {}) do noFormat[key]=value end
 noFormat.Format=nil
 C.setup(bareModule==nil and type(seam)=='table' and type(seam.Format)=='function' and noFormat.Format==nil
  and noFormat.Text==seam.Text and noFormat.IsText==seam.IsText,
  'R5: fixture: Readout ran with no Localization module; the Panel seam keeps the real Text and IsText and lacks only Format')
 Nexus.Localization=noFormat
 local absent=Fresh(H.Clone(supplied))
 Nexus.Localization=seam
 C.expect(v1.charges=='G:0 R:1 B:2' and m1.charges.banish==2 and m1.charges.reroll==1 and m1.charges.freeze==0,
  'R5: INJECTION: a reordered fixture renders through the real formatter and Panel; the counts keep their slots',v1.charges)
 C.guard(V.Same(m1.charges,supplied),'R5: the supplied caller facts remain unchanged')
 C.guard(V.Same(committed1,supplied),'R5: the committed model retains the supplied count facts')
 C.guard(v2.charges=='G:0 R:1 B:2','R5: re-rendering the same facts is stable',v2.charges)
 C.expect(est.charges=='G:0 R:? B:2 ~' and unk.charges=='G:? R:? B:?',
  'R5: INJECTION: unknown stays ? and the code-owned ~ follows the whole row',tostring(est.charges)..' | '..tostring(unk.charges))
 C.guard(back.charges=='B:2 R:1 F:0' and absent.charges=='B:2 R:1 F:0',
  'R5: the shipped English row on the actual Panel is unchanged with the real seam and with the real Text but no formatter',tostring(back.charges)..' | '..tostring(absent.charges))
 C.guard(bare=='B:2 R:1 F:0' and bareEstimate=='B:2 R:? F:0 ~' and bareUnknown=='B:? R:? F:?' and V.Same(bareInput,supplied),
  'R5: with no Localization module the real Readout fallback keeps the English row: unknown is ?, ~ follows the whole row, the caller facts are untouched',
  tostring(bare)..' | '..tostring(bareEstimate)..' | '..tostring(bareUnknown))
 end)
 local again=Render(function(m) m.charges={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true} end)
 C.expect(Nexus.Panel._playDetails~=true and again.charges==nil and not NexusPanel._chargesHover:IsShown(),
  'R5: closed again, the same supplied charges show no row and no hover',tostring(again.charges))
end)


C.scenario('R5 full text recovery and degraded English template',function()
 Boot()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local seam=Nexus.Localization
 local long=string.rep('Long reordered charges ',7)..'G:{freeze} R:{reroll} B:{banish}'
 local wanted=string.rep('Long reordered charges ',7)..'G:0 R:1 B:2 ~'
 local wrapped={};for k,v in pairs(seam)do wrapped[k]=v end
 wrapped.Format=function(key,args)return seam.Format(key,args,{['readout.charge_counts']=long})end
 local hiddenRow=Render(function(m)m.charges={banish=2,reroll=1,freeze=0,arrived=true,trustworthy=false}end)
 C.expect(Nexus.Panel._playDetails~=true and hiddenRow.charges==nil and not NexusPanel._chargesHover:IsShown(),
  'R5: with Details closed the charge row and its hover are not on the panel',tostring(hiddenRow.charges))
 WithDetails(function()
 Nexus.Localization=wrapped
 Render(function(m)m.charges={banish=2,reroll=1,freeze=0,arrived=true,trustworthy=false}end)
 local hover=NexusPanel._chargesHover
 local lines,ok=observer.Quiet('actual full-text hover',V.TooltipLines,hover:GetScript('OnEnter'),hover)
 local joined=table.concat(lines,'\n')
 C.expect(ok and joined:find(wanted,1,true)~=nil,'R5: actual charge hover recovers the complete reordered row and estimate marker',joined)
 local rec=string.rep('A long recommendation with complete context. ',8)
 Render(function(m)m.recommendation=rec end)
 -- The base harness has a constant 14px measurement. Use the existing
 -- offline word-wrap model for this actual overflow callback (not native fit).
 local geometry=dofile('tests/prototype/layout_geometry_support.lua')
 local label=NexusPanel._rollRec;local height=rawget(label,'GetStringHeight')
 label.GetStringHeight=function(self)return geometry.Rows(self:GetText(),self:GetWidth(),5.5)*12 end
 hover=NexusPanel._recommendationHover
 lines,ok={},false
 if hover and hover:GetScript('OnEnter')then lines,ok=observer.Quiet('actual full-text hover',V.TooltipLines,hover:GetScript('OnEnter'),hover)end
 rawset(label,'GetStringHeight',height)
 joined=table.concat(lines,'\n')
 C.expect(ok and joined:find(rec,1,true)~=nil,'R5: actual recommendation hover recovers the complete current text',joined)
 -- A newly loaded real seam with a broken English template, then absent base.
 for _,base in ipairs({{['readout.charge_counts']='broken {banish}'},{}})do
  local data=Nexus.LocalizationEnglish;Nexus.LocalizationEnglish=base
  dofile('core/Localization.lua')
  Nexus.LocalizationEnglish=data
  local broken=Nexus.Localization;local before=broken.Diagnostics()
  local row=Nexus.Readout.ChargesLine({banish=2,freeze=0,arrived=true,trustworthy=false})
  local after=broken.Diagnostics()
  C.expect(row=='B:2 R:? F:0 ~','R5: an unavailable template retains legacy English counts and estimate semantics',row)
  C.guard(after.misses==before.misses+1 and after.byReason.unknown_key==before.byReason.unknown_key+1,'R5: unavailable English template records exactly one diagnostic')
 end
 Nexus.Localization=seam
 Render(function(m)m.charges={banish=2,reroll=1,freeze=0};m.recommendation='waiting for three-card board'end)
 C.guard(NexusPanel._chargesText:GetText()=='B:2 R:1 F:0','R5: normal English committed display restored')
 end)
 local hiddenAgain=Redraw()
 C.expect(Nexus.Panel._playDetails~=true and hiddenAgain.charges==nil and not NexusPanel._chargesHover:IsShown(),
  'R5: closed again, the restored English row and its hover are not on the panel',tostring(hiddenAgain.charges))
end)

-- Producer integration (M2-charge): the charges the runtime's own decision
-- read (StepRun's single Adapter.Charges call, observed through the policy
-- state it is passed into) reach the HUD through the real Main view model and
-- Panel, with no extra read, request or action. Run data is the harness's
-- PlayerRunService table; a new table is a fresh push for the adapter ledger.
C.scenario('R6 producer: the runtime\'s own charge read reaches the HUD (Auto OFF)',function()
 Boot()
 C.setup(not Auto(),'R6: fixture: Auto is OFF')
 local decided,reads,used,getter=0,0,nil,0
 local decide,charges=Nexus.Policy.Decide,A.Charges
 Nexus.Policy.Decide=function(state,...) decided=decided+1;used=state and state.charges;return decide(state,...) end
 A.Charges=function(...) reads=reads+1;return charges(...) end
 local service=ProjectEbonhold.PlayerRunService
 local current=service.GetCurrentData
 service.GetCurrentData=function(...) getter=getter+1;return current(...) end
 local function Step() Nexus.RequestRecompute();H.Advance(.6) end
 local function Shown() local v=View();return v.charges end
 local function Same(model,read)
  return type(model)=='table' and type(read)=='table' and model.banish==read.banish and model.reroll==read.reroll
   and model.freeze==read.freeze and model.trustworthy==read.trustworthy and model.arrived==read.arrived
 end
 local acts,auto=Acts(),Auto()
 -- Baseline: what one HUD re-render reads before any charge fact exists.
 local g0,r0=getter,reads
 Nexus.RefreshHudView()
 local baseline={getter=getter-g0,reads=reads-r0}
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 C.setup(decided>0 and type(used)=='table' and used.arrived==true and used.banish==20,
  'R6: fixture: the runtime decided on the board with the harness run data (20/20/10)',decided)
 C.guard(reads==decided,'R6: each decision reads charges exactly once (no extra read)',reads..' reads / '..decided..' decisions')
 local closedLine=Shown()
 C.expect(Nexus.Panel._playDetails~=true and closedLine==nil and Same(Nexus.Panel._lastModel.charges,used),
  'R6: with Details closed the charges this decision read are carried by the model and not shown on the HUD',tostring(closedLine))
 WithDetails(function()
 Redraw()
 local line=Shown()
 print('OBSERVED','R6 known charges='..tostring(line))
 C.expect(line=='B:20 R:20 F:10' and Same(Nexus.Panel._lastModel.charges,used),
  'R6: the HUD shows the charges this decision read, unchanged in value',line)
 -- Changed run data (a fresh push): the next decision's read is shown.
 H.run={remainingBanishes=7,totalRerolls=20,usedRerolls=15,totalFreezes=10,usedFreezes=9}
 Step()
 line=Shown()
 C.guard(reads==decided,'R6: still one read per decision after a push',reads..' / '..decided)
 C.expect(line=='B:7 R:5 F:1' and Same(Nexus.Panel._lastModel.charges,used),'R6: changed counts refresh the HUD',line)
 -- Upstream limitation: a partial push is already normalized by the
 -- adapter into decision zeros. This guard is characterization, not proof of
 -- server-known per-field zero counts or freshness.
 H.run={remainingBanishes=5}
 Step()
 C.guard(used.arrived==true and used.reroll==0 and used.freeze==0
  and Shown()=='B:5 R:0 F:0','R6: partial-push adapter coercion remains an explicit upstream limitation',Shown())
 -- Run data not reported: unknown, never a known 0.
 H.run={}
 Step()
 line=Shown()
 C.setup(type(used)=='table' and used.arrived==false,'R6: fixture: the adapter reports the counts as not arrived')
 C.expect(line=='B:? R:? F:?' and not (line or ''):find('0',1,true),'R6: unreported charges are shown as unknown, not 0',line)
 -- A legacy-synthesized push: estimated counts stay marked.
 H.run={remainingBanishes=1,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}
 Step()
 line=Shown()
 C.setup(type(used)=='table' and used.trustworthy==false and used.arrived==true,'R6: fixture: the adapter marks these counts untrusted')
 C.expect(line=='B:1 R:0 F:0 ~','R6: untrusted counts are marked estimated',line)
 -- Re-rendering the HUD with its charge facts reads exactly what the baseline
 -- re-render read (no charge read at all), and requests, performs and sends nothing.
 local before={reads=reads,getter=getter,granted=H.grantedRequests,slots=H.slotRequests,acts=Acts(),sent=#H.sent}
 Nexus.RefreshHudView()
 C.guard(baseline.reads==0 and reads==before.reads and getter-before.getter==baseline.getter
  and H.grantedRequests==before.granted and H.slotRequests==before.slots
  and Acts()==before.acts and #H.sent==before.sent,
  'R6: a HUD re-render makes no charge read and no host read, request, action or send beyond its baseline',
  'getter '..(getter-before.getter)..' vs baseline '..baseline.getter)
 -- No stale counts: between boards, and with Auto ON, nothing is shown.
 H.run={remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}
 H.Board({});H.Notify();Step()
 C.guard(Shown()==nil and Nexus.Panel._lastModel.charges==nil,'R6: without a board no charges are shown or carried')
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 C.expect(Shown()=='B:20 R:20 F:10','R6: the next board shows its own fresh read',Shown())
 -- INJECTION EVIDENCE only (a non-shipped fixture through the real formatter):
 -- the producer still reads charges once per decision and keeps its raw data.
 local seam=Nexus.Localization
 local wrapped={}
 for key,value in pairs(seam or {}) do wrapped[key]=value end
 wrapped.Format=function(key,arguments) return seam.Format(key,arguments,{['readout.charge_counts']='G:{freeze} R:{reroll} B:{banish}'}) end
 local push={remainingBanishes=3,totalRerolls=20,usedRerolls=18,totalFreezes=10,usedFreezes=9}
 Nexus.Localization=wrapped
 H.run=push
 local observed=observer.Instrument()
 observed.Run(Step)
 line=Shown()
 Nexus.Localization=seam
 C.expect(line=='G:1 R:2 B:3' and Same(Nexus.Panel._lastModel.charges,used),
  'R6: INJECTION: the runtime\'s own read renders through the real formatter; the model keeps the read counts',line)
 C.guard(push.remainingBanishes==3 and push.usedRerolls==18 and push.usedFreezes==9 and reads==decided,
  'R6: formatting changes no run data and adds no read',reads..' / '..decided)
 H.run={remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}
 observed=observer.Instrument();observed.Run(Step)
 C.guard(Shown()=='B:20 R:20 F:10','R6: the shipped English row returns with the real seam',Shown())
 end)
 Redraw()
 C.expect(Nexus.Panel._playDetails~=true and Shown()==nil and type(Nexus.Panel._lastModel.charges)=='table',
  'R6: closed again, the charges stay in the model and leave the HUD',tostring(Shown()))
 C.guard(Acts()==acts and Auto()==auto,'R6: Auto OFF throughout: no action was performed and Auto is unchanged')
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 C.setup(Auto(),'R6: fixture: Auto is ON')
 Offer({{spellId=200002,quality=2},{spellId=200052,quality=0},{spellId=200053,quality=1}})
 C.guard(Shown()==nil and Nexus.Panel._lastModel.charges==nil,'R6: with Auto ON the panel carries and shows no charges (unchanged)')
 C.guard(reads==decided,'R6: one read per decision throughout',reads..' / '..decided)
 Nexus.Policy.Decide,A.Charges,service.GetCurrentData=decide,charges,current
end)

-- UX-02/J4 successor (#131 all41 canonical UX-02: "Auto OFF heading never
-- says active", "Two Needed cards -> exactly one marked and named", "No
-- engine name in recommendations"). Real TOC boot, adapter, policy, runtime
-- and Panel widgets; synthetic boards, plans, Orb service and run data only.
-- Effects() is everything presentation must leave alone: game actions
-- (uploads included), sends, assignment calls, settings and Auto.
local function Ser(v,seen)
 seen=seen or {}
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
 return '{'..table.concat(o,',')..'}'
end
local assigned=0
local function CountAssignments()
 assigned=0
 for _,n in ipairs({'SetLoadoutWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity'}) do
  local real=A[n]
  if type(real)=='function' then A[n]=function(...) assigned=assigned+1;return real(...) end end
 end
end
local function Effects()
 return {acts=Acts(),sent=#H.sent,assigned=assigned,settings=Ser(Nexus.Store.Settings()),auto=Auto()}
end
local function SameEffects(a,b)
 return a.acts==b.acts and a.sent==b.sent and a.assigned==b.assigned and a.settings==b.settings and a.auto==b.auto
end
-- Every visible text of the HUD (recommendation, status, heading, cards).
local function VisibleText()
 local out={}
 for _,f in ipairs(H.frames) do
  if f.IsVisible and f:IsVisible() then
   local value=f.GetText and f:GetText();if type(value)=='string' then out[#out+1]=Plain(value) end
   for _,r in ipairs(f.regions or {}) do if r:IsShown() and r.GetText then
    value=r:GetText();if type(value)=='string' then out[#out+1]=Plain(value) end
   end end
  end
 end
 return table.concat(out,'\n')
end
local function EngineFree(text) return not text:find('EchoWeaver',1,true) and not text:lower():find('experimental',1,true) end
local function Line(d) return d and (tostring(d.type)..':'..tostring(d.index)..':'..tostring(d.spellId)..':'..tostring(d.reasonCode)) or 'nil' end
-- The real policy's last decision (observed, not changed).
local function WatchDecisions()
 local decide=Nexus.Policy.Decide
 local w={}
 Nexus.Policy.Decide=function(...) local d=decide(...);w.last=d;return d end
 function w.Stop() Nexus.Policy.Decide=decide end
 return w
end

C.scenario('R7 Auto OFF with Orb guidance: the heading says you choose, never Active; reason and Open Orbs remain',function()
 Boot()
 CountAssignments()
 C.setup(not Auto(),'R7: fixture: Auto is OFF')
 -- A synthetic Orb service whose state the game cannot confirm.
 ProjectEbonhold.OrbService={IsStateKnown=function() return false end,IsOfferPending=function() return false end}
 local e0=Effects()
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 for _=1,3 do Nexus.RequestRecompute();H.Advance(.4) end
 local v=View()
 local m=Nexus.Panel._lastModel
 local g=type(m.orbGuidance)=='table' and m.orbGuidance or {}
 local button=NexusPanel._orbsBtn
 print('OBSERVED','R7 head=['..v.head..'] body=['..v.body..'] guide='..tostring(g.state))
 C.setup(m.auto==false and m.paused==nil and g.state=='orb-state' and g.openOrbs==true and #v.cards==3,
  'R7: fixture: Auto OFF (not held), an unknown Orb state with inspection guidance, and the board shown',tostring(g.state))
 -- The short one-line form beside the Orb guidance (orb_guidance_geometry
 -- pins its fit): who chooses and the destination.
 C.expect(not v.head:find('Active',1,true) and v.head:lower():find('you choose',1,true)~=nil and v.head:find('Slot 1',1,true)~=nil,
  'R7: the heading says the player chooses, with the destination, never Active',v.head)
 C.guard(button and button:IsShown(),'R7: the Open Orbs button for inspection remains')
 C.guard(v.body:find('Ordinary rolling paused',1,true)~=nil,'R7: the Orb pause reason remains in the body',v.body)
 C.guard(Marked(v)==0 and Frozen(v)==0,'R7: a wait marks no card')
 C.guard(not (NexusOrbPanel and NexusOrbPanel:IsShown()),'R7: nothing opens by itself')
 C.guard(SameEffects(Effects(),e0),'R7: no action, send, assignment, setting or Auto change')
 -- Control: the same Orb state with Auto ON keeps its paused heading.
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 for _=1,3 do Nexus.RequestRecompute();H.Advance(.4) end
 v=View()
 C.setup(Auto(),'R7: fixture: Auto is ON')
 C.guard(v.head:find('Auto ON',1,true)~=nil and v.head:find('paused',1,true)~=nil and not v.head:find('Active',1,true),
  'R7: with Auto ON the Orb hold keeps its paused heading',v.head)
 C.guard(button:IsShown(),'R7: and its Open Orbs button')
 C.guard(Acts()==e0.acts,'R7: the held Auto performed nothing')
 ProjectEbonhold.OrbService=nil
end)

C.scenario('R8 Auto OFF, two different Needed offers: the Freeze target is named and identified as a Freeze',function()
 Boot()
 CountAssignments()
 C.setup(not Auto(),'R8: fixture: Auto is OFF')
 local w=WatchDecisions()
 local e0=Effects()
 Offer({{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200050,quality=2}})
 local v=View()
 local m=Nexus.Panel._lastModel
 print('OBSERVED','R8 decision='..Line(w.last)..' head=['..v.head..'] body=['..v.body..'] cards=['..table.concat(v.cards,' | ')..']')
 C.setup(w.last and w.last.type=='freeze' and w.last.reasonCode=='PAIR_FREEZE_SECOND_NEEDED' and w.last.index==1
  and w.last.spellId==200001,'R8: fixture: the real adaptive decision Freezes card 1 of two different Needed offers',Line(w.last))
 C.setup(m.charges and m.charges.freeze==10 and m.charges.trustworthy==true and #v.cards==3,
  'R8: fixture: trusted Freeze charges and the board shown')
 local n,at=Frozen(v)
 C.expect(n==1 and at==1 and Shows(v,1,'Echo 1','Uncommon'),'R8: exactly the Freeze target is visibly identified as a Freeze',
  table.concat(v.cards,' | '))
 C.guard(Marked(v)==0,'R8: no card carries the Take marker: a Freeze is not a Wishlist pick',table.concat(v.cards,' | '))
 C.expect(v.body:find('Echo 1 (Uncommon)',1,true)~=nil and v.body:lower():find('freeze',1,true)~=nil
  and not v.body:find('Echo 2',1,true) and not v.body:find('Take',1,true),
  'R8: the recommendation names its Freeze target with Freeze wording, not Take',v.body)
 C.guard(v.head:find('you choose',1,true)~=nil and not v.head:find('Active',1,true),'R8: the heading says the player chooses',v.head)
 C.expect(EngineFree(VisibleText()),'R8: no engine name in any visible recommendation or status text',v.body)
 C.guard(m.cards[1].highlight~=true and m.cards[2].highlight~=true,'R8: the Take highlight (automation target) is not set for a Freeze')
 -- The one-line rows (the fallback without a built layout) hold the same
 -- identification, never the Take marker. Hidden rows keep their text.
 local rows={}
 for _,r in ipairs(NexusPanel._rollArea.regions or {}) do
  local text=r.kind=='FontString' and Plain(r:GetText() or '') or ''
  if text:find('^%[Freeze%] ') or text:find('^>> ') then rows[#rows+1]=text end
 end
 C.expect(#rows==1 and rows[1]:find('[Freeze] Echo 1 (Uncommon)',1,true)==1,'R8: the fallback row identifies the same Freeze card',table.concat(rows,' | '))
 -- Re-rendering the same decision changes nothing saved and performs nothing.
 local db=Ser(NexusDB)
 Nexus.RefreshHudView()
 C.guard(Ser(NexusDB)==db,'R8: a HUD re-render writes no saved data')
 C.guard(SameEffects(Effects(),e0),'R8: Auto OFF performed, sent and assigned nothing; settings and Auto unchanged')
 -- Auto ON consumer (held, so it cannot act): no Freeze or Take marker is added.
 local held=Render(function(x) x.auto=true;x.paused='waiting for current Echo data';x.effective={state='paused'} end)
 C.guard(Frozen(held)==0 and Marked(held)==0 and held.head=='Auto ON — paused','R8: a held Auto shows its paused heading and no marker',held.head)
 C.expect(EngineFree(held.body),'R8: the held Auto body has no engine name',held.body)
 local waiting=Render(function(x) x.auto=true;x.paused='waiting';x.effective={state='waiting',hold=true} end)
 C.guard(waiting.head=='Auto waiting' and Frozen(waiting)==0,'R8: a waiting Auto is named as the wait, no marker',waiting.head)
 Nexus.RefreshHudView()
 -- Reordered board: the decision's own target, not the first card.
 Offer({{spellId=200050,quality=2},{spellId=200003,quality=3},{spellId=200004,quality=0}})
 v=View()
 C.setup(w.last and w.last.type=='freeze' and w.last.index==2 and w.last.spellId==200003,'R8: fixture: reordered, the decision Freezes card 2',Line(w.last))
 n,at=Frozen(v)
 C.expect(n==1 and at==2 and Shows(v,2,'Echo 3','Epic') and not v.freezes[1],'R8: the Freeze mark follows the decision on a new board',
  table.concat(v.cards,' | '))
 C.expect(v.body:find('Echo 3 (Epic)',1,true)~=nil and not v.body:find('Echo 1',1,true),'R8: the body names the new target only',v.body)
 -- Ordinary Take board: the Take marker, no Freeze mark survives.
 Offer({{spellId=200060,quality=1},{spellId=200061,quality=2},{spellId=200005,quality=1}})
 v=View()
 C.setup(w.last and w.last.type=='take' and w.last.spellId==200005,'R8: fixture: one Needed offer, a Take',Line(w.last))
 n,at=Marked(v)
 C.guard(n==1 and at==3 and Frozen(v)==0,'R8: an ordinary Take keeps its Wishlist pick marker; no Freeze mark remains',table.concat(v.cards,' | '))
 C.guard(v.body:find('Take a needed Echo',1,true)~=nil and v.body:find('Echo 5 (Uncommon)',1,true)~=nil,'R8: and its named Take recommendation',v.body)
 -- No choice: nothing marked.
 H.Board({});H.Notify();H.Advance(.6)
 v=View()
 C.guard(Marked(v)==0 and Frozen(v)==0,'R8: with no choice nothing is marked')
 C.guard(SameEffects(Effects(),e0),'R8: across every board nothing was performed, sent or assigned')
 w.Stop()
end)

C.scenario('R9 Freeze controls: duplicate same Echo, unknown charges and a long name',function()
 -- The same Echo needed twice and offered twice: the decision Freezes one
 -- copy, but the two cards are the same Echo; no card is guessed.
 local plan={}
 for _,e in ipairs(PLAN) do plan[#plan+1]={spellId=e.spellId,quality=e.quality,stacks=e.spellId==200003 and 2 or 1} end
 Boot({plan=plan})
 CountAssignments()
 local w=WatchDecisions()
 local e0=Effects()
 Offer({{spellId=200003,quality=3},{spellId=200003,quality=3},{spellId=200050,quality=2}})
 local v=View()
 C.setup(w.last and w.last.type=='freeze' and w.last.reasonCode=='PAIR_FREEZE_SECOND_NEEDED' and w.last.spellId==200003,
  'R9: fixture: two copies of an Echo needed twice: the decision Freezes one',Line(w.last))
 C.guard(Frozen(v)==0 and Marked(v)==0,'R9: with two equal targets no card is marked',table.concat(v.cards,' | '))
 C.guard(not v.body:find('(Epic)',1,true) and v.body~='','R9: and none is named; the reason is still shown',v.body)
 C.expect(EngineFree(VisibleText()),'R9: the unnamed Freeze reason has no engine name',v.body)
 C.guard(SameEffects(Effects(),e0),'R9: nothing performed')
 w.Stop()
 -- Unknown charges: the policy cannot Freeze; the ordinary Take stays.
 Boot()
 CountAssignments()
 w=WatchDecisions()
 e0=Effects()
 H.run={}
 Offer({{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200050,quality=2}})
 v=View()
 local unreported=Nexus.Panel._lastModel and Nexus.Panel._lastModel.charges
 C.expect(Nexus.Panel._playDetails~=true and v.charges==nil and type(unreported)=='table' and unreported.arrived==false,
  'R9: with Details closed the unreported charges are carried by the model and not shown',tostring(v.charges))
 WithDetails(function()
  local open=Redraw()
  C.setup(w.last and w.last.type=='take' and open.charges=='B:? R:? F:?','R9: fixture: unreported charges, the decision is a Take',Line(w.last)..' '..tostring(open.charges))
 end)
 v=Redraw()
 C.expect(Nexus.Panel._playDetails~=true and v.charges==nil,'R9: closed again, the unreported charges show no row',tostring(v.charges))
 local n,at=Marked(v)
 C.guard(n==1 and at==1 and Frozen(v)==0 and Shows(v,1,'Echo 1','Uncommon'),'R9: unknown charges keep the Take marker, no Freeze mark',table.concat(v.cards,' | '))
 C.guard(SameEffects(Effects(),e0),'R9: nothing performed')
 w.Stop()
 -- A long synthetic Echo name as the Freeze target: named whole.
 local long='Echo of an Exceptionally Long Synthetic Name for Fit'
 Boot({before=function(h) h.AddEcho(200001,long,1,5) end})
 CountAssignments()
 w=WatchDecisions()
 e0=Effects()
 Offer({{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200050,quality=2}})
 v=View()
 C.setup(w.last and w.last.type=='freeze' and w.last.spellId==200001,'R9: fixture: the long-named Echo is the Freeze target',Line(w.last))
 n,at=Frozen(v)
 C.expect(n==1 and at==1 and Shows(v,1,long,'Uncommon'),'R9: the long-named Freeze target is identified',table.concat(v.cards,' | '))
 C.expect(v.body:find(long..' (Uncommon)',1,true)~=nil,'R9: and named whole in the recommendation',v.body)
 C.guard(SameEffects(Effects(),e0),'R9: nothing performed')
 w.Stop()
end)

-- The adaptive Freeze admits two or more unheld Needed offers
-- (logic/EchoWeaver.lua, #unheld>=2), so its words claim no exact count.
C.scenario('R10 Auto OFF, three different Needed offers: the Freeze is named without an exact-count claim',function()
 Boot()
 CountAssignments()
 C.setup(not Auto(),'R10: fixture: Auto is OFF')
 local w=WatchDecisions()
 local e0=Effects()
 Offer({{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200003,quality=3}})
 local v=View()
 local m=Nexus.Panel._lastModel
 local d=w.last
 print('OBSERVED','R10 decision='..Line(d)..' head=['..v.head..'] body=['..v.body..'] cards=['..table.concat(v.cards,' | ')..']')
 C.setup(d and d.type=='freeze' and d.reasonCode=='PAIR_FREEZE_SECOND_NEEDED' and type(d.index)=='number'
  and ({200001,200002,200003})[d.index]==d.spellId,'R10: fixture: the real adaptive decision Freezes one of three different Needed offers',Line(d))
 C.setup(m.charges and m.charges.freeze==10 and m.charges.trustworthy==true and #v.cards==3,
  'R10: fixture: trusted Freeze charges and the three offers shown')
 local names={'Echo 1 (Uncommon)','Echo 2 (Rare)','Echo 3 (Epic)'}
 local target=d and names[d.index] or '?'
 local n,at=Frozen(v)
 C.guard(n==1 and d and at==d.index,'R10: exactly the decision\'s Freeze card is identified',table.concat(v.cards,' | '))
 C.guard(Marked(v)==0,'R10: no card carries the Take marker')
 C.guard(v.body:find(target,1,true)~=nil and v.body:lower():find('freeze',1,true)~=nil and not v.body:find('Take',1,true),
  'R10: the body names the Freeze target with Freeze wording',v.body)
 local shown=VisibleText()
 C.expect(not shown:lower():find('two needed',1,true) and not shown:lower():find('of two',1,true),
  'R10: no visible recommendation or status text claims exactly two Needed offers',v.body)
 C.guard(EngineFree(shown),'R10: no engine name in any visible text',v.body)
 C.guard(SameEffects(Effects(),e0),'R10: nothing performed, sent or assigned; settings and Auto unchanged')
 w.Stop()
end)

C.finish('(manual recommendation marked and named only when definite; Auto ON unchanged; charges unknown is not zero)')
