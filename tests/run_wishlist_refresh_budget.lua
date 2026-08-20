-- Stage 36.6: identical Wishlist refreshes must stay on a scalar revision
-- path.  Product work is counted through real adapter, sort, theme, frame,
-- retry, filter, scroll, overlay-scale, and OnUpdate owners.

local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")

NexusDB = {
    settingsVersion=2,settings={},chars={},dpsCapture={},
    editorClassOnly=false,overlayScale=1,overlayLocked=true,
    futureRoot={keep=true},
}
UISpecialFrames = {}
Nexus.Store.Init()

local desired, expectedRed, controls = 0, 0, 0
local failures = {}
local function Desired(name, condition, detail)
    desired = desired + 1
    if not condition then
        expectedRed = expectedRed + 1
        failures[#failures + 1] = name .. ": " .. detail
    end
end
local function Control(condition, detail)
    controls = controls + 1
    if not condition then error("control failed: " .. detail, 0) end
end

local work = {
    catalog=0,owned=0,locked=0,wishlist=0,candidates=0,slots=0,
    revisions=0,sorts=0,styles=0,styleWindows=0,uploads=0,
    associations=0,
}
local revisions = {
    slots=1,active=1,granted=1,owned=1,wishlist=1,catalog=1,
    locked=1,lockedProjection=1,discovery=1,lever=1,firstRun=0,
}
local catalog = {rows={},playerMask=1}
for index = 1, 1000 do
    local spellId = 860000 + index
    catalog.rows[spellId] = {
        spellId=spellId,groupId=spellId,
        name=string.format("Refresh Echo %04d",index),
        quality=index % 5,maxStack=2,classMask=1,
    }
end
local draft = {}
for index = 1, 35 do
    draft[index] = {
        spellId=860000+index,quality=index % 5,stacks=1,
    }
end

local Adapter = {
    PresentationRevisions=function()
        work.revisions = work.revisions + 1
        return revisions.slots,revisions.active,revisions.granted,
            revisions.owned,revisions.wishlist,revisions.catalog,
            revisions.locked,revisions.lockedProjection,
            revisions.discovery,revisions.lever,revisions.firstRun
    end,
    Catalog=function() work.catalog=work.catalog+1; return catalog end,
    Owned=function()
        work.owned=work.owned+1
        return {bySpell={},byFamily={}}
    end,
    LockedOwned=function()
        work.locked=work.locked+1
        return {bySpell={}}
    end,
    Wishlist=function() work.wishlist=work.wishlist+1; return nil end,
    GetWishlistCandidates=function()
        work.candidates=work.candidates+1
        return {}
    end,
    Slots=function()
        work.slots=work.slots+1
        return {activeSlot=0,maxSlots=5,bySlot={}}
    end,
    GetLoadoutWishlist=function() return nil end,
    WishlistKey=function() return "refresh-fixture" end,
    UploadWishlist=function()
        work.uploads=work.uploads+1
        return false,"spacing"
    end,
    SetLoadoutWishlist=function()
        work.associations=work.associations+1
        return true
    end,
    SetFirstRunWishlist=function()
        work.associations=work.associations+1
        return true
    end,
}

Nexus.Panel = {
    AttachMenuFrame=function() end,
    CloseOtherWindows=function() end,
}
Nexus.Theme = {
    StyleWindow=function() work.styleWindows=work.styleWindows+1 end,
    StyleTree=function() work.styles=work.styles+1 end,
}

local created = {}
local realCreateFrame = CreateFrame
CreateFrame = function(kind,name,parent,template)
    local frame = realCreateFrame(kind,name,parent,template)
    frame._kind,frame._name,frame._parent,frame._template =
        kind,name,parent,template
    created[#created+1] = frame
    return frame
end
local realSort = table.sort
table.sort = function(...)
    work.sorts=work.sorts+1
    return realSort(...)
end

dofile("ui/WishlistEditor.lua")
local Editor = Nexus.WishlistEditor
Editor.Init(Adapter,Nexus.Model)
Control(Editor.OpenForCandidate({title="Refresh Budget",echoes=draft}),
    "legacy draft did not open")
local main = assert(H.frames.NexusEditorFrame,"editor frame missing")
Control(main:IsShown(),"editor was not shown")

local leftArea,pickArea,applyButton
for _,frame in ipairs(created) do
    if frame._kind=="Frame" and frame._parent==main
        and frame.w==600 and frame.h==19*24 then leftArea=frame end
    if frame._kind=="Frame" and frame._parent==main
        and frame.w==332 and frame.h==18*24 then pickArea=frame end
    if frame._kind=="Button" and frame._parent==main
        and frame.text=="Create Wishlist" then applyButton=frame end
end
Control(leftArea and pickArea and applyButton,
    "fixed viewports or Apply control missing")
local function DirectRows(parent)
    local count=0
    for _,frame in ipairs(created) do
        if frame._kind=="Button" and frame._parent==parent then
            count=count+1
        end
    end
    return count
end
Control(DirectRows(leftArea)==19 and DirectRows(pickArea)==18,
    "fixed Wishlist row pools changed")

-- Establish non-zero scroll and a real retained retry. These are deliberately
-- live controller states, not synthetic renderer-only flags.
leftArea:GetScript("OnMouseWheel")(leftArea,-1)
pickArea:GetScript("OnMouseWheel")(pickArea,-1)
applyButton:GetScript("OnClick")(applyButton)
Control(H.AcceptLastStaticPopup(),"Apply confirmation was not registered")
Control(Editor.IsApplyPending() and work.uploads==1,
    "spacing retry was not retained")
Editor.Refresh()
local baselineState = Editor.DebugDraftState()
local baselineFrames = #created
Control(baselineState.pending==35 and baselineState.scrollOffset>0
        and baselineState.pickOffset>0,
    "draft or scroll fixture did not materialize")

local function Snapshot()
    return {
        catalog=work.catalog,sorts=work.sorts,styles=work.styles,
        frames=#created,uploads=work.uploads,associations=work.associations,
    }
end
local function Delta(before,key)
    return (key=="frames" and #created or work[key])-before[key]
end
local function ZeroProjection(prefix,before)
    Desired(prefix.."_catalog",Delta(before,"catalog")==0,
        "identical refresh walked the catalog")
    Desired(prefix.."_sort",Delta(before,"sorts")==0,
        "identical refresh sorted a projection")
    Desired(prefix.."_style",Delta(before,"styles")==0,
        "identical refresh recursively restyled the tree")
end

local warm = Snapshot()
for _=1,5 do Editor.Refresh() end
ZeroProjection("warm",warm)
Control(#created==baselineFrames,"warm refresh rebuilt a fixed pool")
local warmState=Editor.DebugDraftState()
Control(warmState.pending==baselineState.pending
        and warmState.pendingLock==baselineState.pendingLock
        and warmState.scrollOffset==baselineState.scrollOffset
        and warmState.pickOffset==baselineState.pickOffset
        and Editor.IsApplyPending(),
    "warm refresh changed draft, scroll, or retry state")
Control(work.associations==0 and NexusDB.futureRoot.keep,
    "warm refresh mutated association or unknown state")

-- The half-second ticker may advance one retained retry and update its button,
-- but it must not re-enter catalog projection, sorting, or recursive styling.
local timer = Snapshot()
main:GetScript("OnUpdate")(main,0.5)
ZeroProjection("timer",timer)
Control(work.uploads==timer.uploads+1 and Editor.IsApplyPending(),
    "timer did not advance exactly one retained retry")
Control(applyButton.text=="Saving...", "timer status text is stale")
local timerState=Editor.DebugDraftState()
Control(timerState.pending==baselineState.pending
        and timerState.scrollOffset==baselineState.scrollOffset
        and timerState.pickOffset==baselineState.pickOffset
        and #created==baselineFrames and work.associations==0,
    "timer-only update changed draft, scroll, pools, or association")

-- A filter change owns exactly one catalog projection rebuild. Styling is not
-- part of the filter owner, and the immediately following refresh is warm.
local search=assert(H.frames.NexusEditorSearch,"search box missing")
local filtered=Snapshot()
search:SetText("Refresh Echo 00")
search:GetScript("OnTextChanged")(search)
Control(Delta(filtered,"catalog")>0 and Delta(filtered,"sorts")>0,
    "filter change did not rebuild its catalog projection")
Desired("filter_style",Delta(filtered,"styles")==0,
    "filter change recursively restyled the frame")
local filteredWarm=Snapshot()
Editor.Refresh()
ZeroProjection("filtered_warm",filteredWarm)

-- Replacing the theme owner is a real theme change: exactly one styling pass
-- is required, while catalog and sort ownership remains quiet.
Nexus.Theme.StyleTree=function() work.styles=work.styles+1 end
local themed=Snapshot()
Editor.Refresh()
Desired("theme_catalog",Delta(themed,"catalog")==0,
    "theme-only change walked the catalog")
Desired("theme_sort",Delta(themed,"sorts")==0,
    "theme-only change sorted a projection")
Control(Delta(themed,"styles")==1,
    "theme-owner change did not perform exactly one style pass")
local themedWarm=Snapshot()
Editor.Refresh()
ZeroProjection("theme_warm",themedWarm)

-- The overlay already has its own revision cache. A theme-owner replacement
-- must be noticed once, and a scale-only update must remain data/style quiet.
dofile("ui/WishlistOverlay.lua")
local Overlay=Nexus.WishlistOverlay
Overlay.Init(Adapter,Nexus.Model)
Overlay.Show()
local overlayFrames=#created
local overlayTheme=function() work.styles=work.styles+1 end
Nexus.Theme.StyleTree=overlayTheme
local overlayThemed=Snapshot()
Overlay.Refresh()
Desired("overlay_theme",Delta(overlayThemed,"styles")==1,
    "overlay ignored its new theme owner")
Desired("overlay_theme_catalog",Delta(overlayThemed,"catalog")==0,
    "overlay theme change reacquired the catalog")
Desired("overlay_theme_sort",Delta(overlayThemed,"sorts")==0,
    "overlay theme change resorted rows")

local overlayFrame=assert(H.frames.NexusOverlay,"overlay frame missing")
local controlsFrame=assert(H.frames.NexusOverlayControls,
    "overlay controls frame missing")
overlayFrame.SetScale=function(self,value) self.appliedScale=value end
controlsFrame.SetScale=function(self,value) self.appliedScale=value end
local scaled=Snapshot()
Overlay.SetScale(1.25)
Control(NexusDB.overlayScale==1.25
        and overlayFrame.appliedScale==1.25
        and controlsFrame.appliedScale==1.25,
    "overlay scale owner did not apply the exact value")
ZeroProjection("scale",scaled)
Control(#created==overlayFrames,"theme/scale change rebuilt overlay pools")

table.sort=realSort
print(string.format(
    "wishlist refresh budget: desired=%d expected_red=%d controls=%d catalog=%d sorts=%d styles=%d frames=%d retries=%d associations=%d",
    desired,expectedRed,controls,work.catalog,work.sorts,work.styles,#created,
    work.uploads,work.associations))
if expectedRed>0 then
    error("Wishlist refresh expected red ("..tostring(expectedRed).."):\n - "
        ..table.concat(failures,"\n - "),0)
end
print("Wishlist revision/filter cache, timer status, theme, scale, and fixed pools -- OK")
