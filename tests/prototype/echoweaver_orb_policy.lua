-- EchoWeaver Orb policy: the Nexus safety rules, self-contained.
-- Exact quality and roles, protected low quality, approved excess only,
-- explicit source exclusion, same-ID locked copies, target order, envelope
-- limits and the single-gain confirmation diff. No outside source.
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
s.locked['5:0']=1;check(#P.Sources(t,s,{})==0,'ID-only action cannot disambiguate a same-ID locked copy')
local targets=assert(P.Normalize({{spellId=1,quality=1,stacks=2},{spellId=1,quality=2,stacks=1},{spellId=7,quality=3,stacks=1,locked=true}}))
local prog=P.Progress(targets,{granted={['1:1']=1},locked={['7:3']=1}})
check(prog.rolledMissing==2 and prog.permanentMissing==0,'role and exact-quality deficits kept separate')
local d=P.Decide({{spellId=1,quality=2},{spellId=1,quality=1}},prog,s,false,{})
check(d and d.index==2,'target list order rather than highest offer quality')
check(not P.Normalize({{spellId=1,quality=1,stacks=80}}),'oversized ordinary target rejected')
check(not P.Normalize({{spellId=1,quality=1,stacks=7,locked=true}}),'oversized locked target rejected')
local k,st=P.SingleGain({['1:1']=1},'1:1',{['1:1']=1})
check(k=='1:1' and st=='CONFIRMED','same-ID diff subtracts known sacrifice; runtime separately requires fresh evidence')
print('PASS echoweaver_orb_policy: Orb policy safety checks='..checks)
