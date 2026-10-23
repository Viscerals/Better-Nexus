-- M7 (UX status composition): the destination, Auto, Sync and Orb status the
-- setup checklist states are composed from the same facts the panel already
-- shows. Panel.DestinationFacts is the one source of the destination lines:
-- the My Builds tooltip, Panel.DestinationLines and the checklist read it. The
-- status lines follow the committed HUD model (Auto selection and its hold),
-- SyncModePolicy.Mode and OrbRuntime.CompactStatus; a read that fails is "not
-- known", never OFF, Automatic or "no run". Reading the facts changes neither
-- the model nor anything else. The Build Library's receive window reads
-- "listening for answers"; "receiving" is reserved for reception in progress.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a; not executed by the author);
-- missing functions are a failed EXPECT, not a raised scenario. GUARD already
-- holds there and must keep holding; SETUP is the fixture.
-- Oracles: the real panel model and tooltip, Panel/UserText functions, the
-- policy and runtime reads (stubbed only to inject an unreadable or a given
-- mode, restored at once), the renderer source for the vocabulary lint, and
-- the counted writers, actions and sends. Real TOC boot; synthetic services.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_status_composition')
local H,A
local E2={{spellId=201175,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}

local function Boot(active,slots)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusEditorFrame=nil;NexusPanel=nil;NexusHelpWindow=nil;NexusSetupChecklist=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=slots or {[2]={name='Fire PvE',verified=true,echoes=E2},[107]={name='W-Free',verified=false,echoes=EF}}
 H.perks.serverActiveSlot=active
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('reading status must not spend') end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function Refresh()
 Nexus.Panel.Show()
 if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 H.Notify();A.Poll();H.Advance(1)
 return Nexus.Panel._lastModel
end
local function HeaderTip()
 local button=NexusPanel and NexusPanel._switchBtn
 if not (button and button:GetScript('OnEnter')) then return '' end
 return V.Plain(table.concat(V.TooltipLines(function() button:GetScript('OnEnter')(button) end),'\n'))
end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
local function Serialize(v,seen)
 seen=seen or {}
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end
 seen[v]=true
 local keys={}
 for k in pairs(v) do keys[#keys+1]=tostring(k) end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys) do
  local value=v[k];if value==nil then value=v[tonumber(k)] end
  out[#out+1]=k..'='..Serialize(value,seen)
 end
 seen[v]=nil
 return '{'..table.concat(out,',')..'}'
end

C.scenario('C1 one source of destination facts for the tooltip, the panel lines and the checklist',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C1: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 C.setup(type(model)=='table','C1: fixture: the runtime published a panel model')
 local P,T=Nexus.Panel,Nexus.UserText
 C.expect(type(P.DestinationFacts)=='function' and type(P.SetupFacts)=='function','C1: the panel exposes its destination and setup facts')
 if type(P.DestinationFacts)~='function' or type(P.SetupFacts)~='function' then return end
 local facts=P.DestinationFacts(model)
 local lines=P.DestinationLines(model)
 C.expect(type(facts)=='table' and facts.kind=='savedBuild' and facts.slot==2 and facts.active==true and facts.wishlistState=='assigned',
  'C1: the facts are the active Saved Build 2 with an assigned Wishlist',Serialize(facts))
 C.expect(table.concat(T.DestinationLines(facts),'\n')==table.concat(lines,'\n'),'C1: the panel lines are the wording of those facts')
 local tip=HeaderTip()
 for _,line in ipairs(lines) do C.guard(Has(tip,line),'C1: the My Builds tooltip still shows: '..line,tip) end
 local setup=P.SetupFacts()
 C.expect(type(setup.destination)=='table' and Serialize(setup.destination)==Serialize(facts),
  'C1: the checklist reads the same destination facts',Serialize(setup.destination))
 C.guard(P.DestinationFacts(nil)==nil and #P.DestinationLines(nil)==0,'C1: without a model nothing is captured or claimed')
end)

C.scenario('C2 the Auto line follows the committed model, including its hold',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C2: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 local P,T=Nexus.Panel,Nexus.UserText
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C2: setup facts and status lines exist');return
 end
 local f=P.SetupFacts()
 C.expect(f.auto==false and Has(T.StatusLines(f)[1],'Auto: OFF'),'C2: Auto OFF in the model reads OFF',tostring(f.auto))
 local held=H.Clone(model);held.auto=true;held.paused='Synthetic hold for the status test.'
 C.setup(P.Render(held)==true,'C2: fixture: the panel renders a selected Auto with a hold')
 f=P.SetupFacts()
 local line=T.StatusLines(f)[1]
 C.expect(f.auto==true and Has(line,'Auto: ON') and Has(line,'not acting now'),'C2: a selected Auto with a hold says it is not acting now',line)
 C.guard(Nexus.RecomputeStats().autoEnabled==false,'C2: reading the status turns nothing ON')
end)

C.scenario('C3 the Sync line states the saved mode, and an unreadable mode as not known',function()
 Boot(2)
 local P,T,policy=Nexus.Panel,Nexus.UserText,Nexus.SyncModePolicy
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C3: setup facts and status lines exist');return
 end
 Refresh()
 local realMode=policy.Mode
 local seen={}
 for _,mode in ipairs({'automatic','manual','off'}) do
  policy.Mode=function() return mode end
  local f=P.SetupFacts();seen[mode]=T.StatusLines(f)[2]
  policy.Mode=realMode
 end
 C.expect(Has(seen.automatic,'Sync: Automatic') and Has(seen.manual,'Sync: Manual') and Has(seen.off,'Sync: Off'),
  'C3: each saved mode is stated as itself',table.concat({seen.automatic,seen.manual,seen.off},' / '))
 policy.Mode=function() error('synthetic unreadable mode') end
 local okFacts,f=pcall(P.SetupFacts)
 policy.Mode=realMode
 C.expect(okFacts and f.syncMode==nil and Has(T.StatusLines(f)[2],'not known'),'C3: an unreadable mode is not known, not Automatic',okFacts and tostring(f.syncMode))
 C.guard(policy.Mode()==realMode(),'C3: the policy is restored and unchanged')
end)

C.scenario('C4 the Orb line: no run, a failed read and the model stay distinct; reading changes nothing',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C4: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 local P,T,runtime=Nexus.Panel,Nexus.UserText,Nexus.OrbRuntime
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C4: setup facts and status lines exist');return
 end
 local before=Serialize(model);local sent,actions=#H.sent,#H.actions
 local f=P.SetupFacts()
 C.expect(f.orb==false and Has(T.StatusLines(f)[3],'no Orb run approved'),'C4: no approved run is stated as such',tostring(f.orb))
 local realCompact=runtime.CompactStatus
 runtime.CompactStatus=function() error('synthetic unreadable run') end
 local okFacts;okFacts,f=pcall(P.SetupFacts)
 runtime.CompactStatus=realCompact
 C.expect(okFacts and f.orb==nil and Has(T.StatusLines(f)[3],'not known'),'C4: a failed run read is not known, not "no run"',okFacts and tostring(f.orb))
 C.guard(Serialize(Nexus.Panel._lastModel)==before and #H.sent==sent and #H.actions==actions,
  'C4: reading the facts changed neither the model nor anything else')
end)

-- M5R-NB18 (fresh31 reconciliation): Sync.IsReceiving is the window in which
-- answers are accepted, not evidence that any arrive, so the Build Library
-- says "listening for answers"; only inbound transfers in flight are called
-- "receiving" (the Leaderboard's count). A vocabulary lint of the sources.
C.scenario('C5 listening is not called receiving; receiving is only reception in progress',function()
 local handle=assert(io.open('ui/CommunityRenderer.lua','rb'));local src=handle:read('*a');handle:close()
 local lb=assert(io.open('ui/Leaderboard.lua','rb'));local board=lb:read('*a');lb:close()
 C.expect(Has(src,'Listening for answers %ds (%d new)'),'C5: the receive window is stated as listening for answers, with the stored new count')
 C.guard(Has(src,'sync="Listening..."') and Has(src,'receiving and "Listening..."'),'C5: the measured label and the button keep "Listening..."')
 C.guard(not Has(src,'sync="Receiving..."') and not Has(src,'receiving and "Receiving..."') and not Has(src,'Receiving %ds'),
  'C5: no Library text claims reception from the receive window alone')
 C.guard(Has(board,'local receiving=tonumber(work.receiving) or 0') and Has(board,'receiving.." receiving"'),
  'C5: the Leaderboard says "receiving" only from its count of inbound transfers in flight')
end)

C.finish('(one fact source for destination and status; unknown stays unknown; reading changes nothing)')
