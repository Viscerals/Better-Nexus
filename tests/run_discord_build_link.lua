dofile('tests/harness.lua')
NexusDB = NexusDB or {}
NexusDB.communityBuilds = {}
-- Static regression guard: Discord links must be carried by full build payloads
-- and summary metadata must flag stale link metadata for on-demand refresh.
local f=assert(io.open('core/CommunityController.lua','r')); local controller=f:read('*a'); f:close()
assert(controller:find('discord%.com/channels/',1,false), 'Discord message link validation missing')
assert(controller:find('BroadcastBuildSummary',1,true), 'link save must broadcast updated build summary')
local s=assert(io.open('core/Sync.lua','r')); local sync=s:read('*a'); s:close()
assert(sync:find('needsFullBuild',1,true), 'summary link-change refresh flag missing')
assert(sync:find('linkHash',1,true), 'link hash metadata missing')
print('discord build link tests passed')
