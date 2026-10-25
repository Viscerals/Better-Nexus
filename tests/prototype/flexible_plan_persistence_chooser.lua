-- #151 binding slice: chooser persistence callbacks over the real Store facade.
-- Real TOC boot with synthetic format-5 data, the actual chooser Factory.New
-- with the real FlexiblePlanStore facade and a tiny literal catalog. Rows are
-- driven through the rendered Add/Set/Reset controls; counts are read from the
-- rendered pool rows. SavePool/LoadPool/PersistenceState are called directly
-- here; the MAIN PRESENTATION block at the end drives the visible Save pool /
-- Load saved buttons, the persistence status line and editor-opened readback
-- across fresh boots. Its EDITOR COEXISTENCE block drives the real editor Save
-- retry and replacement request beside pool Save/Load. Still PENDING here:
-- unverified fault injection; unknown, future, read-only, malformed, loading,
-- owner and root refusal presentation in the UI; docs, the final full suite,
-- content checks and independent UltraCode reviews. The popup host is the identity-aware
-- synthetic host of flexible_plan_editor_handoff. Native StaticPopup pooling,
-- return handling, timing and game behaviour are NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local passed,failed=0,0
local function check(ok,label)
    if ok then passed=passed+1 else failed=failed+1;print('FAIL '..label) end
end
local LOAD,CLEAR,CREATE='NEXUS_FLEXIBLE_PLAN_LOAD','NEXUS_FLEXIBLE_PLAN_CLEAR','WISHLISTREALIZER_CREATE_WISHLIST'
local Popup
local function InstallHost()
    Popup={shown={},hidden={}}
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
end
local function Click(record,button)
    assert(record and Popup.shown[record.which]==record,'only a shown dialog can be clicked')
    local dialog,keep=StaticPopupDialogs[record.which],nil
    if button==2 then
        if dialog.OnCancel then dialog.OnCancel(record.frame,record.data) end
    elseif dialog.OnAccept then keep=dialog.OnAccept(record.frame,record.data) end
    if not keep and Popup.shown[record.which]==record then StaticPopup_Hide(record.which) end
end
local function Hidden(which) return Popup.hidden[which] or 0 end
local CAT={rows={
    [300001]={spellId=300001,quality=2,maxStack=5,name='Alpha'},
    [300002]={spellId=300002,quality=1,maxStack=3,groupId=7,name='Beta'},
    [300003]={spellId=300003,quality=0,maxStack=1,name='Gamma'}}}
local opened=0
local function NewChooser(withStore)
    return Nexus.FlexiblePlanChooser.New({catalog=function() return CAT end,
        openDraft=function() opened=opened+1 end,
        persistence=withStore and Nexus.FlexiblePlanStore.New({store=Nexus.Store}) or nil})
end
local H,owner
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
local function Rendered(id) return tonumber(PoolRow(id).label:GetText():match('^Set: (%d+)')) end
local function Raw()
    local row=NexusDB.chars and NexusDB.chars[owner]
    return row and row.flexiblePlanPoolV1
end

H=F.Boot(F.Database());InstallHost()
local ch=NewChooser(true)
local missing=type(ch.SavePool)~='function' or type(ch.LoadPool)~='function' or type(ch.PersistenceState)~='function'
check(not missing,'chooser exposes SavePool, LoadPool and PersistenceState')
if missing then print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed));os.exit(1) end
local actions,chat,sent=#H.actions,#H.chat,#H.sent
local probe=Nexus.FlexiblePlanStore.New({store=Nexus.Store})
local first=probe.Read();owner=first.ownerKey
check(first.mode=='durable' and first.class=='ABSENT' and type(owner)=='string','CONTROL real boot gives a durable absent pool')
check(StaticPopupDialogs[LOAD].OnAccept(nil,{Accept=function() return true end})==nil
    and StaticPopupDialogs[CLEAR].OnAccept(nil,nil)==nil,'Load/Clear OnAccept return nil')
ch.Show()
local st=ch.PersistenceState()
check(st.available and st.phase=='idle' and not st.dirty and st.class=='ABSENT','first Show observes; an untouched empty session is clean')
Add(300001);Add(300002);Count(300001,4)
check(Rendered(300001)==4 and Rendered(300002)==0 and ch.PersistenceState().dirty,'rendered Add/Set make the session dirty')
PoolRow(300002).count:SetText('2')
local phase,code=ch.SavePool()
check(phase=='refused' and code=='COUNT_PENDING' and Raw()==nil,'pending count input refuses Save; nothing written automatically')
Count(300002,0)
phase,code=ch.SavePool()
check(phase=='saved' and code==nil,'explicit Save reports saved')
local want={version=1,ids={300001,300002},quality={2,1},maxStack={5,3},groupId={-1,7},counts={4,0}}
check(Raw()~=nil and F.Serialize(Raw())==F.Serialize(want),'Save writes the exact literal v1 record on the owner row')
check(probe.Read().bytes=='v1|300001,2,5,-1,4;300002,1,3,7,0;','a fresh facade Read returns the canonical bytes')
st=ch.PersistenceState()
check(st.phase=='saved' and not st.dirty and not st.stale and st.saved,'after Save the session is clean')

StaticPopup_Show(CREATE,nil,nil,{other=true});local other=Popup.shown[CREATE]
Count(300001,2)
phase=ch.LoadPool();local ask=Popup.shown[LOAD]
check(phase=='confirm' and ask~=nil and ch.PersistenceState().confirming=='load','dirty Load asks NEXUS_FLEXIBLE_PLAN_LOAD')
Click(ask,2)
check(Rendered(300001)==2 and ch.PersistenceState().dirty and Popup.shown[LOAD]==nil and Popup.shown[CREATE]==other,
    'Cancel keeps pool, counts and the unrelated popup')
