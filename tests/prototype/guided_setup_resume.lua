-- Guided setup resume across a reload (the guided design's "GUIDE RECORD
-- (separate store, per character)", its R2 and R4 and "Character change"):
-- the coach keeps its own place for the character it belongs to, through the
-- sanctioned Store writer, and applies it once after a reload, while every
-- outcome is read again. An assignment confirmed before the reload is only
-- observed after it, Keep Auto is asked again, a kept Wishlist is taken again
-- only while Nexus lists it (a saved association still lists it after the
-- server slot is gone) and is dropped once it is listed nowhere, and a change
-- made by another route shows as it is now.
-- Also: another character's own place, an owner change in the session and
-- before the first resume, Close/Escape/Help reopen, replay, a record of
-- another version or with invalid or unknown fields, read-only (future and
-- malformed) saved data, and saved data still loading.
-- EXPECT: added behaviour. On the source base dfcca312 the guide keeps its
-- place in session memory only, so after a reload it starts at Welcome and the
-- kept-place EXPECTs fail there. S4's resume under another character and S7's
-- first resume after a loading-time read also fail on the reviewed partial
-- source (core/GuidedSetup.lua Recheck/Resume order) by design. GUARD: what
-- must already hold (no assignment, game action, send, Orb spend or Auto
-- change by the guide; every other saved byte unchanged; read-only saved data
-- byte-identical). SETUP: fixture state. Reloads are offline module reloads of
-- round-tripped literal saved data (format5_support F.Boot), not a client
-- /reload: native SavedVariables writing, reload timing and frames are
-- NOT RUN. Real TOC boot, coach, Echo Journal chooser, Help and adapter
-- writers; synthetic host services and saved data only. No native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('guided_setup_resume')
local H,A,G,writes,spends
local HOST={}
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity',
 'UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local NAMES={'ProjectEbonholdEchoJournal','EchoJournalMicroButton','NexusEditorFrame','NexusWishlistNameInput',
 'NexusActiveWishlistSelector','NexusWishlistOnlyPicker','NexusLoadoutAssociationPanel','NexusGuidedSetup',
 'NexusGuidedSetupEscape','NexusQuickStart','NexusQuickStartEscape','NexusHelpWindow','NexusSetupChecklist',
 'NexusOverwriteWarning','NexusOverwriteWarningScroll','NexusPanel'}
-- core/GuidedSetup.lua PLACE_KEY (S1 checks the module names it) and the
-- only fields its version-1 record may hold: no request, receipt, read back,
-- replacement acceptance or Keep Auto choice.
local KEY='guidedSetupPlaceV1'
local PLACE={version=true,step=true,path=true,skipped=true,manual=true,wishlist=true,target=true}
-- What S1 leaves for the later scenarios: its saved data, owner, the chosen
-- Wishlist key and the kept place.
local S1={}

local function Clear() for _,n in ipairs(NAMES) do _G[n]=nil end end
local function Ser(v) return F.Serialize(v) end
local function Copy(v) return assert(loadstring('return '..Ser(v)))() end

-- The synthetic host of every boot, before the TOC loads: two Saved Builds,
-- two server Wishlists, Saved Build 2 selected and a counted Orb service.
-- HOST.noFree: the server no longer lists W-Free. HOST.owner: another
-- character of the same account is logged in.
local function Host(h)
 h.playerLevel=80;wipe(h.db)
 h.AddEcho(201172,'Echo One',0,5);h.AddEcho(201173,'Echo Six',0,5)
 h.AddEcho(201174,'Echo Free',0,5);h.AddEcho(201175,'Echo Fire',0,5)
 h.service.GetServerMaxSlots=function() return 6 end
 local slots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 if HOST.noFree then slots[107]=nil end
 h.perks.serverBuildSlots=slots;h.perks.serverActiveSlot=2
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function() return true end,GetCharges=function() return 0 end,
  IsOfferPending=function() return false end,RequestCharges=function() end,
  ConfirmSpend=function() spends=spends+1;return false end}
 if HOST.owner then local name=HOST.owner;UnitName=function() return name,'Ebonhold' end end
end

