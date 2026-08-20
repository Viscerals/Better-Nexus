-- 100-character leaderboard stress: bounded rows, bucket deltas, and exact
-- loadout references remain stable.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local DPS=Nexus.DpsCapture
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
UnitName=function() return "Viewer" end
local broadcasts={}
DPS.Init({}, {BroadcastDpsRecord=function(r) broadcasts[#broadcasts+1]=r return true end})
for i=1,100 do
 local echoes={{spellId=300000+i,stacks=1},{spellId=310000+i,stacks=(i%3)+1}}
 local id="stress-"..i
 NexusDB.communityBuilds[id]={id=id,title="Loadout "..i,author="Player"..i,class="MAGE",echoes=echoes,lastModified=i,postedAt=i,isMine=false}
 local fp=DPS.GetEchoKey(echoes)
 assert(DPS.ReceiveRecord({v=6,f=fp,e=echoes,c="dummy",d=1000000+i*10000,u=65,t=i,p="Player"..i,k="MAGE",l=80,b=id}))
end
local rows=DPS.GetDpsBoard("dummy")
assert(#rows==100,"100 distinct characters should produce 100 rows")
-- Same character, stronger different exact loadout: still 100 rows.
local better={{spellId=400050,stacks=2},{spellId=410050,stacks=1}}
NexusDB.communityBuilds["stress-50b"]={id="stress-50b",title="Winner 50",author="Player50",class="MAGE",echoes=better,lastModified=200,postedAt=200,isMine=false}
assert(DPS.ReceiveRecord({v=6,f=DPS.GetEchoKey(better),e=better,c="dummy",d=9000000,u=65,t=200,p="Player50",k="MAGE",l=80,b="stress-50b"}))
rows=DPS.GetDpsBoard("dummy")
assert(#rows==100,"new winning loadout for one character must replace, not append")
local found=false; for _,r in ipairs(rows) do if r.player=="Player50" then found=r.buildId=="stress-50b" and r.dps==9000000 end end
assert(found,"Player50 winning loadout was not replaced correctly")
local fullHash=DPS.GetSyncHash()
assert(select(2,fullHash:gsub(",",","))==7,"DPS sync hash should contain 8 delta buckets")
assert(DPS.BroadcastAllBuildBests(fullHash)==0,"identical peer should receive zero leaderboard records")
local parts={}; for p in fullHash:gmatch("([^,]+)") do parts[#parts+1]=p end; parts[1]="different"
broadcasts={}
local n=DPS.BroadcastAllBuildBests(table.concat(parts,","))
assert(n>0 and n<40,"one changed bucket should send a bounded subset, got "..tostring(n))
local attempts,room,firstAdmitted={},1,nil
DPS.Init({}, {BroadcastDpsRecord=function(record)
 local key=tostring(record.category)..":"..tostring(record.player)
 attempts[key]=(attempts[key] or 0)+1
 if room<=0 then return false,"sync queue full" end
 room=room-1; firstAdmitted=firstAdmitted or key
 return true
end})
local progress={}
local admitted,complete=DPS.BroadcastAllBuildBests("0",nil,progress)
assert(admitted==1 and complete==false and firstAdmitted,
 "partial DPS bucket admission was incorrectly reported as complete")
room=200
local resumed,resumeComplete=DPS.BroadcastAllBuildBests("0",nil,progress)
assert(resumed==99 and resumeComplete==true,
 "DPS bucket retry did not resume after the admitted record")
assert(attempts[firstAdmitted]==1,
 "DPS bucket retry re-enqueued an already admitted record")
print("100-entry leaderboard and bucket-delta sync stress -- OK")