StaticPopupDialogs[LOAD].OnAccept(nil,ask.data)
check(Rendered(300001)==2,'a replayed cancelled request installs nothing')
ch.LoadPool();local older=Popup.shown[LOAD];local hides=Hidden(LOAD)
ch.LoadPool();local newer=Popup.shown[LOAD]
check(newer~=nil and newer~=older and Hidden(LOAD)==hides+1 and Popup.shown[CREATE]==other,'a superseding Load retires only the former request')
StaticPopupDialogs[LOAD].OnAccept(nil,older.data)
check(Rendered(300001)==2 and Popup.shown[LOAD]==newer,'a replayed former request neither installs nor dismisses the newer popup')
Click(newer,1)
st=ch.PersistenceState()
check(Rendered(300001)==4 and Rendered(300002)==0 and st.phase=='loaded' and not st.dirty and st.catalogChanged==0
    and Popup.shown[CREATE]==other,'Accept installs the exact saved counts and keeps the unrelated popup')
Count(300001,3)
StaticPopupDialogs[LOAD].OnAccept(nil,newer.data)
check(Rendered(300001)==3,'a replayed accepted request installs nothing')

ch.LoadPool();local staleAsk=Popup.shown[LOAD]
local replaced=probe.Save({ids={300003},rows={[300003]={spellId=300003,quality=0,maxStack=1}},chosen={[300003]=1}},probe.Read())
check(replaced.state=='saved','CONTROL an independent facade replaces the saved pool')
Click(staleAsk,1)
st=ch.PersistenceState()
check(Rendered(300001)==3 and st.code=='LOAD_CHANGED' and st.stale,'changed saved data refuses Accept and keeps the session')
phase,code=ch.SavePool()
check(phase=='refused' and code=='SAVED_CHANGED' and Raw().ids[1]==300003,'the retained stale receipt refuses Save; the newer record survives')
ch.LoadPool();Click(Popup.shown[LOAD],1)
check(Rendered(300003)==1 and not ch.PersistenceState().stale,'Accept loads the current saved pool')

NexusFlexiblePlanReset:Click()
phase=ch.SavePool();local ask2=Popup.shown[CLEAR]
check(phase=='confirm' and ask2~=nil,'Save of an empty session over a saved pool asks NEXUS_FLEXIBLE_PLAN_CLEAR')
Click(ask2,2)
check(Raw()~=nil and Popup.shown[CREATE]==other,'Clear Cancel keeps the saved pool')
ch.SavePool();local ask3=Popup.shown[CLEAR]
Click(ask3,1)
check(Raw()==nil and probe.Read().class=='ABSENT' and ch.PersistenceState().phase=='saved','Clear Accept removes the saved pool')
Add(300002);Count(300002,1)
check(ch.SavePool()=='saved','a new pool saves over the cleared key')
StaticPopupDialogs[CLEAR].OnAccept(nil,ask3.data)
check(Raw()~=nil and Raw().ids[1]==300002,'a replayed Clear request removes nothing')
local bare=NewChooser(false)
check(bare.SavePool()=='refused' and select(2,bare.LoadPool())=='NO_PERSISTENCE' and not bare.PersistenceState().available,
    'without the persistence option the new callbacks refuse')
