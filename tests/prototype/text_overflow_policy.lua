-- Text boxes that must not cut their text (BN text/layout audit). With a
-- wider, taller replacement face (16 px, measured natively for 20dabcd) and
-- the default face:
--  1. Role picker: the longest message keeps both its lines above the
--     Confirm row; the row labels keep one line at the row height.
--  2. On-Screen Wishlist settings: the subtitle and the hint take their
--     measured height and the controls below them move down, inside the popup.
--  3. Orb panel and Continue: a fixed status or refusal box keeps its size and
--     its complete text is in a tooltip while it overflows (only then).
--  4. Orb history: the details child is as tall as the measured details, so
--     the last line of a long operation is inside the scroll range.
--  5. Release note: the window is as tall as the measured note, above its button.
--  6. Loading status: both status lines keep their measured height; the bar
--     and the elapsed line follow inside the window.
--  7. Log viewer: the status line stays left of Clear Log (it used to run
--     under it), and a longer status is complete in its tooltip.
--  8. Support report: a fixed box shows a tooltip only while its text overflows.
--  9. On-Screen Wishlist overlay: every row box is one line tall at the row
--     pitch, so adjacent rows never overlap; every column and the final row
--     lie inside the overlay, below its control strip, at every overlay scale
--     and in both lock states; a long or multi-line name keeps its one row.
-- Real windows with synthetic data; nothing is selected, sent or spent.
-- Geometry and text fit use the offline models of
-- tests/prototype/layout_geometry_support.lua; native pixel fit is NOT TESTED.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local G

