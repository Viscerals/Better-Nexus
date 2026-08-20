-- Stage 21.1 expected red: authoritative locked-target evidence must permit a
-- designed 79+6 Wishlist without weakening ordinary capacity or stable identity.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

local realCreateFrame = CreateFrame
local created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._kind, frame._name = kind, name
    frame._parent, frame._template = parent, template
    created[#created + 1] = frame
    return frame
end

dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")
dofile("ui/JournalTab.lua")

NexusDB = {
    settingsVersion=2, settings={}, chars={}, communityBuilds={},
    buildFilters={}, dpsCapture={}, futureRoot={keep=true},
}
UISpecialFrames = {}
Nexus.Store.Init()
local Store, A = Nexus.Store, Nexus.GameAdapter
A.Init({}, Store)
H.playerLevel = 80

local function Design(ordinary, locked)
    local rows = {}
    for index = 1, ordinary do
        rows[#rows + 1] = {
            spellId=210000 + index, quality=index % 4, stacks=1,
            locked=false,
        }
    end
    for index = 1, locked do
        rows[#rows + 1] = {
            spellId=220000 + index, quality=3, stacks=1, locked=true,
        }
    end
    return rows
end

local legitimate = Design(79, 6)
local legitimateKey = assert(A.WishlistKey(legitimate))
local loadouts = {
    [1]={slot=1,name="Synthetic One",verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}}},
    [2]={slot=2,name="Synthetic Two",verified=true,
        echoes={{spellId=200102,quality=2,stacks=1}}},
    [3]={slot=3,name="Synthetic Three",verified=true,
        echoes={{spellId=200104,quality=2,stacks=1}}},
}
local designed = {
    slot=102,name="Synthetic Designed Target",verified=false,
    echoes=legitimate,
}

local function SlotsWith(candidate)
    local rows = {}
    for slot, row in pairs(loadouts) do rows[slot] = row end
    if candidate then rows[candidate.slot] = candidate end
    return rows
end

H.DeliverSlots(SlotsWith(designed), 1)
local state = Store.State()
for slot = 1, 3 do
    state.loadoutWishlists[slot] = {
        slot=102, name="Synthetic Designed Target", key=legitimateKey,
        futureAssociationField={keep=true},
    }
end
state.pendingRelay = {
    sourceSlot=1, targetSlot=3, wishlistSlot=102,
    wishlistKey=legitimateKey, futureRelayField={keep=true},
}
local associationRefs = {
    state.loadoutWishlists[1], state.loadoutWishlists[2],
    state.loadoutWishlists[3],
}
local relayRef = state.pendingRelay

local function LockedCount(rows)
    local count = 0
    for _, row in ipairs(rows or {}) do
        if row.locked then count = count + (tonumber(row.stacks) or 1) end
    end
    return count
end

-- Exact authoritative live content recovers all three legacy key-only links.
for slot = 1, 3 do
    local linked = assert(A.GetLoadoutWishlist(slot),
        "authoritative 85-entry candidate did not recover association " .. slot)
    assert(linked.key == legitimateKey and #linked.echoes == 85
        and LockedCount(linked.echoes) == 6,
        "authoritative locked evidence changed during association recovery")
end

-- Missing/partial mirrors retain association and relay identity without
-- presenting guessed unlocked content as valid.
H.DeliverSlots(SlotsWith({
    slot=103,name="Unrelated Partial",verified=false,
    echoes={{spellId=230001,quality=1,stacks=1}},
}), 1)
for slot = 1, 3 do
    assert(A.GetLoadoutWishlist(slot) == nil
        and state.loadoutWishlists[slot] == associationRefs[slot]
        and associationRefs[slot].futureAssociationField.keep,
        "partial mirror rewrote or guessed association " .. slot)
end
assert(A.Wishlist() == nil
    and tostring(A.WishlistNote()):find("temporarily unavailable", 1, true),
    "missing authoritative evidence reported a vague or destructive state")
assert(state.pendingRelay == relayRef and relayRef.wishlistKey == legitimateKey
    and relayRef.futureRelayField.keep,
    "partial mirror discarded or rewrote pending relay identity")
H.DeliverSlots(SlotsWith(designed), 1)
assert(A.GetLoadoutWishlist(1)
    and A.GetLoadoutWishlist(1).key == legitimateKey,
    "authoritative candidate did not recover after partial mirror")

local function Candidate(slot, name, rows, key)
    return {slot=slot,name=name,echoes=rows,key=key or A.WishlistKey(rows)}
end

-- Negative capacity and malformed boundaries stay rejected.
local ok, err = A.SetLoadoutWishlist(1, 201,
    Candidate(201, "80 Ordinary", Design(80, 0)))
assert(ok == false and err == "invalid wishlist",
    "80 ordinary copies became valid")
ok, err = A.SetLoadoutWishlist(1, 202,
    Candidate(202, "Seven Locked", Design(78, 7)))
