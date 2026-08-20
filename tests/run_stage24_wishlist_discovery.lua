-- Stage 24.1 expected red: explicit all-false lock rows are structurally valid
-- server identities. At 80-85 entries they must remain passively visible as
-- awaiting evidence even though every action continues to fail closed.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds={},
    buildFilters={},dpsCapture={},futureRoot={keep=true},
}
Nexus.Store.Init()
local Store, A = Nexus.Store, Nexus.GameAdapter
A.Init({}, Store)
H.playerLevel = 80

for index = 1, 86 do
    H.AddEcho(270000 + index, "Structural Fixture " .. index,
        {quality=index % 4})
end

local function Rows(count)
    local out = {}
    for index = 1, count do
        out[index] = {
            spellId=270000 + index,quality=index % 4,
            stacks=1,locked=false,
        }
    end
    return out
end

local function FindCandidate(key)
    for _, candidate in ipairs(A.GetWishlistCandidates()) do
        if candidate.key == key then return candidate end
    end
end

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

local state = Store.State()
for _, count in ipairs({80, 85}) do
    local echoes = Rows(count)
    local key = assert(A.WishlistKey(echoes))
    local slot = 100 + count
    state.loadoutWishlists[1] = nil
    state.pendingRelay = nil
    local association = {
        slot=slot,name="Structural Candidate " .. count,key=key,
        futureAssociationField={keep=true},
    }

    -- A same-title Community record is deliberately not server authority.
    NexusDB.communityBuilds["remote-" .. count] = {
        id="remote-" .. count,title=association.name,author="RemoteFixture",
        class="MAGE",echoes=Rows(79),postedAt=1,lastModified=1,
    }
    H.DeliverSlots({
        [1]={slot=1,name="Active Fixture",verified=true,
            echoes={{spellId=200100,quality=3,stacks=1}}},
        [slot]={slot=slot,name=association.name,verified=false,echoes=echoes},
    }, 1)

    local raw = assert(A.Slots().bySlot[slot],
        "structurally valid raw slot disappeared before discovery")
    assert(raw.echoes[1].locked == false,
        "explicit false lock evidence was not preserved")
    local standaloneCandidate = FindCandidate(key)
    Expect("all_false_" .. count .. "_visible",
        standaloneCandidate and #standaloneCandidate.echoes == count,
        "candidate disappeared before action validation")
    Expect("all_false_" .. count .. "_awaits_evidence",
        standaloneCandidate
            and standaloneCandidate.lockEvidenceStatus == "unavailable",
        "candidate was not labeled awaiting lock evidence")

    -- Add a durable association only after the standalone discovery check so
    -- stored fallback cannot conceal a live candidate being discarded.
    state.loadoutWishlists[1] = association
    state.pendingRelay = {
        sourceSlot=1,targetSlot=2,wishlistSlot=slot,wishlistKey=key,
        futureRelayField={keep=true},
    }
    local relay = state.pendingRelay
    local candidate = FindCandidate(key)
    local resolved = A.Wishlist()
    Expect("all_false_" .. count .. "_tracking_stays_pending",
        resolved == nil and tostring(A.WishlistNote()):find(
            "lock evidence", 1, true),
        "candidate became authoritative or lost its pending reason")

    local beforeAssociation, beforeRelay = state.loadoutWishlists[1],
        state.pendingRelay
    local ok, err = A.SetLoadoutWishlist(1, slot, candidate or {
        slot=slot,name=association.name,key=key,echoes=echoes,
        lockEvidenceStatus="unavailable",
    })
    assert(ok == false and (err == "invalid wishlist"
            or tostring(err):find("evidence", 1, true)),
        "all-false over-79 candidate gained action authority")
    assert(state.loadoutWishlists[1] == beforeAssociation
        and beforeAssociation.futureAssociationField.keep
        and state.pendingRelay == beforeRelay
        and beforeRelay.futureRelayField.keep
        and #H.saveCalls == 0 and #H.activateCalls == 0
        and NexusDB.futureRoot.keep,
        "passive discovery/action check rewrote state or mutated the character")
end

-- Adversarial edges: the passive exception must not demote a valid ordinary
-- 79-row Wishlist, a valid 79-plus-one locked design, or admit total 86.
state.loadoutWishlists[1] = nil
state.pendingRelay = nil
local exact79 = Rows(79)
local exact79Key = assert(A.WishlistKey(exact79))
H.DeliverSlots({
    [1]={slot=1,name="Active Fixture",verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}}},
    [179]={slot=179,name="Exact 79",verified=false,echoes=exact79},
}, 1)
local exact79Candidate = assert(FindCandidate(exact79Key),
    "all-false exact-79 candidate disappeared")
assert(exact79Candidate.lockEvidenceVersion == 1
    and exact79Candidate.lockEvidenceStatus == nil,
    "valid exact-79 ordinary evidence was demoted to pending")

local mixed80 = Rows(80)
mixed80[80].locked = true
local mixed80Key = assert(A.WishlistKey(mixed80))
H.DeliverSlots({
    [1]={slot=1,name="Active Fixture",verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}}},
    [180]={slot=180,name="79 Plus One",verified=false,echoes=mixed80},
}, 1)
local mixed80Candidate = assert(FindCandidate(mixed80Key),
    "authoritative 79-plus-one candidate disappeared")
assert(mixed80Candidate.lockEvidenceVersion == 1
    and mixed80Candidate.lockEvidenceStatus == nil,
    "authoritative 79-plus-one candidate was demoted to pending")
local mixedOk, mixedErr = A.SetLoadoutWishlist(
    1, mixed80Candidate.slot, mixed80Candidate)
assert(mixedOk and mixedErr == nil,
    "authoritative 79-plus-one candidate lost action authority")

state.loadoutWishlists[1] = nil
local over86 = Rows(86)
local over86Key = assert(A.WishlistKey(over86))
H.DeliverSlots({
    [1]={slot=1,name="Active Fixture",verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}}},
    [186]={slot=186,name="Over 85",verified=false,echoes=over86},
}, 1)
assert(FindCandidate(over86Key) == nil,
    "all-false total-86 identity escaped the structural bound")
assert(NexusDB.futureRoot.keep,
    "adversarial boundary checks rewrote unknown SavedVariables")

if #failures > 0 then
    error("EXPECTED RED: Stage 24 Wishlist discovery characterization:\n - "
        .. table.concat(failures, "\n - "))
end

print("Stage 24 all-false Wishlist discovery remains visible and inert -- OK")
