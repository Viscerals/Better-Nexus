-- Stage 48.4: every progress surface must consume exact spell/tier ownership
-- and keep ordinary and permanently locked quotas independent.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")

local catalog = {
    rows={
        [101]={name="Quick Hands Common",quality=0},
        [102]={name="Quick Hands Rare",quality=2},
        [103]={name="Iron Constitution Epic",quality=3},
    },
    familyOf={[101]=10,[102]=10,[103]=20},
    familyMembers={[10]={101,102},[20]={103}},
    familyName={[10]="Quick Hands",[20]="Iron Constitution"},
}
local entries = {
    {spellId=101,quality=0,stacks=2,family=10,locked=false},
    {spellId=102,quality=2,stacks=1,family=10,locked=false},
    {spellId=103,quality=3,stacks=1,family=20,locked=true},
    {spellId=103,quality=3,stacks=1,family=20,locked=true},
}
local wishlist = {name="Exact",entries=entries,byFamily={
    [10]={targetStacks=3,qualityTiers={
        {spellId=101,q=0,n=2},{spellId=102,q=2,n=1},
    }},
    [20]={targetStacks=2,qualityTiers={
        {spellId=103,q=3,n=2},
    }},
}}
local owned = {bySpell={[101]=2},byFamily={[10]=2},synced=true}
local lockedOwned = {bySpell={[103]=1},byFamily={[20]=1},synced=true}

