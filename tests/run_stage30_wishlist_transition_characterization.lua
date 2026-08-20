-- Stage 30.4 regression: a stable Wishlist identity that gains complete
-- lock evidence must invalidate the relevant projection and refresh an open
-- editor without any upload, association rewrite, lock, or automation action.
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
    frame._stage30Kind, frame._stage30Parent = kind, parent
    created[#created + 1] = frame
    return frame
end
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds={},buildFilters={},
    dpsCapture={},futureRoot={keep=true},
}
UISpecialFrames = {}
Nexus.Store.Init()
local Store, Adapter = Nexus.Store, Nexus.GameAdapter
Adapter.Init({}, Store)
H.playerLevel = 80

for index = 1, 85 do
    H.AddEcho(780000 + index, "Transition Echo " .. index,
        {quality=index % 4})
end

local function Rows(ordinary, locked, explicit)
    local rows = {}
    for index = 1, ordinary do
        local row = {spellId=780000+index,quality=index%4,stacks=1}
        if explicit then row.locked = false end
        rows[#rows + 1] = row
    end
    for index = 1, locked do
        local row = {
            spellId=780000+ordinary+index,quality=3,stacks=1,
        }
        if explicit then row.locked = true end
        rows[#rows + 1] = row
    end
    return rows
end

local loadout = {slot=1,name="Mage Foundation",verified=true,
    echoes={{spellId=780001,quality=3,stacks=1,locked=false}}}
local function Slots(candidate)
    local out = {[1]=loadout}
    if candidate then out[candidate.slot] = candidate end
    return out
end
local function Candidate(rows, slot, name)
    return {slot=slot or 102,name=name or "Mage Foundation Wishlist",
        verified=false,echoes=rows}
end

local state = Store.State()
local ordinary41 = Rows(41, 0, false)
local ordinary41Key = assert(Adapter.WishlistKey(ordinary41))
state.loadoutWishlists[1] = {
    slot=102,name="Mage Foundation Wishlist",key=ordinary41Key,
    echoes=ordinary41,futureAssociationField={keep=true},
}
local association41 = state.loadoutWishlists[1]
H.DeliverSlots(Slots(Candidate(ordinary41)), 1)
local usable41 = Adapter.GetLoadoutWishlist(1)
assert(usable41 and usable41.key == ordinary41Key
    and #usable41.echoes == 41
    and usable41.lockEvidenceStatus == nil,
    "41-entry at-most-79 Wishlist incorrectly requires lock evidence")
assert(state.loadoutWishlists[1] == association41,
    "passive 41-entry resolution rewrote its association")

-- Switch fixture state to the established over-envelope pending case so the
-- unavailable-to-authoritative transition remains fail-closed until evidence.
local pendingRows = Rows(79, 6, false)
local authoritativeRows = Rows(79, 6, true)
local transitionKey = assert(Adapter.WishlistKey(pendingRows))
state.loadoutWishlists[1] = {
    slot=103,name="Transition Wishlist",key=transitionKey,
    echoes=pendingRows,futureAssociationField={keep=true},
}
local association = state.loadoutWishlists[1]
H.DeliverSlots(Slots(Candidate(pendingRows, 103, "Transition Wishlist")), 1)
local pending = Adapter.GetWishlistCandidates()[1]
for _, candidate in ipairs(Adapter.GetWishlistCandidates()) do
    if candidate.key == transitionKey then pending = candidate break end
end
assert(pending and pending.lockEvidenceStatus == "unavailable"
    and Adapter.Wishlist() == nil
    and tostring(Adapter.WishlistNote()):find("lock evidence", 1, true),
    "fixture did not establish the fail-closed pending identity")

local uploads, locks, associationWrites = 0, 0, 0
local realUpload, realLock, realAssociate = Adapter.UploadWishlist,
    Adapter.LockPerk, Adapter.SetLoadoutWishlist
Adapter.UploadWishlist = function(...)
    uploads = uploads + 1
    return realUpload(...)
end
Adapter.LockPerk = function(...)
    locks = locks + 1
    return realLock(...)
end
Adapter.SetLoadoutWishlist = function(...)
    associationWrites = associationWrites + 1
    return realAssociate(...)
end

Nexus.Panel = {AttachMenuFrame=function() end,CloseOtherWindows=function() end}
Nexus.Theme = {StyleWindow=function() end,StyleTree=function() end}
Nexus.WishlistEditor.Init(Adapter, Nexus.Model)
Nexus.WishlistEditor.Show()
local editorFrame = assert(NexusEditorFrame,
    "Wishlist Editor frame was not assembled")
assert(editorFrame:IsShown(), "Wishlist Editor did not remain open")

local function ButtonText(value)
    for _, frame in ipairs(created) do
        local text = type(frame.text) == "table" and frame.text.text or frame.text
        if frame._stage30Kind == "Button" and text == value then return frame end
    end
end
assert(ButtonText("Create Wishlist"),
    "pending identity did not leave the editor in its current create state")

local _,_,_,_,wishlistRevisionBefore = Adapter.PresentationRevisions()
local unrelatedRows = Rows(79, 6, false)
unrelatedRows[1].spellId = 779999
H.DeliverSlots(Slots(Candidate(unrelatedRows, 104,
    "Unrelated Wishlist")), 1)
Adapter.Poll()
local _,_,_,_,wishlistRevisionUnrelated = Adapter.PresentationRevisions()
local warmCallsBefore = Adapter.EchoReconcileStats().projections.slots.calls
Adapter.Poll()
local warmCallsAfter = Adapter.EchoReconcileStats().projections.slots.calls
H.DeliverSlots(Slots(Candidate(authoritativeRows, 103,
    "Transition Wishlist")), 1)
Adapter.Poll()
local resolved = Adapter.GetLoadoutWishlist(1)
local resolutionRows = Adapter.GetWishlistCandidates()
local resolutionDetail = {}
for _, candidate in ipairs(resolutionRows) do
    resolutionDetail[#resolutionDetail + 1] = table.concat({
        tostring(candidate.slot),tostring(candidate.key == transitionKey),
        tostring(candidate.lockEvidenceVersion),
        tostring(candidate.lockEvidenceStatus),tostring(#(candidate.echoes or {})),
    }, "/")
end
assert(resolved and resolved.key == transitionKey
    and resolved.lockEvidenceVersion == 1,
    "authoritative mirror did not resolve the stable association: "
        .. tostring(Adapter.WishlistNote()) .. " candidates="
        .. table.concat(resolutionDetail, ","))
local _,_,_,_,wishlistRevisionAfter = Adapter.PresentationRevisions()
Adapter.Poll()
local _,_,_,_,wishlistRevisionSettled = Adapter.PresentationRevisions()
local update = assert(editorFrame:GetScript("OnUpdate"),
    "open Wishlist Editor has no refresh path")
update(editorFrame, 0.5)

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end
Expect("authoritative_transition_marks_wishlist_projection_dirty",
    wishlistRevisionAfter == wishlistRevisionBefore + 1
        and wishlistRevisionSettled == wishlistRevisionAfter,
    string.format("wishlist revision changed %s -> %s -> %s",
        tostring(wishlistRevisionBefore),tostring(wishlistRevisionAfter),
        tostring(wishlistRevisionSettled)))
Expect("unrelated_identity_does_not_dirty_wishlist_projection",
    wishlistRevisionUnrelated == wishlistRevisionBefore,
    string.format("unrelated identity changed revision %s -> %s",
        tostring(wishlistRevisionBefore),tostring(wishlistRevisionUnrelated)))
Expect("pending_warm_poll_has_zero_slot_traversals",
    warmCallsAfter == warmCallsBefore,
    string.format("warm slot traversals changed %s -> %s",
        tostring(warmCallsBefore),tostring(warmCallsAfter)))
Expect("open_editor_promotes_matching_authoritative_identity",
    ButtonText("Save Wishlist") ~= nil and ButtonText("Create Wishlist") == nil,
    "the open editor remained in create/awaiting presentation after resolution")
Expect("authoritative_refresh_is_mutation_free",
    uploads == 0 and locks == 0 and associationWrites == 0
        and #H.saveCalls == 0 and #H.activateCalls == 0
        and state.loadoutWishlists[1] == association
        and association.slot == 103
        and association.name == "Transition Wishlist"
        and association.key == transitionKey,
    string.format("uploads=%d locks=%d associations=%d saves=%d activates=%d",
        uploads,locks,associationWrites,#H.saveCalls,#H.activateCalls))
assert(editorFrame:IsShown() and NexusDB.futureRoot.keep
    and association.futureAssociationField.keep,
    "transition closed the UI or replaced unknown SavedVariables fields")

Adapter.UploadWishlist, Adapter.LockPerk, Adapter.SetLoadoutWishlist =
    realUpload, realLock, realAssociate

if #failures > 0 then
    error("Stage 30.4 Wishlist transition regression ("
        .. #failures .. "):\n - " .. table.concat(failures, "\n - "))
end

print("Stage 30 Wishlist evidence transition characterization -- OK")
