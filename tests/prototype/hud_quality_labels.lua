-- #38: the HUD names quality 4 "Legendary", as every other Nexus surface
-- does (Readout, Orb History, Wishlist Editor). The HUD's own table stopped
-- at Epic, so a Legendary tier read "q4" and a shed Legendary row lost its
-- quality label. An unknown quality still shows as "q<n>".
--
-- Real TOC boot; the real HUD view model; synthetic catalog rows.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local VM=Nexus.MainInternals.ViewModel.New({ratchet=Nexus.Ratchet,model=Nexus.Model,
 wishlistModel=Nexus.WishlistModel.New()})
local catalog={
 rows={[900001]={name='Legend',quality=4},[900002]={name='Tier Epic',quality=3},
  [900003]={name='Tier Legendary',quality=4},[900004]={name='Odd',quality=7}},
 familyName={famA='Family A',famB='Family B'}}

-- 1. A multi-tier wishlist target: each missing tier is labelled by quality.
local plan={wishedFamilies={famA=true},targets={famA={targetStacks=2,
 qualityTiers={{spellId=900002,q=3,n=1},{spellId=900003,q=4,n=1}}}}}
local _,_,missing=VM.WishlistProgress(plan,{bySpell={},byFamily={}},catalog,{},nil,nil,nil)
local line=table.concat(missing,' | ')
check(line:find('Legendary:×1',1,true)~=nil,'a missing Legendary tier says Legendary: '..line)
check(line:find('q4',1,true)==nil,'and not q4: '..line)
check(line:find('Epic:×1',1,true)~=nil,'the Epic tier is unchanged: '..line)

-- 2. A Legendary copy the loadout sheds keeps its quality label.
local progress=VM.BuildProgress({plan={wishedFamilies={},targets={}},
 owned={bySpell={[900001]=2},byFamily={}},slots={bySlot={}},catalog=catalog})
local shed=table.concat(progress.shed or {},' | ')
check(shed=='Legend (Legendary) ×2','a shed Legendary row is labelled: '..shed)

-- 3. A quality no table knows still shows its number.
plan={wishedFamilies={famB=true},targets={famB={targetStacks=2,
 qualityTiers={{spellId=900002,q=3,n=1},{spellId=900004,q=7,n=1}}}}}
_,_,missing=VM.WishlistProgress(plan,{bySpell={},byFamily={}},catalog,{},nil,nil,nil)
line=table.concat(missing,' | ')
check(line:find('q7:×1',1,true)~=nil,'an unknown quality keeps the q<n> fallback: '..line)

print('PASS hud_quality_labels checks='..checks)
