local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
for _,name in ipairs({'Model','Policy','Ratchet','Strategy','GameAdapter','Store','WishlistEditor','CommunityBuilds','Leaderboard','DpsCapture','Sync','Codec','JournalTab','LogViewer','WishlistPilot','SyncWire'})do
 check(type(Nexus[name])=='table','included feature '..name)
end
local function invoke(label,fn)
 local ok,err=pcall(fn);check(ok,label..': '..tostring(err));H.Advance(.3)
end
invoke('Wishlist window',function()Nexus.WishlistEditor.Show()end)
invoke('Community window',function()Nexus.CommunityBuilds.Show()end)
invoke('Leaderboard window',function()Nexus.Leaderboard.Show('lk')end)
invoke('Dummy board',function()Nexus.Leaderboard.SetCategory('dummy')end)
invoke('Combined board',function()Nexus.Leaderboard.SetCategory('combined')end)
invoke('Class filter',function()Nexus.Leaderboard.SetClassFilter('MAGE')end)
invoke('Diagnostics window',function()Nexus.LogViewer.Show('state')end)
invoke('Close diagnostics',function()Nexus.LogViewer.Toggle('state')end)
invoke('Status command',function()SlashCmdList.NEXUS('status')end)
invoke('Prototype command',function()SlashCmdList.NEXUS('prototype')end)
local function manual() local start=#H.chat;SlashCmdList.NEXUS('status');for i=start+1,#H.chat do if H.chat[i]:find('auto OFF',1,true) then return true end end end
check(manual(),'automation defaults OFF')
-- Readiness once and repeated world events must not replace per-character data.
local owner=Nexus.MainInternals.StoreAuthorityOwner
assert(owner.UpdateStateV1(function(s)s.prototypeTestMarker={value=37}end))
H.Fire('PLAYER_ENTERING_WORLD');H.Advance(2)
check(Nexus.Store.State().prototypeTestMarker.value==37,'world transition preserves user state')
-- Read-only public view inspection and report details do not enable automation.
check(manual(),'UI navigation retains manual mode')
check(Nexus.RuntimeBuildLabel()~=nil,'build identity available')
-- Target limit includes the Lua 5.1 closure-upvalue ceiling. Ignore _ENV, which
-- exists only in the Lua 5.4 compatibility runner, not the addon source.
local seen={};local maxup,functions=0,0
local function walk(v,depth)
 if (type(v)~='table' and type(v)~='function') or seen[v] or depth>64 then return end
 seen[v]=true
 if type(v)=='function'then
  local n=0
  for i=1,200 do local name,child=debug.getupvalue(v,i);if not name then break end
   if name~='_ENV'then n=n+1;walk(child,depth+1)end
  end
  maxup=math.max(maxup,n);functions=functions+1
  assert(n<=60,'closure exceeds Lua 5.1 upvalue limit: '..n)
 else
  for k,child in pairs(v)do if k~='_G' and k~='db'then walk(child,depth+1)end end
 end
end
walk(Nexus,0)
check(functions>100,'runtime functions inspected')
print('PASS feature UI/bootstrap/safety checks='..checks..'; functions='..functions..'; max non-environment upvalues='..maxup)
