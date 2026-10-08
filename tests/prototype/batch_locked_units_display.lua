-- Group 3 (display seam): the Wishlist editor's locked strip and footer count
-- current locked ownership. ui/WishlistRenderer.lua expands every held copy
-- of a locked record into its own slot icon and counts copies in
-- "Locked (N/6):" and "Currently locked: N/6", so one record holding 5 copies
-- reads as five occupied slots, and records 1,1,1,3,1 (refused by the copy
-- trust today) read as none.
-- EXPECT (fails at 8c): five records holding 1,1,1,3,1 copies show five
-- occupied slots (label and footer numerator 5) with each record's spell
-- once; two records holding 5 and 1 copies show two occupied slots.
-- GUARD (holds at 8c): five single records show five; no locked records show
-- zero and no "Currently locked" part; the authored-target footer
-- ("Locked targets") is unchanged (design policy, separate from ownership);
-- no game action.
-- CONFLICT NOTE for root: existing tests/prototype/wishlist_footer_layout.lua
-- line 74 asserts "Currently locked: 6/6" for the two-record 5+1 state (the
-- copy count). A records-unit display repair makes that existing line fail;
-- it is preserved unchanged in this test phase and must be decided by root.
-- SETUP: real TOC boot, real WishlistModel/Controller/Renderer, injected Store
-- as in wishlist_footer_layout.lua; synthetic locked records only.
-- EBH1 export of a plan without locked targets (standards review r1,
-- STD-R1-02), through the real editor's import and its export dialog. The
-- export appended every held locked copy to such a plan, and above six copies
-- the code's envelope emptied its Echo list (a code that imports nowhere).
-- EXPECT (fails at 3bc6d88): EX7 with five records holding seven copies the
-- export is a code that imports, holding the 79 ordinary copies and no
-- locked row, and the dialog and the chat say the held locked Echoes are not
-- in it; EX0 a draft with nothing to export offers no code and the dialog
-- says why. GUARD (holds at 3bc6d88): EX6 six single records are still
-- appended as the plan's six locked rows (the codec's 79/6/85 is unchanged).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_units_display')
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
local frame=r.Prepare();r.ShowFrame();r.Refresh()
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
C.setup(Region('Locked')~=nil and Region('Rolled copies:')~=nil,'the actual locked strip label and footer exist')
local actions=#H.actions

local function Show(label,records)
 H.locked=H.Clone(records);H.Notify();A.Poll();r.Refresh()
 local strip,footer=Region('Locked (') or '',Region('Rolled copies:') or ''
 local count,ids=Icons()
 print('OBSERVED',label,'label='..strip,'footer='..(footer:gsub('\n',' | ')),'locked icons='..count)
 return strip,footer,count,ids
end
local function R(id,stack) return {spellId=id,stack=stack} end

C.scenario('S5 five records holding 1,1,1,3,1',function()
 local strip,footer,count,ids=Show('S5',{R(200080,1),R(200081,1),R(200082,1),R(200083,3),R(200084,1)})
 C.expect(strip:find('Locked (5/',1,true)~=nil,'S5: the strip label counts five occupied records',strip)
 C.expect(footer:find('Currently locked: 5/',1,true)~=nil,'S5: the footer counts five occupied records',footer)
 local distinct=0;for _ in pairs(ids) do distinct=distinct+1 end
 C.expect(count==5 and distinct==5 and ids[200083]==1,'S5: one slot icon per record, the stacked record once',count)
end)

C.scenario('S2 two records holding 5 and 1',function()
 local strip,footer,count,ids=Show('S2',{R(200080,5),R(200081,1)})
 C.expect(strip:find('Locked (2/',1,true)~=nil,'S2: the strip label counts two occupied records',strip)
 C.expect(footer:find('Currently locked: 2/',1,true)~=nil,'S2: the footer counts two occupied records',footer)
 C.expect(count==2 and ids[200080]==1 and ids[200081]==1,'S2: two slot icons, one per record',count)
end)

