-- Stage 48.3: a verified active total may authorize roles for only its exact
-- associated designed mirror, using authoritative locked-count agreement.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

NexusDB = {}
Nexus.Store.Init()
local A = Nexus.GameAdapter
A.Init({}, Nexus.Store)

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Signature(value, seen)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[value] = nil
    return table.concat(out)
end

local activeEchoes = {
    {spellId=200110,quality=0,stacks=40,locked=false},
    {spellId=200112,quality=2,stacks=39,locked=false},
    {spellId=200110,quality=0,stacks=2,locked=true},
    {spellId=200100,quality=3,stacks=2,locked=true},
    {spellId=200104,quality=2,stacks=2,locked=true},
}
local designedEchoes = H.CloneValue(activeEchoes)
for _, row in ipairs(designedEchoes) do row.locked = false end
local mismatchEchoes = H.CloneValue(designedEchoes)
mismatchEchoes[1].stacks = 39
mismatchEchoes[#mismatchEchoes + 1] = {
    spellId=200200,quality=1,stacks=1,locked=false,
}

H.DeliverSlots({
    [1]={slot=1,name="Exact",verified=true,echoes=activeEchoes},
    -- Another verified copy with the same title is never the authority for
    -- active slot 1.
    [2]={slot=2,name="Exact",verified=true,echoes=mismatchEchoes},
    [102]={slot=102,name="Exact",verified=false,echoes=designedEchoes},
    [103]={slot=103,name="Exact",verified=false,echoes=mismatchEchoes},
}, 1)
H.locked = {
    {spellId=200110,quality=0,stacks=2},
    {spellId=200100,quality=3,stacks=2},
    {spellId=200104,quality=2,stacks=2},
}

local designedKey = assert(A.WishlistKey(designedEchoes))
local state = Nexus.Store.State()
state.loadoutWishlists = {
    [1]={slot=102,name="Exact",key=designedKey,future={keep=true}},
}
local saved = state.loadoutWishlists[1]
local before = Signature({slots=H.Perks.serverBuildSlots,locked=H.locked,saved=saved})

local wishlist = A.Wishlist()
Check(wishlist and wishlist.source == "loadout-association"
        and #wishlist.entries == 5,
    "exact active/associated mirror remained evidence-pending")
local ordinary, locked = 0, 0
local rolesBySpell = {}
for _, row in ipairs(wishlist.entries) do
    if row.locked then locked = locked + row.stacks else ordinary = ordinary + row.stacks end
    rolesBySpell[row.spellId] = rolesBySpell[row.spellId] or {}
    rolesBySpell[row.spellId][row.locked and "locked" or "ordinary"] = true
end
Check(ordinary == 79 and locked == 6,
    "exact active total did not derive 79 ordinary plus six locked copies")
Check(rolesBySpell[200110].ordinary and rolesBySpell[200110].locked,
    "one exact tier could not retain both ordinary and locked roles")
Check(wishlist.entries[1].quality == 0 and wishlist.entries[2].quality == 2,
    "same-family exact quality siblings were collapsed during derivation")

local diagnosed, evidenceState = A.GetLoadoutWishlistState(1)
Check(diagnosed and evidenceState == "actionable",
    "read-only association diagnosis disagreed with Wishlist resolution")
Check(A.GetLoadoutWishlist(1) ~= nil,
    "exact loadout Wishlist reader remained unavailable")
Check(Signature({slots=H.Perks.serverBuildSlots,locked=H.locked,saved=saved}) == before
        and state.loadoutWishlists[1] == saved and saved.future.keep,
    "role derivation mutated server mirrors or SavedVariables evidence")

-- Reload/re-init converges from the same durable exact association.
Nexus.Store.Init()
Check(A.Wishlist() and Nexus.Store.State().loadoutWishlists[1] == saved,
    "exact bridge did not converge across Store reload")

-- A one-copy identity mismatch, despite equal title and nearby slots, cannot
-- receive active authority.
saved.slot, saved.key = 103, assert(A.WishlistKey(mismatchEchoes))
local mismatchBefore = Signature(saved)
Check(A.Wishlist() == nil and Signature(saved) == mismatchBefore,
    "title/slot proximity or approximate identity authorized a mismatch")

saved.slot, saved.key = 102, designedKey
local lockedBefore = H.locked
H.locked = {
    {spellId=200110,stacks=2}, {spellId=200100,stacks=2},
}
Check(A.Wishlist() == nil,
    "partial authoritative locked counts authorized the active mirror")
H.locked = {
    {spellId=200110,stacks=3}, {spellId=200100,stacks=2},
    {spellId=200104,stacks=2},
}
Check(A.Wishlist() == nil,
    "seven/underflowing locked copies authorized the active mirror")
H.locked = lockedBefore

local activeLock = H.Perks.serverBuildSlots[1].echoes[3]
activeLock.locked = nil
Check(A.Wishlist() == nil,
    "partial active lock booleans authorized role derivation")
activeLock.locked = true
Check(A.Wishlist() ~= nil,
    "exact bridge did not recover after authoritative evidence returned")

print(string.format(
    "active Wishlist lock bridge: ordinary=79 locked=6 overlap=yes mismatch/partial/underflow=closed checks=%d -- OK",
    checks))
