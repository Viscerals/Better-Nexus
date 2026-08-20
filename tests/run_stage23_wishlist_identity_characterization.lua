-- Stage 23.1 expected red: a server Wishlist whose raw rows omit per-Echo
-- lock flags must remain a visible, identity-only candidate while actions
-- fail closed until exact authoritative lock evidence arrives.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

local realCreateFrame = CreateFrame
local created, regions = {}, {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._kind, frame._name = kind, name
    frame._parent, frame._template = parent, template
    local realCreateFontString = frame.CreateFontString
    frame.CreateFontString = function(self, ...)
        local region = realCreateFontString(self, ...)
        regions[#regions + 1] = region
        return region
    end
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

local function AddSyntheticCatalog()
    for index = 1, 79 do
        H.AddEcho(260000 + index, "Identity Ordinary " .. index,
            {quality=index % 4})
    end
    for index = 1, 7 do
        H.AddEcho(261000 + index, "Identity Locked " .. index,
            {quality=3})
    end
end
AddSyntheticCatalog()

local function Design(ordinary, locked, lockShape)
    local rows = {}
    for index = 1, ordinary do
        local row = {
            spellId=260000 + index, quality=index % 4, stacks=1,
        }
        if lockShape == "explicit" then row.locked = false end
        rows[#rows + 1] = row
    end
    for index = 1, locked do
        local row = {
            spellId=261000 + index, quality=3, stacks=1,
        }
        if lockShape == "explicit" then row.locked = true end
        rows[#rows + 1] = row
    end
    return rows
end

local identityOnly = Design(79, 6, "omitted")
-- Unknown alternate spellings are deliberately not trusted as lock evidence.
identityOnly[#identityOnly].isLocked = true
local authoritative = Design(79, 6, "explicit")
local allFalse = Design(79, 6, "explicit")
for _, row in ipairs(allFalse) do row.locked = false end
local identityKey = assert(A.WishlistKey(identityOnly))

local loadouts = {
    [1]={slot=1,name="Synthetic One",verified=true,
        echoes={{spellId=200100,quality=3,stacks=1}}},
    [2]={slot=2,name="Synthetic Two",verified=true,
        echoes={{spellId=200102,quality=2,stacks=1}}},
    [3]={slot=3,name="Synthetic Three",verified=true,
        echoes={{spellId=200104,quality=2,stacks=1}}},
}

local function Designed(rows, slot, name)
    return {
        slot=slot or 102,
        name=name or "Synthetic Pending Wishlist",
        verified=false,
        echoes=rows,
    }
end

local function SlotsWith(candidate)
    local rows = {}
    for slot, row in pairs(loadouts) do rows[slot] = row end
    if candidate then rows[candidate.slot] = candidate end
    return rows
end

local state = Store.State()
for slot = 1, 3 do
    state.loadoutWishlists[slot] = {
        slot=102, name="Synthetic Pending Wishlist", key=identityKey,
        futureAssociationField={keep=true},
    }
end
state.pendingRelay = {
    sourceSlot=1, targetSlot=3, wishlistSlot=102,
    wishlistKey=identityKey, futureRelayField={keep=true},
}
local associationRefs = {
    state.loadoutWishlists[1], state.loadoutWishlists[2],
    state.loadoutWishlists[3],
}
local relayRef = state.pendingRelay

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

local function LockedCount(rows)
    local count = 0
    for _, row in ipairs(rows or {}) do
        if row.locked == true then
            count = count + (tonumber(row.stacks) or 1)
        end
    end
    return count
end

local function FindCandidate(key)
    for _, candidate in ipairs(A.GetWishlistCandidates()) do
        if candidate.key == key then return candidate end
    end
end

local function RegionContains(fragment)
    for _, region in ipairs(regions) do
        if type(region.text) == "string"
            and region.text:find(fragment, 1, true) then return true end
    end
    return false
end

local function ButtonContaining(fragment)
    for _, frame in ipairs(created) do
        local text = type(frame.text) == "string" and frame.text
            or (type(frame.text) == "table" and frame.text.text)
        if type(text) == "string" and text:find(fragment, 1, true) then
            return frame, text
        end
    end
end

-- The real raw-delivery path currently collapses both omitted fields and an
-- unrecognized alternate spelling to false. The desired boundary preserves
-- both as unavailable; this is not evidence that the alternate means locked.
H.DeliverSlots(SlotsWith(Designed(identityOnly)), 1)
local normalizedRaw = assert(A.Slots().bySlot[102])
Expect("raw_omitted_lock_stays_unavailable",
    normalizedRaw.echoes[1] and normalizedRaw.echoes[1].locked == nil,
    "GameAdapter.Slots() manufactured "
        .. tostring(normalizedRaw.echoes[1] and normalizedRaw.echoes[1].locked)
        .. " from an omitted raw lock field")
Expect("raw_unknown_alternate_not_guessed",
    normalizedRaw.echoes[#normalizedRaw.echoes]
        and normalizedRaw.echoes[#normalizedRaw.echoes].locked == nil,
    "an unrecognized alternate field was collapsed to a guessed boolean")

-- Explicit false is distinct from unavailable and remains authoritative
-- ordinary evidence. An 85-ordinary snapshot must never become actionable.
H.DeliverSlots(SlotsWith(Designed(allFalse)), 1)
local normalizedFalse = assert(A.Slots().bySlot[102])
assert(normalizedFalse.echoes[1].locked == false
    and LockedCount(normalizedFalse.echoes) == 0,
    "explicit false raw lock evidence did not remain false")
local ok, err = A.SetLoadoutWishlist(1, 102, {
    slot=102, name="All False", key=identityKey, echoes=allFalse,
})
assert(ok == false and err == "invalid wishlist",
    "85 authoritative ordinary entries became actionable")

-- Restore the omitted-field mirror. Matching key-only associations should
-- surface one pending candidate instead of disappearing.
H.DeliverSlots(SlotsWith(Designed(identityOnly)), 1)
local pendingCandidate = FindCandidate(identityKey)
Expect("identity_only_candidate_visible",
    pendingCandidate and #pendingCandidate.echoes == 85
        and pendingCandidate.lockEvidenceStatus == "unavailable",
    "matching 85-entry raw/stored identity was rejected instead of exposed pending")
if pendingCandidate then
    local guessed = false
    for _, row in ipairs(pendingCandidate.echoes or {}) do
        if row.locked ~= nil then guessed = true end
    end
    Expect("identity_only_has_no_guessed_locks", not guessed,
        "pending candidate manufactured authoritative lock booleans")
end
local unresolvedWishlist = A.Wishlist()
Expect("identity_only_tracking_stays_pending",
    unresolvedWishlist == nil
        and tostring(A.WishlistNote()):find("lock evidence", 1, true),
    "identity-only state was actionable or lacked an explicit lock-evidence note: "
        .. tostring(A.WishlistNote()))

-- Identity-only state is presentation/recovery evidence, never action
-- authority. Exercise direct, controller, and passive paths and count all
-- upload/lock side effects.
local uploads, locks = 0, 0
local realUploadWishlist, realLockPerk = A.UploadWishlist, A.LockPerk
A.UploadWishlist = function(...)
    uploads = uploads + 1
    return realUploadWishlist(...)
end
A.LockPerk = function(...)
    locks = locks + 1
    return realLockPerk(...)
end
local controller = Nexus.WishlistInternals.Controller.New({
    model=Nexus.WishlistModel.New(), store=Store,
    accountRoot=function() return NexusDB end,
    notify=function() end,
})
controller.Initialize(A)
ok, err = A.SetLoadoutWishlist(1, 102, pendingCandidate or {
    slot=102, name="Synthetic Pending Wishlist", key=identityKey,
    echoes=identityOnly, lockEvidenceStatus="unavailable",
})
Expect("identity_only_direct_action_fails_closed",
    ok == false and tostring(err):find("evidence", 1, true),
    "direct association returned " .. tostring(err or ok))
local controllerOk, controllerErr = controller.AssociateCandidate(
    pendingCandidate or {
        slot=102, name="Synthetic Pending Wishlist", key=identityKey,
        echoes=identityOnly, lockEvidenceStatus="unavailable",
    })
Expect("identity_only_controller_action_fails_closed",
    controllerOk == false and tostring(controllerErr):find("evidence", 1, true),
    "controller association returned " .. tostring(controllerErr or controllerOk))
local beforeFirstRun = state.firstRunWishlist
local firstRunOk, firstRunErr = A.SetFirstRunWishlist(102,
    pendingCandidate or {
        slot=102, name="Synthetic Pending Wishlist", key=identityKey,
        echoes=identityOnly, lockEvidenceStatus="unavailable",
    })
Expect("identity_only_first_run_action_fails_closed",
    firstRunOk == false and tostring(firstRunErr):find("evidence", 1, true)
        and state.firstRunWishlist == beforeFirstRun,
    "first-run association returned " .. tostring(firstRunErr or firstRunOk))
local beforePassive = state.loadoutWishlists[1]
A.DIAGNOSTIC_PASSIVE = true
ok = A.SetLoadoutWishlist(1, 102, pendingCandidate)
A.DIAGNOSTIC_PASSIVE = nil
assert(ok == false and state.loadoutWishlists[1] == beforePassive,
    "passive identity-only action mutated the association")

-- Wishlist Editor and Journal must render the pending identity explicitly.
-- The current expected-red detail captures both exact empty states.
Nexus.Panel = {AttachMenuFrame=function() end,CloseOtherWindows=function() end}
Nexus.Theme = {StyleWindow=function() end,StyleTree=function() end}
Nexus.WishlistEditor.Init(A, Nexus.Model)
Nexus.WishlistEditor.Show()
local editorButton, editorText = ButtonContaining("Synthetic Pending Wishlist")
Expect("wishlist_editor_identity_only_visible",
    editorButton and tostring(editorText):lower():find("awaiting", 1, true)
        and RegionContains("awaiting lock evidence"),
    RegionContains("No wishlist yet")
        and "Wishlist Editor rendered exact 'No wishlist yet' state"
        or "Wishlist Editor omitted the explicit awaiting-evidence candidate")
if editorButton and editorButton:GetScript("OnClick") then
    editorButton:GetScript("OnClick")(editorButton)
end

local journal = CreateFrame("Frame", "ProjectEbonholdEchoJournal", UIParent)
journal:Show()
Nexus.JournalTab.RefreshAssociations()
local selector = assert(_G.NexusActiveWishlistSelector,
    "Journal association selector was not assembled")
selector:GetScript("OnClick")(selector)
local picker = assert(_G.NexusWishlistOnlyPicker,
    "Journal Wishlist picker was not assembled")
local journalButton, journalText
for _, frame in ipairs(created) do
    local text = type(frame.text) == "table" and frame.text.text or nil
    if frame._kind == "Button" and frame._parent
        and frame._parent._parent == picker
        and type(text) == "string"
        and text:find("Synthetic Pending Wishlist", 1, true) then
        journalButton, journalText = frame, text
        break
    end
end
Expect("journal_identity_only_visible",
    journalButton and tostring(journalText):lower():find("awaiting", 1, true),
    RegionContains("No server wishlists found")
        and "Journal rendered exact 'No server wishlists found' state"
        or "Journal omitted the explicit awaiting-evidence candidate")
if journalButton and journalButton:GetScript("OnClick") then
    journalButton:GetScript("OnClick")(journalButton)
end

Expect("identity_only_actions_zero_mutation",
    uploads == 0 and locks == 0 and #H.saveCalls == 0
        and #H.activateCalls == 0 and #H.wire == 0
        and state.loadoutWishlists[1] == associationRefs[1]
        and state.pendingRelay == relayRef,
    "pending display/action path uploaded, locked, activated, or rewrote identity")

-- Missing and partial mirrors retain all associations and the relay, then the
-- exact positive 79+6 mirror promotes the same key authoritatively.
H.DeliverSlots(SlotsWith(nil), 1)
local missingCandidate = FindCandidate(identityKey)
Expect("missing_mirror_retains_pending_identity",
    missingCandidate and missingCandidate.lockEvidenceStatus == "unavailable",
    "missing mirror discarded the stored 85-entry identity")
H.DeliverSlots(SlotsWith(Designed({
    {spellId=200200,quality=1,stacks=1},
}, 103, "Unrelated Partial")), 1)
local partialCandidate = FindCandidate(identityKey)
Expect("partial_mirror_retains_pending_identity",
    partialCandidate and partialCandidate.lockEvidenceStatus == "unavailable",
    "partial mirror discarded or guessed the stored 85-entry identity")
for slot = 1, 3 do
    assert(state.loadoutWishlists[slot] == associationRefs[slot]
        and associationRefs[slot].futureAssociationField.keep,
        "missing/partial mirror rewrote association " .. slot)
end
assert(state.pendingRelay == relayRef and relayRef.futureRelayField.keep,
    "missing/partial mirror rewrote the pending relay")

H.DeliverSlots(SlotsWith(Designed(identityOnly, 104, "Pending Renamed")), 1)
local movedPending = assert(FindCandidate(identityKey),
    "moved identity-only candidate disappeared")
assert(movedPending.slot == 104 and A.GetLoadoutWishlist(1) == nil
    and A.Wishlist() == nil,
    "moved identity-only candidate became actionable")
for slot = 1, 3 do
    assert(state.loadoutWishlists[slot] == associationRefs[slot]
        and associationRefs[slot].slot == 102
        and associationRefs[slot].name == "Synthetic Pending Wishlist",
        "passive pending move/rename rewrote association " .. slot)
end

H.DeliverSlots(SlotsWith(Designed(authoritative, 104, "Promoted Renamed")), 1)
local promoted = assert(FindCandidate(identityKey),
    "exact authoritative 79+6 content did not produce a candidate")
assert(promoted.slot == 104 and promoted.lockEvidenceVersion == 1
    and LockedCount(promoted.echoes) == 6,
    "exact authoritative recovery lost bounded positive lock evidence")
for slot = 1, 3 do
    local linked = assert(A.GetLoadoutWishlist(slot),
        "exact authoritative recovery did not resolve association " .. slot)
    assert(linked.key == identityKey and linked.lockEvidenceVersion == 1
        and associationRefs[slot].slot == 104
        and associationRefs[slot].name == "Promoted Renamed",
        "authoritative recovery changed identity or evidence " .. slot)
end

local function Candidate(slot, name, rows, key)
    return {slot=slot,name=name,echoes=rows,key=key or A.WishlistKey(rows)}
end

-- Positive and hostile boundary matrix.
ok, err = A.SetLoadoutWishlist(1, promoted.slot, promoted)
assert(ok and err == nil, "explicit 79+6 authoritative candidate became invalid")
local exact79 = Candidate(206, "Exact 79", Design(79, 0, "explicit"))
ok, err = A.SetLoadoutWishlist(1, 206, exact79)
assert(ok and err == nil, "exactly 79 ordinary entries became invalid")
ok, err = A.SetLoadoutWishlist(1, 207,
    Candidate(207, "80 Ordinary", Design(80, 0, "explicit")))
assert(ok == false and err == "invalid wishlist", "80 ordinary entries became valid")
ok, err = A.SetLoadoutWishlist(1, 208,
    Candidate(208, "Seven Locked", Design(78, 7, "explicit")))
assert(ok == false and err == "invalid wishlist", "more than six locked entries became valid")
ok, err = A.SetLoadoutWishlist(1, 209, {
    slot=209,name="Malformed",key="forged",
    echoes={{spellId=0,quality=1,stacks="bad",locked=false}},
})
assert(ok == false and err == "invalid wishlist", "malformed or forged candidate became valid")
local sparse = Candidate(210, "Sparse", Design(2, 0, "explicit"))
sparse.echoes[1] = nil
ok, err = A.SetLoadoutWishlist(1, 210, sparse)
assert(ok == false and err == "invalid wishlist", "sparse candidate became valid")
H.DeliverSlots(SlotsWith(Designed({
    {spellId=200202,quality=1,stacks=1,locked=false},
}, 206, "Recycled")), 1)
ok, err = A.SetLoadoutWishlist(1, 206, exact79)
assert(ok == false and err == "wishlist changed; refresh and try again",
    "recycled numeric slot overrode immutable identity")

A.UploadWishlist, A.LockPerk = realUploadWishlist, realLockPerk
assert(state.pendingRelay == relayRef and NexusDB.futureRoot.keep,
    "characterization damaged relay or unknown SavedVariables fields")

if #failures > 0 then
    error(string.format("Stage 23.1 expected red (%d): %s",
        #failures, table.concat(failures, " | ")))
end
print("Stage 23 Wishlist identity-only characterization -- OK")
