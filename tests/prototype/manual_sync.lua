local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.sent={};SlashCmdList.NEXUS('sync')
local sentAt
for i=1,400 do
 H.Advance(.1,.05)
 if #H.sent>0 then sentAt=H.now;break end
end
if not sentAt then
 for _,s in ipairs(H.chat)do print('CHAT',s)end
 for k,v in pairs(Nexus.SyncWire.Stats())do print('WIRE',k,v)end
end
check(sentAt~=nil,'real slash -> preparation -> transport dispatch')
check(H.sent[1].route=='chat' and H.sent[1].kind=='CHANNEL','unknown peers retain legacy discovery')
check(not Nexus.SyncWire.Stats().suspended,'normal CTL dispatch remains usable')
-- Combat retains any new work; no data/handshake is emitted while in combat.
H.combat=true;local before=#H.sent
SlashCmdList.NEXUS('sync');H.Advance(2)
check(#H.sent==before,'actual Sync pipeline emits no packet in combat')
H.combat=false;H.Advance(4)
check(not Nexus.SyncWire.Stats().suspended,'pipeline resumes without library suspension')
print('PASS manual Sync actual command/lifecycle/wire checks='..checks)
