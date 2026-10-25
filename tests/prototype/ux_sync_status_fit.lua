-- UX M5 14d (MB1 / M5R-NB09 / M5R-NB12): the Build Library status region
-- fits its text, through the production LayoutMetrics.Community geometry and
-- the real renderer. Root qualification: the responsive status was 28 px at
-- the default examined scale (38 px at a larger one), not 14 px everywhere; at
-- UIParent 800 (frame 760, status 720) the count, the mode line and a Share
-- line need several rows, while the full-size window can fit two.
-- Healthy behaviour (EXPECT, fails on the preimage d15ba07c, whose status
-- region is a fixed two-row reserve): in both repository font models (default
-- 5.5 px / 12 px lines; 16 px face 7.0 px / 17 px lines), at 1366x768 and
-- 800x600, in Automatic, Manual and Off, idle, receiving, preparing and with a
-- long Share sentence, the allocated status region holds every row of its
-- text; it overlaps no control, the list or the detail; the detail keeps its
-- minimum body; the window holds every region; a refresh with the same rows
-- reuses the geometry (no layout request) and a change of rows re-lays it
-- once; LayoutMetrics.Community keys and sizes the status by its rows.
-- 14e: the same checks with the longest supported Share text (an 80-byte
-- title, the Share form's limit, in the controller's terminal sentence with
-- Retry Share, the locked-target sentence and the roles; and in its preparing
-- sentence, with the Off addition in Off), in both models and both viewports;
-- and at the largest supported font scale (the repository's 2.0 model), where
-- the 8-row bound held fewer rows than these texts need.
-- 14f: each boot is a new harness with its own region methods, and
-- LayoutMetrics reads the runtime font scale from the NexusFontNormal object
-- that layout_geometry_support creates only when it is absent. A font object
-- left from an earlier boot keeps that boot's methods, so production read the
-- earlier model's size (scale 1) while D measured the 2.0 model. Boot now
-- clears it, and SETUP checks that production reads this boot's font object
-- at the model's size and lays out at the model's scale, at the stated
-- viewport. GUARD: the measured rows are production's measure of the current
-- text at that scale, and the allocated height is production's height for
-- the rows the status shows.
-- M5 queue item 2 (14E-Q4 / M5R-NB09 / NB12): the window itself against the
-- viewport, through the same production layout and renderer. History: on
-- the preimage 2e34bce8 the 2.0-scale window grew past the viewport (11 of 12
-- modeled windows); c34fa248 (frozen22) bounded the status, with its text on
-- hover, and still left 18 windows of 760x766 in 800x600 (reported, not
-- closed). Continuation 39 replaces that bound. The status again holds every
-- row. The window is as tall as the viewport allows with the 24 px
-- FitToScreen margin, and its laid-out content scrolls inside it, through
-- the window's own scroll bar and mouse wheel.
-- EXPECT (fails on 2e34bce8 and on c34fa248 where their windows leave the
-- viewport or hold rows back), in every model, mode, state and viewport:
--  - the whole window (centred on UIParent; dragging not modelled) lies
--    inside the viewport with its margin;
--  - each control, the title and navigation, the browse and action controls,
--    the status and the list/detail can be brought fully on screen through
--    that bar and through that wheel;
--  - a layout taller than the window shows the bar over exactly the rest.
-- The inherited checks hold inside the window's laid-out content (the former
-- whole window). Nothing shrinks: font, controls, minimum body, cache. The
-- 0.75 model joins the default and 16 px faces, and the 2.0 model runs in
-- Automatic, Manual and Off. R: a taller UI re-lays once and leaves less to
-- scroll. S: while the window is open, the wheel and the bar reach the end and
-- stop there, and a UI or font change keeps the scrolled place inside the new
-- range. Native pixel fit, clipping, nested scrolling, tooltips and dragging
-- remain NOT TESTED.
-- Unchanged (GUARD): the pinned count sentence (' bundled + ') and the
-- policies' Off/Manual words in the status; no game action.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- State text injection, disclosed: receiving and preparing are produced by
-- replacing Nexus.Sync.IsReceiving/ReceiveTimeLeft/LastSyncNewCount/Stats for
-- the read only; the Share sentence by wrapping the real controller's
-- ShareStatusText/ShareStatus at its factory with text in the controller's
-- own formats. Geometry, layout, renderer and measurement are production;
-- text measurement uses layout_geometry_support models (native fit NOT TESTED).
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_status_fit')