assert(ok == false and err == "invalid wishlist",
    "more than six locked targets became valid")
ok, err = A.SetLoadoutWishlist(1, 203,
    Candidate(203, "Over Combined", Design(80, 6)))
assert(ok == false and err == "invalid wishlist",
    "more than the combined 85-entry envelope became valid")
ok, err = A.SetLoadoutWishlist(1, 204, {
    slot=204,name="Malformed",key="bad",
    echoes={{spellId=0,quality=1,stacks=1}},
})
assert(ok == false and err == "invalid wishlist",
    "malformed spell ID or forged key became valid")
ok, err = A.SetLoadoutWishlist(1, 205, {
    slot=205,name="Malformed Stack",key="250000:1",
    echoes={{spellId=250000,quality=1,stacks="not-a-count"}},
})
assert(ok == false and err == "invalid wishlist",
    "malformed stack value became valid")
local sparse = Candidate(205, "Sparse", Design(2, 0))
sparse.echoes[1] = nil
ok, err = A.SetLoadoutWishlist(1, 205, sparse)
assert(ok == false and err == "invalid wishlist",
    "sparse Wishlist array became valid")

-- Exact 79 remains valid, and its immutable content still rejects slot reuse.
local exact = Candidate(206, "Exact Ordinary", Design(79, 0))
ok, err = A.SetLoadoutWishlist(1, 206, exact)
assert(ok and err == nil, "exactly 79 ordinary copies became invalid")
H.DeliverSlots(SlotsWith({
    slot=206,name="Recycled",verified=false,
    echoes={{spellId=240001,quality=1,stacks=1}},
}), 1)
ok, err = A.SetLoadoutWishlist(1, 206, exact)
assert(ok == false and err == "wishlist changed; refresh and try again",
    "recycled slot overrode immutable Wishlist identity")
H.DeliverSlots(SlotsWith(designed), 1)

-- Passive diagnostic mode must not mutate the prior association or relay.
local beforePassive = state.loadoutWishlists[1]
A.DIAGNOSTIC_PASSIVE = true
ok = A.SetLoadoutWishlist(1, 102,
    Candidate(102, designed.name, legitimate, legitimateKey))
A.DIAGNOSTIC_PASSIVE = nil
assert(ok == false and state.loadoutWishlists[1] == beforePassive
    and state.pendingRelay == relayRef,
    "passive association path mutated character or relay state")

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

-- Real controller path: this is the named expected red on current test.6.
state.loadoutWishlists[1] = associationRefs[1]
local controller = Nexus.WishlistInternals.Controller.New({
    model=Nexus.WishlistModel.New(), store=Store,
    accountRoot=function() return NexusDB end,
    notify=function() end,
})
controller.Initialize(A)
local rendered = nil
for _, candidate in ipairs(A.GetWishlistCandidates()) do
    if candidate.key == legitimateKey then rendered = candidate end
end
assert(rendered, "real GameAdapter did not expose authoritative candidate")
ok, err = controller.AssociateCandidate(rendered)
Expect("legitimate_79_plus_6_controller", ok == true,
    "returned " .. tostring(err or ok) .. " instead of associating bounded locked evidence")
Expect("authoritative_lock_evidence_persisted",
    state.loadoutWishlists[1]
        and state.loadoutWishlists[1].lockEvidenceVersion == 1
        and #state.loadoutWishlists[1].echoes == 85
        and LockedCount(state.loadoutWishlists[1].echoes) == 6,
    "explicit association did not preserve versioned locked-target evidence")
local persistedEvidence = state.loadoutWishlists[1]
H.DeliverSlots(SlotsWith({
    slot=103,name="Unrelated Partial",verified=false,
    echoes={{spellId=230001,quality=1,stacks=1}},
}), 1)
local offlinePersisted = A.GetLoadoutWishlist(1)
Expect("persisted_evidence_survives_missing_mirror",
    offlinePersisted and offlinePersisted.key == legitimateKey
        and #offlinePersisted.echoes == 85
        and LockedCount(offlinePersisted.echoes) == 6
        and state.loadoutWishlists[1] == persistedEvidence,
    "versioned evidence was dropped or rewritten without a live mirror")
H.DeliverSlots(SlotsWith(designed), 1)

