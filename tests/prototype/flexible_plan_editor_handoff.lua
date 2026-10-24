-- #47 session chooser and atomic new-draft handoff, real TOC/public callbacks.
-- Synthetic catalog/host only. No native UI claim.
local H = dofile('tests/prototype/harness.lua')
-- Record root-window paint calls at the synthetic host boundary. The real
-- Theme helper must paint the chooser; a styled-button tree alone is not a
-- window surface over the editor beneath it.
local createFrame=CreateFrame
CreateFrame=function(kind,name,parent,template)
    local frame=createFrame(kind,name,parent,template)
    if name=='NexusEditorFrame' or name=='NexusFlexiblePlanChooser' then
        frame.SetBackdrop=function(self,value) self.drawnBackdrop=value end
        frame.SetBackdropColor=function(self,...) self.drawnFill={...} end
        frame.SetBackdropBorderColor=function(self,...) self.drawnBorder={...} end
    end
    return frame
end
wipe(H.db)
local function EchoName(i) return (i==22 or i==23) and 'Exact variants' or 'Choice '..i end
for i=1,257 do H.AddEcho(410000+i,EchoName(i),i%4,5,(i==22 or i==23) and 77 or 0) end
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
local savePopup=assert(H.popup)
check(savePopup.which=='WISHLISTREALIZER_CREATE_WISHLIST','existing Save remains separate confirmation')
local saveData=H.Clone(savePopup.data)
NexusFlexiblePlanEntry:Click()
check(ChooserText():find('Chosen: 79 / 79',1,true),'hide/reopen retains explicit whole choice')
local oldRendered=Rendered()
local beforePopup=H.popup
check(not Count(ids[22],6) and H.popup==beforePopup,'planning refusal preserves active save popup identity')
NexusFlexiblePlanOpen:Click()
local replacement=assert(H.popup)
check(replacement.which=='NEXUS_FLEXIBLE_PLAN_REPLACE' and editor.DebugPendingCount()==79,
    'explicit Open action asks before replacing an existing draft')
StaticPopupDialogs[replacement.which].OnCancel(replacement.frame,replacement.data)
check(NexusWishlistNameInput:GetText()=='Keep this draft'
    and equal(savePopup.data,saveData),'Cancel keeps name/exact rows and existing save-confirmation bytes')
local canceled=StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)
check(canceled==false and NexusWishlistNameInput:GetText()=='Keep this draft',
    'EXPECT canceled replacement callback is retired')
check(equal(Rendered(),oldRendered),'Cancel keeps exact rendered rows')
NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
editor.Refresh()
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==true,
    'EXPECT passive editor refresh does not invalidate an unchanged replacement')
check(NexusWishlistNameInput:GetText()=='' and editor.DebugPendingCount()==79,
    'confirmed replacement opens fresh exact new editor')
local staleSave=StaticPopupDialogs[savePopup.which].OnAccept(savePopup.frame,savePopup.data)
check(staleSave==nil and #H.actions==actionBaseline,'successful new draft invalidates previous save confirmation')

-- Stale replacement callbacks preserve the later editor and changed catalog.
NexusFlexiblePlanEntry:Click();NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
editor.NewWishlist();NexusWishlistNameInput:SetText('Later work')
local laterState=H.Clone(editor.DebugDraftState())
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==false
    and NexusWishlistNameInput:GetText()=='Later work' and equal(editor.DebugDraftState(),laterState),
    'old UI confirmation cannot overwrite later editor context')
NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
NexusWishlistNameInput:SetText('Later typed name')
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==false
    and NexusWishlistNameInput:GetText()=='Later typed name','later typed name is bound into confirmation')
NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
local live=Nexus.GameAdapter.Catalog()
local priorQuality=live.rows[ids[22]].quality
live.rows[ids[22]].quality=priorQuality+1
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==false
    and editor.DebugPendingCount()==0 and NexusWishlistNameInput:GetText()=='Later typed name'
    and ChooserText():find('catalog details changed',1,true),'catalog drift after confirmation refuses before reset')
live.rows[ids[22]].quality=priorQuality
NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==true,
    'restored required facts allow retry of retained exact choice')
live.rows[ids[22]].quality=9
check(equal(Rendered(),exact.CanonicalEchoes(manual)),'later catalog mutation cannot change installed pending quality/count')
live.rows[ids[22]].quality=priorQuality
NexusFlexiblePlanEntry:Click();NexusFlexiblePlanOpen:Click();replacement=assert(H.popup)
check(Count(ids[22],0),'explicit zero unchooses one alternative')
check(StaticPopupDialogs[replacement.which].OnAccept(replacement.frame,replacement.data)==false
    and editor.DebugPendingCount()==79,'changed planning choice retires older replacement payload')
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
