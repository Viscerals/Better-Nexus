-- NX-03 semantic controls for the slot projection and the Echo catalog
-- (stutter review, 2026-10-14). Companion of stutter_slot_projection.lua: that
-- test bounds the catalog work of one GameAdapter.Slots() projection; this one
-- holds the behaviour a fix must keep. It passes on the delivered build
-- test.2026101502-3d52b0ed7044 and must still pass after the NX-03 fix.
--
-- Required, through public GameAdapter functions and foreign inputs only:
--  A. No catalog yet (login-time class unknown): every Echo projects
--     "s<spellId>", nothing is cached, and the next projection retries; once
--     the class is known the next projection shows the catalog families.
--  B. With the catalog: known families, the unknown-Echo fallback, detached
--     results, unnotified in-place mirror edits, malformed mirror entries, an
--     unnotified PerkDatabase reference swap, an in-place catalog change seen
--     after the source check, family drift blocked (in place and by reference),
--     and source loss keeping the published catalog.
-- Expected families are worked by hand from the fixture rows and the contract
-- rule (CONTRACTS.md: "g<groupId>" when more than one row shares groupId, else
-- "s<spellId>"); no production helper computes an expectation.
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

H.AddEcho(330001,'Stutter Pair One',1,3,3300)
H.AddEcho(330002,'Stutter Pair Two',2,3,3300)
H.AddEcho(330003,'Stutter Lone Group',3,2,3301)
H.AddEcho(330004,'Stutter Ungrouped',0,4,0)
H.AddEcho(330005,'Stutter Trio One',1,2,3302)
H.AddEcho(330006,'Stutter Trio Two',2,2,3302)
H.AddEcho(330007,'Stutter Trio Three',3,2,3302)
local UNKNOWN=339999 -- not in PerkDatabase

local P=H.perks
P.serverBuildSlots={
 [1]={name='Alpha',verified=true,echoes={
  {spellId=330001,quality=1,stacks=2},{spellId=330003,quality=3,stacks=1},
  {spellId=UNKNOWN,quality=0,stacks=1},{spellId=330005,quality=2,stacks=3}}},
 [2]={name='Beta',verified=true,echoes={
  {spellId=330002,quality=2,stacks=1},{spellId=330004,quality=0},
  {spellId=330006,quality=1,stacks=2},{spellId=330007,quality=3,stacks=1}}},
 [4]={name='Delta',verified=false,echoes={}},
}
-- {spellId, stacks, quality, family} with the catalog.
local SMALL={
 [1]={{330001,2,1,'g3300'},{330003,1,3,'s330003'},{339999,1,0,'s339999'},{330005,3,2,'g3302'}},
 [2]={{330002,1,2,'g3300'},{330004,1,0,'s330004'},{330006,2,1,'g3302'},{330007,1,3,'g3302'}},
 [4]={},
}
-- The same rows with no catalog: every family is the "s<spellId>" fallback.
local FALLBACK={
 [1]={{330001,2,1,'s330001'},{330003,1,3,'s330003'},{339999,1,0,'s339999'},{330005,3,2,'s330005'}},
 [2]={{330002,1,2,'s330002'},{330004,1,0,'s330004'},{330006,2,1,'s330006'},{330007,1,3,'s330007'}},
 [4]={},
}

local function Echo(label,slots,slot,i,id,stacks,quality,family)
 local row=slots and slots.bySlot and slots.bySlot[slot]
 local e=row and row.echoes[i]
 check(type(e)=='table' and e.spellId==id and e.stacks==stacks and e.quality==quality and e.family==family,
  label..': slot '..slot..' Echo '..i..' {'..id..','..stacks..','..quality..','..family..'} got {'
  ..tostring(e and e.spellId)..','..tostring(e and e.stacks)..','..tostring(e and e.quality)..','..tostring(e and e.family)..'}')
