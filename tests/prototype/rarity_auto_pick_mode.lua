-- Auto-pick by rarity as the alternative to a Wishlist (the optional leveling
-- pick, settings.autoPickLeveling, "Random Roll" in Options), offered in Plan
-- and shown in Play. The user's words: "it should be like a button or
-- something that says don't use a wish list and random roll instead", "and
-- in this section then probably have like Random roll choice".
--
-- M1  the words and the state of the mode are a pure function of facts;
--     "running" needs the runtime's own fact, never the option alone;
-- M2  with nothing assigned (first run) and Auto OFF the choice only turns
--     the option on: no question, no Auto, no action, no permission change;
--     Play says the mode and "Auto OFF" where the Wishlist name is, with the
--     Auto button; Auto is started by the player, picks the highest rarity
--     (first current offer on a tie) and is stopped by the stop-only route;
-- M3  levels 1 and 80 never pick and say so; levels 2 and 79 pick;
-- M4  autoPick off and a session pause are said, and neither is changed;
-- M5  with a Wishlist assigned to a Saved Build the choice asks first, names
--     the Wishlist and the exact Saved Build; Cancel changes nothing; accept
--     removes only that assignment, keeps the Wishlist and the other Saved
--     Build's assignment, turns the option on and leaves Auto OFF;
-- M6  a destination, assignment or owner that changed while the question
--     was open changes nothing; an assignment already removed elsewhere
--     needs no further write;
-- M7  loading, restoring, unavailable and an empty Saved Build are unknown,
--     never unassigned: the choice refuses and changes nothing;
-- M8  a failed removal changes nothing; a removal not yet confirmed by the
--     assignment facts is said as unconfirmed and is not claimed as in use;
-- M9  a pending Save refuses the choice, before and after the question;
-- M10 the first-run plan is removed with its own stamped Saved Build 1 copy
--     and kept as a recoverable plan that can be brought back (review SP-4);
-- M11 Plan: the button and the chooser's row exist beside the saved
--     Wishlists; showing, hovering and opening them changes nothing; saved
--     rows still open their Wishlist; an unsaved draft survives the choice;
-- M12 with Auto selected ON the choice asks first, and accepting it turns
--     Auto OFF through the stop-only route before anything else: with an
--     offer open the runtime takes nothing until the player's own Auto start;
--     Cancel leaves Auto ON; a stop that fails changes nothing (review SP-3);
-- M13 a first-run plan handed to Saved Build 1: both records it owns are
--     removed in one write, so the adapter's next reads keep it unassigned,
--     and another Saved Build's assignment is untouched (review SP-1);
-- M14 an unrelated first-run plan that would take the removed assignment's
--     place is not guessed away: the choice refuses with its reason;
-- M15 Plan's destination row says the mode and its state where it shows the
--     destination's Wishlist, with the chooser closed, and only for the
--     destination that uses it; "Editing" stays the draft (review SP-2);
-- M16 a first-run plan assigned by the real picker route alone (no Saved
--     Build 1 copy): kept with its first-run origin in words, never "nil";
--     its Undo returns it to the first run while that is still the
--     unassigned destination, and says so; when a Saved Build is in use by
--     then, it says which Saved Build index it was stored under and what the
--     first run holds (review SP-5); with a newer numbered assignment made in
--     between, the Undo leaves the first-run record exactly as it is, so
--     nothing is handed to a Saved Build later (review SP-6).
--
-- Categories (view_regression_support): EXPECT fails at 0dbd0349 (no such
-- choice, no selected-but-OFF words in Play), GUARD already held, SETUP is
-- the fixture. Real TOC boot, adapter, runtime and commands over the
-- synthetic harness; no game, saved data or native popup. Native look and
-- the real client's confirmation dialog are NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('rarity_auto_pick_mode')

