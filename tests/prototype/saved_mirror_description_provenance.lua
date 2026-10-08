-- SPEC-R2-1 control: the provenance of a Saved Build mirror's generated
-- description, the optional catalog V1 field generatedDescriptionWitness.
-- With each description it generates, the Saved import (CommunityController
-- SavedMirrorDescription) records a witness of that exact text and of the
-- owner title (userTitle) the mirror carries. A title-only owner edit
-- (EditBuild) records it again when the description is known to be generated;
-- a description edit clears it. A re-import rewrites a marked mirror's
-- description only while its witness still matches; any other marked mirror
-- keeps its text, as before. Another build keeps the field as unknown data
-- and never updates it.
-- EXPECT (needs the field, so it does not hold at 067d6ab): every newly
-- imported mirror carries a witness; a title-only edit leaves one and Save
-- Link leaves it as it was; the reload keeps it; after those edits and the
-- reload a signature-changing re-import describes the current progress, keeps
-- a witness, and the detail pane shows it; the witnesses another build left
-- unchanged are still read after the reload; through the catalog Put/Get a
-- string witness reads back exactly, while a non-string or a witness over
-- 2048 bytes makes the record malformed.
-- Unchanged (GUARD, holds at 067d6ab): the edits change none of the import
-- signature, owner, verification and bindings; a description the
-- owner wrote (mirror 2) leaves no witness, also after a later title-only
-- edit, and is kept; an older build's description edit is kept although the
-- witness it left is stale, on a mirror whose title the owner had changed here
-- (mirror 3) and on an unmarked one (mirror 4); a mirror an earlier build
-- marked without a witness (mirror 5) gains none through a title-only edit
-- and keeps its text; titles, link, identity, server slot, assigned Wishlist
-- and verified owner are kept; summaries carry no witness; a record without
-- the field reads back without it, an unknown field beside it is kept, and a
-- witness changes no owner, verification or Sync answer; no game action; the
-- Saved Build assignments are unchanged.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, adapter, Saved import, Build Library window (detail pane,
-- link field, Save Link, Edit Build dialog) and catalog Put/Get/GetSummary;
-- the format-5 saved fixture (Saved Build 1's "Gen plan") with artificial
-- assignments of Saved Builds 2-5 in the same record shape. The older build
-- and the earlier build are simulated by changing saved bundle rows between
-- two sessions (an offline module reload with round-tripped literal data, not
-- a client reload); the older build leaves the field as it found it. Only the
-- fake server Saved Builds change. Artificial names, notes and link; nothing
-- is sent.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_description_provenance')
local FIELD='generatedDescriptionWitness'

-- An Echo row of harness Echo `id`, with the quality the harness catalog gives it.
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end
-- Server Saved Build 1 measured against its assigned Wishlist "Gen plan"
-- (F.PLAN: 200001 x2, 200002 x3, 200003 x1): 2+second of the 6 copies, or all
-- 6 with the third Echo.
local function Slot1(second,third)
 local rows={E(200001,2),E(200002,second)}
 if third then rows[3]=E(200003,1) end
 return rows
end
-- The Wishlists assigned to Saved Builds 2-5, stored in the record shape the
-- fixture gives "Gen plan" (F.Row): slot, content key, name and Echo rows.
local PLAN={
 [2]={name='Side plan',echoes={E(200004,2),E(200005,2)}},
 [3]={name='Third plan',echoes={E(200006,2),E(200007,1)}},
 [4]={name='Fourth plan',echoes={E(200008,2),E(200009,2)}},
 [5]={name='Fifth plan',echoes={E(200012,1),E(200013,2)}},
}
local function PlanName(slot) return slot==1 and 'Gen plan' or PLAN[slot].name end
local function AddPlans(db)
 local links=db.chars[F.NAME].loadoutWishlists
 for slot,plan in pairs(PLAN) do
  local echoes={}
  for i,e in ipairs(plan.echoes) do echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=false} end
  links[slot]={slot=slot,key=F.Key(echoes),name=plan.name,echoes=echoes}
 end
