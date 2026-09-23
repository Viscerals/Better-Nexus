-- Stacked-copy shape from a test.9032 tester report (synthetic IDs, no player data):
-- the active Saved Build has 75 entries = 69 ordinary entries holding 79 ordinary
-- copies (one x2 and one x10 stack among them) + 6 permanent copies. The assigned
-- desired Wishlist is a SEPARATE record (62 entries); it is not replaced by the
-- Saved Build of the same name, and stacks are never flattened.
-- Real TOC boot, adapter, Orb runtime/policy and panel; fake Orb services only
-- (a spend here is a counted fake call, not a game action).
-- Same fake Orb service as tests/prototype/orbs_support.lua; the two stacked Echoes
-- are defined before the real boot so that the catalog contains them.
local H=dofile('tests/prototype/harness.lua')
local QUICK,DOUBLE=410101,410102
H.AddEcho(QUICK,'Quick Hands',1,2,4101)
H.AddEcho(DOUBLE,'Double Strike',2,10,4102)
H.orbs={charges=10,known=true,offer=false,requests=0}
local O=H.orbs
ProjectEbonhold.OrbService={
 IsStateKnown=function()return O.known end,
 GetCharges=function()return O.charges end,
 IsOfferPending=function()return O.offer end,
 ConfirmSpend=function(id,n)H.actions[#H.actions+1]={'orb-spend',id,n};O.source=id;return true end,
 RequestCharges=function()O.requests=O.requests+1;return true end,
}
H.Boot();local A=Nexus.GameAdapter;local M=Nexus.OrbRuntime
function H.Count(kind)local n=0;for _,a in ipairs(H.actions)do if a[1]==kind then n=n+1 end end;return n end
local ordinary,permanent,granted,locked={}, {}, {}, {}
ordinary[1]={spellId=QUICK,quality=1,stacks=2};ordinary[2]={spellId=DOUBLE,quality=2,stacks=10}
for i=1,67 do ordinary[#ordinary+1]={spellId=200000+i,quality=i%4,stacks=1}end
for i=1,6 do permanent[i]={spellId=200070+i,quality=(70+i)%4,stacks=1,locked=true}end
local copies=0;for _,e in ipairs(ordinary)do copies=copies+e.stacks end
assert(#ordinary==69 and copies==79 and #ordinary+#permanent==75,'fixture: 69 ordinary entries = 79 copies, +6 locked = 75 entries')
for _,e in ipairs(ordinary)do granted[H.names[e.spellId]]={{spellId=e.spellId,quality=e.quality,stacks=e.stacks}}end
for _,e in ipairs(permanent)do locked[H.names[e.spellId]]={{spellId=e.spellId,quality=e.quality}}end
H.granted=granted;H.locked=locked
local saved={};for _,e in ipairs(ordinary)do saved[#saved+1]=e end;for _,e in ipairs(permanent)do saved[#saved+1]=e end
H.perks.serverBuildSlots={[1]={name='stacked',verified=true,echoes=saved}};H.perks.serverActiveSlot=1
-- The desired Wishlist: 56 ordinary entries + 6 permanent targets = 62 entries, different content.
local desired={{spellId=QUICK,quality=1,stacks=2},{spellId=DOUBLE,quality=2,stacks=4}}
for i=1,50 do desired[#desired+1]={spellId=200000+i,quality=i%4,stacks=1}end
for i=1,4 do desired[#desired+1]={spellId=200080+i,quality=(80+i)%4,stacks=1}end   -- not owned yet
for _,e in ipairs(permanent)do desired[#desired+1]={spellId=e.spellId,quality=e.quality,stacks=1,locked=true}end
assert(#desired==62,'fixture: 62 desired entries')
assert(A.SetFirstLoadoutWishlistIdentity('stacked',desired))
H.Notify();A.Poll()

Nexus.OrbPanel.Show()
local s=NexusOrbPanel.snapshot
assert(s.assignment and s.assignment.state=='ready','the assigned desired Wishlist resolves: '..tostring(s.assignment and s.assignment.note))
assert(#s.config.entries==62,'the display uses the desired Wishlist, not the 75-entry Saved Build')
assert(s.progress and s.progress.rolledMissing==4 and s.progress.permanentMissing==0,'4 rolled target copies missing, counted as copies: '..tostring(s.progress and s.progress.rolledMissing))
assert(NexusOrbPanel.targets:GetText()=='4 rolled target copies still missing','the status text states copies')
-- Sources by copies: Double Strike x10 with 4 needed has 6 safe copies; Quick Hands x2 with 2 needed has none.
local st=M.Status(true)
local bySpell={};for _,r in ipairs(st.sources)do bySpell[r.spellId]=r end
assert(bySpell[DOUBLE] and bySpell[DOUBLE].count==10 and bySpell[DOUBLE].excess==6,'the x10 stack is read as 10 copies with 6 safe: '..tostring(bySpell[DOUBLE] and bySpell[DOUBLE].excess))
assert(bySpell[QUICK]==nil,'the x2 stack needed by the plan is protected')
for _,e in ipairs(permanent)do assert(bySpell[e.spellId]==nil,'locked copies are never sources')end
assert(s.canStart==true,'Start is available with the stacked shape: '..tostring(s.startReason))
assert(#H.actions==0,'opening and reading send nothing')
-- One explicit Start: one fake spend of a safe copy; never the protected stack or a permanent copy.
assert(M.SetLimit(1));assert(M.Start())
assert(H.Count('orb-spend')==1,'one spend')
assert(O.source~=QUICK,'the protected x2 stack is not spent')
for _,e in ipairs(permanent)do assert(O.source~=e.spellId,'no locked copy is spent')end
assert(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending,'the receipt of that spend is durable')
assert(s.persistence.mode=='durable' and s.persistence.rowPresent==true,'assignment already created the durable row')
print('PASS orb_stacked_copies: 75 saved entries = 79 ordinary + 6 locked copies; desired Wishlist separate; stacks counted as copies')
