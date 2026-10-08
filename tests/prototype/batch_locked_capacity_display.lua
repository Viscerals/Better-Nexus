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
-- Copy and save design boundary (standards review r2, STD-R2-01). Admitted
-- owned records (a record's locked rows, one per occupied record holding its
-- whole stack) stay valid data; a Copy makes them the plan's authored target
-- design, which holds at most six copies. Copy candidates are built by the
-- real CandidateEvidence.Build/Validate as Leaderboard and the Build Library
-- build them; uploads reach only the harness's fake service, and saves and
-- assignments only the injected Store.
-- EXPECT (fails at 1756f4d):
--   CPY7  the player's own record of 79 ordinary copies and five locked
--         records holding 1,1,1,3,1 (seven copies, held now at capacity 6):
--         BeginCandidate refuses the Copy, naming the six-copy design limit,
--         and keeps the seeded draft exactly, with no Copy binding;
--   CPY7S the same record, nothing held: the Copy and the Save after it
--         upload nothing and keep no retry;
--   SAV7  an existing editor state whose own design is seven copies (two
--         kept fulfilled targets, three lock intents, two queued copies of a
--         stored design; through the controller's untyped loader, not a
--         Copy): Save refuses before any upload, naming the design limit, and
--         keeps the draft with nothing saved or assigned; a direct
--         AcceptApply payload uploads, saves and assigns nothing; while an
--         upload is still spaced no retry is kept and nothing is uploaded later.
-- GUARD (holds at 1756f4d): CPY7 the record evidence stays valid and opening
-- the Copy writes nothing; CPY7S nothing is remembered, saved or assigned;
-- CPY6 a Copy of five records holding six copies opens with the six design
-- copies and saves them (only the 79 ordinary copies are uploaded; the
-- assigned plan and its remembered roles hold the six); CPY6M one record
-- holding six copies of one Echo, above its catalog maxStack, opens and saves
-- as six copies; CPYA a Copy of an unknown contract, with no bound validator,
-- or whose record evidence changed is refused with the draft unchanged, and
-- Save of a Copy whose record changed after opening is refused before upload;
-- SAVX a draft replacing a fulfilled target saves six design copies (the
-- replaced target is not counted, as PlanLockCommit drops it); SAVU six
-- target copies beside seven unrelated held copies in five records (five
-- occupied plus six planned exceed capacity 6) are not refused, and the
-- spaced save is retried once and saves the six.
-- SETUP: the seeded drafts, the seven-copy state (its own intent, queued and
-- kept fulfilled copies; replaced targets excluded), and the fake upload that
-- keeps the next upload spaced. No capacity or maxStack bound is asserted.
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

-- Copy and save design boundary (STD-R2-01). These scenarios upload through
-- the fake service, so the guard above covers the scenarios before it; each
-- one below counts its own uploads and Store writes.
local CE=Nexus.CandidateEvidence
-- Admitted owned records: a record's locked rows, the copies each record holds.
local RECORD_SEVEN,RECORD_SIX={1,1,1,3,1},{1,1,1,2,1}
-- Those rows as locked spells from 200080, by copies: a Copy's design targets.
local function Spells(stacks) local t={};for i,s in ipairs(stacks) do t[200079+i]=s end;return t end
-- A Copy candidate as Leaderboard and the Build Library make one: the real
-- CandidateEvidence.Build over a record's two typed pools (79 ordinary copies;
-- locked rows from 200080), bound to the record's current evidence. The
-- second result changes that evidence (the record goes stale).
local function Candidate(id,stacks)
 local ordinary,locked={},{}
 for i=1,79 do ordinary[i]={spellId=200000+i,quality=i%4,stacks=1} end
 for i,s in ipairs(stacks) do locked[i]={spellId=200079+i,quality=(79+i)%4,stacks=s} end
 local current='synthetic-evidence-'..id
 local candidate=CE.Build({title='Synthetic Copy '..id,ordinaryEchoes=ordinary,lockedEchoes=locked,
  sourceIdentity='synthetic-record-'..id,selectedEvidence=current,currentEvidence=function() return current end})
 return candidate,function(value) current=value end
