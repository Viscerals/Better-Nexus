-- Group 3 supplement (NX-01; root audit questions 1 and 2): the Wishlist
-- editor's locked strip and the locked presentation revision against a dynamic
-- live capacity and against the native record partition.
-- Native contract (static data, never executed): one locked record per Echo
-- holds its full stack (perks_service.lua 308-315); occupancy is the number
-- of records, compared with the dynamic GetMaximumPermanentEchoes
-- (echo_journal.lua 4533-4535); the six journal discs are display only.
-- core/GameAdapter.lua LockedFingerprint is the aggregate per-spell copy map,
-- so a new record partition with equal copies advances no locked revision,
-- and ui/WishlistRenderer.lua skips its refresh while the revisions match.
-- EXPECT (fails at 8c):
--   CAP7 capacity 7, seven single records: the strip and the footer count
--        seven occupied records, never above a stated maximum below seven
--        (no denominator, or the live capacity 7), and each record shows once;
--   PART the same per-spell copies {A x2, B, C} move from four records
--        (A, A, B, C) to three (A x2, B, C) in fresh tables: the locked
--        presentation revision advances exactly once, and the strip, the
--        footer and the icons show three occupied records (A once); moving
--        back advances it once more.
-- GUARD (holds at 8c): the four-record partition shows four (A twice, one
-- per record); the identical three records in fresh tables, and the same
-- records in another order, advance nothing; a real per-spell change advances
-- the revision once; the authored-target footer stays "Locked targets: 0/6"
-- at live capacity 7 (design policy, separate from current ownership); no
-- game action.
-- SETUP: real TOC boot, real WishlistModel/Controller/Renderer and injected
-- Store as batch_locked_units_display.lua; synthetic records and capacity.
-- No claim is made that the server grants a seventh slot.
-- Editor locked-target budget (standards review r1, STD-R1-01). The editor
-- held current locked COPIES plus new designs to one universal six, so an
-- empty strip slot could not be targeted. Two rules replace it: the plan's
-- own target copies stay within the authored six (a target's copies count),
-- and occupied records plus one record per designed spell that holds none
-- stay within the live capacity (six cells while it is unknown).
-- EXPECT (fails at 3bc6d88): through the real controller's empty-slot
-- assignment, BUD5 five records holding seven copies at capacity 6 and BUD7
-- six single records at capacity 7 (design-less plans; the held Echoes are
-- not design) each accept their first locked target; BUDN two records kept
-- and a plan of four target copies in two spells at capacity 6 accept a
-- third designed spell (records counted per spell, copies per target); the
-- two refusal notices name their own rule (the plan's six target copies, the
-- live locked slots); BUDFX the export of a draft that replaces a fulfilled
-- target carries the final design's six copies, not the replaced target too.
-- GUARD (holds at 3bc6d88): BUD6 six single records at capacity 6 refuse a
-- new target and the draft is unchanged; BUDD a seventh authored target copy
-- (four spells holding six copies) is refused; BUDF six fulfilled target
-- copies refuse a seventh although capacity 8 leaves two slots free; BUDX
-- the replacement of a locked Echo at full occupancy, and BUDFX of a
-- fulfilled target, are accepted and name the replaced spell; BUDR the BUDN
-- plan loaded beside the held records accepts the third spell (accepted at
-- 3bc6d88 too: the root red run observed outcome=queued; by source reading
-- NormalizeCandidateEvidence pairs each loaded target with a held record as
-- its replacement there, so those records are freed).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_capacity_display')
local printable=B.printable
local H=dofile('tests/prototype/harness.lua')
H.Boot()
local backing,settings,account={},{},{}
local store={State=function() return backing end,Settings=function() return settings end}
local A=Nexus.GameAdapter;A.Init({},store)
local model=Nexus.WishlistModel.New()
local notices={}
local c=Nexus.WishlistInternals.Controller.New({model=model,store=store,
 accountRoot=function() return account end,
 notify=function(message) notices[#notices+1]=B.Plain(tostring(message)) end})
c.Initialize(A);c.BeginNewWishlist()
local r=Nexus.WishlistInternals.Renderer.New({controller=c,family=model.Family,
 draftKey=model.DraftKey,echoListTotal=model.EchoListTotal})
local frame=r.Prepare();r.ShowFrame();r.Refresh();A.Poll()
local capacity=6
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return capacity end
local function Region(prefix)
 for _,f in ipairs(frame.regions) do
  local text=B.Plain(f:GetText() or '')
  if text:find(prefix,1,true) then return text end
 end
end
local function Icons()
 local ids,count={},0
 for _,f in ipairs(frame.children) do
  if f.slotState=='locked' and f:IsShown() then
   count=count+1;ids[f.spellId]=(ids[f.spellId] or 0)+1
  end
 end
 return count,ids
end
local function LockedRevision() return (select(7,A.PresentationRevisions())) end
C.setup(Region('Locked')~=nil and Region('Rolled copies:')~=nil,'the actual locked strip label and footer exist')
C.setup(type(LockedRevision())=='number','the locked presentation revision is readable')
local actions=#H.actions

local function Show(label,records)
 H.locked=records;H.Notify();A.Poll();r.Refresh()
 local strip,footer=Region('Locked (') or '',Region('Rolled copies:') or ''
 local count,ids=Icons()
 print('OBSERVED',label,'label='..strip,'footer='..(footer:gsub('\n',' | ')),'locked icons='..count,
  'locked revision='..printable(LockedRevision()))
 return strip,footer,count,ids
end
-- The occupied count of a "Locked (N/M):" or "Currently locked: N/M" text and
-- its stated maximum ('' when none is stated).
local function Count(text,prefix)
 local n,rest=text:match(prefix..'(%d+)(/?%d*)')
 return tonumber(n),rest and rest:gsub('/','') or nil
end
local function R(id,stack) return {spellId=id,stack=stack} end

C.scenario('CAP7 seven single records at capacity 7',function()
 capacity=7
 local strip,footer,count,ids=Show('CAP7',{R(200080,1),R(200081,1),R(200082,1),R(200083,1),R(200084,1),R(200085,1),R(200086,1)})
 local n,max=Count(strip,'Locked %(')
 C.expect(n==7 and (max=='' or max=='7'),'CAP7: the strip counts seven occupied records, with no maximum below seven',strip)
 local f,fmax=Count(footer,'Currently locked: ')
 C.expect(f==7 and (fmax=='' or fmax=='7'),'CAP7: the footer counts seven occupied records, with no maximum below seven',footer)
 local distinct=0;for _ in pairs(ids) do distinct=distinct+1 end
 C.expect(count==7 and distinct==7,'CAP7: each of the seven records shows once',count)
 C.guard(footer:find('Locked targets: 0/6',1,true)~=nil,'CAP7: the authored-target footer stays six (design policy)',footer)
 capacity=6
end)

C.scenario('PART same per-spell copies, another record partition',function()
 capacity=6
 local A1,B1,C1,D1=200090,200091,200092,200093
 local strip,_,count,ids=Show('P4',{R(A1,1),R(A1,1),R(B1,1),R(C1,1)})
 C.guard(strip:find('Locked (4/',1,true)~=nil and count==4 and ids[A1]==2,
  'PART: four records (two of one spell) show four, one icon per record',strip)
 local rev0=LockedRevision()
 local footer
 strip,footer,count,ids=Show('P3',{R(A1,2),R(B1,1),R(C1,1)})
 local rev1=LockedRevision()
 C.expect(rev1==rev0+1,'PART: the locked revision advances once when the partition changes with equal copies',
  printable(rev0)..' -> '..printable(rev1))
 C.expect(strip:find('Locked (3/',1,true)~=nil,'PART: the strip counts three occupied records',strip)
 C.expect(footer:find('Currently locked: 3/',1,true)~=nil,'PART: the footer counts three occupied records',footer)
 C.expect(count==3 and ids[A1]==1,'PART: one icon per record, the stacked record once',count)
 Show('P3 again',{R(A1,2),R(B1,1),R(C1,1)})
 local rev2=LockedRevision()
 C.guard(rev2==rev1,'PART: the identical records in fresh tables are not a change',printable(rev1)..' -> '..printable(rev2))
 Show('P3 reordered',{R(C1,1),R(B1,1),R(A1,2)})
 local rev3=LockedRevision()
 C.guard(rev3==rev2,'PART: the same records in another order are not a change',printable(rev2)..' -> '..printable(rev3))
 Show('P4 back',{R(A1,1),R(B1,1),R(A1,1),R(C1,1)})
 local rev4=LockedRevision()
 C.expect(rev4==rev3+1,'PART: moving back to four records advances the revision once more',printable(rev3)..' -> '..printable(rev4))
 Show('real change',{R(A1,2),R(B1,1),R(D1,1)})
 local rev5=LockedRevision()
 C.guard(rev5==rev4+1,'PART: a real per-spell change advances the revision once',printable(rev4)..' -> '..printable(rev5))
end)

-- The editor's locked-target budget. A new draft, optionally holding the
-- typed locked targets {spellId, copies} of a plan; the targets are spells
-- nobody holds locked.
local function Draft(targets)
 c.BeginNewWishlist()
 if not targets then return true end
 local rows={}
 for i=1,10 do rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for _,t in ipairs(targets) do rows[#rows+1]={spellId=t[1],quality=t[1]%4,stacks=t[2],locked=true} end
 return c.LoadPendingEchoes(rows)==true
end
-- Designed targets of the draft: distinct rows and their copies.
local function Designed()
 local n,copies=0,0
 for _,row in pairs(c.PendingLockRows()) do n=n+1;copies=copies+(tonumber(row.stacks) or 1) end
 for _,row in pairs(c.PendingRows()) do if row.lockIntent then n=n+1;copies=copies+1 end end
 return n,copies
end
-- The empty-slot flow of the strip: assignment mode, an Echo chosen, done.
-- Returns the controller's outcome and the notices it gave.
local function Assign(id,replacing)
 local before=#notices
 if replacing then c.ToggleReplacementAssignment(replacing) else c.ToggleEmptyAssignment() end
 local outcome=c.AssignLockSlot(A.Catalog().rows[id])
 c.EndAssignment();r.Refresh()
 local said={}
 for i=before+1,#notices do said[#said+1]=notices[i] end
 return outcome,table.concat(said,' | ')
end
local DESIGN_NOTICE,SLOTS_NOTICE='at most 6 locked target copies','locked Echo slots the game reports'
local function Singles(first,n) local t={};for i=0,n-1 do t[#t+1]=R(first+i,1) end;return t end

C.scenario('BUD5 five records holding seven copies, capacity 6',function()
 capacity=6
 Show('BUD5',{R(200080,1),R(200081,1),R(200082,1),R(200083,3),R(200084,1)})
 C.setup(Draft(),'BUD5: a new draft')
 local outcome,said=Assign(200050)
 print('OBSERVED','BUD5 outcome='..printable(outcome),'notices='..said)
 C.expect(outcome=='queued' and Designed()==1,'BUD5: the free sixth slot takes one new locked target',printable(outcome)..' | '..said)
end)

C.scenario('BUD7 six single records, capacity 7',function()
 capacity=7
 Show('BUD7',Singles(200080,6))
 C.setup(Draft(),'BUD7: a new draft')
 local outcome,said=Assign(200050)
 print('OBSERVED','BUD7 outcome='..printable(outcome),'notices='..said)
 C.expect(outcome=='queued' and Designed()==1,'BUD7: the free seventh slot takes one new locked target',printable(outcome)..' | '..said)
 capacity=6
end)

C.scenario('BUDR two records and four target copies in two spells, capacity 6',function()
 capacity=6
 Show('BUDR',Singles(200086,2))
 C.setup(Draft({{200060,3},{200061,1}}) and select(2,Designed())==4,'BUDR: a draft whose plan targets 3+1 copies')
 local outcome,said=Assign(200062)
 local n,copies=Designed()
 print('OBSERVED','BUDR outcome='..printable(outcome),'targets='..n..'/'..copies,'notices='..said)
 C.guard(outcome=='queued' and n==3 and copies==5,
  'BUDR: a plan loaded beside the held records accepts a third designed spell (5 of 6 target copies)',printable(outcome)..' '..n..'/'..copies)
end)

C.scenario('BUDN the same plan loaded before the records are held',function()
 capacity=6
 Show('BUDN0',{})
 C.setup(Draft({{200060,3},{200061,1}}) and select(2,Designed())==4,'BUDN: a draft whose plan targets 3+1 copies')
 Show('BUDN',Singles(200086,2))
 local paired=0
 for _,row in pairs(c.PendingLockRows()) do if row.replaces~=nil then paired=paired+1 end end
 C.setup(paired==0,'BUDN: no planned target replaces a held record',paired)
 local outcome,said=Assign(200062)
 local n,copies=Designed()
 print('OBSERVED','BUDN outcome='..printable(outcome),'targets='..n..'/'..copies,'notices='..said)
 C.expect(outcome=='queued' and n==3 and copies==5,
  'BUDN: two kept records and three designed spells fit six slots (5 of 6 target copies)',printable(outcome)..' '..n..'/'..copies)
end)

C.scenario('BUD6 six single records, capacity 6',function()
 capacity=6
 Show('BUD6',Singles(200080,6))
 C.setup(Draft(),'BUD6: a new draft')
 local outcome,said=Assign(200050)
 print('OBSERVED','BUD6 outcome='..printable(outcome),'notices='..said)
 C.guard(outcome~='queued' and outcome~='tagged' and Designed()==0,'BUD6: full occupancy refuses a new target; the draft is unchanged',
  printable(outcome))
 C.expect(said:find(SLOTS_NOTICE,1,true)~=nil and said:find('6 locked Echo slots',1,true)~=nil,
  'BUD6: the refusal names the live locked slots',said)
end)

C.scenario('BUDD a seventh authored target copy',function()
 capacity=6
 Show('BUDD',{})
 C.setup(Draft({{200060,3},{200061,1},{200062,1},{200063,1}}) and select(2,Designed())==6,'BUDD: a draft whose plan targets six copies in four spells')
 local outcome,said=Assign(200064)
 local n,copies=Designed()
 print('OBSERVED','BUDD outcome='..printable(outcome),'targets='..n..'/'..copies,'notices='..said)
 C.guard(outcome=='lock_full' and n==4 and copies==6,'BUDD: a seventh target copy is refused by the design limit',printable(outcome)..' '..n..'/'..copies)
 C.expect(said:find(DESIGN_NOTICE,1,true)~=nil and said:find(SLOTS_NOTICE,1,true)==nil,
  'BUDD: the refusal names the plan design limit, not the slots',said)
end)

C.scenario('BUDX a replacement at full occupancy',function()
 capacity=6
 Show('BUDX',Singles(200080,6))
 C.setup(Draft(),'BUDX: a new draft')
 local outcome,said=Assign(200050,200080)
 local planned
 for _,row in pairs(c.PendingLockRows()) do planned=row end
 print('OBSERVED','BUDX outcome='..printable(outcome),'replaces='..printable(planned and planned.replaces),'notices='..said)
 C.guard(outcome=='queued' and planned~=nil and planned.spellId==200050 and planned.replaces==200080,
  'BUDX: the replacement of a locked Echo is accepted and names the replaced spell',printable(outcome))
end)

-- A plan whose six target copies are the six held records: fulfilled targets.
local SIX_HELD={{200080,1},{200081,1},{200082,1},{200083,1},{200084,1},{200085,1}}
local function Fulfilled()
 local n=0
 for _ in pairs(c.FulfilledDraftTargets()) do n=n+1 end
 return n
end

C.scenario('BUDF six fulfilled target copies, spare capacity 8',function()
 capacity=8
 Show('BUDF',Singles(200080,6))
 C.setup(Draft(SIX_HELD) and Fulfilled()==6 and Designed()==0,'BUDF: a draft whose six targets are all held (fulfilled)')
 local outcome,said=Assign(200050)
 print('OBSERVED','BUDF outcome='..printable(outcome),'fulfilled='..Fulfilled(),'notices='..said)
 C.guard(outcome=='lock_full' and Designed()==0 and Fulfilled()==6,
  'BUDF: a seventh authored target copy is refused although two record slots are free',printable(outcome))
 capacity=6
end)

C.scenario('BUDFX replacing a fulfilled target at full occupancy',function()
 capacity=6
 Show('BUDFX',Singles(200080,6))
 C.setup(Draft(SIX_HELD) and Fulfilled()==6,'BUDFX: a draft whose six targets are all held (fulfilled)')
 local outcome,said=Assign(200050,200080)
 local planned
 for _,row in pairs(c.PendingLockRows()) do planned=row end
 print('OBSERVED','BUDFX outcome='..printable(outcome),'replaces='..printable(planned and planned.replaces),'notices='..said)
 C.guard(outcome=='queued' and planned~=nil and planned.replaces==200080,
  'BUDFX: the replacement of a fulfilled target is accepted (its old target leaves the design)',printable(outcome))
 local locked,old=0,0
 for _,e in ipairs(c.ExportEntries()) do
  if e.locked==true then locked=locked+(tonumber(e.stacks) or 1);if e.spellId==200080 then old=old+1 end end
 end
 print('OBSERVED','BUDFX export locked='..locked,'replaced exported='..old)
 C.expect(locked==6 and old==0,'BUDFX: the export carries the six target copies of the final design, not the replaced target too',
  locked..'/'..old)
end)

C.guard(#H.actions==actions,'no game action',#H.actions-actions)
C.finish('(occupied records and the live capacity drive the locked display; a new partition is a change)')
