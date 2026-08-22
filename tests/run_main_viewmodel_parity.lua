-- Pure Main view-model extraction preserves exact progress/HUD projections,
-- defensive snapshots, value-keyed cache reuse, and zero service authority.
Nexus = {}
dofile("logic/Ratchet.lua")
dofile("core/MainViewModel.lua")

local factory = Nexus.MainInternals and Nexus.MainInternals.ViewModel
assert(factory and type(factory.New) == "function",
    "MainViewModel internal constructor is unavailable")
local view = factory.New({ratchet=Nexus.Ratchet})

local catalog = {
    rows={
        [101]={name="Alpha",quality=3},
        [102]={name="Beta",quality=2},
        [201]={name="Gamma",quality=0},
    },
    familyOf={[101]=10,[102]=10,[201]=20},
    familyName={[10]="Ten",[20]="Twenty"},
}
local plan = {
    wishedFamilies={[10]=true,[20]=true},
    targets={
        [10]={targetStacks=3,qualityTiers={
            {spellId=101,q=3,n=2},{spellId=102,q=2,n=1},
        }},
        [20]={targetStacks=1,qualityTiers={{spellId=201,q=0,n=1}}},
    },
}
local owned={byFamily={[10]=1,[20]=2},bySpell={[101]=1,[201]=2}}
local wishlist={name="Golden",byFamily={[10]=true,[20]=true},entries={
    {spellId=101,family=10,stacks=2},{spellId=102,family=10,stacks=1},
    {spellId=201,family=20,stacks=1},
}}
local slots={activeSlot=1,bySlot={[1]={slot=1,verified=true,
    verifiedFieldPresent=true,suspectParse=false,echoes={
        {spellId=101,family=10,stacks=1,locked=true},
        {spellId=201,family=20,stacks=1},
    }}}}
local lockedOwned={byFamily={},bySpell={},synced=true}
local designTargets={[101]=true}
local unknownTomes={"Tome X"}

local progress=view.BuildProgress({
    plan=plan,owned=owned,slots=slots,catalog=catalog,wishlist=wishlist,
    lockedOwned=lockedOwned,designTargets=designTargets,
    unknownTomes=unknownTomes,matchedBuildId="match",previewBuildId=nil,
})
assert(progress.owned==2 and progress.total==4
    and #progress.missing==1
    and progress.missing[1]=="Ten ×2 (Epic:×1 Rare:×1)"
    and progress.loadoutStacks.stackCount==2
    and progress.loadoutStacks.stackTotal==4
    and #progress.loadoutMissing==1 and progress.loadoutMissing[1]=="Ten"
    and #progress.locked==1 and progress.locked[1]=="Alpha"
    and #progress.shed==1 and progress.shed[1]=="Gamma (Common)"
    and #progress.toLock==1 and progress.toLock[1]=="Alpha"
    and progress.unknownTomes[1]=="Tome X"
    and progress.wishlistName=="Golden" and progress.activeSlot==1
    and progress.matchedBuildId=="match"
    and progress.dpsEchoes~=wishlist.entries
    and progress.dpsEchoes[1]~=wishlist.entries[1]
    and progress.isCommunityPreview==false,
    "exact progress, loadout, lock, shed, tome, or identity projection changed")
wishlist.entries[1].stacks=99
unknownTomes[1]="mutated"
assert(progress.dpsEchoes[1].stacks==2
    and progress.unknownTomes[1]=="Tome X",
    "progress model retained caller-owned wishlist or tome tables")

local hidden=view.BuildProgress({
    plan=plan,owned=owned,slots=slots,catalog=catalog,wishlist=wishlist,
    lockedOwned={byFamily={[10]=3},bySpell={[101]=2,[102]=1},synced=true},
    designTargets=designTargets,unknownTomes={},
})
assert(hidden.total==1 and hidden.owned==1 and #hidden.missing==0
    and #hidden.toLock==0,
    "permanently locked exact coverage did not leave the rolled target")

assert(view.ActiveSlotRow({activeSlot=0,bySlot={}})==nil
    and view.ActiveSlotRow({activeSlot=1,bySlot={[1]={verified=true}}})==nil
    and view.ActiveSlotRow(slots)==slots.bySlot[1],
    "active-slot verification/suspect guard changed")
local tomeEchoes=view.TomeEchoes(wishlist.entries,{[101]=true,[999]=true})
assert(#tomeEchoes==4 and tomeEchoes[4].spellId==999,
    "designed lock targets were not deduplicated into tome readiness")
