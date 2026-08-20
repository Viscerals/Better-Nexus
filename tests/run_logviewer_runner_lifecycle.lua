local H = dofile("tests/harness.lua")

H.AssertEqual = function(actual, expected, message)
    assert(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

H.AssertTrue = function(value, message)
    assert(value, message)
end

local originalCreateFrame = CreateFrame
local created = {}
local textEvents = {}

CreateFrame = function(kind, name, parent, ...)
    local region = originalCreateFrame(kind, name, parent, ...)
    local info = {
        kind = kind,
        name = name,
        parent = parent,
        frame = region,
        delayed = kind == "Frame" and name == nil and parent == nil,
    }
    created[#created + 1] = info

    local originalSetText = region.SetText
    region.SetText = function(self, value)
        textEvents[#textEvents + 1] = tostring(value or "")
        return originalSetText(self, value)
    end
    return region
end

Nexus.Panel = nil
Nexus.Theme = nil
Nexus.PeerDebug = nil

local source = os.getenv and os.getenv("NEXUS_LOGVIEWER_SOURCE") or nil
dofile(source or "ui/LogViewer.lua")

local providerTabs = {}
local clearTabs = {}
local clearResult = true
local exportSpecs = {}
local exportSlices = 0

local function TestProvider(tab)
    providerTabs[#providerTabs + 1] = tab
    return "PAGE:" .. tostring(tab)
end

local function TestClearProvider(tab)
    clearTabs[#clearTabs + 1] = tab
    return clearResult
end

Nexus.LogViewer.Init(TestProvider, TestClearProvider)

Nexus.NewAIExportCoroutine = function()
    local spec = table.remove(exportSpecs, 1)
    H.AssertTrue(spec ~= nil, "export factory should receive a queued specification")
    return coroutine.create(function()
        for index = 1, spec.yields do
            exportSlices = exportSlices + 1
            coroutine.yield("slice " .. tostring(index))
        end
        exportSlices = exportSlices + 1
        return spec.text
    end)
end

local function RunnerCount()
    local count = 0
    for _, info in ipairs(created) do
        if info.delayed then count = count + 1 end
    end
    return count
end

local function ActiveRunnerCount()
    local count = 0
    for _, info in ipairs(created) do
        if info.delayed and info.frame:GetScript("OnUpdate") then
            count = count + 1
        end
    end
    return count
end

local function Tick(delta)
    H.now = H.now + delta
    local callbacks = {}
    for _, info in ipairs(created) do
        local callback = info.frame:GetScript("OnUpdate")
        if callback then
            callbacks[#callbacks + 1] = { frame = info.frame, callback = callback }
        end
    end
    for _, entry in ipairs(callbacks) do
        if entry.frame:GetScript("OnUpdate") == entry.callback then
            entry.callback(entry.frame, delta)
        end
    end
end

local function FindButton(text)
    for _, info in ipairs(created) do
        if info.kind == "Button"
            and info.frame:GetText() == text
            and info.frame:GetScript("OnClick")
        then
            return info.frame
        end
    end
    error("button not found: " .. tostring(text))
end

local function Click(button)
    button:GetScript("OnClick")(button)
end

local function SawTextSince(text, firstIndex)
    for index = firstIndex, #textEvents do
        if textEvents[index] == text then return true end
    end
    return false
end

local function HideViewer(viewer)
    viewer:Hide()
    local onHide = viewer:GetScript("OnHide")
    if onHide then onHide(viewer) end
end

Nexus.LogViewer.Show("state")
H.AssertEqual(RunnerCount(), 1, "initial show should allocate only the reusable repaint runner")

for _ = 1, 100 do
    Nexus.LogViewer.Show("state")
end
H.AssertEqual(RunnerCount(), 1, "100 coalesced repaint requests should allocate no runner frames")
Tick(0.049)
H.AssertEqual(#providerTabs, 0, "repaint should retain its short delay")
Tick(0.001)
H.AssertEqual(#providerTabs, 1, "coalesced repaint requests should produce one repaint")
H.AssertEqual(ActiveRunnerCount(), 0, "repaint runner should idle without OnUpdate")

local refreshButton = FindButton("Refresh")
local tabs = { "errors", "sync", "state" }
for index = 1, 12 do
    Nexus.LogViewer.Show(tabs[((index - 1) % #tabs) + 1])
    Click(refreshButton)
    Tick(0.05)
    H.AssertEqual(RunnerCount(), 1, "tab and refresh repaint cycles should reuse one runner")
end
H.AssertEqual(ActiveRunnerCount(), 0, "repeated repaint cycles should leave no runner active")

local exportButton = FindButton("Copy Full Diagnostic Log")
exportSpecs[#exportSpecs + 1] = { text = "FINAL-OLD", yields = 0 }
Click(exportButton)
H.AssertEqual(RunnerCount(), 2, "first export should allocate one reusable slicer")
local beforeSlice = exportSlices
Tick(0.05)
H.AssertEqual(exportSlices - beforeSlice, 1, "export should resume once in a rendered frame")
H.AssertEqual(RunnerCount(), 3, "first completion should allocate one reusable finisher")

exportSpecs[#exportSpecs + 1] = { text = "FINAL-NEW", yields = 3 }
Click(exportButton)
local newerExportEvent = #textEvents + 1
for _ = 1, 6 do
    beforeSlice = exportSlices
    Tick(0.05)
    H.AssertTrue(exportSlices - beforeSlice <= 1, "export must run at most one coroutine slice per frame")
end
H.AssertTrue(not SawTextSince("FINAL-OLD", newerExportEvent), "stale export must not overwrite newer text")
H.AssertTrue(SawTextSince("FINAL-NEW", newerExportEvent), "new export should finish on its later frame")
H.AssertEqual(ActiveRunnerCount(), 0, "completed export should leave slicer and finisher idle")

for index = 1, 4 do
    exportSpecs[#exportSpecs + 1] = { text = "FINAL-" .. tostring(index), yields = 0 }
    Click(exportButton)
    Tick(0.05)
    Tick(0.05)
    Tick(0.05)
    H.AssertEqual(RunnerCount(), 3, "repeated exports should reuse slicer and finisher")
    H.AssertEqual(ActiveRunnerCount(), 0, "repeated exports should finish with no active runner")
end

Nexus.LogViewer.Show("errors")
Tick(0.05)
local clearButton = FindButton("Clear Log")
clearResult = true
Click(clearButton)
H.AssertEqual(clearButton:GetText(), "Cleared", "successful clear should report Cleared")
H.AssertEqual(RunnerCount(), 4, "first clear should allocate one reusable reset runner")
Tick(0.6)

clearResult = false
Click(clearButton)
H.AssertEqual(clearButton:GetText(), "Clear Failed", "later clear should replace the button state")
Tick(0.61)
H.AssertEqual(clearButton:GetText(), "Clear Failed", "stale reset must not clear the later button state")
Tick(0.58)
H.AssertEqual(clearButton:GetText(), "Clear Failed", "latest reset should retain its full delay")
Tick(0.02)
H.AssertEqual(clearButton:GetText(), "Clear Log", "latest reset should restore the button label")
H.AssertEqual(clearTabs[#clearTabs - 1], "errors", "successful clear should route the active diagnostic tab")
H.AssertEqual(clearTabs[#clearTabs], "errors", "failed clear should route the active diagnostic tab")
H.AssertEqual(ActiveRunnerCount(), 0, "clear reset should idle without OnUpdate")

clearResult = true
for _ = 1, 5 do
    Click(clearButton)
    Tick(1.21)
    H.AssertEqual(RunnerCount(), 4, "repeated clears should reuse one reset runner")
    H.AssertEqual(clearButton:GetText(), "Clear Log", "repeated clear should restore its button label")
end

exportSpecs[#exportSpecs + 1] = { text = "HIDDEN-EXPORT", yields = 10 }
Click(exportButton)
Nexus.LogViewer.Show("state")
local viewer = H.frames.NexusLogViewer
HideViewer(viewer)
H.AssertEqual(ActiveRunnerCount(), 0, "hiding should disable repaint and export runners")
local hiddenSlices = exportSlices
local hiddenProviderCalls = #providerTabs
Tick(0.5)
Tick(0.5)
H.AssertEqual(exportSlices, hiddenSlices, "hidden export should remain canceled")
H.AssertEqual(#providerTabs, hiddenProviderCalls, "hidden repaint should remain canceled")

Nexus.LogViewer.Show("errors")
Click(clearButton)
HideViewer(viewer)
H.AssertEqual(ActiveRunnerCount(), 0, "hiding should disable the clear reset runner")
H.AssertEqual(clearButton:GetText(), "Clear Log", "hidden clear state should safely return to idle")
H.AssertEqual(RunnerCount(), 4, "all delayed work should use the fixed four-runner set")

CreateFrame = originalCreateFrame
print("LogViewer runners=4 repaint=coalesced export=guarded clear=guarded hidden=idle slices=one/frame -- OK")
