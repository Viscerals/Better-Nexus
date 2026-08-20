-- Regression guard for Blizzard-owned globals used by protected UI paths.
-- Nexus may add namespaced entries, but it must never reassign the globals.

local files = {
    "core/GameAdapter.lua", "core/AutomationRuntime.lua",
    "core/MainLifecycle.lua", "core/Main.lua",
    "ui/WishlistEditor.lua", "ui/CommunityRenderer.lua",
    "ui/CommunityBuilds.lua",
    "ui/LogViewer.lua", "ui/Leaderboard.lua",
}

for _, path in ipairs(files) do
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()

    for _, name in ipairs({ "StaticPopupDialogs", "UISpecialFrames" }) do
        local assignment = "\n%s*" .. name .. "%s*="
        assert(not source:match(assignment)
                and not source:match("^%s*" .. name .. "%s*="),
            path .. " reassigns Blizzard-owned global " .. name)
    end
    assert(not source:match('StaticPopupDialogs%s*%[%s*["\']USE_BIND["\']%s*%]%s*='),
        path .. " overrides the stock USE_BIND confirmation")
    assert(not source:match('hooksecurefunc%s*%(%s*StaticPopup_Show'),
        path .. " hooks the protected popup dispatcher")
    assert(not source:match('StaticPopup[1-4]%s*='),
        path .. " assigns a stock popup frame global")
    assert(not source:match('ConfirmBindOnUse%s*%(')
            and not source:match('UseContainerItem%s*%('),
        path .. " drives protected item acceptance")
end

print("protected Blizzard globals remain stock-owned -- OK")
