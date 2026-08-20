-- Checkpoint 26.5: freeze the two explicitly scoped cleanup defects before
-- changing runtime source. This fixture is expected red at the 26.4 review
-- head and must become green without broadening cleanup ownership.
local failures = {}

local function Check(value, message)
    if not value then failures[#failures + 1] = message end
end

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local function CountExact(value, needle)
    local count, offset = 0, 1
    while true do
        local found = value:find(needle, offset, true)
        if not found then return count end
        count, offset = count + 1, found + #needle
    end
end

local controller = Read("core/CommunityController.lua")
Check(controller:find(
        'string.format("Destination wishlist: %s - in progress (%d/%d).",',
        1, true),
    "destination-Wishlist description still contains mojibake")

local viewer = Read("ui/LogViewer.lua")
local closeCall =
    'Nexus.Panel.CloseOtherWindows("NexusLogViewer")'
Check(CountExact(viewer, closeCall) == 1,
    "LogViewer.Show still calls CloseOtherWindows more than once")

if #failures > 0 then
    error("EXPECTED RED [Stage 26.5 scoped cleanup]:\n - "
        .. table.concat(failures, "\n - "))
end
print("Stage 26.5 scoped cleanup -- OK")
