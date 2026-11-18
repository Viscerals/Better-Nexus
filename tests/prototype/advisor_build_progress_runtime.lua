-- Build Progress against the real Journal provider. On world entry the
-- lifecycle hands automation.JournalData to the Journal tab; this test captures
-- that same callback and renders what it actually writes: the Target line, the
-- Pending and extras lists and the Ratchet estimate. If that wording drifts,
-- these checks fail instead of the page quietly showing "unknown".
-- Covered: an active Saved Build whose contents are not confirmed (the extras
-- list arrives empty, shown as "none listed", never 0), a confirmed one (its
-- off-Wishlist family is listed), a Wishlist with no requested family, a
-- Wishlist whose family is owned, and every estimate form written here. Rows
-- keep one line at the row height at a narrow width: the no-wrap calls are
-- recorded, not assumed, because the harness answers unknown methods with a
-- silent no-op. Real boot, runtime, compiler, estimate and Journal tab;
-- synthetic game surface and frames. The zero-family case replaces only the
-- adapter's Wishlist read for one refresh, because the real adapter never
-- resolves a Wishlist without a family.
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local LONG='Example shadow of an Echo family whose name is far too long for one row'
H.AddEcho(410001,'Disposable A',1,4,4100)
H.AddEcho(410002,'Desired A',2,3,4101)
H.AddEcho(410004,'Desired B',3,2,4103)
H.AddEcho(410009,LONG,1,1,4107)
H.perks.serverActiveSlot=1
H.perks.serverBuildSlots={[1]={name='Active saved build',verified=false,
 echoes={{spellId=410001,quality=1,stacks=1},{spellId=410002,quality=2,stacks=1}}}}
H.granted={['Desired A']={{spellId=410002,quality=2}}}
H.Boot();local A=Nexus.GameAdapter
check(A.SetLoadoutWishlistIdentity(1,'Raid plan',{{spellId=410002,quality=2,stacks=1},
 {spellId=410004,quality=3,stacks=1},{spellId=410009,quality=1,stacks=1}}),'a Wishlist is assigned to the active Saved Build')
check(A.Wishlist(),'and resolves')

-- The lifecycle hands its own provider to the tab on an ordinary world entry.
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
local provider;local install=Nexus.JournalTab.TryInstall
Nexus.JournalTab.TryInstall=function(dataProvider,...)provider=dataProvider;return install(dataProvider,...)end
H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1,.05)
Nexus.JournalTab.TryInstall=install
check(type(provider)=='function','the lifecycle supplied the real Journal provider')
local tab=assert(NexusJournalTab,'the tab installed with it')
local page=assert(NexusJournalScroll.scrollChild,'the page has its scrolled content')
-- A narrow page: the rows are 228 px wide.
NexusJournalScroll:SetWidth(240)

-- Record the real no-wrap calls on every font string the page's frames create.
local wraps={}
local realCreateFrame=CreateFrame
CreateFrame=function(kind,name,parent,...)
 local f=realCreateFrame(kind,name,parent,...)
 if parent==page then
  local create=f.CreateFontString
  f.CreateFontString=function(self,...)
   local fs=create(self,...)
   fs.SetWordWrap=function(region,on)wraps[region]=on end
   return fs
  end
 end
 return f
end

