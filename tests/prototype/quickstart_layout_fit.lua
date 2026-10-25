-- Quick Start layout fit. The harness has no font renderer, so text fit is a
-- model: word-wrapped visible characters at a per-character width and a line
-- height, checked against the real anchors and sizes of the real window.
--   default      the 10 px small font (0.55 em, 12 px lines), as in the Auto label model
--   conservative a 16 px replacement font wider and taller than the ElvUI font
--                measured natively for 20dabcd (6.27 px per character, 16.1 px
--                lines; the body was cut after 4 lines): 7.0 px and 17 px
-- Native pixel fit is NOT established here; the native run checks it.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local BODY="Already have a Saved Build? Assign the Wishlist you want it to follow. "..
 "With Auto ON, Nexus may replace the active Saved Build with a better finished run. "..
 "Keep Auto OFF to leave that slot unchanged.\n"..
 "Starting fresh? Import a Wishlist code or copy a Community build into an editable draft."
local HINT="Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls."
local SUBTITLE="Plan your Echoes, then choose what to automate."
local BUTTONS={'Set up current build','Import / Create Wishlist','Browse Community builds',
 'Open Leaderboard','Help / Getting Started','Orbs / Lost Memories','Close'}
local MODELS={{name='default',char=5.5,line=12},{name='conservative',char=7.0,line=17}}

