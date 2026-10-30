-- Owner-approved Wishlist editor usability (#173, displayed items 3, 4, 6).
--
-- Real boot, real editor, real fitting callbacks. Text widths and heights
-- come from the stated font models of tests/prototype/layout_geometry_support
-- (default face, 16 px face, 2.0 scale); they are a regression aid, not
-- native font measurement. Native fit, hit order, focus, contrast and
-- performance are NOT_RUN.
--
-- E3  The locked-slot automation caption says what the box is for without a
--     hover: what is shown names locked slots (never a bare "Auto..."), every
--     shown line fits its room, and the caption stays clear of its neighbours.
--     The box is the same separate, default-OFF autoLockEchoes switch.
-- E4  Always-visible counts and Owned text: the planned rolled copies total
--     leads the footer's first line, which fits; the catalog status column is
--     as wide as its text; a long name does not hide a plan row's copy count.
-- E6  The destination row has the editor's full content width, and the
--     Editing selector's hover says the opened Wishlist is not a claim that it
--     is assigned now.
-- Every scenario opens, reads, hovers and closes only: the saved roots,
-- assignment, Auto settings, actions and sends are unchanged, and the main
-- panel's Auto OFF label is not renamed.
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0
-- Checks are recorded and reported together at the end, so one run shows
-- every unmet requirement; a fixture that cannot be found still stops.
local failed={}
local function check(v,m) checks=checks+1;if not v then failed[#failed+1]=m end end

local LONG_UTF8='R\195\169serve '..string.rep('\195\169',6)..' Pipe||Name '..string.rep('W',24)
local LONG_ECHO='Zyzzyva R\195\169serve '..string.rep('Longer ',9)..'Pipe||Name'
local H=F.Boot(F.Database({mutate=function(db)
 db.chars[F.NAME].loadoutWishlists={[1]={slot=101,name=LONG_UTF8,
  echoes={{spellId=201172,quality=0,stacks=1}},assignmentId='assigned:1',designTargets={}}}
end}),function(h)
 h.perks.serverBuildSlots={{name='Mage Foundation Warlock Hybrid '..string.rep('\195\169',4),verified=true,
  echoes={{spellId=201172,quality=0,stacks=1}}}}
 h.perks.serverActiveSlot=1
 -- A catalog Echo with a long UTF-8 name and an escaped pipe, Uncommon.
 h.AddEcho(299001,LONG_ECHO,1,5)
end)
for _=1,40 do H.Advance(.05,.05) end

local function Plain(t) return G.Visible(t or '') end
-- Every saved root, except the search text this test types itself (the
-- existing Controller.SetSearch keeps it, as before).
local function Snapshot()
 local search=NexusDB.editorSearch;NexusDB.editorSearch=nil
 local text=F.Serialize(NexusDB);NexusDB.editorSearch=search
 return text
end
local before={db=Snapshot(),actions=#H.actions,sent=#H.sent,
 autoLock=Nexus.Store.Settings().autoLockEchoes,auto=Nexus.RecomputeStats().autoEnabled}
check(before.auto==false,'fixture: the main Auto switch starts OFF')

Nexus.WishlistEditor.Show()
local f=NexusEditorFrame
assert(f and f:IsShown(),'fixture: the Wishlist editor is open')

local function Find(list,pred) for _,c in ipairs(list or {}) do if pred(c) then return c end end end
local function Region(text) return Find(f.regions,function(r) return Plain(r:GetText())==text end) end

------------------------------------------------------------------------
-- E3: the locked-slot automation caption
------------------------------------------------------------------------
local label=f._autoLockLabel
local box=label and label.points[1] and label.points[1][2]
local locked=f._nexusLockedSlot(1).points[1][2]
local myBuilds=f._workspaceMyBuildsBtn
local plan=NexusFlexiblePlanEntry
local pickTitle=Region('Selected Echoes')
local search=NexusEditorSearch
local class=Find(f.children,function(c) local p=c.points[1]
 return c.kind=='CheckButton' and p and p[2]==search end)
check(label and type(box)=='table' and box.kind=='CheckButton' and box:GetParent()==f,
 'E3 fixture: the caption is anchored to its own check box')
check(label._nexusFullText=='Auto-manage locked Echo slots','E3: the whole caption is kept for the hover')
check(locked and myBuilds and plan and pickTitle and search and class and class.text,
 'E3 fixture: the strip, My Builds, Plan alternatives, Selected Echoes, search and class filter')
check(box:GetChecked()==false and before.autoLock==false,'E3 fixture: the separate option starts OFF')

local function Lines(text)
 local out={}
 for line in (Plain(text)..'\n'):gmatch('(.-)\n') do out[#out+1]=line end
 return out
end
local function Fit(model,n)
 G.UseFont(model)
 locked:SetText(string.format('Locked (%d/%d):',n,n))
 f._fitAutoLock(n)
 local tag='E3 '..model.name..', '..n..' slots'
 local lr,cr,mr=G.Rect(label,f),G.Rect(box,f),G.Rect(myBuilds,f)
 return tag,lr,cr,mr
end
local function Clear(a,b) return G.Apart(a,b) end
-- The harness gives every frame a 100 px box; the class filter keeps its
-- template size natively. A 32 px template box is modelled here (an
-- assumption, not a verified client size); the strip is placed from the
-- box's actual width, so the geometry checks below hold for either.
class:SetSize(32,32)

local header=Find(f.regions,function(r) return Plain(r:GetText()):find('^Choose up to 79')~=nil end)
local leftArea0=Find(f.children,function(c) return c.scripts.OnMouseWheel and c:GetWidth()==600 end)
local pickArea0=Find(f.children,function(c) return c.scripts.OnMouseWheel and c:GetWidth()==332 end)
check(header and leftArea0 and pickArea0,'E3 fixture: the header line and both lists')
-- Every supported model, the largest included: the caption is shown and
-- names locked slots, every line fits, and the box and caption overlap no
-- neighbour. The box sits after the last slot, or (when that leaves no room
-- for the caption) on its own line under the strip, with the lists and
-- their titles moved below it.
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 for _,n in ipairs({6,8}) do
  local tag,lr,cr,mr=Fit(model,n)
  check(label:IsShown(),tag..': the caption is shown')
  local shown=Plain(label:GetText())
  local words=shown:gsub('\n',' '):lower()
  check(words:find('locked',1,true) and words:find('slots',1,true),
   tag..': the shown caption names locked slots without a hover: '..shown)
  for _,line in ipairs(Lines(label:GetText())) do
   check(G.Length(line)*model.char<=label:GetWidth()+0.5,tag..': a shown line fits its room: '..line)
  end
  check(#Lines(label:GetText())*model.line<=label:GetHeight()+0.5,tag..': every shown line has height room')
  check(lr[1]>=cr[3] and lr[3]<=mr[1]-8+0.5,tag..': the caption follows its box, left of My Builds')
  check(cr[3]<=mr[1]-8+0.5 and G.Apart(cr,mr) and f._autoLockClear==true,tag..': the box is clear of My Builds')
  local neighbours={plan=plan,pickTitle=pickTitle,myBuilds=myBuilds,header=header,search=search,
   class=class,lockedCaption=locked,catalog=leftArea0,selected=pickArea0}
  for i=1,n do neighbours['slot'..i]=f._nexusLockedSlot(i) end
  for name,other in pairs(neighbours) do
   local r=G.Rect(other,f)
   check(Clear(lr,r),tag..': the caption is clear of '..name..' '..G.Text(lr)..' / '..G.Text(r))
   if name~='myBuilds' then check(Clear(cr,r),tag..': the box is clear of '..name..' '..G.Text(cr)..' / '..G.Text(r)) end
  end
  -- The strip starts after the class filter's caption.
  local tr=G.Rect(class.text,f)
  local captionRight=tr[1]+G.Length(Plain(class.text:GetText()))*model.char
  check(G.Rect(locked,f)[1]>=captionRight+6,tag..': the Locked caption starts after "Current class only"')
  -- The lists keep at least ten rows and stay inside the editor.
  local la,pa=G.Rect(leftArea0,f),G.Rect(pickArea0,f)
  check(la[4]<=f:GetHeight()-40 and leftArea0:GetHeight()>=10*24,tag..': the catalog keeps 10+ rows inside the editor')
  check(pickArea0:GetHeight()>=10*24,tag..': the Selected list keeps 10+ rows')
 end
end
G.UseFont(G.MODELS.default)
locked:SetText('Locked (0/6):');f._fitAutoLock(6)

------------------------------------------------------------------------
-- E4a: the Selected Echoes footer's planned total
------------------------------------------------------------------------
local function Footer()
 return Find(f.regions,function(r) return Plain(r:GetText()):find('Planned rolled copies: ',1,true)~=nil end)
end
local function Refresh() H.Notify();Nexus.GameAdapter.Poll();Nexus.WishlistEditor.Refresh() end
local function FooterCase(model,lockedRecords)
 G.UseFont(model)
 H.locked=H.Clone(lockedRecords);Refresh()
 local footer=Footer()
 local tag='E4 footer, '..model.name..', '..#lockedRecords..' locked records'
 check(footer and footer:IsShown(),tag..': the footer is shown')
 check(footer:GetWidth()==332 and footer:GetHeight()>=28,tag..': its box is 332 wide, at least 28 high')
 local rows=Lines(footer:GetText())
 check(rows[1]:find('^Planned rolled copies: %d+/79')~=nil,tag..': the planned total leads line 1: '..rows[1])
 for _,line in ipairs(rows) do
  check(G.Length(line)*model.char<=332,tag..': each line fits the footer width: '..line)
 end
 -- Every line is inside the footer's own height: no count is clipped or
 -- left to the hover.
 check(#rows*model.line<=footer:GetHeight()+0.5,
  tag..': all '..#rows..' lines fit the footer height '..footer:GetHeight())
 local shown=Plain(footer:GetText())
 for _,part in ipairs({'Planned rolled copies: ','Locked targets: ',' Echo/quality entries'}) do
  check(shown:find(part,1,true)~=nil,tag..': the shown footer says '..part)
 end
 if #lockedRecords>0 then
  check(shown:find('Currently locked: '..#lockedRecords..'/',1,true)~=nil,tag..': the shown footer counts the locked records')
 end
 -- It stays between the list and Save, under neither; shown rows end above it.
 local fr,lr=G.Rect(footer,f),G.Rect(pickArea0,f)
 local save=Find(f.children,function(c) return c.kind=='Button' and c._nexusPrimary==true end)
 check(lr[4]+8<=fr[2]+0.5,tag..': the list ends 8 px above the footer '..G.Text(lr)..' / '..G.Text(fr))
 check(save==nil or G.Apart(fr,G.Rect(save,f)),tag..': the footer is clear of Save')
 for _,row in ipairs(pickArea0.children) do
  if row:IsShown() then check(G.Rect(row,f)[4]<=fr[2],tag..': a shown Selected row ends above the footer') end
 end
 -- The complete hover still repeats everything when asked.
 local hit=f._pickFooterHit
 check(hit~=nil and hit:GetScript('OnEnter')~=nil,tag..': the footer keeps its full-text hover')
 return rows
end
-- The footer's caption-line move is exercised too: the largest model drops
-- the lists for the locked-slot caption, and the footer still fits.
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 FooterCase(model,{})
 FooterCase(model,{{spellId=200080,stacks=5},{spellId=200081,stacks=1}})
end
check(Footer():GetHeight()>28,'E4 footer: the largest model really needs and gets more than 28 px')
G.UseFont(G.MODELS.default)
H.locked={};Refresh()

------------------------------------------------------------------------
-- E4b: the catalog's Owned status beside a long UTF-8 name
------------------------------------------------------------------------
H.granted[LONG_ECHO]={{spellId=299001,quality=1}}
search:SetText('Zyzzyva');Refresh()
local leftArea=Find(f.children,function(c) return c.scripts.OnMouseWheel and c:GetWidth()==600 end)
local function CatalogRow()
 return leftArea and Find(leftArea.children,function(r) return r:IsShown() and r.data and r.data.spellId==299001 end)
end
check(CatalogRow()~=nil,'E4 fixture: the catalog lists the long-named Echo')
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 -- A new font model is applied by a real re-render (a search change).
 G.UseFont(model);search:SetText('');search:SetText('Zyzzyva');Refresh()
 local row=CatalogRow()
 local tag='E4 Owned, '..model.name
 local status=Plain(row.status:GetText())
 check(status=='Uncommon · Owned',tag..': the row says it is owned (calculation unchanged): '..status)
 check(G.Length(status)*model.char<=row.status:GetWidth(),tag..': the whole status fits its column')
 local tr,sr,rr=G.Rect(row.text,f),G.Rect(row.status,f),G.Rect(row,f)
 check(tr[3]<=sr[1] and G.Inside(sr,rr),tag..': the name ends before the status, inside the row')
 check(row.text:GetWidth()>=200,tag..': the name keeps most of the row')
 check(Plain(row.text:GetText()):find('Zyzzyva R\195\169serve',1,true)==1,tag..': the name text itself is unchanged')
end
G.UseFont(G.MODELS.default)
search:SetText('');Refresh()

------------------------------------------------------------------------
-- E6: room for the destination row; the Editing selector's hover
------------------------------------------------------------------------
local tip,lines=GameTooltip,nil
local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show,Hide=tip.Hide}
tip.SetOwner=function() lines={} end
tip.AddLine=function(_,t) if lines then lines[#lines+1]=Plain(t) end end
tip.Show=function() end;tip.Hide=function() end
local row=f._destinationRow
local rr=G.Rect(row,f)
check(rr[1]<=34+0.5 and rr[3]>=f:GetWidth()-34-0.5,'E6: the destination row spans the content width '..G.Text(rr))
check(row.cells and #row.cells==4,'E6: the four destination cells are the shared row\'s own')
local loadout=Find(f.children,function(c) return c.kind=='Button' and c:IsVisible() and Plain(c:GetText()):find('Saved Build: ',1,true)==1 end)
for _,cell in ipairs(row.cells) do
 local cr=G.Rect(cell,f)
 check(G.Inside(cr,rr,0.5),'E6: each cell lies inside the row')
 check(G.Apart(cr,G.Rect(loadout,f)),'E6: a cell stays clear of the selector row')
end
local switch=NexusWishlistEditorSwitchButton
local editing=Plain(switch:GetText())
check(editing:find('^Editing: ')~=nil,'E6 fixture: a saved Wishlist is open for editing: '..editing)
switch:GetScript('OnEnter')(switch)
local said=table.concat(lines or {},' ')
check(said:find('opened',1,true) and said:find('not checked',1,true),
 'E6: the Editing hover says the opened Wishlist\'s current assignment is not checked here: '..said)
check(not said:lower():find('is assigned',1,true) and not said:lower():find('in use',1,true),
 'E6: the hover does not claim a current assignment: '..said)
-- A changed backend with no refresh does not repaint the captured row.
local cellTexts={};for i,cell in ipairs(row.cells) do cellTexts[i]=cell:GetText() end
H.perks.serverActiveSlot=0
switch:GetScript('OnEnter')(switch);switch:GetScript('OnLeave')(switch)
for i,cell in ipairs(row.cells) do check(cell:GetText()==cellTexts[i],'E6: hovering reads no fresh active slot ('..i..')') end
H.perks.serverActiveSlot=1
for k,v in pairs(saved) do tip[k]=v end

------------------------------------------------------------------------
-- Opening, reading, hovering and closing changed nothing saved or sent.
------------------------------------------------------------------------
f:Hide()
check(Snapshot()==before.db,'reading the editor left every saved root unchanged')
check(#H.actions==before.actions and #H.sent==before.sent,'reading the editor acted and sent nothing')
check(Nexus.Store.Settings().autoLockEchoes==before.autoLock and Nexus.RecomputeStats().autoEnabled==before.auto,
 'reading the editor changed neither Auto setting')
-- The main panel's Auto OFF label is kept exactly (displayed item 10 is excluded).
Nexus.Panel.Show()
-- The runtime reports its state through Panel.SetAuto; the actual state
-- (AutoSelectedNow) is OFF.
check(Nexus.Panel.AutoSelectedNow()==false,'fixture: the runtime reports Auto OFF')
Nexus.Panel.SetAuto(Nexus.Panel.AutoSelectedNow())
local autoText=Plain(NexusPanel._autoBtn:GetText())
check(autoText=='Auto OFF','the main panel still says Auto OFF: '..autoText)
local function NoColon(frame)
 for _,r in ipairs(frame.regions or {}) do check(not Plain(r:GetText()):find('Auto: Off',1,true),'no Auto: Off label') end
 for _,c in ipairs(frame.children or {}) do NoColon(c) end
end
NoColon(NexusPanel);NoColon(f)

------------------------------------------------------------------------
-- E3 (control): the box is the same separate setting, on and off again.
------------------------------------------------------------------------
Nexus.WishlistEditor.Show()
local main=Nexus.Store.Settings()
box:SetChecked(true);box:GetScript('OnClick')(box)
check(main.autoLockEchoes==true,'E3: the box still turns the separate locked-slot option on')
check(Nexus.RecomputeStats().autoEnabled==false,'E3: the main Auto switch stays OFF')
box:SetChecked(false);box:GetScript('OnClick')(box)
check(main.autoLockEchoes==false,'E3: and off again')

------------------------------------------------------------------------
-- E4c: a plan row's copies beside a long name (an unsaved draft edit)
------------------------------------------------------------------------
search:SetText('Zyzzyva');Refresh()
CatalogRow():Click();Nexus.WishlistEditor.Refresh()
local pickArea=Find(f.children,function(c) return c.scripts.OnMouseWheel and c:GetWidth()==332 end)
local function PickRow()
 return Find(pickArea.children,function(r) return r:IsShown() and r.data and r.data.spellId==299001 end)
end
local pick=PickRow()
check(pick~=nil,'E4 fixture: the long-named Echo is in the plan')
pick.plus:Click();Nexus.WishlistEditor.Refresh();pick=PickRow()
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 G.UseFont(model);search:SetText('');search:SetText('Zyzzyva');Refresh();pick=PickRow()
 local tag='E4 plan row, '..model.name
 local note=pick.count and Plain(pick.count:GetText()) or ''
 check(note=='x2',tag..': the planned copies are shown on their own: '..note)
 if pick.count then
  check(G.Length(note)*model.char<=pick.count:GetWidth(),tag..': the copies fit their place')
  local tr,cr,mr=G.Rect(pick.text,f),G.Rect(pick.count,f),G.Rect(pick.minus,f)
  check(tr[3]<=cr[1] and cr[3]<=mr[1],tag..': name, then copies, then the - button')
 end
 check(Plain(pick.text:GetText())==G.Visible(LONG_ECHO),tag..': the name text is the whole name')
end
G.UseFont(G.MODELS.default)

------------------------------------------------------------------------
-- E4d: the replacement route's "(currently locked)" note
------------------------------------------------------------------------
-- Real route: an occupied lock slot's right-click plans its replacement, a
-- catalog click picks it, Refresh shows the read-only pairing row.
H.locked={{spellId=200080,stacks=1}};search:SetText('');Refresh()
local slot1=f._nexusLockedSlot(1)
check(slot1.slotState=='locked' and slot1.spellId==200080,'E4d fixture: slot 1 holds a locked Echo')
slot1:GetScript('OnClick')(slot1,'RightButton')
search:SetText('Zyzzyva');Refresh()
CatalogRow():Click();search:SetText('');Refresh()
local function GhostRow()
 return Find(pickArea.children,function(r) return r:IsShown() and r.data and r.data.ghost and r.data.spellId==200080 end)
end
check(GhostRow()~=nil,'E4d fixture: the pairing row for the replaced Echo is shown')
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 G.UseFont(model);search:SetText('x');search:SetText('');Refresh()
 local ghost=GhostRow()
 local tag='E4d replacement note, '..model.name
 if ghost and ghost.count then
  local note=Plain(ghost.count:GetText())
  check(note=='(currently locked)',tag..': the whole note is shown: '..note)
  check(G.Length(note)*model.char<=ghost.count:GetWidth(),tag..': it fits one line')
  check(G.Rows(note,ghost.count:GetWidth(),model.char)==1 and ghost.count:GetHeight()>=model.line,
   tag..': one line, with a line of height')
  local tr,cr,rr=G.Rect(ghost.text,f),G.Rect(ghost.count,f),G.Rect(ghost,f)
  check(tr[3]<=cr[1] and cr[3]<=rr[3],tag..': name, then the note, inside the row')
  check(Plain(ghost.text:GetText()):find('-> replaces ',1,true)~=nil,tag..': the pairing name stays')
  check(ghost.text:GetWidth()>=24,tag..': the name keeps room')
  for _,b in ipairs({ghost.minus,ghost.plus,ghost.remove}) do
   check(not b:IsShown(),tag..': the pairing row has no -, + or remove control')
  end
 else
  check(false,tag..': the pairing row and its note place exist')
 end
 -- A normal row keeps its copies left of its - / + / remove controls.
 local pick=PickRow()
 if pick and pick.count then
  check(G.Rect(pick.count,f)[3]<=G.Rect(pick.minus,f)[1],tag..': a normal row\'s copies stay left of -')
 end
end
G.UseFont(G.MODELS.default)

------------------------------------------------------------------------
-- E4e: adjacent rows stay apart; scrolling still reaches every entry
------------------------------------------------------------------------
-- The same replacement-route plan (normal, pairing, normal rows), plus
-- ordinary catalog picks so the Selected list is longer than its window.
local function ShownPicks()
 local t={}
 for _,r in ipairs(pickArea.children) do if r:IsShown() and r.data then t[#t+1]=r end end
 table.sort(t,function(a,b) return G.Rect(a,f)[2]<G.Rect(b,f)[2] end)
 return t
end
local function CatalogShown()
 local t={}
 for _,r in ipairs(leftArea.children) do if r:IsShown() and r.data then t[#t+1]=r end end
 table.sort(t,function(a,b) return G.Rect(a,f)[2]<G.Rect(b,f)[2] end)
 return t
end
search:SetText('');Refresh()
-- Click catalog rows not yet in the plan until the draft holds 24 entries.
local Pending=Nexus.WishlistEditor.DebugPendingCount
for _=1,20 do
 for _,r in ipairs(CatalogShown()) do
  if Pending()<24 and r.data.spellId~=200080 and not Plain(r.status:GetText()):find('Selected',1,true) then
   r:Click();Refresh()
  end
 end
 leftArea.scripts.OnMouseWheel(leftArea,-1);Refresh()
end
check(Pending()>=24,'E4e fixture: the plan holds 24 entries: '..Pending())
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 G.UseFont(model);search:SetText('x');search:SetText('');Refresh()
 local tag='E4e '..model.name
 -- Every scrolled window, from the top to the clamped end: rows lie
 -- inside the list, each part inside its own row, and adjacent rows'
 -- names, counts/notes and buttons stay apart.
 local ar=G.Rect(pickArea,f)
 local sawGhost,seen,first=false,{},nil
 local function Window(at)
  local rows=ShownPicks()
  check(#rows>=2,tag..at..': several Selected rows are shown')
  for i,r in ipairs(rows) do
   local rr=G.Rect(r,f)
   check(rr[2]>=ar[2]-0.5 and rr[4]<=ar[4]+0.5,tag..at..': row '..i..' lies inside the list '..G.Text(rr)..' / '..G.Text(ar))
   seen[r.data.ghost and ('ghost'..r.data.spellId) or tostring(r.data.draftKey)]=true
   if r.data.ghost then sawGhost=true end
   for _,part in ipairs({r.text,r.count,r.minus,r.plus,r.remove}) do
    if part and part:IsShown() then
     local pr=G.Rect(part,f)
     check(pr[2]>=rr[2]-0.5 and pr[4]<=rr[4]+0.5,tag..at..': row '..i..' part stays in its row '..G.Text(pr)..' / '..G.Text(rr))
    end
   end
   check(r.count==nil or r.count:GetHeight()>=model.line,tag..at..': row '..i..' count/note keeps a full line')
   local nxt=rows[i+1]
   if nxt then
    check(rr[4]<=G.Rect(nxt,f)[2]+0.5,tag..at..': rows '..i..' and '..(i+1)..' do not overlap')
    for _,a in ipairs({r.text,r.count,r.minus,r.plus,r.remove}) do
     for _,b in ipairs({nxt.text,nxt.count,nxt.minus,nxt.plus,nxt.remove}) do
      if a and b and a:IsShown() and b:IsShown() then
       check(G.Apart(G.Rect(a,f),G.Rect(b,f)),tag..at..': rows '..i..'/'..(i+1)..' labels and buttons stay apart '
        ..G.Text(G.Rect(a,f))..' / '..G.Text(G.Rect(b,f)))
      end
     end
    end
   end
  end
  return rows
 end
 for _=1,40 do pickArea.scripts.OnMouseWheel(pickArea,1) end;Refresh()
 first=Window(' top')[1]
 local window
 for step=1,40 do
  pickArea.scripts.OnMouseWheel(pickArea,-1);Refresh()
  window=Window(' step '..step)
 end
 check(sawGhost,tag..': the pairing row is shown and checked')
 local count=0;for _ in pairs(seen) do count=count+1 end
 -- Every draft entry once, plus the one read-only pairing row.
 local expected=Nexus.WishlistEditor.DebugPendingCount()+1
 check(expected>=18,tag..': fixture: the plan is longer than one window: '..expected)
 check(count==expected,tag..': scrolling reaches every Selected row exactly: '..count..' of '..expected)
 local pitch=G.Rect(window[1],f)[4]-G.Rect(window[1],f)[2]
 check(#window==math.floor(pickArea:GetHeight()/pitch+0.0001),tag..': the clamped last window is full: '..#window)
 check(G.Rect(window[#window],f)[4]<=ar[4]+0.5,tag..': the last row ends inside the list')
 for _=1,40 do pickArea.scripts.OnMouseWheel(pickArea,1) end;Refresh()
 local top=ShownPicks()[1]
 check(top~=nil and first~=nil and top.data==first.data,tag..': the wheel returns to the same first row')
 -- The catalog rows likewise stay apart and inside their list.
 local cat=CatalogShown();local lr=G.Rect(leftArea,f)
 for i,r in ipairs(cat) do
  local rr=G.Rect(r,f)
  check(rr[4]<=lr[4]+0.5,tag..': catalog row '..i..' ends inside its list')
  check(r.text:GetHeight()>=model.line and r.status:GetHeight()>=model.line,tag..': catalog row '..i..' name and status keep a full line')
  if cat[i+1] then check(rr[4]<=G.Rect(cat[i+1],f)[2]+0.5,tag..': catalog rows '..i..'/'..(i+1)..' do not overlap') end
 end
end
G.UseFont(G.MODELS.default)
check(#H.actions==before.actions and #H.sent==before.sent,'editing the draft acted and sent nothing')
f:Hide()

for _,m in ipairs(failed) do io.stderr:write('FAILED ',m,'\n') end
if #failed>0 then error(string.format('owner14_editor_usability: %d of %d checks failed; first: %s',#failed,checks,failed[1]),0) end
print(string.format('owner14_editor_usability: %d checks passed',checks))
