-- Group 10a (S5-C9): the My Builds / Assign Wishlist fallback calls the native
-- EchoJournal.Show with a valid argument.
-- Native (static data, never executed): echo_journal.lua 5406-5412 defines
-- Journal.Show(tab) as a dot-call that selects `tab or currentTab`; the tabs
-- are 1, 2, 3 (TAB_MY_RUN, TAB_ALL, TAB_LOADOUTS, line 43); the native caller
-- player_run_ui.lua 895 uses EchoJournal.Toggle(1). ui/Panel.lua's fallback,
-- taken only when Nexus.JournalTab.OpenBuilds is missing, calls
-- pcall(pe.EchoJournal.Show, pe.EchoJournal): the module table becomes `tab`.
-- Destination (supplement r2): no source maps either button to a tab index.
-- The primary helper (ui/JournalTab.lua 998-1062) enters through the
-- Character Progression micro button, never Journal.Show. Natively, tab 3
-- (Loadouts, whose sub-view is "My Builds", echo_journal.lua 5150-5166) is
-- "no longer a separate reachable tab" (4647-4649, 4706-4708) and tab 1 is the
-- dead standalone entrypoint (4355-4356, 4529-4531); nothing ties these
-- buttons to tab 2 either. The native standalone fallback itself passes no tab
-- (echo_journal.lua 5566 Journal.Toggle()). So the healthy fallback passes no
-- tab and the native current tab applies; an invented index is not accepted.
-- EXPECT (fails at 8c): with the primary helper missing, each of the two
-- Panel buttons calls the native Show once with no tab argument (the native
-- current tab), never with the module table or an unestablished index.
-- GUARD (holds at 8c): with the primary helper present it is used and the
-- native Show is not called; one Show per click (no duplicate open); no game
-- or network action.
-- SETUP: real TOC boot and real Panel buttons; the native Show is a synthetic
-- spy; the missing primary helper is deliberate fault injection.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_journal_fallback_argument')
local printable=B.printable
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database())
C.setup(Nexus.StartupStatus().coreReady==true,'start-up reached core-ready')
Nexus.Panel.Toggle()
local panel=_G.NexusPanel
local buttons={{'My Builds',panel and panel._switchBtn}}
for _,f in ipairs(panel and panel.children or {}) do
 if f.kind=='Button' and B.Plain(f:GetText() or '')=='Assign Wishlist' then buttons[2]={'Assign Wishlist',f} end
end
C.setup(buttons[1][2]~=nil and buttons[2]~=nil,'the real My Builds and Assign Wishlist buttons exist')
local native=ProjectEbonhold.EchoJournal
local primary=Nexus.JournalTab and Nexus.JournalTab.OpenBuilds
C.setup(type(primary)=='function','the normal TOC loads the primary helper')
local calls,primaryCalls={},0
local realShow=native.Show
native.Show=function(...) calls[#calls+1]={n=select('#',...),tab=(...)} end
-- No source establishes a tab index for these buttons (see the header): only
-- the native current tab (no argument) is a supported destination.
local function NoTab(tab)
 return tab==nil
end

for _,entry in ipairs(buttons) do
 local label,button=entry[1],entry[2]
 C.scenario(label,function()
  if not button then return end
  C.setup(button:IsEnabled(),label..': the button is enabled')
  calls,primaryCalls={},0
  Nexus.JournalTab.OpenBuilds=function() primaryCalls=primaryCalls+1 end
  button:Click()
  C.guard(primaryCalls==1 and #calls==0,label..': the present primary helper is used, not the native Show')
  Nexus.JournalTab.OpenBuilds=nil
  button:Click()
  C.setup(#calls>=1,label..': with the helper missing the click reaches the native fallback')
  C.guard(#calls==1,label..': one native Show per click',#calls)
  local call=calls[1] or {}
  local shown=call.tab==native and 'module table' or printable(call.tab)
  print('OBSERVED',label,'tab type='..type(call.tab),'tab='..shown,'arguments='..printable(call.n))
  C.expect(call.tab~=native and NoTab(call.tab),
   label..': the fallback passes no tab (the native current tab), not the module table or an unestablished index',
   type(call.tab))
  Nexus.JournalTab.OpenBuilds=primary
 end)
end

native.Show=realShow
Nexus.JournalTab.OpenBuilds=primary
C.guard(#H.actions==0 and #H.sent==0,'no game or network action',#H.actions..'/'..#H.sent)
C.finish('(the fallback passes no tab, never the module; the native current tab applies)')
