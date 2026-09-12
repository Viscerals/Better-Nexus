-- Current peers reconcile complete builds; compact indexes remain a safe
-- compatibility path for an older summary-only peer.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/SyncProtocol.lua'); dofile('core/SyncTransport.lua'); dofile('core/SyncCompatibility.lua'); dofile('core/SyncReconciler.lua'); dofile('core/SyncInbound.lua'); dofile('core/SyncDiagnostics.lua'); dofile('core/SyncSession.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local function AwaitCatalog()
    local catalog=Nexus.BuildCatalog
    for _=1,4 do
        if not catalog.RootState().candidate then return true end
        assert(catalog.RootState().state=='ROOT_ADMITTED',
            'index fixture found non-mutation catalog work')
        local ticket=catalog.PumpRootAdmission()
        assert(type(ticket)=='table','index catalog work returned no ticket')
        local previous=tonumber(ticket.pumps) or -1
        for _=1,catalog.Budget().maximumPumps do
            if ticket.state~='pending' then break end
            local observed=catalog.PumpRootAdmission()
            assert(observed==ticket,'index catalog work changed tickets')
            local current=tonumber(ticket.pumps)
            assert(current and current>previous,'index catalog work made no progress')
            previous=current
        end
        assert(ticket.state~='pending','index catalog work exhausted its bound')
        assert(ticket.state=='committed' and ticket.committed,
            ticket.reason or 'index catalog work failed')
    end
    error('index fixture produced too many catalog candidates')
end
local who='Source'; UnitName=function() return who end
-- Exactly 79 ordinary copies: the valid maximum under issue #22, still a
-- 79-row payload that must chunk.
local echoes={}; for i=1,79 do echoes[i]={spellId=200000+i,stacks=1,quality=3} end
local build={id='build-79',title='AoE | ST',description=string.rep('description ',50),
    author='Source',ownerKey='source@ebonhold',ownerVerified=true,
    realm='ebonhold',class='MAGE',echoes=echoes,
    postedAt=10,lastModified=10,isMine=true}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{}); Nexus.DpsCapture.Init({},Sync)

H.sentChatMessages={}
Sync.HandleIncoming('WLRQ|Receiver|0|0|req-current','Receiver')
Pump(300)
local complete={}; for _,m in ipairs(H.sentChatMessages) do
    if m.text:find('^WLRB') then complete[#complete+1]=m end
    assert(#m.text<=255,'full-loadout chunk exceeded 255 chars')
end
assert(#complete>1,'complete 79-Echo reconciliation was not chunked')

who='Receiver'; NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
H.AdmitCatalogV1(NexusDB)
clock=1200; Sync.Init(Nexus.Codec,{})
for _,m in ipairs(complete) do
    Sync.HandleIncoming(m.text,'Source-Ebonhold')
end
AwaitCatalog()
-- Legacy-to-bundle cutover: durable rows live in the bundle payload.
local loaded=H.DurableBuilds()['build-79']
assert(loaded and loaded.echoes and #loaded.echoes==79,'complete loadout did not reassemble')
assert(loaded.description:find('description'),'full description was not restored')

-- Legacy compact summaries are accepted only from their direct author and
-- remain explicitly incomplete until a background recovery succeeds.
who='Source'; NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
H.AdmitCatalogV1(NexusDB)
clock=1400; Sync.Init(Nexus.Codec,{})
H.sentChatMessages={}; assert(Sync.BroadcastBuildSummary(build)); Pump(10)
local summaries=H.sentChatMessages
who='Receiver'; NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{})
for _,m in ipairs(summaries) do
    Sync.HandleIncoming(m.text,'Source-Ebonhold')
end
AwaitCatalog()
local placeholder=H.DurableBuilds()['build-79']
assert(placeholder and not placeholder.loadoutAvailable and not placeholder.echoes,
    'legacy summary was incorrectly treated as exact evidence')
assert(placeholder.title=='AoE | ST',
    'Base64-encoded summary title containing a wire delimiter was rejected')
local immediate,why=Sync.RequestLoadout('build-79')
assert(not immediate and why,'legacy recovery request did not remain background-only')

-- A recovery rejected at the queue cap must remain immediately eligible once
-- a slot opens; rejected work must not receive the 120-second cooldown.
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{})
local recoveryLimit=Sync.WorkState().maxRecoveryQueue
for i=1,recoveryLimit do
    local sent,reason=Sync.RequestLoadout('recovery-'..i)
    assert(not sent and reason=='queued for background recovery',
        'recovery queue rejected work before its documented cap')
end
assert(Sync.WorkState().recovery==recoveryLimit,
    'recovery queue did not reach its documented cap')
local sentOverflow,overflowReason=Sync.RequestLoadout('recovery-overflow')
assert(not sentOverflow and overflowReason=='awaiting sync',
    'overflow recovery request was not rejected explicitly')
Sync.OnUpdate(1.6)
assert(Sync.WorkState().recovery==recoveryLimit-1,
    'recovery pump did not release one queue slot')
local sentRetry,retryReason=Sync.RequestLoadout('recovery-overflow')
assert(not sentRetry and retryReason=='queued for background recovery',
    'rejected recovery request was incorrectly left on cooldown')
assert(Sync.WorkState().recovery==recoveryLimit,
    'immediate recovery retry did not enter the released slot')

print('complete current sync, legacy recovery, and cooldown admission -- OK')