end
-- The draft's own design copies as PlanLockCommit keeps them: one per
-- lock-intent row, each queued target's stacks, and the fulfilled targets the
-- final design keeps (held, not replaced, not designed again).
local function PlanDesign()
 local designed,replaced,copies={},{},0
 local function Design(row,n)
  designed[row.spellId]=true;copies=copies+n
  if type(row.replaces)=='number' then replaced[row.replaces]=true end
 end
 for _,row in pairs(c.PendingRows()) do if row.lockIntent then Design(row,1) end end
 for _,row in pairs(c.PendingLockRows()) do Design(row,tonumber(row.stacks) or 1) end
 local fulfilled=c.FulfilledDraftTargets()
 for id,value in pairs(fulfilled) do
  for _,spell in ipairs(model.TargetReplacements(value,id) or {}) do replaced[spell]=true end
 end
 local held=(model.LockedProjection(A.LockedOwned()) or {}).bySpell or {}
 for id,value in pairs(fulfilled) do
  local n=model.TargetCopies(value,id)
  if n and not designed[id] and not replaced[id] and (tonumber(held[id]) or 0)>=n then copies=copies+n end
 end
 return copies
end
-- Held locked copies and the occupied records holding them.
local function Held()
 local projection=model.LockedProjection(A.LockedOwned()) or {}
 local copies=0
 for _,n in pairs(projection.bySpell or {}) do copies=copies+n end
 return copies,projection.occupied
end
-- Byte-identity witnesses: the draft with its bindings, and everything a save
-- writes (remembered roles, design buckets, assignments, assignment tokens).
local function DraftDump()
 return B.Dump({pending=c.PendingRows(),lock=c.PendingLockRows(),fulfilled=c.FulfilledDraftTargets(),
  candidate=c.CandidateContext(),editing=c.EditingContext(),create=c.CreateTargetContext(),retry=c.PendingApply()})
end
local function Saved()
 return B.Dump({roles=backing.wishlistRoleChoices,buckets=backing.lockDesignTargetsBySlot,
  first=backing.firstRunWishlist,loadouts=backing.loadoutWishlists,tokens=A.AssignmentActionSnapshot()})
end
local function Said(from)
 local said={}
 for i=from+1,#notices do said[#said+1]=notices[i] end
 return table.concat(said,' | ')
end
-- A refusal that names the plan's authored design limit (six locked target
-- copies), not the live slots.
local function NamesDesignLimit(text)
 text=B.Plain(tostring(text or '')):lower()
 return text:find('locked target cop',1,true)~=nil and (text:find('6',1,true)~=nil or text:find('six',1,true)~=nil)
  and text:find(SLOTS_NOTICE:lower(),1,true)==nil
end
local function Uploads() return B.Count(H,'upload') end
local function LastUpload()
 for i=#H.actions,1,-1 do if H.actions[i][1]=='upload' then return H.actions[i] end end
end
-- Copies by spell of the design the last save assigned (the first-run plan's
-- durable record; the harness has no active Saved Build) and their total.
local function AssignedDesign()
 local first=backing.firstRunWishlist
 local bySpell,total={},0
 for _,row in ipairs(type(first)=='table' and type(first.designRows)=='table' and first.designRows or {}) do
  local n=tonumber(row.stacks) or 0
  bySpell[row.spellId]=(bySpell[row.spellId] or 0)+n;total=total+n
 end
 return bySpell,total
end
-- Whether a remembered role choice holds exactly these locked copies by spell.
local function RolesHold(expected)
 for _,record in ipairs(type(backing.wishlistRoleChoices)=='table' and backing.wishlistRoleChoices or {}) do
  local got={}
  for _,e in ipairs(type(record)=='table' and type(record.echoes)=='table' and record.echoes or {}) do
   if e.locked==true then got[e.spellId]=(got[e.spellId] or 0)+(tonumber(e.stacks) or 0) end
  end
  if B.Dump(got)==B.Dump(expected) then return true end
 end
 return false
