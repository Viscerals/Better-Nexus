-- Group 3 (S3-C-05): occupied locked records versus held copies in the
-- durable evidence and catalog envelopes. A locked record keeps its full
-- stack (native SS18, static data), so a real loadout of 79 ordinary copies
-- and five locked records holding 1,1,1,3,1 copies has 7 locked copies and
-- 86 total. Today every envelope sums locked COPIES against six (and 85).
-- EXPECT (fails at 8c): that loadout passes CandidateEvidence's locked pool
-- (rows and copies preserved), LoadoutEvidence.SemanticEnvelope, the actual
-- DPS capture envelope verdict, and actual BuildCatalog.Put admission; the
-- prior two-record (4+3) catalog record is admitted too; and 79 ordinary
-- copies with seven single locked records (a capacity-7 loadout) pass the
-- same four seams.
-- GUARD (holds at 8c): six single locked records pass; 80 ordinary copies
-- are refused; malformed stacks stay refused/malformed; an absurd locked
-- stack (1000) stays refused; a locked pool above the existing 256-entry
-- evidence ceiling stays refused (bounded parsing); refused records are not
-- served; no game or network action.
-- CORRECTED ASSUMPTION (supplement r2): the first version guarded "seven
-- locked records are refused everywhere". That assumed a universal six-record
-- capacity, which the native contract does not have: GetMaximumPermanentEchoes
-- is a dynamic positive server value (perks_service SS18 first field; the
-- journal gate compares #lockedPerks with it, echo_journal.lua 4533-4535) and
-- the six journal discs are display only. These durable envelopes carry no
-- capacity, and their rows are normalized (LoadoutEvidence.Normalize merges
-- rows of one spell/quality/role), so they can neither know the live capacity
-- nor count native records: a six bound here is guessed game policy, not a
-- structural or resource contract. The seven-record checks are therefore
-- EXPECT. The source-grounded bounds that stay GUARDs are the existing ones:
-- 79 ordinary copies, a positive integer stack, the existing 120-copy per-row
-- wire ceiling (SyncProtocol NetworkEcho/DpsEcho, DpsCapture
-- ValidWireEchoList: a 1000-copy row could never be shared) and the existing
-- LoadoutEvidence MAX_ENTRIES 256. The authored design-target limit (six
-- copies) is separate and stays (batch_locked_capacity_trust.lua).
-- The peer wire is covered by batch_locked_wire_records.lua.
-- SETUP: real TOC boot (format-5 profile) for the catalog; the evidence
-- owners are called through their public functions. Synthetic IDs only.
-- Incident limits (standards review r1, STD-R1-09): a refusal held to the
-- locked row ceilings keeps them, as its producers hand them over (DpsCapture
-- the capture verdict's limits; the catalog refusal LoadoutEvidence
-- SemanticLimits). EXPECT (fails at 3bc6d88): I the retained limits keep
-- lockedRows 256 and lockedRowStacks 120 and the report line names them.
-- GUARD (holds at 3bc6d88): ordinary 79 and total 10000 stay retained; an
-- older producer's {79, 6, 85} limits still read "limits 79/6/85".
-- Build Library detail (standards review r2, STD-R2-02). GUARD (holds at
-- 1756f4d; existing behaviour): D the record P7 admitted through the actual
-- catalog (79 ordinary, seven single locked records), opened with
-- CB.ShowBuild as batch_description_unseeded_edit opens a record, reads
-- "LOCKED ECHOES  +1 more locked" with exactly six locked icons drawn; the P6
-- record (six rows) reads "LOCKED ECHOES" with six icons; no game action.
-- SETUP: both records are served and the detail pane opens. No layout change
-- and no envelope or fixture limit is relaxed.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_units_envelopes')
local printable=B.printable
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database())
C.setup(Nexus.StartupStatus().coreReady==true,'start-up reached core-ready')
local CE,LE,D,CAT=Nexus.CandidateEvidence,Nexus.LoadoutEvidence,Nexus.DpsCapture,Nexus.BuildCatalog
C.setup(type(CE.NormalizeLockedEchoes)=='function' and type(LE.SemanticEnvelope)=='function'
 and type(D._CaptureEnvelopeVerdict)=='function','the public envelope owners are loaded')

