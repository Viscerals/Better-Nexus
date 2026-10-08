-- Leaderboard detail layout. Natively the Copy/Open refusal of a record
-- without an established owner and catalog build was cut in its single
-- 305x18 line under the Echo grid. The detail now has a fixed heading, a
-- measured scrolled body (record, description, locked and exact Echoes) and,
-- at the bottom, the wrapped status text above the Copy and Open actions.
-- A status longer than its cap keeps its complete text in a tooltip.
--
-- Real TOC boot, catalog, DpsCapture, projections and the Leaderboard
-- window; synthetic data only. The Sync roles-request functions are counting
-- stubs (the transport is covered by sync_locked_roles_request), so every
-- request state is shown without sending. Copy/Open availability is read,
-- never changed. Geometry and text fit use the offline font models of
-- tests/prototype/layout_geometry_support.lua; native pixel fit is NOT TESTED.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local HISTORICAL='historical locked evidence is not current copy authority'
local VAL='Valentin\195\169'
local WIDE=string.rep('W',40)..string.rep('M',40)
local parts={}
for i=1,40 do
 parts[#parts+1]=(i%5==0 and '\n' or '')..'Step '..i..': keep caf\195\169 uptime, then rotate the opener.'
end
local PARA=(table.concat(parts,' ')..' '..string.rep('end ',500)):sub(1,2000)

local fx=L.New({players={
 {name=VAL,class='MAGE',variant=1,ordinary=79,locked=6,dps={dummy=61000},title=WIDE}, -- roles unknown
 {name='Twin',class='PRIEST',variant=2,dps={dummy=52000},locked=2},                   -- roles known
 {name='Cirri',class='MAGE',variant=3,ordinary=79,locked=6,dps={dummy=43000},build='missing'}, -- no catalog build
}})
local function Player(name) for _,p in ipairs(fx.players) do if p.name==name then return p end end end
local val,twin,cirri=Player(VAL),Player('Twin'),Player('Cirri')
local db=F.Database({version=2})
fx:Install(db)
do
 local b=db.communityBuilds[val.buildId]
 b.lockedEchoes,b.lockedEvidenceKey,b.lockedAuthorityProven=nil,nil,nil
 b.description=PARA
end
local H=F.Boot(db,function(h) h.playerLevel=60 end)
for _=1,400 do H.Advance(.05,.05) end

local S=Nexus.Sync
local calls,script={},{}
S.RequestLockedRoles=function(id) calls[#calls+1]=id;return script.request(id) end
S.LockedRolesRequestStatus=function(id) return script.status(id) end
script.request=function() return true,'pending' end
script.status=function() return nil end

local catalogBefore=F.Serialize(NexusDB.authorityBundle)
local actionsBefore=#H.actions
L.Open(H,'dummy')
local rows=L.RenderedRows(H)
local byOwner={}
for i,r in ipairs(rows) do byOwner[r.data.ownerKey]={index=i,row=r} end
local function Select(p) return L.Select(H,assert(byOwner[p.owner],'row of '..p.owner).index) end
local frame=NexusLeaderboardFrame
local d=frame._leaderboardDetail

local function Verify(label,expect)
 local m=G.model
 local window={0,0,frame:GetWidth(),frame:GetHeight()}
 local panel=G.Rect(d,frame)
 check(G.Inside(panel,window),label..': the detail '..G.Text(panel)..' is inside the window')
 local title,owner=G.Rect(d.title,frame),G.Rect(d.owner,frame)
 check(G.Inside(title,panel) and G.Inside(owner,panel) and G.Apart(title,owner),label..': heading lines inside the detail and apart')
 check(d.title:GetHeight()>=m.line and d.owner:GetHeight()>=m.line,label..': each heading line holds a full line')
 -- Footer: the status wraps in full (or is capped with its tooltip) above
 -- the two actions; nothing overlaps.
 local more,copy,open=G.Rect(d.more,frame),G.Rect(d.copy,frame),G.Rect(d.open,frame)
 local view=G.Rect(d.bodyScroll,frame)
 for name,r in pairs({status=more,copy=copy,open=open,body=view}) do
  check(G.Inside(r,panel),label..': '..name..' '..G.Text(r)..' inside the detail '..G.Text(panel))
 end
 check(G.Apart(more,copy) and G.Apart(more,open) and G.Apart(copy,open),label..': status, Copy and Open do not overlap')
 check(more[4]<=copy[2] and view[4]<=more[2] and view[2]>=owner[4],label..': heading, body, status and actions are stacked in order')
 for _,b in ipairs({d.copy,d.open}) do
  check(b:GetWidth()>=G.Length(G.Visible(b:GetText()))*m.char+12,label..': "'..b:GetText()..'" fits its button')
 end
 local text=d.more:GetText()
 check(text==expect.status,label..': the status widget holds the complete text: '..tostring(text))
 local rows=G.Rows(text,d.more:GetWidth(),m.char)
 if d.moreHit.capped then
  check(expect.capped,label..': only an over-long status is capped')
  local lines
  local tip=GameTooltip
  local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show}
  tip.SetOwner=function() lines={} end
  tip.AddLine=function(_,t) lines[#lines+1]=tostring(t) end
  tip.Show=function() end
  d.moreHit:GetScript('OnEnter')(d.moreHit)
  for k,v in pairs(saved) do tip[k]=v end
  check(lines and lines[1]==text,label..': the capped status is complete in its tooltip')
  check(d.more:GetHeight()>=3*m.line,label..': a capped status still shows several lines')
 else
  check(not expect.capped,label..': the status is not capped')
  check(d.more:GetHeight()>=rows*m.line,label..': all '..rows..' status lines are shown ('..d.more:GetHeight()..' px)')
 end
 -- Body: a readable viewport; every element inside the body and apart;
 -- every text as tall as its lines; the last Echo row reachable.
 check(view[4]-view[2]>=3*m.line,label..': the scrolled body shows at least three lines ('..(view[4]-view[2])..' px)')
 local body=d.body
 check(body:GetWidth()<=view[3]-view[1],label..': the body is no wider than its viewport')
 d.bodyScroll:SetVerticalScroll(0)
 local top=G.Rect(body,frame)
 local items,last={},nil
 for _,r in ipairs(G.Shown(body)) do
  if r:GetParent()==body then
   local rr=G.Rect(r,frame)
   local rel={rr[1]-top[1],rr[2]-top[2],rr[3]-top[1],rr[4]-top[2]}
   check(rel[1]>=0 and rel[2]>=0 and rel[3]<=body:GetWidth()+0.5 and rel[4]<=body:GetHeight()+0.5,
    label..': body element '..r.kind..' '..G.Text(rel)..' inside the body '..body:GetWidth()..'x'..body:GetHeight())
   if r.kind=='FontString' then
    local n=G.Rows(r:GetText(),r:GetWidth(),m.char)
    check(r:GetHeight()>=n*m.line,label..': "'..G.Visible(r:GetText()):sub(1,20)..'" keeps all '..n..' lines')
   end
   items[#items+1]={r,rel}
   if not last or rel[4]>last[2][4] then last={r,rel} end
  end
 end
 for i=1,#items do for j=i+1,#items do
  check(G.Apart(items[i][2],items[j][2]),label..': body elements '..items[i][1].kind..' '..G.Text(items[i][2])..' and '..items[j][1].kind..' '..G.Text(items[j][2])..' do not overlap')
 end end
 local icons=0
 for _,b in ipairs(d.icons) do if b:IsShown() then icons=icons+1 end end
 check(icons==expect.icons,label..': all '..expect.icons..' exact-loadout Echoes are shown ('..icons..')')
 local range=math.max(0,body:GetHeight()-(view[4]-view[2]))
 d.bodyScroll:SetVerticalScroll(range)
 local lr=G.Rect(last[1],frame)
 check(lr[2]>=view[2]-0.5 and lr[4]<=view[4]+0.5,label..': the last body element '..G.Text(lr)..' is reachable inside the viewport '..G.Text(view))
 d.bodyScroll:SetVerticalScroll(0)
 print('LEADERBOARD_DETAIL_LAYOUT',label,'status',G.Text(more),'capped',tostring(d.moreHit.capped),'view',G.Text(view),'content',body:GetHeight())
end

-- The client's GameFont objects carry the Leaderboard; the Nexus font scale
-- does not apply, so the models are the default face and a wider, taller
-- replacement face at the same size.
for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
 G.UseFont(m)
 local name=m.name
 -- 1. The natively truncated case: no established owner, no catalog build.
 local det=Select(cirri)
 check(det.copyReason and det.openReason and not det.copyEnabled and not det.openEnabled,
  name..': fixture: Copy and Open are both refused: '..tostring(det.copyReason)..' / '..tostring(det.openReason))
 Verify(name..' / Copy and Open refused',{status='Copy unavailable: '..det.copyReason..'; Open unavailable: '..det.openReason,icons=79})
 -- 2. Roles never received: each state of the deliberate request.
 script.status=function() return nil end
 det=Select(val)
 check(det.copyReason==HISTORICAL and det.copyButton:GetText()=='Request full build','fixture: roles not received')
 Verify(name..' / roles not received',{status=det.more,icons=79})
 check(det.more:find('were not received',1,true),'the not-received text')
 det.copyButton:Click()
 Verify(name..' / request pending',{status=L.Detail().more,icons=79})
 check(L.Detail().more:find(VAL,1,true),'the pending text names the owner')
 script.status=function() return 'timeout','no reply with the locked Echo roles arrived' end
 for _=1,30 do H.Advance(.05,.05) end
 Verify(name..' / request timed out',{status=L.Detail().more,icons=79})
 check(L.Detail().more:find('You can request again',1,true),'the whole timeout text')
 script.request=function() return false,'refused','the build owner is not verified' end
 L.Detail().copyButton:Click()
 Verify(name..' / request refused',{status='Request not sent: the build owner is not verified.',icons=79})
 -- Boundary: a status beyond the cap keeps its whole text reachable.
 local long='Sync refused the request: '..string.rep('the realm channel reported a long reason ',30)
 script.request=function() return false,'refused',long end
 L.Detail().copyButton:Click()
 Verify(name..' / over-long status',{status='Request not sent: '..long..'.',icons=79,capped=true})
 script.request=function() return true,'pending' end
 script.status=function() return nil end
 -- 3. Known roles: Copy and Open available, a short status.
 det=Select(twin)
 check(det.copyEnabled and det.openEnabled,'fixture: known roles, both actions available')
 Verify(name..' / available',{status=det.more,icons=#twin.dpsOrdinary})
end

-- 4. The empty state keeps its whole explanation.
do
 G.UseFont(G.MODELS.px16)
 Nexus.Leaderboard.SetClassFilter('WARRIOR')
 for _=1,200 do H.Advance(.05,.05) end
 L.Open(H,'combined')
 local e=d.empty
 check(e:IsShown() and not d.bodyScroll:IsShown(),'the empty state replaces the detail body')
 local n=G.Rows(e:GetText(),e:GetWidth(),G.model.char)
 check(e:GetHeight()>=n*G.model.line,'the empty-state text keeps all '..n..' lines ('..e:GetHeight()..' px)')
 check(G.Inside(G.Rect(e,frame),G.Rect(d,frame)),'the empty-state text is inside the detail')
 Nexus.Leaderboard.SetClassFilter('ALL')
end

-- 5. The 980 px window on a 5:4 UI (960 px wide at scale 1) is scaled to
-- fit with its close button on screen; on a wide UI it keeps scale 1.
do
 local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 Nexus.Leaderboard.Hide()
 UIParent:SetSize(960,768);Nexus.Leaderboard.Show('dummy')
 local s=frame:GetScale()
 check(s<1 and frame:GetWidth()*s<=960-24+0.01 and frame:GetHeight()*s<=768,'a 960 px UI scales the window to fit: '..s)
 Nexus.Leaderboard.Hide()
 UIParent:SetSize(1366,768);Nexus.Leaderboard.Show('dummy')
 check(frame:GetScale()==1,'a 1366 px UI keeps scale 1')
 UIParent:SetSize(w,h)
end

-- 6. Display only: the clicks above were the only roles requests, and no
-- data changed and no game action ran.
check(#calls==6,'one roles request per deliberate click (three per model): '..#calls)
for _,id in ipairs(calls) do check(id==val.buildId,'each request names the exact build') end
check(F.Serialize(NexusDB.authorityBundle)==catalogBefore,'catalog and DPS data unchanged')
check(#H.actions==actionsBefore,'no game action')
Nexus.Leaderboard.Hide()
print('PASS leaderboard_detail_layout checks='..checks..'; native pixel fit NOT TESTED')
