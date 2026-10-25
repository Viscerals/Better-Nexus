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
-- Taxonomy. EXPECT (expect: collected, reported at the end) is a requirement
-- new with these labels: the new exact captions (Continue / Close and the
-- Welcome's Close) and a fit newly required by a long label or by the
-- 2.0-scale Close (the original 110x28 answer or 74x24 Close box did not
-- hold it). GUARD (guard: a check tagged GUARD) is behaviour or ordinary
-- geometry that already held: the Auto Yes / No captions and fits, the
-- first-launch Close answer's fit, the unchanged answer heights, the ordinary
-- Welcome Close fit, the 110 / 520 answer row, the 74x24 Close in the 420 px
-- Welcome and the Welcome entries' texts. SETUP (check) is the fixture's own
-- precondition. A result that depends on a failed caption EXPECT says so.
-- The verdict fails on any failed EXPECT or RAISED case. Setup and guards still
-- assert; inside a label case, a failed one is reported as a RAISED case.
-- Every case restores the harness measurement, the font object and
-- LayoutMetrics, and declines its own Auto request, also when it raises.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local CONTINUE='Continue \226\128\148 Auto stays OFF' -- U+2014 em dash: the exact onboarding caption
-- CAPS is a stated synthetic end-cap allowance: the +24 that ui/LayoutMetrics.lua
-- FitButtonWidth (and the warning's and the Welcome's own fallbacks) add to a
-- label's width. It is not quoted from docs/UI_TEXT_LAYOUT.md, which names no
-- number, and is no independent proof of the native button template's caps.
local CAPS=24
local methods,MEASURE=G.RegionMethods(),{'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
local saved,font0,metrics0={},rawget(_G,'NexusFontNormal'),Nexus.LayoutMetrics
for _,k in ipairs(MEASURE)do saved[k]=rawget(methods,k) end
local AUTO_OWNER,autoAccepted,missed,raised,warning={},0,{},{}
local function expect(v,m)checks=checks+1;if v then return true end;missed[#missed+1]=m;print('FAIL EXPECT '..m);return false end
-- GUARD: an already-holding behaviour or geometry check. It asserts as check
-- does (inside a label case a failure is a RAISED case) and is tagged GUARD.
local function guard(v,m)check(v,'GUARD '..m);return true end
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
-- The warning's answer row by its literal layout contract, through the real
-- anchors and rectangles (GUARD: it held before the labels). No keeps 110 px
-- at BOTTOMRIGHT -24/20; Yes sits 14 px left of No on the same row; the
-- 410 px high window stays 520 px wide while both answers fit there and
-- otherwise grows only until Yes reaches the 24 px left edge.
local function answerRow(w,label,dep)
 local ww,wh=w:GetWidth(),w:GetHeight()
 local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
 local noPoint,yesPoint={w.no:GetPoint(1)},{w.yes:GetPoint(1)}
 guard(w.no:GetNumPoints()==1 and noPoint[1]=='BOTTOMRIGHT' and w.no:GetWidth()==110 and no[3]==ww-24 and no[4]==wh-20,
  label..': No keeps 110 px at BOTTOMRIGHT -24/20 '..G.Text(no)..dep)
 guard(w.yes:GetNumPoints()==1 and yesPoint[1]=='BOTTOMRIGHT' and no[1]-yes[3]==14 and yes[4]==no[4],
  label..': Yes sits 14 px left of No on the same row '..G.Text(yes)..G.Text(no)..dep)
 guard(wh==410 and ww>=520 and yes[1]>=24 and (ww==520 or yes[1]==24),
  label..': the 410 px high window stays 520 px wide while both answers fit and grows only as needed ['..ww..'x'..wh..']'..dep)
end
-- A fit is GUARD where the original literal box (w0 x h0: the 110x28 answer,
-- the 74x24 Close) already held the whole label at this model, and EXPECT
-- where it is newly required (a long label, the 2.0-scale Close). Without a
-- box it stays EXPECT.
local function fits(button,caption,m,label,dep,w0,h0)
 local need=G.Length(caption)*m.char+CAPS
 local widthCheck=w0 and need<=w0 and guard or expect
 local heightCheck=h0 and m.line<=h0 and guard or expect
 widthCheck(G.Length(caption)*m.char+CAPS<=button:GetWidth(),label..': the whole "'..caption..'" fits its button width ['..button:GetWidth()..']'..dep)
 heightCheck(m.line<=button:GetHeight(),label..': one complete line fits its button height ['..button:GetHeight()..']'..dep)
end
local function answers(kind,m,name,yesCaption,noCaption)
 local w,label=NexusOverwriteWarning,kind..' warning, '..m.name..name
 check(w and w==warning and w:IsShown() and w.close and w.suppress and w.countdown,label..': the same warning is shown with its controls')
 -- Auto keeps its original Yes / No (GUARD); Continue / Close are new (EXPECT).
 local named=(kind=='Auto' and guard or expect)(w.yes:GetText()==yesCaption and w.no:GetText()==noCaption,label..': answers read exactly "'..yesCaption..
  '" / "'..noCaption..'" ['..tostring(w.yes:GetText())..' / '..tostring(w.no:GetText())..']')
 local dep=named and '' or ' [depends on the failed caption EXPECT]'
 fits(w.yes,yesCaption,m,label,dep,110,28);fits(w.no,noCaption,m,label,dep,110,28)
 local ww,wh=w:GetWidth(),w:GetHeight()
 local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
 check(G.Inside(yes,{5,5,ww-5,wh-5}) and G.Inside(no,{5,5,ww-5,wh-5}) and ww<=1024,label..': answers inside a window on the smallest UI '..G.Text(yes)..G.Text(no))
 check(G.Apart(yes,no),label..': answers do not overlap')
 for _,o in ipairs({w.close,w.suppress,w.countdown})do
  local r=G.Rect(o,w);check(G.Apart(yes,r) and G.Apart(no,r),label..': answers apart from the control at '..G.Text(r))
 end
 answerRow(w,label,dep)
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
guard(W==420 and closeW==74 and closeH==24,'the default Welcome is 420 px wide with its original 74x24 Close'..closeDep)
-- The other Welcome regions' sizes at this presentation. No presentation
-- changes them; a widened window moves its right-anchored controls only.
local KEEP,KEEP0={hint,body},{}
if qs.sync then KEEP[#KEEP+1]=qs.sync end
for i=1,#order-1 do KEEP[#KEEP+1]=buttons[order[i]] end
for i,o in ipairs(KEEP)do KEEP0[i]=o:GetWidth()..'x'..o:GetHeight() end
local actions0,sent0=#H.actions,#H.sent
local welcomeFit
local function welcome(m,name)
 Nexus.QuickStart.Show()
 welcomeFit(m,'Welcome, '..m.name..name)
end
-- The Welcome's fit oracle after any entry; it shows nothing itself. Close
-- holds its whole label, lies inside the border and apart from the hint, the
-- Sync line and the six other controls, and follows the right edge; the
-- window grows only to keep Close 8 px right of the hint; the hint keeps its
-- place and the other regions their sizes.
function welcomeFit(m,label)
 local close=buttons.Close
 check(qs:IsShown() and qs.sync,label..': the Welcome and its Sync line are shown')
 fits(close,'Close',m,label,closeDep,74,24)
 local w2,h2,r=qs:GetWidth(),qs:GetHeight(),G.Rect(close,qs)
 check(G.Inside(r,{11,12,w2-12,h2-11}) and w2<=1024 and h2/2+55<=384,label..': Close inside the window border, window on the smallest UI '..G.Text(r))
 local others={hint,qs.sync}
 for i=1,#order-1 do others[#others+1]=buttons[order[i]] end
 local hr,same=G.Rect(hint,qs),true
 for i,o in ipairs(KEEP)do same=same and o:GetWidth()..'x'..o:GetHeight()==KEEP0[i] end
 guard(same and h2==Ht and hr[1]==24 and hr[4]==h2-22,label..': the hint stays at BOTTOMLEFT 24/22 '..G.Text(hr)..', the window keeps its '..Ht..' px height and the other regions their sizes')
 guard(r[3]==w2-24 and r[4]==h2-20,label..': Close follows the right edge at BOTTOMRIGHT -24/20 '..G.Text(r)..closeDep)
 guard(w2>=420 and r[1]-hr[3]>=8 and (w2==420 or r[1]-hr[3]==8),label..': the window stays 420 px unless Close needs room, then grows only to keep Close 8 px right of the hint ['..w2..']'..closeDep)
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

-- The Welcome's own entries on its cached window. The real warning was
-- answered Continue above, and the real first-time Welcome is neither closed
-- nor acknowledged. Each step hides the Welcome (a plain Hide: no Finish,
-- nothing recorded) and enters it again through the real ShowIfFirstTime
-- (the first-time window) or the real ShowSetup (the informational replay,
-- entered hidden because it refits only a hidden Welcome). Nothing shows the
-- Welcome between an entry and its oracle (welcomeFit). At 2.0 scale, with
-- the text measured and unmeasured and LayoutMetrics present and absent,
-- Close must grow (EXPECT: newly required sizing); at the default model it
-- must be the original 74x24 in the 420 px window again, after the same and
-- after the other entry (GUARD), each entry with its exact texts (GUARD).
-- Afterwards ShowIfFirstTime reopens the first-time Welcome at the harness
-- measurement (if it does not, that is reported, and only then does the
-- deliberate Show restore it), so the original Close handler and no-effect
-- checks below still run. Saved data, the warning's answer and the dismissal
-- state are only read. Offline models only; native NOT_RUN.
do
 local Q,OW,title=Nexus.QuickStart,Nexus.OverwriteWarning,texts['Welcome to Nexus']
 local SETUP_TITLE,SETUP_HINT='Nexus setup (information only)','Information only: this guide saves nothing and never turns Auto ON.'
 local db1,settled0,actions1,sent1=H.Clone(rawget(_G,'NexusDB')),Q.Settled(),#H.actions,#H.sent
 local function reads(t,h) return title~=nil and G.Visible(title:GetText())==t and G.Visible(hint:GetText())==h end
 local D,X=G.MODELS.default,G.MODELS.double
 local steps={
  {'ShowIfFirstTime',D,true,true},{'ShowIfFirstTime',X,true,true},{'ShowIfFirstTime',D,true,true},
  {'ShowSetup',D,true,true},{'ShowSetup',X,true,true},{'ShowSetup',D,true,true},
  {'ShowSetup',X,false,true},{'ShowIfFirstTime',D,false,true},
  {'ShowIfFirstTime',X,false,false},{'ShowSetup',D,false,false},
  {'ShowSetup',X,false,false},{'ShowSetup',D,true,false},
  {'ShowIfFirstTime',X,true,false},{'ShowIfFirstTime',D,true,false},
 }
 for i,s in ipairs(steps)do
  local entry,m,measured,metrics=s[1],s[2],s[3],s[4]
  local label='Welcome '..entry..' step '..i..', '..m.name..(measured and ', text measured' or ', text unmeasured')..(metrics and ', LayoutMetrics' or ', no LayoutMetrics')
  under(label,m,measured,metrics,function()
   local close=buttons.Close
   local was=close:GetWidth()..'x'..close:GetHeight()..' in '..qs:GetWidth()
   qs:Hide()
   check(not qs:IsShown() and not OW.IsOpen(),label..': SETUP the Welcome is hidden without Finish and no warning waits')
   if entry=='ShowIfFirstTime' then
    local settled=Q.ShowIfFirstTime()
    guard(settled==false and NexusQuickStart==qs and qs:IsShown() and reads('Welcome to Nexus',HINT),
     label..': ShowIfFirstTime reopens the cached first-time Welcome with its exact title and hint ['..tostring(settled)..']')
   else
    local shown,why=Q.ShowSetup()
    guard(shown==true and why==nil and NexusQuickStart==qs and qs:IsShown() and reads(SETUP_TITLE,SETUP_HINT),
     label..': ShowSetup opens the cached hidden Welcome as information only with its exact title and hint ['..tostring(shown)..', '..tostring(why)..']')
   end
   welcomeFit(m,label)
   local cw,ch,ww=close:GetWidth(),close:GetHeight(),qs:GetWidth()
   local now=' ['..cw..'x'..ch..' in '..ww..', was '..was..']'
   if m==D then
    guard(cw==74 and ch==24 and ww==420,label..': Close is again the original 74x24 in the 420 px window'..now..closeDep)
   else
    expect(cw>74 and ch>24,label..': Close grows past its original 74x24 for its whole label'..now..closeDep)
   end
  end)
 end
 pcall(function() qs:Hide() end)
 local ok,settled=pcall(Q.ShowIfFirstTime)
 if not (ok and settled==false and qs:IsShown() and reads('Welcome to Nexus',HINT)) then
  raised[#raised+1]='Welcome entries: ShowIfFirstTime did not reopen the first-time Welcome at the harness measurement ['..tostring(ok)..', '..tostring(settled)..']; the deliberate Show restores it for the original checks'
  print('FAIL RAISED '..raised[#raised])
  Nexus.QuickStart.Show()
 end
 check(qs:IsShown() and reads('Welcome to Nexus',HINT) and qs:GetWidth()==W and buttons.Close:GetWidth()==closeW and buttons.Close:GetHeight()==closeH,
  'SETUP the first-time Welcome is restored at the harness measurement for the original Close handler')
 guard(Q.Settled()==settled0 and T.Equal(rawget(_G,'NexusDB'),db1) and #H.actions==actions1 and #H.sent==sent1 and autoAccepted==0
  and not OW.IsOpen() and not NexusOverwriteWarning:IsShown(),'the Welcome entries record no dismissal, change no saved data and accept, submit and spend nothing')
end

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
      fits(w.yes,CONTINUE,m,label,dep,110,28);fits(w.no,'Close',m,label,dep,110,28)
      local ww,wh=w:GetWidth(),w:GetHeight()
      local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
      check(G.Inside(yes,{5,5,ww-5,wh-5}) and G.Inside(no,{5,5,ww-5,wh-5}) and ww<=1024,label..': answers inside a window on the smallest UI '..G.Text(yes)..G.Text(no)..dep)
      check(G.Apart(yes,no),label..': answers do not overlap'..dep)
      answerRow(w,label,dep)
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
do
 -- Invalid measurement, font and helper boundaries (offline models; native
 -- NOT_RUN). Each stated case breaks inputs of the answer and Close fit: the
 -- text width is 0, negative, NaN or infinite, raises, or is not a function
 -- (raw on the Welcome's Close, where a nil would resolve the harness no-op;
 -- a fresh warning makes and fits its answers inside one EnsureOnboarding, so
 -- it gets that value through the shared widget methods); NexusFontNormal's
 -- GetFont raises or reports an invalid size; LayoutMetrics.FitButtonWidth
 -- raises or returns below its minimum after setting a bogus width. The real
 -- LayoutMetrics is present or absent as stated. Each case runs a fresh public
 -- ui/OverwriteWarning through its own EnsureOnboarding and the current
 -- deliberate Welcome (QuickStart.Show). Oracle, the documented fallback:
 -- 7 px per visible character at font scale 1 (an invalid font reads as 1)
 -- and 14 px at 2.0, plus 24 px end caps; answers at least 110 px, Close at
 -- least 74x24 with a 13 px line per font scale. Invalid widths use the 2.0
 -- model, invalid fonts the default model (whose own size reads as 1). Full
 -- captions, the long affirmative's fit and stated width and, at 2.0, the
 -- 546 px warning and the Welcome's Close fit, size and line and 440 px width
 -- are EXPECT, the collected new-feature expectations. Dimensions that already
 -- hold are tagged GUARD: "Close" fitting the No answer at its stated 110 px,
 -- and on the default model the 520 px warning and the Welcome's Close fit,
 -- 74x24 size and 420 px width. Reading, ordinary geometry, a line within the
 -- original height, no writes and restoration are guards too. Offline only,
 -- native NOT_RUN: nothing is answered, accepted or saved; no time passes.
 local KEYS,rm,lm,measure0={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'},G.RegionMethods(),Nexus.LayoutMetrics,{}
 for _,k in ipairs(KEYS)do measure0[k]=rawget(rm,k) end
 local fit0=type(lm)=='table' and rawget(lm,'FitButtonWidth')
 local nexus,db0,ow=Nexus,rawget(_G,'NexusDB'),Nexus.OverwriteWarning
 local dbSnap,outcome,actions1,sent1=H.Clone(db0),ow.EnsureOnboarding(),#H.actions,#H.sent
 local wOrig,scrollOrig,qsOrig,fontOrig=rawget(_G,'NexusOverwriteWarning'),rawget(_G,'NexusOverwriteWarningScroll'),rawget(_G,'NexusQuickStart'),rawget(_G,'NexusFontNormal')
 local fontRaw0,specials,special=type(fontOrig)=='table' and rawget(fontOrig,'GetFont') or nil,UISpecialFrames,{}
 for i,v in ipairs(specials)do special[i]=v end
 check(type(fit0)=='function' and outcome~='pending' and not ow.IsOpen() and wOrig and not wOrig:IsShown() and qsOrig and not qsOrig:IsShown(),'fault cases start from the real LayoutMetrics, the answered original warning and a closed Welcome')
 local yes1,no1,width1=wOrig.yes:GetText(),wOrig.no:GetText(),wOrig:GetWidth()
 local HINT_TEXT,byCaption,hintText='Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls.',{},nil
 for _,c in ipairs(qsOrig.children)do
  if c.kind=='Button' then byCaption[c:GetText()]=c end
  if c.kind=='FontString' and G.Visible(c:GetText())==HINT_TEXT then hintText=c end
 end
 local dismissal=byCaption.Close
 local closeNamed=expect(dismissal~=nil and dismissal:GetScript('OnClick')~=nil,'fault cases: the Welcome dismissal reads exactly "Close" with its click handler')
 if not dismissal then dismissal=byCaption.Later end -- the real legacy caption, only after that EXPECT failed
 local closeDep,sync=closeNamed and '' or ' [depends on the failed Close caption EXPECT]',rawget(qsOrig,'sync')
 check(dismissal and dismissal:GetScript('OnClick') and hintText and sync,'fault cases: the Welcome has its dismissal, hint and Sync line'..closeDep)
 local others={hintText,sync}
 for _,caption in ipairs({'Set up current build','Import / Create Wishlist','Browse Community builds','Open Leaderboard','Help / Getting Started','Orbs / Lost Memories'})do
  local b=byCaption[caption];check(b and b~=dismissal,'fault cases: the Welcome keeps "'..caption..'"');others[#others+1]=b
 end
 local dw,dh,qw,qh,rawWidth0=dismissal:GetWidth(),dismissal:GetHeight(),qsOrig:GetWidth(),qsOrig:GetHeight(),rawget(dismissal,'GetTextWidth')
 local function shape()
  local out={tostring(qsOrig:IsShown()),qsOrig:GetWidth(),qsOrig:GetHeight()}
  for _,c in ipairs(qsOrig.children)do
   out[#out+1]=table.concat({c.kind,tostring(c:GetText()),tostring(c:GetWidth()),tostring(c:GetHeight()),tostring(c:IsShown()),c:GetNumPoints()},'/')
  end
  return table.concat(out,'|')
 end
 local shape0=shape()
 -- Stated fallback sizes: the two answers, the warning width, Close and the Welcome width.
 local O={[G.MODELS.double]={yes=374,no=110,window=546,close=94,closeH=26,welcome=440},
  [G.MODELS.default]={yes=199,no=110,window=520,close=74,closeH=24,welcome=420}}
 local function raising(what) return function() error('injected '..what..' fault',0) end end
 local HELPER={raise=function(b) b:SetWidth(1);error('injected FitButtonWidth fault',0) end,
  below=function(b,minimum) local w=(tonumber(minimum) or 2)-1;b:SetWidth(w);return w end}
 local CASES={
  {fault='text width 0',m=G.MODELS.double,width=function() return 0 end,metrics=true},
  {fault='text width 0, own positive-width check',m=G.MODELS.double,width=function() return 0 end,metrics=false},
  {fault='negative text width',m=G.MODELS.double,width=function() return -88 end,metrics=false},
  {fault='NaN text width, FitButtonWidth raising',m=G.MODELS.double,width=function() return 0/0 end,metrics=true,helper='raise'},
  {fault='infinite text width, FitButtonWidth below its minimum',m=G.MODELS.double,width=function() return math.huge end,metrics=true,helper='below'},
  {fault='raising text width',m=G.MODELS.double,width=raising('GetTextWidth'),metrics=false},
  {fault='nonfunction text width',m=G.MODELS.double,width=42,metrics=true},
  {fault='nonfunction text width, own type check',m=G.MODELS.double,width=42,metrics=false},
  {fault='raising GetFont, text unmeasured',m=G.MODELS.default,font=raising('GetFont'),metrics=true},
  {fault='raising GetFont, text unmeasured, own exception check',m=G.MODELS.default,font=raising('GetFont'),metrics=false},
  {fault='invalid GetFont size, text unmeasured',m=G.MODELS.default,font=function() return 'Fonts\\FRIZQT__.TTF',0/0,'' end,metrics=false},
 }
 local function inject(c,widget)
  if c.width~=nil then
   if widget and type(c.width)~='function' then rawset(widget,'GetTextWidth',c.width) else rm.GetTextWidth=c.width end
  end
  if c.font then rawset(rawget(_G,'NexusFontNormal'),'GetFont',c.font) end
  if c.helper then lm.FitButtonWidth=HELPER[c.helper] end
 end
 local function restore()
  for _,k in ipairs(KEYS)do rm[k]=measure0[k] end
  local font=rawget(_G,'NexusFontNormal')
  if type(font)=='table' then rawset(font,'GetFont',font==fontOrig and fontRaw0 or nil) end
  lm.FitButtonWidth=fit0;rawset(dismissal,'GetTextWidth',rawWidth0)
  Nexus,NexusDB=nexus,db0;nexus.LayoutMetrics=lm;G.model=nil
  _G.NexusFontNormal,_G.NexusOverwriteWarning,_G.NexusOverwriteWarningScroll,_G.NexusQuickStart=fontOrig,wOrig,scrollOrig,qsOrig
  UISpecialFrames=specials;for i=#specials,#special+1,-1 do specials[i]=nil end
 end
 local function warningCase(c,label,o)
  local db,fresh={},nil
  local ok,err=xpcall(function()
   inject(c)
   Nexus,NexusDB={LayoutMetrics=c.metrics and lm or nil},db
   fresh=dofile('ui/OverwriteWarning.lua')
   check(type(fresh)=='table' and fresh~=ow and Nexus.OverwriteWarning==fresh and nexus.OverwriteWarning==ow,label..': a fresh public warning module in its own namespace')
   check(fresh.EnsureOnboarding()=='pending' and fresh.IsOpen(),label..': its EnsureOnboarding opens the first-launch warning')
   local w=rawget(_G,'NexusOverwriteWarning')
   check(w and w~=wOrig and w:IsShown() and w.yes and w.no and w.close and not w.yes:IsEnabled() and not w.no:IsEnabled(),label..': a fresh warning is shown, its answers held for the reading interval')
   local named=expect(w.yes:GetText()==CONTINUE and w.no:GetText()=='Close',label..': answers read exactly "'..CONTINUE..'" / "Close" ['..tostring(w.yes:GetText())..' / '..tostring(w.no:GetText())..']')
   local dep=named and '' or ' [depends on the failed caption EXPECT]'
   for _,a in ipairs({{w.yes,CONTINUE,o.yes},{w.no,'Close',o.no}})do
    local b,caption,want=a[1],a[2],a[3]
    local bw,bh=b:GetWidth(),b:GetHeight()
    local line=label..': one complete '..c.m.line..' px line fits "'..caption..'" ['..tostring(bh)..']'
    ;(caption=='Close' and guard or expect)(G.Length(caption)*c.m.char+CAPS<=bw,label..': the whole "'..caption..'" fits its button width ['..tostring(bw)..']'..dep)
    ;(caption=='Close' and guard or expect)(bw==want,label..': "'..caption..'" takes the stated fallback width '..want..' px ['..tostring(bw)..']'..dep)
    if c.m.line<=28 then check(c.m.line<=bh,line) else expect(c.m.line<=bh,line..dep) end
   end
   local ww,wh=w:GetWidth(),w:GetHeight()
   ;(o.window==520 and guard or expect)(ww==o.window,label..': the window takes the stated width '..o.window..' px ['..tostring(ww)..']'..dep)
   local yes,no=G.Rect(w.yes,w),G.Rect(w.no,w)
   check(G.Inside(yes,{5,5,ww-5,wh-5}) and G.Inside(no,{5,5,ww-5,wh-5}) and ww<=1024,label..': answers inside a window on the smallest UI '..G.Text(yes)..G.Text(no))
   check(no[3]==ww-24 and no[4]==wh-20 and yes[3]==no[1]-14 and yes[4]==no[4] and G.Apart(yes,no),label..': answers keep their 24 px edge and 14 px gap without overlap '..G.Text(yes)..G.Text(no))
   for _,other in ipairs(w.children)do
    if other~=w.yes and other~=w.no and other:IsShown() then
     local r=G.Rect(other,w);check(G.Apart(yes,r) and G.Apart(no,r),label..': answers apart from the control at '..G.Text(r))
    end
   end
  end,debug.traceback)
  local closed=true
  pcall(function()
   local tmp=rawget(_G,'NexusOverwriteWarning')
   if tmp and tmp~=wOrig then
    closed=false;pcall(function() tmp.close:Click() end)
    closed=not tmp:IsShown() and tmp:GetScript('OnUpdate')==nil
    if not closed then pcall(function() tmp:Hide() end);pcall(function() tmp:SetScript('OnUpdate',nil) end) end
   end
  end)
  restore()
  if not ok then error(err,0) end
  check(closed and next(db)==nil and not fresh.IsOpen(),label..': its own Close (X) hides it and stops its countdown; its synthetic NexusDB stays empty')
 end
 local function welcomeCase(c,label,o)
  local ok,err=xpcall(function()
   inject(c,dismissal)
   Nexus.QuickStart.Show()
   check(rawget(_G,'NexusQuickStart')==qsOrig and qsOrig:IsShown() and not ow.IsOpen() and not wOrig:IsShown(),label..': the deliberate Welcome is shown, over no warning')
   local w2,h2,bw,bh=qsOrig:GetWidth(),qsOrig:GetHeight(),dismissal:GetWidth(),dismissal:GetHeight()
   local line=label..': one complete '..c.m.line..' px line fits Close ['..tostring(bh)..']'..closeDep
   ;(c.m==G.MODELS.default and guard or expect)(G.Length('Close')*c.m.char+CAPS<=bw,label..': the whole "Close" fits its button width ['..tostring(bw)..']'..closeDep)
   ;(c.m==G.MODELS.default and guard or expect)(bw==o.close and bh==o.closeH,label..': Close takes the stated fallback size '..o.close..'x'..o.closeH..' ['..tostring(bw)..'x'..tostring(bh)..']'..closeDep)
   if c.m.line<=24 then check(c.m.line<=bh,line) else expect(c.m.line<=bh,line) end
   ;(c.m==G.MODELS.default and guard or expect)(w2==o.welcome,label..': the Welcome takes the stated width '..o.welcome..' px ['..tostring(w2)..']'..closeDep)
   local r=G.Rect(dismissal,qsOrig)
   check(G.Inside(r,{11,12,w2-12,h2-11}) and w2<=1024 and h2/2+55<=384,label..': Close inside the window border, window on the smallest UI '..G.Text(r))
   for _,other in ipairs(others)do
    local box=G.Rect(other,qsOrig);check(G.Apart(r,box),label..': Close apart from the hint, Sync line or control at '..G.Text(box))
   end
  end,debug.traceback)
  restore()
  local hidden=pcall(function() qsOrig:Hide() end)
  pcall(function() dismissal:SetWidth(dw);dismissal:SetHeight(dh);qsOrig:SetWidth(qw);qsOrig:SetHeight(qh) end)
  if not ok then error(err,0) end
  check(hidden and not qsOrig:IsShown() and ow.EnsureOnboarding()==outcome and not ow.IsOpen() and T.Equal(rawget(_G,'NexusDB'),dbSnap) and #H.actions==actions1 and #H.sent==sent1,label..': hidden again; the original warning outcome, saved data, actions and sends are unchanged')
 end
 for _,c in ipairs(CASES)do
  local name=', '..c.m.name..', '..c.fault..(c.metrics and ', LayoutMetrics' or ', no LayoutMetrics')
  under('fault, fresh onboarding warning'..name,c.m,c.font==nil,c.metrics,function() warningCase(c,'fault, fresh onboarding warning'..name,O[c.m]) end)
  under('fault, deliberate Welcome'..name,c.m,c.font==nil,c.metrics,function() welcomeCase(c,'fault, deliberate Welcome'..name,O[c.m]) end)
 end
 local same=Nexus==nexus and rawget(_G,'NexusDB')==db0 and nexus.OverwriteWarning==ow and nexus.LayoutMetrics==lm and rawget(lm,'FitButtonWidth')==fit0 and G.model==nil
  and rawget(_G,'NexusOverwriteWarning')==wOrig and rawget(_G,'NexusOverwriteWarningScroll')==scrollOrig and rawget(_G,'NexusQuickStart')==qsOrig and rawget(_G,'NexusFontNormal')==fontOrig
  and UISpecialFrames==specials and #specials==#special and rawget(dismissal,'GetTextWidth')==rawWidth0 and (type(fontOrig)~='table' or rawget(fontOrig,'GetFont')==fontRaw0)
 for i,v in ipairs(special)do same=same and specials[i]==v end
 for _,k in ipairs(KEYS)do same=same and rawget(rm,k)==measure0[k] end
 check(same,'fault cases restore the namespace, saved data, windows, font object, measurement, helper, widget override, special frames and model')
 check(T.Equal(rawget(_G,'NexusDB'),dbSnap) and #H.actions==actions1 and #H.sent==sent1,'fault cases change no saved data and submit, send and spend nothing')
 check(not ow.IsOpen() and ow.EnsureOnboarding()==outcome and not wOrig:IsShown() and wOrig.yes:GetText()==yes1 and wOrig.no:GetText()==no1 and wOrig:GetWidth()==width1 and shape()==shape0,'fault cases keep the original warning outcome, answers and width and the closed Welcome as it was')
end
if #missed+#raised>0 then
 error('quickstart_layout_fit: '..#missed..' EXPECT(s) failed (collected) and '..#raised..' case(s) raised a SETUP or GUARD failure; first: '..tostring(missed[1] or raised[1]),0)
end
print('PASS Quick Start text fits its regions in the default and conservative font models; the full answer and Close labels fit the declared label models; no overlap; inside the window; checks='..checks)
