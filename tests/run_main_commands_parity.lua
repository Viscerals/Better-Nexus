-- Main command routing preserves exact normalization, aliases, prefix quirks,
-- callback order, passive unknown handling, and nil return behavior.
Nexus = {}
dofile("core/MainCommands.lua")

local factory = Nexus.MainInternals and Nexus.MainInternals.Commands
assert(factory and type(factory.New) == "function",
    "MainCommands internal constructor is unavailable")

local initialized, preparing = false, 0
local calls, context = {}, {settings=true}
local callbacks = {}
local names = {"auto","panel","restore","flags","status","wishlist",
    "progress","missing","editor","syncdebug","probe","nameplate","dps",
    "sync","builds","leaderboard","errors","performance","log","logclear","err",
    "undemote","overlay","anchor","help"}
for _, name in ipairs(names) do
    callbacks[name] = function(receivedContext, normalized, argument)
        calls[#calls + 1] = {name=name,context=receivedContext,
            normalized=normalized,argument=argument}
        return "must be discarded"
    end
end

local notReady = 0
local commands = factory.New({
    callbacks=callbacks,
    isInitialized=function() return initialized end,
    prepare=function() preparing=preparing+1; return context end,
    notInitialized=function() notReady=notReady+1 end,
})

assert(commands.Dispatch("auto")==nil and notReady==1 and preparing==0
    and #calls==0,
    "pre-initialization command routing changed")
initialized = true

local cases = {
    {"  AuTo  ","auto","auto"}, {"panel","panel"},
    {"restore","restore"}, {"flags","flags"}, {"status","status"},
    {"wishlist","wishlist"}, {"check","wishlist"},
    {"progress","progress"}, {"missing","missing"}, {"editor","editor"},
    {"syncdebug","syncdebug"}, {"nameplate","nameplate"}, {"dps","dps"},
    {"sync","sync"}, {"builds","builds"},
    {"leaderboard","leaderboard"}, {"ranks","leaderboard"},
    {"log errors","errors"}, {"errors","errors"},
    {"perf","performance"}, {"performance","performance"},
    {"log","log"}, {"logs","log"}, {"err","err"},
    {"undemote","undemote"}, {"overlay","overlay"},
    {"probe   Peer Name  ","probe","probe   peer name","peer name"},
    {"anchor 200100 extra","anchor","anchor 200100 extra","200100"},
    {"anchor\tOFF","anchor","anchor\toff","off"},
    {"anchorfoo","anchor","anchorfoo",nil},
    {"", "help", ""}, {"unknown", "help", "unknown"},
    {"sniff", "help", "sniff"}, {"sniffdump", "help", "sniffdump"},
    {"logclear", "logclear", "logclear"}, {"probe ", "help", "probe"},
}

for index, row in ipairs(cases) do
    local before = #calls
    assert(commands.Dispatch(row[1])==nil and #calls==before+1,
        "command did not dispatch exactly once at case "..index)
    local call = calls[#calls]
    assert(call.name==row[2] and call.context==context
        and call.normalized==(row[3] or row[1]) and call.argument==row[4],
        "command route/argument changed at case "..index..": "..tostring(row[1]))
end
assert(preparing==#cases,
    "initialized command did not prepare settings exactly once")

local beforeMalformed, preparesMalformed = #calls, preparing
assert(not pcall(commands.Dispatch, 42)
    and #calls==beforeMalformed and preparing==preparesMalformed,
    "non-string command input no longer fails before preparation/dispatch")

local errorCommands = factory.New({
    callbacks={auto=function() error("callback failure") end},
    isInitialized=function() return true end,
    prepare=function() return context end,
})
assert(not pcall(errorCommands.Dispatch,"auto"),
    "command callback failure was swallowed")

local sourceFile=assert(io.open("core/MainCommands.lua","r"))
local source=sourceFile:read("*a"); sourceFile:close()
for _, forbidden in ipairs({"NexusDB","Nexus.GameAdapter","ProjectEbonhold",
    "CreateFrame","SlashCmdList","SendAddonMessage","Nexus.Sync"}) do
    assert(not source:find(forbidden,1,true),
        "MainCommands acquired service/global authority: "..forbidden)
end
print("exact slash normalization, aliases, prefixes, order, and passivity -- OK")