local function Ordinary(n)
 local t={}
 for i=1,n do t[i]={spellId=200000+i,quality=i%4,stacks=1} end
 return t
end
local function Locked(stacks,first)
 local t={}
 for i,s in ipairs(stacks) do
  local id=(first or 200079)+i
  t[i]={spellId=id,quality=(id-200000)%4,stacks=s}
 end
 return t
end
local FIVE={1,1,1,3,1}
local SIX={1,1,1,1,1,1}
local SEVEN={1,1,1,1,1,1,1}

C.scenario('E CandidateEvidence locked pool',function()
 local rows,why,total=CE.NormalizeLockedEchoes(Locked(FIVE))
 print('OBSERVED','E five records',printable(rows and #rows),printable(total),printable(why))
 C.expect(rows~=nil and #rows==5 and rows[4].stacks==3 and total==7,
  'E5: five locked records holding seven copies pass with every row and copy',why)
 rows=CE.NormalizeLockedEchoes(Locked(SIX))
 C.guard(rows~=nil and #rows==6,'E6: six single records pass')
 rows,why,total=CE.NormalizeLockedEchoes(Locked(SEVEN))
 C.expect(rows~=nil and #rows==7 and total==7,'E7: seven single locked records (a capacity-7 loadout) pass with every row',why)
 rows=CE.NormalizeLockedEchoes({{spellId=200080,stacks=0}})
 C.guard(rows==nil,'E0: a zero stack is refused')
 rows=CE.NormalizeLockedEchoes(Locked({1000}))
 C.guard(rows==nil,'Ex: an absurd locked stack (1000) is refused')
end)

local function Envelope(ordinary,locked)
 local rows={}
 for _,r in ipairs(ordinary) do rows[#rows+1]={spellId=r.spellId,quality=r.quality,stacks=r.stacks,locked=false} end
 for _,r in ipairs(locked) do rows[#rows+1]={spellId=r.spellId,quality=r.quality,stacks=r.stacks,locked=true} end
 return LE.SemanticEnvelope(rows)
end
C.scenario('L LoadoutEvidence semantic envelope',function()
 local v=Envelope(Ordinary(79),Locked(FIVE))
 print('OBSERVED','L 79+five',printable(v.valid),printable(v.reason),printable(v.locked),printable(v.total))
 C.expect(v.valid==true,'L5: 79 ordinary copies and five locked records (7 copies) are a valid loadout',v.reason)
 v=Envelope(Ordinary(79),Locked(SIX))
 C.guard(v.valid==true,'L6: 79 ordinary and six single locked records are valid')
 v=Envelope(Ordinary(79),Locked(SEVEN))
 C.expect(v.valid==true,'L7: 79 ordinary copies and seven single locked records are a valid loadout',v.reason)
 v=Envelope(Ordinary(80),{})
 C.guard(v.valid==false,'L80: 80 ordinary copies are refused',v.reason)
 v=LE.SemanticEnvelope({{spellId=200080,quality=0,stacks=0,locked=true}})
 C.guard(v.valid==false and v.reason=='malformed','L0: a zero stack is malformed',v.reason)
 v=Envelope(Ordinary(79),Locked({1000}))
 C.guard(v.valid==false,'Lx: an absurd locked stack (1000) is refused',v.reason)
end)

local function Capture(ordinaryCount,stacks)
 local ordinary,locked={},{}
 for i=1,ordinaryCount do ordinary[i]={spellId=200000+i,count=1} end
 for i,s in ipairs(stacks) do locked[i]={spellId=200079+i,count=s} end
 return D._CaptureEnvelopeVerdict(ordinary,locked)
end
C.scenario('V actual DPS capture envelope verdict',function()
 local ok,counts,_,why=Capture(79,FIVE)
 print('OBSERVED','V 79+five',printable(ok),printable(counts and counts.locked),printable(why))
 C.expect(ok==true,'V5: a capture of 79 ordinary and five locked records (7 copies) is coherent',why)
 C.guard((Capture(79,SIX))==true,'V6: 79 ordinary and six single locked records are coherent')
 local sevenOk,_,_,sevenWhy=Capture(79,SEVEN)
 C.expect(sevenOk==true,'V7: a capture of 79 ordinary and seven single locked records is coherent',sevenWhy)
 C.guard((Capture(80,{}))==false,'V80: 80 ordinary copies are deferred')
end)

local function Put(id,ordinary,locked)
 local row={id=id,title='Synthetic envelope '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedComplete=true,echoes=ordinary,lockedEchoes=locked}
 local ok,why,ticket=CAT.Put(row,{source='local'})
 if ticket then
  for _=1,4000 do CAT.PumpRootAdmission();H.Advance(.05,.05);if ticket.state~='pending' then break end end
  ok,why=ticket.committed,ticket.reason
 end
 print('OBSERVED','P',id,'committed='..printable(ok),'reason='..printable(why),'served='..printable(CAT.Get(id)~=nil))
 return ok,why
end
C.scenario('P actual BuildCatalog admission',function()
 local actions,sent=#H.actions,#H.sent
 local ok,why=Put('synthetic-env-79-five',Ordinary(79),Locked(FIVE))
 C.expect(ok==true and CAT.Get('synthetic-env-79-five')~=nil,'P5: 79 ordinary and five locked records (7 copies) are admitted and served',why)
 ok,why=Put('synthetic-env-two-records',{},{{spellId=200001,quality=1,stacks=4},{spellId=200002,quality=2,stacks=3}})
 C.expect(ok==true,'P2: two locked records holding 4+3 copies are admitted',why)
 ok,why=Put('synthetic-env-79-six',Ordinary(79),Locked(SIX))
 C.guard(ok==true,'P6: 79 ordinary and six single locked records are admitted',why)
 ok,why=Put('synthetic-env-79-seven',Ordinary(79),Locked(SEVEN))
 C.expect(ok==true and CAT.Get('synthetic-env-79-seven')~=nil,
  'P7: 79 ordinary and seven single locked records are admitted and served',why)
 local many={};for i=1,257 do many[i]=1 end
 ok,why=Put('synthetic-env-257',Ordinary(1),Locked(many))
 C.guard(ok~=true and CAT.Get('synthetic-env-257')==nil,
  'P257: a locked pool above the existing 256-entry evidence ceiling stays refused and unserved',why)
 ok,why=Put('synthetic-env-80',Ordinary(80),{})
 C.guard(ok~=true and CAT.Get('synthetic-env-80')==nil,'P80: 80 ordinary copies are refused',why)
 ok,why=Put('synthetic-env-absurd',Ordinary(10),Locked({1000}))
 C.guard(ok~=true and CAT.Get('synthetic-env-absurd')==nil,'Px: an absurd locked stack (1000) is refused',why)
 C.guard(#H.actions==actions and #H.sent==sent,'P: no game or network action')
end)

C.scenario('I incident limits keep the locked row ceilings',function()
 local support,report=Nexus.SupportIncidents,Nexus.SupportReport
 local function Counted(incident)
  for _,text in ipairs(report.IncidentLines(incident)) do
   if text:find('Counted at refusal',1,true) then return text end
  end
 end
 support.Clear()
 local ok,counts,limits,why=Capture(1,{121})
 C.setup(ok==false and type(limits)=='table','I: the actual capture verdict refuses a 121-copy locked row',why)
 support.Record('capture-deferred',{reason='SEMANTIC_ENVELOPE',producer='DPS record capture',origin='local',
  operation='personal record capture',representation='inline',counts=counts,limits=limits,committed=false})
 local kept=support.Latest() or {}
 local l=kept.limits or {}
 local line=Counted(kept)
 print('OBSERVED','I limits',printable(l.ordinary),printable(l.lockedRows),printable(l.lockedRowStacks),printable(l.total),
  'line='..printable(line))
 C.guard(l.ordinary==79 and l.total==10000,'I: the ordinary and total limits are retained',printable(l.ordinary)..'/'..printable(l.total))
 C.expect(l.lockedRows==256 and l.lockedRowStacks==120,'I: the locked row ceilings the refusal was held to are retained',
  printable(l.lockedRows)..'/'..printable(l.lockedRowStacks))
 C.expect(line~=nil and line:find('locked rows 256',1,true)~=nil and line:find('120 copies in one locked row',1,true)~=nil,
  'I: the report names the locked row ceilings',line)
 support.Record('catalog-refusal',{reason='SEMANTIC_ENVELOPE',producer='saved-build capture',origin='local',
  counts={ordinary=81,locked=6,total=87},limits={ordinary=79,locked=6,total=85},committed=false})
 local old=Counted(support.Latest())
 C.guard(old~=nil and old:find('(limits 79/6/85)',1,true)~=nil,'I: an older producer\'s limits still read 79/6/85',old)
 support.Clear()
end)

C.scenario('D Build Library detail of seven and six locked records',function()
 local CB=Nexus.CommunityBuilds
 local actions=#H.actions
 C.setup(CAT.Get('synthetic-env-79-seven')~=nil and CAT.Get('synthetic-env-79-six')~=nil,
  'D: the catalog serves the P7 (seven locked rows) and P6 (six rows) records')
 local function Panel() local f=NexusCommunityBuildsFrame;return f and f._detailPanel end
 -- The record's detail pane: its locked label, and the locked icons shown.
 local function Detail(id)
  CB.ShowBuild(id)
  B.Until(H,function() local p=Panel();return p and p:IsShown() and p._nexusShownId==id end,2000)
  local p=Panel()
  if not (p and p:IsShown() and p._nexusShownId==id) then return nil end
  local icons=0
  for _,ic in ipairs(p.lockedIcons or {}) do if ic:IsShown() then icons=icons+1 end end
  return {label=B.Plain(p.lockedLabel:GetText() or ''),shown=p.lockedLabel:IsShown(),icons=icons,
   slots=#(p.lockedIcons or {})}
 end
 CB.Show()
 local seven=Detail('synthetic-env-79-seven')
 C.setup(seven~=nil,'D7: the Build Library detail pane opens the seven-row record')
 if seven then
  print('OBSERVED','D7 label='..seven.label,'shown='..printable(seven.shown),'icons='..seven.icons..'/'..seven.slots)
  C.guard(seven.shown and seven.label=='LOCKED ECHOES  +1 more locked',
   'D7: the detail reports the one locked row it does not draw',seven.label)
  C.guard(seven.icons==6 and seven.slots==6,'D7: exactly six locked icons are drawn',seven.icons..'/'..seven.slots)
 end
 local six=Detail('synthetic-env-79-six')
 C.setup(six~=nil,'D6: the detail pane opens the six-row record')
 if six then
  print('OBSERVED','D6 label='..six.label,'shown='..printable(six.shown),'icons='..six.icons..'/'..six.slots)
  C.guard(six.shown and six.label=='LOCKED ECHOES' and six.icons==6,
   'D6: a six-row record reports no further locked row and draws its six icons',six.label)
 end
 C.guard(#H.actions==actions,'D: no game action',#H.actions-actions)
 print('OBSERVED','D fake sends='..#H.sent)
end)

C.finish('(records bound the locked envelope; copies preserved; refusals unchanged)')
