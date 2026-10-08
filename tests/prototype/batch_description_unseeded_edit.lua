-- Group 2 (SPEC-R4-PRE-1): an admitted own description longer than the Edit
-- dialog can seed. The catalog admits up to 4000 bytes; ui/CommunityRenderer
-- seeds the description box through a 2000-byte editor rule, so a 3000-byte
-- stored description seeds as empty, and a title-only Save Details submits
-- that empty field: the stored text is silently deleted.
-- EXPECT (fails at 8c): after a title-only Save in the actual Edit dialog the
-- stored 3000-byte description is still the original text; the Save either
-- commits the new title with that text, or visibly refuses (dialog stays open,
-- a printed reason) with the whole stored record byte-identical.
-- GUARD (holds at 8c): a 1900-byte description survives a title-only Save; a
-- description the owner changes with a "|" is still refused in the dialog
-- with the stored record unchanged; an explicit valid replacement typed by the
-- owner is saved; an explicit controller deletion (description "") still
-- proceeds; a changed description over 2000 bytes is still refused ("too
-- long"); identity, verified owner and Echoes unchanged; no game action.
-- SETUP: real TOC start-up (format-5 profile), actual catalog admission as
-- the producer of the long own records, real Build Library detail pane and
-- Edit dialog. No editor/catalog/wire limit is widened by this test and no
-- old authorship is inferred. No native Lua, network or native action.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_description_unseeded_edit')
local printable=B.printable
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database())
local CAT,CB=Nexus.BuildCatalog,Nexus.CommunityBuilds
C.setup(Nexus.StartupStatus().coreReady==true,'start-up reached core-ready')