C.scenario('K controls',function()
 local strip,footer,count=Show('K5',{R(200080,1),R(200081,1),R(200082,1),R(200083,1),R(200084,1)})
 C.guard(strip:find('Locked (5/',1,true)~=nil and footer:find('Currently locked: 5/',1,true)~=nil and count==5,
  'K5: five single records show five occupied slots',strip..' / '..footer)
 strip,footer,count=Show('K0',{})
 C.guard(strip:find('Locked (0/',1,true)~=nil and footer:find('Currently locked',1,true)==nil and count==0,
  'K0: no locked records show none',strip..' / '..footer)
 C.guard(footer:find('Locked targets: 0/6',1,true)~=nil,'K0: the authored-target footer is unchanged design policy',footer)
end)

-- The real export dialog over the real editor's draft, with the given held
-- records; the dialog's prompt is a font string, as the client's is.
local editor=Nexus.WishlistEditor
local function ExportShown(label,records)
 H.locked=H.Clone(records);H.Notify();A.Poll()
 local prompt=CreateFrame('Frame',nil,UIParent):CreateFontString()
 prompt:SetText('Your current wishlist + locked Echoes, as an EBH1 string.')
 local box=CreateFrame('EditBox',nil,UIParent)
 local lines,ok,err=B.CapturePrint(function()
  StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box,text=prompt})
 end)
 local code=box._nexusExplicitExportText
 local parsed=type(code)=='string' and code~='' and Nexus.Codec.DecodeEBH1(code) or nil
 local ordinary,locked=0,0
 for _,e in ipairs(parsed and parsed.entries or {}) do
  if e.locked then locked=locked+e.stacks else ordinary=ordinary+e.stacks end
 end
 local x={ok=ok,err=err,code=code,box=box:GetText(),parsed=parsed,ordinary=ordinary,locked=locked,
  prompt=B.Plain(prompt:GetText() or ''),said=B.Plain(table.concat(lines,' | '))}
 print('OBSERVED',label,'code bytes='..printable(code and #code),'imports='..printable(parsed~=nil),
  'ordinary='..ordinary,'locked='..locked,'prompt='..x.prompt)
 return x
end

C.scenario('EX export of a plan without locked targets',function()
 local rows={}
 for i=1,79 do rows[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 H.locked={};H.Notify();A.Poll()
 B.CapturePrint(function()
  editor.ImportEBH1String(Nexus.Codec.EncodeEBH1(rows,'MAGE','Synthetic export'),'Synthetic export')
 end)
 local draft=editor.DebugDraftState()
 C.setup(draft.pending==79 and draft.pendingLock==0 and draft.fulfilled==0,
  'EX: the real editor holds a 79-copy plan without locked targets',draft.pending)
 local x=ExportShown('EX7',{R(200080,1),R(200081,1),R(200082,1),R(200083,3),R(200084,1)})
 C.expect(x.ok and x.parsed~=nil and x.ordinary==79 and x.locked==0,
  'EX7: with seven held locked copies the export is a code that imports, holding the 79 ordinary copies',
  printable(x.code)..' '..printable(x.err))
 C.expect(x.prompt:find('not in this code',1,true)~=nil and x.said:find('not in this code',1,true)~=nil,
  'EX7: the dialog and the chat say the held locked Echoes are not in the code',x.prompt..' | '..x.said)
 x=ExportShown('EX6',{R(200080,1),R(200081,1),R(200082,1),R(200083,1),R(200084,1),R(200085,1)})
 C.guard(x.ok and x.parsed~=nil and x.ordinary==79 and x.locked==6,
  'EX6: six held single records are still appended as the plan\'s six locked rows',x.ordinary..'/'..x.locked)
end)

C.scenario('EX0 an export with nothing to export',function()
 B.CapturePrint(function() editor.NewWishlist() end)
 C.setup(editor.DebugDraftState().pending==0,'EX0: the real editor holds an empty new draft')
 local x=ExportShown('EX0',{})
 C.expect(x.ok and x.code=='' and x.box=='' and x.prompt:find('Export unavailable',1,true)~=nil
  and x.said:find('no Echoes to export',1,true)~=nil,'EX0: no code is offered and the dialog says why',
  printable(x.code)..' | '..x.prompt)
end)

C.guard(#H.actions==actions,'no game action',#H.actions-actions)
C.finish('(locked strip and footer count occupied records; authored-target policy unchanged)')