end
-- The editor's Save: PrepareApply, then the confirmation's AcceptApply.
local function Save(name)
 local data,code=c.PrepareApply(name)
 local ok,why
 if data then ok,why=c.AcceptApply(data) end
 return data,code,ok,why
end

C.scenario('CPY7 Copy of a record whose five locked records hold seven copies',function()
 capacity=6
 Show('CPY7',{R(200080,1),R(200081,1),R(200082,1),R(200083,3),R(200084,1)})
 local current=CE.Validate((Candidate('seven',RECORD_SEVEN)))
 local rows,copies=0,0
 for _,row in ipairs(current and current.lockedEchoes or {}) do rows=rows+1;copies=copies+row.stacks end
 print('OBSERVED','CPY7 record ordinary='..#(current and current.ordinaryEchoes or {}),'locked records='..rows,
  'copies='..copies)
 C.guard(current~=nil and #current.ordinaryEchoes==79 and rows==5 and copies==7,
  'CPY7: the record evidence stays valid (79 ordinary copies; five locked records holding seven)')
 if not current then return end
 C.setup(Draft({{200060,2},{200061,1}}) and PlanDesign()==3,'CPY7: a seeded draft designing three target copies')
 local draft,saved,actions,from=DraftDump(),Saved(),#H.actions,#notices
 local name,why=c.BeginCandidate(current)
 local said=Said(from)
 print('OBSERVED','CPY7 opened='..printable(name),'reason='..printable(why),'draft design copies='..PlanDesign(),
  'notices='..said)
 C.expect(name==nil and NamesDesignLimit(why) and said:find('Copy unavailable',1,true)~=nil and NamesDesignLimit(said),
  'CPY7: the Copy is refused, naming the plan design limit of six locked target copies',
  printable(name)..' | '..printable(why))
 C.expect(DraftDump()==draft and c.CandidateContext()==nil,'CPY7: the seeded draft is kept exactly; no Copy binding is installed')
 C.guard(#H.actions==actions and Saved()==saved,'CPY7: opening the Copy uploads, saves and assigns nothing',
  #H.actions-actions)
end)

C.scenario('CPY7S the same Copy with nothing held, then Save',function()
 capacity=6
 Show('CPY7S',{})
 c.BeginNewWishlist()
 local current=CE.Validate((Candidate('seven-s',RECORD_SEVEN)))
 local saved,actions,uploads,from=Saved(),#H.actions,Uploads(),#notices
 local name=c.BeginCandidate(current)
 r.Refresh()
 print('OBSERVED','CPY7S opened='..printable(name),'draft design copies='..PlanDesign(),
  'footer='..((Region('Rolled copies:') or ''):gsub('\n',' | ')))
 H.now=H.now+4
 local data,code,ok,why=Save(name or 'Synthetic copy seven')
 local said=Said(from)
 print('OBSERVED','CPY7S prepared='..printable(data~=nil)..'/'..printable(code),'saved='..printable(ok),
  'why='..printable(why),'uploads='..(Uploads()-uploads),'notices='..said)
 C.expect(#H.actions==actions and not c.IsApplyPending() and said:find('Wishlist uploaded',1,true)==nil,
  'CPY7S: the over-six Copy and its Save upload nothing and keep no retry',Uploads()-uploads)
 C.guard(Saved()==saved,'CPY7S: no role choice, design or assignment is written')
end)

C.scenario('CPY6 a Copy of five records holding six copies',function()
 capacity=6
 Show('CPY6',{})
 local from=#notices
 local name=c.BeginCandidate(CE.Validate((Candidate('six',RECORD_SIX))))
 local design=PlanDesign()
 print('OBSERVED','CPY6 opened='..printable(name),'draft design copies='..design)
 C.guard(name~=nil and c.CandidateContext()~=nil and design==6,'CPY6: the Copy opens with all six design copies',design)
 H.now=H.now+4
 local uploads=Uploads()
 local data,code,ok,why=Save(name)
 local upload=Uploads()==uploads+1 and LastUpload() or nil
 local rows,copies,locked=0,0,0
 for _,e in ipairs(upload and upload[4] or {}) do
  rows=rows+1;copies=copies+e.stacks
  if e.spellId>=200080 then locked=locked+1 end
 end
 local assigned,total=AssignedDesign()
 print('OBSERVED','CPY6 prepared='..printable(data~=nil)..'/'..printable(code),'saved='..printable(ok),
  'why='..printable(why),'uploaded rows='..rows,'copies='..copies,'assigned design copies='..total,'notices='..Said(from))
 C.guard(ok==true and upload~=nil and rows==79 and copies==79 and locked==0,
  'CPY6: the save uploads exactly the 79 ordinary copies and no locked row',printable(why))
 C.guard(B.Dump(assigned)==B.Dump(Spells(RECORD_SIX)) and RolesHold(Spells(RECORD_SIX)),
  'CPY6: the saved plan and its remembered roles hold all six design copies',total)
end)

C.scenario('CPY6M a Copy of one record holding six copies of one Echo',function()
 capacity=6
 Show('CPY6M',{})
 local maxStack=(A.Catalog().rows[200080] or {}).maxStack
 C.setup((tonumber(maxStack) or 0)<6,'CPY6M: the catalog maxStack of that Echo is below six',maxStack)
 local name=c.BeginCandidate(CE.Validate((Candidate('six-one',{6}))))
 local design=PlanDesign()
 print('OBSERVED','CPY6M opened='..printable(name),'draft design copies='..design,'catalog maxStack='..printable(maxStack))
 C.guard(name~=nil and design==6,'CPY6M: a record holding six copies of one Echo opens as six design copies',design)
 H.now=H.now+4
 local data,code,ok,why=Save(name)
 local assigned,total=AssignedDesign()
 print('OBSERVED','CPY6M prepared='..printable(data~=nil)..'/'..printable(code),'saved='..printable(ok),
  'why='..printable(why),'assigned design copies='..total)
 C.guard(ok==true and B.Dump(assigned)==B.Dump({[200080]=6}),
  'CPY6M: Save is not refused by a maxStack bound and keeps the six copies',printable(code)..' '..total)
end)

C.scenario('CPYA unknown or stale Copy authority',function()
 capacity=6
 Show('CPYA',{})
 C.setup(Draft({{200060,2},{200061,1}}),'CPYA: a seeded draft')
 local draft=DraftDump()
 local unknown=CE.Validate((Candidate('six-unknown',RECORD_SIX)))
 local unbound={evidenceKind=CE.CurrentKind(),title='Synthetic unbound',
  ordinaryEchoes=unknown.ordinaryEchoes,lockedEchoes=unknown.lockedEchoes}
 unknown.evidenceKind='synthetic-unknown-contract'
 local a,whyA=c.BeginCandidate(unknown)
 local b,whyB=c.BeginCandidate(unbound)
 local stale,change=Candidate('six-stale',RECORD_SIX)
 local current=CE.Validate(stale)
 change('synthetic-evidence-changed')
 local s,whyS=c.BeginCandidate(current)
 print('OBSERVED','CPYA unknown='..printable(whyA),'unbound='..printable(whyB),'stale='..printable(whyS))
 C.guard(a==nil and b==nil and DraftDump()==draft,
  'CPYA: a Copy of an unknown contract or with no bound validator is refused; the draft is unchanged')
 C.guard(s==nil and DraftDump()==draft,'CPYA: a Copy whose record evidence changed is refused; the draft is unchanged',whyS)
 local live,changeLive=Candidate('six-live',RECORD_SIX)
 local name=c.BeginCandidate(CE.Validate(live))
 C.setup(name~=nil,'CPYA: a current six-copy Copy opens')
 changeLive('synthetic-evidence-changed')
 H.now=H.now+4
 local uploads=Uploads()
 local data,code=Save(name)
 C.guard(data==nil and code=='stale_candidate' and Uploads()==uploads,
  'CPYA: Save of a Copy whose record changed after opening is refused before upload',printable(code))
end)

-- An existing editor state whose own design is seven copies, through the
-- controller's own loader (the one BeginWishlist and SeedPendingFromWishlist
-- use), not a Copy: untyped rows whose lock marks make the two held spells
-- kept fulfilled targets and three others lock intents, and the plan's stored
-- design of two queued copies of 200064. Held: 200080 and 200081.
local STORED_TWO={[200064]={version=1,copies=2,rows={{spellId=200064,quality=0,stacks=2}}}}
local function OverSix()
 c.BeginNewWishlist()
 local rows={}
 for i=1,10 do rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1} end
 for _,id in ipairs({200080,200081,200060,200061,200062}) do
  rows[#rows+1]={spellId=id,quality=(id-200000)%4,stacks=1,locked=true}
 end
 return c.LoadPendingEchoes(rows,nil,H.Clone(STORED_TWO))==true and PlanDesign()==7
end

C.scenario('SAV7 an existing editor state whose own design is seven copies',function()
 capacity=6
 Show('SAV7',Singles(200080,2))
 local loaded=OverSix()
 if not C.setup(loaded,'SAV7: the plan designs 2 kept fulfilled + 3 intent + 2 queued = 7 target copies',
  PlanDesign()) then return end
 local draft,saved,uploads,from=DraftDump(),Saved(),Uploads(),#notices
 H.now=H.now+4
 local data,code,ok,why=Save('Synthetic over-six plan')
 local said=Said(from)
 print('OBSERVED','SAV7 Save prepared='..printable(data~=nil)..'/'..printable(code),'saved='..printable(ok),
  'why='..printable(why),'uploads='..(Uploads()-uploads),'assigned design copies='..select(2,AssignedDesign()),
  'notices='..said)
 C.expect(data==nil and Uploads()==uploads and NamesDesignLimit(said),
  'SAV7: Save refuses the seven-copy design before any upload, naming the design limit',Uploads()-uploads)
 C.expect(DraftDump()==draft and Saved()==saved,'SAV7: the draft is kept; nothing is saved or assigned')
 -- The direct controller payload (no confirmation token).
 if not C.setup(OverSix(),'SAV7 A: the same plan loaded again') then return end
 draft,saved,uploads,from=DraftDump(),Saved(),Uploads(),#notices
 H.now=H.now+4
 ok,why=c.AcceptApply(0,'Synthetic over-six plan',c.CanonicalEchoes())
 said=Said(from)
 print('OBSERVED','SAV7 A saved='..printable(ok),'why='..printable(why),'uploads='..(Uploads()-uploads),'notices='..said)
 C.expect(ok~=true and Uploads()==uploads and DraftDump()==draft and Saved()==saved and NamesDesignLimit(said),
  'SAV7 A: the direct AcceptApply payload uploads, saves and assigns nothing, naming the design limit',Uploads()-uploads)
 -- An upload still spaced: the save would be kept for a retry.
 if not C.setup(OverSix(),'SAV7 R: the same plan loaded again') then return end
 H.now=H.now+4
 C.setup(A.UploadWishlist(0,'Synthetic spacing',{{spellId=200011,quality=3,stacks=1}})==true,
  'SAV7 R: a fake upload just now keeps the next upload spaced')
 saved,uploads=Saved(),Uploads()
 ok,why=c.AcceptApply(0,'Synthetic over-six plan',c.CanonicalEchoes())
 local pending=c.IsApplyPending()
 H.now=H.now+4
 local pumped,pumpWhy=c.PumpApplyRetry()
 print('OBSERVED','SAV7 R accepted='..printable(ok),'why='..printable(why),'retry kept='..printable(pending),
  'pump='..printable(pumped)..'/'..printable(pumpWhy),'uploads='..(Uploads()-uploads))
 C.expect(not pending and Uploads()==uploads and Saved()==saved,
  'SAV7 R: no retry is kept for the seven-copy design and nothing is uploaded later',Uploads()-uploads)
end)

C.scenario('SAVX a draft replacing a fulfilled target saves six design copies',function()
 capacity=6
 Show('SAVX',Singles(200080,6))
 C.setup(Draft(SIX_HELD) and Fulfilled()==6,'SAVX: a draft whose six targets are all held (fulfilled)')
 local outcome=Assign(200050,200080)
 C.setup(outcome=='queued' and PlanDesign()==6,'SAVX: 200050 replaces the fulfilled 200080; the design stays six copies',
  printable(outcome))
 H.now=H.now+4
 local uploads,from=Uploads(),#notices
 local data,code,ok,why=Save('Synthetic replacement plan')
 local assigned,total=AssignedDesign()
 print('OBSERVED','SAVX prepared='..printable(data~=nil)..'/'..printable(code),'saved='..printable(ok),
  'why='..printable(why),'uploads='..(Uploads()-uploads),'assigned design copies='..total,
  'replaced target assigned='..printable(assigned[200080]),'notices='..Said(from))
 C.guard(ok==true and Uploads()==uploads+1
  and B.Dump(assigned)==B.Dump({[200050]=1,[200081]=1,[200082]=1,[200083]=1,[200084]=1,[200085]=1}),
  'SAVX: the plan saves its six design copies; the replaced fulfilled target is not counted',printable(code)..' '..total)
end)

C.scenario('SAVU six target copies beside seven unrelated held copies',function()
 capacity=6
 Show('SAVU0',{})
 C.setup(Draft({{200060,1},{200061,1},{200062,1},{200063,1},{200064,1},{200065,1}}) and PlanDesign()==6,
  'SAVU: a draft whose plan targets six copies in six spells')
 Show('SAVU',{R(200085,1),R(200086,1),R(200087,1),R(200088,3),R(200089,1)})
 local paired=0
 for _,row in pairs(c.PendingLockRows()) do if row.replaces~=nil then paired=paired+1 end end
 local held,records=Held()
 C.setup(paired==0 and held==7 and records==5 and PlanDesign()==6,
  'SAVU: seven unrelated copies are held in five records; no target replaces one',held..'/'..printable(records))
 H.now=H.now+4
 C.setup(A.UploadWishlist(0,'Synthetic spacing',{{spellId=200011,quality=3,stacks=1}})==true,
  'SAVU: a fake upload just now keeps the next upload spaced')
 local uploads,from=Uploads(),#notices
 local data,code,ok,why=Save('Synthetic six beside seven held')
 local pending=c.IsApplyPending()
 H.now=H.now+4
 local pumped=c.PumpApplyRetry()
 local assigned,total=AssignedDesign()
 print('OBSERVED','SAVU prepared='..printable(data~=nil)..'/'..printable(code),'first try='..printable(ok)..'/'..printable(why),
  'retry kept='..printable(pending),'retried='..printable(pumped),'uploads='..(Uploads()-uploads),
  'assigned design copies='..total,'notices='..Said(from))
 C.guard(data~=nil,'SAVU: seven unrelated held copies and the occupied slots do not refuse a six-copy design',printable(code))
 C.guard(why=='spacing' and pending and pumped==true and Uploads()==uploads+1
  and B.Dump(assigned)==B.Dump({[200060]=1,[200061]=1,[200062]=1,[200063]=1,[200064]=1,[200065]=1}),
  'SAVU: the spaced save is kept, retried once and saves the six design copies',printable(why)..' '..total)
end)

C.finish('(occupied records and the live capacity drive the locked display; a new partition is a change)')
