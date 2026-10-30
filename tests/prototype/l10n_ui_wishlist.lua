-- Full UI localization, Wishlist family (editor.*, overlay.*, wishlist.*).
-- A synthetic pseudo-locale pack (tests/prototype/l10n_pseudo_support.lua) is
-- made the session language before the real TOC boot; the real Wishlist
-- editor, its menus, popups, locked-target chooser, save result, tooltips,
-- chat lines, the On-Screen Wishlist overlay and its settings popup are then
-- driven through their real entry points and scripts. Every visible word on
-- those receivers must have come through the seam (marked text), except data
-- (fixture Wishlist/Saved Build/Echo names, numbers) and an explicit list of
-- texts that are recorded as pending in the family fragment or owned by
-- another family. Also: long mode (expanded text) shows without error,
-- missing pack entries show exact English, template counts show ? for
-- unknown and 0 for zero, long UTF-8 names are inserted verbatim, an English
-- boot shows the exact English bytes, and opening, hovering, menus, popups
-- and navigation write no saved data and send or act on nothing.
-- Synthetic offline evidence only: no native font, glyph, layout or client
-- popup claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end

local LONG_NAME='Zq R\195\169serve '..string.rep('\195\169',6)..' \208\150\208\176\209\128 '..string.rep('W',20)
local SAVED_NAME='Qv Foundation '..string.rep('\195\169',4)
local OTHER_NAME='Kx Pl\195\162n'
local LOCKED_ECHO=200007

