-- Opening the Orb window preserves the unapproved draft, a valid
-- preparation and every approved or pending operation. The only change it
-- can make is the existing reconciliation of an OBSOLETE unapproved draft
-- (the assignment's contents changed and no run is running, pending or
-- owned): the in-memory target list follows the assignment and the manual
-- source counts are cleared. A prepared but unconfirmed approval keeps its
-- own scope unchanged beside it (case 4). That is recorded here exactly, and
-- it is identical to the existing /nexus orbs opener. Nothing is saved, no
-- permission appears.
--
-- Observation is test-only and non-advancing: the runtime's own locals are
-- read with debug.getupvalue before the click, without Status() (which
-- itself reconciles) and without advancing time. Real OrbRuntime/OrbAdapter
-- with the synthetic Orb service of orbs_support.lua; SYNTHETIC ids.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Ser(v,seen)
 seen=seen or {}
 if type(v)=='function' then return 'fn' end
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
 return '{'..table.concat(o,',')..'}'
end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 if NexusOrbPanel then NexusOrbPanel:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
-- Test-only: the runtime's current config/run/approval tables.
local function Up(fn,name)
 for i=1,300 do local n,v=debug.getupvalue(fn,i);if n==nil then return nil end;if n==name then return v end end
end
local function Locals(M)
 return {config=Up(M.Status,'config') or Up(M.SetLimit,'config'),run=Up(M.Status,'run'),approval=Up(M.Confirm,'approval')}
end
local function Stored() local st=Nexus.Store.State();return Ser(st and st.orbRefinement) end
local function Prefs(c) return Ser({maxOrbs=c.maxOrbs,recycle=c.recycle,excluded=c.excluded,name=c.name}) end
local function Open() Nexus.OrbPanel.Show() end
local other={{spellId=410004,quality=3,stacks=1}}

-- 1. Unchanged assignment with a manual source draft: preserved exactly.
do
 local H,M,A,O=Fresh()
 H.OrbPlan();assert(M.SetLimit(2));assert(M.SuggestSources())
 local L=Locals(M)
 check(L.config and next(L.config.sources or {})~=nil,'fixture: a manual source draft exists')
 local before,stored=Ser(L.config),Stored()
 Open()
 check(Ser(Locals(M).config)==before,'the draft (targets, sources, limit, preferences) is unchanged')
 check(Stored()==stored,'and nothing is saved')
 check(Locals(M).approval==nil,'no approval appears')
end

-- 2. Changed assignment contents, nothing approved or pending: the obsolete
-- draft is reconciled in memory exactly as the existing opener does it.
local function Obsolete(opener)
 local H,M,A,O=Fresh()
 H.OrbPlan();assert(M.SetLimit(2));assert(M.SuggestSources())
 assert(A.SetFirstLoadoutWishlistIdentity('Orb test',other))
 local L=Locals(M)
 local before={entries=Ser(L.config.entries),sources=Ser(L.config.sources),prefs=Prefs(L.config),stored=Stored()}
 opener()
 L=Locals(M)
 return before,{entries=Ser(L.config.entries),sources=Ser(L.config.sources),prefs=Prefs(L.config),stored=Stored(),
  approval=L.approval,running=L.run.running,pending=L.run.pending}
end
do
 local before,after=Obsolete(Open)
 check(after.entries:find('spellId=410004',1,true)~=nil and not after.entries:find('410002',1,true),
  'the in-memory targets follow the changed assignment: '..after.entries)
 check(before.entries:find('410002',1,true)~=nil,'fixture: before, they held the old target: '..before.entries)
 check(before.sources~='{}' and after.sources=='{}','the obsolete manual source counts are cleared (not approved ones)')
 check(after.prefs==before.prefs,'no other preference changes')
 check(after.stored==before.stored,'nothing is saved')
 check(after.approval==nil and not after.running and after.pending==nil,'no approval, run or pending operation appears')
 local _,old=Obsolete(function() SlashCmdList.NEXUS('orbs') end)
 check(old.entries==after.entries and old.sources==after.sources and old.prefs==after.prefs,
  'the existing /nexus orbs opener reconciles it identically')
end

-- 3. A valid preparation with an unchanged assignment: opening neither
-- replaces its scope nor invalidates it; Confirm behaves as without opening.
local function Prepared(open)
 local H,M,A,O=Fresh()
 H.OrbPlan();assert(M.SetLimit(2));assert(M.SetRecycle(false));assert(M.SuggestSources())
 local p=assert(M.Prepare('auto'))
 local before=Ser(Locals(M).approval)
 if open then Open() end
 local after=Ser(Locals(M).approval)
 local ok,err=M.Confirm(p.token)
 return before,after,ok,err,Ser({state=M.Status().state,limit=M.Status().limit,spent=M.Status().spent})