check(opened==0 and #H.actions==actions and #H.chat==chat and #H.sent==sent,'no draft handoff, native action, message or send')

local savedRecord=F.Serialize(Raw())
H=F.Reload();InstallHost()
check(F.Serialize(Raw())==savedRecord,'the saved record survives serialize and a fresh module boot')
actions=#H.actions
local again=NewChooser(true)
again.Show()
st=again.PersistenceState()
check(st.saved and not st.dirty and st.phase=='idle','after reload an empty clean session observes the saved pool')
CAT.rows[300002].quality=3
phase=again.LoadPool()
check(phase=='loaded' and Rendered(300002)==1 and again.PersistenceState().catalogChanged==1
    and PoolRow(300002).label:GetText():find('Q1',1,true)~=nil,'clean Load restores saved facts and counts, reporting catalog drift')
check(opened==0 and #H.actions==actions,'reload Load opens no draft and performs no action')

-- MAIN PRESENTATION (#151 visible controls/readback slice). Actual TOC boots
-- with two literal Echoes seeded through F.Boot's before hook (so the catalog
-- scan sees them), the real editor entry (NewWishlist, then
-- NexusFlexiblePlanEntry) and the rendered controls only: Add/Set, the new
-- Save pool / Load saved buttons, Reset and the identity-aware popup host
-- above. Stored data is read from NexusDB, counts from rendered pool rows and
-- the persistence status from the fixed line at (22,-66). The font models are
-- the offline layout_geometry_support models, not native measurement.
-- Unknown/future/read-only presentation and unverified fault injection are
-- queued for a later slice. The EDITOR COEXISTENCE block at the end of this
-- block covers the editor Save-retry/replace interplay.
do
    local A,B=310001,310002
    local function Seed(h) h.AddEcho(A,'Delta',2,5,7);h.AddEcho(B,'Epsilon',1,3,9) end
    local T={
        EMPTY="Not saved. Save pool stores this character's planning pool; Load saved restores it. Hide keeps this session; Reset clears only this session.",
        NEW="Not saved. Save pool stores this pool on this character.",
        PENDING="Unsaved changes: Set each edited count before Save pool.",
        REFUSED_PENDING="Not saved: Set each edited count first. Your pool is kept.",
        SAVED="Saved on this character.",
        HAS="A pool is saved on this character. Load saved restores it.",
        LOADED="Loaded the pool saved on this character.",
        UNSAVED="Unsaved changes. Save pool replaces the saved pool; Load saved restores it.",
        ASK_LOAD="Waiting for your answer: Load saved replaces this pool; Cancel keeps it.",
        UNSAVED_EMPTY="Unsaved changes: the pool is empty. Save pool asks before removing the saved pool.",
        ASK_CLEAR="Waiting for your answer: remove the saved pool; Cancel keeps it.",
        CLEARED="Saved pool removed from this character.",
        NOTHING="Nothing is saved on this character. Your pool is unchanged.",
    }
    local EMPTY_BUDGET='^0 / 256 alternatives%s+Chosen: 0 / 79 ordinary copies$'
    local G=dofile('tests/prototype/layout_geometry_support.lua')
    local function LabelAt(y)
        local found
        for _,r in ipairs(NexusFlexiblePlanChooser.regions) do
            local p=r.kind=='FontString' and r.points[1]
            if p and p[1]=='TOPLEFT' and p[2]==22 and p[3]==y then
                assert(found==nil,'one chooser label at '..y);found=r
            end
        end
        return assert(found,'chooser label at '..y..' exists')
    end
    local function Persisted() return LabelAt(-66):GetText() end
    local function PoolStatus() return LabelAt(-570):GetText() end
    local function Budget() return LabelAt(-546):GetText() end
    local function Deep(a,b,seen)
        if a==b then return true end
        if type(a)~='table' or type(b)~='table' then return false end
        seen=seen or {}
        if seen[a]==b then return true end
        seen[a]=b
        for k,v in pairs(a) do if not Deep(v,b[k],seen) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local function Effects()
        local name=rawget(_G,'NexusWishlistNameInput')
        return {state=H.Clone(Nexus.WishlistEditor.DebugDraftState()),name=name and name:GetText() or nil,
            actions=#H.actions,chat=#H.chat,sent=#H.sent,replace=Popup.shown.NEXUS_FLEXIBLE_PLAN_REPLACE}
    end
    local function Quiet(before,label)
        check(Deep(before,Effects()),label..' keeps the editor draft and name, with no action, message or send')
    end
    -- Boot effects (setup) are separate: the baseline is taken after the entry opened.
    local function Open(boot)
        H=boot;InstallHost()
        owner=Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read().ownerKey
        Nexus.WishlistEditor.NewWishlist()
        NexusFlexiblePlanEntry:Click()
        return Effects()
    end
    local function Record(counts)
        return F.Serialize({version=1,ids={A,B},quality={2,1},maxStack={5,3},groupId={7,9},counts=counts})
    end
    local function Holders()
        local n=0
        for _,row in pairs(NexusDB.chars or {}) do
            if type(row)=='table' and row.flexiblePlanPoolV1~=nil then n=n+1 end
        end
        return n
    end
    local fx=Open(F.Boot(F.Database(),Seed))
    local root=NexusFlexiblePlanChooser
    local saveBtn,loadBtn=rawget(_G,'NexusFlexiblePlanSave'),rawget(_G,'NexusFlexiblePlanLoad')
    local present=root~=nil and root:IsShown() and saveBtn~=nil and loadBtn~=nil
        and saveBtn:GetParent()==root and loadBtn:GetParent()==root
    check(present,'EXPECT visible Save pool and Load saved controls in the editor-opened chooser')
    if not present then
        print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed));os.exit(1)
    end
    check(saveBtn:GetText()=='Save pool' and loadBtn:GetText()=='Load saved' and saveBtn:IsShown() and loadBtn:IsShown()
        and saveBtn:IsEnabled() and loadBtn:IsEnabled(),'Save pool and Load saved are shown, labelled and enabled')
    local function Same(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] and a[4]==b[4] end
    local box={0,0,root:GetWidth(),root:GetHeight()}
    local saveRect,loadRect,resetRect=G.Rect(saveBtn,root),G.Rect(loadBtn,root),G.Rect(NexusFlexiblePlanReset,root)
    local fitted=true
    for _,b in ipairs({saveBtn,loadBtn}) do
        fitted=fitted and G.Length(b:GetText())*7+24<=b:GetWidth() and b:GetWidth()<=170 and b:GetHeight()==22
    end
    check(box[3]==1020 and box[4]==650 and Same(G.Rect(NexusFlexiblePlanOpen,root),{774,610,998,632})
        and Same(resetRect,{666,610,766,632}) and saveRect[1]==22 and saveRect[2]==610 and saveRect[4]==632
        and loadRect[1]==saveRect[3]+8 and loadRect[2]==610 and G.Inside(saveRect,box) and G.Inside(loadRect,box)
        and G.Apart(loadRect,resetRect) and G.Apart(saveRect,G.Rect(LabelAt(-570),root))
        and G.Apart(loadRect,G.Rect(LabelAt(-570),root)) and fitted,
        'Save/Load sit in the free left of the action row, fitted to their labels; Open, Reset and the 1020x650 frame keep their places')
    local persist=LabelAt(-66)
    check(LabelAt(-16):GetText()=='Plan alternatives' and LabelAt(-44):GetText():find('Set: shows the committed count',1,true)~=nil
        and Same(G.Rect(persist,root),{22,66,992,86}) and PoolStatus()=='',
        'the title drops session-only; count help and the blank pool status stay; the persistence line keeps a 970x20 box')
    check(Persisted()==T.EMPTY,'an untouched session says it is not saved and what Save, Load, Hide and Reset do')
    local area,areas=nil,0
    for _,f in ipairs(H.frames) do if f._nexusText==persist then area,areas=area or f,areas+1 end end
    check(areas==1 and area:GetParent()==root and area:GetScript('OnEnter')~=nil,'one hover area serves the persistence line')
    local methods=G.RegionMethods()
    local FONT,TIP={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'},{'SetOwner','AddLine','Show','Hide'}
    local savedFont,savedTip,savedObject={},{},rawget(_G,'NexusFontNormal')
    for _,k in ipairs(FONT) do savedFont[k]=rawget(methods,k) end
    for _,k in ipairs(TIP) do savedTip[k]=rawget(GameTooltip,k) end
    local tip
    GameTooltip.SetOwner=function(_,o) tip.owner=o end
    GameTooltip.AddLine=function(_,t) tip.lines[#tip.lines+1]=tostring(t) end
    GameTooltip.Show=function() tip.shows=tip.shows+1 end
    GameTooltip.Hide=function() tip.hides=tip.hides+1 end
    -- Hover the real area under a stated font model; the model's own measure
    -- must agree with the expected branch before the tooltip is judged.
    local function Hover(model,overflow)
        G.UseFont(model)
        tip={lines={},shows=0,hides=0}
        local text,w,h=persist:GetText(),persist:GetWidth(),persist:GetHeight()
        local measured=G.Rows(text,w,model.char)*model.line>h
        area:GetScript('OnEnter')(area)
        local owner,lines,shows=tip.owner,tip.lines,tip.shows
        area:GetScript('OnLeave')(area)
        local ok=measured==overflow and persist:GetText()==text and persist:GetWidth()==w and persist:GetHeight()==h
        if overflow then return ok and owner==area and #lines==1 and lines[1]==text and shows==1 and tip.hides==1 end
        return ok and owner==nil and #lines==0 and shows==0 and tip.hides==0
    end
    local quiet=Effects()
    local fits=Hover(G.MODELS.default,false)
    local overflows=Hover(G.MODELS.double,true)
    for _,k in ipairs(FONT) do methods[k]=savedFont[k] end
    for _,k in ipairs(TIP) do GameTooltip[k]=savedTip[k] end
    _G.NexusFontNormal=savedObject
    check(fits,'default font model: the persistence text fits its box and hover adds no tooltip')
    check(overflows,'2.0 font model: the persistence text overflows its fixed box; hover shows all of it, leave hides it')
    check(Persisted()==T.EMPTY and Same(G.Rect(persist,root),{22,66,992,86}),'hover keeps the persistence text and box')
    Quiet(quiet,'hovering the persistence line')

    fx=Effects()
    check(Add(A) and Persisted()==T.NEW and Raw()==nil,'after Add the pool is not saved yet; nothing is written automatically')
    Count(A,3);Add(B);Count(B,1)
    check(Rendered(A)==3 and Rendered(B)==1 and Persisted()==T.NEW and PoolStatus()=='' and Raw()==nil,
        'rendered Set commits counts; the status still says not saved')
    PoolRow(B).count:SetText('2')
    check(Persisted()==T.PENDING and PoolStatus()==Nexus.FlexiblePlanChooser.Reason('COUNT_PENDING'),
        'typing a count shows unsaved pending input on the persistence line, apart from the pool status')
    saveBtn:Click()
    check(Persisted()==T.REFUSED_PENDING and Raw()==nil,'Save pool with pending input is refused and says why')
    PoolRow(B).count:SetText('1')
    check(Persisted()==T.NEW and PoolStatus()=='','restoring the committed count clears the pending state')
    saveBtn:Click()
    check(Persisted()==T.SAVED and Raw()~=nil and F.Serialize(Raw())==Record({3,1}) and Holders()==1,
        'Save pool writes the exact literal record and reports Saved')
    Quiet(fx,'Add, Set, typing and Save pool')
    local frames=#H.frames
    NexusFlexiblePlanHide:Click()
    check(not root:IsShown() and Persisted()==T.SAVED,'Hide keeps the status')
    NexusFlexiblePlanEntry:Click()
    local reused=0
    for _,f in ipairs(H.frames) do if f._nexusText==persist then reused=reused+1 end end
    check(NexusFlexiblePlanChooser==root and root:IsShown() and Rendered(A)==3 and Rendered(B)==1
        and Persisted()==T.SAVED and F.Serialize(Raw())==Record({3,1}) and #H.frames==frames and reused==1
        and Popup.shown[LOAD]==nil and Popup.shown[CLEAR]==nil,
        'Hide and reopen keep choices and status, reuse every control, and neither save nor load')
    Quiet(fx,'Hide and reopen')

    local text=F.Serialize(Raw())
    fx=Open(F.Reload(Seed))
    check(F.Serialize(Raw())==text and Persisted()==T.HAS and Budget():find(EMPTY_BUDGET)~=nil and PoolStatus()=='',
        'after serialize and a fresh boot the editor-opened chooser starts empty and says a pool is saved')
    NexusFlexiblePlanLoad:Click()
    check(Rendered(A)==3 and Rendered(B)==1 and Persisted()==T.LOADED and Popup.shown[LOAD]==nil
        and F.Serialize(Raw())==text,'Load saved restores the exact rows and counts without a question or a write')
    Quiet(fx,'Load saved into a clean session')
    Count(A,2)
    check(Rendered(A)==2 and Persisted()==T.UNSAVED and F.Serialize(Raw())==text,
        'an edited count is an unsaved change; the saved record is untouched by the session')
    NexusFlexiblePlanLoad:Click()
    local ask=Popup.shown[LOAD]
    check(ask~=nil and Persisted()==T.ASK_LOAD..' '..T.UNSAVED,'Load saved over unsaved changes asks first and says so')
    if ask then Click(ask,2) end
    check(Popup.shown[LOAD]==nil and Rendered(A)==2 and Persisted()==T.UNSAVED,
        'Cancel keeps the edited pool and says it is unsaved')
    NexusFlexiblePlanLoad:Click()
    if Popup.shown[LOAD] then Click(Popup.shown[LOAD],1) end
    check(Rendered(A)==3 and Rendered(B)==1 and Persisted()==T.LOADED and Popup.shown[LOAD]==nil,
        'Accept restores the saved counts and the status reads Loaded')
    Count(A,2);NexusFlexiblePlanSave:Click()
    check(Persisted()==T.SAVED and F.Serialize(Raw())==Record({2,1}) and Holders()==1,
        'Save pool updates the one saved record with the edited count')
    Quiet(fx,'edit, the Load question, Cancel, Accept and Save pool')

    text=F.Serialize(Raw())
    fx=Open(F.Reload(Seed))
    NexusFlexiblePlanLoad:Click()
    check(F.Serialize(Raw())==text and Rendered(A)==2 and Rendered(B)==1 and Persisted()==T.LOADED,
        'after another fresh boot Load saved restores the updated counts')
    NexusFlexiblePlanReset:Click()
    check(Budget():find(EMPTY_BUDGET)~=nil and Persisted()==T.UNSAVED_EMPTY and F.Serialize(Raw())==text,
        'Reset clears only the session; the status says the empty pool is unsaved')
    NexusFlexiblePlanSave:Click()
    local clear=Popup.shown[CLEAR]
    check(clear~=nil and Persisted()==T.ASK_CLEAR..' '..T.UNSAVED_EMPTY and F.Serialize(Raw())==text,
        'Save pool of an empty pool asks before removing the saved pool')
    if clear then Click(clear,2) end
    check(Popup.shown[CLEAR]==nil and F.Serialize(Raw())==text and Persisted()==T.UNSAVED_EMPTY,
        'Cancel keeps the saved record and the status')
    NexusFlexiblePlanSave:Click()
    local fresh=Popup.shown[CLEAR]
    check(fresh~=nil and fresh~=clear,'Save pool asks again with a fresh question')
    if fresh then Click(fresh,1) end
    check(Raw()==nil and Holders()==0 and Persisted()==T.CLEARED,'Accept removes the saved pool and says so')
    Quiet(fx,'Reset and the remove question')
    fx=Open(F.Reload(Seed))
    check(Raw()==nil and Persisted()==T.EMPTY,'after a fresh boot nothing is saved')
    NexusFlexiblePlanLoad:Click()
    check(Raw()==nil and Persisted()==T.NOTHING and Budget():find(EMPTY_BUDGET)~=nil and Popup.shown[LOAD]==nil,
        'Load saved after removal says nothing is saved and restores nothing')
    Quiet(fx,'Load saved with nothing saved')

    -- EDITOR COEXISTENCE (#151 editor Save-retry/replace slice). Pool Save/Load
    -- are separate from the editor draft and its Save authority. A fresh
    -- synthetic boot seeds three literal Echoes (410002 q2, 410003 q3, 410005 q1,
    -- max 5, group 0). The real editor entry, the rendered chooser controls, the
    -- editor's visible Create unassigned and its own Save confirmation drive
    -- every step. The editor controller is found through an upvalue of
    -- editor.Show, as flexible_plan_editor_handoff does, and is only read.
    -- A forwarding counter at the public GameAdapter.UploadWishlist boundary,
    -- with the unmodified function behind it, counts every upload attempt,
    -- refused or sent. The spacing that keeps the confirmed Save waiting
    -- therefore cannot mask an attempt. The spacer upload is setup and is
    -- counted alone. No claim advances the clock.
    -- Episode 1: a real confirmed Save waits as a retry. The dirty pool's own
    -- Load Cancel/Accept and an earlier replacement request (refused
    -- PLAN_CHANGED, then replayed) keep the editor and its retry.
    -- Episode 2, after the spacing ended: an open, unconfirmed Save
    -- confirmation survives pool Load Cancel/Accept and stale Load/Clear
    -- callbacks, then still saves.
    -- The offline synthetic host only models callbacks. Native StaticPopup
    -- pooling, return handling, timing, fonts and server behaviour are NOT_RUN.
    do
        local X2,X3,X5,REPLACE=410002,410003,410005,'NEXUS_FLEXIBLE_PLAN_REPLACE'
        local SAVE1,SAVE2='Coexist waiting save','Coexist open save'
        local function Seed3(h) h.AddEcho(X2,'Zeta',2,5,0);h.AddEcho(X3,'Eta',3,5,0);h.AddEcho(X5,'Theta',1,5,0) end
        local function Need(ok,label)
            check(ok,label)
            if not ok then
                print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed));os.exit(1)
            end
        end
        local function Reason(code) return Nexus.FlexiblePlanChooser.Reason(code) end
        -- The literal spellId, quality and count of each row, in ID order.
        local function Literal(echoes)
            local out={}
            for i,e in ipairs(type(echoes)=='table' and echoes or {}) do
                out[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks}
            end
            table.sort(out,function(a,b) return a.spellId<b.spellId end)
            return out
        end
        -- The editor's rendered rows: every visible row of its virtual list.
        local function EditorRows()
            local seen,area={},nil
            for _,f in ipairs(H.frames) do if f.plus and f.data and f:IsVisible() then area=f:GetParent();break end end
            if not area then return {} end
            area:GetScript('OnMouseWheel')(area,1000)
            for _=1,80 do
                for _,f in ipairs(H.frames) do
                    local d=f.data
                    if f:GetParent()==area and f:IsVisible() and d and not d.ghost then
                        seen[d.spellId]={spellId=d.spellId,quality=d.quality,stacks=d.stacks}
                    end
                end
                area:GetScript('OnMouseWheel')(area,-1)
            end
            local rows={};for _,r in pairs(seen) do rows[#rows+1]=r end
            return Literal(rows)
        end
        -- Every rendered pool row: committed count, count text and Set label.
        local function PoolCounts()
            local area=NexusFlexiblePlanPool
            area:GetScript('OnMouseWheel')(area,1000)
            local out={}
            for _,f in ipairs(H.frames) do
                if f:GetParent()==area and f:IsVisible() and f.spellId then
                    out[f.spellId]={n=tonumber(f.label:GetText():match('^Set: (%d+)')),text=f.count:GetText(),set=f.action:GetText()}
                end
            end
            return out
        end
        local function Pool(counts)
            local out={}
            for id,n in pairs(counts) do out[id]={n=n,text=tostring(n),set='Set'} end
            return out
        end
        local function CreateButton()
            for _,f in ipairs(H.frames) do
                if f.kind=='Button' and f:GetParent()==NexusEditorFrame and f:IsVisible()
                    and f:GetText()=='Create unassigned' then return f end
            end
        end
        Open(F.Boot(F.Database(),Seed3))
        local editor,ctl=Nexus.WishlistEditor,nil
        for i=1,64 do
            local name,value=debug.getupvalue(editor.Show,i)
            if name==nil then break end
            if name=='wishlistController' then ctl=value;break end
        end
        Need(type(ctl)=='table' and type(ctl.PendingApply)=='function' and type(ctl.PendingRows)=='function'
            and type(ctl.PendingLockRows)=='function' and type(ctl.FulfilledDraftTargets)=='function'
            and type(ctl.CanonicalEchoes)=='function','COEXIST setup the real editor controller through an upvalue of editor.Show')
        local realUpload,attempts,lastWhy=Nexus.GameAdapter.UploadWishlist,0,nil
        local function Counted(...)
            attempts=attempts+1
            local ok,why=realUpload(...)
            lastWhy=why
            return ok,why
        end
        Nexus.GameAdapter.UploadWishlist=Counted
        -- PendingApply returns a fresh wrapper on every read: compare its literal fields.
        local function Retry()
            local r=ctl.PendingApply()
            return r and {slot=r.slot,name=r.name,tries=r.tries,rows=Literal(r.echoes)} or nil
        end
        -- Everything a pool callback must keep. These are the editor rows, debug state,
        -- full maps, name, contexts, destination and retry; the Save popup and its
        -- hides; the complete saved root, held locks, traffic, actions and attempts.
        local function Snap()
            return {rows=EditorRows(),state=H.Clone(editor.DebugDraftState()),name=NexusWishlistNameInput:GetText(),
                pending=H.Clone(ctl.PendingRows()),locked=H.Clone(ctl.PendingLockRows()),
                fulfilled=H.Clone(ctl.FulfilledDraftTargets()),editing=ctl.EditingContext(),
                target=ctl.CreateTargetContext(),destination=ctl.SaveDestinationDescriptor(),
                applyPending=editor.IsApplyPending(),retry=Retry(),create=tostring(Popup.shown[CREATE]),
                createHides=Hidden(CREATE),db=F.Serialize(NexusDB),held=H.Clone(H.locked),
                actions=#H.actions,chat=#H.chat,sent=#H.sent,uploads=attempts}
        end

        -- Episode 1 setup: a saved pool, then a different dirty pool, before any editor Save.
        Need(Persisted()==T.EMPTY and Raw()==nil and NexusFlexiblePlanChooser:IsShown(),
            'COEXIST setup the editor-opened chooser starts empty with nothing saved')
        Need(Add(X3) and Add(X5) and Count(X3,3) and Count(X5,2),'COEXIST setup a pool 410003x3 410005x2 through real Add and Set')
        NexusFlexiblePlanSave:Click()
        local raw=Raw() or {}
        Need(Persisted()==T.SAVED and F.Serialize(raw.ids)==F.Serialize({X3,X5}) and F.Serialize(raw.quality)==F.Serialize({3,1})
            and F.Serialize(raw.maxStack)==F.Serialize({5,5}) and F.Serialize(raw.counts)==F.Serialize({3,2}),
            'COEXIST setup Save pool writes the literal saved pool 410003x3 410005x2')
        local savedRoot=F.Serialize(Raw())
        NexusFlexiblePlanReset:Click()
        Need(Add(X2) and Add(X3) and Count(X2,2) and Count(X3,1) and Deep(PoolCounts(),Pool({[X2]=2,[X3]=1}))
            and Persisted()==T.UNSAVED and F.Serialize(Raw())==savedRoot,
            'COEXIST setup a different dirty pool 410002x2 410003x1 before the editor Save; the saved pool is unchanged')
        local spaced=Nexus.GameAdapter.UploadWishlist(0,'Coexist spacer',{{spellId=410004,quality=0,stacks=1}})
        local spacerActions=#H.actions
        local spacerRow=H.actions[spacerActions] or {}
        Need(spaced==true and attempts==1 and spacerRow[1]=='upload' and spacerRow[3]=='Coexist spacer',
            'COEXIST setup CONTROL one real spacer upload (setup, counted alone) reaches the synthetic host and starts the spacing')
        local DRAFT={{spellId=X2,quality=2,stacks=2},{spellId=X3,quality=3,stacks=1}}
        NexusFlexiblePlanOpen:Click()
        if Popup.shown[REPLACE] then Click(Popup.shown[REPLACE],1) end
        Need(Deep(EditorRows(),DRAFT) and Deep(Literal(ctl.CanonicalEchoes()),DRAFT) and not NexusFlexiblePlanChooser:IsShown()
            and NexusWishlistNameInput:GetText()=='' and attempts==1,
            'COEXIST setup Open as new Wishlist draft installs the exact editor draft 410002x2 410003x1')
        NexusWishlistNameInput:SetText(SAVE1)
        local create=CreateButton()
        Need(create~=nil,'COEXIST setup the visible Create unassigned control')
        create:Click()
        local save1=Popup.shown[CREATE]
        Need(save1~=nil and type(save1.data)=='table' and save1.data.slot==0 and save1.data.name==SAVE1
            and Deep(Literal(save1.data.echoes),DRAFT) and Popup.shown[REPLACE]==nil,
            'COEXIST setup the real Save confirmation names the exact unassigned draft')
        Click(save1,1)
        local held=ctl.PendingApply()
        Need(held~=nil and Popup.shown[CREATE]==nil and editor.IsApplyPending()==true and held.slot==0 and held.name==SAVE1
            and type(held.tries)=='number' and Deep(Literal(held.echoes),DRAFT) and held.echoes==save1.data.echoes,
            'COEXIST CONTROL its Accept leaves a real nonnil retry holding the accepted payload: slot 0, name, tries and literal rows')
        local retryEchoes=held.echoes
        Need(attempts==2 and lastWhy=='spacing' and #H.actions==spacerActions,
            'COEXIST CONTROL the confirmed Save makes one real upload attempt, refused by the spacing before the host')
        NexusFlexiblePlanEntry:Click()
        Need(NexusFlexiblePlanChooser:IsShown() and Deep(PoolCounts(),Pool({[X2]=2,[X3]=1})) and Persisted()==T.UNSAVED,
            'COEXIST setup the reopened chooser keeps the dirty pool')
        Need(Count(X2,1) and Count(X3,2) and Deep(PoolCounts(),Pool({[X2]=1,[X3]=2})) and PoolStatus()=='',
            'COEXIST setup a different committed choice 410002x1 410003x2 with no pending input')
        NexusFlexiblePlanOpen:Click()
        local rq=Popup.shown[REPLACE]
        Need(rq~=nil and type(rq.data)=='table' and (ctl.PendingApply() or {}).echoes==retryEchoes,
            'COEXIST setup an Open as new Wishlist draft replacement request is shown while the confirmed Save waits')
        local replaceHides=Hidden(REPLACE)
        local before,pendingMap=Snap(),ctl.PendingRows()
        local function Kept(label)
            local r=ctl.PendingApply()
            check(Deep(Snap(),before) and r~=nil and r.echoes==retryEchoes and ctl.PendingRows()==pendingMap
                and editor.IsApplyPending()==true and F.Serialize(Raw())==savedRoot,
                label..' keeps the editor rows, maps, name, contexts, destination, the waiting retry and its payload, held, saved root, traffic and upload attempts')
        end
        NexusFlexiblePlanLoad:Click()
        local ask1=Popup.shown[LOAD]
        Need(ask1~=nil and Persisted()==T.ASK_LOAD..' '..T.UNSAVED and Popup.shown[REPLACE]==rq,
            'COEXIST Load saved over the dirty pool asks its own question; the replacement request stays shown')
        Kept('COEXIST asking to load')
        Click(ask1,2)
        check(Popup.shown[LOAD]==nil and Popup.shown[REPLACE]==rq and Hidden(REPLACE)==replaceHides
            and Deep(PoolCounts(),Pool({[X2]=1,[X3]=2})) and PoolStatus()=='' and Persisted()==T.UNSAVED
            and Budget():find('^2 / 256 alternatives%s+Chosen: 3 / 79 ordinary copies$')~=nil,
            'COEXIST Load Cancel keeps the literal chooser counts, no pending input and the replacement request')
        Kept('COEXIST Load Cancel')
        NexusFlexiblePlanLoad:Click()
        local ask2=Popup.shown[LOAD]
        Need(ask2~=nil and ask2~=ask1,'COEXIST setup a fresh current Load question')
        Click(ask2,1)
        check(Popup.shown[LOAD]==nil and Deep(PoolCounts(),Pool({[X3]=3,[X5]=2})) and Persisted()==T.LOADED
            and Budget():find('^2 / 256 alternatives%s+Chosen: 5 / 79 ordinary copies$')~=nil and PoolStatus()==''
            and Popup.shown[REPLACE]==rq and Hidden(REPLACE)==replaceHides,
            'COEXIST CONTROL the fresh Load Accept installs exactly the saved pool 410003x3 410005x2, in the chooser only')
        Kept('COEXIST the accepted pool Load')
        Click(rq,1)
        check(Popup.shown[REPLACE]==nil and NexusFlexiblePlanChooser:IsShown() and PoolStatus()==Reason('PLAN_CHANGED')
            and Deep(PoolCounts(),Pool({[X3]=3,[X5]=2})),
            'COEXIST the earlier replacement request, accepted after the pool Load, is refused PLAN_CHANGED in the chooser')
        Kept('COEXIST the refused replacement Accept')
        NexusFlexiblePlanReset:Click()
        Need(Add(X2) and Add(X3) and Count(X2,1) and Count(X3,2) and Deep(PoolCounts(),Pool({[X2]=1,[X3]=2}))
            and PoolStatus()=='','COEXIST setup restores the replacement request choice 410002x1 410003x2 through real controls')
        StaticPopupDialogs[REPLACE].OnAccept(rq.frame,rq.data)
        StaticPopupDialogs[REPLACE].OnCancel(rq.frame,rq.data)
        check(Popup.shown[REPLACE]==nil and Hidden(REPLACE)==replaceHides+1 and PoolStatus()==Reason('EDITOR_CHANGED')
            and Deep(PoolCounts(),Pool({[X2]=1,[X3]=2})),
            'COEXIST the replayed replacement callbacks install nothing once the choice is restored; the retired request is refused')
        Kept('COEXIST the replayed replacement callbacks')
        local load=StaticPopupDialogs[LOAD]
        for _,r in ipairs({ask1,ask2}) do load.OnAccept(r.frame,r.data);load.OnCancel(r.frame,r.data) end
        check(Popup.shown[LOAD]==nil and Deep(PoolCounts(),Pool({[X2]=1,[X3]=2})) and Persisted()==T.UNSAVED,
            'COEXIST replayed cancelled and accepted Load requests install nothing')
        Kept('COEXIST the replayed Load callbacks')
        -- Cleanup through the supported editor New and chooser Reset. The
        -- editor's own pump then retires any retry whose draft changed; it
        -- cannot upload, because the draft token changed.
        local cleanupUploads=attempts
        editor.NewWishlist()
        editor._PumpApplyRetry()
        NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
        NexusFlexiblePlanSearch:SetText('')
        Need(ctl.PendingApply()==nil and not editor.IsApplyPending() and editor.DebugPendingCount()==0
            and NexusWishlistNameInput:GetText()=='' and Popup.shown[CREATE]==nil and Popup.shown[REPLACE]==nil
            and Popup.shown[LOAD]==nil and NexusFlexiblePlanChooser:IsShown() and next(PoolCounts())==nil
            and attempts==cleanupUploads and #H.actions==spacerActions and F.Serialize(Raw())==savedRoot,
            'COEXIST cleanup leaves no waiting Save, popup or further upload attempt and keeps the saved pool')
        local bad={{spellId=0,quality=0,stacks=1}}
        local _,during=realUpload(0,'Coexist probe',bad)
        H.Advance(3,0.25)
        local _,ended=realUpload(0,'Coexist probe',bad)
        Need(during=='spacing' and ended=='invalid exact Echo target' and attempts==cleanupUploads,
            'COEXIST CONTROL the checks above ran inside the spacer window; after H.Advance(3,0.25) a malformed target reaches its validation reason, not spacing')
        Nexus.GameAdapter.UploadWishlist=realUpload
        check(Nexus.GameAdapter.UploadWishlist==realUpload,'COEXIST the public upload function is restored before the next baselines')

        -- Episode 2: no spacing. The same forwarding counter counts attempts
        -- again, so any attempt would reach the host and be seen.
        Nexus.GameAdapter.UploadWishlist=Counted
        local DRAFT2={{spellId=X2,quality=2,stacks=1},{spellId=X5,quality=1,stacks=4}}
        Need(Add(X2) and Add(X5) and Count(X2,1) and Count(X5,4),'COEXIST setup a second choice 410002x1 410005x4 through real Add and Set')
        NexusFlexiblePlanOpen:Click()
        if Popup.shown[REPLACE] then Click(Popup.shown[REPLACE],1) end
        NexusFlexiblePlanEntry:Click()
        NexusWishlistNameInput:SetText(SAVE2)
        create=CreateButton()
        Need(create~=nil,'COEXIST setup the visible Create unassigned control for the second draft')
        create:Click()
        local save2=Popup.shown[CREATE]
        Need(Deep(EditorRows(),DRAFT2) and NexusFlexiblePlanChooser:IsShown() and Deep(PoolCounts(),Pool({[X2]=1,[X5]=4}))
            and save2~=nil and type(save2.data)=='table' and save2.data.slot==0 and save2.data.name==SAVE2
            and Deep(Literal(save2.data.echoes),DRAFT2) and ctl.PendingApply()==nil and attempts==cleanupUploads,
            'COEXIST setup an open, unconfirmed Save confirmation for the exact draft 410002x1 410005x4 beside the chooser')
        local base=Snap()
        local function Survives(label)
            check(Deep(Snap(),base) and Popup.shown[CREATE]==save2 and ctl.PendingApply()==nil and F.Serialize(Raw())==savedRoot,
                label..' keeps the open Save confirmation shown and unhidden, the editor draft, maps, name, contexts, destination, saved root, traffic and upload attempts')
        end
        PoolRow(X5).count:SetText('3')
        NexusFlexiblePlanLoad:Click()
        local l1=Popup.shown[LOAD]
        Need(l1~=nil and Persisted()==T.ASK_LOAD..' '..T.PENDING,'COEXIST Load saved over pending count input asks its own question')
        Survives('COEXIST asking to load')
        Click(l1,2)
        check(Popup.shown[LOAD]==nil and Deep(PoolCounts(),{[X2]={n=1,text='1',set='Set'},[X5]={n=4,text='3',set='Set *'}})
            and PoolStatus()==Reason('COUNT_PENDING') and Persisted()==T.PENDING,
            'COEXIST Load Cancel keeps the committed counts and the pending count text')
        Survives('COEXIST Load Cancel')
        PoolRow(X5).count:SetText('4')
        NexusFlexiblePlanLoad:Click()
        local l2=Popup.shown[LOAD]
        local loadHides=Hidden(LOAD)
        NexusFlexiblePlanLoad:Click()
        local l3=Popup.shown[LOAD]
        Need(l2~=nil and l3~=nil and l3~=l2 and Hidden(LOAD)==loadHides+1,'COEXIST setup a newer Load question retires only the former one')
        for _,r in ipairs({l1,l2}) do load.OnAccept(r.frame,r.data);load.OnCancel(r.frame,r.data) end
        check(Popup.shown[LOAD]==l3 and Hidden(LOAD)==loadHides+1 and Deep(PoolCounts(),Pool({[X2]=1,[X5]=4}))
            and Persisted()==T.ASK_LOAD..' '..T.UNSAVED,
            'COEXIST stale Load Accept and Cancel callbacks keep the newer Load question and install nothing')
        Survives('COEXIST the stale Load callbacks')
        Click(l3,1)
        check(Popup.shown[LOAD]==nil and Deep(PoolCounts(),Pool({[X3]=3,[X5]=2})) and Persisted()==T.LOADED,
            'COEXIST CONTROL the newer Load Accept installs exactly the saved pool while the Save confirmation waits')
        Survives('COEXIST the accepted pool Load')
        NexusFlexiblePlanReset:Click();NexusFlexiblePlanSave:Click()
        local c1=Popup.shown[CLEAR]
        Need(c1~=nil,'COEXIST setup a remove question for the empty pool')
        Click(c1,2)
        NexusFlexiblePlanSave:Click()
        local c2=Popup.shown[CLEAR]
        Need(c2~=nil and c2~=c1 and Persisted()==T.ASK_CLEAR..' '..T.UNSAVED_EMPTY,'COEXIST setup a fresh current remove question')
        local clearDialog=StaticPopupDialogs[CLEAR]
        clearDialog.OnAccept(c1.frame,c1.data);clearDialog.OnCancel(c1.frame,c1.data)
        load.OnAccept(l3.frame,l3.data);load.OnCancel(l3.frame,l3.data)
        check(Popup.shown[CLEAR]==c2 and next(PoolCounts())==nil and Persisted()==T.ASK_CLEAR..' '..T.UNSAVED_EMPTY,
            'COEXIST a stale remove Accept/Cancel and a replayed accepted Load keep the newer remove question and the saved pool')
        Survives('COEXIST the stale remove and Load callbacks')
        Click(c2,2)
        clearDialog.OnAccept(c2.frame,c2.data)
        check(Popup.shown[CLEAR]==nil and Persisted()==T.UNSAVED_EMPTY,
            'COEXIST the current remove Cancel and its replayed Accept remove nothing')
        Survives('COEXIST the remove Cancel and its replay')
        local actionsBefore=#H.actions
        Click(save2,1)
        local upload=H.actions[#H.actions] or {}
        check(Popup.shown[CREATE]==nil and attempts==base.uploads+1 and lastWhy==nil and #H.actions==actionsBefore+1
            and upload[1]=='upload' and upload[2]==0 and upload[3]==SAVE2 and Deep(Literal(upload[4]),DRAFT2)
            and ctl.PendingApply()==nil and F.Serialize(Raw())==savedRoot,
            'COEXIST CONTROL the surviving Save confirmation still saves: one real upload of its exact draft reaches the host; the saved pool is unchanged')
        editor.NewWishlist();NexusFlexiblePlanEntry:Click();NexusFlexiblePlanReset:Click()
        NexusFlexiblePlanSearch:SetText('')
        Nexus.GameAdapter.UploadWishlist=realUpload
        check(Nexus.GameAdapter.UploadWishlist==realUpload and ctl.PendingApply()==nil and Popup.shown[CREATE]==nil
            and Popup.shown[LOAD]==nil and Popup.shown[CLEAR]==nil and Popup.shown[REPLACE]==nil,
            'COEXIST cleanup restores the public upload function and leaves no popup or waiting Save')
        -- PENDING acceptance, not covered by this block: unverified fault
        -- injection; unknown, future, read-only, malformed, loading, owner and
        -- root refusal presentation in the UI; docs, the final full suite,
        -- content checks and independent UltraCode Spec/Standards reviews.
    end
end
print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed))
if failed>0 then os.exit(1) end
