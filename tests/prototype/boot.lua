local H=dofile('tests/prototype/harness.lua')
H.Boot()
print('BOOT chat',#H.chat,'frames',#H.frames)
for _,line in ipairs(H.chat) do print('CHAT',line) end
assert(Nexus.GameAdapter and Nexus.Policy and Nexus.WishlistPilot)
assert(SlashCmdList.NEXUS,'slash registration')
SlashCmdList.NEXUS('status')
for i=math.max(1,#H.chat-15),#H.chat do print('STATUS',H.chat[i]) end
assert(not table.concat(H.chat,'\n'):find('not initialized yet',1,true),'startup not ready')
print('PASS full TOC and synthetic startup')
