-- Shared synthetic fixture for the progress-refresh regressions
-- (echo_snapshot_rejected_field, fallback_static_invalidation).
--
-- Real TOC boot through format5_support (real GameAdapter, AutomationRuntime,
-- MainViewModel, Panel, overlay). Harness Echo ids only; no player data.
-- Level 80, ordinary Automation OFF. Two Saved Builds hold two finished runs:
--   GA: 79 rolled copies, 40 of them on the ordinary Wishlist W
--   GB: 79 rolled copies, 35 of them on W
-- so the HUD reads 40/79 for GA and 35/79 for GB against W.
local F=dofile('tests/prototype/format5_support.lua')
local S={F=F}

function S.Q(id) return (id-200000)%4 end -- harness.lua: quality of Echo i is i%4

function S.Copy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local t={};seen[v]=t
 for k,c in pairs(v) do t[S.Copy(k,seen)]=S.Copy(c,seen) end
 return t
end

-- spec: array of {id, copies, locked}; locked=nil omits the role field.
function S.Rows(spec)
 local rows={}
 for i,s in ipairs(spec) do
  rows[i]={spellId=s[1],quality=S.Q(s[1]),stacks=s[2] or 1}
  if s[3]~=nil then rows[i].locked=s[3] end
 end
 return rows
end
function S.Ordinary(first,last)
 local spec={} for i=first,last do spec[#spec+1]={200000+i,1,false} end
 return spec
end

-- counts {[id]=copies} -> the client's granted mirror (name-keyed, one entry per copy)
function S.Granted(counts)
 local g={}
 for id,n in pairs(counts) do
  local list={}
  for k=1,n do list[k]={spellId=id,quality=S.Q(id)} end
  g['Echo '..(id-200000)]=list
 end
 return g
end
function S.SlotRows(counts)
 local ids={} for id in pairs(counts) do ids[#ids+1]=id end
 table.sort(ids)
 local rows={}
 for i,id in ipairs(ids) do rows[i]={spellId=id,quality=S.Q(id),stacks=counts[id]} end
 return rows
end
function S.Association(slot,name,rows)
 return {slot=slot,key=F.Key(rows),name=name,echoes=S.Copy(rows)}
end

S.GA,S.GB={},{}
for i=1,40 do S.GA[200000+i]=1 end
for i=80,85 do S.GA[200000+i]=4 end
for i=86,90 do S.GA[200000+i]=3 end
for i=1,35 do S.GB[200000+i]=1 end
for i=80,90 do S.GB[200000+i]=4 end

-- o: granted, slots, active, associations, locked, before(h)
function S.Boot(o)
 local db=F.Database({mutate=function(d)
  local row=d.chars[F.NAME]
  row.loadoutWishlists=S.Copy(o.associations)
  row.lockDesignTargetsBySlot=nil
  row.recordedPicks=nil
 end})
 local H=F.Boot(db,function(h)
  h.playerLevel=80
  h.granted=S.Granted(o.granted)
  h.locked=S.Copy(o.locked or {})
  h.perks.serverBuildSlots=S.Copy(o.slots)
  h.perks.serverActiveSlot=o.active
  if o.before then o.before(h) end
 end)
 assert(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 H.Advance(3)
 return H
end

function S.Hud()
 local m=Nexus.Panel and Nexus.Panel._lastModel
 local pr=m and type(m.progress)=='table' and m.progress or {}
 return {owned=tonumber(pr.owned),total=tonumber(pr.total),missing=pr.missing or {},
  toLock=pr.toLock or {},name=pr.wishlistName,lockedOwned=pr.lockedOwned,lockedTotal=pr.lockedTotal}
end
function S.Text(h) return tostring(h.name)..' '..tostring(h.owned)..'/'..tostring(h.total) end
function S.Has(list,needle)
 for _,v in ipairs(list or {}) do if tostring(v):find(needle,1,true) then return true end end
 return false
end

-- The ordinary have of the given Wishlist rows through the adapter's own
-- ownership getter, read now (the fresh value the HUD is expected to show).
function S.GetterHave(rows)
 local owned=Nexus.GameAdapter.Owned()
 return Nexus.Model.WishlistEntryProgress(S.Copy(rows),owned,nil).ordinaryHave
end

-- Overlay rows that read complete ([X]).
function S.OverlayComplete()
 local f=_G.NexusOverlay
 if not f then return -1 end
 local n=0
 for _,r in ipairs(f.regions or {}) do
  if r.shown and type(r.text)=='string' and r.text:find('[X]',1,true) then n=n+1 end
 end
 return n
end

-- Advance in 0.05 s steps until pred() holds or `limit` seconds pass.
-- Returns the elapsed seconds at the first hold, or nil.
function S.Within(H,limit,pred)
 local start=H.now
 if pred() then return 0 end
 while H.now-start<limit-1e-9 do
  H.Advance(.05,.05)
  if pred() then return H.now-start end
 end
 return nil
end

function S.Work()
 local r=Nexus.RecomputeStats()
 local e=Nexus.GameAdapter.EchoReconcileStats()
 return {steps=r.fullSteps or 0,repairs=r.fallbackRepairs or 0,static=r.staticProbes or 0,
  scans=e.scans or 0,failures=e.failures or 0,generations=S.Copy(e.generations or {})}
end

-- Counting wrapper around the Journal association refresh (the Journal frames
-- do not exist in the harness; only the call is observed).
function S.CountJournalRefreshes()
 local J=Nexus.JournalTab
 local real=J.RefreshAssociations
 local box={n=0}
 J.RefreshAssociations=function() box.n=box.n+1 end
 function box.restore() J.RefreshAssociations=real end
 return box
end

-- A check that records every failure and keeps going, so a red run reports
-- each stale assertion; Finish raises once at the end.
function S.Checker(name)
 local c={n=0,failed={}}
 function c.check(v,msg)
  c.n=c.n+1
  if not v then c.failed[#c.failed+1]=msg;print('FAIL '..tostring(msg)) end
  return v
 end
 function c.finish(summary)
  if #c.failed>0 then
   error(name..': '..#c.failed..' of '..c.n..' checks failed; first: '..tostring(c.failed[1]),0)
  end
  print('PASS '..name..': '..summary..' checks='..c.n)
 end
 return c
end

return S
