-- Replay parity of the live adaptive policy with the studied candidate
-- adaptive-0-settle (private study echo-banish-policy-sim 85ec1d2).
--
-- The vectors are decisions the STUDY made on ordinary boards (neutral weights,
-- group exclusion, no locked ownership). They were produced by the study's own
-- code (adaptive-policy-010/gen_parity.lua) and are replayed here through the
-- real pure modules in TOC order. Fixtures only; this is not an efficacy test and
-- says nothing about draw odds.
--  * parity set: every quality group has one member count, so the study's group pool
--    weights are equal. The live decision must equal the study's action, index and id.
--  * divergence set: group sizes differ. The study ranks Banish victims by group pool
--    weight; the live addon has no pool, so it picks the first safe offer. Only the
--    Banish victim may differ; the kind of action may not.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local V=dofile('tests/prototype/fixtures/adaptive_parity_vectors.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local function Build(v)
 local families={}
 for f,members in ipairs(v.F)do
  local fam={};for q,id in ipairs(members)do fam[q-1]=id end
  families['f'..f]=fam
 end
 local catalog=P.Catalog(families)
 local targets={};for i,t in ipairs(v.T)do targets[i]={spellId=t[1],stacks=t[2]}end
 local owned={};for id,n in pairs(v.O)do owned[id]=n end
 local cards={}
 for i,c in ipairs(v.C)do
  cards[i]={spellId=c[1],isFrozen=c[2]:find('F',1,true)~=nil,isCarried=c[2]:find('C',1,true)~=nil,
   justFrozen=c[2]:find('J',1,true)~=nil,isGuaranteed=c[2]:find('G',1,true)~=nil}
 end
 return {catalog=catalog,plan=P.Plan(catalog,targets),owned=P.Owned(catalog,owned),cards=cards,horizon=v.H,
  charges={banish=v.R[1],reroll=v.R[2],freeze=v.R[3],trustworthy=v.R[4]},
  allowBanish=v.A[1],allowReroll=v.A[2],allowFreeze=v.A[3]}
end
local function Key(a) return string.format('%s:%d:%d',a.type,a.index or 0,a.spellId or 0) end

check(#V.parity>=500 and #V.divergence>=250,'the fixture holds the declared vector counts')
local kinds={}
local releasedMatches=0
for n,v in ipairs(V.parity)do
 local input=Build(v)
 local got=P.Decide(input)
 check(got.policyId=='adaptive-0-settle-live1' and got.fallbackReason==nil,'parity '..n..': adaptive ran with no fallback: '..tostring(got.fallbackReason))
 check(Key(got)==v.E,'parity '..n..': live '..Key(got)..' = study '..v.E)
 kinds[got.type]=(kinds[got.type] or 0)+1
 input.rollingPolicy='released'
 if Key(P.Decide(input))==v.E then releasedMatches=releasedMatches+1 end
end
-- The set exercises every action kind and the released policy does not already match it.
for _,kind in ipairs({'take','freeze','banish','reroll'})do check((kinds[kind] or 0)>=20,'parity set holds at least 20 '..kind..' decisions: '..tostring(kinds[kind]))end
check(releasedMatches<#V.parity-40,'the released policy differs from the study on at least 40 parity vectors ('..releasedMatches..'/'..#V.parity..' equal)')

local differs,sameKindOnly=0,true
for n,v in ipairs(V.divergence)do
 local got=P.Decide(Build(v))
 check(got.policyId=='adaptive-0-settle-live1' and got.fallbackReason==nil,'divergence '..n..': adaptive ran with no fallback')
 local expectedKind=v.E:match('^(%a+):')
 if Key(got)~=v.E then
  differs=differs+1
  if got.type~=expectedKind then sameKindOnly=false end
  check(got.type=='banish' and expectedKind=='banish','divergence '..n..': only a Banish victim differs: live '..Key(got)..' study '..v.E)
 end
end
check(sameKindOnly,'divergences keep the action kind')
check(differs>=5,'the divergence set shows the documented difference at least 5 times ('..differs..')')
print(string.format('PASS adaptive policy replay parity: %d parity vectors equal, %d divergence vectors (%d Banish-victim differences) checks=%d',#V.parity,#V.divergence,differs,checks))
