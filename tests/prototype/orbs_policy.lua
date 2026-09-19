Nexus={};assert(loadfile('logic/OrbPolicy.lua'))();local P=Nexus.OrbPolicy
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local s={catalog={},granted={},locked={}}
for i=1,8 do s.catalog[i]={name='Echo '..i,quality=i%4,group='g'..i,maxStack=3,available=true}end
s.catalog[5].group='family';s.catalog[6].group='family'
s.granted['5:0']=1;s.granted['6:3']=2
local t=assert(P.Normalize({{spellId=5,quality=0,stacks=1}}))
check(#P.Sources(t,s,{})==0,'protected low quality prevents using a higher family source')
t=assert(P.Normalize({{spellId=1,quality=1,stacks=1}}))
local src=P.Sources(t,s,{});check(#src==1 and src[1].key=='5:0','lowest actual family copy selected first')
s.granted['5:0']=3;t=assert(P.Normalize({{spellId=5,quality=0,stacks=2}}))
src=P.Sources(t,s,{});check(#src==1 and src[1].excess==1,'only excess above exact target can be approved')
check(#P.Sources(t,s,{['5:0']=true})==0,'explicit source exclusion preserved')
s.locked['5:0']=1;check(#P.Sources(t,s,{})==0,'ID-only action cannot disambiguate a same-ID permanent copy')
local targets=assert(P.Normalize({{spellId=1,quality=1,stacks=2},{spellId=1,quality=2,stacks=1},{spellId=7,quality=3,stacks=1,locked=true}}))
local prog=P.Progress(targets,{granted={['1:1']=1},locked={['7:3']=1}})
check(prog.rolledMissing==2 and prog.permanentMissing==0,'role and exact-quality deficits kept separate')
local d=P.Decide({{spellId=1,quality=2},{spellId=1,quality=1}},prog,s,false,{})
check(d and d.index==2,'target list order rather than highest offer quality')
check(not P.Normalize({{spellId=1,quality=1,stacks=80}}),'oversized ordinary target rejected')
check(not P.Normalize({{spellId=1,quality=1,stacks=7,locked=true}}),'oversized permanent target rejected')
local k,st=P.SingleGain({['1:1']=1},'1:1',{['1:1']=1})
check(k=='1:1' and st=='CONFIRMED','same-ID diff subtracts known sacrifice; runtime separately requires fresh evidence')
-- Behavior comparison uses the exact supplied MemoryMode source, not a copied fixture.
local ref=assert(os.getenv('LOADOUTPILOT_ROOT'),'reference path required')
local addon={Database={},Wishlist={},ProjectEbonholdIntegration={},Settings={GetBanlist=function()return {}end},
 EchoSelectionPolicy={IsNeverSelect=function()return false end}}
assert(loadfile(ref..'/Memory/MemoryMode.lua'))('LoadoutPilot',addon)
local reference=assert(addon.MemoryMode)
math.randomseed(515)
local cases=3000
for case=1,cases do
 local state={catalog={},granted={},locked={}};local groups={byEchoID={}};local entries={};local referenceProgress={items={}};local targetSet={}
 for id=1,8 do
  local q=id%4;local owned=math.random(0,3)
  state.catalog[id]={spellId=id,name='Echo '..id,quality=q,group='g'..id,maxStack=3,available=true}
  state.granted[P.Key(id,q)]=owned
  groups.byEchoID[id]={quality=q,ownedQuality=q,ownedStacks=owned,maxStack=3,group={}}
 end
 for _,id in ipairs({1,2,3}) do
  local desired=math.random(1,3);local q=id%4
  entries[#entries+1]={spellId=id,quality=q,stacks=desired}
  referenceProgress.items[#referenceProgress.items+1]={echoID=id,quality=q,remaining=math.max(0,desired-(state.granted[P.Key(id,q)]or 0))}
  targetSet[id]={quality=q,desiredStacks=desired}
 end
 local board,refboard={}, {choices={}}
 for i=1,3 do local id=math.random(1,8);local q=id%4;board[i]={spellId=id,quality=q};refboard.choices[i]={echoID=id,quality=q,index=i}end
 local got=P.Decide(board,P.Progress(assert(P.Normalize(entries)),state),state,true,{})
 local expected=reference.DecideOffer(refboard,referenceProgress,groups,targetSet)
 assert((got==nil)==(expected==nil),'reference nil decision mismatch '..case)
 if got then assert(got.kind==expected.kind and got.index==expected.index and got.spellId==expected.echoID and got.quality==expected.quality,'reference offer mismatch '..case)end
 local before,after={},{ };local b,a={},{}
 for id=1,8 do local n=math.random(0,3);before[id]=n;b[P.Key(id,id%4)]=n;after[id]=n;a[P.Key(id,id%4)]=n end
 local removed=math.random(1,8);before[removed]=math.max(1,before[removed]);b[P.Key(removed,removed%4)]=before[removed];after[removed]=before[removed]-1;a[P.Key(removed,removed%4)]=after[removed]
 local gained=math.random(1,8);after[gained]=after[gained]+1;a[P.Key(gained,gained%4)]=a[P.Key(gained,gained%4)]+1
 local rk,rs=reference.FindSingleGain(before,removed,after);local nk,ns=P.SingleGain(b,P.Key(removed,removed%4),a)
 assert(rs=='RESOLVED' and ns=='CONFIRMED' and nk==P.Key(rk,rk%4),'reference confirmation diff mismatch '..case)
end
print('PASS Orb policy safety checks='..checks..'; supplied MemoryMode offer and result comparisons='..cases..' each')
