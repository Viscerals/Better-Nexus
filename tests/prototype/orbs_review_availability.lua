local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
H.db[410002].requiredSpell=12345
assert(A.CheckCatalogSource()) -- Publish the fixture's changed discovery requirement.
H.perks.discoveredEchoes={[410002]=true}
H.service.GetDiscoveredEchoes=function()return H.perks.discoveredEchoes end
H.service.IsTomeEchoDisabled=function()return false end
IsSpellKnown=function()return false end
H.OrbPlan();assert(M.SuggestSources())
assert(M.Prepare(),'N1: discovered Echo does not require equivalent spellbook state')
H.service.IsTomeEchoDisabled=nil
local p,e=M.Prepare()
assert(not p and e:find('IsTomeEchoDisabled',1,true),'unknown disable capability blocks only affected action with explanation')
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});assert(M.SuggestSources())
assert(M.Prepare(),'unrelated ungated target is still actionable')
H.OrbPlan();assert(M.SuggestSources())
H.service.IsTomeEchoDisabled=function()return nil end
assert(not M.Prepare(),'nonboolean disable answer is not permissive')
H.service.IsTomeEchoDisabled=function()return false end
H.perks.discoveredEchoes=nil;IsSpellKnown=function()return true end
assert(not M.Prepare(),'spellbook true cannot substitute for unknown discovery')
H.perks.discoveredEchoes={};assert(not M.Prepare(),'known undiscovered target stays unavailable')
H.perks.discoveredEchoes={[410002]=true};H.service.IsTomeEchoDisabled=function()error('unknown')end
assert(not M.Prepare(),'failed capability read stays unknown')
H.service.IsTomeEchoDisabled=function()return false end
H.Approve(1,false);assert(H.Count('orb-spend')==1,'supported discovery approval reaches adapter')
print('PASS N1 discovered/unknown/disabled capability states and affected-action isolation')
