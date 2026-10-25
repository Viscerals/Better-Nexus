-- #151 binding slice: chooser persistence callbacks over the real Store facade.
-- Real TOC boot with synthetic format-5 data, the actual chooser Factory.New
-- with the real FlexiblePlanStore facade and a tiny literal catalog. Rows are
-- driven through the rendered Add/Set/Reset controls; counts are read from the
-- rendered pool rows. SavePool/LoadPool/PersistenceState are called directly:
-- visible Save/Load buttons, status presentation, editor-opened chooser
-- readback, unverified fault injection and the real editor retry/replace
-- interplay are PENDING for later slices. The popup host is the identity-aware
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
print(string.format('flexible_plan_persistence_chooser: %d passed, %d failed',passed,failed))
if failed>0 then os.exit(1) end