-- Capture the actual overlay rows. Family ownership contains two Quick Hands
-- copies, but none is the requested Rare tier.
local fontStrings = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local frame = realCreateFrame(...)
    local realCreateFontString = frame.CreateFontString
    frame.CreateFontString = function(self, ...)
        local font = realCreateFontString(self, ...)
        fontStrings[#fontStrings + 1] = font
        return font
    end
    return frame
end

dofile("ui/WishlistOverlay.lua")
local lockedRevision = 1
local Adapter = {
    Wishlist=function() return wishlist end,
    Owned=function() return owned end,
    LockedOwned=function() return lockedOwned end,
    Catalog=function() return catalog end,
    PresentationRevisions=function()
        return 1,1,1,1,1,1,lockedRevision,lockedRevision
    end,
}
NexusDB = {}
Nexus.WishlistOverlay.Init(Adapter, Nexus.Model)
Nexus.WishlistOverlay.Show()

local rareMissing = false
local lockedComplete, lockedMissing = 0, 0
for _, font in ipairs(fontStrings) do
    local text = font.text
    if type(text) == "string" then
        if text:find("Quick Hands Rare",1,true)
            and text:find("[ ]",1,true) then rareMissing = true end
        if text:find("Iron Constitution Epic",1,true)
            and text:find("locked",1,true) then
            if text:find("[X]",1,true) then lockedComplete = lockedComplete + 1 end
            if text:find("[ ]",1,true) then lockedMissing = lockedMissing + 1 end
        end
    end
end
assert(rareMissing,
    "wrong-quality family ownership marked the exact Rare overlay row complete")
assert(lockedComplete == 0 and lockedMissing == 0,
    "duplicate locked quotas were rendered as individually complete/missing")
local lockedPartial = 0
for _, font in ipairs(fontStrings) do
    local text = font.text
    if type(text) == "string" and text:find("Iron Constitution Epic",1,true)
        and text:find("locked",1,true) and text:find("[~]",1,true)
        and text:find("(1/2)",1,true) then
        lockedPartial = lockedPartial + 1
    end
end
assert(lockedPartial == 2,
    "duplicate locked quotas did not share one order-independent exact total")

lockedOwned.bySpell[103] = 2
lockedOwned.byFamily[20] = 2
lockedRevision = lockedRevision + 1
Nexus.WishlistOverlay.Refresh()
local lockedNowComplete = 0
for _, font in ipairs(fontStrings) do
    local text = font.text
    if type(text) == "string" and text:find("Iron Constitution Epic",1,true)
        and text:find("locked",1,true) and text:find("[X]",1,true)
        and text:find("(2/2)",1,true) then
        lockedNowComplete = lockedNowComplete + 1
    end
end
assert(lockedNowComplete == 2,
    "locked-only revision did not refresh exact locked progress")
lockedOwned.bySpell[103] = 1
lockedOwned.byFamily[20] = 1
lockedRevision = lockedRevision + 1
Nexus.WishlistOverlay.Refresh()

local exact = assert(Nexus.Model.WishlistEntryProgress(
    entries, owned, lockedOwned), "shared exact progress projection unavailable")
assert(exact.ordinaryHave == 2 and exact.ordinaryWant == 3
    and exact.lockedHave == 1 and exact.lockedWant == 2
    and exact.rows[2].have == 0 and exact.rows[2].complete == false
    and exact.rows[3].have == 1 and exact.rows[3].want == 2
    and exact.rows[3].complete == false
    and exact.rows[4].have == 1 and exact.rows[4].want == 2
    and exact.rows[4].complete == false,
    "shared exact progress projection collapsed tier or role quotas")

local view = Nexus.MainInternals.ViewModel.New({
    ratchet=Nexus.Ratchet,model=Nexus.Model,
    wishlistModel=Nexus.WishlistModel.New(),
})
local plan = {wishedFamilies={[10]=true,[20]=true},targets=wishlist.byFamily}
local progress = view.BuildProgress({
    plan=plan,owned=owned,lockedOwned=lockedOwned,wishlist=wishlist,
    catalog=catalog,slots={activeSlot=0,bySlot={}},designTargets={},
})
assert(progress.owned == 2 and progress.total == 3
    and progress.lockedOwned == 1 and progress.lockedTotal == 2
    and #progress.missing == 1
    and progress.missing[1]:find("Quick Hands Rare",1,true)
    and #progress.toLock == 1
    and progress.toLock[1]:find("Iron Constitution Epic",1,true),
    "HUD/automation progress disagreed with exact overlay tier and role progress")

local projectionTargets = {
    [101]=true,
    [102]=103,
    [103]={version=2,copies=1,rows={{spellId=103,stacks=1}}},
    [104]={version=1,copies=1,rows={{spellId=103,stacks=1}}},
    [105]={version=1,copies=2,rows={{spellId=105,stacks=1}}},
    [106]="future",
    [1.5]=true,
    [math.huge]=true,
    [-1]=true,
    [999999]=true,
}
local projectedTomes = view.TomeEchoes({}, projectionTargets, catalog)
assert(#projectedTomes == 0,
    "HUD Tome projection partially admitted a malformed target map")
local _, _, _, projectedLocks = view.WishlistProgress(
    {wishedFamilies={},targets={}},
    {bySpell={},byFamily={},synced=true}, catalog, {},
    {bySpell={},byFamily={},synced=true}, projectionTargets, nil)
local projectedText = table.concat(projectedLocks, "|")
assert(#projectedLocks == 0,
    "HUD progress partially admitted a malformed target map: "
        .. projectedText)
local validProjectionTargets = {[101]=true,[102]=103}
projectedTomes = view.TomeEchoes({}, validProjectionTargets, catalog)
local projectedTomeIds = {}
for _, row in ipairs(projectedTomes) do projectedTomeIds[row.spellId] = true end
local _, _, _, validProjectedLocks = view.WishlistProgress(
    {wishedFamilies={},targets={}},
    {bySpell={},byFamily={},synced=true}, catalog, {},
    {bySpell={},byFamily={},synced=true}, validProjectionTargets, nil)
assert(#projectedTomes == 2 and projectedTomeIds[101]
        and projectedTomeIds[102] and #validProjectedLocks == 2,
    "HUD projection dropped a fully valid legacy target map")

-- An exact Rare copy completes only the Rare ordinary row; surplus Common
-- copies still cannot be borrowed by either the Rare or locked role.
owned.bySpell[102] = 1
local refreshed = Nexus.Model.WishlistEntryProgress(entries, owned, lockedOwned)
assert(refreshed.ordinaryHave == 3 and refreshed.ordinaryWant == 3
    and refreshed.rows[2].complete == true
    and refreshed.lockedHave == 1 and refreshed.lockedWant == 2,
    "exact refresh changed the independent locked quota")

-- Exact automation authority uses spell ID, not a pooled quality bucket.
-- Same-quality siblings cannot lend one owned copy to two exact quotas, and a
-- represented one-tier low-quality target is not silently escalated to peak.
local exactPlan = Nexus.Strategy.Compile(catalog, {
    entries={
        {spellId=101,quality=0,stacks=1,family=10},
        {spellId=102,quality=2,stacks=1,family=10},
    },
    byFamily={[10]={targetStacks=2,qualityTiers={
        {spellId=101,q=0,n=1},{spellId=102,q=2,n=1},
    }}},
}, {})
local exactHave, exactWant = Nexus.Model.TargetProgress(
    exactPlan, catalog, 10, {bySpell={[101]=2},byFamily={[10]=2}})
assert(exactHave == 1 and exactWant == 2
        and Nexus.Model.Delta(exactPlan,
            {bySpell={[101]=2},byFamily={[10]=2}}, 102, catalog, {}) > 0,
    "same-family ownership was reused across exact automation tiers")
local lowOnlyPlan = Nexus.Strategy.Compile(catalog, {
    entries={{spellId=101,quality=0,stacks=1,family=10}},
    byFamily={[10]={targetStacks=1,qualityTiers={
        {spellId=101,q=0,n=1},
    }}},
}, {})
assert(Nexus.Model.TargetProgress(lowOnlyPlan, catalog, 10,
        {bySpell={[101]=1},byFamily={[10]=1}}) == 1
    and Nexus.Model.Delta(lowOnlyPlan,
        {bySpell={},byFamily={}}, 101, catalog, {}) > 0,
    "one-tier exact automation target fell back to peak-quality semantics")

-- Partial locked evidence is diagnostic only. Policy must not merge it into
-- authoritative owned state and skip the still-needed target offer.
local policy = Nexus.Policy.Decide({
    board={cards={
        {spellId=101,quality=0,family=10},
        {spellId=999,quality=0,family=99},
    },signature="unsynced-lock"},
    owned={bySpell={},byFamily={},synced=true,distinct=0},
    locked={bySpell={[101]=1},byFamily={[10]=1},synced=false},
    charges={banish=0,reroll=0,trustworthy=true},
    plan={wishedFamilies={[10]=true},targets={
        [10]={targetStacks=1,wishedQuality=0},
    }},catalog={
        rows={
            [101]={name="Quick Hands Common",quality=0,maxStack=1},
            [999]={name="Filler",quality=0,maxStack=1},
        },
        familyOf={[101]=10,[999]=99},
        familyMembers={[10]={101},[99]={999}},
    },
    level=40,params=Nexus.DefaultProfile.params,
})
assert(policy.type == "take" and policy.spellId == 101,
    "Policy consumed partial unsynced locked evidence as authority")

local nonfinitePolicy = Nexus.Policy.Decide({
    board={cards={
        {spellId=101,quality=0,family=10},
        {spellId=999,quality=0,family=99},
    },signature="nonfinite-lock"},
    owned={bySpell={},byFamily={},synced=true,distinct=0},
    locked={bySpell={[math.huge]=1},byFamily={[10]=1},synced=true},
    charges={banish=0,reroll=0,trustworthy=true},
    plan={wishedFamilies={[10]=true},targets={
        [10]={targetStacks=1,wishedQuality=0},
    }},catalog={
        rows={
            [101]={name="Quick Hands Common",quality=0,maxStack=1},
            [999]={name="Filler",quality=0,maxStack=1},
        },
        familyOf={[101]=10,[999]=99},
        familyMembers={[10]={101},[99]={999}},
    },
    level=40,params=Nexus.DefaultProfile.params,
})
assert(nonfinitePolicy.type == "take" and nonfinitePolicy.spellId == 101,
    "Policy consumed a nonfinite locked spell identity as authority")

local contradictoryPolicy = Nexus.Policy.Decide({
    board={cards={
        {spellId=101,quality=0,family=10},
        {spellId=999,quality=0,family=99},
    },signature="contradictory-lock"},
    owned={bySpell={},byFamily={},synced=true,distinct=0},
    locked={bySpell={[999]=1},byFamily={[10]=1},synced=true},
    charges={banish=0,reroll=0,trustworthy=true},
    plan={wishedFamilies={[10]=true},targets={
        [10]={targetStacks=1,wishedQuality=0},
    }},catalog={
        rows={
            [101]={name="Quick Hands Common",quality=0,maxStack=1},
            [999]={name="Filler",quality=0,maxStack=1},
        },
        familyOf={[101]=10,[999]=99},
        familyMembers={[10]={101},[99]={999}},
    },
    level=40,params=Nexus.DefaultProfile.params,
})
assert(contradictoryPolicy.type == "take"
        and contradictoryPolicy.spellId == 101,
    "Policy consumed contradictory locked family evidence as authority")

local aliasedPolicy = Nexus.Policy.Decide({
    board={cards={
        {spellId=101,quality=0,family=10},
        {spellId=999,quality=0,family=99},
    },signature="aliased-lock"},
    owned={bySpell={},byFamily={},synced=true,distinct=0},
    locked={bySpell={[101]=1,["101"]=1},byFamily={[10]=2},synced=true},
    charges={banish=0,reroll=0,trustworthy=true},
    plan={wishedFamilies={[10]=true},targets={
        [10]={targetStacks=1,wishedQuality=0},
    }},catalog={
        rows={
            [101]={name="Quick Hands Common",quality=0,maxStack=1},
            [999]={name="Filler",quality=0,maxStack=1},
        },
        familyOf={[101]=10,[999]=99},
        familyMembers={[10]={101},[99]={999}},
    },
    level=40,params=Nexus.DefaultProfile.params,
})
assert(aliasedPolicy.type == "take" and aliasedPolicy.spellId == 101,
    "Policy merged canonical aliases in locked evidence")

local capacityCatalog = {
    rows={
        [101]={name="Quick Hands Common",quality=0,maxStack=1},
        [999]={name="Filler",quality=0,maxStack=1},
        [997]={name="Other A",quality=0,maxStack=2},
        [998]={name="Other B",quality=0,maxStack=2},
        [996]={name="Overflow",quality=0,maxStack=1},
    },
    familyOf={[101]=10,[999]=99,[997]=97,[998]=98,[996]=96},
    familyMembers={[10]={101},[99]={999},[97]={997},[98]={998},[96]={996}},
}
assert(Nexus.Model.LockedProjection({
        synced=true,bySpell={[101]=0},byFamily={[10]=0},
    },capacityCatalog,6) == nil,
    "shared locked projection accepted a zero-count spell row")
local capacityState = {
    board={cards={
        {spellId=101,quality=0,family=10},
        {spellId=999,quality=0,family=99},
    },signature="six-locks"},
    owned={bySpell={},byFamily={},synced=true,distinct=0},
    locked={bySpell={[101]=1,[999]=1,[997]=2,[998]=2},
        byFamily={[10]=1,[99]=1,[97]=2,[98]=2},synced=true},
    charges={banish=0,reroll=0,trustworthy=true},
    plan={wishedFamilies={[10]=true},targets={
        [10]={targetStacks=1,wishedQuality=0},
    }},catalog=capacityCatalog,level=40,params=Nexus.DefaultProfile.params,
}
local realDelta, observedLocked = Nexus.Model.Delta, {}
Nexus.Model.Delta = function(currentPlan, currentOwned, spellId,
    currentCatalog, params)
    observedLocked[#observedLocked + 1] =
        tonumber(currentOwned and currentOwned.bySpell
            and currentOwned.bySpell[101]) or 0
    return realDelta(currentPlan, currentOwned, spellId, currentCatalog, params)
end
local sixCopyPolicy = Nexus.Policy.Decide(capacityState)
assert(sixCopyPolicy.type == "take" and observedLocked[1] == 1,
    "Policy rejected coherent six-copy locked evidence")
capacityState.board.signature = "seven-locks"
capacityState.locked.bySpell[996] = 1
capacityState.locked.byFamily[96] = 1
observedLocked = {}
local sevenCopyPolicy = Nexus.Policy.Decide(capacityState)
Nexus.Model.Delta = realDelta
assert(sevenCopyPolicy.type == "take" and sevenCopyPolicy.spellId == 101
        and observedLocked[1] == 0,
    "Policy trusted seven-copy locked evidence")

print("exact Wishlist progress: tiers=independent roles=independent duplicates=allocated -- OK")
