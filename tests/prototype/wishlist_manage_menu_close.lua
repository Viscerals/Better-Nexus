-- F-S4-3 (P3), regression-first: the editor's "Manage" list closes with the
-- editor. The list (NexusWishlistManageMenu) is a child of the editor frame;
-- the editor's OnHide closes the other editor transients but not this list,
-- and only the renderer's Hide (which the public Toggle runs), a row click
-- and the Manage button close it.
-- A raw editor hide (its close button, Escape, its own Build Library or
-- Leaderboard buttons, Panel.CloseOtherWindows) therefore leaves the list's
-- shown flag set: the next open shows the old list again, with the header,
-- rows and per-row confirmation facts captured when it was drawn, and the
-- player's next Manage click closes it instead of opening a current one.
-- Healthy behaviour (EXPECT, fails at the baseline): after a raw editor Hide
-- (and after the editor's own Leaderboard button) the list is not shown;
-- reopening the editor shows no list until a new Manage click, and one click
-- then opens it; the removal confirmation the player can reach after reopening
-- states the current server facts, not those captured before the editor closed.
-- Unchanged (GUARD, holds at the baseline): the public Toggle closes the list
-- with the editor, and reopening after it shows none; a raw Hide of an editor
-- that is already closed is harmless; the Manage button toggles the list;
-- opening a removal confirmation removes nothing; the retained plans; no game
-- action.
-- Nexus.WishlistEditor has no Hide. Each scenario is closed afterwards, also
-- when it raised, with the existing controls only: the public Toggle
-- (/nexus editor) while the editor is shown, then a raw Hide of a list still
-- shown behind the closed editor (all HideManageWishlistsMenu does).
-- Real TOC boot, adapter, controller and editor controls; the format-5 saved
-- fixture with the two retained plans of wishlist_switch_recovery.lua (one on
-- Saved Build 1, one under the mirror index 101, both naming mirror slot 103).
-- Synthetic plan contents; the live mirror added later is artificial.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('wishlist_manage_menu_close')
local NAME='Synthetic Manage Plan'
local function Echoes(extra)
 local rows={}
 for index=1,12 do rows[#rows+1]={spellId=310000+index,quality=2,stacks=1,locked=false} end
 for index=1,3 do rows[#rows+1]={spellId=311000+index,quality=3,stacks=1,locked=true} end
 if extra then rows[#rows+1]={spellId=319999,quality=2,stacks=1,locked=false} end
 return rows
end
local H=F.Boot(F.Database({mutate=function(db)
 db.chars[F.NAME].loadoutWishlists={
  [1]={slot=103,name=NAME,echoes=Echoes(true),assignmentId='assigned:13',designTargets={}},
  [101]={slot=103,name=NAME,echoes=Echoes(false),assignmentId='assigned:6',designTargets={}},
 }
end}))
local A=Nexus.GameAdapter
local WE=Nexus.WishlistEditor
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
C.setup(#A.RetainedWishlistPlans()==2,'fixture: two plans are retained',#A.RetainedWishlistPlans())

local function Editor() return NexusEditorFrame end
local function Menu() return NexusWishlistManageMenu end
local function Manage() local b=NexusWishlistEditorManageButton;if b then b:Click() end;return b~=nil end
local function Shown() local m=Menu() return m~=nil and m:IsShown() end
local function Visible() local m=Menu() return m~=nil and m:IsVisible() end
local function Open(tag)
 WE.Show()
 C.setup(Editor()~=nil and Editor():IsShown(),tag..': fixture: the Wishlist editor is open')
 if not Shown() then Manage() end
 return C.setup(Visible(),tag..': fixture: a Manage click opens the list')
end
-- The visible row of the plan stored under the mirror index 101.
local function MirrorRow()
 for _,row in ipairs((Menu() or {}).rows or {}) do
  if row:IsVisible() and tostring(row._label:GetText() or ''):find('not a Saved Build (101)',1,true) then return row end
 end
 return nil
end
local function Plan101()
 for _,plan in ipairs(A.RetainedWishlistPlans()) do
  if plan.associationIndex==101 then return plan end
 end
 return {}
end
local function Close(tag)
 if Editor() and Editor():IsShown() then WE.Toggle() end
 local m=Menu()
 if m and m:IsShown() then m:Hide() end
 C.setup(not (Editor() and Editor():IsShown()) and not Shown(),tag..': cleanup: the editor and its list are closed')
end
local function Scenario(tag,label,fn)
 C.scenario(tag..' '..label,fn)
 C.scenario(tag..' cleanup',function() Close(tag) end)
end

Scenario('M1','a raw editor Hide',function()
 if not Open('M1') then return end
 Editor():Hide()
 C.setup(not Editor():IsShown(),'M1: fixture: the editor is closed by a raw Hide (close button, Escape)')
 print('OBSERVED','M1 list shown after the editor closed='..printable(Shown()))
 C.expect(not Shown(),'M1: the Manage list closes with the editor')
 WE.Show()
 C.setup(Editor():IsShown(),'M1: fixture: the editor is reopened')
 C.expect(not Visible(),'M1: reopening the editor shows no Manage list without a new Manage click')
 Manage()
 C.expect(Visible(),'M1: one Manage click after reopening opens the list')
 if Editor():IsShown() then WE.Toggle() end
 C.guard(not Editor():IsShown() and not Shown(),'M1: the public Toggle closes the reopened editor and its list')
end)

Scenario('M2','the confirmation reachable after reopening',function()
 if not Open('M2') then return end
 local before=Plan101()
 C.setup(before.mirrorSlotLive==false and before.mirrorResolved==false,
  'M2: fixture: no server Wishlist slot 103 exists yet')
 Editor():Hide()
 -- While the editor is closed, the server list gains a Wishlist in slot 103
 -- with other contents: the plans' mirror slot now exists.
 H.perks.serverBuildSlots[103]={name='Artificial live mirror',verified=false,
  echoes={{spellId=200001,quality=1,stacks=1,locked=false}}}
 H.Notify();A.Poll()
 local now=Plan101()
 C.setup(now.mirrorSlotLive==true and now.mirrorResolved==false,'M2: fixture: the mirror slot is now live with other contents',
  printable(now.mirrorSlotLive)..'/'..printable(now.mirrorResolved))
 WE.Show()
 -- The player acts on what the editor shows: the list if it is visible,
 -- otherwise a Manage click first.
 if not Visible() then Manage() end
 local row=MirrorRow()
 C.setup(row~=nil,'M2: fixture: the list shows the plan under index 101')
 local count=#A.RetainedWishlistPlans()
 H.popup=nil
 if row then row:Click() end
 local asked=V.Plain(H.popup and H.popup.which=='NEXUS_FORGET_WISHLIST' and H.popup.arg1 or '')
 C.setup(asked~='','M2: fixture: the removal asks for confirmation')
 print('OBSERVED','M2 confirmation='..asked:gsub('\n',' / '))
 C.expect(asked:find('still exists',1,true)~=nil and asked:find('only copy',1,true)==nil,
  'M2: the confirmation states the current server facts (the slot exists, holding other contents)',asked)
 C.guard(#A.RetainedWishlistPlans()==count,'M2: opening the confirmation removes nothing')
 StaticPopup_Hide('NEXUS_FORGET_WISHLIST')
end)

Scenario('M3','the editor\'s own Leaderboard button',function()
 if not Open('M3') then return end
 local board=V.Button(H,Editor(),'Leaderboard')
 C.setup(board~=nil,'M3: fixture: the editor\'s Leaderboard button exists')
 if not board then return end
 board:Click()
 C.setup(not Editor():IsShown(),'M3: fixture: the Leaderboard button closes the editor')
 C.expect(not Shown(),'M3: the Manage list closes with the editor')
 if Nexus.Leaderboard.IsShown() then Nexus.Leaderboard.Hide() end
end)

Scenario('G1','the public Toggle, a raw Hide of the closed editor, and the Manage button',function()
 if not Open('G1') then return end
 WE.Toggle()
 C.guard(not Editor():IsShown() and not Shown(),'G1: the public Toggle closes the editor and its list')
 local ok,err=pcall(Editor().Hide,Editor())
 C.guard(ok and not Editor():IsShown() and not Shown(),'G1: a raw Hide of the closed editor is harmless',err)
 WE.Toggle()
 C.guard(Editor():IsShown() and not Visible(),'G1: the public Toggle reopens the editor without the list')
 Manage()
 C.guard(Visible(),'G1: the Manage button opens the list')
 Manage()
 C.guard(not Shown(),'G1: and closes it again')
 Manage()
 C.setup(Visible(),'G1: fixture: a third Manage click opens the list again')
 WE.Toggle()
 C.guard(not Editor():IsShown() and not Shown(),'G1: the public Toggle closes the editor with the list the button opened')
 WE.Show()
 C.guard(Editor():IsShown() and not Visible(),'G1: reopening after the public Toggle shows no list')
end)

C.guard(#A.RetainedWishlistPlans()==2,'both plans are still retained',#A.RetainedWishlistPlans())
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the Manage list closes with the editor; a reopened editor needs a new Manage click)')