local TITLE='Artificial '..string.rep('W',40)..' status-fit build'
local SHARE_TEXT='Preparing "'..TITLE..'" to share — not sent yet. The local catalog is finishing earlier work first. '
 ..'The same request continues by itself. Do not share it again.'
local SHARE={state='preparing',text=SHARE_TEXT,
 status={id='artificial',title=TITLE,ordinaryCopies=79,permanentCopies=6,localPending=true}}
-- The longest supported title, in the controller's own sentences
-- (CommunityController BaseShareStatusText and ShareStatusText).
local TITLE80='Frost Mage Arcane Barrage Burst Rotation for Heroic Raids and Mythic Dungeons v2'
local LONG_SHARE={state='stopped',
 text='Saved "'..TITLE80..'" locally — not sent: throttle-exhausted (server throttle). Open the build to use Retry Share.'
  ..' 3 answers for requesters that did not state locked-target support (for example an older Nexus version) carried the ordinary targets only.',
 status={id='artificial',title=TITLE80,ordinaryCopies=79,permanentCopies=6,localSaved=true,terminal=true,
  outcome='throttle-exhausted',reason='server throttle',lockedRolesOrdinaryOnly=3}}
local function LongPreparing()
 local off=Nexus.SyncModePolicy.Mode()=='off'
 return {state='preparing',
  text='Preparing "'..TITLE80..'" to share — not sent yet. The local save is submitted; the catalog has not finished it. '
   ..'The same request continues by itself. Do not share it again.'
   ..(off and ' Your saved Sync mode is Off: it will be saved locally and not sent.' or ''),
  status={id='artificial',title=TITLE80,ordinaryCopies=79,permanentCopies=6,localPending=true,localStage='saving'}}
end
local share=nil
local H

local function Boot(db)
 NexusQuickStart,NexusCommunityBuildsFrame,NexusLeaderboardFrame,NexusSyncModeDialog=nil,nil,nil,nil
 NexusHelpWindow,NexusOverwriteWarning,NexusPanel=nil,nil,nil
 -- A font object from an earlier boot answers GetFont through that boot's
 -- harness methods; G.UseFont creates this boot's one only when it is absent.
 NexusFontNormal=nil
 F.fileHooks={['core\\CommunityController.lua']=function()
  local factory=Nexus.CommunityInternals and Nexus.CommunityInternals.Controller
  local new=factory and factory.New
  if type(new)~='function' then return end
  factory.New=function(...)
   local instance=new(...)
   local text,status=instance.ShareStatusText,instance.ShareStatus
   instance.ShareStatusText=function(...)
    if share then return share.state,share.text end
    return text(...)
   end
   instance.ShareStatus=function(...)
    if share then return share.status end
    return status(...)
   end
   return instance
  end
 end}
 H=F.Boot(db)
 F.fileHooks=nil
 return H
end

