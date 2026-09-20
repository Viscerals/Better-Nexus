-- Maintained pure-policy adapter for offline rolling comparison.
--
-- It loads the real pure rolling modules of one source root in that root's
-- own Nexus.toc order, and builds the decision state the production runtime
-- builds (core/AutomationRuntime.lua StepRun, the `state` table before
-- Policy.Decide). No module is replaced or patched. No WoW API, saved state,
-- network or game action is involved, and no draw odds are modelled.
--
-- The root is NEXUS_POLICY_ROOT or the current directory, so the same adapter
-- drives the immutable test.9020 baseline and a corrected candidate.
local Adapter={}
local PURE={'data\\DefaultProfile.lua','core\\EchoCatalogSource.lua','logic\\Model.lua','logic\\Strategy.lua','logic\\Ratchet.lua',
 'logic\\WishlistPilot.lua','logic\\OrbPolicy.lua','logic\\Policy.lua'}
function Adapter.Load(root)
 root=(root or os.getenv('NEXUS_POLICY_ROOT') or '.'):gsub('\\','/')
 local toc=assert(io.open(root..'/Nexus.toc','rb')):read('*a')
 local last,order=0,{}
 for _,entry in ipairs(PURE)do
  local at=assert(toc:find(entry,1,true),'TOC does not list '..entry)
  assert(at>last,'adapter order differs from the production TOC at '..entry)
  last=at;order[#order+1]=entry
 end
 Nexus=nil
 for _,entry in ipairs(order)do dofile(root..'/'..entry:gsub('\\','/'))end
 assert(Nexus.WishlistPilot and Nexus.Policy and Nexus.Strategy and Nexus.Ratchet and Nexus.Model and Nexus.EchoCatalogSource,'pure rolling modules loaded')
 Adapter.root,Adapter.order=root,order
 return Nexus
end
-- Production-shaped catalog. The synthetic PerkDatabase rows go through the
-- real pure core/EchoCatalogSource.lua Materialize, exactly as GameAdapter
-- does, so the result has the production fields: rows, familyOf,
-- familyMembers, familyName and levers. Quality siblings share one groupId and
-- therefore one production family key ("g<groupId>"); a single Echo is its
-- own family ("s<spellId>"). Input: { name = { [quality] = spellId, ... } }.
function Adapter.Catalog(families)
 local names={}
 for name in pairs(families)do names[#names+1]=name end
 table.sort(names)
 local database={}
 for group,name in ipairs(names)do
  local members=0
  for _ in pairs(families[name])do members=members+1 end
  for quality,id in pairs(families[name])do
   database[id]={maxStack=5,quality=quality,groupId=members>1 and group or 0,classMask=0,minLevel=1,
    requiredSpell=0,comment=name..'-q'..quality}
  end
 end
 local catalog,why=Nexus.EchoCatalogSource.Materialize(database,nil)
 return assert(catalog,why)
end
-- Exact copy of the shape GameAdapter's EchoesToWishlist builds for a designed
-- build (core/GameAdapter.lua 782-841, echoHasQuality=false): quality comes
-- from the catalog row, a family's entries are merged into one target, and
-- every quality keeps its own tier. It is duplicated here only because that
-- function is local to an event-driven module.
function Adapter.Wishlist(catalog,echoes,name)
 local entries,byFamily={}, {}
 for i=1,#echoes do
  local e=echoes[i]
  local id=type(e)=='table' and tonumber(e.spellId)
  if id and catalog.rows[id] then
   local fam=catalog.familyOf[id] or ('s'..tostring(id))
   local stacks=tonumber(e.stacks) or 1
   if stacks<1 then stacks=1 end
   local q=catalog.rows[id].quality or 0
   entries[#entries+1]={spellId=id,quality=q,stacks=stacks,family=fam}
   local t=byFamily[fam]
   if not t then
    byFamily[fam]={targetStacks=stacks,wishedQuality=q,spellId=id,qualityTiers={{q=q,n=stacks,spellId=id}}}
   else
    t.targetStacks=t.targetStacks+stacks
    if q<t.wishedQuality then t.wishedQuality=q end
    local found=false
    for _,tier in ipairs(t.qualityTiers)do
     if tier.q==q then tier.n=tier.n+stacks;found=true;break end
    end
    if not found then t.qualityTiers[#t.qualityTiers+1]={q=q,n=stacks,spellId=id}end
   end
  end
 end
 for _,t in pairs(byFamily)do
  if #t.qualityTiers>1 then table.sort(t.qualityTiers,function(a,b)return a.q<b.q end)end
 end
 if #entries==0 then return nil end
 return {name=tostring(name or ''),entries=entries,byFamily=byFamily,source='designed'}
end
-- Real Strategy.Compile from exact Wishlist entries {spellId,stacks}. The
-- runtime also passes WishlistWithLockTargets; this adapter models a Wishlist
-- with no permanent-slot targets, and permanent copies arrive through `locked`.
function Adapter.Plan(catalog,entries)
 local wishlist=assert(Adapter.Wishlist(catalog,entries,'adapter'),'wishlist entries resolve in the catalog')
 local plan=Nexus.Strategy.Compile(catalog,wishlist,{})
 local expected={}
 for _,e in ipairs(entries)do expected[e.spellId]=(expected[e.spellId] or 0)+(e.stacks or 1)end
 for id,count in pairs(expected)do
  assert(plan.requestedCounts[id]==count,'compiled plan carries the exact requested count')
 end
 return plan
end
-- Saved-row echoes as GameAdapter.Slots rows carry them, with the catalog family.
function Adapter.Echoes(catalog,echoes)
 local out={}
 for i,e in ipairs(echoes)do
  local row=assert(catalog.rows[e.spellId],'saved echo in catalog')
  out[i]={spellId=e.spellId,family=catalog.familyOf[e.spellId],quality=row.quality,stacks=e.stacks or 1}
 end
 return out
end
-- GameAdapter.Owned / LockedOwned projection fields used by the policy.
function Adapter.Owned(catalog,bySpell,synced)
 local owned={synced=synced~=false,bySpell={},byFamily={},distinct=0,total=0}
 for id,count in pairs(bySpell or {})do
  if catalog.rows[id] then
   owned.bySpell[id]=count
   local family=catalog.familyOf[id]
   owned.byFamily[family]=(owned.byFamily[family] or 0)+count
   owned.distinct=owned.distinct+1;owned.total=owned.total+count
  end
 end
 return owned
end
local function Cards(catalog,cards)
 local out={}
 for i,c in ipairs(cards)do
  local row=catalog.rows[c.spellId] or {}
  -- GameAdapter.Board: spellId, quality, family from the catalog, and the
  -- four observed flags as booleans.
  local card={spellId=c.spellId,quality=c.quality or row.quality or 0,
   family=catalog.familyOf[c.spellId] or ('s'..tostring(c.spellId)),
   isFrozen=c.isFrozen and true or false,isCarried=c.isCarried and true or false,
   isGuaranteed=c.isGuaranteed and true or false,justFrozen=c.justFrozen and true or false}
  out[i]=card
 end
 return out
end
-- The saved-row preparation is the one place the two candidates differ.
--  test.9020 (AutomationRuntime 2182-2195): snapshotVerified = row.verified;
--   queue = verified and Ratchet.PredictQueue(row.echoes, ...) or empty.
--  corrected: no verification flag reaches the policy; the queue is empty.
-- 'as-runtime' asks the loaded root's own Ratchet, which is how each runtime
-- obtains its queue, and passes the flag only where that runtime passes it.
function Adapter.State(input)
 local catalog,plan=input.catalog,input.plan
 local owned=input.owned or Adapter.Owned(catalog,{})
 local locked=input.locked or Adapter.Owned(catalog,{})
 local row=input.activeRow or {verified=false,echoes={}}
 local flags=input.flags or {}
 local board={cards=Cards(catalog,input.cards),signature=input.signature or 'adapter-board'}
 for i,c in ipairs(board.cards)do if c.isGuaranteed then board.guaranteedIndex=i end end
 local legacyRuntime=input.runtime=='test9020'
 local verified=row.verified==true
 local queue={entries={}}
 if legacyRuntime and verified then
  queue=Nexus.Ratchet.PredictQueue(row.echoes or {},owned,plan,flags,input.disabledLevers or {},catalog)
 end
 if input.prefilledQueue then queue=input.prefilledQueue end
 local level=input.level or 20
 local charges=input.charges or {trustworthy=true,banish=0,freeze=0,reroll=0}
 local state={board=board,owned=owned,locked=locked,charges=charges,plan=plan,
  ordinaryBoardAllowed=input.ordinaryBoardAllowed~=false,
  allowReroll=input.allowReroll==true,allowFreeze=input.allowFreeze==true,
  allowBanish=input.allowBanish==true,
  activeEchoes=row.echoes or {},queue=queue,flags=flags,level=level,catalog=catalog,
  horizon=input.horizon,
  canFreeze=input.allowFreeze==true and (level<80 or (type(input.horizon)=='number' and input.horizon>1)),
  support=Nexus.Model.Support(catalog,owned,level,input.disabledLevers or {},plan,Nexus.DefaultProfile.params),
  params=Nexus.DefaultProfile.params,
  searchRefused={banish=false,reroll=input.allowReroll~=true},
  rerollBudget={consecutive=0,consecutiveLimit=3,bracketSpent=0,bracketLimit=4,reserve=5},
  pending=input.pending,pendingAction=input.pendingAction}
 if legacyRuntime or input.forceVerifiedFlag~=nil then
  state.snapshotVerified=input.forceVerifiedFlag==nil and verified or input.forceVerifiedFlag
 end
 return state
end
function Adapter.Decide(input)
 local state=Adapter.State(input)
 return Nexus.Policy.Decide(state),state
end
function Adapter.Line(action)
 return table.concat({tostring(action.type),tostring(action.spellId),tostring(action.index),
  tostring(action.planner),tostring(action.reason)},'|')
end
-- Deterministic djb2 fingerprint of decision lines; no clock or RNG input.
function Adapter.Fingerprint(lines)
 local hash=5381
 for _,line in ipairs(lines)do
  for i=1,#line do hash=((hash*33)+line:byte(i))%2147483648 end
  hash=((hash*33)+10)%2147483648
 end
 return string.format('%08x',hash)
end
return Adapter