local forgedEvidence = Design(79, 6)
forgedEvidence[#forgedEvidence].locked = nil
ok, err = A.SetLoadoutWishlist(1, 207, {
    slot=207, name="Incomplete Evidence", key=A.WishlistKey(forgedEvidence),
    echoes=forgedEvidence, lockEvidenceVersion=1,
})
Expect("incomplete_versioned_evidence_rejected",
    ok == false and err == "invalid wishlist"
        and state.loadoutWishlists[1] == persistedEvidence,
    "version marker admitted incomplete or non-authoritative lock flags")

-- Real Wishlist renderer path: the rendered candidate button already carries
-- the immutable candidate, but GameAdapter rejects its complete 85-entry body.
state.loadoutWishlists = {}
Nexus.Panel = {AttachMenuFrame=function() end,CloseOtherWindows=function() end}
Nexus.Theme = {StyleWindow=function() end,StyleTree=function() end}
local Editor = Nexus.WishlistEditor
Editor.Init(A, Nexus.Model)
Editor.Show()
local rendererCandidateButton
local rendererButtonTexts = {}
for _, frame in ipairs(created) do
    if frame._kind == "Button" and type(frame.text) == "string"
        and frame.text ~= "" then
        rendererButtonTexts[#rendererButtonTexts + 1] = frame.text
    end
    if frame._kind == "Button"
        and type(frame.text) == "string"
        and frame.text:find("Synthetic Designed Target", 1, true) then
        rendererCandidateButton = frame
    end
end
if rendererCandidateButton and rendererCandidateButton:GetScript("OnClick") then
    rendererCandidateButton:GetScript("OnClick")(rendererCandidateButton)
end
Expect("legitimate_79_plus_6_renderer",
    state.loadoutWishlists[1] and state.loadoutWishlists[1].key == legitimateKey,
    rendererCandidateButton and "candidate click ended without bounded association"
        or ("real renderer did not bind the authoritative candidate; buttons="
            .. table.concat(rendererButtonTexts, ",")))

-- Real Journal loadout button: render candidate A, recycle its numeric slot,
-- then click. The captured immutable candidate must reject the replacement.
state.loadoutWishlists = {}
local journal = CreateFrame("Frame", "ProjectEbonholdEchoJournal", UIParent)
journal:Show()
H.DeliverSlots(SlotsWith(designed), 1)
Nexus.JournalTab.RefreshAssociations()
local selector = assert(_G.NexusActiveWishlistSelector,
    "Journal association selector was not assembled")
selector:GetScript("OnClick")(selector)
local picker = assert(_G.NexusWishlistOnlyPicker,
    "Journal Wishlist picker was not assembled")
local function FindJournalCandidateButton()
    for _, frame in ipairs(created) do
        if frame._kind == "Button" and frame._parent
            and frame._parent._parent == picker
            and type(frame.text) == "table"
            and tostring(frame.text.text or ""):find(
                "Synthetic Designed Target", 1, true) then
            return frame
        end
    end
end
local journalCandidate = assert(FindJournalCandidateButton(),
    "Journal did not render the authoritative candidate")
local realSetLoadoutWishlist = A.SetLoadoutWishlist
local realSetFirstRunWishlist = A.SetFirstRunWishlist
local loadoutCalls, firstRunCalls = 0, 0
A.SetLoadoutWishlist = function(...)
    loadoutCalls = loadoutCalls + 1
    return realSetLoadoutWishlist(...)
end
A.SetFirstRunWishlist = function(...)
    firstRunCalls = firstRunCalls + 1
    return realSetFirstRunWishlist(...)
end
H.DeliverSlots(SlotsWith({
    slot=102,name="Recycled Journal Slot",verified=false,
    echoes={{spellId=250001,quality=1,stacks=1}},
}), 1)
journalCandidate:GetScript("OnClick")(journalCandidate)
Expect("journal_loadout_click_identity",
    state.loadoutWishlists[1] == nil and loadoutCalls == 1
        and firstRunCalls == 0,
    "numeric slot selected recycled content after mirror churn")

-- Repeat the same real button path for first-run assignment.
state.loadoutWishlists = {}
state.firstRunWishlist = nil
H.DeliverSlots({[102]=designed}, 0)
Nexus.JournalTab.RefreshAssociations()
if picker:IsShown() then selector:GetScript("OnClick")(selector) end
selector:GetScript("OnClick")(selector)
journalCandidate = assert(FindJournalCandidateButton(),
    "Journal first-run candidate was not rendered")
H.DeliverSlots({
    [102]={slot=102,name="Recycled First Run",verified=false,
        echoes={{spellId=250002,quality=1,stacks=1}}},
}, 0)
journalCandidate:GetScript("OnClick")(journalCandidate)
Expect("journal_first_run_click_identity",
    state.firstRunWishlist == nil and loadoutCalls == 1
        and firstRunCalls == 1,
    "numeric slot selected recycled first-run content after mirror churn")
A.SetLoadoutWishlist = realSetLoadoutWishlist
A.SetFirstRunWishlist = realSetFirstRunWishlist

assert(state.pendingRelay == relayRef and relayRef.wishlistKey == legitimateKey,
    "expected-red actions discarded pending relay")
assert(NexusDB.futureRoot.keep, "characterization damaged unknown SavedVariables")

if #failures > 0 then
    error(string.format("Stage 21.1 expected red (%d): %s",
        #failures, table.concat(failures, " | ")))
end
print("Stage 21 Wishlist evidence and Journal identity characterization -- OK")
