local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.granted={['Protected low']={{spellId=410005,quality=0}},['Excess high']={{spellId=410006,quality=3}}}
H.Notify();A.Poll()
H.OrbPlan({{spellId=410005,quality=0,stacks=1},{spellId=410002,quality=2,stacks=1}})
assert(M.SuggestSources());assert(not M.Prepare(),'known shared family protects lowest required copy')
print('BEFORE_SOURCE_LOSS','sources',#M.Status().sources,'lowGroup',M.Status().catalog[410005].group,'highGroup',M.Status().catalog[410006].group)
ProjectEbonhold.PerkDatabase=nil
assert(M.SuggestSources());local status=M.Status();local plan,why=M.Prepare('single')
print('AFTER_SOURCE_LOSS','sources',#status.sources,'lowGroup',status.catalog[410005].group,'highGroup',status.catalog[410006].group,'approval',plan~=nil)
if plan then assert(M.Confirm(plan.token)) end
print('FAMILY_GUARD_BYPASS','spends',H.Count('orb-spend'),'source',O.source,'cachedGroup',A.Catalog().rows[410006].groupId)
assert(not plan and H.Count('orb-spend')==0,'SAFETY: missing raw catalog must not erase the known family guard and approve a previously protected family')
print('PASS missing raw catalog preserves family protection')
