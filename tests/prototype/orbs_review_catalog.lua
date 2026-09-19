-- Independent fail-capable N1 capability probe; no product functions are replaced.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.db[410002].requiredSpell=12345;H.discovered[410002]=true
H.perks.discoveredEchoes=H.discovered;H.service.IsTomeEchoDisabled=nil
assert(A.CheckCatalogSource())
H.OrbPlan();assert(M.SuggestSources())
local before,why=M.Prepare('single')
assert(not before and why:find('IsTomeEchoDisabled',1,true))
print('KNOWN_GATED_BEFORE',A.Catalog().rows[410002].requiredSpell,'approval',before~=nil,'reason',why)
-- GameAdapter intentionally retains its prior complete catalog during source loss.
ProjectEbonhold.PerkDatabase=nil
local status=M.Status();local after,e=M.Prepare('single')
print('RAW_CATALOG_UNAVAILABLE','cachedGate',A.Catalog().rows[410002].requiredSpell,'available',status.catalog[410002].available,'approval',after~=nil,'reason',e)
if after then assert(M.Confirm(after.token)) end
print('UNKNOWN_CAPABILITY_SPEND','spends',H.Count('orb-spend'),'source',O.source)
assert(not after and H.Count('orb-spend')==0,'SAFETY: missing raw catalog must not turn a cached gated target with unknown disable capability into permission to spend')
print('PASS missing raw catalog does not erase availability gating')