end
local function Matches(label,slots,want)
 check(type(slots)=='table' and type(slots.bySlot)=='table',label..': a projection')
 local keys=0
 for slot in pairs(slots.bySlot) do keys=keys+1;check(want[slot]~=nil,label..': no unexpected slot '..tostring(slot)) end
 local wanted=0;for _ in pairs(want) do wanted=wanted+1 end
 check(keys==wanted,label..': '..wanted..' slots: '..keys)
 for slot,rows in pairs(want) do
  check(#slots.bySlot[slot].echoes==#rows,label..': slot '..slot..' has '..#rows..' Echoes: '..#slots.bySlot[slot].echoes)
  for i,e in ipairs(rows) do Echo(label,slots,slot,i,e[1],e[2],e[3],e[4]) end
 end
end

-- A. No catalog yet. A login-time class without a token is the documented
-- waiting state: the build waits and retries once the class is known. The
-- adapter is loaded directly (as orb_readiness_persistence.lua loads its
-- modules) so its first catalog build happens here, before the normal boot.
local realClass=UnitClass
UnitClass=function() return 'Mage' end
Nexus={}
dofile('core/EchoCatalogSource.lua');dofile('core/GameAdapter.lua')
local A0=Nexus.GameAdapter
Matches('A no class, first projection',A0.Slots(),FALLBACK)
check(A0.Catalog()==nil,'A no class: no catalog')
local s0=A0.CatalogStatus()
check(s0.lastResult=='waiting-for-class' and s0.rebuilds==0 and s0.failures==0,
 'A no class: waiting, not a failure: '..tostring(s0.lastResult)..' rebuilds='..s0.rebuilds..' failures='..s0.failures)
Matches('A no class, second projection',A0.Slots(),FALLBACK)
check(A0.Catalog()==nil and A0.CatalogStatus().rebuilds==0,'A no class: still no catalog')
UnitClass=realClass
Matches('A class known: the next projection retries',A0.Slots(),SMALL)
s0=A0.CatalogStatus()
check(type(A0.Catalog())=='table' and s0.rebuilds==1 and s0.lastResult=='rebuilt',
 'A class known: one catalog build: '..tostring(s0.lastResult)..' rebuilds='..s0.rebuilds)
Nexus=nil

-- B. The normal boot.
H.Boot()
local A=Nexus.GameAdapter
check(type(A.Catalog())=='table','B SETUP: the Echo catalog is built at boot')
local live=P.serverBuildSlots

-- B1. Known families and the unknown-Echo fallback.
local s=A.Slots()
Matches('B1',s,SMALL)
check(s.activeSlot==0 and s.activeKnown==true and s.maxSlots==5,'B1: no active slot, 5 slots')
check(s.bySlot[1].roleSourceValid==true and s.bySlot[2].roleSourceValid==true,'B1: well-formed rows are role sources')

-- B2. Results are detached: editing one projection does not change the next.
s.bySlot[1].echoes[1].family='tampered';s.bySlot[1].echoes[1].stacks=99;s.bySlot[2]=nil
Matches('B2 after a caller edit',A.Slots(),SMALL)

-- B3. Unnotified in-place mirror edits are seen by the next projection.
live[1].echoes[1].stacks=3;live[2].echoes[2].spellId=330003
s=A.Slots()
Echo('B3 in-place stacks',s,1,1,330001,3,1,'g3300')
Echo('B3 in-place spellId',s,2,2,330003,1,0,'s330003')
live[1].echoes[1].stacks=2;live[2].echoes[2].spellId=330004
Matches('B3 edited back',A.Slots(),SMALL)

-- B4. A malformed mirror entry is omitted and marks the row as no role source.
live[5]={name='Echo',verified=true,echoes={{spellId=330002,quality=2,stacks=1},
 {spellId='not a spell',quality=1,stacks=1},{spellId=330006,quality=-1,stacks=1}}}
s=A.Slots()
check(s.bySlot[5] and #s.bySlot[5].echoes==2,'B4: the non-numeric spellId is omitted: '..tostring(s.bySlot[5] and #s.bySlot[5].echoes))
Echo('B4',s,5,1,330002,1,2,'g3300')
Echo('B4',s,5,2,330006,1,-1,'g3302')
check(s.bySlot[5].roleSourceValid==false and s.bySlot[1].roleSourceValid==true,'B4: only the malformed row is not a role source')
live[5]=nil

-- B5. Unnotified PerkDatabase reference swap: the next projection uses it.
live[1].echoes[5]={spellId=330008,quality=1,stacks=1}
s=A.Slots()
Echo('B5 before the swap: not in the catalog',s,1,5,330008,1,1,'s330008')
local before=A.CatalogStatus()
local swapped=H.Clone(ProjectEbonhold.PerkDatabase)
swapped[330008]={comment='Stutter Pair Three - Uncommon',quality=1,classMask=1535,maxStack=3,minLevel=1,groupId=3300,requiredSpell=0,families={}}
H.names[330008]='Stutter Pair Three'
ProjectEbonhold.PerkDatabase=swapped
s=A.Slots()
Echo('B5 after the swap',s,1,5,330008,1,1,'g3300')
Echo('B5 after the swap',s,1,1,330001,2,1,'g3300')
Echo('B5 after the swap',s,2,1,330002,1,2,'g3300')
local after=A.CatalogStatus()
check(after.lastResult=='rebuilt' and after.rebuilds==before.rebuilds+1,
 'B5: the swap is rebuilt once: '..tostring(after.lastResult)..' '..before.rebuilds..' -> '..after.rebuilds)

-- B6. Unnotified in-place catalog change (same table, same version): ordinary
-- reads stay O(1) (GameAdapter catalog contract); the source check publishes
-- it and the next projection uses it.
live[2].echoes[5]={spellId=330009,quality=2,stacks=1}
swapped[330009]={comment='Stutter Trio Four - Rare',quality=2,classMask=1535,maxStack=2,minLevel=1,groupId=3302,requiredSpell=0,families={}}
H.names[330009]='Stutter Trio Four'
before=A.CatalogStatus()
s=A.Slots()
Echo('B6 before the check',s,2,5,330009,1,2,'s330009')
check(A.CatalogStatus().rebuilds==before.rebuilds,'B6: an ordinary projection does not rebuild')
local ok,result,changed=A.CheckCatalogSource()
check(ok==true and result=='rebuilt' and changed==true,'B6: the check publishes the in-place change: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
s=A.Slots()
Echo('B6 after the check',s,2,5,330009,1,2,'g3302')
Echo('B6 after the check',s,2,3,330006,2,1,'g3302')
Echo('B6 after the check',s,1,4,330005,3,2,'g3302')

-- B7. In-place family drift is blocked; the published families stay.
swapped[330004].groupId=3302
before=A.CatalogStatus()
ok,result,changed=A.CheckCatalogSource()
check(ok==false and result=='family-blocked' and changed==false,'B7: in-place drift is blocked: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
after=A.CatalogStatus()
check(after.familyBlocks==before.familyBlocks+1 and after.rebuilds==before.rebuilds,'B7: blocked, not rebuilt')
for pass=1,2 do Echo('B7 projection '..pass,A.Slots(),2,2,330004,1,0,'s330004') end
swapped[330004].groupId=0
ok,result,changed=A.CheckCatalogSource()
check(ok==true and result=='unchanged' and changed==false,'B7: reverted: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))

-- B8. Family drift by reference swap is blocked at the next projection.
local drifted=H.Clone(swapped)
drifted[330001].groupId=3302
ProjectEbonhold.PerkDatabase=drifted
before=A.CatalogStatus()
s=A.Slots()
Echo('B8 drifted source',s,1,1,330001,2,1,'g3300')
after=A.CatalogStatus()
check(after.lastResult=='family-blocked' and after.familyBlocks==before.familyBlocks+1 and after.rebuilds==before.rebuilds,
 'B8: the swap is blocked: '..tostring(after.lastResult)..' blocks '..before.familyBlocks..' -> '..after.familyBlocks)
Echo('B8 second projection',A.Slots(),1,1,330001,2,1,'g3300')
check(A.CatalogStatus().rebuilds==before.rebuilds,'B8: still not rebuilt')
ProjectEbonhold.PerkDatabase=swapped
s=A.Slots()
check(A.CatalogStatus().lastResult=='unchanged' and A.CatalogStatus().rebuilds==before.rebuilds,
 'B8: the published source again is unchanged: '..tostring(A.CatalogStatus().lastResult))
Echo('B8 restored',s,1,1,330001,2,1,'g3300')
Echo('B8 restored',s,2,5,330009,1,2,'g3302')

-- B9. Source loss keeps the published catalog.
ProjectEbonhold.PerkDatabase=nil
before=A.CatalogStatus()
s=A.Slots()
Echo('B9 source lost',s,1,5,330008,1,1,'g3300')
Echo('B9 source lost',s,2,5,330009,1,2,'g3302')
Echo('B9 source lost',s,1,3,UNKNOWN,1,0,'s339999')
check(A.CatalogStatus().lastResult=='failed' and A.CatalogStatus().rebuilds==before.rebuilds,
 'B9: source loss is a failure, the catalog is kept: '..tostring(A.CatalogStatus().lastResult))
ProjectEbonhold.PerkDatabase=swapped
s=A.Slots()
check(A.CatalogStatus().lastResult=='unchanged','B9: restored source is unchanged: '..tostring(A.CatalogStatus().lastResult))
Echo('B9 restored',s,1,1,330001,2,1,'g3300')

-- B10. Updated client (2026-11 capture; second Spec review and Root
-- probe_catalog_contract_transition.lua): a row's requiredSpell is a tome
-- gate only when the database uses isTome marks; otherwise it is a talent
-- gate. A first mark added in place (same table, same version) changes the
-- whole contract: the bounded row verifier no longer accepts the published
-- legacy catalog, and the atomic source check rebuilds it. Removing the mark
-- goes back; a mark on a row the catalog skips changes nothing.
do
 local db=ProjectEbonhold.PerkDatabase
 local src=Nexus.EchoCatalogSource
 H.names[440004]='Tome of Stutter Ungrouped'
 H.names[9]='Some Talent'
 db[330003].requiredSpell=9
 db[330004].requiredSpell=440004
 ok,result,changed=A.CheckCatalogSource()
 check(ok==true and result=='rebuilt','B10: the in-place gates are published: '..tostring(result))
 local cat=A.Catalog()
 check(cat.tomeContract==false and cat.levers[9]~=nil and cat.levers[440004]~=nil,
  'B10: without isTome marks every gate is a tome lever, as before')
 db[330004].isTome=true
 check(src.VerifyRow(cat,330004,db[330004],H.SpellName or GetSpellInfo)==false,
  'B10: a first isTome mark added in place fails the bounded row verifier')
 ok,result,changed=A.CheckCatalogSource()
 cat=A.Catalog()
 check(ok==true and result=='rebuilt' and cat.tomeContract==true,'B10: the contract change is rebuilt atomically: '..tostring(result))
 check(cat.levers[440004]~=nil and cat.levers[9]==nil,'B10: under the contract a talent gate is no tome lever')
 check(cat.rows[330003].requiredSpell==0 and cat.rows[330003].talentSpell==9,'B10: the talent gate is kept as a requirement')
 db[339990]={comment='Skipped - Common',isTome=true}
 ok,result,changed=A.CheckCatalogSource()
 check(result=='unchanged' and A.Catalog().tomeContract==true,'B10: a mark on a row the catalog skips changes nothing: '..tostring(result))
 db[339990]=nil
 db[330004].isTome=nil
 check(src.VerifyRow(A.Catalog(),330004,db[330004],H.SpellName or GetSpellInfo)==false,
  'B10: removing the only mark fails the bounded row verifier')
 ok,result,changed=A.CheckCatalogSource()
 cat=A.Catalog()
 check(result=='rebuilt' and cat.tomeContract==false and cat.levers[9]~=nil,'B10: and is rebuilt back to the legacy reading: '..tostring(result))
 db[330003].requiredSpell=0
 db[330004].requiredSpell=0
 ok,result,changed=A.CheckCatalogSource()
 check(result=='rebuilt','B10: the fixture rows are restored: '..tostring(result))
 -- Third Spec review (Root probe_catalog_contract_removal): the only mark on
 -- a row whose requiredSpell is 0 changes no gate, yet it decides the
 -- contract. Its removal, and its move, are seen by the bounded verifier.
 db[330003].requiredSpell=9
 db[330006].isTome=true
 ok,result,changed=A.CheckCatalogSource()
 cat=A.Catalog()
 check(result=='rebuilt' and cat.tomeContract==true and cat.levers[9]==nil,
  'B10: a single mark on a zero-gate row makes the contract: '..tostring(result))
 db[330006].isTome=nil
 check(src.VerifyRow(cat,330006,db[330006],H.SpellName or GetSpellInfo)==false,
  'B10: removing the last mark from a zero-gate row fails the bounded row verifier')
 ok,result,changed=A.CheckCatalogSource()
 cat=A.Catalog()
 check(result=='rebuilt' and cat.tomeContract==false and cat.levers[9]~=nil,
  'B10: and the legacy reading is rebuilt atomically: '..tostring(result))
 db[330006].isTome=true
 ok,result,changed=A.CheckCatalogSource()
 db[330006].isTome=nil
 db[330007].isTome=true
 cat=A.Catalog()
 check(src.VerifyRow(cat,330006,db[330006],H.SpellName or GetSpellInfo)==false
  and src.VerifyRow(cat,330007,db[330007],H.SpellName or GetSpellInfo)==false,
  'B10: a mark moved between zero-gate rows fails the verifier on both rows')
 ok,result,changed=A.CheckCatalogSource()
 check(result=='rebuilt' and A.Catalog().tomeContract==true and A.Catalog().rows[330007].tomeMark==true,
  'B10: the moved mark is rebuilt: '..tostring(result))
 db[330007].isTome=nil
 db[330003].requiredSpell=0
 ok,result,changed=A.CheckCatalogSource()
 check(result=='rebuilt' and A.Catalog().tomeContract==false,'B10: the fixture rows are restored again: '..tostring(result))
end

print('PASS slot projection catalog semantics: fallback, retry, detached, mirror edits, swap, in-place, drift, source loss; '..checks..' checks')