local function Guide() return _G.NexusGuidedSetup end
local function Shown() local g=Guide();return g~=nil and g:IsShown() end
local function Find(exact,text)
 local g=Guide();if not g then return nil end
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local t=V.Plain(c:GetText() or '')
   if (exact and t==text) or (not exact and t:find(text,1,true)) then return c end
  end
 end
end
local function Btn(t) return Find(true,t) end
local function Opt(t) return Find(false,t) end
local function Press(b) if b then b:Click() end return b~=nil end
local function Text() return Guide() and V.Plain(Nexus.GuidedSetupUI.VisibleText() or '') or '' end
local function Step() return G and G.StepId() or nil end
local function St() return G.AssignStatus().state end
local function Kept() return G.PlaceKept() end
local function Stored(slot) local s=Nexus.Store.State();return s.loadoutWishlists and s.loadoutWishlists[slot] end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Quiet() return table.concat({#H.actions,#H.sent,spends,tostring(Auto())},'/') end
local function Effects() return Writes()..'/'..Quiet() end
-- One of the last chat lines holds text.
local function Chat(text)
 for i=#H.chat,math.max(1,#H.chat-3),-1 do if tostring(H.chat[i]):find(text,1,true) then return true end end
 return false
end
local function Row(name)
 local p=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(p and p.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
end
-- Help's primary Setup / Welcome, the design's reopen route.
local function HelpRoute()
 Nexus.Help.Show('start')
 local w=_G.NexusHelpWindow
 for _,c in ipairs(w and w.children or {}) do
  if c.kind=='Button' and c:IsShown() and V.Plain(c:GetText() or '')=='Setup / Welcome' then c:Click();return true end
 end
 return false
end

-- The owner's character row and the Store authority bundle's mirror of it.
-- While the session's bundle wrapper references the admitted chars table
-- (core/Store.lua StoreData.Build), both are the same table, so one record is
-- serialized twice; after a reload the mirror is a separate copy that the
-- guide does not write.
local function Rows(db,owner)
 local function Of(chars)
  local row=type(chars)=='table' and owner and rawget(chars,owner) or nil
  return type(row)=='table' and row or nil
 end
 local bundle=type(db)=='table' and rawget(db,'authorityBundle') or nil
 local data=type(bundle)=='table' and rawget(bundle,'storeData') or nil
 return Of(type(db)=='table' and rawget(db,'chars') or nil),Of(type(data)=='table' and rawget(data,'chars') or nil)
end
local function Place(owner)
 local row=Rows(NexusDB,owner or Nexus.Store.CurrentOwnerKey())
 return row and rawget(row,KEY) or nil
end
local function Saved() return type(NexusDB)=='table' and Ser(NexusDB) or tostring(NexusDB) end
-- Every saved byte except the owner's place record and its mirror, and those two.
local function Rest(owner)
 local copy=Copy(NexusDB)
 local row,mirror=Rows(copy,owner or Nexus.Store.CurrentOwnerKey())
 local place,mirrored=row and row[KEY],mirror and mirror[KEY]
 if row then row[KEY]=nil end
 if mirror then mirror[KEY]=nil end
 return Ser(copy),place,mirrored
end
local function Fields(t)
 local out={}
 for k in pairs(type(t)=='table' and t or {}) do out[#out+1]=tostring(k) end
 table.sort(out);return table.concat(out,',')
end
local function OnlyPlace(t)
 if type(t)~='table' then return false end
 for k in pairs(t) do if not PLACE[k] then return false end end
 return true
end

-- After a boot: the host read once, counted adapter writers, the Echo
-- Journal frames, and no window of the boot left open. A first-use coach is
-- closed once with its own Close (first use seen, an account-level flag), so
-- that later boots open nothing by themselves.
local function Settle(tag,readOnly)
 A,G=Nexus.GameAdapter,Nexus.GuidedSetup
 H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do local real=A[k]
  if type(real)=='function' then writes[k]=0;A[k]=function(...) writes[k]=writes[k]+1;return real(...) end end end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 if Shown() then Press(Btn('X')) end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
 local status=Nexus.Store.StateWriteStatus()
 local healthy=status.mode=='durable' and Nexus.StartupStatus().coreReady==true
 if readOnly then healthy=status.mode~='durable' end
 return C.setup(healthy and G~=nil and not Shown(),
  tag..': fixture: booted ('..(readOnly and 'read-only' or 'durable')..' saved data), no window open',status.mode)
end
local function Fresh(tag)
 HOST={};Clear();H=F.Boot(nil,Host)
 return Settle(tag)
end
-- A boot of saved data text (optionally changed first), as a reload starts.
local function From(tag,text,o)
 o=o or {}
 if not C.setup(type(text)=='string',tag..': fixture: the saved data S1 left') then return false end
 local db=assert(loadstring('return '..text))()
 if o.mutate then o.mutate(db) end
 HOST={owner=o.owner,noFree=o.noFree}
 Clear();H=F.Boot(db,Host,o.early)
 return Settle(tag,o.readOnly)
end
local function Reload(tag,o) return From(tag,Saved(),o) end

C.scenario('S1 the kept place outlasts a reload for its own character; every result is read again',function()
 if not Fresh('S1') then return end
 C.expect(G.PLACE_KEY==KEY,'S1: the guide names its one saved record',tostring(G.PLACE_KEY))
 local owner=Nexus.Store.CurrentOwnerKey()
 local quiet=Quiet()
 Nexus.GuidedSetupUI.Show()
 C.expect(Kept()=='saved','S1: a durable saved root of this character keeps the place',Kept())
 Press(Opt('I already have'));Press(Btn('Continue'));Press(Opt('W-Free'));Press(Btn('Continue'))
 Press(Opt('Fire PvE'));Press(Btn('Continue'))
 if not C.setup(Step()=='assign' and Press(Btn('Open the Wishlist chooser')),
  'S1: fixture: W-Free and Saved Build 2 chosen; the real chooser opened',Step()) then return end
 local row=Row('W-Free')
 if not C.setup(row~=nil,'S1: fixture: the chooser lists W-Free') then return end
 row.nameButton:Click()
 if not C.setup(Shown() and St()=='verified' and Writes()==1,
  'S1: fixture: one explicit assignment, confirmed by its own receipt and read back',St()) then return end
 local key=G.State().wishlist.key
 Press(Btn('Continue'));Press(Btn('Skip for now'));Press(Btn('Keep Auto OFF'))
 if not C.setup(Step()=='summary' and G.Summary().complete==true and G.State().autoKept=='off',
  'S1: fixture: at the summary, set up, Auto kept OFF',Step()) then return end
 local _,place,mirrored=Rest(owner)
 C.expect(OnlyPlace(place) and Fields(place)=='path,skipped,step,target,version,wishlist' and place.version==1
  and place.step=='summary' and place.path=='existing' and place.skipped=='manual' and place.wishlist==key and place.target==2,
  'S1: the kept place is the step, the path, the skipped step and the two choices; no request, receipt, read back or Keep Auto',Ser(place))
 C.guard(mirrored==nil or Ser(mirrored)==Ser(place),'S1: the authority bundle mirror holds this same record and nothing else',Ser(mirrored))
 C.guard(Writes()==1 and Quiet()==quiet,'S1: besides the player\'s one assignment nothing was written, acted, sent, spent or toggled',Effects())
 Press(Btn('X'))
 C.expect(not Shown() and Chat('It resumes at this step and checks every result again'),'S1: Close says where it resumes and that results are read again')
 C.guard(Ser(Place(owner))==Ser(place),'S1: closing writes nothing to the place')
 S1.text,S1.owner,S1.key,S1.place=Saved(),owner,key,Copy(place)

 if not Reload('S1 reload') then return end
 C.guard(Stored(2)~=nil and Stored(2).name=='W-Free' and not Auto(),'S1: after the reload the assignment and Auto OFF are the game\'s own saved state')
 C.expect(Kept()=='loading','S1: the guide binds nothing before it is shown',Kept())
 local before,rest=Effects(),Rest(owner)
 Nexus.GuidedSetupUI.Show()
 local s=G.State()
 C.expect(Kept()=='saved' and Step()=='summary' and s.path=='existing' and s.skipped.manual==true,
  'S1: reopening after the reload resumes at the kept step on the kept path, the skipped step still skipped',Step())
 C.expect(s.wishlist~=nil and s.wishlist.key==key and s.target~=nil and s.target.destination==2,
  'S1: the kept Wishlist and Saved Build are taken again from what Nexus lists now')
 C.expect(s.notice=='restored' and Text():find('Resumed where you left off',1,true)~=nil,
  'S1: the coach says it resumed and that each result is read again',Text())
 C.expect(St()=='observed' and s.request==nil,'S1: the assignment confirmed before the reload is only observed by a fresh read back',St())
 local sm=G.Summary()
 C.expect(sm.complete==false and sm.trueNow==true and sm.autoKept==nil and s.autoKept==nil,
  'S1: nothing the earlier session completed or kept is claimed: not complete, no Keep Auto')
 C.expect(Text():find('Read back; not changed by this guide',1,true)~=nil and Text():find('Confirmed by read back',1,true)==nil,
  'S1: the summary shows the assignment as read back now, not as confirmed by this guide',Text())
 G.GoTo('assign')
 C.expect(Text():find('Already linked.',1,true)~=nil and Text():find('Nexus confirmed it',1,true)==nil and G.CanNext(),
  'S1: the Assign step shows the link read back now, not the earlier confirmation',Text())
 G.GoTo('auto')
 C.expect(not G.CanNext() and Btn('Keep Auto OFF')~=nil and Text():find('Auto is OFF right now',1,true)~=nil,
  'S1: Auto is read now and Keep Auto is asked again',Text())
 local rest2,place2,mirrored2=Rest(owner)
 C.expect(OnlyPlace(place2) and place2.step=='auto' and place2.wishlist==key and place2.target==2,'S1: moving on keeps the new place',Ser(place2))
 C.guard(rest2==rest,'S1: showing and moving the resumed coach changes no other saved byte')
 C.guard(mirrored2==nil or Ser(mirrored2)==Ser(place2) or Ser(mirrored2)==Ser(S1.place),
  'S1: the authority bundle mirror holds this place or the one saved before, nothing else',Ser(mirrored2))
 C.guard(Effects()==before,'S1: the resumed coach assigned, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('S2 a kept Wishlist is taken again only while Nexus lists it; one it lists nowhere is dropped, never shown as chosen',function()
 -- The server no longer lists W-Free, but Saved Build 2 still holds the
 -- association S1 saved, and Nexus still offers that identity from it
 -- (core/GameAdapter.lua ReadWishlistCandidates): the guide takes it again as
 -- listed now, never as confirmed by the earlier session.
 if not From('S2 association',S1.text,{noFree=true}) then return end
 local quiet=Quiet()
 Nexus.GuidedSetupUI.Show()
 local s,sm=G.State(),G.Summary()
 C.expect(Kept()=='saved' and Step()=='summary' and s.target~=nil and s.target.destination==2,
  'S2: the place and the Saved Build still listed are resumed',Step())
 C.expect(s.wishlist~=nil and s.wishlist.key==S1.key and s.resume==nil and sm.wishlist=='done',
  'S2: a Wishlist Nexus still lists through its saved association is taken again',tostring(sm.wishlist))
 C.expect(sm.complete==false and sm.autoKept==nil and St()~='verified' and Text():find('Confirmed by read back',1,true)==nil,
  'S2: nothing the earlier session confirmed or kept is claimed',St())
 C.guard(Quiet()==quiet,'S2: no game action, send, Orb spend or Auto change',Quiet())
 -- Another route also removes that association: Nexus lists W-Free nowhere.
 if not From('S2 unlisted',S1.text,{noFree=true}) then return end
 if not C.setup(A.ClearLoadoutWishlist(2)==true and Stored(2)==nil,
  'S2: fixture: another route unassigns Saved Build 2 while the guide is closed') then return end
 local list,listed=G.WishlistOptions(),false
 for _,c in ipairs(list or {}) do if c.key==S1.key then listed=true end end
 if not C.setup(list~=nil and not listed,'S2: fixture: Nexus reads its Wishlists and lists W-Free nowhere') then return end
 local before=Effects()
 Nexus.GuidedSetupUI.Show()
 s,sm=G.State(),G.Summary()
 C.expect(Kept()=='saved' and Step()=='summary' and s.target~=nil and s.target.destination==2,
  'S2: the place and the Saved Build still listed are resumed without the Wishlist',Step())
 C.expect(s.wishlist==nil and s.resume==nil and sm.wishlist=='todo' and St()=='none',
  'S2: the Wishlist that is gone is dropped, not restored',tostring(sm.wishlist))
 C.expect(sm.complete==false and sm.trueNow==false and Text():find('Not finished',1,true)~=nil,
  'S2: the summary says setup is not finished',Text())
 C.guard(Effects()==before,'S2: the resumed coach assigned, wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('S3 Close, Escape and Help reopen keep the place; a later change is read as it is; replay resets only the guide',function()
 if not From('S3',S1.text) then return end
 local owner=S1.owner
 Nexus.GuidedSetupUI.Show()
 if not C.setup(Step()=='summary' and St()=='observed','S3: fixture: resumed at the summary, the assignment read back',St()) then return end
 local kept=Ser(Place(owner))
 Press(Btn('X'))
 C.expect(not Shown() and Chat('It resumes at this step and checks every result again') and Ser(Place(owner))==kept,
  'S3: Close keeps the place and says where it resumes')
 Nexus.GuidedSetupUI.Show()
 C.expect(Shown() and Step()=='summary' and G.State().wishlist~=nil and G.State().target~=nil,'S3: reopening resumes the same step and choices',Step())
 if _G.NexusGuidedSetupEscape then NexusGuidedSetupEscape:Hide() end
 C.expect(not Shown() and Ser(Place(owner))==kept,'S3: Escape closes as Close does and keeps the place')
 C.expect(HelpRoute() and Shown() and Step()=='summary' and not NexusHelpWindow:IsShown(),
  'S3: Help Setup / Welcome resumes the coach at the kept step',Step())
 C.guard(Ser(Place(owner))==kept,'S3: closing and reopening wrote nothing to the place')
 Press(Btn('X'))
 if not C.setup(A.ClearLoadoutWishlist(2)==true and Stored(2)==nil,'S3: fixture: another route unassigns Saved Build 2 while the guide is closed') then return end
 local before=Effects()
 Nexus.GuidedSetupUI.Show()
 local sm=G.Summary()
 C.expect(St()=='ready' and sm.assign=='todo' and sm.complete==false and sm.trueNow==false,
  'S3: the removed assignment is read as not assigned; nothing is claimed',St())
 C.expect(Text():find('Not finished: 1 step still open',1,true)~=nil,'S3: the summary counts the open step',Text())
 Press(Btn('Run the guide again'))
 local s=G.State()
 C.expect(Step()=='welcome' and s.path==nil and s.wishlist==nil and s.target==nil and next(s.skipped)==nil
  and Text():find('Welcome back',1,true)~=nil,'S3: replay starts again at Welcome with no choice',Step())
 local place=Place(owner)
 C.expect(Fields(place)=='step,version' and place.step=='welcome','S3: the replayed place is kept as Welcome and nothing else',Ser(place))
 C.guard(Effects()==before and Stored(2)==nil,'S3: reopening, reading and replay assigned, wrote, acted, sent, spent and toggled nothing',Effects())
 Press(Btn('X'))
 if not Reload('S3 reload') then return end
 Nexus.GuidedSetupUI.Show()
 s=G.State()
 C.expect(Step()=='welcome' and s.path==nil and s.wishlist==nil and s.target==nil,'S3: after a reload the replayed guide starts at Welcome',Step())
end)

C.scenario('S4 another character keeps its own place; an owner change writes no character\'s record',function()
 local ownerA,keptA=S1.owner,Ser(S1.place)
 if not From('S4',S1.text,{owner='SyntheticOther'}) then return end
 local ownerB=Nexus.Store.CurrentOwnerKey()
 if not C.setup(ownerB~=nil and ownerB~=ownerA and Ser(Place(ownerA))==keptA,
  'S4: fixture: another character of the account; the first character\'s record is saved',tostring(ownerB)) then return end
 local before=Effects()
 Nexus.GuidedSetupUI.Show()
 local s=G.State()
 C.expect(Kept()=='saved' and Step()=='welcome' and s.path==nil and s.wishlist==nil and s.target==nil,
  'S4: the other character starts its own guide; the first character\'s place is not applied',Step())
 Press(Opt('Just look around'));Press(Btn('Continue'))
 local placeB=Copy(Place(ownerB))
 C.expect(type(placeB)=='table' and placeB.step=='manual' and placeB.path=='explore','S4: its place is kept in its own row',Ser(placeB))
 C.guard(Ser(Place(ownerA))==keptA,'S4: the first character\'s record is left exactly as it was',Ser(Place(ownerA)))
 -- The identity reads as the first character while the guide is in use.
 Nexus.GuidedSetupUI.Hide()
 local realName=UnitName
 local ok,err=pcall(function()
  UnitName=function() return 'PrototypeTester','Ebonhold' end
  -- The owner notice lasts until the next navigation (core/GuidedSetup.lua
  -- GoTo clears it), so it is read straight after Recheck.
  G.Recheck()
  C.expect(Kept()=='session' and G.State().notice=='owner','S4: after an owner change the coach says so and keeps the place for this session only',Kept())
  local moved=G.GoTo('auto')
  C.expect(moved and Step()=='auto' and Kept()=='session' and Ser(Place(ownerA))==keptA and Ser(Place(ownerB))==Ser(placeB),
   'S4: moving on after the change stays session-only and writes neither character\'s record',Kept())
 end)
 UnitName=realName
 C.setup(ok,'S4: fixture: the owner-change probe ran',err)
 G.Recheck();G.Back()
 C.expect(Kept()=='session' and Ser(Place(ownerB))==Ser(placeB),'S4: reading the second character again does not bind the guide again',Kept())
 C.guard(Effects()==before,'S4: no assignment, game action, send, Orb spend or Auto change',Effects())
 -- A guide used by the second character before its first resume, then
 -- first resumed while the identity reads as the first character.
 if not Reload('S4 reload',{owner='SyntheticOther'}) then return end
 placeB=Copy(Place(ownerB))
 G.State();G.SetPath('new')
 C.setup(Kept()=='loading','S4: fixture: the guide was used before its first resume',Kept())
 realName=UnitName
 local kind
 ok,err=pcall(function()
  UnitName=function() return 'PrototypeTester','Ebonhold' end
  G.Recheck();kind=G.Resume()
 end)
 UnitName=realName
 C.setup(ok,'S4: fixture: the pre-resume owner-change probe ran',err)
 C.expect(kind=='session' and Ser(Place(ownerA))==keptA and Ser(Place(ownerB))==Ser(placeB),
  'S4: a place made under one character is never written into another character\'s row',tostring(kind)..' '..Ser(Place(ownerA)))
end)

for _,case in ipairs({{'future',function(db) db.settingsVersion=6 end},{'malformed',function(db) db.settingsVersion={version=5} end}}) do
 C.scenario('S5 '..case[1]..' saved data is read-only: the place lasts this session only and nothing is written',function()
  local tag='S5 '..case[1]
  -- A place record in the character's own row, as a newer or other build may leave it.
  local db=F.Database({mutate=function(d) case[2](d);d.chars[F.NAME][KEY]={version=1,step='manual',path='explore'} end})
  HOST={};Clear();H=F.Boot(db,Host)
  if not Settle(tag,true) then return end
  local saved,before=Saved(),Effects()
  Nexus.GuidedSetupUI.Show()
  C.expect(Kept()=='session' and Step()=='welcome','S5: a place in read-only saved data is not applied; the guide keeps its place for this session',Kept())
  C.expect(Guide().close.tip==Nexus.UserText.Guide.buttons.closeTipSession,'S5: Close says the place lasts until a reload',tostring(Guide().close.tip))
  Press(Opt('Just look around'));Press(Btn('Continue'));Press(Btn('X'))
  C.expect(Chat('your place is kept only until you reload or log out'),'S5: the close line says the place is kept for this session only')
  Nexus.GuidedSetupUI.Show()
  C.expect(Step()=='manual','S5: within the session the coach still resumes its step',Step())
  Nexus.GuidedSetupUI.Replay();Press(Btn('X'))
  C.guard(Saved()==saved,'S5: showing, moving, closing, reopening and replay leave the saved data byte-identical')
  C.guard(Effects()==before,'S5: no assignment, game action, send, Orb spend or Auto change',Effects())
 end)
end

C.scenario('S6 a record of another version is never read or written; a version-1 record keeps unknown fields and drops invalid values',function()
 local owner=S1.owner
 local foreign={version=2,step='assign',path='existing',wishlist=S1.key,target=2,future={keep='newer'}}
 if not From('S6 foreign',S1.text,{mutate=function(db) db.chars[owner][KEY]=Copy(foreign) end}) then return end
 local kept=Ser(Place(owner))
 Nexus.GuidedSetupUI.Show()
 C.expect(Kept()=='session' and Step()=='welcome' and G.State().wishlist==nil,'S6: a record of another version is not read as a place',Kept())
 Press(Opt('Just look around'));Press(Btn('Continue'));Press(Btn('X'))
 C.expect(Ser(Place(owner))==kept,'S6: nor written: it is left exactly as it is',Ser(Place(owner)))
 local odd={version=1,step='bogus',path='existing',target=9999,wishlist=string.rep('w',200),
  skipped='manual,welcome,nope',manual=7,later={keep='me'}}
 if not From('S6 odd',S1.text,{mutate=function(db) db.chars[owner][KEY]=Copy(odd) end}) then return end
 Nexus.GuidedSetupUI.Show()
 local s=G.State()
 C.expect(Kept()=='saved' and Step()=='welcome' and s.path=='existing' and s.skipped.manual==true and s.skipped.welcome==nil
  and s.manualAck==false and s.wishlist==nil and s.target==nil,'S6: invalid values in a version-1 record are dropped, never applied',Step())
 Press(Btn('Continue'))
 local place=Place(owner)
 C.expect(type(place)=='table' and place.version==1 and place.step=='wishlist' and place.path=='existing'
  and type(place.later)=='table' and place.later.keep=='me' and place.target==nil and place.wishlist==nil,
  'S6: moving on keeps its unknown fields and writes only valid place fields',Ser(place))
end)

C.scenario('S7 while saved data is loading the guide binds and writes nothing; once ready it resumes',function()
 local owner=S1.owner
 local seen={}
 local function Early()
  seen.mode=Nexus.Store.StateWriteStatus().mode
  seen.kind=Nexus.GuidedSetup.Resume()
 end
 if not From('S7',S1.text,{early=Early}) then return end
 C.setup(seen.mode=='loading','S7: fixture: the guide was first read while saved data was loading',tostring(seen.mode))
 C.expect(seen.kind=='loading','S7: while loading it is not bound',tostring(seen.kind))
 Nexus.GuidedSetupUI.Show()
 local s=G.State()
 C.expect(Kept()=='saved' and Step()=='summary' and s.wishlist~=nil and s.wishlist.key==S1.key
  and s.target~=nil and s.target.destination==2,'S7: once ready it resumes the kept place and takes its choices again',Step())
 C.expect(St()=='observed' and G.Summary().complete==false,'S7: and reads the assignment again',St())
 local probe={}
 local function Touch()
  local g=Nexus.GuidedSetup
  probe.mode=Nexus.Store.StateWriteStatus().mode
  probe.before=Ser(Place(owner))
  probe.kind=g.Resume();g.SetPath('explore');g.GoTo('manual')
  probe.after=Ser(Place(owner))
 end
 if not From('S7 touched',S1.text,{early=Touch}) then return end
 C.setup(probe.mode=='loading','S7: fixture: the guide was moved while saved data was loading',tostring(probe.mode))
 C.expect(probe.kind=='loading' and probe.after==probe.before,'S7: moving the guide while loading writes nothing',probe.after)
 C.expect(G.Resume()=='saved' and Kept()=='saved','S7: once ready it binds to this character',Kept())
 local place=Place(owner)
 C.expect(type(place)=='table' and place.path=='explore' and place.step=='manual' and place.wishlist==nil and place.target==nil,
  'S7: the place made this session is the one kept, with no earlier choice',Ser(place))
end)

C.finish('(guide place kept per character across an offline reload; outcomes read again; read-only, foreign and loading kept session-only; native reload NOT_RUN)')
