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
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_capacity_display')
local printable=B.printable
local H=dofile('tests/prototype/harness.lua')
H.Boot()
local backing,settings,account={},{},{}
local store={State=function() return backing end,Settings=function() return settings end}
local A=Nexus.GameAdapter;A.Init({},store)
local model=Nexus.WishlistModel.New()
local c=Nexus.WishlistInternals.Controller.New({model=model,store=store,
 accountRoot=function() return account end,notify=function() end})
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

C.guard(#H.actions==actions,'no game action',#H.actions-actions)
C.finish('(occupied records and the live capacity drive the locked display; a new partition is a change)')
