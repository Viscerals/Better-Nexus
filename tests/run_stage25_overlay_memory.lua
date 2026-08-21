-- Stage 25.4 gate: the visible Wishlist overlay is revision-driven, identical
-- models write no rows or styles, hidden paths do no presentation work, and
-- retained widget/cache state stays fixed across long board-like bursts.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Revisions.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

-- The overlay cache key is supplied by the real GameAdapter boundary. Prove
-- that association, ownership, and slot/active changes advance their intended
-- scalar components before isolating presentation behavior with a fake view.
NexusDB = {}
Nexus.Store.Init()
H.granted = {}
Nexus.GameAdapter.Init({}, Nexus.Store)
local realSlots, realActive, realGranted, realOwned,
    realWishlist, realCatalog =
    Nexus.GameAdapter.PresentationRevisions()
assert(Nexus.GameAdapter.SetFirstRunWishlistIdentity("Revision Goal", {
    {spellId=200100,quality=3,stacks=1},
}))
local associationSlots, associationActive, associationGranted,
    associationOwned, associationWishlist, associationCatalog =
    Nexus.GameAdapter.PresentationRevisions()
assert(associationWishlist == realWishlist + 1
    and associationSlots == realSlots and associationActive == realActive
    and associationGranted == realGranted and associationOwned == realOwned
    and associationCatalog == realCatalog,
    "wishlist association did not advance only its presentation revision")
H.granted = {generated={{spellId=200100,quality=3}}}
H.NotifyEchoDataChanged()
Nexus.GameAdapter.Poll()
local grantedSlots, grantedActive, grantedGeneration, grantedOwned,
    grantedWishlist, grantedCatalog = Nexus.GameAdapter.PresentationRevisions()
assert(grantedGeneration > associationGranted
    and grantedSlots == associationSlots and grantedActive == associationActive
    and grantedOwned == associationOwned
    and grantedWishlist == associationWishlist
    and grantedCatalog == associationCatalog,
    "granted change did not advance only its presentation generation")
H.DeliverSlots({
    [1]={slot=1,name="Saved",verified=true,echoes={
        {spellId=200100,quality=3,stacks=1},
    }},
}, 1)
Nexus.GameAdapter.Poll()
local slotRevision, activeRevision, slotGranted, slotOwned,
    slotWishlist, slotCatalog = Nexus.GameAdapter.PresentationRevisions()
assert((slotRevision > grantedSlots or activeRevision > grantedActive)
    and slotGranted == grantedGeneration and slotOwned == grantedOwned
    and slotWishlist == grantedWishlist
    and slotCatalog == grantedCatalog,
    "slot/active change did not remain local to presentation revisions")
H.DeliverBoard({{spellId=200100,quality=3}})
assert(Nexus.GameAdapter.Take(200100),
    "local-owned presentation fixture could not submit its selection")
H.ResolveSelect(true)
Nexus.GameAdapter.Poll()
local pickSlots, pickActive, pickGranted, pickOwned,
    pickWishlist, pickCatalog = Nexus.GameAdapter.PresentationRevisions()
assert(pickOwned > slotOwned and pickGranted == slotGranted
    and pickSlots == slotRevision and pickActive == activeRevision
    and pickWishlist == slotWishlist and pickCatalog == slotCatalog,
    "confirmed local pick did not advance only its owned presentation revision")

