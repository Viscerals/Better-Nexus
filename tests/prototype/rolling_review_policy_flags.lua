-- Review findings F5 and N3 on range eadff8a..578c77e. NEW test. It uses the
-- maintained production-policy adapter (real pure modules in TOC order).
--
-- F5: the supported way to switch R3 or R5 off alone is its flag in
-- WishlistPilot.NEXUS_POLICY. Each flag alone restores the reference decision on
-- the review fixtures F1 and F3, and leaves the other change active.
-- N3: tests/prototype/policy_compare.lua pins no decision fingerprint. This
-- test pins, on the same 432-state battery (864 decisions with the saved
-- verification flag), how many decisions R3 and R5 change against the reference
-- rules and in which direction, so that a later drift is visible. The battery
-- definition below is a copy of the one in policy_compare.lua (that file is not
-- edited). If that battery changes, this copy must follow; the 864 size is checked.
-- Fixtures only. No draw odds. No efficiency claim.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local Pilot=Nexus.WishlistPilot
local PRODUCTION=Pilot.NEXUS_POLICY
check(PRODUCTION.rerollIgnoresSatisfiedTargets==true and PRODUCTION.freezeMustStayNeeded==true,'production policy has both flags on')
local function With(policy,fn)
 local saved=Pilot.NEXUS_POLICY;Pilot.NEXUS_POLICY=policy
 local ok,a,b=pcall(fn);Pilot.NEXUS_POLICY=saved;assert(ok,a);return a,b
end
-- F1 and F3 fixtures from the review report.
local small=P.Catalog({a={[0]=101},b={[0]=102},x={[0]=901},y={[0]=902}})
local smallPlan=P.Plan(small,{{spellId=101,stacks=1},{spellId=102,stacks=1}})
local function F1()return P.Decide({catalog=small,plan=smallPlan,horizon=1,cards={{spellId=101},{spellId=901},{spellId=902}},
 owned=P.Owned(small,{[101]=1}),charges={trustworthy=true,banish=0,freeze=0,reroll=5},allowReroll=true})end
local function F3()return P.Decide({catalog=small,plan=smallPlan,horizon=2,cards={{spellId=101},{spellId=101},{spellId=901}},
 charges={trustworthy=true,banish=1,freeze=1,reroll=0},allowFreeze=true,allowBanish=true})end
local REFERENCE_F1='take|101|1|pilot103|Take filler; search unavailable (Pilot)'
local REFERENCE_F3='freeze|101|1|pilot103|Freeze wanted Echo before search (Pilot)'
local variants={
 {'both on (production)',{rerollIgnoresSatisfiedTargets=true,freezeMustStayNeeded=true},false,false},
 {'R3 off alone',{rerollIgnoresSatisfiedTargets=false,freezeMustStayNeeded=true},true,false},
 {'R5 off alone',{rerollIgnoresSatisfiedTargets=true,freezeMustStayNeeded=false},false,true},
 {'both off',{rerollIgnoresSatisfiedTargets=false,freezeMustStayNeeded=false},true,true},
 {'empty policy table',{},true,true},
}
for _,v in ipairs(variants)do
 local f1=With(v[2],function()return P.Line(F1())end)
 local f3=With(v[2],function()return P.Line(F3())end)
 check((f1==REFERENCE_F1)==v[3],v[1]..': F1 '..(v[3]and'is'or'is not')..' the reference decision: '..f1)
 check((f3==REFERENCE_F3)==v[4],v[1]..': F3 '..(v[4]and'is'or'is not')..' the reference decision: '..f3)
end
check(With({rerollIgnoresSatisfiedTargets=false,freezeMustStayNeeded=true},function()return F3().type end)=='take','R3 off alone leaves R5 active')
check(With({rerollIgnoresSatisfiedTargets=true,freezeMustStayNeeded=false},function()return F1().type end)=='reroll','R5 off alone leaves R3 active')

