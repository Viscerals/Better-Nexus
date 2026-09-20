-- Deterministic decision battery for offline candidate comparison.
--
-- Every candidate faces the same NO-GUARANTEE environment: the boards below
-- are fixed inputs and none is produced by a saved build. The battery holds
-- no draw weights, quality odds or redraw behaviour, so it yields decisions at
-- given states only. It yields no completion rate and no efficiency figure.
--
--   NEXUS_POLICY_ROOT     source root to load (default: current directory)
--   NEXUS_POLICY_RUNTIME  'current' (default) or 'test9020' saved-row preparation
--   NEXUS_POLICY_DUMP     path; writes one line per scenario for an external diff
local P=dofile('tests/prototype/policy_adapter.lua')
P.Load()
local runtime=os.getenv('NEXUS_POLICY_RUNTIME') or 'current'
assert(runtime=='current' or runtime=='test9020','known runtime preparation')
local catalog=P.Catalog({f1={[0]=1001,[1]=1011},f2={[0]=1002},f3={[0]=1003},f4={[0]=1004},f5={[0]=1005}})
local plan=P.Plan(catalog,{{spellId=1001,stacks=2},{spellId=1002,stacks=1}})
local savedEchoes={{spellId=1001,family='f1',quality=0,stacks=2},{spellId=1002,family='f2',quality=0,stacks=1}}
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
 local lines,byKey={}, {}
 for _,board in ipairs(boards)do for _,horizon in ipairs(horizons)do for _,resource in ipairs(resources)do
  for _,own in ipairs(ownership)do for _,verified in ipairs({false,true})do
   local action=P.Decide({catalog=catalog,plan=plan,horizon=horizon,cards=board[2],charges=resource[2],
    allowFreeze=resource[3],allowBanish=resource[4],allowReroll=resource[5],
    owned=P.Owned(catalog,own[2]),locked=P.Owned(catalog,own[3]),
    activeRow={verified=verified,echoes=savedEchoes},runtime=runtime,
    flags={DISABLE_SUPPRESSES_GUARANTEE=true}})
   local key=table.concat({board[1],'h'..horizon,resource[1],own[1]},'/')
   local line=table.concat({tostring(action.type),tostring(action.spellId),tostring(action.index)},':')
   lines[#lines+1]=key..'/'..(verified and 'verified' or 'unverified')..' '..line..' planner='..tostring(action.planner)..' reason='..tostring(action.reason)
   byKey[key]=byKey[key] or {};byKey[key][verified]=line
  end end
 end end end
 return lines,byKey
end
local lines,byKey=Battery()
local again=Battery()
assert(P.Fingerprint(lines)==P.Fingerprint(again),'repeated identical inputs give identical decisions')
local scenarios,dependent=0,0
for _,pair in pairs(byKey)do
 scenarios=scenarios+1
 if pair[true]~=pair[false] then dependent=dependent+1 end
end
local dump=os.getenv('NEXUS_POLICY_DUMP')
if dump then local f=assert(io.open(dump,'w'));f:write(table.concat(lines,'\n'),'\n');f:close()end
print('ROOT '..P.root..' RUNTIME '..runtime)
print('SCENARIOS '..scenarios..' DECISIONS '..#lines..' VERIFICATION_DEPENDENT '..dependent..' FINGERPRINT '..P.Fingerprint(lines))
-- As a maintained test this runs on the current source with the current
-- preparation, where saved verification must change no decision.
if runtime=='current' and not os.getenv('NEXUS_POLICY_ROOT') then
 assert(scenarios==432 and dependent==0,'no decision depends on saved verification')
 print('PASS 432 fixed states: no decision depends on saved verification')
end
