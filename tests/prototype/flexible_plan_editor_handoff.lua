-- #47 session chooser and atomic new-draft handoff, real TOC/public callbacks.
-- Synthetic catalog/host only. No native UI claim.
local H = dofile('tests/prototype/harness.lua')
-- Record root-window paint calls at the synthetic host boundary. The real
-- Theme helper must paint the chooser; a styled-button tree alone is not a
-- window surface over the editor beneath it. A pool row's EnableMouse is
-- recorded too: the row owns the tooltip of its one-line label.
-- A frame placed directly on the chooser records its EnableMouse and the
-- region SetAllPoints anchors it to, as the client anchors it (that region's
-- TOPLEFT and BOTTOMRIGHT), so a fixed-text hover area is found by the
-- rendered label it covers.
local createFrame=CreateFrame
CreateFrame=function(kind,name,parent,template)
    local frame=createFrame(kind,name,parent,template)
    if name=='NexusEditorFrame' or name=='NexusFlexiblePlanChooser' then
        frame.SetBackdrop=function(self,value) self.drawnBackdrop=value end
        frame.SetBackdropColor=function(self,...) self.drawnFill={...} end
        frame.SetBackdropBorderColor=function(self,...) self.drawnBorder={...} end
    end
    if type(parent)=='table' and parent.name=='NexusFlexiblePlanPool' then
        frame.EnableMouse=function(self,enabled) self.recordedMouse=enabled end
    end
    if type(parent)=='table' and parent.name=='NexusFlexiblePlanChooser' then
        frame.EnableMouse=function(self,enabled) self.recordedMouse=enabled end
        frame.SetAllPoints=function(self,region)
            region=region or self:GetParent()
            self.coveredRegion=region
            self.points={{'TOPLEFT',region,'TOPLEFT',0,0},{'BOTTOMRIGHT',region,'BOTTOMRIGHT',0,0}}
        end
    end
    return frame
end
wipe(H.db)
local function EchoName(i) return (i==22 or i==23) and 'Exact variants' or 'Choice '..i end
for i=1,257 do H.AddEcho(410000+i,EchoName(i),i%4,5,(i==22 or i==23) and 77 or 0) end
-- One more exact Echo, whose name is wider than a pool row label.
local LONG_ID=419001
H.AddEcho(LONG_ID,'Exceptionally Long Exact Echo Name For Picker Row Tooltips',2,5,0)
H.locked={{spellId=410022,stacks=1}}
H.Boot()
local checks = 0
local function check(value, message) assert(value, message); checks=checks+1 end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local catalog, ids = {rows={}}, {}
for i=1,257 do
    local id=410000+i; ids[i]=id
    catalog.rows[id]={spellId=id,name=EchoName(i),quality=i%4,maxStack=5,groupId=(i==22 or i==23) and 77 or 0}
end
local exact = Nexus.WishlistModel.New()
local retained={lockDesignTargetsBySlot={matching={[ids[22]]=true}}}
local account={lockDesignTargets={[ids[23]]=true}}
local controller = Nexus.WishlistInternals.Controller.New({model=exact,accountRoot=function()return account end,
    store={State=function() return retained end,Settings=function() return {} end}})
local actions,uploads=0,0
controller.Initialize({Catalog=function() return catalog end,
    AssignmentActionSnapshot=function() actions=actions+1;return {} end,
    UploadWishlist=function() uploads=uploads+1;return true end,
    WishlistKey=function()return 'matching' end,
    Slots=function() return {activeSlot=0,bySlot={}} end})
