-- Guided setup context, choice marks and the Step 7 rows (issue #131 guide
-- behaviour, #163 visual composition; native QA test.163008 follow-up):
-- V1 a Wishlist the active Saved Build already follows says Assigned now
--    before any choice, and is not selected, chosen, completed or written;
-- V2 choosing other cards keeps one selected card, which the footer names
--    alone, while Assigned now stays with what the game follows; an existing
--    link is then only observed, never verified by the guide;
-- V3 Wishlists holding the same Echoes (one content key): only the one the
--    read back names is marked; under one shared name none is;
-- V4 failing and missing read backs, an unassigned build, a change by
--    another route and a link of a Saved Build that is not active: never a
--    guessed or stale mark;
-- V5 replay and an offline reload keep the coach's own choice and the
--    assignment read now apart, and the summary stays honest; its Already
--    linked row has its own icon, apart from a confirmed or chosen one;
-- V6 Step 7 in the compact and desktop windows at the default text model:
--    every row an icon and a 12 px word, Go to step a link on the row's
--    detail line (no button stacked under the chip), rows two text lines
--    tall, and the optional lessons in view or one scroll away;
-- V7 the choice cards' mark is the client's round radio button
--    (UIRadioButtonTemplate, as the Sync mode dialog uses it), checked for
--    the one choice and taking no mouse; no painted square remains.
-- EXPECT: added behaviour. On 0e5b84d7 (this pass's base) no card says
-- Assigned now, the mark is three painted squares, the Step 7 chip is one
-- 10 px text and Go to step a 22 px button under it, so each EXPECT fails
-- there by design. GUARD: what must already hold: reading and rendering
-- select, receipt, complete, keep, write, act, send, spend and toggle nothing.
-- SETUP: fixture state. Real TOC boots through format5_support; a reload is
-- an offline module reload of round-tripped literal saved data, not a client
-- /reload. Text is measured by layout_geometry_support's stated model. The
-- client's radio art, fonts, pixels, mouse dispatch and SavedVariables
-- writing are NOT RUN; no native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('visual_guide_context_163009')
local H,A,G,U,writes,spends
local HOST={}
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity',
 'UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local NAMES={'ProjectEbonholdEchoJournal','EchoJournalMicroButton','NexusEditorFrame','NexusWishlistNameInput',
 'NexusActiveWishlistSelector','NexusWishlistOnlyPicker','NexusLoadoutAssociationPanel','NexusGuidedSetup',
 'NexusGuidedSetupEscape','NexusQuickStart','NexusQuickStartEscape','NexusHelpWindow','NexusSetupChecklist',
 'NexusOverwriteWarning','NexusOverwriteWarningScroll','NexusPanel','NexusFontNormal'}
-- core/GuidedSetup.lua PLACE_KEY: the coach's one kept record.
local KEY='guidedSetupPlaceV1'
local ROUND='UIRadioButtonTemplate'
local WHITE='Interface\\Buttons\\WHITE8X8'
-- The stock 12 px font objects (GameFontNormal, GameFontHighlight); the
-- Small ones are 10 px. A client font fact this harness cannot measure.
local TWELVE={GameFontNormal=true,GameFontHighlight=true}
local NOW='Assigned now'

local function Clear() for _,n in ipairs(NAMES) do _G[n]=nil end end

-- The synthetic host before the TOC loads: Saved Builds 1 and 2 (2 active),
-- server Wishlists W-Six, W-Free and W-Copy, where W-Copy holds W-Free's
-- Echoes (one content key) under its own name and slot. HOST.twin names it
-- W-Free too (same Echoes, same name, two server slots). A counted Orb
-- service. Every frame keeps the template it was made from and every font
-- string the font object it was made with, and a CheckButton what its mouse
-- was set to (the harness drops all three).
local function Host(h)
 h.playerLevel=80;wipe(h.db)
 h.AddEcho(201172,'Echo One',0,5);h.AddEcho(201173,'Echo Six',0,5)
 h.AddEcho(201174,'Echo Free',0,5);h.AddEcho(201175,'Echo Fire',0,5)
 h.service.GetServerMaxSlots=function() return 6 end
 h.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF},
  [108]={name=HOST.twin and 'W-Free' or 'W-Copy',verified=false,echoes={{spellId=201174,quality=0,stacks=1}}}}
 h.perks.serverActiveSlot=2
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function() return true end,GetCharges=function() return 0 end,
  IsOfferPending=function() return false end,RequestCharges=function() end,
  ConfirmSpend=function() spends=spends+1;return false end}
 local make=CreateFrame
 CreateFrame=function(kind,name,parent,template,...)
  local f=make(kind,name,parent,template,...)
  f._template=template
  local fonts=f.CreateFontString
  f.CreateFontString=function(self,n,layer,font,...) local fs=fonts(self,n,layer,font,...);fs._font=font;return fs end
  if kind=='CheckButton' then f.EnableMouse=function(self,on) self._mouse=on and true or false end end
  return f
 end