-- The data values this fixture shows (never translated).
local function DataStrings()
 local out={LONG_NAME,SAVED_NAME,OTHER_NAME,'PrototypeTester','Ebonhold','Gen plan'}
 local catalog=Nexus.GameAdapter and Nexus.GameAdapter.Catalog and Nexus.GameAdapter.Catalog()
 for _,row in pairs(catalog and catalog.rows or {}) do if row.name then out[#out+1]=row.name end end
 table.sort(out,function(a,b) return #a>#b end)
 return out
end

-- The Wishlist controller's chat lines (v3 remainder): every entry of its
-- phrasebook rebuilt as core/WishlistController.lua builds it, after one of
-- its coloured tags. A count slot gets 7, a text slot a data name.
local TAGS={'|cffff6060Nexus:|r ','|cff4dff80Nexus:|r ','|cffffd200Nexus:|r '}
local function NotifyLines()
 local book=Nexus.WishlistInternals.Controller.NotifyBook()
 local out,i={},0
 local function add(body) i=i+1;out[#out+1]=TAGS[i%#TAGS+1]..body end
 for raw,key in pairs(book.exact) do
  if key:sub(1,14)=='editor.notify.' then add(raw)
  -- A Library record reason in the Copy line it fills, unless an earlier
  -- UserText rule already presents that whole line (existing behaviour).
  elseif Nexus.UserText.EnglishMessage(TAGS[1]..'Copy unavailable: '..raw..'.')==TAGS[1]..'Copy unavailable: '..raw..'.' then
   add('Copy unavailable: '..raw..'.')
  end
 end
 for _,entry in ipairs(book.formats) do
  local args={}
  for n,slot in ipairs(entry.slots) do args[n]=slot=='count' and 7 or 'Qv Plan' end
  add(string.format(entry.format,unpack(args)))
 end
 return out,book
end

local function Boot(mode,entries)
 if mode~='english' then S.InstallBootHook(mode~='wrap' and mode or nil,entries) end
 local H=F.Boot(F.Database({mutate=function(db)
  local echoes={}
  for i=1,6 do echoes[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
  db.chars[F.NAME].loadoutWishlists={
   [1]={slot=101,name=LONG_NAME,echoes=echoes,assignmentId='assigned:1',designTargets={}},
   [207]={slot=102,name=OTHER_NAME,echoes={{spellId=200011,quality=3,stacks=1,locked=false}},
    assignmentId='assigned:207',designTargets={}}}
 end}),function(h)
  h.perks.serverBuildSlots={
   {name=SAVED_NAME,verified=true,echoes={{spellId=200001,quality=1,stacks=1}}},
   {name='',verified=true,echoes={{spellId=200002,quality=2,stacks=1}}}}
  h.perks.serverActiveSlot=1
  h.locked={{spellId=LOCKED_ECHO,stacks=1}}
 end)
 for _=1,40 do H.Advance(.05,.05) end
 return H
end

-- Texts that are visible here but are not this family's adopted copy: each is
-- listed as pending in fragments/wishlist.json or owned by another family.
-- (The six Help-quoted editor action labels are reviewed keys now: owner
-- follow-up v2.)
local PENDING_TEXT={
 ['Plan']='FullUIWorkspaces tab label (workspace family)',
 ['Explore']='FullUIWorkspaces tab label (workspace family)',
 ['Records']='FullUIWorkspaces tab label (workspace family)',
}
local function Strip(text,data)
 local t=tostring(text or '')
 for _,d in ipairs(data) do
  local i=t:find(d,1,true)
  while i do t=t:sub(1,i-1)..' '..t:sub(i+#d);i=t:find(d,1,true) end
 end
 return t
end
local function Allowed(word) return word=='Nexus' end -- the code-owned chat prefix "Nexus:"
local function Untranslated(texts)
 local data=DataStrings()
 local plain,out={},{}
 for _,item in ipairs(texts) do
  local text=type(item)=='table' and item.text or item
  local bare=S.Unmarked(text):gsub('^%s+',''):gsub('%s+$','')
  if not PENDING_TEXT[bare] then plain[#plain+1]=Strip(text,data) end
 end
 for _,m in ipairs(S.Untranslated(plain,Allowed)) do out[#out+1]=m end
 return out
end
local function Report(list)
 local parts={}
 for i=1,math.min(#list,12) do parts[#parts+1]=('%q (%s)'):format(list[i].text,list[i].word) end
 return table.concat(parts,'; ')
end

-- Every visible text under the editor except the destination row, whose
-- cells (the first is the editor's own FontString) Panel.UpdateDestinationRow
-- words (panel family).
local function EditorTexts(frame)
 local row=frame._destinationRow
 local skip={}
 for _,cell in ipairs(row and row.cells or {}) do skip[cell]=true end
 local texts={}
 for _,item in ipairs(S.VisibleTexts(frame)) do
  if not skip[item.frame] and not (row and item.frame.parent==row) then texts[#texts+1]=item end
 end
 return texts
end
local function Hover(frame) return S.CaptureTooltip(function() local f=frame:GetScript('OnEnter');if f then f(frame) end end) end
local function Find(list,pred) for _,c in ipairs(list or {}) do if pred(c) then return c end end end
local function Has(texts,needle)
 for _,t in ipairs(texts) do if tostring(type(t)=='table' and t.text or t):find(needle,1,true) then return true end end
end
local function PopupText(H)
 local p=assert(H.popup,'a popup is shown')
 local ok,text=pcall(string.format,tostring(p.frame.text),p.arg1,p.arg2)
 assert(ok,'the popup text formats as the client formats it: '..tostring(text))
 return text,p
end

------------------------------------------------------------------------
-- A. Pseudo session: every visible word of the family passes the seam.
------------------------------------------------------------------------
local H=Boot('wrap')
check(Nexus.Localization.ActiveLanguage()=='frFR','A: the pseudo pack is the session language')
local snapshot=function() return F.Serialize(NexusDB)..'|'..F.Serialize(WishlistRealizerDB or {}) end
-- The overlay is shown first: Show is a deliberate setting (overlayShown).
Nexus.WishlistOverlay.Show()
local before={db=snapshot(),sent=#H.sent,actions=#H.actions}

-- A1: an existing Wishlist opened for the active Saved Build (edit mode,
-- planned rows, a locked Echo slot, the catalog).
Nexus.WishlistEditor.Show()
local f=assert(NexusEditorFrame,'the editor frame')
check(f:IsShown(),'A1: the editor is open')
local texts=EditorTexts(f)
check(#texts>40,'A1: the editor shows its texts ('..#texts..')')
local missing=Untranslated(texts)
check(#missing==0,'A1: every visible editor word passed the seam: '..Report(missing))
check(Has(texts,S.OPEN..'Plan / Edit Wishlist'..S.CLOSE),'A1: the edit title reaches its FontString')
check(Has(texts,LONG_NAME),'A1: the long UTF-8 Wishlist name is shown verbatim')
local switch=assert(NexusWishlistEditorSwitchButton)
check(switch:GetText()==S.OPEN..'Editing: '..LONG_NAME..S.CLOSE,'A1: the Editing template inserts the name verbatim: '..switch:GetText())

-- A2: every hover of the editor's own controls and rows.
local tips={}
local function AddTips(frame)
 for _,line in ipairs(Hover(frame)) do tips[#tips+1]=line end
end
local loadoutBtn=Find(f.children,function(c) return c.kind=='Button' and tostring(c:GetText()):find('Saved Build: ',1,true) end)
check(loadoutBtn~=nil,'A2: the Saved Build selector')
for _,b in ipairs({loadoutBtn,switch,f._manageBtn,f._workspaceAssignBtn,f._workspaceMyBuildsBtn}) do AddTips(b) end
local displayBtn=Find(f.children,function(c) return c.kind=='Button' and tostring(c:GetText()):find('Display Settings',1,true) end)
AddTips(assert(displayBtn,'A2: Display Settings'))
local apply=Find(f.children,function(c) return c.kind=='Button' and c:GetWidth()>=188 and c.scripts.OnEnter and c.points[1] and c.points[1][1]=='BOTTOMLEFT' end)
AddTips(assert(apply,'A2: the Save button'))
if f._saveOnlyBtn then AddTips(f._saveOnlyBtn) end
for i=1,8 do local slot=f._nexusLockedSlot(i);if slot:IsShown() then AddTips(slot) end end
local check6=Find(f.children,function(c) return c.kind=='CheckButton' and c._nexusAnchorSlot end)
AddTips(assert(check6,'A2: the locked-slot automation box'))
local pickArea=f._pickArea
for _,row in ipairs(pickArea.children or {}) do
 if row:IsShown() then
  for _,b in ipairs({row.minus,row.plus,row.remove}) do if b and b:IsShown() then AddTips(b) end end
 end
end
check(#tips>=20,'A2: the hovers show lines ('..#tips..')')
missing=Untranslated(tips)
check(#missing==0,'A2: every editor hover line passed the seam: '..Report(missing))
check(Has(tips,S.OPEN..'Auto-manage locked Echo slots'..S.CLOSE),'A2: the locked-slot automation hover reaches the tooltip')
check(Has(tips,S.OPEN..'Left-click: find in catalog'..S.CLOSE),'A2: a currently locked slot shows its hints (locked Echo slot, not Freeze)')

-- A3: menus through their real builders (switch, Saved Build, Manage).
switch:Click()
local switchMenu=assert(NexusWishlistEditorSwitchMenu,'A3: the switch list')
local menuTexts=S.VisibleTexts(switchMenu)
check(#menuTexts>=2,'A3: the switch list shows rows')
missing=Untranslated(menuTexts)
check(#missing==0,'A3: switch list rows passed the seam: '..Report(missing))
check(Has(menuTexts,'(index 207 is not a Saved Build)'),'A3: the not-a-Saved-Build note is shown')
local rowTips={}
for _,r in ipairs(switchMenu.rows) do if r:IsShown() then for _,l in ipairs(Hover(r)) do rowTips[#rowTips+1]=l end end end
missing=Untranslated(rowTips)
check(#missing==0,'A3: switch row hovers passed the seam: '..Report(missing))
switch:Click()
loadoutBtn:Click()
local loadoutMenu=assert(NexusWishlistEditorLoadoutMenu,'A3: the Saved Build list')
menuTexts=S.VisibleTexts(loadoutMenu)
missing=Untranslated(menuTexts)
check(#missing==0,'A3: Saved Build rows passed the seam: '..Report(missing))
check(Has(menuTexts,S.OPEN..'Saved Build 2'..S.CLOSE),'A3: an unnamed Saved Build shows the localized number fallback')
loadoutBtn:Click()
f._manageBtn:Click()
local manage=assert(NexusWishlistManageMenu,'A3: the Manage list')
menuTexts=S.VisibleTexts(manage)
missing=Untranslated(menuTexts)
check(#missing==0,'A3: Manage rows and header passed the seam: '..Report(missing))
check(Has(menuTexts,S.OPEN..'Saved wishlists on this character: 2'..S.CLOSE),'A3: the Manage count reaches its header')

-- A4: the removal confirmation, opened from a Manage row (not accepted).
local manageRow=Find(manage.rows,function(r) return r:IsShown() and r:IsEnabled() and tostring(r._label:GetText()):find('Remove',1,true) end)
manageRow:Click()
local popup,p=PopupText(H)
check(p.which=='NEXUS_FORGET_WISHLIST','A4: the removal confirmation is shown')
missing=Untranslated({popup})
check(#missing==0,'A4: the removal confirmation passed the seam: '..Report({popup}))
check(StaticPopupDialogs.NEXUS_FORGET_WISHLIST.button1==S.OPEN..'Remove'..S.CLOSE
 and StaticPopupDialogs.NEXUS_FORGET_WISHLIST.button2==S.OPEN..'Cancel'..S.CLOSE,'A4: its buttons resolve through the seam when read')
StaticPopup_Hide('NEXUS_FORGET_WISHLIST')

-- A6: the import and export popups and their chat lines.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
popup=PopupText(H)
missing=Untranslated({popup,StaticPopupDialogs.NEXUS_IMPORT_WISHLIST.button1})
check(#missing==0,'A6: the import popup passed the seam: '..Report(missing))
StaticPopup_Hide('NEXUS_IMPORT_WISHLIST')
local chat=S.CaptureChat(function() Nexus.WishlistEditor.ImportEBH1String('not a code') end)
check(#chat==1 and chat[1]=='|cffff6060Nexus:|r '..S.OPEN.."couldn't parse that as an EBH1 string."..S.CLOSE,
 'A6: an unreadable code is refused in the session language: '..tostring(chat[1]))
StaticPopup_Show('NEXUS_EXPORT_WISHLIST')
popup=PopupText(H)
missing=Untranslated({popup,StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.button1})
check(#missing==0,'A6: the export popup passed the seam: '..Report(missing))
StaticPopup_Hide('NEXUS_EXPORT_WISHLIST')
for _,which in ipairs({'NEXUS_FLEXIBLE_PLAN_REPLACE','NEXUS_WORKSPACE_CONTEXT_CHANGED','NEXUS_NAME_IMPORTED_WISHLIST'}) do
 local d=StaticPopupDialogs[which]
 local ok,text=pcall(string.format,d.text,OTHER_NAME)
 check(ok,'A6: '..which..' text formats as the client formats it')
 missing=Untranslated({text,d.button1,d.button2})
 check(#missing==0,'A6: '..which..' passed the seam when read: '..Report(missing))
end

-- A7: the display popup and the overlay (shown with its settings).
Nexus.WishlistEditor.ToggleDisplayPopup(displayBtn)
local display=assert(NexusDisplayPopup,'A7: the display popup')
local displayTexts=S.VisibleTexts(display)
missing=Untranslated(displayTexts)
check(#missing==0,'A7: the display popup passed the seam: '..Report(missing))
check(Has(displayTexts,S.OPEN..'On-Screen Wishlist'..S.CLOSE),'A7: its title reaches the FontString')
Nexus.WishlistEditor.ToggleDisplayPopup(displayBtn)
local overlay=assert(NexusOverlay,'A7: the overlay frame');H.Advance(1.1,.05)
local overlayTexts=S.VisibleTexts(overlay)
for _,t in ipairs(S.VisibleTexts(NexusOverlayControls)) do overlayTexts[#overlayTexts+1]=t end
missing=Untranslated(overlayTexts)
check(#missing==0,'A7: the overlay and its controls passed the seam: '..Report(missing))
local hide=Find(NexusOverlayControls.children,function(c) return c:GetText()=='-' end)
missing=Untranslated(Hover(hide))
check(#missing==0,'A7: the overlay hide hover passed the seam: '..Report(missing))

-- A8: create mode (a new draft): title, name field, catalog and empty plan.
Nexus.WishlistEditor.NewWishlist()
texts=EditorTexts(f)
missing=Untranslated(texts)
check(#missing==0,'A8: create mode passed the seam: '..Report(missing))
check(Has(texts,S.OPEN..'Plan / Create Wishlist'..S.CLOSE) and Has(texts,S.OPEN..'Wishlist name:'..S.CLOSE),
 'A8: the create title and name label reach their FontStrings')
check(Has(texts,S.OPEN..'Planned rolled copies: 0/79'..S.CLOSE),'A8: a zero count shows 0, never ?')
StaticPopup_Show('NEXUS_EXPORT_WISHLIST')
popup=PopupText(H)
StaticPopup_Hide('NEXUS_EXPORT_WISHLIST')

-- Passivity: opening, hovering, menus, popups and navigation wrote nothing.
check(snapshot()==before.db,'passive: no saved data was written')
check(#H.sent==before.sent and #H.actions==before.actions,'passive: nothing was sent and no game action ran')

-- A9: the locked-target chooser (an import that needs locked roles; the
-- automatic suggestion is refused while the locked list is not synced).
-- An untagged code (no role marks) with 81 copies, as another tool writes it.
H.locked=nil;H.Advance(1,.05)
local parts={}
for i=1,81 do parts[i]=(200000+i)..'.'..(i%4)..'.1' end
local raw='EBH1:'..table.concat(parts,',')..':MAGE:Untyped'
local roleChat=S.CaptureChat(function() Nexus.WishlistEditor.ImportEBH1String(raw,OTHER_NAME) end)
local picker=NexusWishlistRolePicker
check(picker and picker:IsShown(),'A9: the locked-target chooser opens for an untagged 81-copy import')
local pickerTexts=S.VisibleTexts(picker)
missing=Untranslated(pickerTexts)
check(#missing==0,'A9: the locked-target chooser passed the seam: '..Report(missing))
check(Has(pickerTexts,S.OPEN..'Choose locked Echo targets: '..OTHER_NAME..S.CLOSE),'A9: its title inserts the name verbatim')
check(Has(pickerTexts,S.OPEN..'Page 1 / 9'..S.CLOSE) and Has(pickerTexts,S.OPEN..'0 locked'..S.CLOSE),
 'A9: its pager and zero counts reach their FontStrings')
NexusWishlistRoleUseOwned:Click()
check(picker.message:GetText()==S.OPEN.."Waiting for the server's current locked Echo list. You can choose the intended targets manually."..S.CLOSE,
 'A9: the suggestion refusal while the locked list is unknown is shown in the session language')
NexusWishlistRoleNext:Click()
missing=Untranslated(S.VisibleTexts(picker))
check(#missing==0,'A9: the next page passed the seam: '..Report(missing))
missing=Untranslated(roleChat)
check(#missing==0,'A9: the import chat passed the seam: '..Report(missing))
NexusWishlistRoleCancel:Click()
check(not picker:IsShown(),'A9: Cancel closes the chooser')
Nexus.WishlistEditor.NewWishlist()

-- A10: draft actions (outside the passivity window): add one catalog Echo to
-- the new draft, name it, open the Create confirmation, then accept it and
-- read the save result line and its hover.
local catalogRow=Find(f._leftArea.children,function(r) return r:IsShown() and r.data end)
catalogRow:Click()
NexusWishlistNameInput:SetText(OTHER_NAME..' 2')
local create=Find(f.children,function(c) return c.kind=='Button' and c:IsShown() and c:IsEnabled()
 and (c:GetText()==S.OPEN..'Create unassigned'..S.CLOSE or c:GetText()==S.OPEN..'Create & assign'..S.CLOSE) end)
check(create~=nil,'A10: the Create button shows its reviewed label')
create:Click()
popup,p=PopupText(H)
check(p.which=='WISHLISTREALIZER_CREATE_WISHLIST','A10: the Create confirmation is shown')
missing=Untranslated({popup})
check(#missing==0,'A10: the Create confirmation passed the seam: '..Report(missing))
check(popup:find(S.OPEN.."Create '"..OTHER_NAME..' 2'.."'?"..S.CLOSE,1,true)~=nil,'A10: the question names the Wishlist verbatim')
check(StaticPopupDialogs[p.which].button2==S.OPEN..'Cancel'..S.CLOSE,'A10: Cancel resolves through the seam')
local saveChat=S.CaptureChat(function() H.AcceptPopup();H.now=H.now+3.1;H.Advance(.6,.05) end)
do
 local found
 for _,line in ipairs(saveChat) do if line:find('Wishlist saved (',1,true) then found=line end end
 check(found=='|cff4dff80Nexus:|r '..S.OPEN..'Wishlist saved (1/79 rolled copies planned; planned locked targets are saved separately).'..S.CLOSE,
  'A10: the real save chat line is said once through the seam, its tag kept: '..tostring(found))
end
do
 local lines,book=NotifyLines()
 check(#lines>150,'A11: the chat book holds the controller lines and the record reasons: '..#lines)
 local bad={}
 for _,line in ipairs(lines) do
  local shown=Nexus.UserText.Message(line)
  local tag=line:match('^(|c%x+Nexus:|r )')
  if shown:sub(1,#tag)~=tag or S.LooksUntranslated(shown:sub(#tag+1),function(w) return w=='Qv' or w=='Plan' end)~=nil then
   bad[#bad+1]=line..' -> '..shown
  end
 end
 check(#bad==0,'A11: every Wishlist chat line passes the seam once:\n'..table.concat(bad,'\n'))
 -- A Library record reason inside a Copy line is said through its own key.
 local nested=0
 for raw,key in pairs(book.exact) do
  local line=TAGS[1]..'Copy unavailable: '..raw..'.'
  -- (A whole line the controller writes itself is its own exact entry.)
  if key:sub(1,14)~='editor.notify.' and Nexus.UserText.EnglishMessage(line)==line
   and not book.exact['Copy unavailable: '..raw..'.'] then
   nested=nested+1
   local shown=Nexus.UserText.Message(line)
   check(shown:find(S.OPEN..raw..S.CLOSE,1,true)~=nil,'A11: the record reason is said through its key inside the Copy line: '..shown)
  end
 end
 check(nested>40,'A11: record reasons checked inside Copy lines: '..nested)
 -- An unknown line keeps its existing presentation.
 local other='|cffff6060Nexus:|r '..LONG_NAME
 check(Nexus.UserText.Message(other)==other,'A11: an unknown chat line is shown unchanged')
end
local result=f._saveResultText
if result and result:IsShown() then
 missing=Untranslated({result:GetText()})
 check(#missing==0,'A10: the save result line passed the seam: '..Report(missing))
 local hover=Find(f.children,function(c) return c==f._saveResultHover end)
 missing=Untranslated(Hover(hover))
 check(#missing==0,'A10: the save result hover passed the seam: '..Report(missing))
end

-- Template contract on the real seam: unknown is ?, zero is 0.
local L=Nexus.Localization
check(L.Format('editor.label.pick_planned',{count=L.Count(nil)})==S.OPEN..'Planned rolled copies: ?/79'..S.CLOSE,'template: unknown count shows ?')
check(L.Format('editor.label.pick_planned',{count=L.Count(0)})==S.OPEN..'Planned rolled copies: 0/79'..S.CLOSE,'template: zero shows 0')
check(L.Format('overlay.tooltip.show_again',{command='/nexus overlay'})==S.OPEN..'/nexus overlay to show it again'..S.CLOSE,
 'template: the slash command slot is inserted as typed')

------------------------------------------------------------------------
-- B. Long mode on the densest window: no error, text still shown.
------------------------------------------------------------------------
H=Boot('long')
check(Nexus.Localization.ActiveLanguage()=='frFR','B: the long pack is active')
local ok,err=pcall(function()
 Nexus.WishlistEditor.Show()
 NexusWishlistEditorSwitchButton:Click();NexusWishlistEditorSwitchButton:Click()
 Nexus.WishlistEditor.ToggleDisplayPopup()
end)
check(ok,'B: the editor, its list and display popup open in long mode: '..tostring(err))
texts=EditorTexts(NexusEditorFrame)
check(Has(texts,'Plann') and Has(texts,'Wishlistwishlist'),'B: expanded text is shown')
check(#Untranslated(texts)==0,'B: long mode still passes every word through the seam')

------------------------------------------------------------------------
-- C. Missing pack entries show exact English.
------------------------------------------------------------------------
local entries=S.PseudoEntries()
local MISSING={'editor.title.edit','editor.heading.selected','overlay.status.no_wishlist',
 'editor.label.pick_planned','editor.tooltip.manage_heading'}
for _,key in ipairs(MISSING) do entries[key]=nil end
H=Boot('wrap',entries)
Nexus.WishlistEditor.Show()
texts=EditorTexts(NexusEditorFrame)
check(Has(texts,'Plan / Edit Wishlist') and not Has(texts,S.OPEN..'Plan / Edit Wishlist'),'C: a missing title entry shows exact English')
check(Has(texts,'Selected Echoes') and not Has(texts,S.OPEN..'Selected Echoes'),'C: a missing heading entry shows exact English')
local planned=Find(texts,function(t) return t.text:find('Planned rolled copies: ',1,true) end)
check(planned and planned.text:sub(1,23)=='Planned rolled copies: ','C: a missing template entry uses the English template')
local manageTip=Hover(NexusEditorFrame._manageBtn)
check(manageTip[1]=='Manage saved wishlists' and manageTip[2]:sub(1,#S.OPEN)==S.OPEN,'C: only the missing tooltip line falls back to English')
Nexus.WishlistOverlay.Show();H.Advance(1.1,.05)
-- The fixture has an assigned Wishlist; the empty state is read directly.
check(Nexus.Localization.Text('overlay.status.no_wishlist')=='No wishlist set','C: the missing overlay status is exact English')

------------------------------------------------------------------------
-- D. English session: exact English bytes on the real receivers.
------------------------------------------------------------------------
H=Boot('english')
check(Nexus.Localization.ActiveLanguage()=='enUS','D: English session')
Nexus.WishlistEditor.Show()
f=NexusEditorFrame
texts=EditorTexts(f)
check(Has(texts,'Plan / Edit Wishlist') and Has(texts,'Selected Echoes'),'D: title and heading in exact English')
check(NexusWishlistEditorSwitchButton:GetText()=='Editing: '..LONG_NAME,'D: the Editing label in exact English')
f._manageBtn:Click()
local header=NexusWishlistManageMenu.header:GetText()
check(header:sub(1,#'Saved wishlists on this character: 2  |cff777777removals here are local; ')
 =='Saved wishlists on this character: 2  |cff777777removals here are local; ','D: the Manage header in exact English: '..header)
f._manageBtn:Click()
Nexus.WishlistEditor.NewWishlist()
Find(f._leftArea.children,function(r) return r:IsShown() and r.data end):Click()
NexusWishlistNameInput:SetText(OTHER_NAME..' 3')
Find(f.children,function(c) return c.kind=='Button' and c:IsShown() and c:IsEnabled()
 and (c:GetText()=='Create unassigned' or c:GetText()=='Create & assign') end):Click()
popup,p=PopupText(H)
local CREATE_HEAD="Create '"..OTHER_NAME.." 3'?\n1 of 79 rolled copies planned; planned locked targets are saved separately.\n"
check(popup:sub(1,#CREATE_HEAD)==CREATE_HEAD,'D: the Create confirmation in exact English: '..popup)
check(popup:find('Existing Wishlists are not overwritten. Nothing is rolled, spent or activated.',1,true)~=nil,
 'D: joined sentences keep their exact English spacing')
check(StaticPopupDialogs[p.which].button2=='Cancel','D: Cancel in exact English')
StaticPopupDialogs[p.which].OnCancel(p.frame,p.data);StaticPopup_Hide(p.which)
check(StaticPopupDialogs.NEXUS_IMPORT_WISHLIST.text=='Paste a Wishlist import code (EBH1):\nThe import will be loaded as a new '
 ..'wishlist and will not overwrite the one currently open.','D: the import prompt in exact English')
check(StaticPopupDialogs.WISHLISTREALIZER_CREATE_WISHLIST.text=="Create '%s'?\n%s",'D: the Create question keeps its exact format')
chat=S.CaptureChat(function() Nexus.WishlistEditor.ImportEBH1String('not a code') end)
check(chat[1]=="|cffff6060Nexus:|r couldn't parse that as an EBH1 string.",'D: chat line in exact English')
do
 local lines=NotifyLines()
 local bad={}
 for _,line in ipairs(lines) do
  local shown,before=Nexus.UserText.Message(line),Nexus.UserText.EnglishMessage(line)
  if shown~=before then bad[#bad+1]=line..' -> '..shown..' (before: '..before..')' end
 end
 check(#bad==0,'D: every Wishlist chat line shows the English bytes it showed before:\n'..table.concat(bad,'\n'))
 check(Nexus.UserText.Message('|cffff9040Nexus:|r Wishlist identity found; awaiting authoritative locked-Echo evidence.')
  =='|cffff9040Nexus:|r awaiting authoritative locked-Echo evidence.','D: the legacy-rewritten line keeps its earlier English')
 -- The editor's callback prints the controller's line as given: the
 -- controller's notify is its one presentation (UserText.Message).
 local function Up(fn,name)
  for i=1,200 do
   local n,v=debug.getupvalue(fn,i)
   if n==nil then return nil end
   if n==name then return v end
  end
 end
 local controller
 for _,fn in pairs(Nexus.WishlistEditor) do
  if type(fn)=='function' then controller=controller or Up(fn,'wishlistController') end
 end
 local notify=assert(Up(assert(controller,'the editor controller').ToggleEmptyAssignment,'notify'),'the controller notify')
 local options=assert(Up(notify,'options'),'the editor options')
 local presented=Nexus.UserText.Message('|cffff6060Nexus:|r retry refused because its payload changed.')
 local printed=S.CaptureChat(function() options.notify(presented) end)
 check(printed[1]==presented,'D: the editor prints the presented line as given (no second presentation): '..tostring(printed[1]))
 local said=S.CaptureChat(function() notify('|cffff6060Nexus:|r retry refused because its payload changed.') end)
 check(said[1]==presented,'D: the real controller notify presents its line once: '..tostring(said[1]))
end
Nexus.WishlistOverlay.Show();H.Advance(1.1,.05)
check(Find(S.VisibleTexts(NexusOverlayControls),function(t) return t.text=='Unlock position' end)~=nil,'D: overlay control in exact English')

print('l10n_ui_wishlist PASS '..checks)
