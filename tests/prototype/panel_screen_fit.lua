-- Offline panel viewport regression: real HUD render and anchor geometry,
-- synthetic 800x600 UI viewport and 2x owned-font model. The harness does
-- not implement native clamping or pixel drawing.
local H = dofile('tests/prototype/harness.lua')
H.Boot()
local G = dofile('tests/prototype/layout_geometry_support.lua')
G.UseFont(G.MODELS.double)
UIParent:SetSize(800, 600)
NexusDB.uiShowPerformance = true
Nexus.Panel.Show()
Nexus.CallboardStatus.GetSummary = function()
    return {observed=true, title='Callboard objective',
        lines={'Bring the tome'}, rewards={}}
end

local model = {
    status='ready', level=40, auto=false, cards={},
    recommendation='Review the next choice',
    progress={wishlistName='Synthetic plan', total=6, owned=1,
        missing={}, shed={}, toLock={}, unknownTomes={}},
    serverStatus={tier='Hardcore I', ash='500', gain='20', intensity=0.5},
}
local function Render()
    assert(Nexus.Panel.Render(model), 'synthetic HUD model renders')
    local panel = assert(NexusPanel)
    assert(panel._callboardTitle:IsShown(), 'the Callboard title is visible')
    assert(panel._responsiveLayout.boxes.callboard, 'responsive Callboard box exists')
    return panel
end

local panel = Render()
assert(panel:GetHeight() > UIParent:GetHeight(),
    'fixture: at 2x font the real HUD layout exceeds the 600px viewport')
local function Fits(tag)
    local margin = 24
    assert(panel:GetHeight() * panel:GetScale() <= UIParent:GetHeight() - margin + 0.01,
        tag .. ': panel height stays inside the viewport with margin')
    assert(panel:GetWidth() * panel:GetScale() <= UIParent:GetWidth() - margin + 0.01,
        tag .. ': panel width stays inside the viewport with margin')
end
Fits('initial render')

-- A viewport change does not alter the model or font signature. Fit must
-- still update on an otherwise settled render.
UIParent:SetSize(1200, 900)
Render()
assert(panel:GetScale() == 1, 'a larger viewport restores the native panel scale')
UIParent:SetSize(800, 600)
Render()
Fits('settled render after viewport shrinks')

print('PASS panel_screen_fit')