local STATES={
 {name='idle'},
 {name='receiving',apply=function(S)
  local saved={S.IsReceiving,S.ReceiveTimeLeft,S.LastSyncNewCount}
  S.IsReceiving=function() return true end
  S.ReceiveTimeLeft=function() return 42 end
  S.LastSyncNewCount=function() return 12 end
  return function() S.IsReceiving,S.ReceiveTimeLeft,S.LastSyncNewCount=saved[1],saved[2],saved[3] end
 end},
 {name='preparing',apply=function(S)
  local real=S.Stats
  S.Stats=function(...)
   local out={};for k,v in pairs(real(...) or {}) do out[k]=v end
   out.preparingRequest=true
   return out
  end
  return function() S.Stats=real end
 end},
 {name='share',apply=function() share=SHARE;return function() share=nil end end},
 {name='share-long',apply=function() share=LONG_SHARE;return function() share=nil end end},
 {name='preparing-long',apply=function() share=LongPreparing();return function() share=nil end end},
}
local VIEWPORTS={{w=1366,h=768},{w=800,h=600}}
-- M5 queue item 2: the smallest supported font scale (0.75) joins the default
-- face and the 16 px face; the largest (2.0) runs in every mode below.
local MODELS={G.MODELS.default,G.MODELS.px16,G.MODELS.small}
C.setup(#TITLE80==80,'fixture: the long title is exactly the Share form\'s 80-byte limit',#TITLE80)

local function Frame() return NexusCommunityBuildsFrame end
local function Render()
 Nexus.CommunityBuilds.Refresh()
 for _=1,6 do H.Advance(.05,.05) end
 Nexus.CommunityBuilds.Refresh()
end
local function Controls(f)
 local out={}
 for _,name in ipairs({'_syncBtn','_modeBtn','_postBtn','_resultText','_prevPageBtn','_pageText','_nextPageBtn','_listClip'}) do
  if f[name] then out[#out+1]={name,f[name]} end
 end
 if f._detailPanel and f._detailPanel:IsShown() then out[#out+1]={'_detailPanel',f._detailPanel} end
 return out
end
-- The window's own scroll route as production builds it (continuation 39):
-- the content every laid-out widget is placed in, the ScrollFrame that clips
-- it and the bar at the window's right edge. A window without one (2e34bce8,
-- c34fa248) is measured where it stands; its laid-out content is the window.
local function Route(f)
 local scroll,content=f._contentScroll,f._content
 if scroll and content and scroll.scrollChild==content then return scroll,content,f._contentBar end
 return nil,f,nil
end
-- Everything the window offers: the status, the title and navigation, the
-- browse and action controls with their labels, the list and the detail.
local function Reachables(f)
 local out={}
 for _,name in ipairs({'_syncStatusText','_titleText','_navBar','_browseLabel','_searchBox','_scopeBtn','_myBuildsBtn',
  '_classDropBtn','_qualifiedBox','_sortToggle','_actionLabel'}) do
  if f[name] then out[#out+1]={name,f[name]} end
 end
 for _,c in ipairs(Controls(f)) do out[#out+1]=c end
 return out
end
-- Where the window's content can be seen: its clip (the ScrollFrame, or the
-- window itself) within the UI.
local function Clip(f,ui)
 local scroll=Route(f)
 local c=G.Rect(scroll or f,UIParent)
 return {math.max(c[1],ui[1]),math.max(c[2],ui[2]),math.min(c[3],ui[3]),math.min(c[4],ui[4])}
end
local function OnScreen(f,region,ui) return G.Inside(G.Rect(region,UIParent),Clip(f,ui)) end
-- Drags the window's bar the way the client reports it (SetValue, then
-- OnValueChanged) to where the region's top shows, and answers whether the
-- region is then fully on screen.
local function ByBar(f,region,ui)
 local scroll,content,bar=Route(f)
 if not (scroll and bar and bar:IsShown()) then return OnScreen(f,region,ui) end
 local low,high=bar:GetMinMaxValues()
 local target=math.max(low,math.min(high,G.Rect(region,content)[2]))
 bar:SetValue(target)
 local changed=bar:GetScript('OnValueChanged')
 if changed then changed(bar,target) end
 return OnScreen(f,region,ui)
end
-- Turns the mouse wheel over the window one notch down at a time from the
-- top, until the region is fully on screen or the content stops moving.
local function ByWheel(f,region,ui)
 local scroll=Route(f)
 local wheel=scroll and scroll:GetScript('OnMouseWheel')
 if not wheel then return OnScreen(f,region,ui) end
 wheel(scroll,1000)
 for _=1,200 do
  if OnScreen(f,region,ui) then return true end
  local before=scroll:GetVerticalScroll()
  wheel(scroll,-1)
  if scroll:GetVerticalScroll()==before then break end
 end
 return OnScreen(f,region,ui)
end
local function ToTop(f)
 local scroll=Route(f)
 local wheel=scroll and scroll:GetScript('OnMouseWheel')
 if wheel then wheel(scroll,1000) end
end

local function Check(tag,modeWords,viewport)
 local f=Frame()
 local layout=f and f._responsiveLayout
 local box=type(layout)=='table' and layout.boxes and layout.boxes.status
 C.setup(box~=nil,tag..': fixture: the production layout allocated a status region')
 if not box then return end
 local m=G.model
 -- Font and viewport identity (SETUP, not a result): production's font object
 -- is this boot's, it reports the model's size, and the layout used the scale
 -- LayoutMetrics derives from it (size / 12, within 0.75..2).
 local font=_G.NexusFontNormal
 local fontSize
 if font and type(font.GetFont)=='function' then
  local ok,_,size=pcall(font.GetFont,font)
  fontSize=ok and size or nil
 end
 local current=font~=nil and font.GetFont==G.RegionMethods().GetFont
 local scale=math.max(0.75,math.min(2,m.size/12))
 C.setup(current and fontSize==m.size,tag..': fixture: production reads this boot\'s font object at the model size',
  (current and 'current' or 'stale')..' '..printable(fontSize))
 C.setup(math.abs((tonumber(layout.scale) or 0)-scale)<0.001,tag..': fixture: the production layout uses the model\'s font scale',
  printable(layout.scale)..' ~= '..scale)
 C.setup(UIParent:GetWidth()==viewport.w and UIParent:GetHeight()==viewport.h
  and layout.width==math.max(760,math.min(1040,viewport.w-40)),
  tag..': fixture: the stated viewport, and the window width available there',printable(layout.width))
 local status=f._syncStatusText
 local text=status:GetText() or ''
 local plain=V.Plain(text)
 C.guard(plain:find(' bundled + ',1,true)~=nil or plain:find('Preparing sync data',1,true)~=nil,tag..': the pinned count sentence (or the preparing line) is kept',plain)
 if modeWords then C.guard(plain:find(modeWords,1,true)~=nil,tag..': the mode words are stated',plain) end
 local LM=Nexus.LayoutMetrics
 local rows=G.Rows(text,box.w,m.char)
 local measured=f._nexusStatusRows
 local remeasured=LM.CommunityStatusRows(text,box.w,layout.scale)
 -- The rows the status shows: every measured row. (c34fa248 bounded them for
 -- the viewport and said so in statusVisibleRows; a layout without that field
 -- shows every row.)
 local visible=tonumber(layout.statusVisibleRows) or measured
 local allocated=LM.CommunityStatusHeight(visible,layout.scale)
 -- The viewport, from production's own geometry: the window is centred on
 -- UIParent (dragging is not modelled), and FitToScreen's 24 px margin.
 local margin=tonumber(layout.viewportMargin) or 24
 local ui={0,0,viewport.w,viewport.h}
 local wr=G.Rect(f,UIParent)
 local minimumBody=math.max(150,math.ceil(133*(layout.scale or 1)))
 local scroll,surface,bar=Route(f)
 local extra=math.max(0,surface:GetHeight()-f:GetHeight())
 print('OBSERVED',tag,'rows='..rows,'needs='..rows*m.line,'box='..box.w..'x'..box.h,'measured rows='..printable(measured),
  'shown rows='..printable(visible),'scale='..printable(layout.scale),'line='..printable(layout.statusLine),
  'font='..(current and 'current' or 'stale')..'/'..printable(fontSize),
  'window='..printable(f:GetWidth())..'x'..printable(f:GetHeight()),
  'content='..printable(surface:GetWidth())..'x'..printable(surface:GetHeight()),'viewport='..viewport.w..'x'..viewport.h,
  'window rect='..G.Text(wr),'scroll route='..(scroll and 'yes' or 'no'),'scroll range='..printable(layout.scrollRange),
  'bar='..(bar and (bar:IsShown() and 'shown' or 'hidden') or 'none'))
 C.guard(measured==remeasured,tag..': the measured rows are production\'s measure of the current text at the observed scale',
  printable(measured)..' / '..printable(remeasured))
 C.guard(box.h==allocated,tag..': the allocated height is production\'s height for the rows the status shows at that scale',
  box.h..' / '..printable(allocated))
 local holds=rows*m.line<=box.h
 C.expect(holds,tag..': the allocated status region holds every row of its text',rows*m.line..' > '..box.h)
 if holds then
  C.guard(status._nexusFullText==nil and not (f._statusHit and f._statusHit:IsShown()),
   tag..': a status that holds every row has no extra hover text')
 end
 C.expect(status:GetWidth()==box.w and status:GetHeight()==box.h,tag..': the FontString has exactly the allocated size',
  status:GetWidth()..'x'..status:GetHeight())
 -- Inherited: inside the window's laid-out content (the window itself when it
 -- has no scroll route), and apart from the status.
 local window={0,0,surface:GetWidth(),surface:GetHeight()}
 local sr=G.Rect(status,surface)
 C.expect(G.Inside(sr,window),tag..': the status region is inside the window\'s laid-out content',G.Text(sr))
 for _,c in ipairs(Controls(f)) do
  local r=G.Rect(c[2],surface)
  C.expect(G.Apart(sr,r),tag..': the status region does not overlap '..c[1],G.Text(sr)..' / '..G.Text(r))
  C.expect(G.Inside(r,window),tag..': '..c[1]..' is inside the window\'s laid-out content',G.Text(r))
 end
 local detail=layout.boxes.detail
 C.expect(detail and detail.h>=minimumBody,tag..': the detail keeps its minimum body',detail and detail.h)
 -- The whole window lies inside the viewport, with its margin, everywhere.
 C.expect(G.Inside(wr,ui) and f:GetHeight()<=viewport.h-margin and f:GetWidth()<=viewport.w-margin,
  tag..': the whole window lies inside the viewport, with its margin',G.Text(wr)..' in '..viewport.w..'x'..viewport.h)
 -- A layout taller than the window scrolls over exactly the rest.
 if extra>0 then
  local low,high
  if bar then low,high=bar:GetMinMaxValues() end
  C.expect(scroll~=nil and bar~=nil and bar:IsShown() and low==0 and high==extra
   and G.Inside(G.Rect(bar,UIParent),wr),
   tag..': the layout taller than the window scrolls: its bar is shown inside the window over exactly the rest',
   printable(extra)..' / '..printable(high))
 else
  C.guard(not (bar and bar:IsShown()) and (scroll==nil or scroll:GetVerticalScroll()==0),
   tag..': a layout that fits shows no scroll bar and is not scrolled')
 end
 -- Every control, the status and the list/detail can be brought fully on
 -- screen, through the bar and through the wheel.
 for _,c in ipairs(Reachables(f)) do
  local byBar=ByBar(f,c[2],ui)
  local byWheel=ByWheel(f,c[2],ui)
  C.expect(byBar and byWheel,tag..': '..c[1]..' can be brought fully on screen (scroll bar and mouse wheel)',
   'bar='..tostring(byBar)..' wheel='..tostring(byWheel)..' at '..G.Text(G.Rect(c[2],UIParent)))
 end
 ToTop(f)
end

local function Run(tag,db,modeWords,models)
 Boot(db)
 C.setup(Nexus.StartupStatus().coreReady==true,tag..': fixture: start-up reached core-ready')
 local S=Nexus.Sync
 for _,model in ipairs(models or MODELS) do
  G.UseFont(model)
  for _,v in ipairs(VIEWPORTS) do
   UIParent:SetSize(v.w,v.h)
   Nexus.CommunityBuilds.Show()
   for _,state in ipairs(STATES) do
    local restore=state.apply and state.apply(S) or nil
    local ok,err=pcall(Render)
    C.setup(ok,tag..': fixture: the view rendered',err)
    Check(tag..' '..model.name..' '..v.w..'x'..v.h..' '..state.name,modeWords,v)
    if restore then restore() end
   end
  end
 end
 G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
end

C.scenario('A Automatic (format-2 profile without a choice)',function()
 Run('A',F.Database({version=2}),'Sync is Automatic')
end)
C.scenario('M Manual (accepted format 5)',function()
 Run('M',F.Database(),'saved Sync mode is Manual')
end)
C.scenario('O Off (accepted format 5)',function()
 Run('O',F.Database({mutate=function(db) db.settings.syncMode='off' end}),'saved Sync mode is Off')
end)
C.scenario('D the largest supported font scale (2.0), Automatic',function()
 Run('D',F.Database({version=2}),'Sync is Automatic',{G.MODELS.double})
end)
C.scenario('DM the largest supported font scale (2.0), Manual',function()
 Run('DM',F.Database(),'saved Sync mode is Manual',{G.MODELS.double})
end)
C.scenario('DO the largest supported font scale (2.0), Off',function()
 Run('DO',F.Database({mutate=function(db) db.settings.syncMode='off' end}),'saved Sync mode is Off',{G.MODELS.double})
end)

C.scenario('R re-layout only when the rows change',function()
 Boot(F.Database({version=2}))
 G.UseFont(G.MODELS.default);UIParent:SetSize(800,600)
 Nexus.CommunityBuilds.Show();Render()
 local f=Frame()
 local LM=Nexus.LayoutMetrics
 -- Count the renderer's actual Community layout requests (not the HUD's).
 local realCommunity,requests=LM.Community,0
 LM.Community=function(...) requests=requests+1;return realCommunity(...) end
 local rows0,key0=f._nexusStatusRows,f._nexusLayoutKey
 local r0=requests
 Render()
 C.expect(rows0~=nil and f._nexusStatusRows==rows0 and f._nexusLayoutKey==key0 and requests==r0,
  'R: a refresh with the same rows reuses the geometry (no layout request)',printable(requests-r0))
 share=SHARE
 local r1=requests
 Render()
 local rows2=f._nexusStatusRows
 C.expect(rows2~=nil and rows0~=nil and rows2>rows0 and f._nexusLayoutKey~=key0 and requests>r1,
  'R: a longer status (a Share line) re-lays the window for its rows',printable(rows0)..' -> '..printable(rows2))
 local r3=requests
 Render()
 C.expect(requests==r3,'R: and the next refresh with those rows reuses it',printable(requests-r3))
 LM.Community=realCommunity
 share=nil
 Render()
 C.expect(f._nexusStatusRows==rows0,'R: when the Share line goes, the rows return',printable(f._nexusStatusRows))
 -- The production layout function itself keys and sizes the status by rows.
 local spec={width=760,height=540,fontScale=1,uiScale=1,revision=1,labels={sync='Listening...',mode='Sync mode...',share='Share Build'}}
 local function With(rows) local s={};for k,v in pairs(spec) do s[k]=v end;s.statusRows=rows;return s end
 local three,four=LM.Community(With(3)),LM.Community(With(4))
 C.expect(three.key~=four.key and four.boxes.status.h>three.boxes.status.h and three.boxes.status.h>=3*17,
  'R: LayoutMetrics.Community keys and sizes the status by its rows',three.boxes.status.h..' / '..four.boxes.status.h)
 local hits=LM.Stats().hits
 local again=LM.Community(With(3))
 C.expect(again==three and LM.Stats().hits==hits+1,'R: an equal spec is served from the cache')
 C.expect(three.boxes.mode~=nil and not LM.Overlap(three.boxes.mode,three.boxes.sync)
  and not LM.Overlap(three.boxes.mode,three.boxes.share),'R: the Sync mode control has its own place beside Sync Now')
 -- M5 queue item 2: the UI size is part of the geometry. At font scale 2.0 a
 -- taller UI with the same available window size (1366x768 -> 1366x900: the
 -- requested window is still 1040x640) re-lays once; the window grows and
 -- less is left to scroll. The same UI size again reuses it.
 G.UseFont(G.MODELS.double);UIParent:SetSize(1366,768)
 share=LONG_SHARE;Render()
 local shortWindow=f:GetHeight()
 local shortRange=tonumber(f._responsiveLayout and f._responsiveLayout.scrollRange)
 LM.Community=function(...) requests=requests+1;return realCommunity(...) end
 local r4=requests
 UIParent:SetSize(1366,900);Render()
 local tallRange=tonumber(f._responsiveLayout and f._responsiveLayout.scrollRange)
 C.expect(requests>r4 and shortRange~=nil and tallRange~=nil and shortRange>0 and tallRange<shortRange
  and f:GetHeight()>shortWindow and f:GetHeight()<=900-24,
  'R: at font scale 2.0 a taller UI re-lays the window once: it grows and less is left to scroll',
  printable(shortWindow)..' -> '..printable(f:GetHeight())..' px, range '..printable(shortRange)..' -> '..printable(tallRange)
  ..', '..(requests-r4)..' layout request(s)')
 local r5=requests
 Render()
 C.expect(requests==r5,'R: the same UI size again reuses the geometry',printable(requests-r5))
 LM.Community=realCommunity
 share=nil
 G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
end)

