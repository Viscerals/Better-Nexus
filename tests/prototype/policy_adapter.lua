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
local PURE={'data\\DefaultProfile.lua','logic\\Model.lua','logic\\Strategy.lua','logic\\Ratchet.lua',
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
 assert(Nexus.WishlistPilot and Nexus.Policy and Nexus.Strategy and Nexus.Ratchet and Nexus.Model,'pure rolling modules loaded')
 Adapter.root,Adapter.order=root,order
 return Nexus
end
-- Synthetic catalog. Families may hold several quality siblings.
function Adapter.Catalog(families)
 local catalog={rows={},familyOf={},families={},familyName={},levers={}}
 for family,ids in pairs(families)do
  catalog.families[family]={};catalog.familyName[family]=family
  for quality,id in pairs(ids)do
   catalog.rows[id]={spellId=id,family=family,quality=quality,maxStacks=5,name=family..'-q'..quality,requiredLevel=1}
   catalog.familyOf[id]=family
   table.insert(catalog.families[family],id)
  end
  table.sort(catalog.families[family])
 end
 return catalog
end
-- Real Strategy.Compile from exact Wishlist entries {spellId,stacks}.
function Adapter.Plan(catalog,entries)
 local wishlist={entries={},byFamily={}}
 for _,e in ipairs(entries)do
  wishlist.entries[#wishlist.entries+1]={spellId=e.spellId,stacks=e.stacks or 1}
  local row=assert(catalog.rows[e.spellId],'wishlist entry in catalog')
  wishlist.byFamily[row.family]={spellId=e.spellId,targetStacks=e.stacks or 1,wishedQuality=row.quality}
 end
 local plan=Nexus.Strategy.Compile(catalog,wishlist,{})
 for _,e in ipairs(entries)do
  assert(plan.requestedCounts[e.spellId]==(e.stacks or 1),'compiled plan carries the exact requested count')
 end
 return plan
end
function Adapter.Owned(catalog,bySpell,synced)
 local owned={synced=synced~=false,bySpell={},byFamily={}}
 for id,count in pairs(bySpell or {})do
  owned.bySpell[id]=count
  local family=catalog.familyOf[id]
  if family then owned.byFamily[family]=(owned.byFamily[family] or 0)+count end
 end
 return owned
end
local function Cards(catalog,cards)
 local out={}
 for i,c in ipairs(cards)do
  local row=catalog.rows[c.spellId] or {}
  local card={spellId=c.spellId,family=row.family,quality=row.quality}
  for k,v in pairs(c)do card[k]=v end
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
