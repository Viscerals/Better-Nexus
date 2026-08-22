-- Real Main command callbacks retain exact output and one established target.
local H=dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Relay.lua"); dofile("logic/Policy.lua")
dofile("core/Store.lua"); dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua"); dofile("ui/Panel.lua")

local calls={panel=0,panelAuto=0,editor=0,syncdebug=0,probe=0,sync=0,
    builds=0,leaderboard=0,errors=0,performance=0,log=0,logclear=0,
    overlay=0,restore=0}
Nexus.LogViewer={Init=function() end,Show=function(key)
    local counter=(key=="sync" and "syncdebug") or (key=="perf" and "performance") or key
    calls[counter]=calls[counter]+1
end,
    Toggle=function() calls.log=calls.log+1 end}
Nexus.WishlistEditor={Init=function() end,Toggle=function() calls.editor=calls.editor+1 end}
Nexus.WishlistOverlay={Init=function() end,Toggle=function() calls.overlay=calls.overlay+1 end}
Nexus.CommunityBuilds={Init=function() end,Toggle=function() calls.builds=calls.builds+1 end}
Nexus.Leaderboard={Init=function() end,Toggle=function() calls.leaderboard=calls.leaderboard+1 end}
Nexus.Nameplate={Init=function() end}
Nexus.Sync={
    RequestSync=function() calls.sync=calls.sync+1; return true end,
    SendStatusTo=function(target) calls.probe=calls.probe+1; calls.probeTarget=target; return true end,
    OnUpdate=function() end,
}
Nexus.DpsCapture={
    Init=function() end,OnUpdate=function() end,
    IsDetailsAvailable=function() return true end,
    GetEchoKey=function() return "wishlist-key" end,
    GetCurrentEchoKey=function() return "current-key" end,
}
Nexus.Errors={Latest=function() return {message="retained error"} end}
Nexus.DiagnosticLogs.ClearAll=function()
    calls.logclear=calls.logclear+1
    return true
end

dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB={}
H.playerLevel=5; H.granted={}
local commandFactory=Nexus.MainInternals.Commands
Nexus.MainInternals.Commands=nil
H.chat={}
assert(SlashCmdList.NEXUS("status")==nil
    and H.chat[1]=="|cff7fd5ffNexus:|r not initialized yet",
    "missing command factory did not fail closed before initialization")
Nexus.MainInternals.Commands=commandFactory
H.chat={}
assert(SlashCmdList.NEXUS("status")==nil
    and H.chat[1]=="|cff7fd5ffNexus:|r not initialized yet",
    "pre-initialization command did not preserve its exact response")
H.FireEvent("ADDON_LOADED","Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")

local Adapter=Nexus.GameAdapter
local catalog={rows={[200100]={name="Alpha",quality=3}},
    familyName={[10]="Ten"},familyOf={[200100]=10}}
local wishlist={name="Goal",source="designed",entries={
    {spellId=200100,family=10,quality=3,stacks=1},
}}
local slots={activeSlot=1,bySlot={[1]={slot=1,name="Saved",verified=true,
    verifiedFieldPresent=true,suspectParse=false,echoes={
        {spellId=200100,family=10,quality=3,stacks=1},
    }}}}
local owned={distinct=1,synced=true,byFamily={[10]=1},bySpell={[200100]=1}}
Adapter.Catalog=function() return catalog end
Adapter.Wishlist=function() return wishlist end
Adapter.WishlistNote=function() return nil end
Adapter.Slots=function() return slots end
Adapter.Owned=function() return owned end
Adapter.LockedOwned=function() return {byFamily={},bySpell={}} end
Adapter.Level=function() return 5 end
Adapter.RestoreAutoAccept=function() calls.restore=calls.restore+1; return true end
Adapter.UnknownTomesForEchoes=function() return {} end
Adapter.WishlistKey=function() return "goal-key" end
Nexus.Strategy.Compile=function()
    return {wishedFamilies={[10]=true},targets={[10]={targetStacks=1,
        qualityTiers={{spellId=200100,q=3,n=1}}}},leverPlan={disable={},
        skippedNonConformant={}},advisorOnly=false}
end
Nexus.Ratchet.BestSlot=function() return 1 end
Nexus.Panel.Toggle=function() calls.panel=calls.panel+1 end
Nexus.Panel.SetAuto=function() calls.panelAuto=calls.panelAuto+1 end

