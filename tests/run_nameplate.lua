-- Nameplate: Nexus badge appears correctly on player mouseover.
-- Tests the AugmentUnitTooltip logic directly since GameTooltip
-- HookScript can't fire in the test harness.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Nameplate.lua")

local DPS = Nexus.DpsCapture
local NP  = Nexus.Nameplate
local clock=1000; GetTime=function() return clock end
local wall=50000; time=function() return wall end
UnitName=function(u) return u=="player" and "Solkr" or nil end
UnitIsPlayer=function(u) return true end  -- all units are "players" in test

NexusDB={ communityBuilds={}, syncTombstones={}, dpsCapture={} }
DPS.Init({}, nil)

-- Seed leaderboard records
local echoes={{spellId=200100,stacks=2},{spellId=200101,stacks=1}}
local fp=DPS.GetEchoKey(echoes)
assert(DPS.ReceiveRecord({v=6,f=fp,e=echoes,c="dummy",d=8000000,u=65,t=50000,p="Alice",k="MAGE",l=80}))
assert(DPS.ReceiveRecord({v=6,f=fp,e=echoes,c="dummy",d=5000000,u=65,t=50001,p="Bob",k="MAGE",l=80}))
assert(DPS.ReceiveRecord({v=6,f=fp,e=echoes,c="lk",   d=6500000,u=90,t=50002,p="Alice",k="MAGE",l=80}))

-- 1. GetPlayerInfo rank
local alice=DPS.GetPlayerInfo("Alice")
assert(alice and alice.rank==1 and alice.dps==8000000, "Alice should be #1 dummy: "..tostring(alice and alice.rank))
local bob=DPS.GetPlayerInfo("Bob")
assert(bob and bob.rank==2, "Bob should be #2")
print("GetPlayerInfo rank ordering correct -- OK")

-- 2. Tooltip augmentation via the exported function
local lines={}
local fakeTooltip={
    _unit="target",
    GetUnit=function(self) return self._unit, self._unit end,
    AddLine=function(self,text,...) lines[#lines+1]=text end,
    Show=function(self) end,
}

-- Test: Alice moused over
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target"  then return "Alice" end
    return nil
end
NP._AugmentUnitTooltip(fakeTooltip)
assert(#lines >= 2, "should have badge + rank line for Alice: "..#lines.." lines")
assert(lines[1]:find("Nexus"), "first line should be Nexus badge: "..tostring(lines[1]))
assert(lines[2] and lines[2]:find("1st",1,true),
    "second line should show compact rank: "..tostring(lines[2]))
print("Tooltip augmentation adds Nexus badge and rank -- OK")

-- 3. Bob gets correct rank 2
lines={}
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target"  then return "Bob" end
    return nil
end
NP._AugmentUnitTooltip(fakeTooltip)
assert(lines[2] and lines[2]:find("2nd",1,true),
    "Bob should show #2: "..tostring(lines[2]))
print("Rank 2 displays correctly -- OK")

-- 4. Self tooltips remain untouched by the non-intrusive 1.19.3 badge.
lines={}
UnitName=function(u) return "Solkr" end  -- both player and target return same name
NP._AugmentUnitTooltip(fakeTooltip)
assert(#lines==0, "self tooltip should not be augmented")
print("Self-mouseover remains untouched -- OK")

-- 5. Unknown player: no lines added
lines={}
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target"  then return "RandomPlayer" end
    return nil
end
NP._AugmentUnitTooltip(fakeTooltip)
assert(#lines==0, "unknown player should add nothing")
print("Unknown player produces no output -- OK")

-- 6. Community author with no DPS gets author badge
assert(Nexus.BuildCatalog.Put({
    id="b1",title="Fire Mage",author="AuthorGuy",class="MAGE",
    echoes=echoes,postedAt=50000,lastModified=50000,isMine=false
}))
local catalogAllCalls = 0
local realCatalogAll = Nexus.BuildCatalog.All
Nexus.BuildCatalog.All = function(...)
    catalogAllCalls = catalogAllCalls + 1
    return realCatalogAll(...)
end
lines={}
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target"  then return "AuthorGuy" end
    return nil
end
NP._AugmentUnitTooltip(fakeTooltip)
assert(#lines>=1 and lines[1]:find("Nexus"), "author should get Nexus badge")
assert(#lines==2 and lines[2]:find("Community build author",1,true),
    "non-ranked author tooltip lost its compact author label")
assert(catalogAllCalls == 0,
    "community-author tooltip copied the complete build catalog")
Nexus.BuildCatalog.All = realCatalogAll
print("Bundled community author gets compact Nexus and author labels -- OK")

-- 7. NPC: no lines added
lines={}
UnitIsPlayer=function(u) return false end
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target"  then return "Some NPC" end
    return nil
end
NP._AugmentUnitTooltip(fakeTooltip)
assert(#lines==0, "NPC mouseover should add nothing")
print("NPC mouseover produces no output -- OK")

-- 8. Verify GetUnit returning nil is handled safely
lines={}
local nilUnitTooltip={
    GetUnit=function(self) return nil, nil end,
    AddLine=function(self,text,...) lines[#lines+1]=text end,
    Show=function(self) end,
}
local ok=pcall(NP._AugmentUnitTooltip, nilUnitTooltip)
assert(ok and #lines==0, "nil unit should not error and should add nothing")
print("nil unit handled safely -- OK")

-- 9. A discovered Nexus peer with no build or DPS still gets the user badge.
lines={}
UnitIsPlayer=function(u) return true end
UnitName=function(u)
    if u=="player" then return "Solkr" end
    if u=="target" then return "PeerOnly" end
    return nil
end
time=function() return 60000 end
Nexus.Sync.HandleIncoming("WLNP|PeerOnly-Realm|1.19.3", "PeerOnly-Realm")
assert(Nexus.Sync.IsKnownPeer("PeerOnly"), "recognized presence should record the peer")
fakeTooltip.__nexusAugmentedFor=nil
NP._AugmentUnitTooltip(fakeTooltip)
assert(lines[1] and lines[1]:find("Nexus user"), "known peer should show Nexus user badge")
assert(#lines==2 and lines[2]:find("Connected",1,true),
    "peer without rank/build lost its compact connection label")
print("Known Nexus peer gets badge and connection label -- OK")

-- 10. Unknown protocol traffic must not create a fake Nexus user.
Nexus.Sync.HandleIncoming("FAKE|Spoofer|x", "Spoofer")
assert(not Nexus.Sync.IsKnownPeer("Spoofer"), "unknown wire code must not mark a Nexus peer")
print("Unknown protocol cannot spoof Nexus-user presence -- OK")


-- 11. Even a realm-qualified self record must not alter the self tooltip.
lines={}
UnitExists=function(u) return u=="player" end
UnitIsPlayer=function(u) return u=="player" end
UnitName=function(u) if u=="player" then return "Explore" end end
local selfTooltip={
    GetUnit=function(self) return "Explore", "player" end,
    AddLine=function(self,text,...) lines[#lines+1]=text end,
    Show=function(self) end,
}
Nexus.DpsCapture.GetPlayerInfo=function(name)
    if name=="Explore" then return { rank=1, dps=24000000, category="dummy", title="Mage Record Loadout" } end
end
NP._AugmentUnitTooltip(selfTooltip)
assert(#lines==0, "realm-qualified self row altered the self tooltip")
print("Realm-qualified self row remains non-intrusive -- OK")
