-- #151 binding slice: chooser persistence callbacks over the real Store facade.
-- Real TOC boot with synthetic format-5 data, the actual chooser Factory.New
-- with the real FlexiblePlanStore facade and a tiny literal catalog. Rows are
-- driven through the rendered Add/Set/Reset controls; counts are read from the
-- rendered pool rows. SavePool/LoadPool/PersistenceState are called directly
-- here; the MAIN PRESENTATION block at the end drives the visible Save pool /
-- Load saved buttons, the persistence status line and editor-opened readback
-- across fresh boots. Unverified fault injection, unknown/future/read-only
-- presentation and the real editor retry/replace interplay are PENDING for the
-- next slice. The popup host is the identity-aware
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
-- Unknown/future/read-only presentation, unverified fault injection and the
-- editor Save-retry/replace interplay are queued for the next slice.
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
end
print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed))
if failed>0 then os.exit(1) end
