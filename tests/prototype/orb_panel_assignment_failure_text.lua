-- Orb window targets line for a READY assigned Wishlist whose Orb read is
-- refused. Reproduced from source at aac790c (source diagnosis, section 2): with
-- an active populated Saved Build whose Wishlist resolves through its
-- association (the adapter sets no note), any refusal of the Orb read leaves
-- the window showing "Assigned Wishlist: <name>" together with "Assign a
-- Wishlist through My Builds to begin.". A ready first-run assignment shows
-- only its note, which does not say that progress is unavailable either.
-- Contract (TEST_CONTRACT.md of the tests-first review, section 2): for a ready assignment
-- without progress the targets line contains "progress" and "unavailable" (any
-- letter case) and never the assignment prompt. Every other targets text, the
-- plan line, the status reason and Start eligibility stay as they are.
-- Real TOC boot, adapter, Orb runtime/policy and window; the fake Orb and Perk
-- services of orbs_support.lua. Artificial IDs and names. Nothing is spent or
-- selected. Every expectation is evaluated and reported; the test fails at the
-- end if any did not hold.
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
local BALANCE="Waiting for the server's Orb balance. Use Recheck once it is available."
local VERIFY='Echo ownership could not be verified.'
local FIRST_RUN='Orb test'   -- the first-run plan of orbs_support.lua (H.OrbPlan)
local PLAN='ZQ plan alpha'
local BASE_GRANTED=H.Clone(H.granted)
local f
local function show() Nexus.OrbPanel.Show();f=NexusOrbPanel;return f.snapshot end
local function refresh()
 if not f then return show() end
 Nexus.OrbPanel.Refresh();return f.snapshot
end
local function shown(region) return tostring(region:GetText() or '') end
local function conveysUnavailable(line)
 local lower=line:lower()
 return lower:find('progress',1,true)~=nil and lower:find('unavailable',1,true)~=nil
end
-- Trusted, readable ownership and a known balance, as after login.
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.locked={}
 H.granted=H.Clone(BASE_GRANTED);A.Owned();A.LockedOwned()
end
-- A ready assignment whose Orb read succeeds: everything as before.
local function readyWithProgress(tag,name)
 trusted()
 local s=refresh()
 local targets=shown(f.targets)
 expect(s.assignment.state=='ready' and s.progress~=nil,tag..': fixture: a ready assignment whose Orb read succeeds',s.error)
 if s.progress then
  expect(targets==s.progress.rolledMissing..' rolled target copies still missing',tag..': the progress line is unchanged',targets)
 end
 expect(shown(f.plan)=='Assigned Wishlist: '..name,tag..': the plan line is unchanged',shown(f.plan))
 expect(s.canStart==true and f.start:IsEnabled(),tag..': Start is offered as before',s.startReason)
end
-- A ready assignment whose Orb read is refused by `setup`.
local function refused(tag,name,setup,reason)
 trusted();setup()
 local s=refresh()
 local plan,targets,status=shown(f.plan),shown(f.targets),shown(f.status)
 print('OBSERVED '..tag..': targets line "'..targets..'"; read reason "'..tostring(s.error)..'"')
 expect(s.assignment.state=='ready' and s.progress==nil and s.error==reason,
  tag..': fixture: a ready assignment whose Orb read is refused with the existing text',s.error)
 expect(targets:find('Assign a Wishlist',1,true)==nil,
  tag..': the targets line does not ask to assign the Wishlist the plan line names',targets)
 expect(conveysUnavailable(targets),tag..': the targets line says that target progress is unavailable',targets)
 expect(plan=='Assigned Wishlist: '..name,tag..': the plan line is unchanged',plan)
 expect(type(s.error)=='string' and status:find(s.error,1,true)~=nil,tag..': the status line still gives the read reason',status)
 expect(s.canStart==false and not f.start:IsEnabled() and s.startReason==s.error,
  tag..': Start stays refused for the same reason',s.startReason)
 trusted()