controller.BeginNewWishlist()
controller.AddPending(catalog.rows[ids[1]])
local hundred, selection, manual = {}, {}, {}
for i=1,100 do hundred[i]=ids[i] end
for i=22,100 do
    selection[#selection+1]={spellId=ids[i],stacks=1}
    manual=exact.AddPending(manual,catalog.rows[ids[i]],{catalog=catalog})
end
local pool=assert(Nexus.FlexiblePlanModel.New({alternativeSpellIds=hundred,catalog=catalog}))
local draft=assert(pool.Choose(selection))
check(#exact.CanonicalEchoes(manual)==79, 'CONTROL ordinary manual exact79')
print('CONTROL ordinary manual exact79 PASS')
check(type(controller.PrepareNewExactDraft)=='function',
    'EXPECT atomic public exact draft handoff is available')
local intent=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
check(controller.PendingTotal()==1, 'preparation preserves previous draft')
check(intent.replaces==true, 'existing draft requires explicit replacement')
check(intent.Install(), 'validated intent installs exact draft')
check(equal(controller.CanonicalEchoes(),exact.CanonicalEchoes(manual)),
    'installed last79 match independent ordinary manual control')
check(controller.PendingTotal()==79 and next(controller.PendingLockRows())==nil
    and next(controller.FulfilledDraftTargets())==nil, 'ordinary exact maps installed')
local afterActions=actions
check(not intent.Install() and actions==afterActions, 'an install can reset new context only once')
local detachedDraft=assert(pool.Choose({{spellId=ids[22],stacks=3},{spellId=ids[23],stacks=2}}))
local alternatives=pool.Alternatives()
local detachedIntent=assert(controller.PrepareNewExactDraft(detachedDraft,alternatives))
detachedDraft.pending['exact:'..ids[22]].stacks=5
detachedDraft.echoes[1].stacks=5;alternatives[22].quality=99
check(detachedIntent.Install(),'caller mutations cannot change prepared exact draft')
check(controller.PendingRows()['exact:'..ids[22]].stacks==3
    and controller.PendingRows()['exact:'..ids[23]].stacks==2,'exact explicit counts remain detached')
local oldMap=controller.PendingRows()
local oldDebug=H.Clone(controller.DebugDraftState())
local function Preserve(label)
    check(controller.PendingRows()==oldMap and equal(controller.DebugDraftState(),oldDebug),label..' preserves prior maps/context')
end
local function BadDraft(change,label,code)
    local bad=assert(pool.Choose(selection));change(bad)
    local value,why=controller.PrepareNewExactDraft(bad,pool.Alternatives())
    check(value==nil and (not code or why==code),label..' refuses ('..tostring(why)..')')
    Preserve(label)
end
BadDraft(function(d) d.echoes={} end,'empty')
BadDraft(function(d) d.echoes[1].spellId=ids[101] end,'nonmember','NOT_IN_POOL')
BadDraft(function(d) d.echoes[2].spellId=d.echoes[1].spellId end,'duplicate','DUPLICATE_SELECTION')
BadDraft(function(d) d.echoes[1].stacks=2 end,'80-copy budget','ORDINARY_LIMIT')
BadDraft(function(d) d.echoes[1].stacks=6 end,'over-stack','STACK_LIMIT')
BadDraft(function(d) d.echoes[1].stacks='1' end,'string count')
BadDraft(function(d) d.echoes[1].stacks=0/0 end,'NaN count')
BadDraft(function(d) d.pending['exact:'..ids[22]].quality=7 end,'pending quality mismatch')
BadDraft(function(d) d.pending['exact:'..ids[22]].lockIntent=false end,'pending role field false')
BadDraft(function(d) d.pendingLock.a={spellId=ids[22]} end,'locked sidecar')
BadDraft(function(d) d.fulfilledTargets[ids[22]]=true end,'fulfilled sidecar')
BadDraft(function(d) d.echoes[1].locked=false end,'echo role field false')
BadDraft(function(d) d.echoes[80]=d.echoes[1] end,'80 rows')
BadDraft(function(d) d.echoes[1]=nil end,'sparse')
BadDraft(function(d) d.extra=true end,'unknown draft field')
local calls=0
BadDraft(function(d) setmetatable(d,{__pairs=function() calls=calls+1 end,__index=function()calls=calls+1 end}) end,'metatable')
check(calls==0,'malformed draft metamethods are not invoked')
local badAlternatives=pool.Alternatives();badAlternatives[1].spellId=0/0
local safe,value=pcall(controller.PrepareNewExactDraft,draft,badAlternatives)
check(safe and value==nil,'EXPECT NaN alternative refuses without raising or mutating')
Preserve('NaN alternative')
for _,field in ipairs({'quality','maxStack','groupId','spellId','sourceRole'}) do
    local old=catalog.rows[ids[22]][field]
    catalog.rows[ids[22]][field]=field=='sourceRole' and 'ordinary' or (tonumber(old) or 0)+1
    local refused,why=controller.PrepareNewExactDraft(draft,pool.Alternatives())
    check(refused==nil and why=='CATALOG_CHANGED','changed catalog '..field..' refuses')
    Preserve('changed '..field)
    catalog.rows[ids[22]][field]=old
end
local oldRow=catalog.rows[ids[22]];catalog.rows[ids[22]]=nil
check(controller.PrepareNewExactDraft(draft,pool.Alternatives())==nil,'absent chosen catalog row refuses')
catalog.rows[ids[22]]=oldRow;Preserve('absent catalog')
local current=catalog;catalog=nil
check(controller.PrepareNewExactDraft(draft,pool.Alternatives())==nil,'catalog loading refuses without refresh')
catalog=current;Preserve('catalog loading')
local rename=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
catalog.rows[ids[22]].name='Cosmetic name'
check(rename.Install(),'optional name change does not change exact chosen identity')
catalog.rows[ids[22]].name=EchoName(22)
local passive=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
controller.ReconcileLocked({})
check(passive.Install(),'EXPECT passive no-op reconciliation keeps unchanged editor intent current')
check(#controller.ExportEntries()==79 and account.lockDesignTargets[ids[23]]==true
    and retained.lockDesignTargetsBySlot.matching[ids[22]]==true,
    'matching retained/flat sidecars neither resurrect nor migrate into exact new draft')
check(controller.BeginWishlist({slot=101,name='Existing plan',echoes={{spellId=ids[1],quality=1,stacks=1,locked=false}},designTargets={}},2),
    'existing editor context control opens')
local oldContext=controller.EditingContext()
local oldTarget=controller.CreateTargetContext()
local confirmation=assert(controller.PrepareApply('Ignored opened name','saveChanges'))
local confirmationBytes=H.Clone(confirmation)
local invalid=H.Clone(draft);invalid.echoes[1].locked=true
check(controller.PrepareNewExactDraft(invalid,pool.Alternatives())==nil
    and equal(controller.EditingContext(),oldContext) and equal(controller.CreateTargetContext(),oldTarget)
    and equal(confirmation,confirmationBytes), 'refusal preserves opened identity/destination/name and save confirmation')
local pendingIntent=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
check(equal(controller.EditingContext(),oldContext) and controller.CancelApply(confirmation),
    'preparation preserves exact existing active save confirmation identity')
check(not pendingIntent.Install(),'later cancellation of save intent makes old replacement stale')
local toReplace=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
check(toReplace.Install() and controller.EditingContext()==nil and controller.CandidateContext()==nil
    and controller.PendingApply()==nil,'successful handoff retires existing edit/candidate/retry context')
local lateIntent=assert(controller.PrepareNewExactDraft(draft,pool.Alternatives()))
controller.BeginNewWishlist();controller.AddPending(catalog.rows[ids[3]])
check(not lateIntent.Install() and controller.CanonicalEchoes()[1].spellId==ids[3],
    'stale controller confirmation cannot overwrite later draft')
check(uploads==0,'controller preparation/refusal/install sends no upload')

-- Synthetic StaticPopup boundary, original to this fixture; the shared
-- harness stays untouched. It models one supplied scalar only: after the
-- accept button, a true OnAccept return keeps that dialog shown and nil or
-- false lets the click hide it. Each dialog is tracked by its own `which`,
-- so hiding one confirmation never hides another. Cancel is modelled as
-- OnCancel then hide, and OnShow is not run. Native StaticPopup frames,
-- reuse, timing and the installed client version are not modelled (NOT_RUN).
local REPLACE,CREATE='NEXUS_FLEXIBLE_PLAN_REPLACE','WISHLISTREALIZER_CREATE_WISHLIST'
local Popup={shown={},hidden={}}
function StaticPopup_Show(which,a,b,data)
    local record={which=which,data=data,arg1=a,arg2=b,frame={which=which,data=data}}
    Popup.shown[which]=record
    return record.frame
end
function StaticPopup_Hide(which,data)
    local record=Popup.shown[which]
    if record and (data==nil or record.data==data) then
        Popup.shown[which]=nil
        Popup.hidden[which]=(Popup.hidden[which] or 0)+1
    end
end
function Popup.Click(record,button)
    assert(record and Popup.shown[record.which]==record,'only a shown dialog can be clicked')
    local dialog,keep=StaticPopupDialogs[record.which],nil
    if button==2 then
        if dialog.OnCancel then dialog.OnCancel(record.frame,record.data) end
    elseif dialog.OnAccept then
        keep=dialog.OnAccept(record.frame,record.data)
    end
    if not keep and Popup.shown[record.which]==record then StaticPopup_Hide(record.which) end
end
local function Hidden(which) return Popup.hidden[which] or 0 end
StaticPopupDialogs.NEXUS_TEST_POPUP_CONTROL={OnAccept=function(_,data) return data.value end}
local function ControlKeeps(value)
    StaticPopup_Show('NEXUS_TEST_POPUP_CONTROL',nil,nil,{value=value})
    Popup.Click(Popup.shown.NEXUS_TEST_POPUP_CONTROL,1)
    local kept=Popup.shown.NEXUS_TEST_POPUP_CONTROL~=nil
    StaticPopup_Hide('NEXUS_TEST_POPUP_CONTROL')
    return kept
end
check(ControlKeeps(true) and ControlKeeps('kept'),
    'CONTROL synthetic popup keeps a dialog whose accept returns a true value')
check(not ControlKeeps(nil) and not ControlKeeps(false),
    'CONTROL synthetic popup dismisses a dialog whose accept returns nil or false')
StaticPopup_Show('NEXUS_TEST_POPUP_CONTROL',nil,nil,{});StaticPopup_Show(CREATE,nil,nil,{})
StaticPopup_Hide(CREATE)
check(Popup.shown.NEXUS_TEST_POPUP_CONTROL~=nil and Popup.shown[CREATE]==nil,
    'CONTROL hiding one dialog leaves another shown')
StaticPopup_Hide('NEXUS_TEST_POPUP_CONTROL');StaticPopupDialogs.NEXUS_TEST_POPUP_CONTROL=nil
Popup.hidden={}
print('CONTROL synthetic popup accept-return model PASS')

local editor=Nexus.WishlistEditor
Nexus.WishlistEditor.NewWishlist()
check(NexusFlexiblePlanEntry ~= nil, 'EXPECT reachable session chooser entry in actual editor')
NexusFlexiblePlanEntry:Click()
check(NexusFlexiblePlanChooser and NexusFlexiblePlanChooser:IsShown(),
    'actual production entry callback opens chooser')
local theme,chooser=Nexus.Theme,NexusFlexiblePlanChooser
local function RootTextures(window)
    local count=0
    for _,region in ipairs(window.regions) do
        if region:GetObjectType()=='Texture' then count=count+1 end
    end
    return count
end
check(NexusEditorFrame:IsShown() and NexusEditorFrame.drawnBackdrop
    and NexusEditorFrame.drawnFill[4]==0.96,'CONTROL existing editor beneath chooser has themed window surface')
print('CONTROL existing editor beneath chooser has themed surface PASS')
check(chooser.drawnBackdrop==theme.STYLES.vista.windowBackdrop
    and chooser.drawnFill and chooser.drawnFill[4]==0.96
    and RootTextures(chooser)>0,
    'EXPECT reachable chooser paints a themed root background above the visible editor')
check(chooser:GetFrameStrata()==NexusEditorFrame:GetFrameStrata()
    and chooser:GetFrameLevel()>NexusEditorFrame:GetFrameLevel(),
    'chooser window surface is above the preserved visible editor')
local rootTextureCount,themeTextures=RootTextures(chooser),theme.Stats().textures
local rootBackdrop,rootShade=chooser.drawnBackdrop,chooser._nexusWindowShade
NexusFlexiblePlanHide:Click();NexusFlexiblePlanEntry:Click()
check(chooser==NexusFlexiblePlanChooser and chooser:IsShown() and NexusEditorFrame:IsShown()
    and chooser.drawnBackdrop==rootBackdrop and chooser._nexusWindowShade==rootShade,
    'Hide/reopen retains the chooser surface and the editor beneath')
check(RootTextures(chooser)==rootTextureCount and theme.Stats().textures==themeTextures,
    'Hide/reopen allocates no additional root or themed textures')
-- Simulate a changed read-only settings projection, then invoke the public
-- repaint path; the chooser does not gain a new preference-writing route.
local settingsProvider=Nexus.Store.Settings
local paletteSettings=H.Clone(settingsProvider())
paletteSettings.uiPalette='emerald'
Nexus.Store.Settings=function() return paletteSettings end
theme.Refresh();theme.Reapply()
check(chooser.drawnBorder and chooser.drawnBorder[1]==theme.PALETTES.emerald.windowBorder[1]
    and chooser.drawnBorder[2]==theme.PALETTES.emerald.windowBorder[2]
    and chooser.drawnBorder[3]==theme.PALETTES.emerald.windowBorder[3],
    'existing palette repaint path updates the chooser root window border')
check(RootTextures(chooser)==rootTextureCount and theme.Stats().textures==themeTextures,
    'palette repaint reuses existing root and themed textures')
Nexus.Store.Settings=settingsProvider
theme.Refresh()
check(chooser.drawnBorder[1]==theme.PALETTES.amethyst.windowBorder[1]
    and chooser.drawnBorder[2]==theme.PALETTES.amethyst.windowBorder[2],
    'restoring the existing settings projection repaints the original palette')
local function VisibleRow(area,id)
    for _,f in ipairs(H.frames) do
        if f:GetParent()==area and f:IsVisible() and f.spellId==id then return f end
    end
end
local function PoolRow(id)
    local area=NexusFlexiblePlanPool
    area:GetScript('OnMouseWheel')(area,1000)
    for _=1,257 do
        local row=VisibleRow(area,id)
        if row then return row end
        area:GetScript('OnMouseWheel')(area,-1)
    end
    error('visible pool row absent '..id)
end
local function Add(id)
    NexusFlexiblePlanSearch:SetText(tostring(id))
    local row=assert(VisibleRow(NexusFlexiblePlanCatalog,id),'catalog row exists')
    return row.action:Click()
end
local function Count(id,count)
    local row=PoolRow(id);row.count:SetText(tostring(count));return row.action:Click()
end
local function ChooserText()
    local out={};for _,r in ipairs(NexusFlexiblePlanChooser.regions) do out[#out+1]=r:GetText() end
    return table.concat(out,' | ')
end
-- The chooser's own status line: the FontString it anchors at its status
-- position. Its static help also says "pending", so the whole-window text
-- above cannot tell a pending status from that help.
local function Status()
    local found
    for _,r in ipairs(NexusFlexiblePlanChooser.regions) do
        local p=r.kind=='FontString' and r.points[1]
        if p and p[1]=='TOPLEFT' and p[2]==22 and p[3]==-570 then
            assert(found==nil,'one chooser status region');found=r
        end
    end
    return assert(found,'chooser status region exists'):GetText()
end
local Reason=Nexus.FlexiblePlanChooser.Reason
local function Rendered()
    local gathered, area = {}, nil
    for _,f in ipairs(H.frames) do if f.plus and f.data and f:IsVisible() then area=f:GetParent();break end end
    if not area then return {} end
    area:GetScript('OnMouseWheel')(area,1000)
    for _=1,80 do
        for _,f in ipairs(H.frames) do
            if f:GetParent()==area and f:IsVisible() and f.data and not f.data.ghost then
                local d=f.data
                gathered[d.spellId]={spellId=d.spellId,quality=d.quality,stacks=d.stacks}
            end
        end
        area:GetScript('OnMouseWheel')(area,-1)
    end
    local rows={};for _,r in pairs(gathered) do rows[#rows+1]=r end
    table.sort(rows,function(a,b)return a.spellId<b.spellId end);return rows
end
local actionBaseline,sentBaseline=#H.actions,#H.sent
local storeBaseline=H.Clone(NexusDB)
-- C1a: real count input, Set, Open and original popup acceptance. Only new
-- EXPECTs collect failures so every mismatch path runs on the unchanged a58.
do
    local failures={}
    local function expect(value,label)
        print('C1a '..(value and 'PASS ' or 'FAIL ')..label)
        if not value then failures[#failures+1]=label end
        checks=checks+1
    end
    local function snapshot()
        return {state=H.Clone(editor.DebugDraftState()),rows=Rendered(),name=NexusWishlistNameInput:GetText(),
            db=H.Clone(NexusDB),held=H.Clone(H.locked),actions=#H.actions,sends=#H.sent}
    end
    local function preserved(before) return equal(snapshot(),before) end
    local function start()
        editor.NewWishlist();NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
        for i=1,13 do check(Add(ids[i]),'C1a setup exact pool member '..i) end
        check(Count(ids[1],1),'C1a setup explicitly committed one')
    end
    start()
    local before=snapshot()
    check(not Count(ids[1],6),'C1a setup real max5 rejection')
    expect(PoolRow(ids[1]).count:GetText()=='6' and PoolRow(ids[1]).label:GetText():find('Set: 1',1,true)
        and Status():find('pending',1,true),'rejected6 visibly distinct from committed1')
    expect(Status()==Reason('STACK_LIMIT')..' '..Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'rejected6 status names the refusal and the pending input; its row shows Set *')
    local opened=NexusFlexiblePlanOpen:Click()
    expect(not opened and preserved(before) and Popup.shown[REPLACE]==nil,
        'rejected6 Open refuses rather than silently installing committed1')
    expect(Status()==Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'rejected6 Open status says only that count input is pending')
    -- Restore the public view after the known a58 mis-install so later real
    -- paths still run; this is setup, not an EXPECT failure or product stub.
    editor.NewWishlist();NexusFlexiblePlanEntry:Click()
    check(Count(ids[1],1),'C1a explicit Set restores one after rejection')
    local restored=PoolRow(ids[1])
    expect(restored.action:GetText()=='Set' and Status()=='' and restored.count:GetText()=='1'
        and restored.label:GetText():find('Set: 1',1,true),'explicit Set clears the Set * marker and the status exactly')
    before=snapshot()
    PoolRow(ids[1]).count:SetText('2')
    NexusFlexiblePlanSearch:SetText('unrelated refresh')
    NexusFlexiblePlanPool:GetScript('OnMouseWheel')(NexusFlexiblePlanPool,-1000)
    local rebound=VisibleRow(NexusFlexiblePlanPool,ids[13])
    check(rebound and rebound.count:GetText()=='0','C1a control recycled row binds another unchosen member')
    NexusFlexiblePlanHide:Click();NexusFlexiblePlanEntry:Click()
    expect(PoolRow(ids[1]).count:GetText()=='2' and PoolRow(ids[1]).label:GetText():find('Set: 1',1,true),
        'valid unsubmitted2 survives refresh scroll rebind hide reopen as pending')
    expect(Status()==Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'valid unsubmitted2 keeps the pending status and Set * through refresh, rebind and reopen')
    opened=NexusFlexiblePlanOpen:Click()
    expect(not opened and preserved(before),'pending valid2 Open preserves complete editor and protected effects')
    editor.NewWishlist();NexusFlexiblePlanEntry:Click()
    check(Count(ids[1],2),'C1a explicit Set2 accepted')
    NexusFlexiblePlanOpen:Click()
    if Popup.shown[REPLACE] then Popup.Click(Popup.shown[REPLACE],1) end
    expect(equal(Rendered(),{{spellId=ids[1],quality=1,stacks=2}}) and editor.DebugPendingCount()==1,
        'only explicit accepted Set2 installs literal exact2 ordinary row')
    -- A real nonempty named editor, not a stub openDraft callback.
    NexusWishlistNameInput:SetText('C1a keep exact2')
    NexusFlexiblePlanEntry:Click();check(Count(ids[1],1),'C1a clean explicit choice for popup')
    NexusFlexiblePlanOpen:Click()
    local request=assert(Popup.shown[REPLACE],'C1a production replacement request exists')
    before=snapshot()
    PoolRow(ids[1]).count:SetText('2')
    Popup.Click(request,1)
    expect(preserved(before) and Popup.shown[REPLACE]==nil and PoolRow(ids[1]).count:GetText()=='2'
        and Status():find('pending',1,true),'typed-after-popup accept refuses with editor and pending counts intact')
    expect(Status()==Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'typed-after-popup refusal status says count input is pending; its row shows Set *')
    NexusFlexiblePlanEntry:Click();NexusWishlistNameInput:SetText('C1a keep exact2')
    check(Count(ids[1],1),'C1a explicit restoration for rejected popup control')
    NexusFlexiblePlanOpen:Click();request=assert(Popup.shown[REPLACE])
    before=snapshot();check(not Count(ids[1],6),'C1a popup rejected6 setup')
    Popup.Click(request,1)
    expect(preserved(before) and PoolRow(ids[1]).count:GetText()=='6',
        'rejected-after-popup accept refuses without implicit Set or protected effects')
    expect(Status()==Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'rejected-after-popup refusal status says count input is pending; its row shows Set *')
    NexusFlexiblePlanEntry:Click();NexusWishlistNameInput:SetText('C1a keep exact2')
    check(Count(ids[1],1),'C1a clean count before edited-and-restored request')
    NexusFlexiblePlanOpen:Click();request=assert(Popup.shown[REPLACE]);before=snapshot()
    PoolRow(ids[1]).count:SetText('2');PoolRow(ids[1]).count:SetText('1')
    Popup.Click(request,1)
    expect(preserved(before),'editing then restoring text still invalidates older popup context')
    expect(Status()==Reason('PLAN_CHANGED') and PoolRow(ids[1]).action:GetText()=='Set',
        'edited-and-restored count clears its marker; the older request reports the changed choice')
    NexusFlexiblePlanEntry:Click();NexusWishlistNameInput:SetText('C1a keep exact2')
    check(Count(ids[1],1),'C1a restore one before clean accepted popup')
    NexusFlexiblePlanOpen:Click();request=assert(Popup.shown[REPLACE])
    Popup.Click(request,1)
    expect(equal(Rendered(),{{spellId=ids[1],quality=1,stacks=1}}) and NexusWishlistNameInput:GetText()=='',
        'fresh popup after explicit Set1 installs literal exact1')
    editor.NewWishlist();NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
    print('C1a completed real paths; failures='..#failures)
    assert(#failures==0,'EXPECT C1a count consistency: '..table.concat(failures,'; '))
end

-- Pool-row text layout (docs/UI_TEXT_LAYOUT.md) on the real chooser rows and
-- the real LayoutMetrics, measured with the offline font models of
-- layout_geometry_support (a regression aid, not native font measurement).
-- Setup controls must pass first; only the new EXPECTs collect failures, so
-- the committed-count line and the Set * marker both report on an unchanged
-- chooser. The font model, the font object it adds and the tooltip recorder
-- are restored, and the planning session is reset, before the original paths
-- continue.
do
    local G=dofile('tests/prototype/layout_geometry_support.lua')
    local methods=G.RegionMethods()
    local FONT={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
    local savedFont,savedFontObject={},_G.NexusFontNormal
    for _,key in ipairs(FONT) do savedFont[key]=rawget(methods,key) end
    local savedTip={SetOwner=rawget(GameTooltip,'SetOwner'),AddLine=rawget(GameTooltip,'AddLine'),
        shown=GameTooltip.shown}
    local tip={lines={}}
    GameTooltip.SetOwner=function(_,owner) tip.owner=owner end
    GameTooltip.AddLine=function(_,text) tip.lines[#tip.lines+1]=tostring(text) end
    local failures={}
    local function expect(value,label)
        print('LAYOUT '..(value and 'PASS ' or 'FAIL ')..label)
        if not value then failures[#failures+1]=label end
        checks=checks+1
    end
    -- The end caps LayoutMetrics.FitButtonWidth allows beside a button label.
    local CAPS=24
    local function Need(text,model) return G.Length(G.Visible(text))*model.char+CAPS end
    local live=Nexus.GameAdapter.Catalog()
    local facts={[ids[1]]=live and live.rows[ids[1]],[LONG_ID]=live and live.rows[LONG_ID]}
    check(type(facts[ids[1]])=='table' and type(facts[LONG_ID])=='table'
        and type(facts[LONG_ID].name)=='string','LAYOUT setup exact catalog rows')
    check(Add(ids[1]) and Add(LONG_ID),'LAYOUT setup exact pool members')
    check(Count(ids[1],1) and Count(LONG_ID,2),'LAYOUT setup explicitly committed counts')
    check(G.Length(facts[LONG_ID].name)*G.MODELS.default.char>PoolRow(LONG_ID).label:GetWidth(),
        'LAYOUT setup long exact name is wider than its row label in the default model')
    -- The committed count, full ID, quality, maximum stack and exact name.
    local function Complete(text,id,committed)
        local row=facts[id]
        local name=Nexus.Identity.DisplaySafeText(row.name,256,true) or ''
        return name~='' and text:find('Set: '..committed,1,true)~=nil
            and text:find('#'..id,1,true)~=nil and text:find('Q'..row.quality,1,true)~=nil
            and text:find('max '..row.maxStack,1,true)~=nil and text:find(name,1,true)~=nil
    end
    -- The rendered line that holds the committed count lies inside the label
    -- box, and its "Set: N" fits the label width; earlier lines take the rows
    -- the model wraps them into.
    local function CommittedVisible(label,model,committed)
        local prefix,text,width='Set: '..committed,label:GetText() or '',label:GetWidth()
        local before=0
        for line in (text..'\n'):gmatch('(.-)\n') do
            if line:sub(1,#prefix)==prefix then
                return (before+1)*model.line<=label:GetHeight() and G.Length(prefix)*model.char<=width
            end
            before=before+math.max(1,G.Rows(line,width,model.char))
        end
        return false
    end
    local function LabelCase(row,model,id,committed,tag)
        local label,prefix=row.label,'Set: '..committed
        local text=label:GetText() or ''
        expect(text:sub(1,#prefix)==prefix and not text:find('\n',1,true)
            and label:GetHeight()==row:GetHeight() and Complete(text,id,committed),
            tag..' label is one line at row height, '..prefix..' first, with its complete facts')
        expect(CommittedVisible(label,model,committed),tag..' committed '..prefix..' line is visible')
        local shortened=G.Length(G.Visible(text))*model.char>label:GetWidth()
        tip.owner,tip.lines=nil,{}
        local enter,leave=row:GetScript('OnEnter'),row:GetScript('OnLeave')
        if enter then enter(row) end
        if leave then leave(row) end
        if shortened then
            expect(tip.owner==row and #tip.lines==1 and tip.lines[1]==text,
                tag..' shortened label shows its complete text in the row tooltip')
        else
            expect(#tip.lines==0,tag..' label that fits adds no tooltip')
        end
    end
    local function RowFits(row,tag)
        local bounds={0,0,row:GetWidth(),row:GetHeight()}
        local parts={G.Rect(row.label,row),G.Rect(row.count,row),G.Rect(row.action,row),G.Rect(row.remove,row)}
        local ok,shown=true,''
        for i,a in ipairs(parts) do
            ok=ok and G.Inside(a,bounds)
            for j=i+1,#parts do ok=ok and G.Apart(a,parts[j]) end
            shown=shown..G.Text(a)
        end
        expect(ok,tag..' label, count, '..tostring(row.action:GetText())
            ..' and Remove are inside the row and apart '..shown)
    end
    expect(PoolRow(ids[1]).recordedMouse==true,'pool row tooltip owner accepts mouse input')
    for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
        G.UseFont(model)
        local tag=model.name
        local row=PoolRow(ids[1])
        local width=row.action:GetWidth()
        expect(row.action:GetText()=='Set' and width>=Need('Set',model),
            tag..' bound Set fits its label ('..width..' px)')
        LabelCase(row,model,ids[1],'1',tag..' short exact name')
        LabelCase(PoolRow(LONG_ID),model,LONG_ID,'2',tag..' long exact name')
        row=PoolRow(ids[1])
        row.count:SetText('2')
        expect(row.action:GetText()=='Set *' and row.action:GetWidth()>=Need('Set *',model)
            and Status()==Reason('COUNT_PENDING'),
            tag..' typed count shows a fitting Set * ('..row.action:GetWidth()..' px) and the pending status')
        RowFits(row,tag..' pending')
        row=PoolRow(ids[1])
        expect(row.action:GetText()=='Set *' and row.action:GetWidth()>=Need('Set *',model),
            tag..' refreshed pending row keeps a fitting Set *')
        check(row.action:Click()==true,'LAYOUT '..tag..' explicit Set commits two')
        row=PoolRow(ids[1])
        expect(row.action:GetText()=='Set' and row.action:GetWidth()==width and Status()==''
            and CommittedVisible(row.label,model,'2'),
            tag..' explicit Set clears Set *, its width and the status; committed Set: 2 is visible')
        RowFits(row,tag..' committed')
        check(Count(ids[1],1),'LAYOUT '..tag..' explicit Set restores one')
    end
    for _,key in ipairs(FONT) do methods[key]=savedFont[key] end
    _G.NexusFontNormal=savedFontObject
    GameTooltip.SetOwner,GameTooltip.AddLine,GameTooltip.shown=savedTip.SetOwner,savedTip.AddLine,savedTip.shown
    NexusFlexiblePlanReset:Click()
    check(ChooserText():find('0 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true),
        'LAYOUT checks leave an empty planning session')
    print('LAYOUT completed real paths; failures='..#failures)
    assert(#failures==0,'EXPECT pool-row text layout: '..table.concat(failures,'; '))
end

-- Fixed multi-line chooser text (docs/UI_TEXT_LAYOUT.md): the 970x36 status
-- box and the 970x20 count-instruction help keep their size; while either
-- overflows, the hover area over it shows the complete text (LayoutMetrics
-- FullTextTooltip). The real chooser, its real Set path and the real
-- LayoutMetrics run under the offline font models of layout_geometry_support
-- (a regression aid, not native font measurement or a native tooltip proof).
-- Setup controls must pass first; only the new EXPECTs collect failures, so
-- the status and help disclosure paths both report on an unchanged chooser.
-- The font model, the font object it adds and the tooltip recorder are
-- restored, and the planning session is reset, before the original paths
-- continue.
do
    local G=dofile('tests/prototype/layout_geometry_support.lua')
    local methods=G.RegionMethods()
    local FONT={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
    local savedFont,savedFontObject={},_G.NexusFontNormal
    for _,key in ipairs(FONT) do savedFont[key]=rawget(methods,key) end
    local savedTip={SetOwner=rawget(GameTooltip,'SetOwner'),AddLine=rawget(GameTooltip,'AddLine'),
        Show=rawget(GameTooltip,'Show'),Hide=rawget(GameTooltip,'Hide'),shown=GameTooltip.shown}
    local tip
    local function ResetTip() tip={lines={},shows=0,hides=0} end
    ResetTip()
    GameTooltip.SetOwner=function(_,owner) tip.owner=owner end
    GameTooltip.AddLine=function(_,text) tip.lines[#tip.lines+1]=tostring(text) end
    GameTooltip.Show=function() tip.shows=tip.shows+1 end
    GameTooltip.Hide=function() tip.hides=tip.hides+1 end
    local failures={}
    local function expect(value,label)
        print('FIXED TEXT '..(value and 'PASS ' or 'FAIL ')..label)
        if not value then failures[#failures+1]=label end
        checks=checks+1
    end
    local root=NexusFlexiblePlanChooser
    -- The FontString the chooser anchors at one fixed position.
    local function LabelAt(x,y)
        local found
        for _,r in ipairs(root.regions) do
            local p=r.kind=='FontString' and r.points[1]
            if p and p[1]=='TOPLEFT' and p[2]==x and p[3]==y then
                assert(found==nil,'one chooser label at '..x..','..y);found=r
            end
        end
        return assert(found,'chooser label at '..x..','..y..' exists')
    end
    -- Hover areas over a rendered label: frames on the chooser anchored to
    -- all points of that label. Returns the first and how many there are.
    local function HoverOver(label)
        local found,count=nil,0
        for _,f in ipairs(H.frames) do
            if f:GetParent()==root and f.coveredRegion==label then found,count=found or f,count+1 end
        end
        return found,count
    end
    local function Same(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] and a[4]==b[4] end
    local function Effects()
        return {state=H.Clone(editor.DebugDraftState()),rows=Rendered(),name=NexusWishlistNameInput:GetText(),
            db=H.Clone(NexusDB),held=H.Clone(H.locked),actions=#H.actions,sends=#H.sent,
            replace=tostring(Popup.shown[REPLACE]),save=tostring(Popup.shown[CREATE])}
    end
    check(root==chooser and root:IsShown() and Status()==''
        and ChooserText():find('0 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true),
        'FIXED TEXT setup the shown chooser starts from an empty planning session')
    local status,help=LabelAt(22,-570),LabelAt(22,-44)
    local HELP=help:GetText()
    check(type(HELP)=='string' and HELP:find('Set: shows the committed count',1,true)
        and Same(G.Rect(status,root),{22,570,992,606}) and Same(G.Rect(help,root),{22,44,992,64}),
        'FIXED TEXT setup count help and status keep their fixed 970x20 and 970x36 boxes')
    local before=Effects()
    local statusArea,statusAreas=HoverOver(status)
    local helpArea,helpAreas=HoverOver(help)
    local frames=#H.frames
    NexusFlexiblePlanHide:Click();NexusFlexiblePlanEntry:Click()
    check(NexusFlexiblePlanChooser==root and root:IsShown() and Status()=='',
        'FIXED TEXT setup hide/reopen shows the same chooser')
    local statusAgain,statusAgainCount=HoverOver(status)
    local helpAgain,helpAgainCount=HoverOver(help)
    expect(statusAreas==1 and helpAreas==1 and statusArea~=helpArea and statusAgain==statusArea
        and helpAgain==helpArea and statusAgainCount==1 and helpAgainCount==1 and #H.frames==frames,
        'the chooser creates one hover area over its status and one over its help; hide/reopen reuses both')
    -- Each area is exactly its label box, inside the chooser and apart from
    -- the controls beside it, which keep their own places.
    local function Clear(area,label,neighbours,tag)
        if not area then expect(false,tag..' has a hover area to keep clear of its neighbours');return end
        local rect=G.Rect(area,root)
        local ok=area.recordedMouse==true and area:IsVisible() and Same(rect,G.Rect(label,root))
            and G.Inside(rect,{0,0,root:GetWidth(),root:GetHeight()})
        for _,n in ipairs(neighbours) do ok=ok and G.Apart(rect,G.Rect(n,root)) end
        expect(ok,tag..' mouse-enabled hover area '..G.Text(rect)..' is its label box, apart from its neighbours')
    end
    Clear(statusArea,status,{LabelAt(22,-546),NexusFlexiblePlanOpen,NexusFlexiblePlanReset,
        NexusFlexiblePlanPool,NexusFlexiblePlanCatalog},'status')
    Clear(helpArea,help,{LabelAt(22,-16),LabelAt(22,-66),NexusFlexiblePlanHide,NexusFlexiblePlanSearch},
        'count help')
    -- Hover a label's real area under a font model. want is the complete text
    -- its tooltip must show, or nil where the text fits or is empty and no
    -- tooltip may appear; the model's own measurement must agree first.
    local function Hover(label,model,tag,want)
        G.UseFont(model)
        tag=model.name..' '..tag
        local text,width,height=label:GetText() or '',label:GetWidth(),label:GetHeight()
        local rows=G.Rows(text,width,model.char)
        check((want~=nil)==(rows*model.line>height) and (want==nil or want==text),
            'FIXED TEXT setup '..tag..': '..#text..' bytes need '..rows*model.line..' of its '..height..' px')
        local area=HoverOver(label)
        if not area then
            expect(false,tag..(want and ' complete text is not recoverable: no hover area' or ' has no hover area'))
            return
        end
        ResetTip()
        local enter,leave=area:GetScript('OnEnter'),area:GetScript('OnLeave')
        if enter then enter(area) end
        local owner,lines,shows=tip.owner,tip.lines,tip.shows
        if leave then leave(area) end
        if want then
            expect(owner==area and #lines==1 and lines[1]==want and shows==1 and tip.hides==1,
                tag..' overflow: hover shows all '..#want..' bytes and leave hides them')
        else
            expect(owner==nil and #lines==0 and shows==0 and tip.hides==0,
                tag..(text=='' and ' empty text' or ' text that fits')..' adds no tooltip')
        end
        expect(label:GetText()==text and label:GetWidth()==width and label:GetHeight()==height,
            tag..' hover keeps its text and fixed box')
    end
    local REJECTED=Reason('STACK_LIMIT')..' '..Reason('COUNT_PENDING')
    check(Add(ids[1]) and Count(ids[1],1),'FIXED TEXT setup explicitly committed one')
    check(not Count(ids[1],6),'FIXED TEXT setup real max5 rejection')
    check(Status()==REJECTED and PoolRow(ids[1]).count:GetText()=='6'
        and PoolRow(ids[1]).label:GetText():find('Set: 1',1,true),
        'FIXED TEXT setup status holds the exact refusal reason and its pending clause')
    for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
        Hover(status,model,'rejected count status',model==G.MODELS.double and REJECTED or nil)
        Hover(help,model,'count help',model==G.MODELS.double and HELP or nil)
    end
    PoolRow(ids[1]).count:SetText('2')
    check(Status()==Reason('COUNT_PENDING') and PoolRow(ids[1]).action:GetText()=='Set *',
        'FIXED TEXT setup a typed count leaves only the pending status')
    for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do Hover(status,model,'pending status',nil) end
    check(Count(ids[1],1) and Status()=='','FIXED TEXT setup explicit Set clears the status')
    for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do Hover(status,model,'cleared status',nil) end
    for _,key in ipairs(FONT) do methods[key]=savedFont[key] end
    _G.NexusFontNormal=savedFontObject
    GameTooltip.SetOwner,GameTooltip.AddLine=savedTip.SetOwner,savedTip.AddLine
    GameTooltip.Show,GameTooltip.Hide,GameTooltip.shown=savedTip.Show,savedTip.Hide,savedTip.shown
    check(rawget(methods,'GetStringHeight')==savedFont.GetStringHeight and rawget(GameTooltip,'Hide')==savedTip.Hide,
        'FIXED TEXT font model and tooltip recorder are restored')
    expect(equal(Effects(),before),
        'status and help hovers change no editor, Save, held, locked, data, traffic or action state')
    check(ChooserText():find('1 / 256',1,true) and ChooserText():find('Chosen: 1 / 79',1,true),
        'FIXED TEXT setup the session holds only its explicit choice')
    NexusFlexiblePlanReset:Click()
    check(ChooserText():find('0 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true) and Status()=='',
        'FIXED TEXT checks leave an empty planning session')
    print('FIXED TEXT completed real paths; failures='..#failures)
    assert(#failures==0,'EXPECT fixed chooser text disclosure: '..table.concat(failures,'; '))
end

-- C2: a current replacement request accepted while the chooser is hidden.
-- Its refusal must show the chooser and state the exact reason: the editor
-- name changed after consent (EDITOR_CHANGED), or a count was typed after
-- consent without Set (COUNT_PENDING). The later editor, its unaccepted Save
-- confirmation, the committed counts and the pending input are all kept.
-- Only the new visibility EXPECTs collect failures, so every setup, no-loss
-- and positive control completes first; a refusal left hidden is reopened
-- through the real entry so those controls still run. The editor, popups and
-- planning session are restored before the original paths continue.
do
    local failures={}
    local function expect(value,label)
        print('C2 '..(value and 'PASS ' or 'FAIL ')..label)
        if not value then failures[#failures+1]=label end
        checks=checks+1
    end
    local A,B,C=410002,410003,410005
    local actions0,sends0=#H.actions,#H.sent
    local saveButton
    -- Everything a refusal must keep: editor rows, debug state and maps, name,
    -- destination, Save identity and data, held, saved data, traffic, actions.
    local function snapshot()
        local save=Popup.shown[CREATE]
        return {state=H.Clone(editor.DebugDraftState()),rows=Rendered(),name=NexusWishlistNameInput:GetText(),
            fulfilled=H.Clone(editor._fulfilledDraftTargets),applyPending=editor.IsApplyPending(),
            destination=saveButton and saveButton:GetText(),save=tostring(save),
            saveData=H.Clone(save and save.data),saveArgs={save and save.arg1,save and save.arg2},
            db=H.Clone(NexusDB),held=H.Clone(H.locked),actions=#H.actions,sends=#H.sent}
    end
    -- A pool row: its committed count first in its label, its count text and Set label.
    local function Shows(id,committed,text,action)
        local row=PoolRow(id)
        return row.label:GetText():find('Set: '..committed..'  #'..id,1,true)==1
            and row.count:GetText()==text and row.action:GetText()==action
    end
    local function Budget(members,copies)
        local text=ChooserText()
        return text:find(members..' / 256 alternatives',1,true)~=nil
            and text:find('Chosen: '..copies..' / 79',1,true)~=nil
    end
    editor.NewWishlist();NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
    check(Add(A) and Add(B) and Count(A,2) and Count(B,1),'C2 setup explicit current choice through Add and Set')
    NexusFlexiblePlanOpen:Click()
    if Popup.shown[REPLACE] then Popup.Click(Popup.shown[REPLACE],1) end
    check(equal(Rendered(),{{spellId=410002,quality=2,stacks=2},{spellId=410003,quality=3,stacks=1}})
        and not NexusFlexiblePlanChooser:IsShown(),'C2 setup real exact editor draft 410002x2 410003x1')
    NexusWishlistNameInput:SetText('C2 named exact draft')
    for _,f in ipairs(H.frames) do
        if f.kind=='Button' and f:GetParent()==NexusEditorFrame and f:IsVisible()
            and f:GetText()=='Create unassigned' then saveButton=f;break end
    end
    check(saveButton~=nil,'C2 setup visible Create unassigned control')
    saveButton:Click()
    local savePopup=Popup.shown[CREATE]
    check(savePopup~=nil and savePopup.data~=nil and Popup.shown[REPLACE]==nil,
        'C2 setup real current Save confirmation is shown, not accepted')
    local saveData=H.Clone(savePopup.data)
    -- 1: the editor name changes after consent while the chooser is hidden.
    NexusFlexiblePlanEntry:Click()
    check(Add(C) and Count(C,3) and Count(A,1),'C2 setup next counts through real Add, edited count and Set')
    check(Shows(A,1,'1','Set') and Shows(B,1,'1','Set') and Shows(C,3,'3','Set') and Budget(3,5)
        and Status()=='','C2 setup next choice 410002x1 410003x1 410005x3 has no pending input')
    NexusFlexiblePlanOpen:Click()
    local request=Popup.shown[REPLACE]
    check(request~=nil and Popup.shown[CREATE]==savePopup and equal(savePopup.data,saveData),
        'C2 setup current replacement request beside the unaccepted Save confirmation')
    NexusFlexiblePlanHide:Click()
    NexusWishlistNameInput:SetText('C2 later typed name')
    check(not NexusFlexiblePlanChooser:IsShown() and Popup.shown[REPLACE]==request
        and NexusWishlistNameInput:GetText()=='C2 later typed name',
        'C2 setup chooser hidden, then the editor name changed after consent')
    local before=snapshot()
    Popup.Click(request,1)
    local visible,said=NexusFlexiblePlanChooser:IsVisible(),Status()
    expect(visible,'hidden current request refused for a changed editor shows the chooser')
    expect(said==Reason('EDITOR_CHANGED') and said:find('editor changed',1,true)~=nil,
        'shown chooser status is exactly the EDITOR_CHANGED reason')
    -- Reopen through the real entry only if the refusal stayed hidden, so the
    -- controls below still run; this is setup, not an EXPECT or product stub.
    if not visible then NexusFlexiblePlanEntry:Click() end
    check(Popup.shown[REPLACE]==nil and equal(snapshot(),before),
        'C2 EDITOR_CHANGED refusal keeps later editor rows, debug maps, name, destination, Save identity/data, held, db, traffic and actions')
    check(Shows(A,1,'1','Set') and Shows(B,1,'1','Set') and Shows(C,3,'3','Set') and Budget(3,5),
        'C2 EDITOR_CHANGED refusal keeps every committed count')
    -- 2: a count is typed after consent without Set while the chooser is hidden.
    NexusFlexiblePlanOpen:Click();request=Popup.shown[REPLACE]
    check(request~=nil,'C2 setup fresh current replacement request for the later name')
    PoolRow(B).count:SetText('4')
    check(Shows(B,1,'4','Set *'),'C2 setup count typed after consent stays pending without Set')
    NexusFlexiblePlanHide:Click()
    check(not NexusFlexiblePlanChooser:IsShown() and Popup.shown[REPLACE]==request,
        'C2 setup chooser hidden with the current request still shown')
    before=snapshot()
    Popup.Click(request,1)
    visible,said=NexusFlexiblePlanChooser:IsVisible(),Status()
    expect(visible,'hidden current request refused for pending count input shows the chooser')
    expect(said==Reason('COUNT_PENDING') and said:find('Count input is pending',1,true)~=nil,
        'shown chooser status is exactly the COUNT_PENDING reason')
    if not visible then NexusFlexiblePlanEntry:Click() end
    check(Popup.shown[REPLACE]==nil and equal(snapshot(),before),
        'C2 COUNT_PENDING refusal keeps the complete editor, Save confirmation and effects')
    check(Shows(A,1,'1','Set') and Shows(B,1,'4','Set *') and Shows(C,3,'3','Set') and Budget(3,5),
        'C2 COUNT_PENDING refusal keeps committed counts and the typed 4 pending, uncommitted')
    -- A valid fresh current consent, accepted while hidden, still installs.
    check(Count(B,4) and Shows(B,4,'4','Set') and Budget(3,8) and Status()=='',
        'C2 setup explicit Set commits the typed 4')
    NexusFlexiblePlanOpen:Click();request=Popup.shown[REPLACE]
    check(request~=nil,'C2 setup fresh current consent for the committed choice')
    NexusFlexiblePlanHide:Click()
    Popup.Click(request,1)
    check(Popup.shown[REPLACE]==nil and not NexusFlexiblePlanChooser:IsShown()
        and equal(Rendered(),{{spellId=410002,quality=2,stacks=1},{spellId=410003,quality=3,stacks=4},
            {spellId=410005,quality=1,stacks=3}})
        and NexusWishlistNameInput:GetText()=='' and #H.actions==actions0 and #H.sent==sends0,
        'C2 CONTROL fresh current consent installs literal 410002x1 410003x4 410005x3 without actions')
    StaticPopup_Hide(REPLACE);StaticPopup_Hide(CREATE)
    editor.NewWishlist();NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
    check(Popup.shown[REPLACE]==nil and Popup.shown[CREATE]==nil and NexusFlexiblePlanChooser:IsShown()
        and editor.DebugPendingCount()==0 and NexusWishlistNameInput:GetText()=='' and Status()==''
        and Budget(0,0),'C2 checks leave an empty editor, no popup and an empty planning session')
    print('C2 completed real paths; failures='..#failures)
    assert(#failures==0,'EXPECT C2 hidden current-popup refusal visibility: '..table.concat(failures,'; '))
end

for i=1,100 do check(Add(ids[i]),'explicit catalog Add callback '..i) end
check(editor.DebugPendingCount()==0,'100 pool members choose no editor rows')
check(ChooserText():find('100 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true),
    'pool membership and selected-copy budget are separately visible')
NexusFlexiblePlanSearch:SetText('no result')
NexusFlexiblePlanPool:GetScript('OnMouseWheel')(NexusFlexiblePlanPool,-1000)
NexusFlexiblePlanHide:Click();NexusFlexiblePlanEntry:Click()
check(ChooserText():find('Chosen: 0 / 79',1,true),'filter/scroll/hide/reopen never choose an Echo')
NexusFlexiblePlanOpen:Click()
check(editor.DebugPendingCount()==0 and ChooserText():find('Choose exact',1,true),'empty UI choice refuses')
for i=22,100 do check(Count(ids[i],1),'explicit Set count callback '..i) end
check(not Count(ids[22],2) and ChooserText():find('at most 79',1,true),'UI over-budget refuses without trimming')
check(not Count(ids[22],6) and ChooserText():find('maximum stack',1,true),'UI over-stack refuses without trimming')
check(editor.DebugPendingCount()==0,'explicit planning choice preserves current draft until handoff')
check(Count(ids[22],1),'explicitly restore one after rejected input before handoff')
NexusFlexiblePlanOpen:Click()
check(editor.DebugPendingCount()==79,'actual Open callback installs last79')
check(equal(Rendered(),exact.CanonicalEchoes(manual)),'actual rendered exact last79 matches manual control, including ID held locked')
check(editor.DebugDraftState().pendingLock==0 and editor.DebugDraftState().fulfilled==0,
    'held locked instance creates no locked/fulfilled planning target')
check(not NexusFlexiblePlanChooser:IsShown() and NexusWishlistNameInput:GetText()=='',
    'success opens visible fresh unnamed editor and hides chooser')
editor.Refresh()
check(equal(Rendered(),exact.CanonicalEchoes(manual)),'refresh does not auto-load another Wishlist')

-- A named current draft has an active existing save confirmation. Pool work,
-- refusal and Cancel preserve it and all editor state.
NexusWishlistNameInput:SetText('Keep this draft')
local applyButton
for _,f in ipairs(H.frames) do
    if f.kind=='Button' and f:GetParent()==NexusEditorFrame and f:IsVisible()
        and f:GetText()=='Create unassigned' then applyButton=f;break end
end
assert(applyButton,'existing Create unassigned control')
applyButton:Click()
local savePopup=Popup.shown[CREATE]
check(savePopup~=nil and savePopup.data~=nil and Popup.shown[REPLACE]==nil,
    'existing Save remains a separate confirmation')
local saveData=H.Clone(savePopup.data)
NexusFlexiblePlanEntry:Click()
check(ChooserText():find('Chosen: 79 / 79',1,true),'hide/reopen retains explicit whole choice')
local oldRendered=Rendered()
check(not Count(ids[22],6) and Popup.shown[CREATE]==savePopup and Popup.shown[REPLACE]==nil,
    'planning refusal preserves active save popup identity')
local pendingRefusalState=H.Clone(editor.DebugDraftState())
check(not NexusFlexiblePlanOpen:Click() and Popup.shown[REPLACE]==nil
    and Popup.shown[CREATE]==savePopup and equal(savePopup.data,saveData)
    and NexusWishlistNameInput:GetText()=='Keep this draft' and equal(Rendered(),oldRendered)
    and equal(editor.DebugDraftState(),pendingRefusalState),
    'C1a rejected count Open preserves full editor and active save identity')
check(Count(ids[22],1),'explicitly restore one after rejection before replacement consent')
NexusFlexiblePlanOpen:Click()
local pendingReplacement=assert(Popup.shown[REPLACE])
PoolRow(ids[22]).count:SetText('2')
Popup.Click(pendingReplacement,1)
check(Popup.shown[REPLACE]==nil and Popup.shown[CREATE]==savePopup and equal(savePopup.data,saveData)
    and NexusWishlistNameInput:GetText()=='Keep this draft' and equal(Rendered(),oldRendered)
    and equal(editor.DebugDraftState(),pendingRefusalState),
    'C1a pending count popup accept preserves full editor maps destination and active save identity')
check(Count(ids[22],1),'explicit Set restores committed whole79 before original Cancel control')
NexusFlexiblePlanOpen:Click()
local replacement=Popup.shown[REPLACE]
check(replacement~=nil and editor.DebugPendingCount()==79,
    'explicit Open action asks before replacing an existing draft')
Popup.Click(replacement,2)
check(Popup.shown[REPLACE]==nil and Popup.shown[CREATE]==savePopup
    and NexusWishlistNameInput:GetText()=='Keep this draft' and equal(savePopup.data,saveData),
    'Cancel dismisses only the replacement and keeps name and existing save-confirmation bytes')
check(equal(Rendered(),oldRendered),'Cancel keeps exact rendered rows')
-- A late delivery of the canceled accept is retired: nothing is installed,
-- shown or dismissed, and the chooser says why.
StaticPopupDialogs[REPLACE].OnAccept(replacement.frame,replacement.data)
check(NexusWishlistNameInput:GetText()=='Keep this draft' and equal(Rendered(),oldRendered)
    and Popup.shown[CREATE]==savePopup and equal(savePopup.data,saveData) and Popup.shown[REPLACE]==nil
    and ChooserText():find('editor changed',1,true),'EXPECT canceled replacement callback is retired')
NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
check(replacement~=nil,'the retained exact choice asks again before replacing')
editor.Refresh()
local dismissed=Hidden(REPLACE)
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and Hidden(REPLACE)==dismissed+1,
    'EXPECT an installing accept dismisses its replacement confirmation once, leaving no stale popup')
check(NexusWishlistNameInput:GetText()=='' and editor.DebugPendingCount()==79
    and equal(Rendered(),exact.CanonicalEchoes(manual)) and not NexusFlexiblePlanChooser:IsShown(),
    'EXPECT passive editor refresh keeps the replacement current; accept opens the fresh exact new editor')
check(Popup.shown[CREATE]==nil,'the fresh editor also dismisses the previous save confirmation')
NexusWishlistNameInput:SetText('After install')
StaticPopupDialogs[REPLACE].OnAccept(replacement.frame,replacement.data)
check(NexusWishlistNameInput:GetText()=='After install' and editor.DebugPendingCount()==79
    and Popup.shown[REPLACE]==nil,'a used replacement request installs only once')
local staleSave=StaticPopupDialogs[CREATE].OnAccept(savePopup.frame,savePopup.data)
check(staleSave==nil and #H.actions==actionBaseline,'successful new draft invalidates previous save confirmation')

-- Stale replacement callbacks preserve the later editor and changed catalog.
-- Each refused confirmation is dismissed by its click, not left behind.
NexusFlexiblePlanEntry:Click();NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
editor.NewWishlist();NexusWishlistNameInput:SetText('Later work')
local laterState=H.Clone(editor.DebugDraftState())
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and NexusWishlistNameInput:GetText()=='Later work'
    and equal(editor.DebugDraftState(),laterState),'old UI confirmation cannot overwrite later editor context')
NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
NexusWishlistNameInput:SetText('Later typed name')
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and NexusWishlistNameInput:GetText()=='Later typed name'
    and editor.DebugPendingCount()==0,'later typed name is bound into confirmation')
NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
local live=Nexus.GameAdapter.Catalog()
local priorQuality=live.rows[ids[22]].quality
live.rows[ids[22]].quality=priorQuality+1
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and editor.DebugPendingCount()==0
    and NexusWishlistNameInput:GetText()=='Later typed name'
    and ChooserText():find('catalog details changed',1,true),'catalog drift after confirmation refuses before reset')
live.rows[ids[22]].quality=priorQuality
NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and NexusWishlistNameInput:GetText()=='' and editor.DebugPendingCount()==79,
    'EXPECT restored required facts allow a dismissing retry of the retained exact choice')
live.rows[ids[22]].quality=9
check(equal(Rendered(),exact.CanonicalEchoes(manual)),'later catalog mutation cannot change installed pending quality/count')
live.rows[ids[22]].quality=priorQuality
NexusFlexiblePlanEntry:Click();NexusFlexiblePlanOpen:Click();replacement=Popup.shown[REPLACE]
check(Count(ids[22],0),'explicit zero unchooses one alternative')
Popup.Click(replacement,1)
check(Popup.shown[REPLACE]==nil and editor.DebugPendingCount()==79
    and equal(Rendered(),exact.CanonicalEchoes(manual)) and ChooserText():find('choice changed',1,true),
    'changed planning choice retires older replacement payload')
check(Count(ids[22],1),'player can explicitly restore that choice')

-- No frame allocation per alternative or passive refresh; bound membership.
local frameCount=#H.frames
for i=101,256 do check(Add(ids[i]),'explicit bounded pool add '..i) end
check(#H.frames==frameCount and ChooserText():find('256 / 256',1,true),'256 alternatives reuse bounded visible row frames')
check(not Add(ids[257]) and ChooserText():find('at most 256',1,true),'257th alternative refuses without clipping pool')
NexusFlexiblePlanHide:Click();NexusFlexiblePlanEntry:Click()
check(ChooserText():find('256 / 256',1,true) and ChooserText():find('Chosen: 79 / 79',1,true),
    'reopen retains full bounded pool and explicit choice')
check(#H.frames==frameCount,'reopen/passive view reuses all frames')
NexusFlexiblePlanReset:Click()
check(ChooserText():find('0 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true)
    and editor.DebugPendingCount()==79,'Reset clears only planning session')
check(#H.actions==actionBaseline and #H.sent==sentBaseline and equal(NexusDB,storeBaseline),
    'all UI planning/install/refusal/cancel callbacks perform no upload/action/send/persistent writes')

-- Reload the production chooser module with the current editor facade reloaded:
-- its session memory is not represented by the existing saved root.
check(Add(ids[1]) and Count(ids[1],1),'session can be started after Reset')
NexusFlexiblePlanHide:Click()
dofile('ui/FlexiblePlanChooser.lua');dofile('ui/WishlistEditor.lua')
Nexus.WishlistEditor.Init(Nexus.GameAdapter,Nexus.Model)
Nexus.WishlistEditor.OpenFlexiblePlanChooser()
check(ChooserText():find('0 / 256',1,true) and ChooserText():find('Chosen: 0 / 79',1,true),
    'production module reload has no retained planning schema to resurrect')
check(equal(NexusDB,storeBaseline),'reload writes no planning persistence')
print('flexible_plan_editor_handoff PASS '..checks)