-- The scroll route while the window stays open (continuation 39). At 2.0 in
-- 800x600 with the longest Share line the layout is taller than the window.
-- The mouse wheel and the bar reach its end and stop there, and the bottom of
-- the list is then on screen. A larger UI keeps the scrolled place inside the
-- new range. Back at the default face everything fits again: no scroll and no
-- bar. The bar dragged past its end stops at the end, and the wheel returns
-- to the top.
C.scenario('S the window\'s scroll route while it is open',function()
 Boot(F.Database({version=2}))
 G.UseFont(G.MODELS.double);UIParent:SetSize(800,600)
 Nexus.CommunityBuilds.Show()
 share=LONG_SHARE;Render()
 local f=Frame()
 local ui={0,0,800,600}
 local scroll,content,bar=Route(f)
 local range=tonumber(f._responsiveLayout and f._responsiveLayout.scrollRange) or 0
 print('OBSERVED','S','window='..printable(f:GetWidth())..'x'..printable(f:GetHeight()),
  'content='..printable(content:GetWidth())..'x'..printable(content:GetHeight()),'range='..printable(range))
 C.expect(scroll~=nil and bar~=nil and bar:IsShown() and range>0 and content:GetHeight()-f:GetHeight()==range
  and f:GetHeight()<=600-24,
  'S: at 2.0 in 800x600 the window fits the UI and has a scroll route over the rest of its layout',
  printable(f:GetHeight())..' / '..printable(range))
 local wheel=scroll and scroll:GetScript('OnMouseWheel')
 local changed=bar and bar:GetScript('OnValueChanged')
 if not (scroll and bar and wheel and changed) then
  share=nil;G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
  return
 end
 local notches=0
 while scroll:GetVerticalScroll()<range and notches<200 do wheel(scroll,-1);notches=notches+1 end
 C.expect(scroll:GetVerticalScroll()==range and bar:GetValue()==range,
  'S: the mouse wheel reaches the end of the layout and the bar follows',
  printable(scroll:GetVerticalScroll())..' / '..printable(bar:GetValue())..' after '..notches..' notch(es)')
 wheel(scroll,-1)
 C.expect(scroll:GetVerticalScroll()==range,'S: and goes no further',printable(scroll:GetVerticalScroll()))
 C.expect(OnScreen(f,f._listClip,ui),'S: at the end the bottom of the list is on screen',G.Text(G.Rect(f._listClip,UIParent)))
 UIParent:SetSize(1366,768);Render()
 local wideRange=tonumber(f._responsiveLayout and f._responsiveLayout.scrollRange) or -1
 C.expect(wideRange>=0 and wideRange<range and scroll:GetVerticalScroll()<=wideRange
  and bar:GetValue()==scroll:GetVerticalScroll() and bar:IsShown()==(wideRange>0),
  'S: a larger UI while scrolled keeps the place inside the new, smaller range',
  printable(scroll:GetVerticalScroll())..' of '..printable(wideRange))
 G.UseFont(G.MODELS.default);Render()
 C.expect(scroll:GetVerticalScroll()==0 and not bar:IsShown() and f:GetHeight()==content:GetHeight(),
  'S: back at the default face everything fits again: no scroll and no bar',
  printable(scroll:GetVerticalScroll())..' / '..printable(f:GetHeight())..' of '..printable(content:GetHeight()))
 G.UseFont(G.MODELS.double);UIParent:SetSize(800,600);Render()
 local again=tonumber(f._responsiveLayout and f._responsiveLayout.scrollRange) or 0
 bar:SetValue(10000);changed(bar,10000)
 C.expect(again>0 and scroll:GetVerticalScroll()==again and bar:GetValue()==again,
  'S: the bar dragged past its end stops at the end',printable(scroll:GetVerticalScroll())..' of '..printable(again))
 wheel(scroll,1000)
 C.expect(scroll:GetVerticalScroll()==0 and bar:GetValue()==0,'S: and the wheel returns to the top',printable(scroll:GetVerticalScroll()))
 share=nil
 G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the status region holds every row; the window lies inside the viewport and its laid-out content scrolls so every control, the status and the list/detail can be brought on screen; re-laid only when rows, font or UI size change; native fit NOT TESTED)')