end
-- The server Saved Builds in both sessions and after scenario S, and the
-- progress each gives against its assigned Wishlist (copies held, planned).
local NAME={'Artificial Saved Build','Artificial Second Build','Artificial Third Build',
 'Artificial Fourth Build','Artificial Fifth Build'}
local FIRST={Slot1(1),{E(200004,1),E(200005,1)},{E(200006,1)},{E(200008,1)},{E(200012,1)}}
local LATER={Slot1(3,true),{E(200004,2),E(200005,1)},{E(200006,2)},{E(200008,2),E(200009,1)},{E(200012,1),E(200013,1)}}
local AT_FIRST={{3,6},{2,4},{1,3},{1,4},{1,3}}
local AT_LATER={{6,6},{3,4},{2,3},{3,4},{2,3}}
local function Server(h)
 local slots={}
 for slot=1,5 do slots[slot]={name=NAME[slot],verified=true,echoes=h.Clone(FIRST[slot])} end
 h.perks.serverBuildSlots=slots
 h.perks.serverActiveSlot=1
end
local LINK='https://discord.com/channels/7/8/9'
local TITLE1='Artificial owner title one'
local TITLE2,TITLE2B='Artificial owner title two','Artificial owner title two again'
local NOTE2='Artificial owner note on the second Saved Build.'
local TITLE3='Artificial owner title three'
local OLDER3='Artificial note an older build saved on the third Saved Build.'
local OLDER4='Artificial note an older build saved on the fourth Saved Build.'
local TITLE5='Artificial owner title five'

local H=F.Boot(F.Database({mutate=AddPlans}),Server)
local A,CB,CAT=Nexus.GameAdapter,Nexus.CommunityBuilds,Nexus.BuildCatalog

local function Until(limit,fn)
 for i=1,limit do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return nil
end

-- The Build Library's Saved import counters (through the facade's VirtualStats).
local function Import()
 local stats=CB.VirtualStats()
 return type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
end
local function ImportIdle() return Import().pending~=true end

-- The mirror of server Saved Build `slot`, as the real Build Library reads it.
local function Mirror(slot)
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==slot then found=b end
 end
 return found
end
local function AllMirrors()
 for slot=1,5 do if not Mirror(slot) then return false end end
 return true
end
-- The witness the real Build Library reads on mirror `slot`.
local function Witness(slot) return (Mirror(slot) or {})[FIELD] end

-- The stored row of build `id` (the saved record).
local function StoredRow(id)
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and id~=nil and builds[id] or nil
 return type(row)=='table' and row or nil
end

-- Does the text state progress progress/total ("p/t" or "p of t")?
local function StatesProgress(text,progress,total)
 local l=V.Plain(text)
 return l:find(string.format('%d/%d',progress,total),1,true)~=nil
  or l:find(string.format('%d of %d',progress,total),1,true)~=nil
end
-- Does the text name Wishlist `name` and the progress progress/total?
local function SaysAssigned(text,name,progress,total)
 return V.Names(text,name) and StatesProgress(text,progress,total)
end

