-- Stage 30 Share/Edit regression: exercise the real multiline controls
-- under an explicit Wrath keyboard contract and record the popup drag owner.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local accented = "Mage" .. string.char(0xC3, 0xA9)
local exactText = "Spaces, punctuation!\nSecond line: caf"
    .. string.char(0xC3, 0xA9) .. "."
UnitName = function() return accented end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end

NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds={},
    buildFilters={scope="all",sortMode="title"},dpsCapture={},
    upstreamSavedBuilds={keep=true},upstreamWishlists={keep=true},
}
Nexus.Store.Init()
local savedBuildsRef, wishlistsRef = NexusDB.upstreamSavedBuilds,
    NexusDB.upstreamWishlists

local slot = {slot=1,name="Stage 30 Source",class="MAGE",echoes={
    {spellId=770001,quality=3,stacks=1},
}}
local Adapter = {
    Slots=function() return {bySlot={[1]=slot},activeSlot=1,maxSlots=5} end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={
        [770001]={name="Stage 30 Echo",classMask=128},
    }} end,
    Owned=function() return {bySpell={[770001]=1}} end,
    LockedOwned=function() return {bySpell={}} end,
    Wishlist=function() return slot end,
}
Nexus.DpsCapture = {
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
local deleteCalls = 0
Nexus.Sync = {
    BroadcastBuildSummary=function() return true end,
    BroadcastDelete=function()
        deleteCalls = deleteCalls + 1
        return true
    end,
    RequestLoadout=function() return true end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}

local realCreateFrame = CreateFrame
local created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._stage30Kind, frame._stage30Template = kind, template
    frame._stage30Parent = parent
    created[#created + 1] = frame
    local baseRegisterForDrag = frame.RegisterForDrag
    frame.RegisterForDrag = function(self, button)
        self._stage30DragButton = button
        return baseRegisterForDrag(self, button)
    end
    local baseEnableKeyboard = frame.EnableKeyboard
    frame.EnableKeyboard = function(self, enabled)
        self._stage30KeyboardEnabled = enabled ~= false
        return baseEnableKeyboard(self, enabled)
    end
    local baseSetMaxLetters = frame.SetMaxLetters
    frame.SetMaxLetters = function(self, value)
        self._stage30MaxLetters = value
        return baseSetMaxLetters(self, value)
    end
    local baseSetMultiLine = frame.SetMultiLine
    frame.SetMultiLine = function(self, enabled)
        self._stage30MultiLine = enabled ~= false
        return baseSetMultiLine(self, enabled)
    end
    local baseSetCursorPosition = frame.SetCursorPosition
    frame.SetCursorPosition = function(self, value)
        self._stage30CursorPosition = value
        return baseSetCursorPosition(self, value)
    end
    local baseSetScrollChild = frame.SetScrollChild
    frame.SetScrollChild = function(self, child)
        self._stage30ScrollChild = child
        return baseSetScrollChild(self, child)
    end
    return frame
end

dofile("ui/CommunityBuilds.lua")
local Community = Nexus.CommunityBuilds
Community.Init(Adapter, nil)

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

local function ClickAndType(box, text)
    local click = box:GetScript("OnMouseDown")
    if click then click(box, "LeftButton") end
    if not box:HasFocus() or box._stage30KeyboardEnabled ~= true then
        return false
    end
    box:SetText(text)
    return box:GetText() == text
end

local function DragHandleFor(parent)
    for _, frame in ipairs(created) do
        if frame._stage30Parent == parent
            and frame._stage30DragButton == "LeftButton" then return frame end
    end
end

local function DetailPanel()
    for _, frame in ipairs(created) do
        if frame.deleteBtn and frame.desc then return frame end
    end
end

Community.ShowPostBuild()
local post = assert(H.frames.NexusPostPopup,
    "real Share popup was not assembled")
local postDescription = assert(post._postDescBox,
    "real Share description EditBox is unavailable")
Expect("share_drag_is_limited_to_title_handle",
    post._stage30DragButton == nil and DragHandleFor(post) ~= nil,
    "the entire Share popup owns LeftButton drag and no title handle exists")
local postTyped = ClickAndType(postDescription, exactText)
Expect("share_description_accepts_explicit_keyboard_input",
    postTyped and postDescription:GetText() == exactText,
    string.format("focus=%s keyboard=%s text=%q",
        tostring(postDescription:HasFocus()),
        tostring(postDescription._stage30KeyboardEnabled),
        tostring(postDescription:GetText())))
Expect("share_description_has_clipped_caret_owner",
    post._postDescScroll
        and post._postDescScroll._stage30ScrollChild == postDescription
        and postDescription._stage30CursorPosition == 0,
    string.format("scroll=%s child=%s cursor=%s",
        tostring(post._postDescScroll ~= nil),
        tostring(post._postDescScroll
            and post._postDescScroll._stage30ScrollChild == postDescription),
        tostring(postDescription._stage30CursorPosition)))
assert(postDescription._stage30MultiLine
    and postDescription._stage30MaxLetters == 2000,
    "Share description lost multiline or 2,000-character boundary")
local postEscape = postDescription:GetScript("OnEscapePressed")
if postEscape then postEscape(postDescription) end
assert(not postDescription:HasFocus(),
    "Share description Escape did not clear focus")
post:Hide()
Community.ShowPostBuild()
assert(post:IsShown() and postDescription:GetText() == ""
    and postDescription._stage30CursorPosition == 0
    and ClickAndType(postDescription, exactText),
    "Share description did not reopen with the same keyboard contract")
if postEscape then postEscape(postDescription) end

local posted, sharedId = Community.PostCurrentWishlist(
    "Stage 30 Editable", "seed", slot, "MAGE")
assert(posted and sharedId, "fixture could not seed an owned shared build")
Community.ToggleEditPopup(sharedId)
local edit = assert(H.frames.NexusEditPopup,
    "real Edit Build popup was not assembled")
local editDescription = assert(edit._editDescBox,
    "real Edit Build description EditBox is unavailable")
Expect("edit_drag_is_limited_to_title_handle",
    edit._stage30DragButton == nil and DragHandleFor(edit) ~= nil,
    "the Edit popup has no title-only drag handle")
local editTyped = ClickAndType(editDescription, exactText)
Expect("edit_description_accepts_explicit_keyboard_input",
    editTyped and editDescription:GetText() == exactText,
    string.format("focus=%s keyboard=%s text=%q",
        tostring(editDescription:HasFocus()),
        tostring(editDescription._stage30KeyboardEnabled),
        tostring(editDescription:GetText())))
Expect("edit_description_has_clipped_caret_owner",
    edit._editDescScroll
        and edit._editDescScroll._stage30ScrollChild == editDescription
        and editDescription._stage30CursorPosition == #"seed",
    string.format("scroll=%s child=%s cursor=%s",
        tostring(edit._editDescScroll ~= nil),
        tostring(edit._editDescScroll
            and edit._editDescScroll._stage30ScrollChild == editDescription),
        tostring(editDescription._stage30CursorPosition)))
assert(editDescription._stage30MultiLine
    and editDescription._stage30MaxLetters == 2000,
    "Edit description lost multiline or 2,000-character boundary")
local editEscape = editDescription:GetScript("OnEscapePressed")
if editEscape then editEscape(editDescription) end
assert(not editDescription:HasFocus(),
    "Edit description Escape did not clear focus")
assert(Nexus.BuildCatalog.Get(sharedId).description == "seed",
    "characterization input mutated the owned build")
Community.ToggleEditPopup(sharedId)
assert(not edit:IsShown(), "Edit description did not close before reopen")
Community.ToggleEditPopup(sharedId)
assert(edit:IsShown() and editDescription:GetText() == "seed"
    and editDescription._stage30CursorPosition == #"seed"
    and ClickAndType(editDescription, exactText),
    "Edit description did not reopen with the same keyboard contract")
if editEscape then editEscape(editDescription) end

-- Exact description bytes must survive local mutation, compact JSON/base64,
-- strict receiver validation, empty text, and the 2,000-character boundary.
Community.ToggleEditPopup(sharedId)
local suffix = "\nSecond line: exact boundary."
local exact2000 = string.rep("x", 2000 - #suffix) .. suffix
assert(#exact2000 == 2000, "fixture description boundary drifted")
local exactOk, exactErr = Community.EditBuild(
    sharedId, "Stage 30 Editable", exact2000)
Expect("multiline_description_round_trips_exact_2000_characters",
    exactOk and Nexus.BuildCatalog.Get(sharedId).description == exact2000,
    string.format("ok=%s err=%s bytes=%d retained=%q",
        tostring(exactOk),tostring(exactErr),#exact2000,
        tostring(Nexus.BuildCatalog.Get(sharedId).description)))

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
local Identity = assert(Nexus.Identity, "identity owner unavailable")
local protocol = Nexus.SyncInternals.Protocol.New({
    limits={maxTransferIdBytes=80,maxHashBytes=256,maxVersionBytes=40,
        maxBuildIdBytes=96,maxBuildEchoes=120,maxRequestIdBytes=80,
        bucketCount=8,maxWireFields=8},
    parseVersion=function() return {major=1} end,
    ownerKeyMatchesAuthor=Identity.OwnerKeyMatchesAuthor,
    isSafeTree=Nexus.Codec.IsSafeTree,
})
local wireBuild = {
    id="stage30-wire",title="Exact description",author=accented,
    ownerKey=accented:lower() .. "@ebonhold",class="MAGE",
    lastModified=1,description=exact2000,
    echoes={{spellId=770001,quality=3,stacks=1}},
}
local compact = protocol.CompactEncode(wireBuild)
local wire = Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(compact))
local receivedTree = Nexus.Codec.JSONDecodeNetwork(
    Nexus.Codec.Base64DecodeNetwork(wire))
local received = protocol.ValidateNetworkPayload(receivedTree)
Expect("network_receiver_preserves_exact_multiline_description",
    received and received.description == exact2000,
    string.format("received=%s bytes=%s",
        tostring(received ~= nil),
        tostring(received and #received.description)))
local utf8Multiline = "First line\nSecond line: caf"
    .. string.char(0xC3, 0xA9) .. "."
wireBuild.description = utf8Multiline
local utf8Received = protocol.ValidateNetworkPayload(
    protocol.CompactEncode(wireBuild))
assert(Community.EditBuild(sharedId, "Stage 30 Editable", utf8Multiline)
    and Nexus.BuildCatalog.Get(sharedId).description == utf8Multiline
    and utf8Received and utf8Received.description == utf8Multiline,
    "valid UTF-8 multiline description changed in local or wire handling")
wireBuild.description = ""
local emptyTree = protocol.CompactEncode(wireBuild)
local emptyReceived = protocol.ValidateNetworkPayload(emptyTree)
assert(Community.EditBuild(sharedId, "Stage 30 Editable", "")
    and Nexus.BuildCatalog.Get(sharedId).description == ""
    and emptyTree.d == nil and emptyReceived
    and emptyReceived.description == "",
    "empty description did not remain an accepted empty value")
wireBuild.description = "unsafe\tdescription"
assert(protocol.ValidateNetworkPayload(
        protocol.CompactEncode(wireBuild)) == nil,
    "multiline receiver accepted a non-line-break control byte")
wireBuild.description = "malformed" .. string.char(0xC3)
assert(protocol.ValidateNetworkPayload(
        protocol.CompactEncode(wireBuild)) == nil,
    "multiline receiver accepted malformed UTF-8")
assert(Community.EditBuild(sharedId, "Stage 30 Editable", exact2000),
    "fixture could not restore the exact boundary description")
local beforeTooLong = Nexus.BuildCatalog.Get(sharedId).description
assert(not Community.EditBuild(sharedId, "Stage 30 Editable",
        exact2000 .. "x")
    and Nexus.BuildCatalog.Get(sharedId).description == beforeTooLong,
    "overlong description mutated the owned build")

-- The real detail view must expose an owner-only, confirmation-gated Stop
-- Sharing action. Accepting it uses the existing tombstone path and leaves
-- upstream Saved Build/Wishlist state untouched.
if exactOk then
    assert(Community.EditBuild(sharedId, "Stage 30 Editable", exact2000))
end
Community.Show()
Community.Select(sharedId)
local communityFrame = assert(H.frames.NexusCommunityBuildsFrame,
    "Community frame was not assembled for withdrawal")
local communityUpdate = assert(communityFrame:GetScript("OnUpdate"),
    "Community update path was not installed")
for _ = 1, 200 do
    communityUpdate(communityFrame, 0.05)
    local panel = DetailPanel()
    if panel and panel:IsShown() then break end
end
local detail = assert(DetailPanel(), "real Community detail panel is unavailable")
if exactOk then
    assert(detail.desc:GetText() == exact2000,
        "detail rendering changed the exact description bytes")
end
local stopDialog = StaticPopupDialogs["NEXUS_STOP_SHARING_BUILD"]
local stopUiReady = detail.deleteBtn:GetText() == "Stop Sharing"
    and type(stopDialog) == "table"
Expect("owned_stop_sharing_requires_confirmation", stopUiReady,
    string.format("label=%q dialog=%s",
        tostring(detail.deleteBtn:GetText()),tostring(type(stopDialog))))
if stopUiReady then
    H.lastStaticPopup = nil
    assert(detail.deleteBtn:GetScript("OnClick"))()
    assert(H.lastStaticPopup
        and H.lastStaticPopup.which == "NEXUS_STOP_SHARING_BUILD"
        and Nexus.BuildCatalog.Get(sharedId),
        "Stop Sharing mutated the build before confirmation")
    H.AcceptLastStaticPopup()
    assert(Nexus.BuildCatalog.Get(sharedId) == nil
        and NexusDB.syncTombstones[sharedId]
        and deleteCalls == 1,
        "confirmed Stop Sharing did not use the owner tombstone path")
end

local postedStale, staleId = Community.PostCurrentWishlist(
    "Stage 30 Stale Owner", "stale owner", slot, "MAGE")
assert(postedStale and staleId,
    "fixture could not seed the stale-owner withdrawal guard")
Community.Select(staleId)
for _ = 1, 200 do
    communityUpdate(communityFrame, 0.05)
    if detail:IsShown() and detail.deleteBtn:GetText() == "Stop Sharing" then
        break
    end
end
H.lastStaticPopup = nil
assert(detail.deleteBtn:GetScript("OnClick"))()
assert(H.lastStaticPopup
    and H.lastStaticPopup.which == "NEXUS_STOP_SHARING_BUILD",
    "stale-owner guard did not reach confirmation")
assert(Nexus.BuildCatalog.Get(staleId),
    "stale-owner fixture vanished before confirmation")
local staleStored = assert(NexusDB.communityBuilds[staleId],
    "stale-owner fixture has no authoritative overlay record")
staleStored.ownerKey = "other@ebonhold"
local deletesBeforeStale = deleteCalls
local stalePrinted = {}
local stalePrint = print
print = function(message) stalePrinted[#stalePrinted + 1] = tostring(message) end
H.AcceptLastStaticPopup()
print = stalePrint
local staleRetained = Nexus.BuildCatalog.Get(staleId)
assert(staleRetained and staleRetained.ownerKey == "other@ebonhold"
    and NexusDB.syncTombstones[staleId] == nil
    and deleteCalls == deletesBeforeStale
    and table.concat(stalePrinted, "\n"):find(
        "Stop Sharing refused", 1, true),
    string.format("ownership change after confirmation did not fail closed: "
        .. "retained=%s tombstone=%s calls=%d/%d text=%q",
        tostring(staleRetained ~= nil),
        tostring(NexusDB.syncTombstones[staleId] ~= nil),
        deleteCalls,deletesBeforeStale,table.concat(stalePrinted, "\n")))

local postedRejected, rejectedId = Community.PostCurrentWishlist(
    "Stage 30 Rejected Withdrawal", "rejected", slot, "MAGE")
assert(postedRejected and rejectedId,
    "fixture could not seed rejected withdrawal reporting")
Nexus.Sync.BroadcastDelete = function()
    deleteCalls = deleteCalls + 1
    return false, "sync disabled"
end
Community.Select(rejectedId)
for _ = 1, 200 do
    communityUpdate(communityFrame, 0.05)
    if detail:IsShown() and detail.deleteBtn:GetText() == "Stop Sharing" then
        break
    end
end
local rejectedPrinted = {}
local rejectedPrint = print
print = function(message) rejectedPrinted[#rejectedPrinted + 1] = tostring(message) end
H.lastStaticPopup = nil
assert(detail.deleteBtn:GetScript("OnClick"))()
assert(H.lastStaticPopup
    and H.lastStaticPopup.which == "NEXUS_STOP_SHARING_BUILD",
    "rejected withdrawal did not reach confirmation")
H.AcceptLastStaticPopup()
print = rejectedPrint
assert(Nexus.BuildCatalog.Get(rejectedId) == nil
    and NexusDB.syncTombstones[rejectedId]
    and table.concat(rejectedPrinted, "\n"):find(
        "withdrawal not queued: sync disabled", 1, true),
    "non-retry withdrawal rejection was not reported honestly")

local postedRetry, retryId = Community.PostCurrentWishlist(
    "Stage 30 Retry", "retry", slot, "MAGE")
assert(postedRetry and retryId, "fixture could not seed withdrawal retry")
local deletesBeforeRetry = deleteCalls
Nexus.Sync.BroadcastDelete = function()
    deleteCalls = deleteCalls + 1
    return false, "queued for retry"
end
Community.Select(retryId)
for _ = 1, 200 do
    communityUpdate(communityFrame, 0.05)
    if detail:IsShown() and detail.deleteBtn:GetText() == "Stop Sharing" then
        break
    end
end
local printed = {}
local realPrint = print
print = function(message) printed[#printed + 1] = tostring(message) end
H.lastStaticPopup = nil
assert(detail.deleteBtn:GetScript("OnClick"))()
local retryConfirmed = H.lastStaticPopup
    and H.lastStaticPopup.which == "NEXUS_STOP_SHARING_BUILD"
H.AcceptLastStaticPopup()
print = realPrint
local retryText = table.concat(printed, "\n")
Expect("withdrawal_reports_queue_admission",
    retryConfirmed
        and retryText:find("Withdrawal retry is pending", 1, true)
        and deleteCalls == deletesBeforeRetry + 1
        and Nexus.BuildCatalog.Get(retryId) == nil
        and NexusDB.syncTombstones[retryId]
        and NexusDB.upstreamSavedBuilds == savedBuildsRef
        and NexusDB.upstreamWishlists == wishlistsRef
        and savedBuildsRef.keep and wishlistsRef.keep,
    string.format("confirmed=%s text=%q removed=%s tombstone=%s calls=%d",
        tostring(retryConfirmed),retryText,
        tostring(Nexus.BuildCatalog.Get(retryId) == nil),
        tostring(NexusDB.syncTombstones[retryId] ~= nil),deleteCalls))

if #failures > 0 then
    error("Stage 30 Share/Edit and withdrawal regression ("
        .. #failures .. "): " .. table.concat(failures, " | "))
end

print("Stage 30 Share/Edit keyboard and drag characterization -- OK")
