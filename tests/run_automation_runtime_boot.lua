-- Boot the exact TOC sequence after the external upvalue compatibility gate.
-- This proves the constrained AutomationRuntime chunk registers its factory,
-- Main resolves that factory, and normal world entry reaches initialization
-- without silently retaining an error.
local H = dofile("tests/harness.lua")

local handle = assert(io.open("Nexus.toc", "r"))
local toc = assert(handle:read("*a"))
handle:close()

local factoryCalls = 0
local tocLuaFiles = 0
for raw in toc:gmatch("[^\r\n]+") do
    local file = raw:match("^%s*(.-)%s*$")
    if file ~= "" and not file:find("^#") and file:find("%.lua$") then
        file = file:gsub("\\", "/")
        dofile(file)
        tocLuaFiles = tocLuaFiles + 1
        if file == "core/AutomationRuntime.lua" then
            local factory = Nexus.MainInternals
                and Nexus.MainInternals.AutomationRuntime
            assert(factory and type(factory.New) == "function",
                "AutomationRuntime factory did not register in TOC order")
            local original = factory.New
            factory.New = function(options)
                factoryCalls = factoryCalls + 1
                return original(options)
            end
        end
    end
end

assert(tocLuaFiles == 68, "boot fixture did not load every TOC Lua file")
assert(type(SlashCmdList.NEXUS) == "function",
    "Main did not register the Nexus command owner")

NexusDB = {}
H.playerLevel = 5
H.wishlist = {
    name="Upvalue Boot",class="MAGE",echoes={
        {spellId=200100,quality=3,stacks=1},
    },
}

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.4, 0.2)

assert(factoryCalls == 1,
    "Main did not resolve exactly one AutomationRuntime instance")
assert(Nexus.RequestRecompute() == true,
    "initialized Main did not route recompute to AutomationRuntime")
local stats = Nexus.RecomputeStats()
assert(type(stats) == "table" and stats.polls > 0,
    "normal lifecycle update did not reach AutomationRuntime")
assert(Nexus.lastError == nil,
    "normal boot suppressed an initialization error: "
        .. tostring(Nexus.lastError))

local startupBanner = false
local notInitialized = false
for _, line in ipairs(H.chat) do
    if line:find("v1.20.0%-beta%.1 %-%- type /nexus for commands%.") then
        startupBanner = true
    end
    if line:find("not initialized yet", 1, true) then
        notInitialized = true
    end
end
assert(startupBanner, "normal startup banner was not emitted")
assert(not notInitialized, "boot retained the not-initialized refusal path")

print(string.format(
    "automation boot: toc=%d factoryCalls=%d polls=%d banner=yes error=none",
    tocLuaFiles, factoryCalls, stats.polls))
print("AutomationRuntime constrained compile, factory, Main, and lifecycle boot -- OK")
