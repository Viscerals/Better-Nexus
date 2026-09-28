-- #26: the Community card shows ONE real Dummy + Lich King pair. A build
-- qualifies only when one character has both records on the same loadout,
-- and the numbers the card shows must be that character's numbers. Before
-- this fix the card showed the highest Dummy and the highest Lich King over
-- all characters, from two different people, and averaged them.
--
-- Alpha and Bravo run the SAME loadout. Alpha has the best Dummy record and
-- a low Lich King record; Bravo has the best Lich King record and a low Dummy
-- record. Their per-category maxima (60000 / 50000, average 55000) belong to
-- nobody. The best pair (highest single record, then identity) is Alpha's:
-- 60000 / 20000, average 40000.
--
-- Real TOC boot, catalog, DpsCapture eligibility and the real Community
-- projection; synthetic data.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',isLocal=true,variant=30,ordinary=60},
 {name='Alpha',class='MAGE',variant=7,dps={dummy=60000,lk=20000}},
 {name='Bravo',class='MAGE',variant=7,build='missing',dps={dummy=30000,lk=50000}},
}})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
for _=1,400 do H.Advance(.05,.05) end
local alpha,bravo=fx.players[2],fx.players[3]
check(alpha.fingerprint==bravo.fingerprint,'fixture: Alpha and Bravo run the same loadout')
check(alpha.lockedFingerprint==bravo.lockedFingerprint,'fixture: with the same locked set')

-- 1. The qualification summary that every card and detail reader uses.
local D=Nexus.DpsCapture
local q=D.GetCommunityQualification(alpha.fingerprint)
check(type(q)=='table','the loadout qualifies (Alpha and Bravo each have a real pair)')
check(q.dummy==60000 and q.lk==20000,
 'the summary shows one character\'s pair, not per-category maxima: dummy='..tostring(q.dummy)..' lk='..tostring(q.lk))
check(q.average==40000,'and that pair\'s average: '..tostring(q.average))
check(q.best==60000,'and that pair\'s best record: '..tostring(q.best))

-- 2. The Community card (the real projection row) shows the same numbers.
local P=Nexus.ViewProjections
local rows
local filters={currentClassOnly=false,qualifiedOnly=false,scope='all',sortMode='title',page=1}
for _=1,4000 do
 rows=P.RequestBuilds(filters)
 if rows then break end
 P.PumpBuilds();H.Advance(.05,.05)
end
check(rows~=nil,'the Community projection published')
local card
for _,b in ipairs(rows) do if b.id==alpha.buildId then card=b end end
check(card~=nil,'Alpha\'s build is listed')
local shown=card._nexusDps or {}
check(shown.dummy==60000 and shown.lk==20000,
 'the card shows Alpha\'s Dummy and Lich King records: dummy='..tostring(shown.dummy)..' lk='..tostring(shown.lk))
check(shown.average==40000,'and their average, not a mix of two characters: '..tostring(shown.average))
check(card._nexusQualified==true,'and the build still qualifies')

-- 3. The build detail reader agrees with the card.
local controller=Nexus.CommunityController
if controller and type(controller.DpsSummary)=='function' then
 local detail=controller.DpsSummary(card)
 check(detail.dummy==60000 and detail.lk==20000,
  'the detail summary shows the same pair: dummy='..tostring(detail.dummy)..' lk='..tostring(detail.lk))
end

print('PASS community_card_dps_pair '..checks..' checks')