-- Label cases at the declared models of layout_geometry_support (default,
-- 16 px face, 0.75 and 2.0 scale; offline models, native NOT_RUN), through
-- the real anchors of the real ui/OverwriteWarning and ui/QuickStart widgets.
-- A label EXPECT (exact caption, whole label width, one complete line of
-- height) is collected and reported at the end. Setup and guards still
-- assert; inside a label case, a failed one is reported as a RAISED case.
-- Every case restores the harness measurement, the font object and
-- LayoutMetrics, and declines its own Auto request, also when it raises.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local CONTINUE='Continue \226\128\148 Auto stays OFF' -- U+2014 em dash: the exact onboarding caption
local CAPS=24 -- a button's end caps (docs/UI_TEXT_LAYOUT.md: label plus end caps)
local methods,MEASURE=G.RegionMethods(),{'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
local saved,font0,metrics0={},rawget(_G,'NexusFontNormal'),Nexus.LayoutMetrics
for _,k in ipairs(MEASURE)do saved[k]=rawget(methods,k) end
local AUTO_OWNER,autoAccepted,missed,raised,warning={},0,{},{}
local function expect(v,m)checks=checks+1;if v then return true end;missed[#missed+1]=m;print('FAIL EXPECT '..m);return false end
-- measured=false hides the real text measurement (the fallback model);
-- metrics=false hides LayoutMetrics.
local function under(label,m,measured,metrics,fn)
 local ok,err=xpcall(function()
  G.UseFont(m)
  if not measured then methods.GetTextWidth=nil end
  if not metrics then Nexus.LayoutMetrics=nil end
  fn()
 end,debug.traceback)
 for _,k in ipairs(MEASURE)do methods[k]=saved[k] end
 _G.NexusFontNormal,Nexus.LayoutMetrics,G.model=font0,metrics0,nil
 pcall(function() Nexus.OverwriteWarning.CancelAuto(AUTO_OWNER) end)
 if not ok then raised[#raised+1]=label..': '..tostring(err);print('FAIL RAISED '..label..': '..tostring(err)) end
end
local function fits(button,caption,m,label,dep)
 expect(G.Length(caption)*m.char+CAPS<=button:GetWidth(),label..': the whole "'..caption..'" fits its button width ['..button:GetWidth()..']'..dep)
 expect(m.line<=button:GetHeight(),label..': one complete line fits its button height ['..button:GetHeight()..']'..dep)
end
local function answers(kind,m,name,yesCaption,noCaption)
 local w,label=NexusOverwriteWarning,kind..' warning, '..m.name..name
 check(w and w==warning and w:IsShown() and w.close and w.suppress and w.countdown,label..': the same warning is shown with its controls')
 local named=expect(w.yes:GetText()==yesCaption and w.no:GetText()==noCaption,label..': answers read exactly "'..yesCaption..
  '" / "'..noCaption..'" ['..tostring(w.yes:GetText())..' / '..tostring(w.no:GetText())..']')
 local dep=named and '' or ' [depends on the failed caption EXPECT]'
 fits(w.yes,yesCaption,m,label,dep);fits(w.no,noCaption,m,label,dep)
 local ww,wh=w:GetWidth(),w:GetHeight()
 local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
 check(G.Inside(yes,{5,5,ww-5,wh-5}) and G.Inside(no,{5,5,ww-5,wh-5}) and ww<=1024,label..': answers inside a window on the smallest UI '..G.Text(yes)..G.Text(no))
 check(G.Apart(yes,no),label..': answers do not overlap')
 for _,o in ipairs({w.close,w.suppress,w.countdown})do
  local r=G.Rect(o,w);check(G.Apart(yes,r) and G.Apart(no,r),label..': answers apart from the control at '..G.Text(r))
 end
 return w
end
-- The first-launch warning opens once per session, so its full answers are
-- measured at that presentation: 2.0 scale without text measurement (the
-- supported fallback, the widest Continue). The original Show below then
-- finds that warning still pending and opens nothing more.
under('onboarding warning',G.MODELS.double,false,true,function()
 Nexus.QuickStart.Show()
 warning=NexusOverwriteWarning
 answers('onboarding',G.MODELS.double,', text unmeasured, LayoutMetrics',CONTINUE,'Close')
end)

Nexus.QuickStart.Show()
H.Advance(5.01);NexusOverwriteWarning.yes:Click()
Nexus.QuickStart.Show()
local qs=assert(NexusQuickStart,'Quick Start window exists')
local W,Ht=qs:GetWidth(),qs:GetHeight()
local texts,buttons={},{}
for _,c in ipairs(qs.children)do
 if c.kind=='FontString' then
  local plain=c:GetText():gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  texts[plain]=c
 end
 if c.kind=='Button' then buttons[c:GetText()]=c end
end
local body,hint,subtitle=texts[BODY],texts[HINT],texts[SUBTITLE]
-- #89 wording is unchanged: exact body, hint and subtitle text.
check(body and body==qs.body,'Quick Start body text is exactly the #89 text')
check(hint,'Quick Start hint text unchanged')
check(subtitle,'Quick Start subtitle text unchanged')
local count=0;for _ in pairs(buttons)do count=count+1 end
check(count==#BUTTONS,'Quick Start keeps its seven buttons')
-- The Welcome dismissal must read exactly "Close" (a label EXPECT). Only after
-- that failed EXPECT does the real legacy "Later" stand in as baseline control,
-- so the unchanged guards still run; each Close check is then marked dependent.
local closeNamed=expect(buttons.Close and buttons.Close:GetScript('OnClick'),'the Welcome dismissal reads exactly "Close" with its click handler')
if not buttons.Close then buttons.Close=buttons.Later end
local closeDep=closeNamed and '' or ' [depends on the failed Close caption EXPECT]'
for _,label in ipairs(BUTTONS)do
 check(buttons[label] and buttons[label]:GetScript('OnClick'),'button "'..label..'" exists with its click handler'..(label=='Close' and closeDep or ''))
end

-- Rectangles in window coordinates: x right, y DOWN from the window top.
local function anchorOf(region,point)
 local l,t,r,b
 if region==qs then l,t,r,b=0,0,W,Ht else l,t,r,b=unpack(region.rect) end
 local x=point:find('LEFT') and l or point:find('RIGHT') and r or (l+r)/2
 local y=point:find('TOP') and t or point:find('BOTTOM') and b or (t+b)/2
 return x,y
end
local function place(region,w,h)
 check(region:GetNumPoints()==1,'one anchor per region')
 local pt={region:GetPoint(1)}
 local point,rel,relPoint,x,y
 if #pt==3 then point,rel,relPoint,x,y=pt[1],qs,pt[1],pt[2],pt[3]
 else point,rel,relPoint,x,y=pt[1],pt[2],pt[3],pt[4],pt[5] end
 local ax,ay=anchorOf(rel,relPoint)
 ax,ay=ax+x,ay-y
 local left=point:find('LEFT') and ax or point:find('RIGHT') and ax-w or ax-w/2
 local top=point:find('TOP') and ay or point:find('BOTTOM') and ay-h or ay-h/2
 region.rect={left,top,left+w,top+h}
 return region.rect
end
local function inside(label,rect)
 -- Dialog border insets: left 11, right 12, top 12, bottom 11.
 check(rect[1]>=11 and rect[3]<=W-12 and rect[2]>=12 and rect[4]<=Ht-11,label..' lies inside the window border')
end
local function apart(a,b,label)
 check(a[3]<=b[1] or b[3]<=a[1] or a[4]<=b[2] or b[4]<=a[2],label..' do not overlap')
end
local order={'Set up current build','Import / Create Wishlist','Browse Community builds','Open Leaderboard',
 'Help / Getting Started','Orbs / Lost Memories','Close'}
for _,label in ipairs(order)do
 local b=buttons[label];inside('button "'..label..'"',place(b,b:GetWidth(),b:GetHeight()))
end
local bodyRect=place(body,body:GetWidth(),body:GetHeight());inside('body',bodyRect)
local hintRect=place(hint,hint:GetWidth(),hint:GetHeight());inside('hint',hintRect)
for i=1,#order do
 local a=buttons[order[i]].rect
 apart(a,bodyRect,'button "'..order[i]..'" and body');apart(a,hintRect,'button "'..order[i]..'" and hint')
 for j=i+1,#order do apart(a,buttons[order[j]].rect,'buttons "'..order[i]..'" and "'..order[j]..'"') end
end
apart(bodyRect,hintRect,'body and hint')
local firstRow=buttons['Set up current build'].rect[2]
check(bodyRect[4]<=firstRow,'body ends above the first button row')

local function wrapped(text,width,char)
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local lines=0
 for para in (text..'\n'):gmatch('(.-)\n')do
  lines=lines+1;local used=0
  for word in para:gmatch('%S+')do
   local w=#word*char;local gap=used>0 and char or 0
   if used>0 and used+gap+w>width then lines=lines+1;used=w else used=used+gap+w end
  end
 end
 return lines
end
local subtitleTop=37
local sp={subtitle:GetPoint(1)}
check(sp[1]=='TOP' and sp[#sp]==-subtitleTop,'subtitle anchor unchanged')
for _,m in ipairs(MODELS)do
 local bodyLines,hintLines=wrapped(BODY,body:GetWidth(),m.char),wrapped(HINT,hint:GetWidth(),m.char)
 print('QUICKSTART_FIT',m.name,'window',W..'x'..Ht,'body',body:GetWidth()..'x'..body:GetHeight(),'lines',bodyLines,'needs',bodyLines*m.line,
  'hint',hint:GetWidth()..'x'..hint:GetHeight(),'lines',hintLines,'needs',hintLines*m.line)
 check(bodyLines*m.line<=body:GetHeight(),m.name..' font: every body line fits (no cut paragraph)')
 check(hintLines*m.line<=hint:GetHeight(),m.name..' font: every hint line fits')
 check(#SUBTITLE*m.char<=W-24,m.name..' font: subtitle fits on one line')
 check(subtitleTop+m.line<=bodyRect[2],m.name..' font: subtitle line ends above the body')
end
-- The window stays on a 768 px high UI at its offset (centre +55).
check(Ht/2+55<=384 and W<=1024,'window fits the smallest UI height at its offset')

-- Label cases at every declared model, with the real text measurement
-- available and absent (the fallback model, 2.0 scale included) and with
-- LayoutMetrics available and absent. The same warning is rebound for an
-- Auto request (Yes / No at the original 110 px answers in the original
-- 520 px window, however wide Continue made it) and declined, never
-- accepted. The Welcome's Close is fitted again on a deliberate Show: whole
-- label, one complete line, inside the window border and apart from the
-- hint, the Sync line and the other six controls. The old body paragraphs
-- are not asked to fit these models; the body checks above stand.
local closeW,closeH=buttons.Close:GetWidth(),buttons.Close:GetHeight()
local actions0,sent0=#H.actions,#H.sent
local function welcome(m,name)
 Nexus.QuickStart.Show()
 local close,label=buttons.Close,'Welcome, '..m.name..name
 check(qs:IsShown() and qs.sync,label..': the Welcome and its Sync line are shown')
 fits(close,'Close',m,label,closeDep)
 local w2,h2,r=qs:GetWidth(),qs:GetHeight(),G.Rect(close,qs)
 check(G.Inside(r,{11,12,w2-12,h2-11}) and w2<=1024 and h2/2+55<=384,label..': Close inside the window border, window on the smallest UI '..G.Text(r))
 local others={hint,qs.sync}
 for i=1,#order-1 do others[#others+1]=buttons[order[i]] end
 for _,o in ipairs(others)do
  local box=G.Rect(o,qs);check(G.Apart(r,box),label..': Close apart from the hint, Sync line or control at '..G.Text(box))
 end
end
for _,m in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double})do
 for _,measured in ipairs({true,false})do
  for _,metrics in ipairs({true,false})do
   local name=(measured and ', text measured' or ', text unmeasured')..(metrics and ', LayoutMetrics' or ', no LayoutMetrics')
   under('Auto warning, '..m.name..name,m,measured,metrics,function()
    check(Nexus.OverwriteWarning.RequestAuto(AUTO_OWNER,function() autoAccepted=autoAccepted+1 end)==false,'an Auto request opens the warning, accepting nothing')
    local w=answers('Auto',m,name,'Yes','No')
    check(w.yes:GetWidth()==110 and w.no:GetWidth()==110 and w:GetWidth()==520,'Auto warning, '..m.name..name..': Yes / No keep the original 110 px answers and 520 px window')
   end)
   under('Welcome, '..m.name..name,m,measured,metrics,function() welcome(m,name) end)
  end
 end
end
Nexus.QuickStart.Show()
check(qs:GetWidth()==W and buttons.Close:GetWidth()==closeW and buttons.Close:GetHeight()==closeH,'restored measurement fits the Welcome as before the label cases')
check(autoAccepted==0 and not NexusOverwriteWarning:IsShown() and #H.actions==actions0 and #H.sent==sent0,'label cases accept, submit and spend nothing')

-- Handlers keep their behaviour: Close closes the window and assigns, saves
-- and spends nothing.
local actions,sent=#H.actions,#H.sent
buttons.Close:Click()
check(not qs:IsShown(),'Close closes Quick Start')
check(#H.actions==actions and #H.sent==sent,'closing Quick Start submits nothing')

-- Fresh first-launch warning constructors. The long Continue / Close answers
-- above were fitted at one presentation only. Here every declared model runs
-- with the real text measurement available and absent, and with the real
-- LayoutMetrics table present and absent. Each case loads the public
-- ui/OverwriteWarning.lua into a temporary Nexus namespace that holds only
-- that table, over a fresh empty synthetic NexusDB. It opens its first-launch
-- warning through its own EnsureOnboarding, whose outcome is session scoped.
-- The original warning's outcome is only read, and no time passes. Each
-- warning's own Close (X) hides it. The namespace, saved data and globals are
-- restored even when a case raises. Body paragraphs are not fitted here.
-- Offline models only; native NOT_RUN.
do
 local nexus0,db0,ow0,outcome0=Nexus,rawget(_G,'NexusDB'),Nexus.OverwriteWarning,Nexus.OverwriteWarning.EnsureOnboarding()
 local dbCopy,w0,scroll0,qs0=H.Clone(db0),rawget(_G,'NexusOverwriteWarning'),rawget(_G,'NexusOverwriteWarningScroll'),rawget(_G,'NexusQuickStart')
 local special0,yes0,no0,width0=#UISpecialFrames,w0.yes:GetText(),w0.no:GetText(),w0:GetWidth()
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double})do
  for _,measured in ipairs({true,false})do
   for _,metrics in ipairs({true,false})do
    local label='fresh onboarding warning, '..m.name..(measured and ', text measured' or ', text unmeasured')..(metrics and ', LayoutMetrics' or ', no LayoutMetrics')
    under(label,m,measured,metrics,function()
     local db={}
     local ok,err=xpcall(function()
      Nexus,NexusDB={LayoutMetrics=metrics and metrics0 or nil},db
      local fresh=dofile('ui/OverwriteWarning.lua')
      check(type(fresh)=='table' and fresh~=ow0 and Nexus.OverwriteWarning==fresh and nexus0.OverwriteWarning==ow0,label..': a fresh public warning module in its own namespace')
      check(fresh.EnsureOnboarding()=='pending' and fresh.IsOpen(),label..': its EnsureOnboarding opens the first-launch warning')
      local w=rawget(_G,'NexusOverwriteWarning')
      check(w and w~=w0 and w:IsShown() and w.yes and w.no and w.close and not w.yes:IsEnabled() and not w.no:IsEnabled(),label..': a fresh warning is shown, its answers held for the reading interval')
      local named=expect(w.yes:GetText()==CONTINUE and w.no:GetText()=='Close',label..': answers read exactly "'..CONTINUE..'" / "Close" ['..tostring(w.yes:GetText())..' / '..tostring(w.no:GetText())..']')
      local dep=named and '' or ' [depends on the failed caption EXPECT]'
      fits(w.yes,CONTINUE,m,label,dep);fits(w.no,'Close',m,label,dep)
      local ww,wh=w:GetWidth(),w:GetHeight()
      local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
      check(G.Inside(yes,{5,5,ww-5,wh-5}) and G.Inside(no,{5,5,ww-5,wh-5}) and ww<=1024,label..': answers inside a window on the smallest UI '..G.Text(yes)..G.Text(no)..dep)
      check(G.Apart(yes,no),label..': answers do not overlap'..dep)
      for _,o in ipairs(w.children)do
       if o~=w.yes and o~=w.no and o:IsShown() then
        local r=G.Rect(o,w);check(G.Apart(yes,r) and G.Apart(no,r),label..': answers apart from the control at '..G.Text(r)..dep)
       end
      end
     end,debug.traceback)
     local tmp,closed=rawget(_G,'NexusOverwriteWarning'),true
     if tmp and tmp~=w0 then
      pcall(function() tmp.close:Click() end)
      closed=not tmp:IsShown() and tmp:GetScript('OnUpdate')==nil
      if not closed then pcall(function() tmp:Hide() end);tmp:SetScript('OnUpdate',nil) end
     end
     Nexus,NexusDB=nexus0,db0
     _G.NexusOverwriteWarning,_G.NexusOverwriteWarningScroll,_G.NexusQuickStart=w0,scroll0,qs0
     for i=#UISpecialFrames,special0+1,-1 do UISpecialFrames[i]=nil end
     if not ok then error(err,0) end
     check(closed and next(db)==nil,label..': its own Close (X) hides it and stops its countdown; its synthetic NexusDB stays empty')
    end)
   end
  end
 end
 local restored=Nexus==nexus0 and NexusDB==db0 and Nexus.OverwriteWarning==ow0 and Nexus.LayoutMetrics==metrics0 and G.model==nil
  and rawget(_G,'NexusOverwriteWarning')==w0 and rawget(_G,'NexusQuickStart')==qs0 and rawget(_G,'NexusFontNormal')==font0 and #UISpecialFrames==special0
 for _,k in ipairs(MEASURE)do restored=restored and rawget(methods,k)==saved[k] end
 check(restored,'fresh warning cases restore the namespace, saved data, windows, font object, measurement and model')
 check(T.Equal(NexusDB,dbCopy) and #H.actions==actions and #H.sent==sent and autoAccepted==0,'fresh warning cases change no saved data and accept, submit and spend nothing')
 check(not ow0.IsOpen() and ow0.EnsureOnboarding()==outcome0 and not w0:IsShown() and w0.yes:GetText()==yes0 and w0.no:GetText()==no0 and w0:GetWidth()==width0 and not qs:IsShown(),'the original warning keeps its outcome, answers and width; the Welcome stays closed')
end
if #missed+#raised>0 then
 error('quickstart_layout_fit: '..#missed..' label EXPECT(s) failed and '..#raised..' label case(s) raised a setup or guard failure; first: '..tostring(missed[1] or raised[1]),0)
end
print('PASS Quick Start text fits its regions in the default and conservative font models; the full answer and Close labels fit the declared label models; no overlap; inside the window; checks='..checks)