local function Tooltip()
 local tip,lines=GameTooltip,{}
 local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show,Hide=tip.Hide}
 tip.SetOwner=function() lines.owned=true end
 tip.AddLine=function(_,t) lines[#lines+1]=tostring(t) end
 tip.Show=function() end;tip.Hide=function() end
 return lines,function() for k,v in pairs(saved) do tip[k]=v end end
end
local function Hover(hit)
 local lines,restore=Tooltip()
 hit:GetScript('OnEnter')(hit);hit:GetScript('OnLeave')(hit)
 restore()
 return lines.owned and lines or nil
end

-- 1 and 2. Role picker and display settings (one boot of the real editor).
do
 local H=dofile('tests/prototype/harness.lua')
 G=dofile('tests/prototype/layout_geometry_support.lua')
 local entries={}
 for i=1,85 do entries[i]={spellId=200000+i,quality=i%4,stacks=1} end
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
  [102]={name='Another',verified=false,echoes=entries}}
 H.locked=nil -- the current locked list has not arrived
 H.Boot()
 local candidate
 for _,c in ipairs(Nexus.GameAdapter.GetWishlistCandidates()) do if c.slot==102 then candidate=c end end
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  check(Nexus.WishlistEditor.OpenForWishlist(candidate,1),'the plan opens')
  local f=assert(NexusWishlistRolePicker)
  check(f:IsShown() and f.message:GetText():find("Waiting for the server's current locked Echo list",1,true),
   'fixture: the picker shows its longest message')
  local n=G.Rows(f.message:GetText(),f.message:GetWidth(),m.char)
  check(f.message:GetHeight()>=n*m.line,m.name..': the message keeps all '..n..' lines ('..f.message:GetHeight()..' px)')
  local msg,confirm,cancel=G.Rect(f.message,f),G.Rect(NexusWishlistRoleConfirm,f),G.Rect(NexusWishlistRoleCancel,f)
  check(G.Apart(msg,confirm) and G.Apart(msg,cancel) and msg[4]<=confirm[2],m.name..': the message ends above the Confirm row')
  -- Dialog border insets of 10.
  local inner={10,10,f:GetWidth()-10,f:GetHeight()-10}
  check(G.Inside(confirm,inner) and G.Inside(cancel,inner) and G.Inside(msg,inner),m.name..': message and actions are inside the dialog')
  for i,row in ipairs(f.rows) do
   if row.frame:IsShown() then
    check(row.label:GetHeight()==row.frame:GetHeight(),m.name..': role row '..i..' label is one line at the row height')
   end
  end
  NexusWishlistRoleCancel:Click()
 end
 -- The On-Screen Wishlist settings popup, opened by its real button.
 Nexus.WishlistEditor.Show()
 local displayBtn
 for _,b in ipairs(H.frames) do if b.kind=='Button' and b:GetText()=='Display Settings' then displayBtn=b end end
 assert(displayBtn,'the Display Settings button exists')
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  displayBtn:Click()
  local p=assert(NexusDisplayPopup)
  check(p:IsShown(),'the settings popup opens')
  local texts,check_,slider={},nil,nil
  for _,c in ipairs(p.children) do
   if c.kind=='FontString' then texts[#texts+1]=c end
   if c.kind=='CheckButton' then check_=c end
   if c.kind=='Slider' then slider=c end
  end
  check_:SetSize(32,32) -- UICheckButtonTemplate's own size
  local subtitle,hint,moveLabel,sizeLabel
  for _,t in ipairs(texts) do
   local s=t:GetText() or ''
   if s:find('^Show, position') then subtitle=t elseif s:find('^Unlock to drag') then hint=t
   elseif s=='Position' then moveLabel=t elseif s=='Size' then sizeLabel=t end
  end
  for _,t in ipairs({subtitle,hint}) do
   local n=G.Rows(t:GetText(),t:GetWidth(),m.char)
   check(t:GetHeight()>=n*m.line,m.name..': "'..t:GetText():sub(1,20)..'" keeps all '..n..' lines')
  end
  local box={8,8,p:GetWidth()-8,p:GetHeight()-8}
  local sub,chk,move,hin,size,sld=G.Rect(subtitle,p),G.Rect(check_,p),G.Rect(moveLabel,p),G.Rect(hint,p),G.Rect(sizeLabel,p),G.Rect(slider,p)
  check(sub[4]<=chk[2] and chk[4]<=move[2]+2 and hin[4]<=size[2] and size[2]<sld[2],m.name..': subtitle, checkbox, position, hint, size and slider are stacked in order')
  check(G.Inside(sld,box) and G.Inside(hin,box) and G.Inside(sub,box),m.name..': the texts and the slider are inside the popup')
  p:Hide()
 end
 check(#H.actions==0,'role picker and settings take no game action')
end

-- 3 and 4. Orb panel, Continue and history (the Orb support boot).
do
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/orbs_support.lua');local M=H.M
 G=dofile('tests/prototype/layout_geometry_support.lua')
 SlashCmdList.NEXUS('orbs')
 local f=assert(NexusOrbPanel)
 -- The longest notice the Orb panel writes (ui/OrbPanel.lua).
 local LONG='The maximum follows the confirmed Orb balance, which is not available. Nothing was started.'
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  f.notice:SetText(LONG)
  local fits=G.Rows(LONG,f.notice:GetWidth(),m.char)*m.line<=f.notice:GetHeight()
  local lines=Hover(f.noticeHit)
  if fits then check(lines==nil,m.name..': a notice that fits shows no tooltip')
  else check(lines and lines[1]==LONG,m.name..': an overflowing notice is complete in its tooltip') end
  check(f.notice:GetHeight()==24 and f.status:GetHeight()==74,m.name..': the fixed boxes keep their size')
 end
 check(G.Rows(LONG,440,G.MODELS.px16.char)*G.MODELS.px16.line>24,'fixture: the 16 px face overflows the notice')
 local c=Nexus.OrbPanel.ShowContinue()
 c.body:SetText(string.rep('The game reported no usable outcome for the confirmed spend. ',20))
 G.UseFont(G.MODELS.px16)
 check(G.Rows(c.body:GetText(),540,7)*17>c.body:GetHeight(),'fixture: the explanation overflows its box')
 local lines=Hover(c.bodyHit)
 check(lines and lines[1]==c.body:GetText(),'an overflowing Continue explanation is complete in its tooltip')
 c:Hide()
 -- History: one operation with many long offers and a note.
 local offers={}
 for i=1,9 do offers[i]={spellId=410001+(i%8),quality=i%4,name='Synthetic offered Echo with a long name '..i} end
 local entry={serial=1,ordinal=1,at=110,state='confirmed',sourceKey='410001:1',sourceName='Disposable A',
  sourceQuality=1,sourceCopies=3,offered=offers,selectedKey='410002:2',selectionKind='TARGET',
  selectionReason='needed target',obtained='410002:2',confirmedAt=115,
  note=string.rep('A recorded note that explains the choice in full. ',6)}
 M.RunLog=function(which,from,count)
  local run={sessionOnly=true,which=which or 'current',runId=7,startedAt=100,build='test',character='Tester-Realm',
   wishlist='Raid plan',limit=15,state='FINISHED',reason='Finished - limit reached',spent=1,reserved=0,
   revision=3,total=1,entries={entry},hasCurrent=true,hasPrevious=false}
  return run
 end
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  local log=Nexus.OrbPanel.ShowLog()
  log.rows[1]:Click()
  local d=log.details
  check(d:GetText():find('Technical:',1,true),'fixture: the details end with the technical line')
  local n=G.Rows(d:GetText(),680,m.char)
  check(d:GetHeight()>=n*m.line and log.detailChild:GetHeight()>=d:GetHeight(),
   m.name..': the details child holds all '..n..' lines ('..log.detailChild:GetHeight()..' px)')
  check(log.detailScroll:GetVerticalScrollRange()>0,m.name..': the long details have a scroll range ('..log.detailScroll:GetVerticalScrollRange()..')')
  log.rows[1]:Click() -- deselect: the prompt fits the viewport again
  check(log.detailChild:GetHeight()>=96,m.name..': the child keeps at least the viewport height')
  log:Hide()
 end
 check(#H.actions==0 and (H.orbs.spends or 0)==0,'no Orb or game action')
end

-- 5-8. Release note, loading status, log viewer status and support report.
do
 local F=dofile('tests/prototype/format5_support.lua')
 local H=F.Boot(F.Database({mutate=function(db) db.hasSeenQuickStart=true end}))
 G=dofile('tests/prototype/layout_geometry_support.lua')
 G.UseFont(G.MODELS.px16)
 -- 5. The release note window is as tall as its measured note.
 Nexus.Changelog.ShowIfNeeded()
 local note=assert(NexusChangelogPopup,'the release note opens')
 local body,close
 for _,c in ipairs(note.children) do
  if c.kind=='FontString' and (c:GetText() or ''):find('Assigned Wishlist and visible Help',1,true) then body=c end
  if c.kind=='Button' and c:GetText()=='Got it' then close=c end
 end
 local n=G.Rows(body:GetText(),464,G.model.char)
 check(body:GetHeight()>=n*G.model.line,'16px face: the release note keeps all '..n..' lines')
 body:SetWidth(464) -- the width its two anchors give it
 local b,c=G.Rect(body,note),G.Rect(close,note)
 check(b[4]<=c[2] and G.Inside(c,{11,12,note:GetWidth()-12,note:GetHeight()-11}),
  '16px face: the note ends above "Got it", inside the window ('..note:GetHeight()..' px)')
 note:Hide()
 -- 6. The loading window keeps both status lines; the bar follows them.
 Nexus.LoadingStatus.Update({state='loading',coreReady=true,step='catalog',stepDone=123456,stepTotal=987654},true)
 local lf=assert(NexusLoadingStatusFrame)
 n=G.Rows(lf.detail:GetText(),402,G.model.char)
 check(lf.detail:GetHeight()>=n*G.model.line,'16px face: the loading status keeps all '..n..' lines')
 local d,bar,prog=G.Rect(lf.detail,lf),G.Rect(lf.bar,lf),G.Rect(lf.progress,lf)
 check(d[4]<=bar[2] and bar[4]<=prog[2] and prog[4]<=lf:GetHeight(),'16px face: status, bar and elapsed line are stacked inside the window')
 lf:Hide()
 -- 7. The log viewer status stays left of Clear Log and complete in its tooltip.
 Nexus.LogViewer.Show('errors')
 local lv=assert(NexusLogViewer)
 local status,clear
 for _,c in ipairs(lv.children) do
  if c.kind=='Button' and c:GetText()=='Clear Log' then clear=c end
 end
 for _,c in ipairs(lv.regions) do
  local p=c.points[1]
  if c.kind=='FontString' and p and p[1]=='BOTTOMLEFT' and p[4]==12 and p[5]==6 then status=c end
 end
 assert(status and clear,'the log viewer status line and Clear Log exist')
 local LONG='Page 12/34 | 1234567 total bytes | copy pages in order (no inserted separators)'
 status:SetText(LONG)
 check(G.Apart(G.Rect(status,lv),G.Rect(clear,lv)) and G.Inside(G.Rect(status,lv),{0,0,lv:GetWidth(),lv:GetHeight()}),
  'the status line is inside the window and clear of Clear Log')
 local hit
 for _,c in ipairs(lv.children) do if c._nexusText==status then hit=c end end
 local lines=Hover(assert(hit,'the status line has a hover area'))
 check(G.Rows(LONG,status:GetWidth(),G.model.char)*G.model.line<=status:GetHeight() and lines==nil
  or lines and lines[1]==LONG,'16px face: the status is shown whole or is complete in its tooltip')
 lv:Hide()
 -- 8. The support report's fixed boxes carry their complete text in a tooltip.
 Nexus.SupportReportUI.Show()
 local sr=assert(NexusSupportReport)
 local PREPARED='Stored report 7: 12345 bytes, 3 chunk(s), checksum abcdef0123456789; matches its own checksum in memory. This reads the stored copy; it does not prove the session that made it still exists.'
 sr.prepared:SetText(PREPARED)
 for _,c in ipairs(sr.children) do if c._nexusText==sr.prepared then hit=c end end
 check(G.Rows(PREPARED,680,G.model.char)*G.model.line<=sr.prepared:GetHeight() and Hover(hit)==nil,
  '16px face: the longest prepared-report line fits its box and needs no tooltip')
 local INCIDENT=string.rep('Recorded incident detail that the support page lists in full\n',12)
 sr.incident:SetText(INCIDENT)
 for _,c in ipairs(sr.children) do if c._nexusText==sr.incident then hit=c end end
 lines=Hover(hit)
 check(lines and lines[1]==INCIDENT,'16px face: an incident longer than its box is complete in its tooltip')
 sr:Hide()
 check(#H.actions==0,'no game action')
end

-- 9. On-Screen Wishlist overlay with a real imported plan (79 ordinary copies
-- and 6 planned locked targets, the most a plan holds) on the Orb support boot.
-- The overlay uses GameFontHighlightSmall, which the Nexus font scale does not
-- size, so the 0.75 and 2.0 font-scale models do not apply to it; the default
-- face and the 16 px replacement face (17 px lines; 16.1 px measured natively) do.
do
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 G=dofile('tests/prototype/layout_geometry_support.lua')
 local A,W,O=H.A,Nexus.WishlistEditor,Nexus.WishlistOverlay
 -- The harness answers these with nothing; record what the overlay asks for.
 local methods=G.RegionMethods()
 local createFontString=methods.CreateFontString
 methods.CreateFontString=function(self,name,_,template)
  local r=createFontString(self,name);r.template=template;return r
 end
 methods.SetWordWrap=function(self,v) self.wordWrap=v end
 methods.EnableMouse=function(self,v) self.mouse=v and true or false end
 H.perks.serverBuildSlots={[1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 local plan={}
 for i=1,79 do plan[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for i=80,85 do plan[i]={spellId=200000+i,quality=i%4,stacks=1,locked=true} end
 W.ImportEBH1String(assert(Nexus.Codec.EncodeEBH1(plan,'MAGE','Full plan')),'Full plan')
 local create
 for _,f in ipairs(H.frames) do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist' then create=f end end
 assert(create,'Create button');create:Click();H.AcceptPopup();H.now=H.now+3.1
 check(A.AssignedWishlist().state=='ready' and #A.AssignedWishlist().entries==85,
  'fixture: the assigned plan holds 79 ordinary copies and 6 locked targets')
 -- A long and a multi-line Echo name (catalog names are display text).
 local LONG=string.rep('Synthetic very long Echo name ',5)
 local MULTI='First line of a name\nsecond line of a name'
 local catalog=A.Catalog().rows
 catalog[200001].name=LONG;catalog[200002].name=MULTI
 H.locked={{spellId=200080,stacks=1}};H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
 local actions,sent=#H.actions,#H.sent
 O.Show();H.Advance(1.5)
 local f,controls
 for _,c in ipairs(H.frames) do
  if c:GetName()=='NexusOverlay' then f=c elseif c:GetName()=='NexusOverlayControls' then controls=c end
 end
 assert(f and controls,'the overlay and its control strip exist')
 local lines={}
 for _,r in ipairs(f.regions) do if r.kind=='FontString' then lines[#lines+1]=r end end
 check(#lines==90,'the overlay has its 90 rows: '..#lines)
 local function Shown()
  local out={}
  for i,r in ipairs(lines) do if r:IsShown() and r:GetText()~='' then out[#out+1]=i..'='..r:GetText() end end
  return table.concat(out,'\n'),#out
 end
 local before,shown=Shown()
 check(shown==85,'the 79 ordinary rows and 6 locked target rows are shown: '..shown)
 check(before:find('(locked target)|r (1/1)',1,true) and select(2,before:gsub('%(locked target%)|r %(0/1%)',''))==5,
  'the owned locked target counts (1/1) and the five others (0/1)')
 local longRow,multiRow
 for _,r in ipairs(lines) do
  if r:GetText():find(LONG,1,true) then longRow=r end
  if r:GetText():find(MULTI,1,true) then multiRow=r end
 end
 assert(longRow and multiRow,'fixture: the long and the multi-line names are shown')
 -- One line per row: no word wrap, the overlay's own font, and a box that
 -- holds one whole line but not a second, for each applicable font model.
 local wrapOff,font=0,0
 for _,r in ipairs(lines) do
  if r.wordWrap==false then wrapOff=wrapOff+1 end
  if r.template=='GameFontHighlightSmall' then font=font+1 end
 end
 check(wrapOff==90 and font==90,'every row is one GameFontHighlightSmall line without word wrap ('..wrapOff..', '..font..')')
 for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(m)
  local bad
  for i,r in ipairs(lines) do
   local h=r:GetHeight()
   if not (h>=m.line and h<2*m.line) then bad=bad or ('row '..i..' is '..h..' px') end
  end
  check(not bad,m.name..': every row box holds exactly one '..m.line..' px line'..(bad and (': '..bad) or ''))
  check(G.Rows(LONG,longRow:GetWidth(),m.char)>1 and G.Rows(MULTI,multiRow:GetWidth(),m.char)>1,
   m.name..': fixture: the long and the multi-line names would need more than one line')
 end
 -- Every row box inside the overlay, apart from every other row and from the
 -- control strip; the row pitch is at least the row box height.
 local function Geometry(label)
  local box,strip={0,0,f:GetWidth(),f:GetHeight()},G.Rect(controls,f)
  local rects={}
  for i,r in ipairs(lines) do rects[i]=G.Rect(r,f) end
  local bad
  for i,a in ipairs(rects) do
   if not G.Inside(a,box) then bad=bad or ('row '..i..' '..G.Text(a)..' is outside the overlay '..G.Text(box)) end
   if not G.Apart(a,strip) then bad=bad or ('row '..i..' '..G.Text(a)..' is under the control strip '..G.Text(strip)) end
   for j=i+1,#rects do
    local b=rects[j]
    if not G.Apart(a,b) then
     bad=bad or ('rows '..i..' '..G.Text(a)..' and '..j..' '..G.Text(b)..' overlap by '..math.max(0,a[4]-b[2])..' px')
    end
   end
  end
  check(not bad,label..': every row is inside the overlay, below the control strip and apart from every other row'..(bad and (': '..bad) or ''))
  local pitch=rects[2][2]-rects[1][2]
  check(pitch>=lines[1]:GetHeight(),label..': the row pitch '..pitch..' px is at least the row box height '..lines[1]:GetHeight()..' px')
  check(G.Inside(rects[30],box) and G.Inside(rects[60],box) and G.Inside(rects[90],box),
   label..': the last row of every column and the final row are inside the overlay')
 end
 Geometry('scale 1, locked')
 check(f.mouse==false and controls.mouse==true,'locked: the list is click-through and the control strip stays interactive')
 for _,s in ipairs({{0.5,0.5},{1.6,1.6},{3,1.6},{0.1,0.5},{1,1}}) do
  O.SetScale(s[1])
  check(O.GetScale()==s[2] and f:GetScale()==s[2] and controls:GetScale()==s[2],
   'overlay scale '..s[1]..' is applied as '..s[2]..' to the list and its control strip alike')
  Geometry('scale '..s[2])
 end
 O.ToggleLock()
 check(f.mouse==true and controls.mouse==true and not O.IsLocked(),'unlocked: the list takes the mouse to move')
 Geometry('unlocked')
 O.ToggleLock()
 check(f.mouse==false and controls.mouse==true and O.IsLocked(),'locked again: click-through, controls interactive')
 H.Advance(1.5)
 check(Shown()==before,'scale and lock changes keep every row, name and count')
 check(#H.actions==actions and #H.sent==sent,'the overlay takes no game action and sends nothing')
end
print('PASS text_overflow_policy checks='..checks..'; native pixel fit NOT TESTED')
