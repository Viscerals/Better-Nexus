-- The Orb lifecycle observer has to be installed before the first spend.
-- A cold world entry (no earlier Start) used to miss PLAYER_ENTERING_WORLD,
-- so Start half a second later was accepted. The same entry with the observer
-- already installed is refused. Stop stays available through that hold.
-- Offline module behavior only. Not a native client, server, or timing proof.
local checks=0
local function check(v,m) assert(v,m); checks=checks+1 end
local H=dofile('tests/prototype/orbs_support.lua')
local M=H.M

local function Start(limit)
 return M.Start(limit or 1)
end

H.OrbPlan()
H.Fire('PLAYER_LEAVING_WORLD')
local ok,why=Start()
check(ok~=true and type(why)=='string' and why:find('loading screen',1,true)~=nil,
 'cold leave: Start is refused while the world is loading')
check(H.Count('orb-spend')==0,'cold leave: no spend is submitted')
check(M.Stop()==true,'Stop still completes during the loading hold')
check(H.Count('orb-spend')==0,'Stop during loading submits nothing')

H.Fire('PLAYER_ENTERING_WORLD')
H.Advance(0.5)
ok,why=Start()
check(ok~=true and type(why)=='string' and why:find('just loaded',1,true)~=nil,
 'cold enter +0.5s: Start is refused for the post-enter settle')
check(H.Count('orb-spend')==0,'cold enter +0.5s: no synthetic spend')
check(M.Stop()==true,'Stop still completes during the post-enter settle')
check(H.Count('orb-spend')==0,'Stop during settle submits nothing')

H.Advance(2.6)
ok,why=Start(3)
check(ok==true, 'after the settle, Start is accepted: '..tostring(why))
check(H.Count('orb-spend')==1,'after the settle, one spend is submitted')
check(M.Pause()==true,'an accepted run can still be paused')
local spends=H.Count('orb-spend')
local takes=H.Count('take')
H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(0.5)
ok,why=M.Resume()
check(ok~=true and type(why)=='string' and why:find('just loaded',1,true)~=nil,
 'Resume stays refused during the post-enter settle')
check(H.Count('orb-spend')==spends and H.Count('take')==takes,
 'the settle hold does not submit another spend or choice')
check(M.Stop()==true,'Stop still completes after a settled pause')
check(H.Count('orb-spend')==spends,'Stop does not submit a spend')

print('PASS orb_world_entry_hold '..checks)
