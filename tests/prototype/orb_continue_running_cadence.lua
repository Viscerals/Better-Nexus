-- Issue #172: after an explicit Continue, a newly approved Orb run that is
-- running with nothing pending is pumped at the ordinary active cadence, not
-- the 5-second late-observation cadence. The intended slow cadences stay: an
-- idle observer after Continue with no run, and a restored receipt after its
-- fast window. Limits, no-overlap, explicit approval and the unknown-state
-- refusal are unchanged, and the late recorder saves nothing on idle frames.
-- Real Store/OrbRuntime/OrbAdapter/GameAdapter over the synthetic harness
-- (orb_recovery_support). Time advances only through H.Advance, which drives
-- the real observer frame's OnUpdate; the synthetic game answers a spend with
-- an offer and a choice with a result after LAT seconds and never pumps.
-- Setup follows the #172 diagnostic probe. Synthetic timing only.
local failures={}
local function Case(name,fn)
 local ok,err=pcall(fn)
 print((ok and 'CASE PASS ' or 'CASE FAIL ')..name..(ok and '' or (': '..tostring(err))))
 if not ok then failures[#failures+1]=name end
end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local LAT,DT=0.3,0.05
local FAST=LAT+0.5 -- result -> next spend at the ordinary cadence, with slack

local function World(continued)
 local w={spends={},results={},queue={},pumps=0}
 local H,M,A,O=S.Fresh()
 if continued then
  S.SpendOfferNoChoice(H,M,A,O)
  M=S.Reload(H)
  H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
  R.Server(H);S.Pass(H,M,A,2)
  assert(M.ContinueView().eligible==true,'setup: the restored receipt is Continue-eligible')
  assert(M.ContinueBegin())
  local waited=0
  while M.ContinueView().stage~='ready' and waited<20 do H.Advance(.25);waited=waited+.25 end
  local ok,how=M.ContinueConfirm(M.ContinueView().token)
  assert(ok==true and how=='archived','setup: explicit Continue archived: '..tostring(how))
 else
  S.Loadouts(H,A)
 end
 -- A three-copy target and three surplus sources.
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=3}}))
 H.granted=H.Clone(H.granted)
 H.granted['Disposable A']={{spellId=410001,quality=1},{spellId=410001,quality=1}}
 H.Notify();A.Poll()
 w.H,w.M,w.A,w.O=H,M,A,O
 -- The synthetic game: answers later, never pumps.
 local svc=ProjectEbonhold.OrbService;local spend=svc.ConfirmSpend
 svc.ConfirmSpend=function(...)
  local r={spend(...)};w.spends[#w.spends+1]=H.now
  w.queue[#w.queue+1]={at=H.now+LAT,kind='offer'};return unpack(r)
 end
 local select=H.service.SelectPerk
 H.service.SelectPerk=function(id,...)
  local ok=select(id,...)
  if ok then w.queue[#w.queue+1]={at=H.now+LAT,kind='result',id=id} end
  return ok
 end
 -- Counts pumps (the original runs unchanged); the frame calls M.Pump.
 local pump=M.Pump
 M.Pump=function(...) w.pumps=w.pumps+1;return pump(...) end
 function w.Tick(seconds)
  for _=1,math.floor(seconds/DT+.5) do
   for i=#w.queue,1,-1 do
    local q=w.queue[i]
    if q.at<=H.now+1e-9 then
     table.remove(w.queue,i)
     if q.kind=='offer' then
      O.charges=O.charges-1;O.offer=true
      H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
     else
      local source=O.source;local g=H.Clone(H.granted);local removed=false
      for _,entries in pairs(g) do for k=#entries,1,-1 do
       if not removed and entries[k].spellId==source then table.remove(entries,k);removed=true end
      end end
      assert(removed,'the synthetic game removes one actual source')
      g[H.names[q.id]]=g[H.names[q.id]] or {};table.insert(g[H.names[q.id]],{spellId=q.id,quality=2})
      H.granted=g;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
      H.Notify();A.Poll()
      w.results[#w.results+1]=H.now
     end
    end
   end
   H.Advance(DT)
  end
 end
 function w.Start(limit) return M.Start(limit,false,M.Status().historyReview) end
 function w.Gaps()
  local gaps={}
  for k=1,#w.spends-1 do
   assert(w.results[k] and w.results[k]<=w.spends[k+1],'no spend before the previous result')
   gaps[#gaps+1]=w.spends[k+1]-w.results[k]
  end
  return gaps
 end
 return w
end

local function ActiveRun(continued)
 local w=World(continued)
 assert(w.Start(3),'an explicitly approved Start is accepted')
 assert(w.Start(3)==nil,'a second Start while the run owns the action is refused')
 w.Tick(40)
 assert(#w.spends==3,'three actions, never more than the approved 3: '..#w.spends)
 assert(w.M.CompactStatus().state=='COMPLETE','the run completed: '..tostring(w.M.CompactStatus().state))
 local gaps=w.Gaps();local shown={}
 for k,g in ipairs(gaps) do shown[k]=string.format('%.2f',g) end
 print('GAPS '..(continued and 'continued' or 'ordinary')..' '..table.concat(shown,' '))
 for k,g in ipairs(gaps) do
  assert(g<=FAST,string.format('result %d -> next spend took %.2f s (fast bound %.2f s)',k,g,FAST))
 end
 return w
end

Case('ordinary run keeps the active cadence (control)',function() ActiveRun(false) end)
Case('after an explicit Continue, a new running run keeps the active cadence',function() ActiveRun(true) end)

Case('after Continue, the approved limit still stops the run',function()
 local w=World(true)
 assert(w.Start(2));w.Tick(30)
 assert(#w.spends==2,'exactly the approved 2: '..#w.spends)
 for _,g in ipairs(w.Gaps()) do assert(g<=FAST,'fast between the two') end
end)

Case('after Continue with no run, the observer stays slow',function()
 local w=World(true)
 w.pumps=0;w.Tick(30)
 assert(#w.spends==0,'nothing spent')
 assert(w.pumps<=8,'idle late observation stays at the 5 s cadence: '..w.pumps..' pumps in 30 s')
end)

Case('a restored receipt slows after its fast window',function()
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O);M=S.Reload(H)
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 R.Server(H);S.Pass(H,M,A,.5)
 local n=0;local pump=M.Pump;M.Pump=function(...) n=n+1;return pump(...) end
 H.Advance(70);n=0;H.Advance(20)
 assert(n<=6,'passive restored observation is slow after its window: '..n..' pumps in 20 s')
end)

Case('unknown Orb state still refuses Start',function()
 local w=World(true);w.O.known=false
 local ok=w.Start(3);w.Tick(5)
 assert(ok==nil and #w.spends==0,'refused, nothing spent')
end)

-- The late recorder is now visited at the active cadence during such a run.
-- It writes the archive entry only when it has a new fact, never per frame.
local function Serialize(v,seen)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 seen=seen or {};if seen[v] then return 'cycle' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen) end
 seen[v]=nil;return '{'..table.concat(out,',')..'}'
end
local function Archives()
 local parts={}
 for key,row in pairs(type(NexusDB)=='table' and NexusDB.chars or {}) do
  if type(row)=='table' and row.orbRecoveryArchive~=nil then parts[#parts+1]=tostring(key)..Serialize(row.orbRecoveryArchive) end
 end
 table.sort(parts);return table.concat(parts,'|')
end
Case('the late recorder writes the archive only on new facts',function()
 local w=World(true)
 local archived=Archives()
 assert(archived~='','setup: the Continue archive entry is saved')
 assert(w.Start(3))
 local changes,frames,last,pumps=0,0,archived,w.pumps
 for _=1,math.floor(40/DT+.5) do
  if not w.M.CompactStatus().running then break end
  w.Tick(DT);frames=frames+1
  local now=Archives();if now~=last then changes=changes+1;last=now end
 end
 assert(#w.spends==3 and not w.M.CompactStatus().running,'setup: the run completed')
 -- While the run is active: a pump every four 0.05 s frames at the ordinary
 -- 0.2 s cadence, one per hundred frames at the 5 s cadence.
 local active=w.pumps-pumps
 assert(active*4>=frames*0.8,'the observer pumped at the active cadence: '..active..' pumps in '..frames..' active frames')
 assert(changes<=#w.spends+1,'archive writes follow facts, not frames: '..changes..' changes in '..frames..' frames')
end)

assert(#failures==0,'failed cases: '..table.concat(failures,', '))
print('PASS Orb runs keep the active cadence after Continue; idle observation stays slow')