-- The Saved Build Wishlist assignments: each stored record's name and content
-- key, and the Wishlist the adapter resolves for that Saved Build.
local function Assignments()
 local state=Nexus.Store.State() or {}
 local links=type(state.loadoutWishlists)=='table' and state.loadoutWishlists or {}
 local out={}
 for slot=1,5 do
  local stored=type(links[slot])=='table' and links[slot] or {}
  local linked=A.GetLoadoutWishlist(slot) or {}
  out[#out+1]=table.concat({slot,printable(stored.name),printable(stored.key),printable(linked.name)},'/')
 end
 return table.concat(out,' ')
end

-- The server Saved Builds change; opening the Build Library again imports
-- them again (as in saved_mirror_link_only_description).
local function ServerChange(change)
 change(H.perks.serverBuildSlots)
 H.Notify();A.Poll()
 CB.Hide();CB.Show()
end

local function Panel()
 local f=NexusCommunityBuildsFrame
 return f and f._detailPanel
end
-- Select build `id` in the Build Library and wait for its detail pane.
local function ShowBuild(id)
 CB.ShowBuild(id)
 Until(2000,function()
  local p=Panel()
  return p and p:IsShown() and p._nexusShownId==id and ImportIdle()
 end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end

-- The owner types into a field: it gets focus and the text arrives as input.
local function Type(box,text)
 box:SetFocus();box:SetText('');box:Insert(text)
 return box:_NexusRawText()
end

-- Open the real Edit dialog of build `id` with its detail pane's Edit Build.
local function OpenEdit(tag,id)
 local panel=ShowBuild(id)
 C.setup(panel~=nil and panel.editBtn:IsShown() and panel.editBtn:IsEnabled(),
  tag..': fixture: the detail pane offers Edit Build for the own mirror')
 if not panel then return nil end
 panel.editBtn:Click()
 local popup=NexusEditPopup
 local open=popup~=nil and popup:IsShown() and popup._editingId==id
 C.setup(open,tag..': fixture: the Edit dialog opens for that mirror')
 return open and popup or nil
end
-- Save Details, then wait until the Build Library serves what `saved` accepts.
local function SaveDetails(tag,popup,slot,saved)
 popup._saveBtn:Click()
 C.setup(Until(2000,function()
  local m=Mirror(slot)
  return m~=nil and saved(m) and ImportIdle()
 end)~=nil,tag..': fixture: Save Details saved the text and the Build Library serves it')
end
-- A title-only edit in the real Edit dialog: the description stays as served.
local function EditTitle(tag,slot,id,title)
 local before=Mirror(slot) or {}
 local popup=OpenEdit(tag,id)
 if not popup then return nil end
 C.setup(popup._editDescBox:_NexusRawText()==before.description,
  tag..': fixture: the dialog holds the served description',popup._editDescBox:_NexusRawText())
 C.setup(Type(popup._editTitleBox,title)==title,tag..': fixture: the owner typed a new title')
 SaveDetails(tag,popup,slot,function(m) return m.title==title end)
 local m=Mirror(slot) or {}
 print('OBSERVED',tag..' after Save Details title='..printable(m.title),'userTitle='..printable(m.userTitle),
  'witness='..printable(m[FIELD]))
 C.guard(m.description==before.description,tag..': the description is unchanged',m.description)
 return m,before
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
for slot=1,5 do
 local linked=A.GetLoadoutWishlist(slot)
 C.setup(type(linked)=='table' and linked.name==PlanName(slot),
  'fixture: Saved Build '..slot..' has the assigned Wishlist "'..PlanName(slot)..'"',linked and linked.name)
end
local ASSIGNED=Assignments()

local ids={}
C.scenario('P the first session imports the five Saved Builds',function()
 CB.Show()
 C.setup(Until(2000,function() return AllMirrors() and ImportIdle() end)~=nil,
  'P: fixture: the five Saved Builds are imported through the real Build Library facade')
 local missing={}
 for slot=1,5 do
  local m=Mirror(slot) or {}
  ids[slot]=m.id
  C.setup(m.userTitle==nil and SaysAssigned(m.description,PlanName(slot),AT_FIRST[slot][1],AT_FIRST[slot][2]),
   'P: fixture: mirror '..slot..' has the generated description of "'..PlanName(slot)..'" at '
   ..AT_FIRST[slot][1]..'/'..AT_FIRST[slot][2]..' and no owner edit',m.description)
  if type(m[FIELD])~='string' then missing[#missing+1]=slot end
 end
 print('OBSERVED','P mirror 1 witness='..printable(Witness(1)))
 C.expect(#missing==0,'P: every newly imported mirror carries a generated-description witness',
  'without: '..table.concat(missing,','))
end)

C.scenario('T1 mirror 1: a title-only edit, then Save Link',function()
 local m,before=EditTitle('T1',1,ids[1],TITLE1)
 if not m then return end
 C.expect(type(m[FIELD])=='string','T1: after the title-only edit the mirror still carries a witness',m[FIELD])
 C.guard(m.userTitle==TITLE1,"T1: the title is the owner's",m.userTitle)
 C.guard(m._savedSignature==before._savedSignature,'T1: the edit does not change the import signature',m._savedSignature)
 C.guard(m.ownerKey==before.ownerKey and m.ownerVerified==before.ownerVerified and m.isMine==before.isMine
  and m.recordBuildId==before.recordBuildId and m.publishedBuildId==before.publishedBuildId,
  'T1: nor the owner, verification or record and publication bindings')
 local panel=ShowBuild(ids[1])
 C.setup(panel~=nil,'T1: fixture: the detail pane shows mirror 1')
 if not panel then return end
 local box=panel.linkBox
 C.setup(box~=nil and box:IsShown() and box._nexusBoundBuildId==ids[1] and panel.linkSaveBtn:IsShown()
  and panel.linkSaveBtn:IsEnabled(),'T1: fixture: the owner-only link field and Save Link are offered for the own mirror')
 if not box then return end
 C.setup(Type(box,LINK)==LINK,'T1: fixture: the owner typed a link into the field')
 panel.linkSaveBtn:Click()
 C.setup(Until(2000,function()
  local x=Mirror(1)
  return x~=nil and x.link==LINK and ImportIdle()
 end)~=nil,'T1: fixture: Save Link saved the link and the Build Library serves it',(Mirror(1) or {}).link)
 local after=Mirror(1) or {}
 C.expect(m[FIELD]~=nil and after[FIELD]==m[FIELD],'T1: Save Link leaves the witness as it was',after[FIELD])
 C.guard(after.title==TITLE1 and after.userTitle==m.userTitle and after.description==m.description,
  'T1: and the title, the owner-edit marker and the description',printable(after.title)..' / '..printable(after.description))
end)

C.scenario('T2 mirror 2: a title-only edit, a description edit, another title-only edit',function()
 local m=EditTitle('T2a',2,ids[2],TITLE2)
 if not m then return end
 C.expect(type(m[FIELD])=='string','T2a: after the title-only edit mirror 2 carries a witness',m[FIELD])
 local popup=OpenEdit('T2b',ids[2])
 if not popup then return end
 C.setup(Type(popup._editDescBox,NOTE2)==NOTE2,'T2b: fixture: the owner typed a description')
 SaveDetails('T2b',popup,2,function(x) return x.description==NOTE2 end)
 C.guard(Witness(2)==nil,'T2b: a description the owner wrote leaves no witness',Witness(2))
 m=EditTitle('T2c',2,ids[2],TITLE2B)
 if not m then return end
 C.guard(m.description==NOTE2 and m[FIELD]==nil,
  "T2c: a later title-only edit keeps the owner's description and records no witness",m[FIELD])
end)

C.scenario('T3 mirror 3: a title-only edit',function()
 local m=EditTitle('T3',3,ids[3],TITLE3)
 if not m then return end
 C.expect(type(m[FIELD])=='string','T3: after the title-only edit mirror 3 carries a witness',m[FIELD])
end)

local beforeReload,planted={},{}
C.scenario('W an older build and an earlier build wrote mirrors 3-5 before the second session',function()
 C.guard(#H.actions==0,'W: no game action in the first session',#H.actions)
 for slot=1,5 do beforeReload[slot]=Mirror(slot) end
 local three,four,five=StoredRow(ids[3]),StoredRow(ids[4]),StoredRow(ids[5])
 C.setup(three~=nil and four~=nil and five~=nil,'W: fixture: the saved rows of mirrors 3-5 exist')
 if not (three and four and five) then return end
 -- An older build's Edit Build (the field is unknown to it; it keeps it as
 -- it found it) saved an owner description on mirror 3, whose title the
 -- owner had already changed, and on the unmarked mirror 4, which its edit
 -- marked with the title it had.
 three.description,three.userDescription=OLDER3,OLDER3
 four.userTitle,four.description,four.userDescription=four.title,OLDER4,OLDER4
 -- An earlier build wrote no witness; its Save Link marked mirror 5 over the
 -- generated text.
 five[FIELD]=nil
 five.userTitle,five.userDescription=five.title,five.description
 for slot=3,5 do
  local row=StoredRow(ids[slot])
  planted[slot]={userTitle=row.userTitle,title=row.title,description=row.description,witness=row[FIELD]}
  print('OBSERVED','W row '..slot..' userTitle='..printable(row.userTitle),'description='..printable(row.description),
   'witness='..printable(row[FIELD]))
 end
end)

C.scenario('R the second session reads the saved data back',function()
 C.setup(planted[3]~=nil and planted[4]~=nil and planted[5]~=nil,'R: fixture: the other builds\' rows were written')
 H=F.Reload(Server)
 A,CB,CAT=Nexus.GameAdapter,Nexus.CommunityBuilds,Nexus.BuildCatalog
 C.setup(Nexus.StartupStatus().coreReady==true,'R: fixture: the second session reached core-ready')
 C.setup(Assignments()==ASSIGNED,'R: fixture: the Saved Build assignments read back unchanged',Assignments())
 -- Read through the catalog before any Saved import of this session runs.
 local one,was=CAT.Get(ids[1]),beforeReload[1] or {}
 C.setup(one~=nil,'R: fixture: the catalog serves mirror 1 after the reload')
 one=one or {}
 print('OBSERVED','R mirror 1 witness='..printable(one[FIELD]))
 C.expect(was[FIELD]~=nil and one[FIELD]==was[FIELD],'R: mirror 1 keeps its witness through the reload',one[FIELD])
 C.guard(one.title==TITLE1 and one.userTitle==was.userTitle and one.description==was.description and one.link==LINK,
  'R: and its title, owner-edit marker, description and link',printable(one.title)..' / '..printable(one.description))
 local three,four=CAT.Get(ids[3]) or {},CAT.Get(ids[4]) or {}
 local p3,p4=planted[3] or {},planted[4] or {}
 C.expect(p3.witness~=nil and three[FIELD]==p3.witness and p4.witness~=nil and four[FIELD]==p4.witness,
  'R: the witnesses the older build left as it found them are still read on mirrors 3 and 4',
  printable(three[FIELD])..' / '..printable(four[FIELD]))
 CB.Show()
 C.setup(Until(2000,function()
  local s=Import()
  return (tonumber(s.completions) or 0)>0 and s.pending~=true and AllMirrors()
 end)~=nil,'R: fixture: the second session completes a Saved import of the five Saved Builds')
 for slot=1,5 do
  local m=Mirror(slot) or {}
  C.setup(ids[slot]~=nil and m.id==ids[slot],'R: fixture: mirror '..slot..' keeps its identity through the reload',m.id)
 end
 for slot=3,5 do
  local m,p=Mirror(slot) or {},planted[slot] or {}
  C.setup(p.userTitle~=nil and m.userTitle==p.userTitle and m.title==p.title and m.description==p.description,
   'R: fixture: mirror '..slot..' serves the text the other build left',printable(m.userTitle)..' / '..printable(m.description))
 end
 C.setup(Witness(5)==nil,'R: fixture: mirror 5, as the earlier build left it, has no witness',Witness(5))
end)

C.scenario('T5 mirror 5: a title-only edit of the mirror an earlier build marked',function()
 local m=EditTitle('T5',5,ids[5],TITLE5)
 if not m then return end
 C.guard(m[FIELD]==nil,"T5: an earlier build's marker gains no witness: its text is not taken to be generated",m[FIELD])
end)

C.scenario('S a signature-changing re-import of the five Saved Builds',function()
 local bound=Mirror(1) or {}
 ServerChange(function(slots)
  for slot=1,5 do slots[slot].echoes=H.Clone(LATER[slot]) end
 end)
 C.setup(Until(2000,function()
  for slot=1,5 do
   local m=Mirror(slot)
   if not (m and m.destinationProgress==AT_LATER[slot][1]) then return false end
  end
  return ImportIdle()
 end)~=nil,'S: fixture: the re-import stores every mirror\'s new progress')
 local one=Mirror(1) or {}
 print('OBSERVED','S mirror 1 description='..printable(one.description),'title='..printable(one.title),
  'witness='..printable(one[FIELD]))
 C.expect(SaysAssigned(one.description,'Gen plan',6,6) and not StatesProgress(one.description,3,6),
  'S: after its title-only edit, Save Link and the reload, mirror 1 describes "Gen plan" at the current 6/6, not 3/6',
  one.description)
 C.expect(type(one[FIELD])=='string','S: and carries a witness of that description',one[FIELD])
 C.guard(one.title==TITLE1 and one.link==LINK,"S: the owner's title and the saved link are kept",
  printable(one.title)..' / '..printable(one.link))
 C.guard(one.id==ids[1] and one.importedSavedBuild==true and tonumber(one.serverSlot)==1
  and one.destinationWishlistName=='Gen plan','S: the same mirror, server slot and assigned Wishlist',one.id)
 C.guard(CB.IsOwnBuild(ids[1])==true and one.ownerKey==F.OWNER and one.ownerVerified==true and one.isMine==true,
  "S: it stays the character's own verified mirror",printable(one.ownerKey)..'/'..printable(one.ownerVerified))
 C.guard(one.recordBuildId==bound.recordBuildId and one.publishedBuildId==bound.publishedBuildId,
  'S: its record and publication bindings are unchanged',printable(one.recordBuildId)..'/'..printable(one.publishedBuildId))
 local summary=CAT.GetSummary(ids[1]) or {}
 C.guard(summary.id~=nil and summary[FIELD]==nil and summary.syncDelta~=true,
  'S: its summary carries no witness, and it is no Sync record',printable(summary[FIELD]))
 for slot=2,5 do
  local m=Mirror(slot) or {}
  print('OBSERVED','S mirror '..slot..' title='..printable(m.title),'description='..printable(m.description),
   'witness='..printable(m[FIELD]))
 end
 local two,three,four,five=Mirror(2) or {},Mirror(3) or {},Mirror(4) or {},Mirror(5) or {}
 C.guard(two.description==NOTE2 and two.title==TITLE2B,'S: mirror 2 keeps the description and the title its owner wrote',
  two.description)
 C.guard(three.description==OLDER3 and three.title==TITLE3,
  "S: mirror 3 keeps the older build's description: its witness no longer matches",three.description)
 C.guard(four.description==OLDER4 and four.title==(planted[4] or {}).title,
  "S: mirror 4 keeps the older build's description and the title it marked: its witness no longer matches",
  four.description)
 C.guard(five.description==(planted[5] or {}).description and five.title==TITLE5,
  'S: mirror 5 keeps the text the earlier build marked, under the title its owner then wrote',five.description)
 local assigned=true
 for slot=1,5 do assigned=assigned and (Mirror(slot) or {}).destinationWishlistName==PlanName(slot) end
 C.guard(assigned,'S: every mirror keeps its assigned Wishlist')
end)

C.scenario('D the detail pane after the re-import',function()
 local panel=ShowBuild(ids[1])
 C.setup(panel~=nil,'D: fixture: the Build Library detail pane shows mirror 1')
 if not panel then return end
 local shown=V.Plain(panel.desc and panel.desc:GetText() or '')
 local title=V.Plain(panel.title and panel.title:GetText() or '')
 print('OBSERVED','D detail title='..title,'description='..shown)
 C.expect(SaysAssigned(shown,'Gen plan',6,6) and not StatesProgress(shown,3,6),
  'D: the detail pane shows "Gen plan" at the current 6/6',shown)
 C.guard(title==TITLE1,"D: and the owner's title",title)
 local other=ShowBuild(ids[3])
 C.setup(other~=nil,'D: fixture: the detail pane shows mirror 3')
 local text=V.Plain(other and other.desc and other.desc:GetText() or '')
 C.guard(text:find(OLDER3,1,true)~=nil,"D: mirror 3's detail pane shows the older build's description",text)
end)

-- A synthetic record of another player's build (as summary_cursor_named_readers
-- puts them); `extra` adds fields.
local function Record(id,extra)
 local r={id=id,title='Synthetic '..id,author='PeerProvenance-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {}) do r[k]=v end
 return r
end
-- One catalog Put once no other catalog work is open, settled.
local function Put(record)
 Until(2000,function() return CAT.ManualPreparationStatus().ready==true end)
 local ok,why,ticket=CAT.Put(record,{source='sync'})
 if ok==nil and type(ticket)=='table' then
  for _=1,8000 do H.Advance(.05,.05) if ticket.state~='pending' then break end end
  return ticket.committed==true,ticket.reason or why
 end
 return ok,why
end

C.scenario('K the field through the catalog Put, Get and GetSummary',function()
 C.setup(Until(2000,ImportIdle)~=nil,'K: fixture: no Saved import is running')
 CB.Hide()
 C.setup(Until(2000,function() return CAT.ManualPreparationStatus().ready==true end)~=nil,
  'K: fixture: no catalog work is open')
 local GIVEN='Artificial witness text for the catalog roundtrip.'
 local ok,why=Put(Record('provenance-given',{[FIELD]=GIVEN,futureProvenanceNote='artificial unknown field'}))
 C.guard(ok==true,'K: a record with a string witness is accepted',why)
 local given=CAT.Get('provenance-given') or {}
 C.expect(given[FIELD]==GIVEN,'K: and its witness reads back exactly',given[FIELD])
 local stored=StoredRow('provenance-given') or {}
 C.guard(stored[FIELD]==GIVEN and stored.futureProvenanceNote=='artificial unknown field',
  'K: the saved row holds the witness as given and keeps the unknown field beside it',printable(stored[FIELD]))
 ok,why=Put(Record('provenance-none'))
 local none=CAT.Get('provenance-none') or {}
 C.guard(ok==true and none.id~=nil and none[FIELD]==nil and (StoredRow('provenance-none') or {})[FIELD]==nil,
  'K: a record without the field is accepted and reads back without it',why)
 local a,b=CAT.GetSummary('provenance-given') or {},CAT.GetSummary('provenance-none') or {}
 C.guard(a.id~=nil and a[FIELD]==nil,'K: no summary carries the witness',printable(a[FIELD]))
 C.guard(given.ownerKey==none.ownerKey and given.ownerVerified==none.ownerVerified and given.isMine==none.isMine
  and CB.IsOwnBuild('provenance-given')==CB.IsOwnBuild('provenance-none') and a.syncDelta==b.syncDelta,
  'K: the witness changes no owner, verification, ownership or Sync answer',
  printable(given.ownerVerified)..'/'..printable(a.syncDelta))
 ok,why=Put(Record('provenance-number',{[FIELD]=5}))
 C.expect(ok==false and why=='MALFORMED_ROW' and CAT.Get('provenance-number')==nil
  and StoredRow('provenance-number')==nil,
  'K: a witness that is not a string makes the record malformed; nothing is stored',printable(ok)..'/'..printable(why))
 ok,why=Put(Record('provenance-long',{[FIELD]=string.rep('w',2049)}))
 C.expect(ok==false and why=='MALFORMED_ROW' and CAT.Get('provenance-long')==nil,
  'K: a witness over 2048 bytes makes the record malformed',printable(ok)..'/'..printable(why))
 local LONGEST=string.rep('w',2048)
 ok,why=Put(Record('provenance-longest',{[FIELD]=LONGEST}))
 C.guard(ok==true,'K: a witness of 2048 bytes is accepted',why)
 C.expect((CAT.Get('provenance-longest') or {})[FIELD]==LONGEST,'K: and reads back exactly')
end)

C.guard(Assignments()==ASSIGNED,'the Saved Build Wishlist assignments are unchanged',Assignments())
C.guard(#H.actions==0,'no game action in the second session: nothing was activated, saved or uploaded',#H.actions)
C.finish('(a generated description keeps its provenance through title, link and reload edits; owner and older text is kept)')
