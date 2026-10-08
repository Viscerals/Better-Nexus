-- Support report: a bounded Orb readiness block from the LAST NORMAL Orb window
-- read, also before any Orb run. At aac790c a report taken while the Orb read
-- waits and no run exists says only "Orb action: none unresolved" (source
-- diagnosis, section 4): no read stage, no rolled/locked trust facts, no
-- assignment state or role mode.
-- Contract: TEST_CONTRACT.md of the tests-first review, sections 4-6. The block is taken from the
-- real prepared report (the /nexus report page's Prepare report file, and
-- SupportReport.Prepare) and checked only for its documented values and its
-- privacy rules. The rest of the report keeps its existing lines.
-- Real TOC boot, adapter, Orb runtime/policy, Orb window, report builder and
-- report page; the fake services of orbs_support.lua; the companion storage is
-- loaded on demand the way the client loads it. Artificial IDs and names. No run
-- is started; nothing is spent or selected. Every expectation is evaluated and
-- reported; the test fails at the end if any did not hold.
local H=dofile('tests/prototype/orbs_support.lua')
local A,O=H.A,H.O
local failures,checks={},0
local function printable(v)
 local ok,s=pcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
local function expect(ok,label,detail)
 checks=checks+1
 if not ok then
  local line=label..(detail~=nil and (' ['..printable(detail)..']') or '')
  failures[#failures+1]=line;print('FAIL '..line)
 end
 return ok and true or false
end
local function scenario(name,fn)
 local ok,err=pcall(fn)
 if not ok then
  local line=name..': raised '..printable(err)
  failures[#failures+1]=line;print('FAIL '..line)
 end
end

local TRUST='Waiting for current rolled and locked Echo data from the server.'
-- The text of an over-cap refusal is pinned by orb_count_refusal_truthful; R7
-- accepts either honest text (orb_count_refusal_support).
local COUNT_REFUSAL=dofile('tests/prototype/orb_count_refusal_support.lua')
local VERIFY='Echo ownership could not be verified.'
local PLAN,PLAN2='ZQ plan alpha','ZQ plan beta'
local BASE_GRANTED=H.Clone(H.granted)

-- Documented codes (TEST_CONTRACT.md, section 6).
local function set(list) local s={};for _,v in ipairs(list) do s[v]=true end;return s end
local STAGES=set({'ok','assignment','targets','capability','state','balance_loading','balance_invalid','catalog',
 'trust_owned','trust_locked','trust_both','call','granted_unavailable','granted_shape','granted_verify',
 'locked_unavailable','locked_shape','locked_verify','limits','choice','auto_accept','host','unknown'})
local LOCKED_STRICT=set({'locked_unavailable','locked_shape','locked_verify'})
local REJECTIONS=set({'none','absent','not_table','unreadable','invalid_value','conflicting_alias','cycle','depth','over_cap','scalar_leaf'})
local ASSIGNMENTS=set({'ready','unassigned','restoring','loading','unavailable','unknown'})
local ROLES=set({'explicit','untyped','none','unknown'})
local NULL=set({'unknown','unavailable','?'})
local NOT_OBSERVED=set({'none','unknown','unavailable','not_observed','?'})
local REQUIRED={'observed','age','stage','assignment.state','assignment.roles','progress',
 'owned.synced','owned.generation','owned.confirmed','owned.armed','owned.fresh','owned.ghost','owned.total',
 'locked.synced','locked.copies','locked.rejection'}
local function oneOf(values) return function(v) return values[v]==true or NULL[v]==true end end
local function count(v) return (v:match('^%d+$')~=nil and #v<=7) or NULL[v]==true end
local YESNO=set({'yes','no'})
local VALID={
 observed=oneOf(YESNO),
 age=function(v) return (v:match('^%d+s?$')~=nil and #v<=8) or NULL[v]==true end,
 stage=oneOf(STAGES),
 ['assignment.state']=oneOf(ASSIGNMENTS),['assignment.roles']=oneOf(ROLES),
 progress=oneOf(set({'available','unavailable'})),
 ['owned.synced']=oneOf(YESNO),['owned.confirmed']=oneOf(YESNO),['owned.armed']=oneOf(YESNO),
 ['owned.fresh']=oneOf(YESNO),['owned.ghost']=oneOf(YESNO),
 ['owned.generation']=count,['owned.total']=count,
 ['locked.synced']=oneOf(YESNO),['locked.copies']=count,['locked.rejection']=oneOf(REJECTIONS),
 balance=oneOf(set({'confirmed','loading','unknown','unsupported'})),charges=count,
 ['offer.pending']=oneOf(YESNO),['host.pending']=oneOf(YESNO),
 ['progress.rolled']=count,['progress.permanent']=count,
}
-- Privacy (block only): no name, no Echo ID, no reference, no control character.
-- The Echo named 'Locked' (410007) is caught by its ID; its name is also a key word.
local NAMES={'Disposable A','Disposable B','Desired A','Desired B','Protected low','Excess high',
 'Unsafe fallback','Synthetic Echo','Orb test','ZQ plan','ZQ build','PrototypeTester','Ebonhold'}
local IDS={}
for id=410001,410008 do IDS[#IDS+1]=id end
for id=200001,200090 do IDS[#IDS+1]=id end
IDS[#IDS+1]=499999
local function readinessLines(text)
 local out={}
 for line in (tostring(text or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:match('^%s*Orb readiness') then out[#out+1]=line end
 end
 return out
end
local function tokens(lines)
 local t,conflicts={},{}
 for _,line in ipairs(lines) do
  for k,v in line:gmatch('([%a][%w_%.]*)=([%w_%.%-%?]*)') do
   if t[k]~=nil and t[k]~=v then conflicts[#conflicts+1]=k end
   t[k]=v
  end
 end
 return t,conflicts
end
local function leaks(lines,markers)
 local text=table.concat(lines,'\n')
 local found={}
 for _,n in ipairs(NAMES) do if text:find(n,1,true) then found[#found+1]='name '..n end end
 for _,id in ipairs(IDS) do if text:find('%f[%d]'..id..'%f[%D]') then found[#found+1]='id '..id end end
 for _,r in ipairs({'table: ','function: ','userdata: ','thread: ','builtin'}) do
  if text:find(r,1,true) then found[#found+1]='reference' end
 end
 for _,m in ipairs(markers or {}) do if text:find(m,1,true) then found[#found+1]='text '..m:sub(1,40) end end
 for _,line in ipairs(lines) do if line:find('%c') then found[#found+1]='control character' end end
 if #lines>12 then found[#found+1]=#lines..' lines' end
 if #text>1200 then found[#found+1]=#text..' bytes' end
 return found
end
local function ageOf(t)
 local n=t.age and t.age:match('^(%d+)s?$')
 return n and tonumber(n) or nil
end
local function view()
 local fn=Nexus.OrbRuntime.ReadinessView
 if type(fn)~='function' then return nil,'OrbRuntime.ReadinessView is not available' end
 local ok,v=pcall(fn)
 if not ok then return nil,tostring(v) end
 if type(v)~='table' then return nil,'not a table' end
 return v
end
-- One normal Orb window read: open, refresh, close.
local function observe()
 Nexus.OrbPanel.Show();local s=NexusOrbPanel.snapshot;NexusOrbPanel:Hide();return s
end
local function prepared()
 local report,why=Nexus.SupportReport.Prepare({})
 if type(report)~='table' or type(report.chunks)~='table' then error('the real builder did not prepare a report: '..tostring(why)) end
 return table.concat(report.chunks,'')
end
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.locked={}
 H.granted=H.Clone(BASE_GRANTED);A.Owned();A.LockedOwned()
end
-- The block of one no-run report: present, documented, private; existing lines kept.
local function checkBlock(tag,text,markers)
 expect(text:find('Orb action: none unresolved',1,true)~=nil,tag..': the existing Orb action line is kept')
 expect(text:find('no run in this session',1,true)~=nil,tag..': the existing no-run line is kept')
 local lines=readinessLines(text)
 if not expect(#lines>0,tag..': the prepared report carries an Orb readiness block (lines beginning "Orb readiness")') then return nil end
 local t,conflicts=tokens(lines)
 expect(#conflicts==0,tag..': each readiness key has one value',table.concat(conflicts,','))
 local found=leaks(lines,markers)
 expect(#found==0,tag..': the block is bounded and carries no name, Echo ID, reference, raw text or injected payload',table.concat(found,','))
 for key,valid in pairs(VALID) do
  if t[key]~=nil then expect(valid(t[key]),tag..': '..key..' has a documented value',t[key]) end
 end
 return t
end
local function requireObserved(tag,t)
 expect(t.observed=='yes',tag..': the block reports an observation',t.observed)
 local missing={}
 for _,key in ipairs(REQUIRED) do if t[key]==nil then missing[#missing+1]=key end end
 expect(#missing==0,tag..': every documented readiness key is present',table.concat(missing,','))
end
local function is(tag,t,key,want)
 expect(t[key]==want,tag..': '..key..'='..want,t[key])
end

-- The companion storage, loaded on demand as the client loads it.
LoadAddOn=function(name)
 if name~='NexusSupport' then return false end
 dofile('companion/NexusSupport/Storage.lua');H.Fire('ADDON_LOADED','NexusSupport');return true
end
-- Three populated Saved Builds. Slot 1: an untyped Wishlist; slot 2: one with
-- stated roles; slot 3: none. Slot 1 is active.
H.perks.serverBuildSlots={[1]={name='ZQ build one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='ZQ build two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [3]={name='ZQ build three',verified=true,echoes={{spellId=410005,quality=0,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,PLAN,{{spellId=410002,quality=2,stacks=1}}))
assert(A.SetLoadoutWishlistIdentity(2,PLAN2,{{spellId=410002,quality=2,stacks=1,locked=false},
 {spellId=410007,quality=2,stacks=1,locked=true}}))
do
 local a=A.AssignedWishlist()
 assert(a.state=='ready' and a.note==nil and a.name==PLAN,'fixture: slot 1 resolves through its association')
end

-- R0. Before any Orb window read: explicitly not observed, nothing invented.
scenario('R0 before any observation',function()
 local v,why=view()
 if expect(v~=nil,'R0: ReadinessView answers before any Orb read',why) then
  expect(v.observed==false,'R0: nothing is observed yet',tostring(v.observed))
  expect(v.stage==nil and v.at==nil and v.age==nil,'R0: no stage or age is invented')
 end
 local text=prepared()
 local t=checkBlock('R0',text,{})
 if t then
  is('R0',t,'observed','no')
  for _,key in ipairs(REQUIRED) do
   if key~='observed' and t[key]~=nil then
    expect(NOT_OBSERVED[t[key]]==true,'R0: '..key..' is not invented before an observation',t[key])
   end
  end
 end
end)

-- R1. Locked view unavailable. The player opens /nexus orbs, closes it, opens
-- /nexus report and prepares the report file.
scenario('R1 locked view unavailable through /nexus orbs and /nexus report',function()
 H.locked=nil
 local owned,locked=A.Owned(),A.LockedOwned()
 expect(owned.synced==true and locked.synced==false,'R1: fixture: rolled ownership trusted, locked view unavailable')
 SlashCmdList.NEXUS('orbs')
 local s=NexusOrbPanel.snapshot
 expect(s~=nil and s.assignment.state=='ready' and s.progress==nil and s.error==TRUST,
  'R1: fixture: the window read is refused at the trust gate',s and s.error)
 NexusOrbPanel:Hide()
 SlashCmdList.NEXUS('report')
 expect(NexusSupportReport~=nil and NexusSupportReport:IsShown(),'R1: /nexus report opens the support page')
 local meta,why=Nexus.SupportReportUI.PrepareFile(false)
 local stored=type(NexusSupportDB)=='table' and type(NexusSupportDB.report)=='table'
  and type(NexusSupportDB.report.chunks)=='table'
 expect(meta~=nil and stored,'R1: Prepare report file stored the report',why)
 if not stored then return end
 local text=table.concat(NexusSupportDB.report.chunks,'')
 local t=checkBlock('R1',text,{TRUST})
 if t then
  requireObserved('R1',t)
  is('R1',t,'stage','trust_locked')
  is('R1',t,'locked.synced','no');is('R1',t,'locked.copies','0');is('R1',t,'locked.rejection','absent')
  is('R1',t,'owned.synced','yes');is('R1',t,'owned.confirmed','yes');is('R1',t,'owned.armed','yes')
  is('R1',t,'owned.ghost','no')
  is('R1',t,'owned.total',tostring(owned.total));is('R1',t,'owned.generation',tostring(owned.generation))
  is('R1',t,'assignment.state','ready');is('R1',t,'assignment.roles','untyped');is('R1',t,'progress','unavailable')
  local age=ageOf(t);expect(age~=nil and age<=1,'R1: a report right after the read shows a recent age',t.age)
  local v=view()
  if v then expect(v.stage==t.stage,'R1: the report shows the stage the view holds',tostring(v.stage)) end
 end
 -- The copied summary may carry the same lines; if it does, the same rules hold.
 local lines=readinessLines(Nexus.SupportReport.Summary())
 if #lines>0 then
  local found=leaks(lines,{TRUST})
  expect(#found==0,'R1: readiness lines in the copied summary follow the same rules',table.concat(found,','))
 end
end)

-- R2. The observation ages; nothing reads again until the window does.
scenario('R2 stale observation',function()
 local before=view()
 H.locked={}                 -- readable again, but no window read sees it
 H.Advance(90,1)
 local v=view()
 if expect(v~=nil and before~=nil,'R2: ReadinessView answers') then
  expect(v.observed==true and v.at==before.at,'R2: the earlier observation is kept; nothing refreshed it')
  expect(v.stage=='trust_locked','R2: its stage is kept as it was observed',v.stage)
  expect(type(v.age)=='number' and v.age>=90 and v.age<=95,'R2: its age counts from the observation',v.age)
 end
 local t=checkBlock('R2',prepared(),{})
 if t then
  is('R2',t,'observed','yes');is('R2',t,'stage','trust_locked')
  is('R2',t,'locked.synced','no')
  local age=ageOf(t)
  expect(age~=nil and age>=90 and age<=95,'R2: the report shows the age, never a current read',t.age)
 end
 local s=observe()
 expect(s.progress~=nil,'R2: fixture: a new window read succeeds',s.error)
 t=checkBlock('R2 reopened',prepared(),{})
 if t then
  is('R2 reopened',t,'stage','ok');is('R2 reopened',t,'progress','available')
  is('R2 reopened',t,'locked.synced','yes');is('R2 reopened',t,'locked.rejection','none')
  local age=ageOf(t);expect(age~=nil and age<=1,'R2 reopened: the new observation replaces the old one',t.age)
 end
end)

-- R3. A run boundary with an unchanged rolled mirror: armed, not confirmed.
local r3
scenario('R3 rolled ownership not confirmed for this generation',function()
 trusted()
 local gen=A.Owned().generation
 H.holdGrantedResponse=true;A.RunBoundaryReset()
 local owned=A.Owned()
 expect(owned.synced==false and owned.generation==gen+1,'R3: fixture: the same mirror after a run boundary is not confirmed')
 local s=observe()
 expect(s.error==TRUST and s.progress==nil,'R3: fixture: the window read waits at the trust gate',s.error)
 local t=checkBlock('R3',prepared(),{TRUST})
 if t then
  r3=t
  requireObserved('R3',t)
  is('R3',t,'stage','trust_owned')
  is('R3',t,'owned.synced','no');is('R3',t,'owned.confirmed','no');is('R3',t,'owned.armed','yes')
  is('R3',t,'owned.fresh','no');is('R3',t,'owned.ghost','no')
  is('R3',t,'owned.generation',tostring(gen+1));is('R3',t,'owned.total',tostring(owned.total))
  is('R3',t,'locked.synced','yes');is('R3',t,'locked.copies','0');is('R3',t,'locked.rejection','none')
  is('R3',t,'assignment.state','ready');is('R3',t,'progress','unavailable')
 end
end)

-- R4. Both views untrusted.
scenario('R4 rolled and locked both untrusted',function()
 H.locked=nil
 local s=observe()
 expect(s.error==TRUST,'R4: fixture: trust gate',s.error)
 local t=checkBlock('R4',prepared(),{TRUST})
 if t then
  is('R4',t,'stage','trust_both')
  is('R4',t,'owned.synced','no');is('R4',t,'locked.synced','no');is('R4',t,'locked.rejection','absent')
 end
end)

-- R5. A reply that replaces the mirror with an empty table: confirmed EMPTY,
-- which is trusted and is not the same as unavailable.
scenario('R5 confirmed empty rolled ownership',function()
 H.holdGrantedResponse=nil;H.locked={};H.granted={}
 local owned=A.Owned()
 expect(owned.synced==true and owned.total==0,'R5: fixture: a new empty table confirms an empty mirror')
 local s=observe()
 expect(s.progress~=nil,'R5: fixture: the window read succeeds',s.error)
 local t=checkBlock('R5',prepared(),{})
 if t then
  is('R5',t,'stage','ok');is('R5',t,'progress','available')
  is('R5',t,'owned.synced','yes');is('R5',t,'owned.total','0');is('R5',t,'owned.confirmed','yes')
  is('R5',t,'owned.fresh','yes')
  is('R5',t,'locked.synced','yes');is('R5',t,'locked.copies','0');is('R5',t,'locked.rejection','none')
  if r3 then
   expect(r3['owned.synced']~=t['owned.synced'],'R5: confirmed empty is reported differently from unconfirmed ownership')
  end
 end
end)

-- R6. Trusted views, then the strict reader refuses: a failure after trust.
scenario('R6 strict reader refuses after the trust gate',function()
 H.granted=H.Clone(BASE_GRANTED);H.locked={{id=410007,count=1}}
 local locked=A.LockedOwned()
 expect(locked.synced==true and locked.bySpell[410007]==1,'R6: fixture: the locked getter trusts this shape')
 local s=observe()
 expect(s.error==VERIFY and s.progress==nil,'R6: fixture: the strict reader refuses it',s.error)
 local t=checkBlock('R6',prepared(),{VERIFY})
 if t then
  expect(LOCKED_STRICT[t.stage]==true,'R6: the stage names the locked strict reader, not the trust gate',t.stage)
  is('R6',t,'locked.synced','yes');is('R6',t,'locked.copies','1');is('R6',t,'locked.rejection','none')
  is('R6',t,'owned.synced','yes');is('R6',t,'progress','unavailable')
 end
end)

-- R7. Malformed locked counts are kept by the getter while it reports false
-- trust; the report shows both and neither erases nor widens trust.
scenario('R7 locked copies over the limit',function()
 -- One record above the 120-copy row ceiling: over the cap (occupied
 -- records, not copies, meet the live capacity).
 H.locked={{spellId=410007,stacks=121}}
 local locked=A.LockedOwned()
 expect(locked.synced==false and locked.bySpell[410007]==121,'R7: fixture: the getter keeps the parsed count and reports false trust')
 local s=observe()
 expect(COUNT_REFUSAL.TrustRefusal(s.error),'R7: fixture: trust gate',s.error)
 local t=checkBlock('R7',prepared(),{TRUST,type(s.error)=='string' and s.error~='' and s.error or TRUST})
 if t then
  is('R7',t,'stage','trust_locked')
  is('R7',t,'locked.synced','no');is('R7',t,'locked.copies','121');is('R7',t,'locked.rejection','over_cap')
 end
end)

-- R8. A getter that raises: an untrusted locked view, and none of its text.
scenario('R8 a failing locked getter',function()
 H.locked={}
 local S=ProjectEbonhold.PerkService;local real=S.GetLockedPerks
 local MARK='ZQ_GETTER_MARKER_5521 Disposable A 410001'
 S.GetLockedPerks=function() error(MARK) end
 local ok,s=pcall(observe)
 S.GetLockedPerks=real
 expect(ok,'R8: the window read survives the failing getter',s)
 if ok then expect(s.error==TRUST,'R8: fixture: trust gate',s.error) end
 local t=checkBlock('R8',prepared(),{MARK,'ZQ_GETTER_MARKER'})
 if t then
  is('R8',t,'stage','trust_locked');is('R8',t,'locked.synced','no')
  expect(t['locked.rejection']=='absent' or t['locked.rejection']=='unreadable','R8: the rejection is a code',t['locked.rejection'])
 end
end)

-- R9. Role mode and assignment state.
scenario('R9 stated roles and an unassigned loadout',function()
 trusted()
 H.perks.serverActiveSlot=2;H.Notify();A.Poll()
 local s=observe()
 expect(s.assignment.state=='ready' and s.assignment.name==PLAN2,'R9: fixture: slot 2 resolves its Wishlist with stated roles',s.assignment.state)
 local t=checkBlock('R9 roles',prepared(),{})
 if t then is('R9 roles',t,'assignment.state','ready');is('R9 roles',t,'assignment.roles','explicit') end
 H.perks.serverActiveSlot=3;H.Notify();A.Poll()
 s=observe()
 expect(s.assignment.state=='unassigned','R9: fixture: slot 3 has no association',s.assignment.state)
 t=checkBlock('R9 unassigned',prepared(),{})
 if t then
  is('R9 unassigned',t,'assignment.state','unassigned');is('R9 unassigned',t,'stage','assignment')
  is('R9 unassigned',t,'progress','unavailable')
  local roles=t['assignment.roles']
  expect(roles=='none' or roles=='unknown','R9 unassigned: no role mode without a ready assignment',roles)
 end
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
end)

expect(H.Count('orb-spend')==0 and H.Count('take')==0,'no Orb was spent and no Echo selected')
if #failures>0 then
 error('orb_passive_readiness_report: '..#failures..' of '..checks..' expectation(s) failed; first: '..failures[1],0)
end
print('PASS orb_passive_readiness_report checks='..checks)