-- N3: the policy_compare battery.
local catalog=P.Catalog({f1={[0]=1001,[1]=1011},f2={[0]=1002},f3={[0]=1003},f4={[0]=1004},f5={[0]=1005}})
local plan=P.Plan(catalog,{{spellId=1001,stacks=2},{spellId=1002,stacks=1}})
local savedEchoes=P.Echoes(catalog,{{spellId=1001,stacks=2},{spellId=1002,stacks=1}})
local boards={
 {'two-wanted',{{spellId=1001},{spellId=1002},{spellId=1003}}},
 {'one-wanted',{{spellId=1001},{spellId=1003},{spellId=1004}}},
 {'other-wanted',{{spellId=1004},{spellId=1002},{spellId=1005}}},
 {'no-wanted',{{spellId=1003},{spellId=1004},{spellId=1005}}},
 {'wrong-quality',{{spellId=1011},{spellId=1003},{spellId=1004}}},
 {'held-wanted',{{spellId=1001,isFrozen=true},{spellId=1002},{spellId=1003}}},
 {'held-filler',{{spellId=1003,isFrozen=true},{spellId=1001},{spellId=1004}}},
 {'marked-filler',{{spellId=1003},{spellId=1004},{spellId=1005,isGuaranteed=true}}},
 {'marked-wanted',{{spellId=1003},{spellId=1004},{spellId=1002,isGuaranteed=true}}},
}
local horizons={1,2,8,30}
local resources={
 {'none',{trustworthy=true,banish=0,freeze=0,reroll=0},false,false,false},
 {'freeze-banish',{trustworthy=true,banish=2,freeze=2,reroll=0},true,true,false},
 {'all',{trustworthy=true,banish=2,freeze=2,reroll=2},true,true,true},
}
local ownership={{'empty',{},{}},{'one-rolled',{[1001]=1},{}},{'rolled-and-permanent',{[1001]=1},{[1001]=1}},{'complete',{[1001]=2,[1002]=1},{}}}
local function Battery()
 local out={}
 for _,board in ipairs(boards)do for _,horizon in ipairs(horizons)do for _,resource in ipairs(resources)do
  for _,own in ipairs(ownership)do for _,verified in ipairs({false,true})do
   local action=P.Decide({catalog=catalog,plan=plan,horizon=horizon,cards=board[2],charges=resource[2],
    allowFreeze=resource[3],allowBanish=resource[4],allowReroll=resource[5],
    owned=P.Owned(catalog,own[2]),locked=P.Owned(catalog,own[3]),
    activeRow={verified=verified,echoes=savedEchoes},runtime='current',
    flags={DISABLE_SUPPRESSES_GUARANTEE=true}})
   out[#out+1]={key=table.concat({board[1],'h'..horizon,resource[1],own[1],verified and 'verified' or 'unverified'},'/'),
    type=tostring(action.type),line=table.concat({tostring(action.type),tostring(action.spellId),tostring(action.index)},':')}
  end end
 end end end
 return out
end
local function Compare(policy)
 local ref=With({},Battery);local got=With(policy,Battery)
 assert(#ref==864 and #got==864,'battery size')
 local changed,direction=0,{}
 for i=1,#ref do
  assert(ref[i].key==got[i].key)
  if ref[i].line~=got[i].line then
   changed=changed+1
   local d=ref[i].type..'->'..got[i].type;direction[d]=(direction[d] or 0)+1
  end
 end
 return changed,direction
end
local function Count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local changed,direction=Compare({rerollIgnoresSatisfiedTargets=true})
check(changed==16,'R3 alone changes 16 of 864 battery decisions (got '..changed..')')
check(direction['banish->reroll']==12 and direction['take->reroll']==4 and Count(direction)==2,'R3 direction: 12 Banish->Reroll, 4 take->Reroll, nothing else')
changed,direction=Compare({freezeMustStayNeeded=true})
check(changed==0 and Count(direction)==0,'R5 alone changes 0 of 864 battery decisions (got '..changed..')')
changed,direction=Compare(PRODUCTION)
check(changed==16 and direction['banish->reroll']==12 and direction['take->reroll']==4 and Count(direction)==2,'production policy: the same 16 decisions, same direction')
print('PASS F5 each NEXUS_POLICY flag alone restores the reference decision; N3 battery drift pinned (16/864 R3, 0/864 R5) checks='..checks)
