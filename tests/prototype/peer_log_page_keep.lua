-- F-S5-1 (P3), regression-first: an active Peer Test keeps the copy page the
-- reader chose. While a Peer Test session runs and the "Advanced peer" tab is
-- shown, the log viewer repaints that report once per second
-- (ui/LogViewer.lua OnUpdate -> Repaint -> SetCopyText), and SetCopyText always
-- starts again at page 1. The later pages, which hold the newest events, can
-- therefore be read or copied for at most a second.
-- Healthy behaviour (EXPECT, fails at the baseline): through the active
-- periodic repaints, page 2 chosen with the real "Page >" button stays
-- selected (and the visible text is not page 1), as does the last page; when
-- the report shrinks from three pages to two, the selected third page is
-- clamped to the new last page instead of returning to page 1.
-- Unchanged (GUARD, holds at the baseline): the active report is still
-- repainted about once per second, and not more often; an explicit tab change
-- and an explicit open start at page 1; a tab without periodic repaints keeps
-- its page; a stopped session keeps its page and does no periodic provider
-- work; a hidden viewer does none either; the session keeps its 160-event
-- bound; no game action.
-- Real TOC boot, PeerDebug report, LogViewer window, its page and tab buttons
-- and its 1 Hz update; the provider is set through the public LogViewer.Init
-- seam, as diagnostics.lua does (the peer tab reads the real PeerDebug.Report;
-- another tab reads a static three-page synthetic text). Artificial events
-- only; the start-up's synthetic transport stays in memory, nothing is sent
-- to a network.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('peer_log_page_keep')
local LV,P=assert(Nexus.LogViewer),assert(Nexus.PeerDebug)
local PAGE=LV.PageInfo().pageBytes or 16000
local calls={}
local STATIC
do
 local lines={}
 for i=1,750 do lines[i]=string.format('synthetic static control line %04d for the page test',i) end
 STATIC=table.concat(lines,'\n')
