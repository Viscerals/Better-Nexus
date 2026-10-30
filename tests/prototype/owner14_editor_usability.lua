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

for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
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
  check(lr[1]>=cr[3] and lr[3]<=mr[1]-8+0.5,tag..': between its box and My Builds')
  check(cr[3]<=mr[1]-8+0.5 and f._autoLockClear==true,tag..': the box ends 8 px left of My Builds')
  check(cr[1]>=G.Rect(f._nexusLockedSlot(n),f)[3]+6-0.5,tag..': the box stays 6 px right of the last slot')
  for name,other in pairs({plan=plan,pickTitle=pickTitle,myBuilds=myBuilds}) do
   check(Clear(lr,G.Rect(other,f)),tag..': clear of '..name)
  end
  -- The strip starts after the class filter's caption.
  local tr=G.Rect(class.text,f)
  local captionRight=tr[1]+G.Length(Plain(class.text:GetText()))*model.char
  check(G.Rect(locked,f)[1]>=captionRight+6,tag..': the Locked caption starts after "Current class only"')
 end
end
-- The largest scale: never a bare, ambiguous "Auto..." caption.
for _,n in ipairs({6,8}) do
 local tag=Fit(G.MODELS.double,n)
 local words=Plain(label:GetText()):gsub('\n',' '):lower()
 check(not label:IsShown() or (words:find('locked',1,true) and words:find('slot',1,true)),
  tag..': a shown caption still names locked slots: '..words)
 check(f._autoLockClear==true,tag..': the box stays clear of My Builds')
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
 check(footer:GetWidth()==332 and footer:GetHeight()==28,tag..': its box stays 332x28')
 local text=Plain(footer:GetText())
 local rows=Lines(footer:GetText())
 check(rows[1]:find('^Planned rolled copies: %d+/79')~=nil,tag..': the planned total leads line 1: '..rows[1])
 local fitsInBox=math.floor((28+0.5)/model.line)
 check(fitsInBox>=1,tag..': line 1 has height room in the box')
 for _,line in ipairs(rows) do
  check(G.Length(line)*model.char<=332,tag..': each line fits the footer width: '..line)
 end
 -- Every count is still said, on a shown line or on the footer's hover.
 local full=Plain(footer._nexusFullText or footer:GetText())
 for _,part in ipairs({'Planned rolled copies: ','Locked targets: ',' Echo/quality entries'}) do
  check(full:find(part,1,true)~=nil,tag..': still says '..part)
 end
 if #lockedRecords>0 then
  check(full:find('Currently locked: '..#lockedRecords..'/',1,true)~=nil,tag..': still counts the locked records')
 end
 if #rows>fitsInBox then
  check(footer._nexusFullText~=nil,tag..': lines beyond the box are on its hover')
 end
 return rows
end
for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
 FooterCase(model,{})
 FooterCase(model,{{spellId=200080,stacks=5},{spellId=200081,stacks=1}})
end
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
check(#H.actions==before.actions and #H.sent==before.sent,'editing the draft acted and sent nothing')
f:Hide()

for _,m in ipairs(failed) do io.stderr:write('FAILED ',m,'\n') end
if #failed>0 then error(string.format('owner14_editor_usability: %d of %d checks failed; first: %s',#failed,checks,failed[1]),0) end
print(string.format('owner14_editor_usability: %d checks passed',checks))
