-- Stage 48.4: every progress surface must consume exact spell/tier ownership
-- and keep ordinary and permanently locked quotas independent.
local H = dofile("tests/harness.lua")
dofile("logic/Model.lua")
dofile("logic/Ratchet.lua")
dofile("core/MainViewModel.lua")

local catalog = {
    rows={
        [101]={name="Quick Hands Common",quality=0},
        [102]={name="Quick Hands Rare",quality=2},
        [103]={name="Iron Constitution Epic",quality=3},
    },
    familyOf={[101]=10,[102]=10,[103]=20},
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

-- An exact Rare copy completes only the Rare ordinary row; surplus Common
-- copies still cannot be borrowed by either the Rare or locked role.
owned.bySpell[102] = 1
local refreshed = Nexus.Model.WishlistEntryProgress(entries, owned, lockedOwned)
assert(refreshed.ordinaryHave == 3 and refreshed.ordinaryWant == 3
    and refreshed.rows[2].complete == true
    and refreshed.lockedHave == 1 and refreshed.lockedWant == 2,
    "exact refresh changed the independent locked quota")

print("exact Wishlist progress: tiers=independent roles=independent duplicates=allocated -- OK")
