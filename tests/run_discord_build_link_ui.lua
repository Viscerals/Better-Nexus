local f = assert(io.open("ui/CommunityRenderer.lua", "r"))
local s = f:read("*a"); f:close()
local controllerFile = assert(io.open("core/CommunityController.lua", "r"))
local controller = controllerFile:read("*a"); controllerFile:close()
assert(s:find('DISCORD BUILD LINK', 1, true), 'Discord field label missing')
assert(s:find('linkSaveBtn', 1, true), 'owner link-save button missing')
assert(s:find('EditBuild%(%s*selected, build.title, build.description, link%)'),
    'link not saved atomically through EditBuild')
assert(controller:find('link:match("^https://discord%.com/channels/(%d+)/(%d+)/(%d+)/?$")', 1, true)
    and controller:find('link:match("^https://discord%.com/channels/(%d+)/(%d+)/?$")', 1, true),
    'Discord channel-link validator missing from controller')
assert(controller:find('https://discord.com/channels/%s/%s', 1, true),
    'Discord channel-link normalization missing from controller')
print('discord build link UI tests passed')