local LONG,SHORT=string.rep('D',3000),string.rep('S',1900)
local X,Y,Z='synthetic-unseeded-long','synthetic-seeded-short','synthetic-unseeded-delete'
local function Put(id,title,text,echoes)
 local row={id=id,title=title,description=text,author=F.NAME,ownerKey=F.OWNER,
  ownerVerified=true,isMine=true,class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,echoes=echoes,lockedEchoes={}}
 local ok,why,ticket=CAT.Put(row,{source='local'})
 if ticket then
  for _=1,4000 do CAT.PumpRootAdmission();H.Advance(.05,.05);if ticket.state~='pending' then break end end
  ok,why=ticket.committed,ticket.reason
 end
 C.setup(ok==true and (CAT.Get(id) or {}).description==text,
  'the actual catalog admits the own '..#text..'-byte description of '..id,why)
end
Put(X,'Synthetic long title',LONG,H.Clone(F.PLAN))
Put(Y,'Synthetic short title',SHORT,{{spellId=200004,quality=0,stacks=1},{spellId=200005,quality=1,stacks=2}})
Put(Z,'Synthetic delete title',LONG,{{spellId=200006,quality=2,stacks=3}})

-- The stored row (read only) and a stable dump of every field.
local function StoredRow(id)
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and builds[id] or nil
 return type(row)=='table' and row or nil
end
local function Dump(v,depth)
 depth=depth or 0
 if type(v)~='table' then return type(v)..':'..printable(v) end
 if depth>6 then return '<deep>' end
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=printable(k)..'='..Dump(v[k],depth+1) end
 return '{'..table.concat(out,',')..'}'
end
local function Panel() local f=NexusCommunityBuildsFrame;return f and f._detailPanel end
local function ShowBuild(id)
 CB.ShowBuild(id)
 B.Until(H,function() local p=Panel();return p and p:IsShown() and p._nexusShownId==id end,2000)
 local p=Panel()
 return p and p._nexusShownId==id and p or nil
end
local function OpenEdit(tag,id)
 local panel=ShowBuild(id)
 C.setup(panel~=nil and CB.IsOwnBuild(id)==true,tag..': the own build detail pane opens')
 if not panel then return nil end
 panel.editBtn:Click()
 local popup=NexusEditPopup
 local open=popup~=nil and popup:IsShown() and popup._editingId==id
 C.setup(open,tag..': the actual Edit dialog opens for it')
 return open and popup or nil
end
local function CloseEdit()
 local panel,popup=Panel(),NexusEditPopup
 if panel and popup and popup:IsShown() then panel.editBtn:Click() end
end
local function Type(box,text) box:SetFocus();box:SetText('');box:Insert(text);return box:_NexusRawText() end
-- Save Details. Returns the printed lines and whether the dialog closed.
local function Save(popup,committed)
 local lines=B.CapturePrint(function() popup._saveBtn:Click() end)
 local closed=not popup:IsShown()
 if closed then B.Until(H,committed,2000) end
 return lines,closed
end
local function Refusal(lines)
 for _,line in ipairs(lines) do if line:find('ff6060Nexus:',1,true) then return line end end
end
CB.Show()

C.scenario('A title-only Save of an unseedable 3000-byte description',function()
 local stored=Dump(StoredRow(X));local before=CAT.Get(X) or {}
 local popup=OpenEdit('A',X)
 if not popup then return end
 C.setup(Type(popup._editTitleBox,'Synthetic changed title A')=='Synthetic changed title A','A: the owner typed only a new title')
 local lines,closed=Save(popup,function() return (CAT.Get(X) or {}).title=='Synthetic changed title A' end)
 local after=CAT.Get(X) or {}
 local refusal=Refusal(lines)
 print('OBSERVED','A closed='..printable(closed),'title='..printable(after.title),
  'description bytes='..#tostring(after.description or ''),'refusal='..printable(refusal))
 C.expect(after.description==LONG,'A: the stored 3000-byte description is not silently erased',#tostring(after.description or ''))
 local committedKeep=closed and after.title=='Synthetic changed title A' and after.description==LONG
 local refusedUnchanged=not closed and refusal~=nil and Dump(StoredRow(X))==stored
 C.expect(committedKeep or refusedUnchanged,
  'A: the Save either commits the title with the original text, or visibly refuses and changes nothing')
 C.guard(after.id==before.id and after.ownerKey==before.ownerKey and after.ownerVerified==true,
  'A: identity and verified owner unchanged')
 C.guard(F.Serialize(after.echoes)==F.Serialize(before.echoes),'A: Echo records unchanged')
 CloseEdit()
end)

C.scenario('B title-only Save of a seedable 1900-byte description',function()
 local popup=OpenEdit('B',Y)
 if not popup then return end
 C.setup(popup._editDescBox:_NexusRawText()==SHORT,'B: the dialog seeds the 1900-byte description exactly')
 Type(popup._editTitleBox,'Synthetic changed title B')
 local _,closed=Save(popup,function() return (CAT.Get(Y) or {}).title=='Synthetic changed title B' end)
 local after=CAT.Get(Y) or {}
 C.guard(closed and after.title=='Synthetic changed title B' and after.description==SHORT,
  'B: positive control, the title is saved and the seeded description kept',#tostring(after.description or ''))
 CloseEdit()
end)

C.scenario('C a changed description with a "|" is refused',function()
 local popup=OpenEdit('C',X)
 if not popup then return end
 local stored=Dump(StoredRow(X))
 C.setup(Type(popup._editDescBox,'Synthetic owner note with a | in it.')=='Synthetic owner note with a | in it.',
  'C: the owner typed a description with a "|"')
 local lines,closed=Save(popup,function() return true end)
 C.guard(not closed and Refusal(lines)~=nil and Dump(StoredRow(X))==stored,
  'C: the dialog refuses the changed unsafe description and the whole stored record is unchanged')
 CloseEdit()
end)

C.scenario('D an explicit valid replacement is saved',function()
 local popup=OpenEdit('D',X)
 if not popup then return end
 local note='Synthetic owner replacement description.'
 C.setup(Type(popup._editDescBox,note)==note,'D: the owner typed a valid replacement description')
 local _,closed=Save(popup,function() return (CAT.Get(X) or {}).description==note end)
 C.guard(closed and (CAT.Get(X) or {}).description==note,'D: the explicit owner replacement is saved',
  #tostring((CAT.Get(X) or {}).description or ''))
 CloseEdit()
end)

C.scenario('E explicit controller deletion still proceeds',function()
 local ok,why=CB.EditBuild(Z,nil,'',nil)
 B.Until(H,function() return (CAT.Get(Z) or {}).description=='' end,2000)
 C.guard(ok==true and (CAT.Get(Z) or {}).description=='',
  'E: an explicit owner deletion (description "") through the controller still proceeds',printable(ok)..'/'..printable(why))
end)

C.scenario('F a changed description over 2000 bytes is still refused',function()
 local stored=Dump(StoredRow(Y))
 local ok,why=CB.EditBuild(Y,nil,string.rep('E',2100),nil)
 C.guard(ok==false and why=='description is too long' and Dump(StoredRow(Y))==stored,
  'F: the 2000-byte rule for changed text is not widened',printable(ok)..'/'..printable(why))
end)

C.guard(#H.actions==0,'no native action',#H.actions)
print('OBSERVED','fake sends='..#H.sent)
C.finish('(unchanged text kept or visibly refused; changed text rules and limits unchanged)')
