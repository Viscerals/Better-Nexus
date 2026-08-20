-- Nexus: core/MainCommands.lua
-- Pure slash normalization and single-callback dispatch owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local Commands = {}
Nexus.MainInternals.Commands = Commands

local EXACT = {
    auto="auto", panel="panel", restore="restore", flags="flags",
    status="status", wishlist="wishlist", check="wishlist",
    progress="progress", missing="missing", editor="editor",
    syncdebug="syncdebug", nameplate="nameplate", dps="dps", sync="sync",
    builds="builds", leaderboard="leaderboard", ranks="leaderboard",
    ["log errors"]="errors", errors="errors",
    perf="performance", performance="performance",
    log="log", logs="log", err="err", undemote="undemote",
    overlay="overlay", logclear="logclear",
}

function Commands.New(options)
    options = options or {}
    local callbacks = type(options.callbacks) == "table" and options.callbacks or {}
    local isInitialized = type(options.isInitialized) == "function"
        and options.isInitialized or function() return false end
    local prepare = type(options.prepare) == "function"
        and options.prepare or function() return nil end
    local notInitialized = options.notInitialized
    local M = {}

    local function Invoke(name, context, normalized, argument)
        local callback = callbacks[name]
        if type(callback) == "function" then
            callback(context, normalized, argument)
        end
    end

    function M.Dispatch(message)
        if not isInitialized() then
            if type(notInitialized) == "function" then notInitialized() end
            return
        end

        -- Deliberately retain the historical type behavior: a non-string,
        -- non-nil input fails at :lower() instead of being stringified.
        local normalized = (message or ""):lower()
            :gsub("^%s+", ""):gsub("%s+$", "")
        -- Main historically read settings once before selecting every branch,
        -- including passive, unknown, and retired compatibility commands.
        local context = prepare()
        local exact = EXACT[normalized]
        if exact then
            Invoke(exact, context, normalized)
            return
        end
        if normalized:sub(1, 6) == "probe " then
            local target = normalized:sub(7):match("^%s*(.-)%s*$")
            Invoke("probe", context, normalized, target)
            return
        end
        if normalized:match("^anchor") then
            local argument = normalized:match("^anchor%s+(%S+)")
            Invoke("anchor", context, normalized, argument)
            return
        end
        Invoke("help", context, normalized)
    end

    return M
end