end
do
 local b0,a0,ok0,err0,run0=Prepared(false)
 local b1,a1,ok1,err1,run1=Prepared(true)
 check(a1==b1,'opening leaves the prepared scope unchanged')
 check(ok1==ok0 and tostring(err1)==tostring(err0),'Confirm gives the same answer as without opening: '..tostring(ok1)..' '..tostring(err1))
 check(run1==run0,'and the same run: '..run1)
 check(ok0,'fixture: the prepared token is valid: '..tostring(err0))
end

-- 4. The assignment changes after Prepare: the obsolete token cannot approve
-- the new target, with or without opening the window.
local function Stale(open)
 local H,M,A,O=Fresh()
 H.OrbPlan();assert(M.SetLimit(2));assert(M.SuggestSources())
 local p=assert(M.Prepare('auto'))
 assert(A.SetFirstLoadoutWishlistIdentity('Orb test',other))
 local L=Locals(M)
 local before={approval=Ser(L.approval),entries=Ser(L.config.entries),sources=Ser(L.config.sources),stored=Stored()}
 if open then open() end
 L=Locals(M)
 local after={approval=Ser(L.approval),entries=Ser(L.config.entries),sources=Ser(L.config.sources),stored=Stored()}
 local ok,err=M.Confirm(p.token)
 return ok,tostring(err),H.Count('orb-spend'),before,after
end
do
 local ok0,err0,spend0=Stale(nil)
 local ok1,err1,spend1,before,after=Stale(Open)
 -- The prepared approval keeps its own scope (binding, targets, sources,
 -- limit) byte for byte. The unapproved draft beside it is an obsolete draft
 -- (a preparation sets no run token), so it is reconciled as in case 2.
 check(after.approval==before.approval and before.approval:find('410002',1,true)~=nil,
  'opening leaves the prepared approval and its old-target scope unchanged')
 check(after.entries:find('410004',1,true)~=nil and before.sources~='{}' and after.sources=='{}',
  'the obsolete unapproved draft follows the assignment, as in case 2: '..after.entries)
 check(after.stored==before.stored,'nothing is saved')
 local _,_,_,_,old=Stale(function() SlashCmdList.NEXUS('orbs') end)
 check(old.approval==after.approval and old.entries==after.entries and old.sources==after.sources,
  'the existing /nexus orbs opener does the same')
 check(not ok0,'fixture: the obsolete token is refused without opening: '..err0)
 check(not ok1 and err1==err0,'opening does not make it valid: '..err1)
 check(spend0==0 and spend1==0,'and nothing is spent')
end

-- 5. Active, paused (owned) and restored operations: opening preserves the
-- approved targets, sources, limit, exclusions, ownership and receipt.
local function Keep(label,setup)
 local H,M,A,O=Fresh()
 setup(H,M,A,O)
 local L=Locals(M)
 local function Snap()
  local r=L.run
  return Ser({limit=r.limit,spent=r.spent,reserved=r.reserved,state=r.state,running=r.running,
   pending=r.pending,binding=r.binding,token=r.token and true or false,
   excluded=L.config.excluded,entries=L.config.entries,sources=L.config.sources,owned=A.Orbs and A.Orbs.IsOwned()})
 end
 local before,stored=Snap(),Stored()
 Open()
 L=Locals(M)
 check(Snap()==before,label..': the operation is unchanged by opening the window')
 check(Stored()==stored,label..': the saved receipt and preferences are unchanged')
end
Keep('active run',function(H,M) H.OrbPlan();H.Approve(2);H.Offer() end)
Keep('paused run',function(H,M) H.OrbPlan();H.Approve(2);M.Pause() end)
-- The assignment changes while the approved run is paused: its approved
-- targets and sources are not replaced by the new assignment.
Keep('paused run, assignment changed',function(H,M,A)
 H.OrbPlan();H.Approve(2);M.Pause()
 assert(A.SetFirstLoadoutWishlistIdentity('Orb test',other))
end)
Keep('restored receipt',function(H,M,A,O)
 H.OrbPlan();H.Approve(2);H.Offer()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 H.M=Nexus.OrbRuntime
end)

print('PASS orb_draft_approval_preserved checks='..checks)