end

local function Guide() return _G.NexusGuidedSetup end
local function Shown() local g=Guide();return g~=nil and g:IsShown() end
local function Find(exact,text)
 local g=Guide();if not g then return nil end
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local t=V.Plain(c:GetText() or '')
   if (exact and t==text) or (not exact and t:find(text,1,true)) then return c end
  end
 end
end
local function Btn(t) return Find(true,t) end
local function Opt(t) return Find(false,t) end
local function Press(b) if b then b:Click() end return b~=nil end
local function On(b) return b~=nil and b:IsEnabled() end
local function Text() return Guide() and V.Plain(U.VisibleText() or '') or '' end
local function Step() return G and G.StepId() or nil end
local function Kept() return G.PlaceKept() end
local function Stored(slot) local s=Nexus.Store.State();return s.loadoutWishlists and s.loadoutWishlists[slot] end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Quiet() return table.concat({#H.actions,#H.sent,spends,tostring(Auto())},'/') end
local function Effects() return Writes()..'/'..Quiet() end
local function Saved() return F.Serialize(NexusDB) end

-- The coach's shown choice rows, and their label, description and marks.
local function Rows()
 local out,g={},Guide()
 for _,c in ipairs(g and g.children or {}) do
  if c.kind=='Button' and c.radio~=nil and c.desc~=nil and c:IsShown() then out[#out+1]=c end
 end
 return out
end
local function Label(r) return V.Plain(r:GetText() or '') end
local function Desc(r) return r.desc:IsShown() and V.Plain(r.desc:GetText() or '') or '' end
local function Tagged(r) return Desc(r):find(NOW,1,true)~=nil end
-- Read through the round mark itself (V7): shown and checked.
local function Checked(r) return r.radio:IsShown() and type(r.radio.GetChecked)=='function' and r.radio:GetChecked()==true end
-- The Theme's selected look (Theme.SetSelected), the existing selection.
local function Picked(r) return r._nexusSelected==true end
-- The server Wishlist cards of the Wishlist step (their names start W-).
local function Cards()
 local out={}
 for _,r in ipairs(Rows()) do if Label(r):find('^W%-') then out[#out+1]=r end end
 return out
end
local function Card(name) for _,r in ipairs(Cards()) do if Label(r)==name then return r end end end
local function Names(test)
 local out={}
 for _,r in ipairs(Cards()) do if test(r) then out[#out+1]=Label(r) end end
 table.sort(out);return table.concat(out,',')
end
local function Tags() return Names(Tagged) end
local function Checks() return Names(Checked) end
local function Selected() return Names(Picked) end
-- The coach's own progress: its choices, request, receipts, summary and kept
-- place. Reading what Nexus follows now must change none of it.
local function Progress()
 local s=G.State()
 local row=Nexus.Store.State()
 return table.concat({tostring(s.wishlist and s.wishlist.name),tostring(s.target and s.target.destination),
  tostring(s.request~=nil),tostring(s.skipped.wishlist),#G.Receipts(),F.Serialize(G.Summary()),
  F.Serialize(type(row)=='table' and rawget(row,KEY) or nil)},' | ')
end

-- After a boot: the host read once, counted adapter writers, the Echo
-- Journal frames, and no window of the boot left open.
local function Settle(tag)
 A,G,U=Nexus.GameAdapter,Nexus.GuidedSetup,Nexus.GuidedSetupUI
 H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do local real=A[k]
  if type(real)=='function' then writes[k]=0;A[k]=function(...) writes[k]=writes[k]+1;return real(...) end end end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 if Shown() then Press(Btn('X')) end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
 local status=Nexus.Store.StateWriteStatus()
 return C.setup(status.mode=='durable' and Nexus.StartupStatus().coreReady==true and G~=nil and U~=nil and not Shown(),
  tag..': fixture: booted (durable saved data), no window open',status.mode)
end
local function Boot(tag,host,db)
 HOST=host or {};Clear();H=F.Boot(db,Host)
 return Settle(tag)
end
local function TW() return Nexus.UserText.Guide.wishlist end
-- Welcome's existing path, then the Wishlist step.
local function ToWishlist()
 U.Show();Press(Opt('I already have'));Press(Btn('Continue'))
 return Step()=='wishlist'
end
local function Assign(dest,slot,name)
 return A.SetLoadoutWishlist(dest,slot)==true and Stored(dest)~=nil and Stored(dest).name==name
end

C.scenario('V1 the Wishlist the active Saved Build follows says Assigned now before any choice; nothing is selected or done',function()
 if not Boot('V1') then return end
 if not C.setup(Assign(2,107,'W-Free') and A.SelectedSavedBuild()==2,'V1: fixture: Fire PvE (Saved Build 2, active) follows W-Free') then return end
 local before=Effects()
 if not C.setup(ToWishlist() and #Cards()==3,'V1: fixture: the Wishlist step lists W-Six, W-Free and W-Copy',Step()) then return end
 local progress=Progress()
 C.expect(Tags()=='W-Free','V1: exactly the Wishlist Fire PvE follows says Assigned now, before any choice',Tags())
 local free=Card('W-Free')
 C.expect(free~=nil and Desc(free):find('Slot 2 - Fire PvE',1,true)~=nil,'V1: it names the active Saved Build it is assigned to',free and Desc(free))
 C.guard(Selected()=='' and G.State().wishlist==nil,'V1: no card is selected for the player',Selected())
 C.guard(Checks()=='','V1: no round mark is checked',Checks())
 local t=Text()
 C.guard(t:find(TW().selectedNone,1,true)~=nil and t:find(TW().chosen:match('^(.-)%%s'),1,true)==nil,
  'V1: the footer says nothing is selected and no Wishlist is named chosen',t)
 C.guard(not On(Btn('Continue')),'V1: Continue still waits for the player\'s own choice')
 U.Render();U.Render()
 C.guard(Progress()==progress,'V1: reading and rendering it set no choice, receipt, result or kept place',Progress())
 local sm=G.Summary()
 C.guard(sm.wishlist=='todo' and sm.assign=='todo' and sm.complete==false and sm.trueNow==false and sm.open==3,
  'V1: the summary counts no guide step from the game\'s own assignment',F.Serialize(sm))
 C.guard(Effects()==before and Stored(2).name=='W-Free','V1: showing it assigned, wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('V2 choosing other cards: one selected card, named alone by the footer; Assigned now stays with the game',function()
 if not Boot('V2') then return end
 if not C.setup(Assign(2,107,'W-Free'),'V2: fixture: Fire PvE follows W-Free') then return end
 local before=Effects()
 if not C.setup(ToWishlist(),'V2: fixture: the Wishlist step',Step()) then return end
 local function Pick(tag,name)
  Press(Card(name))
  local w,t=G.State().wishlist,Text()
  C.guard(Selected()==name and w~=nil and w.name==name and t:find(TW().selected:format(name),1,true)~=nil
   and t:find(TW().chosen:format(name),1,true)~=nil,tag..': the one selected card is '..name..', the choice the footer names',Selected())
  for _,r in ipairs(Cards()) do
   if Label(r)~=name then C.guard(t:find(TW().selected:format(Label(r)),1,true)==nil,tag..': the footer names no other card: '..Label(r)) end
  end
  C.expect(Checks()==name,tag..': its round mark is the one checked',Checks())
  C.expect(Tags()=='W-Free',tag..': Assigned now still marks W-Free, what Fire PvE follows',Tags())
  C.guard(Stored(2)~=nil and Stored(2).name=='W-Free',tag..': the choice changed no assignment')
 end
 Pick('V2 W-Six','W-Six')
 Pick('V2 W-Six then W-Copy','W-Copy')
 Pick('V2 then W-Free','W-Free')
 local free=Card('W-Free')
 C.expect(free~=nil and Checked(free) and Tagged(free),'V2: the chosen card that is also assigned now says both')
 Pick('V2 then W-Six again','W-Six')
 Pick('V2 then W-Free again','W-Free')
 Press(Btn('Continue'))
 if not C.setup(Step()=='target' and Press(Opt('Fire PvE')) and G.TargetFacts()~=nil and G.TargetFacts().already==true,
  'V2: fixture: Fire PvE chosen; it already follows W-Free',Step()) then return end
 Press(Btn('Continue'))
 local st=G.AssignStatus().state
 C.guard(Step()=='assign' and st=='observed' and G.CanNext(),'V2: the existing link is observed, not verified by this guide',st)
 local sm=G.Summary()
 C.guard(sm.complete==false and sm.trueNow==true,'V2: true now, not completed by the guide',F.Serialize(sm))
 C.guard(Effects()==before,'V2: choosing and moving assigned, wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('V3 Wishlists holding the same Echoes: only the one read back says Assigned now; under one name none does',function()
 if not Boot('V3') then return end
 local key={}
 for _,c in ipairs(G.WishlistOptions() or {}) do key[tonumber(c.slot) or 0]=c.key end
 if not C.setup(key[107]~=nil and key[107]==key[108] and key[106]~=key[107],'V3: fixture: W-Free and W-Copy share one content key') then return end
 if not C.setup(Assign(2,108,'W-Copy'),'V3: fixture: Fire PvE follows W-Copy') then return end
 local before=Effects()
 if not C.setup(ToWishlist(),'V3: fixture: the Wishlist step',Step()) then return end
 C.expect(Tags()=='W-Copy','V3: only W-Copy, the one read back, says Assigned now; W-Free with the same Echoes does not',Tags())
 Press(Card('W-Free'))
 C.guard(Selected()=='W-Free' and G.State().wishlist.slot==107,'V3: choosing W-Free selects W-Free itself',Selected())
 C.expect(Tags()=='W-Copy' and Checks()=='W-Free','V3: the selected card and the assigned card stay two different cards',Tags()..' / '..Checks())
 C.guard(Effects()==before,'V3: nothing was written, acted, sent, spent or toggled',Effects())
 -- The same Echoes under the same name in two server slots: the read back
 -- cannot name one of them, so neither is marked, and the step says why.
 if not Boot('V3 twin',{twin=true}) then return end
 local twins=0
 for _,c in ipairs(G.WishlistOptions() or {}) do if c.name=='W-Free' then twins=twins+1 end end
 if not C.setup(twins==2 and Assign(2,107,'W-Free'),'V3 twin: fixture: two W-Free rows with the same Echoes; Fire PvE follows the one in slot 107',twins) then return end
 local quiet=Quiet()
 if not C.setup(ToWishlist(),'V3 twin: fixture: the Wishlist step',Step()) then return end
 local t=Text()
 C.guard(Tags()=='','V3 twin: neither W-Free row says Assigned now',Tags())
 C.expect(t:find('More than one listed Wishlist',1,true)~=nil or t:find('could not be read',1,true)~=nil,
  'V3 twin: the step says the assignment cannot be pinned to one row (or could not be read)',t)
 C.guard(Selected()=='' and Checks()=='' and G.State().wishlist==nil,'V3 twin: nothing is selected for the player')
 C.guard(Quiet()==quiet,'V3 twin: nothing was acted, sent, spent or toggled',Quiet())
end)

C.scenario('V4 failing, missing, unassigned, changed and inactive reads: never a guessed or stale Assigned now',function()
 if not Boot('V4') then return end
 if not C.setup(Assign(2,107,'W-Free'),'V4: fixture: Fire PvE follows W-Free') then return end
 local quiet=Quiet()
 -- Each render is one read; the writes it made, if any, are counted apart
 -- from the fixture's own writes by other routes.
 local drawn=0
 local function Draw() local w=Writes();U.Render();drawn=drawn+(Writes()-w) end
 local w=Writes()
 if not C.setup(ToWishlist(),'V4: fixture: the Wishlist step',Step()) then return end
 drawn=drawn+(Writes()-w)
 C.expect(Tags()=='W-Free','V4: W-Free says Assigned now',Tags())
 local real=A.GetLoadoutWishlistState
 A.GetLoadoutWishlistState=function() error('synthetic readback failure') end
 Draw()
 C.guard(Tags()=='','V4: a failing read back marks no Wishlist',Tags())
 C.expect(Text():find('could not be read',1,true)~=nil,'V4: the step says what is assigned now could not be read',Text())
 A.GetLoadoutWishlistState=nil
 Draw()
 C.guard(Tags()=='','V4: a missing reader marks no Wishlist',Tags())
 C.expect(Text():find('could not be read',1,true)~=nil,'V4: a missing reader is said to be unread, not unassigned',Text())
 A.GetLoadoutWishlistState=real
 Draw()
 C.expect(Tags()=='W-Free' and Text():find('could not be read',1,true)==nil,'V4: the real read back marks it again',Tags())
 -- Changes by other routes while the step is open: each render reads anew.
 C.setup(A.ClearLoadoutWishlist(2)==true and Stored(2)==nil,'V4: fixture: another route unassigns Fire PvE')
 Draw()
 C.guard(Tags()=='' and Text():find('could not be read',1,true)==nil,'V4: an unassigned build marks nothing and is not called unread',Tags())
 C.setup(Assign(2,106,'W-Six'),'V4: fixture: another route assigns W-Six to Fire PvE')
 Draw()
 C.expect(Tags()=='W-Six','V4: the mark follows the fresh read back, never the earlier one',Tags())
 -- Only the destination Nexus uses now counts: a link of a Saved Build that
 -- is not active is that build's own, not Assigned now.
 C.setup(A.ClearLoadoutWishlist(2)==true and Assign(1,107,'W-Free') and A.SelectedSavedBuild()==2,
  'V4: fixture: only Saved Build 1 (not active) follows W-Free')
 Draw()
 C.guard(Tags()=='','V4: a Wishlist only an inactive Saved Build follows does not say Assigned now',Tags())
 C.guard(G.State().wishlist==nil and Selected()=='' and Checks()=='','V4: none of these reads selected anything')
 C.guard(drawn==0 and Quiet()==quiet,'V4: showing and rendering wrote, acted, sent, spent and toggled nothing; only the fixture wrote',Effects())
end)

-- One summary row's icon glyph and status word, by row order: the icon is
-- the 14 px wide 12 px-font text, the word the 12 px text drawn just before it.
local function Chips()
 local out,regions={},U.TextRegions()
 for i,fs in ipairs(regions) do
  if fs._font=='GameFontNormal' and fs:GetWidth()==14 then
   local prev=regions[i-1]
   local word=prev and prev._font=='GameFontHighlight' and prev or nil
   out[#out+1]={glyph=V.Plain(fs:GetText() or ''),word=word and V.Plain(word:GetText() or '') or nil,fs=fs,wordFs=word}
  end
 end
 return out
end

C.scenario('V5 replay and reload keep the coach\'s choice and the assignment read now apart; the summary stays honest',function()
 if not Boot('V5') then return end
 if not C.setup(Assign(2,107,'W-Free'),'V5: fixture: Fire PvE follows W-Free') then return end
 local before=Effects()
 if not C.setup(ToWishlist() and Press(Card('W-Six')) and G.State().wishlist~=nil and G.State().wishlist.name=='W-Six'
  and Kept()=='saved','V5: fixture: W-Six chosen; the place is kept',Kept()) then return end
 U.Replay()
 C.guard(Step()=='welcome' and G.State().wishlist==nil,'V5 replay: Welcome again, with no choice',Step())
 if not C.setup(Press(Opt('I already have')) and Press(Btn('Continue')) and Step()=='wishlist','V5 replay: fixture: the Wishlist step again') then return end
 C.expect(Tags()=='W-Free','V5 replay: W-Free still says Assigned now, read again',Tags())
 C.guard(Selected()=='' and G.State().wishlist==nil and Text():find(TW().selectedNone,1,true)~=nil,
  'V5 replay: nothing is selected for the player',Selected())
 Press(Card('W-Six'));Press(Btn('X'))
 C.guard(Effects()==before,'V5: choosing, replaying and closing assigned, wrote, acted, sent, spent and toggled nothing',Effects())
 if not C.setup(not Shown() and rawget(Nexus.Store.State(),KEY)~=nil,'V5: fixture: closed with the place kept') then return end
 local db=assert(loadstring('return '..Saved()))()
 if not Boot('V5 reload',{},db) then return end
 local receipts=#G.Receipts()
 U.Show()
 local s=G.State()
 C.guard(Step()=='wishlist' and s.wishlist~=nil and s.wishlist.name=='W-Six' and s.wishlist.source=='existing',
  'V5 reload: the kept choice W-Six is taken again from what Nexus lists',Step())
 C.guard(Selected()=='W-Six' and Text():find(TW().selected:format('W-Six'),1,true)~=nil,'V5 reload: one selected card, W-Six, and the footer names it',Selected())
 C.expect(Checks()=='W-Six','V5 reload: its round mark is the one checked',Checks())
 C.expect(Tags()=='W-Free','V5 reload: W-Free, what Fire PvE follows after the reload, says Assigned now; the kept choice does not',Tags())
 local sm=G.Summary()
 C.guard(sm.wishlist=='done' and sm.target=='todo' and sm.assign=='todo' and sm.complete==false and sm.trueNow==false
  and #G.Receipts()==receipts,'V5 reload: only the kept choice counts; nothing is confirmed or received',F.Serialize(sm))
 -- Another route assigns W-Six: the chosen card is now also the one assigned.
 local quiet=Quiet()
 C.setup(Assign(2,106,'W-Six'),'V5 reload: fixture: another route assigns W-Six to Fire PvE')
 local w0=Writes()
 U.Render()
 C.expect(Tags()=='W-Six' and Checks()=='W-Six','V5 reload: the chosen W-Six is now also the one assigned, read anew',Tags()..' / '..Checks())
 Press(Btn('Continue'));Press(Opt('Fire PvE'));Press(Btn('Continue'))
 if not C.setup(Step()=='assign' and G.AssignStatus().state=='observed','V5: fixture: the link is observed',G.AssignStatus().state) then return end
 Press(Btn('Continue'));Press(Btn('Skip for now'));Press(Btn('Skip for now'))
 if not C.setup(Step()=='summary','V5: fixture: at the summary',Step()) then return end
 sm=G.Summary()
 local t=Text()
 C.guard(sm.assign=='observed' and sm.complete==false and sm.trueNow==true and t:find('Read back; not changed by this guide',1,true)~=nil
  and t:find('Confirmed by read back',1,true)==nil,'V5: the summary shows the link as read back, not confirmed by this guide',t)
 local chips=Chips()
 local function At(i) return chips[i] or {} end
 C.expect(#chips==5,'V5: each of the five summary rows has its own status icon',#chips)
 C.expect(At(3).glyph=='=' and At(1).glyph=='+' and At(3).glyph~=At(1).glyph,
  'V5: Already linked has its own icon, apart from the chosen and confirmed one',tostring(At(1).glyph)..' / '..tostring(At(3).glyph))
 C.guard(At(3).word==Nexus.UserText.Guide.words.linked,'V5: its word says Already linked',At(3).word)
 C.expect(At(4).glyph=='-' and At(4).word=='Skipped' and At(4).glyph~=At(3).glyph,'V5: a skipped step has another icon and word',At(4).glyph)
 C.guard(Writes()==w0 and Quiet()==quiet,'V5 reload: after the fixture write, rendering and moving wrote, acted, sent, spent and toggled nothing',Effects())
end)

-- Step 7 with every step skipped while W-Free is assigned now, checked in one
-- presentation: honest counts, the rows' icons, words and Go to step links,
-- their height, and the optional lessons in view or one scroll away.
local function SummaryChecks(tag,g)
 local T=Nexus.UserText.Guide
 local fin,line=T.finish,L.model.line
 local t=Text()
 C.guard(t:find('Not finished: 3 steps still open',1,true)~=nil and G.Summary().trueNow==false,
  tag..': the summary counts the three open steps; the game\'s own assignment completes none',t)
 local root=L.Rect(g,g)
 -- The rows' labels in order, and the text under the last row.
 local labels,sent={},nil
 for _,fs in ipairs(U.TextRegions()) do
  local s=V.Plain(fs:GetText() or '')
  for _,id in ipairs({'wishlist','target','assign','manual','auto'}) do
   if s==fin.rows[id] and not labels[id] then labels[id]=L.Rect(fs,g) end
  end
  if s==fin.sent then sent=L.Rect(fs,g) end
 end
 local ids={'wishlist','target','assign','manual','auto'}
 local all=sent~=nil
 for _,id in ipairs(ids) do all=all and labels[id]~=nil end
 if not C.setup(all,tag..': fixture: the five rows and the line under them are in view') then return end
 local chips=Chips()
 C.expect(#chips==5,tag..': five status icons',#chips)
 for i,chip in ipairs(chips) do
  C.expect(chip.glyph=='-' and chip.word=='Skipped' and TWELVE[chip.fs._font] and chip.wordFs~=nil and TWELVE[chip.wordFs._font],
   tag..': row '..i..' shows its icon and its word in the 12 px font',tostring(chip.glyph)..' '..tostring(chip.word))
 end
 -- Go to step: one link per open row, inside that row, at most 18 px tall,
 -- in the 12 px font, right of the row's text, never over another control.
 local goes={}
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() and V.Plain(c:GetText() or '')==T.buttons.goStep then goes[#goes+1]={c,L.Rect(c,g)} end
 end
 table.sort(goes,function(a,b) return a[2][2]<b[2][2] end)
 C.guard(#goes==5,tag..': every skipped step offers Go to step',#goes)
 for i,id in ipairs(ids) do
  local go=goes[i]
  local top,bottom=labels[id][2],(ids[i+1] and labels[ids[i+1]] or sent)[2]
  if go then
   local r=go[2]
   C.expect(r[2]>=top and r[4]<=bottom and r[4]-r[2]<=18 and r[1]>=labels[id][3],
    tag..': Go to step for '..id..' is a link inside its own row, right of its text',L.Text(r)..' row '..top..'..'..bottom)
   C.expect(go[1].label~=nil and TWELVE[go[1].label._font],tag..': Go to step for '..id..' reads in the 12 px font')
  end
  -- Two text lines (label and detail) plus the chip and link padding; the
  -- 22 px button stacked under the chip made a row 2*line+32 tall.
  if ids[i+1] then
   C.expect(bottom-top<=2*line+24,tag..': the '..id..' row is two lines tall, not inflated',bottom-top)
  end
 end
 local shown={}
 for _,c in ipairs(g.children) do if c.kind=='Button' and c:IsShown() then shown[#shown+1]={c,L.Rect(c,g)} end end
 for i=1,#shown do
  C.guard(L.Inside(shown[i][2],root),tag..': inside the coach: '..V.Plain(shown[i][1]:GetText() or ''),L.Text(shown[i][2]))
  for j=i+1,#shown do
   C.guard(L.Apart(shown[i][2],shown[j][2]),tag..': no overlap: '..V.Plain(shown[i][1]:GetText() or '')..' / '..V.Plain(shown[j][1]:GetText() or ''))
  end
 end
 -- Go to step only moves the guide.
 local quiet,w0=Quiet(),Writes()
 if goes[3] then Press(goes[3][1]) end
 C.guard(Step()=='assign' and Quiet()==quiet and Writes()==w0,tag..': Go to step moves to that step and changes nothing',Step())
 G.GoTo('summary');U.Render()
 -- The optional lessons: in view, or the body scrolls to them.
 local st=U.ScrollState()
 if st then
  C.guard(st.max>0 and On(Btn('v')),tag..': the summary scrolls and its down control works',st.max)
  U.ScrollBy(100000)
 end
 for _,l in ipairs(fin.lessons or {}) do
  local b=Opt(l.title)
  C.guard(b~=nil and L.Inside(L.Rect(b,g),root),tag..': the optional lesson '..l.title..' is in view (or one scroll away)')
 end
 local orbs=(fin.lessons or {})[1]
 if orbs and Press(Opt(orbs.title)) then
  C.guard(Text():find('spends nothing',1,true)~=nil,tag..': the lesson opens in place and reads only',Text())
  Press(Opt(orbs.title))
 end
 C.guard(Quiet()==quiet and Writes()==w0,tag..': reading the summary acted, sent, spent, wrote and toggled nothing',Effects())
end

C.scenario('V6 Step 7: an icon and a 12 px word per row, Go to step a link on the row, two-line rows, lessons reachable',function()
 if not Boot('V6') then return end
 if not C.setup(Assign(2,107,'W-Free'),'V6: fixture: Fire PvE follows W-Free') then return end
 L.UseFont(L.MODELS.default)
 UIParent:SetSize(800,600)
 local before=Effects()
 if not C.setup(ToWishlist(),'V6: fixture: the Wishlist step') then return end
 for _=1,5 do Press(Btn('Skip for now')) end
 local g=Guide()
 if not C.setup(Step()=='summary' and g:GetWidth()==420,'V6: fixture: everything skipped; the compact summary',Step()) then return end
 SummaryChecks('V6 compact',g)
 UIParent:SetSize(1024,768)
 U.Render()
 if C.setup(g:GetWidth()==900,'V6: fixture: the desktop window',g:GetWidth()) then SummaryChecks('V6 desktop',g) end
 C.guard(Effects()==before and Stored(2).name=='W-Free','V6: the whole flow assigned, wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('V7 choice cards carry the client\'s round radio mark, checked for the one choice, taking no mouse; no square',function()
 if not Boot('V7') then return end
 local before=Effects()
 U.Show()
 local function Marks(tag,want)
  local bad,checked,n={},{},0
  for _,r in ipairs(Rows()) do
   local m=r.radio
   if m:IsShown() then
    n=n+1
    if not (m.kind=='CheckButton' and m._template==ROUND and m._mouse==false and m:GetParent()==r) then bad[#bad+1]=Label(r) end
    if type(m.GetChecked)=='function' and m:GetChecked()==true then checked[#checked+1]=Label(r) end
   end
   for _,tex in ipairs(r.regions or {}) do
    if tex.kind=='Texture' and tex:IsShown() and tex:GetTexture()==WHITE and tex.width==tex.height and tex.width<=12 then
     bad[#bad+1]=Label(r)..' (painted square)'
    end
   end
  end
  table.sort(checked)
  C.expect(n>0 and #bad==0,tag..': every choice mark is the client round radio button, taking no mouse; no painted square',table.concat(bad,', '))
  C.expect(table.concat(checked,',')==(want or ''),tag..': the checked mark is exactly the choice',table.concat(checked,','))
 end
 Marks('V7 Welcome',nil)
 Press(Opt('New to Nexus'));Marks('V7 Welcome New','New to Nexus')
 Press(Opt('I already have'));Marks('V7 Welcome existing','I already have a Saved Build')
 Press(Btn('Continue'))
 if not C.setup(Step()=='wishlist','V7: fixture: the Wishlist step',Step()) then return end
 Marks('V7 Wishlist',nil)
 Press(Card('W-Free'));Marks('V7 W-Free','W-Free')
 Press(Card('W-Copy'));Marks('V7 W-Free then W-Copy','W-Copy')
 -- The paste field is the one choice while open; the listed one shows unchosen.
 Press(Btn(TW().importTitle));Marks('V7 paste field',TW().importTitle)
 Press(Card('W-Copy'));Press(Btn('Continue'))
 if not C.setup(Step()=='target','V7: fixture: the Saved Build step',Step()) then return end
 Marks('V7 target',nil)
 local one=Opt('Slot 1 - One')
 Press(one);Marks('V7 target Slot 1',one and Label(one) or '?')
 local fire=Opt('Fire PvE')
 Press(fire);Marks('V7 target Slot 2',fire and Label(fire) or '?')
 Press(Btn('Back'))
 Marks('V7 back over recycled rows','W-Copy')
 C.guard(Effects()==before,'V7: choosing and moving assigned, wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.finish('(Assigned now read apart from the coach\'s choice; round single-choice marks; compact Step 7 rows)')