local frameCreates, fontStringCreates, lineMutations = 0, 0, 0
local lineObjects = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    frameCreates = frameCreates + 1
    local widget = realCreateFrame(...)
    local realCreateFontString = widget.CreateFontString
    widget.CreateFontString = function(self, ...)
        local line = realCreateFontString(self, ...)
        fontStringCreates = fontStringCreates + 1
        lineObjects[#lineObjects + 1] = line
        local setText, setTextColor = line.SetText, line.SetTextColor
        local show, hide = line.Show, line.Hide
        line.SetText = function(target, ...)
            lineMutations = lineMutations + 1
            return setText(target, ...)
        end
        line.SetTextColor = function(target, ...)
            lineMutations = lineMutations + 1
            return setTextColor(target, ...)
        end
        line.Show = function(target, ...)
            lineMutations = lineMutations + 1
            return show(target, ...)
        end
        line.Hide = function(target, ...)
            lineMutations = lineMutations + 1
            return hide(target, ...)
        end
        return line
    end
    return widget
end

Nexus = Nexus or {}
local styleCalls = 0
Nexus.Theme = {
    StyleTree=function(root)
        assert(root, "overlay attempted to style a missing control tree")
        styleCalls = styleCalls + 1
        return root
    end,
}
dofile("ui/WishlistOverlay.lua")

NexusDB = {}
local revisions = {
    slots=1,active=1,granted=1,owned=1,wishlist=1,catalog=1,
}
local calls = {wishlist=0,owned=0,catalog=0,revisions=0}
local wishlist = {name="Generated Goal",entries={}}
local initialWishlist = wishlist
local owned = {bySpell={},byFamily={},synced=true}
local catalog = {rows={}}
for index = 1, 79 do
    local spellId = 220000 + index
    local family = "generated-family-" .. index
    wishlist.entries[index] = {
        spellId=spellId,quality=index % 5,stacks=(index % 3) + 1,
        family=family,
    }
    catalog.rows[spellId] = {
        name=string.format("Generated Echo %03d", index),
        quality=index % 5,
    }
end

local Adapter = {}
local promoteOnWishlistRead = true
function Adapter.PresentationRevisions()
    calls.revisions = calls.revisions + 1
    return revisions.slots,revisions.active,revisions.granted,revisions.owned,
        revisions.wishlist,revisions.catalog
end
function Adapter.Wishlist()
    calls.wishlist = calls.wishlist + 1
    if promoteOnWishlistRead then
        promoteOnWishlistRead = false
        revisions.wishlist = revisions.wishlist + 1
    end
    return wishlist
end
function Adapter.Owned()
    calls.owned = calls.owned + 1
    return owned
end
function Adapter.Catalog()
    calls.catalog = calls.catalog + 1
    return catalog
end

local function CopyCounts(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end
local function SameGetterCounts(left, right)
    return left.wishlist == right.wishlist
        and left.owned == right.owned
        and left.catalog == right.catalog
end

local Overlay = Nexus.WishlistOverlay
Overlay.Init(Adapter, {})
Overlay.Show()
assert(Overlay.IsShown(), "generated overlay fixture did not show")
assert(frameCreates == 4 and fontStringCreates == 90,
    string.format("overlay widget pool drifted at creation: frames=%d lines=%d",
        frameCreates,fontStringCreates))
assert(styleCalls == 1, "overlay controls were not styled exactly once at creation")

-- Explicit and timer-driven identical refreshes must remain revision-only.
local identicalCalls = CopyCounts(calls)
local identicalMutations, identicalStyles = lineMutations, styleCalls
for _ = 1, 200 do Overlay.Refresh() end
H.Advance(200, 1)
assert(SameGetterCounts(calls, identicalCalls),
    string.format("identical visible models reacquired projections: wishlist=%d owned=%d catalog=%d",
        calls.wishlist-identicalCalls.wishlist,
        calls.owned-identicalCalls.owned,
        calls.catalog-identicalCalls.catalog))
assert(lineMutations == identicalMutations,
    "identical visible models rewrote overlay rows")
assert(styleCalls == identicalStyles,
    "identical visible models recursively restyled controls")

-- Owned-only revision refreshes only ownership and updates affected rows.
local beforeOwned = CopyCounts(calls)
local beforeOwnedMutations = lineMutations
owned.bySpell[220001] = 1
revisions.owned = revisions.owned + 1
Overlay.Refresh()
assert(calls.owned == beforeOwned.owned + 1
    and calls.wishlist == beforeOwned.wishlist
    and calls.catalog == beforeOwned.catalog,
    "owned revision invalidated unrelated overlay projections")
assert(lineMutations > beforeOwnedMutations,
    "owned revision did not update its visible row")

-- A represented revision with byte-identical output may reacquire its one
-- component but performs no row writes.
local equivalentMutations = lineMutations
revisions.owned = revisions.owned + 1
Overlay.Refresh()
assert(lineMutations == equivalentMutations,
    "byte-identical owned projection rewrote overlay rows")

-- Hidden refresh and timer paths do no revision, acquisition, row, or style
-- work. A real hidden change remains pending and renders when shown again.
Overlay.Hide()
local hiddenCalls = CopyCounts(calls)
local hiddenMutations, hiddenStyles = lineMutations, styleCalls
owned.bySpell[220002] = 1
revisions.owned = revisions.owned + 1
for _ = 1, 200 do Overlay.Refresh() end
H.Advance(200, 1)
assert(calls.revisions == hiddenCalls.revisions
    and SameGetterCounts(calls, hiddenCalls),
    "hidden overlay performed revision or projection acquisition")
assert(lineMutations == hiddenMutations and styleCalls == hiddenStyles,
    "hidden overlay performed row or style work")
Overlay.Show()
assert(calls.owned == hiddenCalls.owned + 1
    and lineMutations > hiddenMutations,
    "hidden owned transition was suppressed when the overlay reopened")

-- Wishlist and catalog revisions remain component-local and visible.
local wishlistCalls = CopyCounts(calls)
local wishlistMutations = lineMutations
wishlist.entries[1].stacks = wishlist.entries[1].stacks + 1
revisions.wishlist = revisions.wishlist + 1
Overlay.Refresh()
assert(calls.wishlist == wishlistCalls.wishlist + 1
    and calls.owned == wishlistCalls.owned
    and calls.catalog == wishlistCalls.catalog
    and lineMutations > wishlistMutations,
    "wishlist revision did not remain local and visible")

local catalogCalls = CopyCounts(calls)
local catalogMutations = lineMutations
catalog.rows[220001].name = "Renamed Generated Echo"
revisions.catalog = revisions.catalog + 1
Overlay.Refresh()
assert(calls.catalog == catalogCalls.catalog + 1
    and calls.wishlist == catalogCalls.wishlist
    and calls.owned == catalogCalls.owned
    and lineMutations > catalogMutations,
    "catalog revision did not remain local and visible")

local missingCalls = CopyCounts(calls)
local missingMutations = lineMutations
wishlist = nil
revisions.wishlist = revisions.wishlist + 1
Overlay.Refresh()
local foundMissingMessage = false
for _, line in ipairs(lineObjects) do
    if type(line.text) == "string"
        and line.text:find("No wishlist set", 1, true) then
        foundMissingMessage = true
        break
    end
end
assert(calls.wishlist == missingCalls.wishlist + 1
    and calls.owned == missingCalls.owned
    and calls.catalog == missingCalls.catalog
    and lineMutations > missingMutations and foundMissingMessage,
    "visible no-wishlist transition was suppressed or invalidated unrelated projections")
wishlist = initialWishlist
revisions.wishlist = revisions.wishlist + 1
Overlay.Refresh()

-- Position/scale/lock controls are direct transitions and cannot grow the
-- fixed widget pool or force projection work.
local controlsCalls = CopyCounts(calls)
local controlsFrames, controlsLines = frameCreates, fontStringCreates
Overlay.SetScale(1.2)
Overlay.ToggleLock()
Overlay.ToggleLock()
Overlay.ResetPosition()
assert(SameGetterCounts(calls, controlsCalls),
    "direct overlay controls reacquired presentation projections")
assert(frameCreates == controlsFrames and fontStringCreates == controlsLines,
    "direct overlay controls grew the widget pool")

local stats = assert(Overlay.Stats and Overlay.Stats(),
    "fixed overlay diagnostics are unavailable")
assert(stats.framesCreated == 4 and stats.linesCreated == 90
    and stats.cachedLineStates <= 90
    and stats.revisionSkips >= 400
    and stats.hiddenSkips >= 400
    and stats.identicalModels >= 1
    and stats.stylePasses == 1,
    string.format("overlay retained/work bounds drifted: frames=%s lines=%s cached=%s revisionSkips=%s hidden=%s identical=%s styles=%s",
        tostring(stats.framesCreated),tostring(stats.linesCreated),
        tostring(stats.cachedLineStates),tostring(stats.revisionSkips),
        tostring(stats.hiddenSkips),tostring(stats.identicalModels),
        tostring(stats.stylePasses)))
stats.framesCreated = 999
assert(Overlay.Stats().framesCreated == 4,
    "overlay diagnostics leaked mutable internal state")
stats = Overlay.Stats()

print(string.format(
    "stage25 overlay memory: refresh=%d hidden=%d revisionSkips=%d builds=%d identical=%d rowUpdates=%d styles=%d frames=%d lines=%d cached=%d getters[w=%d o=%d c=%d]",
    stats.refreshCalls,stats.hiddenSkips,stats.revisionSkips,
    stats.projectionBuilds,stats.identicalModels,stats.rowUpdates,
    stats.stylePasses,stats.framesCreated,stats.linesCreated,
    stats.cachedLineStates,calls.wishlist,calls.owned,calls.catalog))

-- Legacy/test adapters without scalar revisions retain correctness: explicit
-- Refresh may reacquire their projections, but byte-identical models still
-- produce zero row writes and the cache stays bounded.
dofile("ui/WishlistOverlay.lua")
local fallbackCalls = {wishlist=0,owned=0,catalog=0}
local Fallback = Nexus.WishlistOverlay
Fallback.Init({
    Wishlist=function() fallbackCalls.wishlist=fallbackCalls.wishlist+1; return initialWishlist end,
    Owned=function() fallbackCalls.owned=fallbackCalls.owned+1; return owned end,
    Catalog=function() fallbackCalls.catalog=fallbackCalls.catalog+1; return catalog end,
}, {})
Fallback.Show()
local fallbackMutations = lineMutations
for _ = 1, 20 do Fallback.Refresh() end
local fallbackStats = Fallback.Stats()
assert(fallbackCalls.wishlist == 21 and fallbackCalls.owned == 21
    and fallbackCalls.catalog == 21
    and lineMutations == fallbackMutations
    and fallbackStats.identicalModels == 20
    and fallbackStats.cachedLineStates == 90,
    "no-revision adapter fallback lost correctness or bounded row reuse")
print("revision-keyed overlay presentation and retained-memory bounds -- OK")