print("exact progress, loadout, lock, shed, and tome projection -- OK")

local capture={
    base={cards={{text="card"}},progress=progress,auto=true,version="fixture"},
    status="ready",level=5,
    updateNotice={version="1.2.3"},releaseUrl="https://example.invalid/releases",
    useServerStatus=true,serverStatus={tier="HC3",ash="12000"},
    bestDps={dummy={dps=24},lk={dps=21},info={title="Golden"}},
    performance={dummy={personal={dps=23},global={dps=25}},
        lk={personal={dps=20},global={dps=22}}},
}
local first=view.BuildHudDisplayModel(capture)
assert(first.status=="ready" and first.level==5
    and first.updateNotice.releaseUrl==capture.releaseUrl
    and first.serverStatus.tier=="HC3" and first.bestDps.dummy.dps==24
    and first.progress.performance.dummy.global.dps==25,
    "complete HUD display model changed")
first.cards[1].text="mutated"
first.progress.missing[1]="mutated"
first.serverStatus.tier="mutated"
local second=view.BuildHudDisplayModel(capture)
local stats=view.Stats()
assert(second.cards[1].text=="card"
    and second.progress.missing[1]~="mutated"
    and second.serverStatus.tier=="HC3"
    and stats.builds==2 and stats.rebuilds==1 and stats.skipped==1,
    "cached HUD model leaked caller mutation or missed equal-value reuse")
local shared={value=1}
local aliased=view.BuildHudDisplayModel({base={left=shared,right=shared},status="alias"})
local separate=view.BuildHudDisplayModel({base={left={value=1},right={value=1}},status="alias"})
stats=view.Stats()
assert(aliased.left==aliased.right and separate.left~=separate.right
    and stats.rebuilds==3,
    "HUD cache collapsed distinct table-alias structure")
capture.serverStatus.ash="13000"
local changed=view.BuildHudDisplayModel(capture)
stats=view.Stats()
assert(changed.serverStatus.ash=="13000"
    and stats.builds==5 and stats.rebuilds==4 and stats.skipped==1,
    "in-place captured-value change reused a stale HUD model")
view.NoteRefresh(); view.NoteRefresh()
stats=view.Stats(); stats.skipped=-1
assert(view.Stats().refreshes==2 and view.Stats().skipped==1,
    "HUD statistics are not additive and defensive")
print("immutable HUD snapshots and value-keyed cache reuse -- OK")

local large={cards={},progress={missing={},dpsEchoes={}}}
for index=1,1000 do
    large.cards[index]={text="card-"..index,nested={value=index}}
end
for index=1,500 do
    large.progress.missing[index]="missing-"..index
    large.progress.dpsEchoes[index]={spellId=100000+index,stacks=1}
end
local largeModel=view.BuildHudDisplayModel({base=large,status="large",level=80,
    bestDps={},performance={dummy={},lk={}}})
assert(#largeModel.cards==1000 and #largeModel.progress.missing==500
    and #largeModel.progress.dpsEchoes==500,
    "large HUD fixture was truncated or malformed")
large.cards[1].nested.value=-1
assert(largeModel.cards[1].nested.value==1,
    "large HUD model retained mutable caller input")

local cyclic={}; cyclic.self=cyclic
local cycleBefore=view.Stats()
local cycleFirst=view.BuildHudDisplayModel({base=cyclic,status="cycle"})
local cycleSecond=view.BuildHudDisplayModel({base=cyclic,status="cycle"})
local cycleAfter=view.Stats()
assert(cycleFirst.self==cycleFirst and cycleSecond.self==cycleSecond
    and cycleAfter.rebuilds==cycleBefore.rebuilds+1
    and cycleAfter.skipped==cycleBefore.skipped+1,
    "cyclic defensive HUD snapshots did not reuse safely")

local sourceFile=assert(io.open("core/MainViewModel.lua","r"))
local source=sourceFile:read("*a"); sourceFile:close()
for _, forbidden in ipairs({"Nexus.GameAdapter","NexusDB","ProjectEbonhold",
    "Nexus.DpsCapture","Nexus.ServerStatus","Nexus.Updates","Nexus.Panel",
    "Nexus.Sync"}) do
    assert(not source:find(forbidden,1,true),
        "pure MainViewModel acquired service authority: "..forbidden)
end
print("1000-card/500-row isolation and zero service authority -- OK")