end

-- A. First run, nothing assigned: the first-run prompt note, unchanged.
scenario('A nothing assigned',function()
 local s=show()
 local targets=shown(f.targets)
 expect(s.assignment.state=='unassigned' and type(s.assignment.note)=='string',
  'A: fixture: no Wishlist is assigned on a first run',s.assignment.state)
 expect(targets==tostring(s.assignment.note),'A: the first-run prompt note is shown unchanged',targets)
 expect(s.canStart==false and not f.start:IsEnabled(),'A: Start stays disabled')
end)

-- C. A ready first-run assignment (note "First-run wishlist target").
scenario('C first-run assignment',function()
 H.OrbPlan()
 local s=refresh()
 expect(s.assignment.state=='ready' and s.assignment.note=='First-run wishlist target',
  'C: fixture: a ready first-run assignment carries its note',tostring(s.assignment.note))
 readyWithProgress('C ready',FIRST_RUN)
 refused('C locked view unavailable',FIRST_RUN,function() H.locked=nil end,TRUST)
end)

-- B. The reproduced case: an active populated Saved Build whose Wishlist
-- resolves through its association, so the assignment carries no note.
scenario('B association',function()
 H.perks.serverBuildSlots={[1]={name='ZQ build one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='ZQ build two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 local ok,why=A.SetLoadoutWishlistIdentity(1,PLAN,{{spellId=410002,quality=2,stacks=1}})
 assert(ok,'fixture: the association is written: '..tostring(why))
 local a=A.AssignedWishlist()
 expect(a.state=='ready' and a.note==nil and a.name==PLAN,
  'B: fixture: the active populated loadout resolves through its association with no adapter note',
  tostring(a.state)..'/'..tostring(a.note))
 readyWithProgress('B ready',PLAN)
 refused('B locked view unavailable',PLAN,function() H.locked=nil end,TRUST)
 refused('B balance not known',PLAN,function() O.known=false end,BALANCE)
 refused('B strict reader after the trust gate',PLAN,function() H.locked={{id=410007,count=1}} end,VERIFY)
 refused('B rolled ownership not confirmed for this run',PLAN,function()
  H.holdGrantedResponse=true;A.RunBoundaryReset()
 end,TRUST)
 readyWithProgress('B ready again',PLAN)
end)

-- B. Assignments that are not ready keep their own note.
scenario('B other assignment states',function()
 trusted()
 H.perks.serverActiveSlot=2;H.Notify();A.Poll()
 local s=refresh()
 expect(s.assignment.state=='unassigned' and type(s.assignment.note)=='string',
  'B unassigned: fixture: the active loadout has no association',s.assignment.state)
 expect(shown(f.targets)==tostring(s.assignment.note),'B unassigned: its note is shown unchanged',shown(f.targets))
 expect(s.canStart==false and not f.start:IsEnabled(),'B unassigned: Start stays disabled')
 H.perks.serverActiveSlot=nil;H.Notify();A.Poll()
 s=refresh()
 expect(s.assignment.state=='restoring','B restoring: fixture: the active loadout is not known yet',s.assignment.state)
 expect(shown(f.plan)=='Restoring assigned Wishlist...','B restoring: the plan line is unchanged',shown(f.plan))
 expect(shown(f.targets)==tostring(s.assignment.note),'B restoring: its note is shown unchanged',shown(f.targets))
 expect(s.canStart==false and not f.start:IsEnabled(),'B restoring: Start stays disabled')
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 s=refresh()
 expect(s.assignment.state=='ready' and s.progress~=nil,'B: the association resolves again with progress',s.error)
end)

expect(H.Count('orb-spend')==0 and H.Count('take')==0,'nothing was spent or selected')
if #failures>0 then
 error('orb_panel_assignment_failure_text: '..#failures..' of '..checks..' expectation(s) failed; first: '..failures[1],0)
end
print('PASS orb_panel_assignment_failure_text checks='..checks)