local said={}
local realPrint=print
local function Boot(o)
 o=o or {}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil;NexusEditorFrame=nil
 NexusWishlistEditorSwitchMenu=nil;NexusWishlistEditorSwitchButton=nil;NexusWishlistEditorRarityButton=nil
 NexusWishlistEditorRarityRow=nil;NexusWishlistNameInput=nil
 print=realPrint
 local L=dofile('tests/prototype/harness.lua');L.pendingRolls=40;L.playerLevel=o.level or 10
 if o.before then o.before(L) end
 L.Boot()
 said={}
 print=function(...)
  local parts={}
  for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
  said[#said+1]=table.concat(parts,' ')
  -- The checker's own failure lines stay on the real output.
  if said[#said]:find('^FAIL ') then realPrint(said[#said]) end
 end
 if o.after then o.after(L) end
 Nexus.Panel.Show();L.Advance(1)
 return L
end
local SLOTS={[1]={name='Build one',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}},
 [2]={name='Build two',verified=true,echoes={{spellId=200002,quality=2,stacks=1}}}}
local function TwoBuilds(h) h.perks.serverActiveSlot=1;h.perks.serverBuildSlots=h.Clone(SLOTS) end
local function Assigned()
 local GA=Nexus.GameAdapter
 assert(GA.SetLoadoutWishlistIdentity(1,'Plan one',{{spellId=200001,quality=1,stacks=2}}))
 assert(GA.SetLoadoutWishlistIdentity(2,'Plan two',{{spellId=200002,quality=2,stacks=1}}))
end
-- The new entry points, absent at the base: called only when they exist, so
-- an expectation fails instead of raising.
local function Status()
 local J=Nexus.JournalTab
 if type(J.RarityAutoPickStatus)~='function' then return {mode={}} end
 return J.RarityAutoPickStatus()
end
local function Use()
 local J=Nexus.JournalTab
 if type(J.UseRarityAutoPick)~='function' then return 'absent' end
 return J.UseRarityAutoPick()
end
local function Said(text) for _,line in ipairs(said) do if line:find(text,1,true) then return true end end return false end
local function Option() return Nexus.Store.Settings().autoPickLeveling end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
-- Main-panel visual correction ("Split Build/Wishlist captions from values"):
-- the Wishlist line's label is a caption of its own
-- (NexusPanel._contextWishlistCaption) and NexusPanel._contextWishlist holds
-- the value. Line() reads the line as the player does, the shown caption and
-- then the value, so NONE below keeps its whole wording, the label included;
-- where no caption is shown it is the text alone, as before. The mode's line
-- is said whole and has no caption: a caption left beside it would make this
-- read differ from ON and OFF. M2 checks the caption and the value apart.
local function Caption()
 local caption=NexusPanel._contextWishlistCaption
 return caption and caption:IsShown() and (caption:GetText() or '') or ''
end
local function Value() return NexusPanel._contextWishlist:GetText() end
local function Line()
 local caption=Caption()
 return caption~='' and (caption..' '..tostring(Value())) or Value()
end
local function Takes(L) local n=0;for _,a in ipairs(L.actions) do if a[1]=='take' then n=n+1 end end return n end
local function LastTake(L) local id;for _,a in ipairs(L.actions) do if a[1]=='take' then id=a[2] end end return id end
local function Record(r) return type(r)=='table' and (tostring(r.name)..'#'..tostring(r.key)) or tostring(r) end
-- Everything the choice must not touch unless it says so: resource and pick
-- permissions, Auto, sent actions, both Saved Builds' assignments, the
-- first-run plan and the mode option.
local function Facts(L)
 local s,st=Nexus.Store.Settings(),Nexus.Store.State()
 local lw=type(st.loadoutWishlists)=='table' and st.loadoutWishlists or {}
 return table.concat({'actions='..#L.actions,'auto='..tostring(Auto()),'option='..tostring(s.autoPickLeveling),
  'autoPick='..tostring(s.autoPick),'reroll='..tostring(s.autoReroll),'freeze='..tostring(s.autoFreeze),
  'banish='..tostring(s.autoBanish),'one='..Record(lw[1]),'two='..Record(lw[2]),'first='..Record(st.firstRunWishlist)},' ')
end
local POPUP='NEXUS_USE_RARITY_AUTO_PICK'
local function Asked(L) return L.popup~=nil and L.popup.which==POPUP end
-- The open question, held so that its accept can be given later whatever the
-- harness did with its one popup slot meanwhile (the client's accept button).
local function Open(L) local p=Asked(L) and L.popup or nil;return p end
local function Accept(p) if p then StaticPopupDialogs[POPUP].OnAccept(p.frame,p.data) end end
local function Question() local d=StaticPopupDialogs[POPUP];return type(d)=='table' and tostring(d.text) or '' end
local BOARD={{spellId=200001,quality=1},{spellId=200004,quality=4},{spellId=200003,quality=4}}
local function Offer(L) L.Board(BOARD);L.Notify();L.Advance(3) end
local ON,OFF,NONE='Auto-pick by rarity (ON)','Auto-pick by rarity (Auto OFF)','Wishlist: None assigned'

C.scenario('M1 the mode\'s state is a pure function of facts; only the runtime\'s fact is running',function()
 Boot()
 local R=Nexus.Readout
 if not C.expect(type(R.RarityMode)=='function' and type(R.RarityText)=='function','M1: Readout words the mode') then return end
 local base={option=true,assignment='unassigned',levelOk=true,autoPick=true,auto=true}
 local function State(change) local f={};for k,v in pairs(base) do f[k]=v end;for k,v in pairs(change or {}) do f[k]=v end;return R.RarityMode(f) end
 local cases={{'off',{option=false,running=true}},{'running',{running=true}},{'assigned',{assignment='assigned'}},
  {'unknown',{assignment='loading'}},{'unknown',{assignment=false}},{'level',{levelOk=false}},{'no_permission',{autoPick=false}},
  {'paused',{sessionPaused=true}},{'auto_off',{auto=false}},{'waiting',{}},{'off',{option='true'}}}
 for _,case in ipairs(cases) do
  local m=State(case[2])
  C.expect(m.state==case[1] and type(m.short)=='string' and m.short~='' and type(m.reason)=='string' and m.reason~='',
   'M1: '..case[1]..' is named with its short words and its reason',tostring(m.state))
 end
 C.expect(State({}).running==false and State({auto=true}).state=='waiting','M1: every setting on without the runtime\'s fact is waiting, never running')
 C.expect(State({running=true}).selected and State({auto=false}).selected and not State({assignment='assigned'}).selected
  and not State({assignment='x'}).selected and not State({option=false}).selected,'M1: selected only where the destination uses the mode')
 local rule=State({}).rule
 C.expect(rule:find('highest-rarity',1,true) and rule:find('first current offer on a tie',1,true) and rule:find('levels 2 to 79',1,true)
  and rule:find('not random',1,true) and rule:find('never rerolls, banishes, freezes, spends, saves or uses Orbs',1,true),
  'M1: the rule says highest rarity, the tie, the levels, not random, and what it never does',rule)
end)

C.scenario('M2 nothing assigned, Auto OFF: the choice only turns the option on; Auto is the player\'s own start and stop',function()
 local L=Boot()
 local a=Nexus.GameAdapter.AssignedWishlist()
 C.setup(a.knownUnassigned==true and Option()==nil and not Auto(),'M2: fixture: first run, nothing assigned, option absent, Auto OFF')
 C.guard(Line()==NONE and not NexusPanel._autoBtn:IsShown(),'M2: before the choice Play says None assigned and has no Auto button',Line())
 C.expect(Caption()=='Wishlist:' and Value()=='None assigned',
  'M2: before the choice the label Wishlist: is a caption of its own and its value says None assigned',Caption()..' | '..tostring(Value()))
 local before=Facts(L)
 local s=Status()
 C.expect(s.assignment=='unassigned' and s.option==false and s.mode.state=='off' and type(s.destination)=='table'
  and s.destination.kind=='firstRun','M2: the status reads nothing assigned on the first-run destination, mode off',tostring(s.assignment))
 C.guard(Facts(L)==before,'M2: reading the status changes nothing',Facts(L))
 local result=Use();L.Advance(1)
 C.expect(result==false and Option()==true and NexusDB.settings.autoPickLeveling==true,'M2: the choice turns the option on at once',tostring(result))
 C.expect(not Asked(L),'M2: with nothing to remove and Auto OFF no question is asked')
 C.guard(not Auto() and #L.actions==0,'M2: the choice does not start Auto and sends nothing')
 local s2=Nexus.Store.Settings()
 C.expect(s2.autoPick==Nexus.Store.Settings().autoPick and Facts(L)==before:gsub('option=nil','option=true'),
  'M2: only the option changed: permissions, assignments and Auto are as before',Facts(L))
 C.expect(Status().mode.state=='auto_off' and Status().mode.selected==true,'M2: the mode is selected and says Auto OFF',tostring(Status().mode.state))
 C.expect(Line()==OFF,'M2: Play says the mode and Auto OFF where the Wishlist name is',Line())
 C.expect(Caption()=='' and Value()==OFF,'M2: the mode is said whole: no Wishlist: caption stands before it',Caption()..' | '..tostring(Value()))
 C.expect(tostring(NexusPanel._contextWishlistHit._nexusFull):find('selecting this never starts Auto',1,true)~=nil
  and tostring(NexusPanel._contextWishlistHit._nexusFull):find(NONE,1,true)~=nil,
  'M2: its hover gives the reason, the rule and keeps the assignment fact',NexusPanel._contextWishlistHit._nexusFull)
 C.expect(NexusPanel._autoBtn:IsShown(),'M2: the Auto button is there to start it')
 C.expect(Said('Auto-pick by rarity is selected for your first run'),'M2: chat names the destination and the state')
 Offer(L)
 C.guard(Takes(L)==0 and Line()~=ON,'M2: selected with Auto OFF takes nothing from an offer and never says ON',Line())
 SlashCmdList.NEXUS('auto');L.Advance(3)
 C.expect(Auto() and Takes(L)==1 and LastTake(L)==200004,'M2: the player\'s own Auto start takes the highest rarity, the first current offer on the tie',tostring(LastTake(L)))
 C.expect(#L.actions==1,'M2: one Take and no other action (no reroll, banish, freeze or Orb)',#L.actions)
 L.Advance(2)
 C.expect(Line()==ON and Status().mode.state=='running','M2: while the runtime says it picks, Play says ON',Line())
 C.guard(Nexus.DisableOrdinaryAutomation()==true and not Auto(),'M2: the stop-only route turns Auto OFF')
 L.Advance(1)
 C.expect(Line()==OFF,'M2: stopped, Play says Auto OFF again at once',Line())
 local taken=Takes(L)
 Offer(L)
 C.guard(Takes(L)==taken,'M2: after Stop nothing more is taken')
 C.expect(Use()==false and Option()==false and not Auto(),'M2: choosing it again turns only the option off')
 L.Advance(1)
 C.guard(Line()==NONE,'M2: deselected, Play says None assigned',Line())
end)

C.scenario('M3 levels 1 and 80 never pick and say so; levels 2 and 79 pick',function()
 for _,level in ipairs({1,80,2,79}) do
  local L=Boot({level=level})
  local picks=level>=2 and level<=79
  C.setup(Nexus.GameAdapter.AssignedWishlist().knownUnassigned==true,'M3: fixture: level '..level..', nothing assigned')
  Use();L.Advance(1)
  C.expect(Option()==true and not Auto(),'M3: level '..level..': the mode can be selected and Auto stays OFF')
  if not picks then
   C.expect(Status().mode.state=='level' and Line()=='Auto-pick by rarity (levels 2-79 only)',
    'M3: level '..level..': Play says it only picks at levels 2-79',Line())
  else
   C.expect(Status().mode.state=='auto_off' and Line()==OFF,'M3: level '..level..': selected, Auto OFF',Line())
  end
  SlashCmdList.NEXUS('auto');Offer(L)
  if picks then
   C.expect(Takes(L)==1 and #L.actions==1 and LastTake(L)==200004,'M3: level '..level..' picks once after the choice and the player\'s Auto: the highest rarity, first on the tie',Takes(L))
  else
   C.guard(#L.actions==0,'M3: level '..level..' sends nothing',#L.actions)
  end
 end
end)

C.scenario('M4 autoPick off and a session pause are said, and the choice changes neither',function()
 local L=Boot({after=function() Nexus.Store.Settings().autoPick=false end})
 Use();L.Advance(1)
 C.expect(Option()==true and Status().mode.state=='no_permission' and Line()=='Auto-pick by rarity (autoPick off)',
  'M4: with autoPick off the mode is selected and says autoPick off',Line())
 C.guard(Nexus.Store.Settings().autoPick==false,'M4: the choice never turns autoPick on')
 SlashCmdList.NEXUS('auto');Offer(L)
 C.guard(#L.actions==0,'M4: with autoPick off Auto ON sends nothing')
 L=Boot()
 Use();L.Advance(1)
 Nexus.SessionPause.Pause();L.Advance(1)
 C.setup(Nexus.SessionPause.IsPaused()==true,'M4: fixture: Nexus is paused for the session')
 C.expect(Status().mode.state=='paused' and Line()=='Auto-pick by rarity (paused)','M4: paused is said, not Auto OFF and not ON',Line())
 Offer(L)
 C.guard(#L.actions==0 and Nexus.SessionPause.IsPaused()==true,'M4: paused sends nothing and the choice does not resume it')
end)

C.scenario('M5 a Wishlist assigned to a Saved Build: asked first, Cancel changes nothing, accept removes only that assignment',function()
 local L=Boot({before=TwoBuilds,after=Assigned})
 local a=Nexus.GameAdapter.AssignedWishlist()
 C.setup(a.state=='ready' and a.name=='Plan one' and a.knownUnassigned==nil,'M5: fixture: Plan one is assigned to Saved Build 1, Plan two to Saved Build 2')
 C.guard(Line():find('Plan one',1,true)~=nil,'M5: Play names the assigned Wishlist',Line())
 local before=Facts(L)
 local s=Status()
 C.expect(s.assignment=='assigned' and s.wishlist=='Plan one' and type(s.destination)=='table' and s.destination.kind=='savedBuild'
  and s.destination.slot==1 and s.destination.name=='Build one','M5: the status names the Wishlist and the exact Saved Build',tostring(s.assignment))
 local result=Use()
 C.expect(result==true and Asked(L),'M5: the choice asks before it removes an assignment',tostring(result))
 local q=Question()
 C.expect(q:find('Plan one',1,true) and q:find('Build one',1,true) and q:find('slot 1',1,true) and q:find('stays saved',1,true)
  and q:find('does not start Auto',1,true),'M5: the question names the Wishlist, the Saved Build and slot, that it stays saved and that Auto is not started',q)
 C.guard(Facts(L)==before,'M5: asking changes nothing',Facts(L))
 StaticPopup_Hide();L.Advance(1)
 C.guard(Facts(L)==before,'M5: Cancel changes no assignment, setting or Auto',Facts(L))
 C.guard(Line():find('Plan one',1,true)~=nil,'M5: after Cancel Play still names the Wishlist',Line())
 local two=Record(Nexus.Store.State().loadoutWishlists[2])
 Use()
 Accept(Open(L))
 L.Advance(1)
 local st=Nexus.Store.State()
 C.expect(st.loadoutWishlists[1]==nil and Nexus.GameAdapter.AssignedWishlist().knownUnassigned==true,'M5: accept removes Saved Build 1\'s assignment')
 C.guard(Record(st.loadoutWishlists[2])==two,'M5: Saved Build 2 keeps its own assignment',Record(st.loadoutWishlists[2]))
 local kept=st.forgottenWishlist
 C.expect(type(kept)=='table' and type(kept.record)=='table' and kept.record.name=='Plan one' and kept.source=='unassign' and kept.loadoutSlot==1,
  'M5: the removed Wishlist is retained as a recoverable plan by the existing Unassign',type(kept)=='table' and kept.source)
 C.expect(Option()==true,'M5: the option is on after the accept')
 C.guard(not Auto() and #L.actions==0 and Nexus.Store.Settings().autoPick==Nexus.Store.Settings().autoPick,'M5: Auto stays OFF and nothing is sent')
 C.expect(Line()==OFF and Status().mode.selected==true,'M5: Play says the mode and Auto OFF',Line())
 C.expect(Said('is selected for Saved Build \'Build one\' (slot 1)'),'M5: chat names the exact destination')
end)

C.scenario('M6 a destination, assignment or owner that changed while the question was open changes nothing',function()
 local changes={
  {'the active Saved Build changed',function(L) L.perks.serverActiveSlot=2;L.Notify();L.Advance(1) end,'Plan one#','Plan two#'},
  {'another Wishlist was assigned there',function(L)
    assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Plan three',{{spellId=200003,quality=3,stacks=1}}));L.Advance(1) end,'Plan three#','Plan two#'},
  {'the character\'s saved data changed',function(L)
    local real=Nexus.Store.CurrentOwnerKey;L.restore=function() Nexus.Store.CurrentOwnerKey=real end
    Nexus.Store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end end,'Plan one#','Plan two#'},
 }
 for _,change in ipairs(changes) do
  local L=Boot({before=TwoBuilds,after=Assigned})
  local asked=Use()==true and Open(L)
  C.expect(asked,'M6: fixture: '..change[1]..': the question is open')
  change[2](L)
  Accept(asked)
  if L.restore then L.restore() end
  L.Advance(1)
  local st=Nexus.Store.State()
  C.guard(Record(st.loadoutWishlists[1]):find(change[3],1,true)==1 and Record(st.loadoutWishlists[2]):find(change[4],1,true)==1,
   'M6: '..change[1]..': both assignments are as they were after the accept',Record(st.loadoutWishlists[1]))
  C.guard(Option()==nil and not Auto() and #L.actions==0,'M6: '..change[1]..': no setting, Auto or action changed',tostring(Option()))
  C.expect(Said('Nothing was changed'),'M6: '..change[1]..': chat says nothing was changed')
 end
 local L=Boot({before=TwoBuilds,after=Assigned})
 local asked=Use()==true and Open(L)
 C.expect(asked,'M6: fixture: removed elsewhere: the question is open')
 C.setup(Nexus.GameAdapter.ClearLoadoutWishlist(1)==true,'M6: fixture: the assignment is removed elsewhere while it is open')
 L.Advance(1)
 local token=Nexus.GameAdapter.AssignmentActionToken(1)
 Accept(asked)
 L.Advance(1)
 C.expect(Option()==true and Nexus.GameAdapter.AssignmentActionToken(1)==token,
  'M6: already unassigned there: the option is turned on and no further assignment write is made',tostring(Option()))
 C.guard(type(Nexus.Store.State().loadoutWishlists[2])=='table' and not Auto(),'M6: the other Saved Build and Auto are untouched')
end)

C.scenario('M7 loading, restoring, unavailable and an empty Saved Build are unknown, never unassigned',function()
 for _,state in ipairs({'loading','restoring','unavailable'}) do
  local L=Boot({before=TwoBuilds,after=Assigned})
  local real=Nexus.GameAdapter.AssignedWishlist
  Nexus.GameAdapter.AssignedWishlist=function() local a=real();a.state=state;a.knownUnassigned=nil;a.wishlist=nil;return a end
  local before=Facts(L)
  local s=Status()
  C.expect(s.assignment=='unknown' and s.reason==state and s.mode.selected~=true,'M7: '..state..' is unknown with its reason',tostring(s.assignment))
  local result=Use()
  C.expect(result==nil and not Asked(L) and Said('Nothing was changed'),'M7: '..state..': the choice refuses, asks nothing and says so',tostring(result))
  Nexus.GameAdapter.AssignedWishlist=real
  C.guard(Facts(L)==before,'M7: '..state..': nothing changed',Facts(L))
 end
 local L=Boot({before=function(h) h.perks.serverActiveSlot=1
  h.perks.serverBuildSlots={[1]={name='Empty build',verified=true,echoes={}},[2]=h.Clone(SLOTS[2])} end})
 local a=Nexus.GameAdapter.AssignedWishlist()
 C.setup(a.knownUnassigned~=true,'M7: fixture: an empty Saved Build is not positively unassigned',tostring(a.state)..'/'..tostring(a.emptySlot))
 local before=Facts(L)
 C.expect(Status().assignment=='unknown' and Use()==nil and not Asked(L),'M7: an empty Saved Build: unknown, refused')
 C.guard(Facts(L)==before and Line()~=OFF,'M7: an empty Saved Build: nothing changed and Play does not claim the mode',Line())
 SlashCmdList.NEXUS('leveling on');L.Advance(1)
 C.guard(Line()~=OFF and Line()~=ON,'M7: with the option on, an unknown destination never shows the mode in Play',Line())
end)

C.scenario('M8 a failed removal changes nothing; an unconfirmed removal is not claimed as in use',function()
 local L=Boot({before=TwoBuilds,after=Assigned})
 local before=Facts(L)
 local asked=Use()==true and Open(L)
 C.expect(asked,'M8: fixture: the question is open')
 local real=Nexus.GameAdapter.ClearLoadoutWishlist
 Nexus.GameAdapter.ClearLoadoutWishlist=function() return false end
 Accept(asked)
 Nexus.GameAdapter.ClearLoadoutWishlist=real
 L.Advance(1)
 C.guard(Facts(L)==before,'M8: a removal that fails leaves the assignment, the option and Auto as they were',Facts(L))
 C.expect(Said('the assignment could not be removed'),'M8: chat says the assignment could not be removed')
 L=Boot({before=TwoBuilds,after=Assigned})
 asked=Use()==true and Open(L)
 C.expect(asked,'M8: fixture: the question is open again')
 local read=Nexus.GameAdapter.AssignedWishlist
 local clear=Nexus.GameAdapter.ClearLoadoutWishlist
 Nexus.GameAdapter.ClearLoadoutWishlist=function(...)
  local ok=clear(...)
  Nexus.GameAdapter.AssignedWishlist=function() local a=read();a.state='loading';a.knownUnassigned=nil;return a end
  return ok
 end
 Accept(asked)
 Nexus.GameAdapter.ClearLoadoutWishlist=clear
 C.expect(Nexus.Store.State().loadoutWishlists[1]==nil and Said('still waiting to confirm'),'M8: removed but not yet confirmed is said as such')
 C.expect(Status().assignment=='unknown' and Status().mode.selected~=true,'M8: while unconfirmed the mode is not claimed as in use')
 Nexus.GameAdapter.AssignedWishlist=read
 C.guard(not Auto() and #L.actions==0,'M8: Auto stays OFF and nothing is sent')
end)

C.scenario('M9 a pending Save refuses the choice, before and after the question',function()
 local L=Boot({before=TwoBuilds,after=Assigned})
 local before=Facts(L)
 local real=Nexus.WishlistEditor.IsApplyPending
 Nexus.WishlistEditor.IsApplyPending=function() return true end
 local result=Use()
 C.expect(result==nil and not Asked(L) and Said('finish or cancel the pending Save first'),'M9: with a Save pending the choice refuses and says why',tostring(result))
 C.guard(Facts(L)==before,'M9: nothing changed',Facts(L))
 Nexus.WishlistEditor.IsApplyPending=real
 local asked=Use()==true and Open(L)
 C.expect(asked,'M9: fixture: without a pending Save the question opens')
 Nexus.WishlistEditor.IsApplyPending=function() return true end
 Accept(asked)
 Nexus.WishlistEditor.IsApplyPending=real
 L.Advance(1)
 C.guard(Facts(L)==before,'M9: a Save that became pending while the question was open: accept changes nothing',Facts(L))
end)

C.scenario('M10 the first-run plan is removed by the first-run Unassign only',function()
 local L=Boot({after=function() assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('First plan',{{spellId=200001,quality=1,stacks=2}})) end})
 local a=Nexus.GameAdapter.AssignedWishlist()
 C.setup(a.state=='ready' and a.knownUnassigned==nil and type(Nexus.Store.State().firstRunWishlist)=='table','M10: fixture: a first-run plan is assigned',tostring(a.state))
 local s=Status()
 C.expect(s.assignment=='assigned' and type(s.destination)=='table' and s.destination.kind=='firstRun' and s.wishlist=='First plan',
  'M10: the status names the first-run destination and its plan',tostring(s.assignment)..'/'..tostring(s.reason))
 local asked=Use()==true and Open(L)
 C.expect(asked and Question():find('First plan',1,true) and Question():find('first run',1,true),'M10: the question names the plan and the first run',Question())
 Accept(asked)
 L.Advance(1)
 C.expect(Nexus.Store.State().firstRunWishlist==false and Nexus.GameAdapter.AssignedWishlist().knownUnassigned==true and Option()==true,
  'M10: accept records the explicit first-run Unassign and turns the option on')
 C.guard(not Auto() and #L.actions==0,'M10: Auto stays OFF and nothing is sent')
 -- SP-4: this plan has no server copy (the harness lists no server Wishlist),
 -- so the removal must keep it. The stamped Saved Build 1 copy is the same
 -- plan and goes with it; exactly one recoverable entry holds it.
 local GA=Nexus.GameAdapter
 local st=Nexus.Store.State()
 C.guard(type(st.loadoutWishlists)~='table' or st.loadoutWishlists[1]==nil,'M10: the plan\'s own stamped Saved Build 1 copy went with it')
 local kept,count=nil,0
 for _,entry in ipairs(GA.ForgottenWishlistPlans()) do
  if entry.name=='First plan' then kept=entry;count=count+1 end
 end
 C.expect(count==1 and kept.key=='200001:2','M10: the removed first-run plan is kept once as a recoverable plan with its exact Echo rows',
  tostring(count)..' / '..tostring(kept and kept.key))
 local restored=kept~=nil and GA.RestoreForgottenWishlistPlan({position=kept.position,key=kept.key,assignmentId=kept.assignmentId})==true
 L.Advance(1)
 local back
 for _,record in pairs(type(Nexus.Store.State().loadoutWishlists)=='table' and Nexus.Store.State().loadoutWishlists or {}) do
  if type(record)=='table' and record.name=='First plan' and record.key=='200001:2' then back=record end
 end
 C.expect(restored and back~=nil and #GA.ForgottenWishlistPlans()==0,'M10: the existing restore brings that exact plan back and empties the recoverable list',
  tostring(restored))
 C.guard(Nexus.Store.State().firstRunWishlist==false and not Auto() and #L.actions==0,
  'M10: bringing it back does not undo the explicit first-run Unassign, start Auto or send anything')
end)

C.scenario('M11 Plan: the button and the chooser row sit beside the saved Wishlists; looking changes nothing; a draft survives',function()
 local L=Boot({before=TwoBuilds,after=function()
  assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(2,'Plan two',{{spellId=200002,quality=2,stacks=1}})) end})
 C.setup(Nexus.GameAdapter.AssignedWishlist().knownUnassigned==true,'M11: fixture: Saved Build 1 has nothing assigned; Plan two is saved on Saved Build 2')
 Nexus.WishlistEditor.NewWishlist();L.Advance(1)
 C.setup(NexusEditorFrame~=nil and NexusEditorFrame:IsVisible(),'M11: fixture: Plan is open on a new draft')
 local name=_G.NexusWishlistNameInput
 if name and name._NexusSetRawText then name:_NexusSetRawText('My unsaved draft') end
 local before=Facts(L)
 local button=_G.NexusWishlistEditorRarityButton
 C.expect(button~=nil and button:IsVisible() and button:GetText()=='Auto-pick by rarity','M11: Plan shows an Auto-pick by rarity button',button and button:GetText())
 if button then
  -- Model geometry: inside Plan and clear of every other visible button of the window.
  local own,window,clear=G.Rect(button,NexusEditorFrame),G.Rect(NexusEditorFrame,NexusEditorFrame),true
  local hit
  for _,f in ipairs(L.frames) do
   if f~=button and f.kind=='Button' and f:GetParent()==NexusEditorFrame and f:IsVisible() then
    local ok,r=pcall(G.Rect,f,NexusEditorFrame)
    if ok and r and not G.Apart(own,r) then clear=false;hit=tostring(f:GetText()) end
   end
  end
  C.expect(G.Inside(own,window,0.01) and clear,'M11: the button is inside Plan and overlaps no other button',G.Text(own)..' '..tostring(hit))
 end
 local sw=_G.NexusWishlistEditorSwitchButton
 sw:GetScript('OnClick')(sw)
 local menu=_G.NexusWishlistEditorSwitchMenu
 C.setup(menu~=nil and menu:IsVisible(),'M11: fixture: the Wishlist chooser is open')
 local saved
 for _,row in ipairs(menu.rows) do if row:IsVisible() and tostring(row._label:GetText()):find('Plan two',1,true) then saved=row end end
 C.guard(saved~=nil,'M11: the chooser still lists the saved Wishlist')
 local row=menu.modeRow
 C.expect(row~=nil and row:IsVisible() and tostring(row._label:GetText()):find('No Wishlist: auto-pick by rarity',1,true)==1
  and not row._check:IsShown(),'M11: below it the chooser offers No Wishlist: auto-pick by rarity, not checked',row and row._label:GetText())
 if row and saved then
  local m,r,sv=G.Rect(menu,menu),G.Rect(row,menu),G.Rect(saved,menu)
  C.expect(r[2]>=sv[4] and G.Inside(r,m,0.01),'M11: the row is its own row under the saved ones, inside the menu',G.Text(r)..' in '..G.Text(m))
 end
 for _,widget in ipairs({button,row}) do
  if widget then
   local lines=V.TooltipLines(widget:GetScript('OnEnter'),widget)
   local tip=table.concat(lines,' ')
   C.expect(tip:find('instead of a Wishlist',1,true) and tip:find('highest-rarity',1,true) and tip:find('never starts Auto',1,true)
    and tip:find('Saved Build \'Build one\' (slot 1)',1,true),'M11: its hover explains the rule, names the destination and says Auto is not started',tip)
  end
 end
 C.guard(Facts(L)==before,'M11: showing, opening and hovering changed nothing',Facts(L))
 if row then row:GetScript('OnClick')(row) end
 L.Advance(1)
 C.expect(Option()==true and not Auto() and not Asked(L),'M11: the row\'s click selects the mode (nothing assigned, Auto OFF): option on, Auto OFF')
 C.guard(NexusEditorFrame:IsVisible() and name~=nil and name:_NexusRawText()=='My unsaved draft','M11: Plan stays open with the unsaved draft\'s name',name and name:_NexusRawText())
 C.expect(button~=nil and button._nexusSelected==true,'M11: the button is lit as selected after the choice')
 sw:GetScript('OnClick')(sw)
 if not menu:IsVisible() then sw:GetScript('OnClick')(sw) end
 C.expect(menu.modeRow~=nil and menu.modeRow._check:IsShown() and tostring(menu.modeRow._label:GetText()):find('(Auto OFF)',1,true)~=nil,
  'M11: reopened, the row is checked and says Auto OFF',menu.modeRow and menu.modeRow._label:GetText())
 if button then button:GetScript('OnClick')(button) end
 L.Advance(1)
 C.expect(Option()==false and not Auto(),'M11: the button\'s click on a selected mode turns only the option off')
 C.guard(type(Nexus.Store.State().loadoutWishlists[2])=='table','M11: the saved Wishlist\'s assignment is untouched throughout')
 for _,r in ipairs(menu.rows) do if tostring(r._label:GetText()):find('Plan two',1,true) then saved=r end end
 sw:GetScript('OnClick')(sw)
 if not menu:IsVisible() then sw:GetScript('OnClick')(sw) end
 if saved and saved:GetScript('OnClick') then saved:GetScript('OnClick')(saved) end
 L.Advance(1)
 local shown=tostring(sw:GetText())
 C.guard(shown:find('Plan two',1,true)~=nil or Asked(L)==false,'M11: a saved row still follows its existing open-for-editing route',shown)
end)

C.scenario('M12 Auto selected ON: asked first; accept turns Auto OFF before anything else; nothing is taken until the player\'s own start',function()
 local L=Boot()
 SlashCmdList.NEXUS('auto');L.Advance(1)
 Offer(L)
 C.setup(Auto() and Option()==nil and #L.actions==0,'M12: fixture: Auto is ON, nothing assigned, option absent, an offer is open and untouched')
 local before=Facts(L)
 local result=Use()
 local q=Question()
 C.expect(result==true and Asked(L) and q:find('Auto is ON',1,true)~=nil and q:find('turns Auto OFF',1,true)~=nil,
  'M12: it asks, and says that choosing this turns Auto OFF',q)
 StaticPopup_Hide();L.Advance(2)
 C.guard(Facts(L)==before and Auto(),'M12: Cancel changes nothing: Auto stays ON, the option stays off, nothing is taken',Facts(L))
 local stop=Nexus.DisableOrdinaryAutomation
 Nexus.DisableOrdinaryAutomation=function() return false,'fixture: the stop route refused' end
 local asked=Use()==true and Open(L)
 Accept(asked)
 Nexus.DisableOrdinaryAutomation=stop
 L.Advance(2)
 C.expect(asked and Option()==nil and Said('Auto could not be turned OFF'),'M12: when Auto cannot be stopped the option is not turned on, and chat says so',tostring(Option()))
 C.expect(#L.actions==0,'M12: and nothing is taken')
 asked=Use()==true and Open(L)
 Accept(asked)
 -- The session switch itself; the panel's model follows on its next render (the Play line below).
 C.expect(asked and not Auto(),'M12: accept turns Auto OFF through the stop-only route')
 C.expect(Option()==true,'M12: and then turns the option on')
 -- The runtime's own steps, with the offer still open: no Take without a start.
 L.Advance(6)
 C.expect(not Auto() and #L.actions==0 and Takes(L)==0,'M12: with the offer open the runtime takes nothing after the accept',#L.actions)
 C.expect(Line()==OFF and Said('Auto was turned OFF'),'M12: Play says selected, Auto OFF, and chat says Auto was turned OFF',Line())
 SlashCmdList.NEXUS('auto');L.Advance(3)
 C.expect(Auto() and Takes(L)==1 and #L.actions==1 and LastTake(L)==200004,'M12: the player\'s own Auto start then takes once: the highest rarity, first on the tie',Takes(L))
 -- A Wishlist assigned and Auto ON for it.
 L=Boot({before=TwoBuilds,after=Assigned})
 SlashCmdList.NEXUS('auto');L.Advance(1)
 C.setup(Auto() and #L.actions==0,'M12: fixture: Plan one is assigned and Auto is ON for it, no offer yet')
 asked=Use()==true and Open(L)
 C.expect(asked and Question():find('Plan one',1,true)~=nil and Question():find('turns Auto OFF',1,true)~=nil,'M12: with a Wishlist the question names it and says Auto is turned OFF',Question())
 Accept(asked)
 C.expect(asked and not Auto() and Option()==true and Nexus.Store.State().loadoutWishlists[1]==nil,'M12: accept stops Auto, removes the assignment and selects the mode')
 Offer(L);L.Advance(4)
 C.expect(#L.actions==0,'M12: an offer after the accept is left alone until the player starts Auto',#L.actions)
 SlashCmdList.NEXUS('auto');L.Advance(3)
 C.expect(Takes(L)==1 and LastTake(L)==200004,'M12: the player\'s own start takes the highest rarity once',Takes(L))
end)

C.scenario('M13 a first-run plan handed to Saved Build 1: both owned records go in one write and the next adapter reads keep it unassigned',function()
 local L=Boot({before=TwoBuilds,after=function()
  -- Saved Build 2 first: its numbered setter reconciles the first-run record.
  assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(2,'Plan two',{{spellId=200002,quality=2,stacks=1}}))
  assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Pair plan',{{spellId=200001,quality=1,stacks=2}}))
 end})
 local GA=Nexus.GameAdapter
 local st=Nexus.Store.State()
 C.setup(type(st.firstRunWishlist)=='table' and type(st.loadoutWishlists[1])=='table'
  and st.firstRunWishlist.assignmentId==st.loadoutWishlists[1].assignmentId and GA.AssignedWishlist().name=='Pair plan',
  'M13: fixture: the first-run plan and its stamped copy on the active, populated Saved Build 1')
 local s=Status()
 C.guard(s.assignment=='assigned' and type(s.destination)=='table' and s.destination.slot==1,'M13: the status names Saved Build 1 and its Wishlist',tostring(s.assignment))
 local two=Record(st.loadoutWishlists[2])
 local asked=Use()==true and Open(L)
 C.guard(asked and Question():find('Pair plan',1,true)~=nil,'M13: the question names the plan')
 Accept(asked)
 -- The adapter's own later reads (the HUD and the runtime step them).
 L.Advance(3)
 local a=GA.AssignedWishlist()
 st=Nexus.Store.State()
 C.expect(st.loadoutWishlists[1]==nil and st.firstRunWishlist==false,'M13: the Saved Build 1 copy and the first-run record it came from are both removed',
  Record(st.loadoutWishlists[1])..' / '..Record(st.firstRunWishlist))
 C.expect(a.knownUnassigned==true and a.state=='unassigned','M13: after the adapter\'s next reads nothing is assigned: the plan is not handed back',tostring(a.state)..' / '..tostring(a.name))
 C.expect(Option()==true and Status().mode.selected==true and Line()==OFF and Said('is selected for Saved Build \'Build one\' (slot 1)'),
  'M13: the mode is selected there, and Play and chat say so',Line())
 local count=0
 for _,entry in ipairs(GA.ForgottenWishlistPlans()) do if entry.name=='Pair plan' then count=count+1 end end
 C.expect(count==1,'M13: the plan is kept once as a recoverable plan',count)
 C.guard(Record(st.loadoutWishlists[2])==two and not Auto() and #L.actions==0,'M13: Saved Build 2\'s assignment, Auto and actions are untouched',Record(st.loadoutWishlists[2]))
end)

C.scenario('M14 an unrelated first-run plan that would take the removed assignment\'s place: refused with its reason',function()
 local L=Boot({before=TwoBuilds,after=function()
  assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Slot plan',{{spellId=200003,quality=3,stacks=1}}))
  assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Other first plan',{{spellId=200002,quality=2,stacks=1}}))
 end})
 local st=Nexus.Store.State()
 C.setup(type(st.firstRunWishlist)=='table' and st.firstRunWishlist.name=='Other first plan' and type(st.loadoutWishlists[1])=='table'
  and st.loadoutWishlists[1].name=='Slot plan' and st.firstRunWishlist.assignmentId~=st.loadoutWishlists[1].assignmentId,
  'M14: fixture: Saved Build 1 has its own Wishlist, and a different first-run plan is stored')
 local before=Facts(L)
 local s=Status()
 C.expect(s.assignment=='unknown' and s.reason=='first_run_plan_pending','M14: not verifiable as removable: a first-run plan would be assigned in its place',
  tostring(s.assignment)..' / '..tostring(s.reason))
 local result=Use()
 C.expect(result==nil and not Asked(L) and Said('Nothing was changed') and Said('first-run plan'),'M14: the choice refuses, asks nothing and names the reason',tostring(result))
 L.Advance(2)
 C.guard(Facts(L)==before,'M14: both plans, the option and Auto are as they were',Facts(L))
end)

C.scenario('M15 Plan\'s destination row says the mode and its state for the destination that uses it; Editing stays the draft',function()
 local L=Boot({before=TwoBuilds,after=function()
  assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(2,'Plan two',{{spellId=200002,quality=2,stacks=1}})) end})
 local function Cell() local row=NexusEditorFrame and NexusEditorFrame._destinationRow;return row and row.cells and tostring(row.cells[3]:GetText()) or '' end
 local function CellHover() local row=NexusEditorFrame._destinationRow;return tostring(row.hits and row.hits[3] and row.hits[3]._nexusFull or row._nexusFull or '') end
 Nexus.WishlistEditor.NewWishlist();L.Advance(1)
 local sw=_G.NexusWishlistEditorSwitchButton
 C.setup(NexusEditorFrame~=nil and NexusEditorFrame:IsVisible() and sw~=nil,'M15: fixture: Plan is open on a new draft for Saved Build 1, nothing assigned there')
 local plain,draft=Cell(),tostring(sw:GetText())
 C.guard(plain:find('Auto-pick',1,true)==nil,'M15: before the choice the row\'s Wishlist cell does not name the mode',plain)
 Use();L.Advance(1)
 C.setup(Option()==true and not Asked(L),'M15: fixture: the mode is selected for Saved Build 1 (nothing assigned, Auto OFF)')
 local menu=_G.NexusWishlistEditorSwitchMenu
 C.guard(menu==nil or not menu:IsVisible(),'M15: the chooser is closed')
 C.expect(Cell():find('Auto-pick by rarity (Auto OFF)',1,true)~=nil,'M15: with the chooser closed the destination row\'s Wishlist cell says the mode and its state',Cell())
 C.guard(tostring(sw:GetText())==draft,'M15: the chooser button still names the draft being edited, not the mode',tostring(sw:GetText()))
 SlashCmdList.NEXUS('auto');L.Advance(2);Nexus.WishlistEditor.Refresh();L.Advance(1)
 C.expect(Cell():find('Auto-pick by rarity (ON)',1,true)~=nil,'M15: after the player\'s own Auto start the cell says ON on the next Plan refresh',Cell())
 Nexus.DisableOrdinaryAutomation();L.Advance(1)
 -- A saved Wishlist of the OTHER Saved Build opened for editing: its row is that destination's.
 sw:GetScript('OnClick')(sw)
 menu=_G.NexusWishlistEditorSwitchMenu
 local saved
 for _,row in ipairs(menu and menu.rows or {}) do if row:IsVisible() and tostring(row._label:GetText()):find('Plan two',1,true) then saved=row end end
 if C.setup(saved~=nil and saved:GetScript('OnClick')~=nil,'M15: fixture: the chooser lists Plan two') then
  saved:GetScript('OnClick')(saved);L.Advance(1)
  C.guard(tostring(sw:GetText()):find('Plan two',1,true)~=nil,'M15: Editing names the opened Wishlist',tostring(sw:GetText()))
  C.guard(Cell():find('Auto-pick',1,true)==nil,'M15: the row of Saved Build 2, which uses that Wishlist, does not show the mode',Cell())
 end
 C.guard(Option()==true and type(Nexus.Store.State().loadoutWishlists[2])=='table','M15: looking and editing changed neither the mode nor the saved assignment')
end)

C.scenario('M16 a first-run-only plan: its Undo row names the first run, and the restore says where the plan went',function()
 local function ServerPlan(h) h.perks.serverActiveSlot=0
  h.perks.serverBuildSlots={[101]={name='Server plan',verified=false,echoes={{spellId=200004,quality=0,stacks=1,locked=false}}}} end
 local function AssignFirstRun()
  local GA=Nexus.GameAdapter
  local chosen
  for _,c in ipairs(GA.GetWishlistCandidates()) do if c.slot==101 then chosen=c end end
  assert(chosen and GA.SetFirstRunWishlist(101,chosen),'fixture: the picker route assigns the server Wishlist to the first run')
 end
 -- The Undo row of Plan's Manage list, read from the real menu.
 local function UndoRow(L)
  local manage=_G.NexusWishlistEditorManageButton
  if not manage then return nil end
  manage:GetScript('OnClick')(manage)
  local found
  for _,f in ipairs(L.frames) do
   if f.kind=='Button' and f:IsVisible() and type(rawget(f,'_label'))=='table'
    and tostring(f._label:GetText()):find('Undo: bring back',1,true) then found=f end
  end
  return found
 end
 local function Removed(L)
  local asked=Use()==true and Open(L)
  Accept(asked)
  L.Advance(1)
  return asked
 end
 local function Kept()
  local out
  for _,entry in ipairs(Nexus.GameAdapter.ForgottenWishlistPlans()) do if entry.name=='Server plan' then out=entry end end
  return out
 end

 -- A: the first run is still the unassigned destination at the Undo.
 local L=Boot({before=ServerPlan,after=AssignFirstRun})
 local GA=Nexus.GameAdapter
 local st=Nexus.Store.State()
 C.setup(type(st.firstRunWishlist)=='table' and (type(st.loadoutWishlists)~='table' or st.loadoutWishlists[1]==nil)
  and GA.AssignedWishlist().name=='Server plan','M16: fixture: a first-run plan alone, with no Saved Build 1 copy',Record(st.firstRunWishlist))
 local key,identity=st.firstRunWishlist.key,st.firstRunWishlist.assignmentId
 C.guard(Removed(L) and Nexus.Store.State().firstRunWishlist==false and Option()==true and not Auto(),
  'M16: the choice removes the first-run assignment, selects the mode and leaves Auto OFF')
 local kept=Kept()
 C.guard(kept~=nil and kept.key==key and kept.assignmentId==identity and kept.rows==1,'M16: the exact plan is kept once as a recoverable entry',kept and kept.key)
 C.expect(kept~=nil and kept.firstRun==true and kept.associationIndex==nil,'M16: the entry says it came from the first run and names no Saved Build index',
  kept and (tostring(kept.firstRun)..' / '..tostring(kept.associationIndex)))
 Nexus.WishlistEditor.NewWishlist();L.Advance(1)
 local row=UndoRow(L)
 local label=row and tostring(row._label:GetText()) or ''
 C.setup(row~=nil and label:find('Server plan',1,true)~=nil,'M16: fixture: Plan\'s Manage list offers the Undo row for the plan',label)
 C.expect(label:find('nil',1,true)==nil and label:find('removed from the first-run target',1,true)~=nil,
  'M16: the Undo row says it was removed from the first-run target, never "nil"',label)
 if row then row:GetScript('OnClick')(row) end
 L.Advance(1)
 st=Nexus.Store.State()
 C.expect(type(st.firstRunWishlist)=='table' and st.firstRunWishlist.key==key and st.firstRunWishlist.assignmentId==identity
  and st.firstRunWishlist.name=='Server plan','M16: the Undo returns the exact plan to the first run, still the unassigned destination',Record(st.firstRunWishlist))
 C.expect(type(st.loadoutWishlists)~='table' or st.loadoutWishlists[1]==nil,'M16: and stores nothing under a Saved Build index',
  Record(type(st.loadoutWishlists)=='table' and st.loadoutWishlists[1] or nil))
 C.expect(Said('selected \'Server plan\' as the first-run wishlist'),'M16: chat says the plan is the first-run Wishlist again')
 C.expect(Kept()==nil and GA.AssignedWishlist().name=='Server plan','M16: the recoverable list no longer holds it and the adapter reads it as assigned to the first run')
 C.guard(not Auto() and #L.actions==0 and Option()==true,'M16: the Undo starts nothing and leaves the option as chosen')
 C.expect(Status().assignment=='assigned' and Status().mode.selected~=true,'M16: the mode is no longer what the first run uses',tostring(Status().assignment))

 -- B: by the Undo a Saved Build is in use, so the first run is not the destination any more.
 L=Boot({before=ServerPlan,after=AssignFirstRun})
 GA=Nexus.GameAdapter
 key=Nexus.Store.State().firstRunWishlist.key
 C.guard(Removed(L) and Kept()~=nil,'M16: fixture: removed again from the first run alone')
 L.perks.serverBuildSlots[1]={name='Build one',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}}
 L.perks.serverActiveSlot=1;L.Notify();L.Advance(1)
 C.setup(GA.NoWishlistTarget().destination~=nil and GA.NoWishlistTarget().destination.kind=='savedBuild','M16: fixture: Saved Build 1 is now in use')
 Nexus.WishlistEditor.NewWishlist();L.Advance(1)
 row=UndoRow(L)
 C.expect(row~=nil and tostring(row._label:GetText()):find('removed from the first-run target',1,true)~=nil,'M16: the Undo row still names the first run as the origin',
  row and row._label:GetText())
 if row then row:GetScript('OnClick')(row) end
 L.Advance(1)
 st=Nexus.Store.State()
 local landed
 for index,record in pairs(type(st.loadoutWishlists)=='table' and st.loadoutWishlists or {}) do
  if type(record)=='table' and record.key==key and record.name=='Server plan' then landed=index end
 end
 C.guard(landed==1 and st.firstRunWishlist==false,'M16: with the first run no longer the destination the plan is stored under the lowest free Saved Build index; the first run stays unassigned',tostring(landed))
 C.expect(Said('Saved Build 1') and Said('first-run target') and Said('none assigned'),
  'M16: chat names the Saved Build index it was stored under and says the first run still has none assigned')
 C.guard(not Auto() and #L.actions==0,'M16: nothing is started or sent')

 -- C (SP-6): after the removal a Saved Build comes into use and gets its own
 -- Wishlist through the real numbered setter, which resets the first-run
 -- record from the explicit Unassign to absent. The Undo of the first-run-only
 -- entry must store it under a free index and leave that record absent.
 L=Boot({before=ServerPlan,after=AssignFirstRun})
 GA=Nexus.GameAdapter
 local first=Nexus.Store.State().firstRunWishlist
 key,identity=first.key,first.assignmentId
 C.guard(Removed(L) and Kept()~=nil,'M16: fixture: removed once more from the first run alone')
 L.perks.serverBuildSlots[1]={name='Build one',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}}
 L.perks.serverActiveSlot=1;L.Notify();L.Advance(1)
 C.setup(GA.SetLoadoutWishlistIdentity(1,'Plan B',{{spellId=200003,quality=3,stacks=1}})==true,'M16: fixture: the real numbered setter assigns Plan B to Saved Build 1')
 L.Advance(1)
 st=Nexus.Store.State()
 C.setup(st.firstRunWishlist==nil and type(st.loadoutWishlists[1])=='table' and st.loadoutWishlists[1].name=='Plan B' and Kept()~=nil,
  'M16: fixture: that assignment reset the first-run record to absent; the removed plan is still recoverable',tostring(st.firstRunWishlist))
 local planB=Record(st.loadoutWishlists[1])
 Nexus.WishlistEditor.NewWishlist();L.Advance(1)
 row=UndoRow(L)
 C.guard(row~=nil and tostring(row._label:GetText()):find('removed from the first-run target',1,true)~=nil,'M16: the Undo row names the first run as the origin',row and row._label:GetText())
 if row then row:GetScript('OnClick')(row) end
 L.Advance(2)
 st=Nexus.Store.State()
 landed=nil
 for index,record in pairs(type(st.loadoutWishlists)=='table' and st.loadoutWishlists or {}) do
  if type(record)=='table' and record.key==key and record.assignmentId==identity and record.name=='Server plan' then landed=index end
 end
 C.guard(landed==2 and Record(st.loadoutWishlists[1])==planB and Kept()==nil,'M16: the exact plan is stored under the lowest free index, 2; Plan B on Saved Build 1 is untouched',tostring(landed))
 C.expect(st.firstRunWishlist==nil,'M16: the Undo of a first-run-only entry does not put a first-run record back',Record(st.firstRunWishlist))
 C.expect(Said('came back as Saved Build 2') and Said('The first-run target is unchanged: none assigned') and st.firstRunWishlist==nil,
  'M16: chat names Saved Build 2 and truthfully says the first-run target is unchanged with none assigned')
 local target=GA.NoWishlistTarget()
 C.expect(target.state=='assigned' and target.name=='Plan B' and target.reason==nil,'M16: Saved Build 1 still reads as assigned to Plan B, with no first-run plan waiting behind it',
  tostring(target.state)..' / '..tostring(target.reason))
 -- The newer assignment is then removed by the existing Unassign; the adapter's
 -- own later reads must hand nothing to Saved Build 1.
 C.setup(GA.ClearLoadoutWishlist(1)==true,'M16: fixture: Plan B is unassigned from Saved Build 1 by the existing Unassign')
 L.Advance(3)
 st=Nexus.Store.State()
 local a=GA.AssignedWishlist()
 C.expect(st.loadoutWishlists[1]==nil and a.knownUnassigned==true and a.name==nil,'M16: after the adapter\'s next reads Saved Build 1 has nothing assigned: the recovered plan is not handed to it',
  Record(st.loadoutWishlists[1])..' / '..tostring(a.state)..' / '..tostring(a.name))
 C.guard(type(st.loadoutWishlists[2])=='table' and st.loadoutWishlists[2].key==key and st.loadoutWishlists[2].assignmentId==identity,
  'M16: the recovered plan stays where the Undo stored it, with its exact contents')
 C.guard(not Auto() and #L.actions==0,'M16: nothing is started or sent')
end)

print=realPrint
C.finish('(real TOC boot, adapter, runtime and commands over the synthetic harness; native look and client dialog NOT RUN)')