local prefix="|cff7fd5ffNexus:|r "
local function Run(command)
    H.chat={}
    local result=SlashCmdList.NEXUS(command)
    local out={}
    for index,line in ipairs(H.chat) do
        out[index]=line:sub(1,#prefix)==prefix and line:sub(#prefix+1) or line
    end
    return result,table.concat(out,"\n")
end
local function Expect(command,expected)
    local result,actual=Run(command)
    assert(result==nil and actual==expected,
        "command output changed for "..command.."\nEXPECTED:\n"..expected.."\nACTUAL:\n"..actual)
end

Nexus.Release.buildLabel="test.13-abcdef0"
Expect("auto","auto ON")
assert(calls.panelAuto==1,"auto did not update Panel exactly once")
Expect("restore","client auto-accept restored")
Expect("status",table.concat({
    "v"..Nexus.VERSION.." build=test.13-abcdef0 -- level 5, auto ON",
    "TARGET: |cff7fff7f'Goal'|r (your Echo Wishlist build) -- 1 echoes",
    "ACTIVE slot 1 'Saved': snapshot (arms the guarantee), 1 echoes",
    "READABLE: 1 loadout snapshot(s), 0 designed wishlist build(s)",
    "Would arm snapshot slot 1 at level 1.",
    "OWNED this run: 1 echoes (synced).",
},"\n"))
Expect("wishlist",table.concat({
    "reading |cff7fff7f'Goal'|r (from your Echo Wishlist build) -- 1 echoes, 1 families",
    "  Alpha",
},"\n"))
Expect("progress","this run: |cff7fff7f1/1|r echoes (100%) -- 0 still short")
Expect("missing","this run: |cff7fff7f1/1|r echoes (100%) -- 0 still short")
Expect("nameplate",table.concat({
    "Mouseover tooltip: active.",
    "Nexus users seen on the sync mesh are tagged, with leaderboard data when available.",
},"\n"))
Expect("dps",table.concat({
    "|cff4dff80DPS capture is active.|r",
    "Fight the Lich King or hit a training dummy to record your best.",
    "Selected wishlist key: wishlist-key",
    "Current tracked Echo key: current-key",
    "Open /nexus log and select DPS for the full capture trace.",
},"\n"))
Expect("sync","asking other players for their builds -- results appear in /nexus builds")
Expect("err","retained error")
Nexus.Store.State().flagDemotions={DISABLE_SUPPRESSES_GUARANTEE="fixture"}
Expect("flags",table.concat({
    "DISABLE_SUPPRESSES_GUARANTEE = false",
    "demoted DISABLE_SUPPRESSES_GUARANTEE: fixture",
},"\n"))
Expect("undemote","flag demotions cleared (they re-arm on fresh evidence)")
Expect("anchor 200100","anchor set to 200100")
assert(Nexus.Store.Settings().anchorSpellId==200100,"anchor set missed established settings")
Expect("anchorfoo","anchor cleared")
assert(Nexus.Store.Settings().anchorSpellId==nil,"anchor prefix clear behavior changed")
Expect("unknown",table.concat({
    "v"..Nexus.VERSION.." -- loading",
    "|cffffd200Nexus v"..Nexus.VERSION.."|r  --  /nexus (or /nx, /wr)",
    "|cffffd200Setup:|r  builds  |  leaderboard  |  editor  |  sync  |  overlay",
    "|cffffd200Run:|r    auto  |  panel  |  status  |  wishlist  |  progress",
    "|cffffd200Data:|r   log  |  perf  |  dps  |  nameplate  |  logclear",
    "|cffffd200Fixes:|r  flags  |  undemote  |  anchor <id|off>  |  restore  |  err",
},"\n"))

for _, command in ipairs({"panel","editor","syncdebug","builds","leaderboard",
    "errors","performance","log","overlay"}) do
    local _,output=Run(command); assert(output=="","unexpected output for "..command)
end
local logcount = calls.log
local durableSentinels={
    settings=NexusDB.settings,chars=NexusDB.chars,
    communityBuilds={keep="community"},bundledBaseline={keep="baseline"},
    tombstones={keep="tombstones"},wishlists={keep="wishlists"},
    associations={keep="associations"},automationState={keep="automation"},
    activeSavedBuild={keep="saved-build"},projectEbonhold={keep="ebonhold"},
}
for key,value in pairs(durableSentinels) do NexusDB[key]=value end
Expect("logclear","diagnostic history cleared")
assert(calls.log==logcount and calls.logclear==1,
    "logclear toggled LogViewer or missed the diagnostic clear owner")
for key,value in pairs(durableSentinels) do
    assert(NexusDB[key]==value,
        "logclear replaced durable product state: "..tostring(key))
end
Nexus.DiagnosticLogs.ClearAll=function()
    calls.logclear=calls.logclear+1
    return false,"fixture refusal"
end
Expect("logclear","could not clear diagnostic history")
assert(calls.log==logcount and calls.logclear==2,
    "failed logclear escaped reporting or toggled LogViewer")
Nexus.DiagnosticLogs.ClearAll=function()
    calls.logclear=calls.logclear+1
    return true
end
Run("probe Peer")
assert(calls.panel==1 and calls.editor==1 and calls.syncdebug==1
    and calls.builds==1 and calls.leaderboard==1 and calls.errors==1
    and calls.performance==1 and calls.log==1 and calls.overlay==1
    and calls.restore==1 and calls.sync==1 and calls.probe==1
    and calls.probeTarget=="peer",
    "explicit command did not reach its established target exactly once")

local saved={editor=Nexus.WishlistEditor,log=Nexus.LogViewer,
    nameplate=Nexus.Nameplate,dps=Nexus.DpsCapture,sync=Nexus.Sync,
    builds=Nexus.CommunityBuilds,leaderboard=Nexus.Leaderboard,
    overlay=Nexus.WishlistOverlay}
Nexus.WishlistEditor=nil; Expect("editor","wishlist editor unavailable")
Nexus.LogViewer=nil
Expect("syncdebug","log viewer unavailable")
Expect("errors","log viewer unavailable")
Expect("performance","performance diagnostics unavailable")
Expect("log","log viewer unavailable")
Expect("logclear","diagnostic history cleared")
assert(calls.logclear==3 and calls.log==1,
    "logclear incorrectly depended on LogViewer availability")
Nexus.Nameplate=nil; Expect("nameplate","Nameplate module not loaded.")
Nexus.DpsCapture=nil; Expect("dps","DPS capture module not loaded")
Nexus.Sync=nil; Expect("sync","sync unavailable")
Nexus.CommunityBuilds=nil; Expect("builds","Nexus Builds unavailable")
Nexus.Leaderboard=nil; Expect("leaderboard","Nexus Leaderboard unavailable")
Nexus.WishlistOverlay=nil; Expect("overlay","overlay unavailable")
Nexus.WishlistEditor=saved.editor; Nexus.LogViewer=saved.log
Nexus.Nameplate=saved.nameplate; Nexus.DpsCapture=saved.dps
Nexus.Sync=saved.sync; Nexus.CommunityBuilds=saved.builds
Nexus.Leaderboard=saved.leaderboard; Nexus.WishlistOverlay=saved.overlay

Nexus.Sync.RequestSync=function() return false,"sync failed" end
Expect("sync","sync failed")
Nexus.Sync.SendStatusTo=function() error("probe failed") end
local probeOk,probeResult,probeOutput=pcall(Run,"probe Peer")
assert(probeOk and probeResult==nil and probeOutput=="",
    "probe send failure escaped its established protected call")
local realWishlist,realNote=Adapter.Wishlist,Adapter.WishlistNote
Adapter.Wishlist=function() return nil end
Adapter.WishlistNote=function() return nil end
Expect("wishlist",table.concat({
    "no wishlist detected -- running as advisor only.",
    "Design one in the Echo Journal: 'New Wishlist' (the 'Echo Wishlist'",
    "section), pick its echoes, and save it. The addon reads that build.",
},"\n"))
Expect("progress","no wishlist set -- advisor only, nothing to track.")
Adapter.WishlistNote=function() return "wishlist waiting" end
Expect("check","wishlist waiting")
Adapter.Wishlist=realWishlist; Adapter.WishlistNote=realNote
local realSlots=Adapter.Slots
Adapter.Slots=function() return nil end
Expect("status",table.concat({
    "v"..Nexus.VERSION.." build=test.13-abcdef0 -- level 5, auto ON",
    "TARGET: |cff7fff7f'Goal'|r (your Echo Wishlist build) -- 1 echoes",
    "LOADOUTS: slot data not loaded yet (waiting on the server).",
    "OWNED this run: 1 echoes (synced).",
},"\n"))
Adapter.Slots=realSlots
Nexus.DpsCapture.IsDetailsAvailable=function() return false end
Expect("dps",table.concat({
    "|cffff9040Details! damage meter is not installed.|r",
    "Install Details! to enable DPS tracking on your builds.",
    "Selected wishlist key: wishlist-key",
    "Current tracked Echo key: current-key",
    "Open /nexus log and select DPS for the full capture trace.",
},"\n"))
Adapter.RestoreAutoAccept=function() return false end
Expect("restore","nothing to restore")
Expect("anchor nonsense","anchor set to nil")
assert(#H.selectCalls==0 and #H.banishCalls==0 and H.rerollCalls==0
    and #H.freezeCalls==0 and #H.activateCalls==0 and #H.saveCalls==0,
    "slash command characterization submitted gameplay automation")

local sourceFile=assert(io.open("core/Main.lua","r"))
local source=sourceFile:read("*a"); sourceFile:close()
assert(select(2,source:gsub('SlashCmdList%["NEXUS"%]',''))==1
    and select(2,source:gsub('SLASH_NEXUS1',''))==1
    and select(2,source:gsub('SLASH_NEXUS2',''))==1
    and select(2,source:gsub('SLASH_NEXUS3',''))==1,
    "Main is not the sole one-shot slash-global registration owner")
local tocFile=assert(io.open("Nexus.toc","r"))
local toc=tocFile:read("*a"); tocFile:close()
for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua$") then
        local path=line:gsub("\\","/")
        local runtimeFile=assert(io.open(path,"r"))
        local runtimeSource=runtimeFile:read("*a"); runtimeFile:close()
        if path~="core/Main.lua" then
            assert(not runtimeSource:find("SLASH_NEXUS",1,true)
                and not runtimeSource:find('SlashCmdList["NEXUS"]',1,true),
                "slash-global registration escaped Main: "..path)
        end
    end
end
print("real Main command outputs, targets, globals, and passive boundary -- OK")
