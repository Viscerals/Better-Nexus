-- Minimal synthetic Select reproduction. Real modules; no game or private data.
local R={X=200010,Y=200009,Z=200012,W=200013}
R.initial={{spellId=R.X,quality=2},{spellId=R.Z,quality=0},{spellId=R.W,quality=1}}
R.next={{spellId=R.Y,quality=1},{spellId=R.Z,quality=0},{spellId=R.W,quality=1}}
function R.Boot(oldCopy)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua')
 H.playerLevel=66;H.pendingRolls=14
 H.granted={['Echo 80']={{spellId=200080,quality=0}}}
 if oldCopy then H.granted['Echo 10']={{spellId=R.X,quality=2}} end
 H.perks.serverActiveSlot=1
 local target={{spellId=R.X,quality=2,stacks=1},{spellId=R.Y,quality=1,stacks=1}}
 H.perks.serverBuildSlots={[1]={name='Synthetic recovery plan',verified=true,echoes=H.Clone(target)}}
 H.selectAttempts=0;H.boardAttempts=0
 for _,name in ipairs({'SelectPerk','BanishPerk','FreezePerk','RequestReroll'}) do
  local old=H.service[name]
  H.service[name]=function(...)
   H.boardAttempts=H.boardAttempts+1
   if name=='SelectPerk' then H.selectAttempts=H.selectAttempts+1 end
   return old(...)
  end
 end
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then assert(loadfile((line:gsub('\\','/'))))('Nexus',{}) end
 end
 local factory=Nexus.MainInternals.AutomationRuntime;local original=factory.New
 factory.New=function(...)H.runtime=original(...);return H.runtime end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20,.05)
 assert(Nexus.StartupStatus().coreReady,'fixture startup')
 assert(H.runtime,'fixture runtime capture')
 assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Synthetic recovery plan',target),'fixture assignment')
 function H.Offer(cards)H.Board(cards or R.initial);H.Notify();Nexus.GameAdapter.Poll()end
 function H.Auto()return Nexus.RecomputeStats().autoEnabled end
 function H.Count(id)
  local n=0;for _,a in ipairs(H.actions)do if a[1]=='take' and (not id or a[2]==id)then n=n+1 end end
  return n
 end
 return H,Nexus.GameAdapter
end
function R.Grant(H,id)
 H.granted=H.Clone(H.granted)
 local key='Echo '..(id-200000);H.granted[key]=H.granted[key] or {}
 table.insert(H.granted[key],{spellId=id,quality=H.db[id].quality})
 H.Notify();Nexus.GameAdapter.Poll()
end
function R.AutoSubmit(H)
 H.Offer();SlashCmdList.NEXUS('auto')
 for _=1,100 do H.Advance(.05);if H.Count()>0 then break end end
 assert(H.Auto() and H.Count(R.X)==1 and H.Count()==1,'fixture: one wished Select submitted')
 assert(H.selectAttempts==1,'fixture: one native Select attempt')
end
function R.Travel(H,delay)
 H.Advance(.1);H.Fire('PLAYER_LEAVING_WORLD');H.Advance(delay or 5)
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(3.5)
end
function R.Checks()
 local count,failures=0,{}
 local function check(v,m)count=count+1;if not v then failures[#failures+1]=m;print('BEHAVIOR FAIL: '..m)end end
 local function scenario(name,fn)
  print('SCENARIO: '..name)
  local ok,err=pcall(fn,check)
  if not ok then failures[#failures+1]=name..': '..tostring(err);print('SCENARIO ERROR: '..tostring(err))end
 end
 local function finish()
  print('behavior checks='..count..', failures='..#failures)
  assert(#failures==0,table.concat(failures,'\n'))
 end
 return scenario,finish
end
return R