end
LV.Init(function(tab)
 calls[tab]=(calls[tab] or 0)+1
 if tab=='peer' then return P.Report() end
 if tab=='sync' then return STATIC end
 return 'artificial control text'
end)
local function Pages(text) return math.max(1,math.ceil(#text/PAGE)) end
local function Info() return LV.PageInfo() end
local function Visible()
 local scroll=NexusLogScroll
 local box=scroll and scroll.scrollChild
 return box and tostring(box:GetText() or '') or ''
end
local function OnFirstPage() return Visible():find('NEXUS PEER TEST REPORT',1,true)==1 end
local function Peer() return calls.peer or 0 end

C.setup(P.Start(nil)==true,'fixture: a local-only Peer Test session starts')
local recorded=0
for i=1,159 do
 if P.Record('artificial_event',{reason=string.rep('r',90),outcome=string.rep('o',90),scope=string.rep('s',90),revision=i}) then
  recorded=recorded+1
 end
end
C.setup(recorded==159,'fixture: 159 artificial events are recorded',recorded)
C.setup(Pages(P.Report())==3,'fixture: the real sanitized report spans three copy pages',#P.Report())
C.setup(Pages(STATIC)==3,'fixture: the static control text spans three copy pages',#STATIC)
LV.Show('peer');H.Advance(.15)
C.setup(Info().pages==3 and Info().page==1 and OnFirstPage(),'fixture: the viewer shows page 1 of the three-page peer report',
 printable(Info().page)..'/'..printable(Info().pages))
local nextButton=NexusLogNextPage
C.setup(nextButton~=nil,'fixture: the real "Page >" button exists')
local function NextTo(page)
 for _=1,3 do if Info().page<page and nextButton then nextButton:Click() end end
 return Info().page==page
end

C.scenario('P1 active periodic repaints',function()
 C.setup(NextTo(2),'P1: fixture: the "Page >" button selects page 2')
 local before=Peer()
 H.Advance(1.1)
 C.guard(Peer()>before and P.IsEnabled(),'P1: the active session\'s report is repainted',Peer()-before)
 print('OBSERVED','P1 after one repaint page='..printable(Info().page),'first page shown='..printable(OnFirstPage()))
 C.expect(Info().page==2,'P1: page 2 stays selected through a periodic repaint',Info().page)
 C.expect(not OnFirstPage(),'P1: and the visible text is not page 1')
 before=Peer()
 H.Advance(3.0)
 local n=Peer()-before
 C.guard(n>=2 and n<=4,'P1: about one repaint per second, no more',n)
 C.expect(Info().page==2,'P1: page 2 stays selected through several periodic repaints',Info().page)
 C.setup(NextTo(3),'P1: fixture: the "Page >" button reaches the last page')
 H.Advance(1.1)
 C.expect(Info().page==3,'P1: the last page stays selected through a periodic repaint',Info().page)
end)

C.scenario('P2 a shrinking report',function()
 C.setup(NextTo(3) and Info().pages==3,'P2: fixture: the last of three pages is selected')
 -- Newer short events replace the oldest long ones in the bounded ring.
 local i=0
 while #P.Report()>2*PAGE-1500 and i<160 do
  i=i+1
  P.Record('artificial_short',{revision=i})
 end
 C.setup(Pages(P.Report())==2,'P2: fixture: the report now spans two pages',#P.Report())
 H.Advance(1.1)
 C.setup(Info().pages==2,'P2: fixture: the periodic repaint shows the two-page report',Info().pages)
 print('OBSERVED','P2 page after the shrink='..printable(Info().page))
 C.expect(Info().page==2,'P2: the selected page is clamped to the new last page, not reset to page 1',Info().page)
 local stats=P.Stats()
 C.guard(stats.retained==160 and stats.cap==160 and (tonumber(stats.dropped) or 0)>0,
  'P2: the session keeps its 160-event bound',printable(stats.retained)..'/'..printable(stats.dropped))
end)

C.scenario('G1 explicit tab changes, a static tab and a hidden viewer',function()
 C.setup(NextTo(2),'G1: fixture: page 2 of the peer report is selected')
 local sync=V.Frame(H,function(f) return f.tabKey=='sync' end)
 local peer=V.Frame(H,function(f) return f.tabKey=='peer' end)
 C.setup(sync~=nil and peer~=nil,'G1: fixture: the real tab buttons exist')
 if not (sync and peer) then return end
 sync:Click();H.Advance(.15)
 C.setup(Info().pages==3,'G1: fixture: the Sync tab shows the three-page static text',Info().pages)
 C.guard(Info().page==1,'G1: an explicit tab change starts at page 1',Info().page)
 C.setup(NextTo(2),'G1: fixture: page 2 of the static text is selected')
 H.Advance(2.2)
 C.guard(Info().page==2,'G1: a tab without periodic repaints keeps its page',Info().page)
 peer:Click();H.Advance(.15)
 C.guard(Info().page==1 and OnFirstPage(),'G1: changing back to the peer tab starts at page 1',Info().page)
 NexusLogViewer:Hide()
 local before=Peer()
 H.Advance(3.0)
 C.guard(Peer()==before,'G1: a hidden viewer does no periodic provider work',Peer()-before)
 LV.Show('peer');H.Advance(.15)
 C.guard(Info().page==1 and OnFirstPage(),'G1: opening the viewer starts at page 1',Info().page)
end)

C.scenario('G2 a stopped session',function()
 C.setup(P.Stop()==true,'G2: fixture: the session stops')
 H.Advance(1.1)
 C.setup(not P.IsEnabled() and NextTo(2),'G2: fixture: page 2 of the stopped report is selected')
 local before=Peer()
 H.Advance(2.2)
 C.guard(Info().page==2,'G2: a stopped session keeps page 2 through later frames',Info().page)
 C.guard(Peer()==before,'G2: and does no periodic provider work',Peer()-before)
end)

C.guard(#H.actions==0,'no game action',#H.actions)
print('OBSERVED','in-memory synthetic transport records='..#H.sent)
C.finish('(an active Peer Test keeps the chosen copy page; explicit changes start at page 1)')