local tip={}
GameTooltip.SetOwner=function()tip={}end
GameTooltip.AddLine=function(_,text)tip[#tip+1]=tostring(text)end
GameTooltip.SetText=function(_,text)tip[#tip+1]=tostring(text)end
local function hover(f)f.scripts.OnEnter(f);local out=table.concat(tip,'\n');f.scripts.OnLeave(f);return out end
local function plain(s)return(s:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))end
local function pageText()
 local out={}
 local function under(f)while f do if f==NexusJournalPanel then return true end f=f.parent end end
 for _,f in ipairs(H.frames)do
  if under(f) and f:IsVisible()then
   for _,r in ipairs(f.regions or {})do if r:IsShown() and type(r:GetText())=='string' then out[#out+1]=r:GetText() end end
  end
 end
 return plain(table.concat(out,'\n'))
end
local function rows()
 local out={}
 for _,f in ipairs(H.frames)do if f.parent==page and f.label and f.status and f:IsVisible()then out[#out+1]=f end end
 return out
end
local function row(label)for _,r in ipairs(rows())do if r.label:GetText()==label then return r end end end
-- The page's own button: the main panel's Play section has a Show/Hide
-- details button with the same label.
local function button(label)
 for _,b in ipairs(H.frames)do if b.kind=='Button' and b.parent==page and b:GetText()==label and b:IsVisible()then return b end end
end
local function lineOf(prefix)
 for _,r in ipairs(page.regions)do
  if r:IsShown() and type(r:GetText())=='string' and plain(r:GetText()):find(prefix,1,true)==1 then return r end
 end
end
local function hoverOver(fs)
 for _,f in ipairs(H.frames)do
  if f.parent==page and f:IsShown() and f.points[1] and f.points[1][2]==fs and f.scripts.OnEnter then return f end
 end
end
local function section(data,prefix)
 for _,s in ipairs(data.sections)do if s.title:find(prefix,1,true)==1 then return s end end
end
local NOTES_FIRST='Compares the assigned Wishlist with the active Saved Build; planned locked targets are not proof of ownership.'
-- Every estimate text the real provider can write here (logic/Ratchet.lua
-- RunsEstimate and core JournalData); true when it is an actual estimate.
local ESTIMATE_FORMS={
 {'^~%d+ wishlist echo[es]* pending; no future random roll is assumed %(rate unmeasured%)$',true},
 {'^wishlist complete %- 0 wanted echoes pending$',true},
 {'^no wishlist target %- advisor mode$',false},
 {'^estimate unavailable$',false},
 {'^no estimate %(advisor mode%)$',false},
}
-- The real estimate in a known form, and what the page shows for it.
local function estimate(data,label)
 local notes=assert(section(data,'Notes'),label..': the provider writes its Notes')
 check(#notes.lines==2 and notes.lines[1]==NOTES_FIRST,label..': Notes keep their two-line form')
 local raw,form=notes.lines[2],nil
 for _,f in ipairs(ESTIMATE_FORMS)do if raw:find(f[1])then form=f end end
 check(form,label..': the provider wrote its estimate in a known form: '..raw)
 local s=pageText()
 if form[2] then
  check(s:find('Estimate, not a prediction: '..raw..'. Based only on what is known to be missing; no future offer is assumed.',1,true),
   label..': the real estimate is shown, labelled as an estimate: '..s)
 else
  check(s:find('Estimate: unavailable.',1,true) and not s:find(raw,1,true) and not s:find('Estimate, not a prediction',1,true),
   label..': a no-target estimate is a plain unavailable estimate: '..s)
 end
 return raw
end
local TAIL=' off%-Wishlist families in the saved build$'
local before,sent=#H.actions,#H.sent

-- 1. The active Saved Build's contents are not confirmed: the provider lists
-- no extras and still writes 0 in its Target line. The page reads the real
-- line as known progress, and shows the empty list as none listed.
tab:Click();Nexus.JournalTab.Refresh()
check(NexusJournalPanel:IsVisible(),'the page opens')
local data=provider()
local target=section(data,'Target').lines[1]
check(target:find("^Wishlist 'Raid plan'") and target:find(': 3 Echo families %-%- 1 represented, 2 missing, 0'..TAIL),
 'the real Target line: '..target)
check(section(data,'Pending (2)') and #section(data,'Extra copies compared with the plan').lines==0,
 'the real Pending list and an empty extras list')
local s=pageText()
check(s:find('Still missing 2 Echo families: Desired B, '..LONG..'.',1,true),'the real line reads as known progress: '..s)
check(s:find('Represented 1 of 3   Missing 2   Off Wishlist: none listed',1,true) and not s:find('Off Wishlist 0',1,true),
 'an empty extras list is none listed, never 0')
local countsTip=hover(assert(hoverOver(assert(lineOf('Represented 1 of 3'),'the counts line')),'the counts line has a tooltip'))
check(countsTip:find("listed only when the active Saved Build's contents are confirmed",1,true)
 and countsTip:find('It does not show that there are none.',1,true),'and says why none listed is not zero: '..countsTip)
local missingEstimate=estimate(data,'missing families')
check(#rows()==2 and row('Desired B').status:GetText()=='Missing' and row(LONG),'one row per real missing family')
button('Show details'):Click()
s=pageText()
for _,wanted in ipairs({target,'Pending (2)','Extra copies compared with the plan',missingEstimate})do
 check(s:find(wanted,1,true),'the details keep the real line: '..wanted)
end
button('Hide details'):Click()

-- 2. Confirmed contents: the real off-Wishlist family and its count stay as
-- supplied, with the provider's explanation as source text.
H.perks.serverBuildSlots[1].verified=true
Nexus.JournalTab.Refresh()
data=provider()
target=section(data,'Target').lines[1]
local extras=section(data,'Extra copies compared with the plan').lines
check(target:find(': 3 Echo families %-%- 1 represented, 2 missing, 1'..TAIL) and #extras==1
 and extras[1]:find('Disposable A  (',1,true)==1,'the real extras list names the off-Wishlist family: '..tostring(extras[1]))
s=pageText()
check(s:find('Represented 1 of 3   Missing 2   Off Wishlist 1',1,true) and s:find('Off Wishlist (1)',1,true),
 'a supplied count is shown as supplied')
local off=assert(row('Disposable A'),'the off-Wishlist row shows the family name without its explanation')
check(off.status:GetText()=='Off Wishlist' and hover(off):find('Source text: '..extras[1],1,true),
 'its tooltip keeps the source text')
countsTip=hover(assert(hoverOver(assert(lineOf('Represented 1 of 3'),'the counts line')),'the counts line has a tooltip'))
check(countsTip:find('families in the active Saved Build that the assigned Wishlist does not request',1,true),
 'and the counts tooltip explains a listed count')
estimate(data,'confirmed contents')

-- 3. Rows keep one line inside their height at this narrow width.
local ROW_H=26
local list=rows()
check(#list==3 and list[1]==row('Desired B') and list[2]==row(LONG) and list[3]==off,'three rows in page order')
for i,r in ipairs(list)do
 check(r:GetHeight()==ROW_H,'row '..i..' keeps its height')
 for _,fs in ipairs({r.label,r.status})do
  check(wraps[fs]==false,'row '..i..': the no-wrap call was made on '..tostring(fs:GetText()))
  check(fs:GetHeight()==ROW_H-6,'row '..i..': one line high, inside the row')
 end
 local a,b,p=r.label.points[1],r.label.points[2],r.status.points[1]
 check(#r.label.points==2 and a[1]=='LEFT' and a[2]==r.tile and a[3]=='RIGHT'
  and b[1]=='RIGHT' and b[2]==r.status and b[3]=='LEFT','row '..i..': the name sits between the icon tile and the status')
 check(#r.status.points==1 and p[1]=='RIGHT' and p[2]==-4 and r.status:GetWidth()==78,'row '..i..': the status keeps the right edge')
 if i>1 then check(r.points[1][5]<=list[i-1].points[1][5]-ROW_H,'row '..i..' starts below the row before it') end
end
check(list[2].points[1][5]==list[1].points[1][5]-ROW_H,'rows of one list are stacked exactly one row height apart')
local long=row(LONG)
local left=long.tile.points[1][2]+long.tile:GetWidth()+long.label.points[1][4]
local right=long:GetWidth()+long.status.points[1][2]-long.status:GetWidth()+long.label.points[2][4]
check(right-left>0 and long.label:GetStringWidth()>right-left,
 'the long name is wider than its '..(right-left)..' px box: shortened on one line, not wrapped')
check(hover(long):find(LONG,1,true),'and its row tooltip has the complete name')
local heading=assert(lineOf('Off Wishlist (1)'),'the off-Wishlist heading')
check(heading.points[1][5]<=long.points[1][5]-ROW_H,'the heading below a row starts under that row, not over it')

-- 4. A Wishlist that requests no family: the real Target line and estimate
-- for zero families, an honest takeaway and a plain unavailable estimate.
local wishlist=A.Wishlist
A.Wishlist=function()return {name='Empty plan',source='designed',entries={},byFamily={},designTargets={}}end
data=provider();Nexus.JournalTab.Refresh();s=pageText()
A.Wishlist=wishlist
target=section(data,'Target').lines[1]
check(target:find(': 0 Echo families %-%- 0 represented, 0 missing, 2'..TAIL),'the real zero-family Target line: '..target)
check(s:find('This Wishlist requests no Echo families, so there is no family progress to show.',1,true),
 'zero requested families: an honest takeaway: '..s)
check(not s:find('each has at least one known copy',1,true) and not s:find('Still missing',1,true),'and no vacuous claim')
check(s:find('Represented 0 of 0   Missing 0   Off Wishlist 2',1,true) and #rows()==2,'the confirmed build\'s families are off Wishlist')
check(estimate(data,'zero families')=='no wishlist target - advisor mode','the real no-target estimate')
check(not s:lower():find('advisor',1,true),'no implementation term reaches the page')

-- 5. A Wishlist whose one family is owned: family coverage, not copy completeness.
check(A.SetLoadoutWishlistIdentity(1,'Owned plan',{{spellId=410002,quality=2,stacks=1}}),'an owned plan is assigned')
Nexus.JournalTab.Refresh();data=provider();s=pageText()
target=section(data,'Target').lines[1]
check(target:find("^Wishlist 'Owned plan'") and target:find(': 1 Echo families %-%- 1 represented, 0 missing, 1'..TAIL),
 'the real Target line: '..target)
check(s:find('No requested Echo family is missing: each has at least one known copy. That is family coverage, '
 ..'not copy completeness; requested copies may still be missing.',1,true),'the real line reads as known coverage: '..s)
estimate(data,'owned family')

check(#H.actions==before and #H.sent==sent,'reading the real provider and the page acted on nothing and sent nothing')
CreateFrame=realCreateFrame
tab:Click();check(not NexusJournalPanel:IsShown(),'the tab still closes the page')
print('PASS advisor_build_progress_runtime: real provider forms read as known progress, none listed is not 0, zero families, real estimates, one-line rows checks='..checks)
