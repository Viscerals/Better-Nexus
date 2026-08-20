-- Safe mixed-version behavior: exact-evidence DPS remains compatible, while
-- legacy packets that cannot carry that evidence are rejected.
local H=dofile('tests/harness.lua')
dofile('core/Codec.lua'); dofile('core/SyncProtocol.lua'); dofile('core/SyncTransport.lua'); dofile('core/SyncCompatibility.lua'); dofile('core/SyncReconciler.lua'); dofile('core/SyncInbound.lua'); dofile('core/SyncDiagnostics.lua'); dofile('core/SyncSession.lua'); dofile('core/Sync.lua'); dofile('core/DpsCapture.lua')
local Codec,Sync,DPS=Nexus.Codec,Nexus.Sync,Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName='Localhero'; UnitName=function() return currentName end
UnitClass=function() return 'Mage','MAGE' end
UnitLevel=function() return 80 end
GetNormalizedRealmName=function() return 'Ebonhold' end
local function Pump(seconds)
    for _=1,math.ceil(seconds/0.2) do clock=clock+0.2; Sync.OnUpdate(0.2) end
end
local function Parts(text)
    text=tostring(text or ''):gsub('||','|'); local out={}
    for part in text:gmatch('([^|]*)|?') do out[#out+1]=part; if #out>12 then break end end
    return out
end
local function DecodeDps(messages)
    local chunks,total={},nil
    for _,message in ipairs(messages) do
        local p=Parts(message.text)
        if p[1]=='WLD2' then
            local i,n=tostring(p[4]):match('^(%d+)/(%d+)$'); i,n=tonumber(i),tonumber(n)
            total=total or n; chunks[i]=p[5]
        end
        assert(#message.text<=255,'wire message exceeded 255 bytes')
    end
    assert(total and total>0,'no exact-evidence DPS payload was sent')
    local joined={}; for i=1,total do assert(chunks[i],'missing DPS chunk'); joined[#joined+1]=chunks[i] end
    return Codec.JSONDecode(Codec.Base64Decode(table.concat(joined)))
end

local echoes={{spellId=200100,stacks=1},{spellId=200102,stacks=2}}
local fp,hash=DPS.GetEchoKey(echoes),DPS.GetEchoHash(echoes)
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Codec,{}); DPS.Init({},Sync)
local record={protocolVersion=7,fingerprint=fp,loadoutHash=hash,echoes=echoes,
    category='dummy',dps=25000000,duration=65,ts=49000,player='Localhero',class='MAGE',
    ownerKey='localhero@ebonhold',realm='ebonhold',level=80,buildId='dps-local'}
H.sentChatMessages={}; assert(Sync.BroadcastDpsRecord(record,'local')); Pump(8)
local payload=DecodeDps(H.sentChatMessages)
assert(payload.v==7 and payload.f==fp and payload.h==hash and type(payload.e)=='table',
    'current wire lost exact Echo evidence')
assert(payload.p=='Localhero' and payload.k=='MAGE' and payload.o=='localhero@ebonhold',
    'current wire lost sender identity evidence')

-- Localized player names are valid in both the WLD2 envelope and its transfer
-- ID. Exercise outbound generation and inbound reassembly with UTF-8 bytes.
currentName='Duká'
local localizedRecord={protocolVersion=7,fingerprint=fp,loadoutHash=hash,echoes=echoes,
    category='dummy',dps=26000000,duration=66,ts=49001,player='Duká',class='MAGE',
    ownerKey='duká@ebonhold',realm='ebonhold',level=80,buildId='dps-localized'}
H.sentChatMessages={}
assert(Sync.BroadcastDpsRecord(localizedRecord),
    'localized player name was rejected from DPS transfer ID')
Pump(8)
local localizedMessages=H.sentChatMessages
local localizedPayload=DecodeDps(localizedMessages)
assert(localizedPayload.p=='Duká','localized DPS identity changed on the wire')

currentName='Receiver'
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Codec,{}); DPS.Init({},Sync)
for _,message in ipairs(localizedMessages) do
    Sync.HandleIncoming(message.text,'Duká')
end
local receivedLocalized=false
for _,row in pairs(NexusDB.dpsCapture.characterBest.dummy or {}) do
    if row.player=='Duká' then receivedLocalized=true end
end
assert(receivedLocalized,'localized DPS transfer was rejected during reassembly')

-- A v6 peer remains acceptable only when it supplies the same complete proof.
assert(DPS.ReceiveRecord({v=6,f=fp,h=hash,e=echoes,c='dummy',d=18000000,u=61,t=40000,
    p='Legacy',k='MAGE',o='legacy@ebonhold',r='ebonhold',l=80,b='legacy-build'},'Legacy'),
    'safe v6 exact-evidence record was rejected')
assert(not DPS.ReceiveRecord({v=6,h=hash,c='dummy',d=19000000,u=61,t=40001,
    p='Legacy',k='MAGE',o='legacy@ebonhold',r='ebonhold',l=80,b='missing-evidence'},'Legacy'),
    'v6 record without an Echo list entered the verified board')
assert(not DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c='dummy',d=19000000,u=61,t=40002,
    p='Legacy',k='MAGE',o='legacy@ebonhold',r='ebonhold',l=80},'Spoofer'),
    'transport sender spoof gained DPS authority')

-- The evidence-free WLDS format is retired, including the historical huge-DPS exploit.
local before=#DPS.GetDpsBoard('dummy')
Sync.HandleIncoming('WLDS|Attacker|victim|dummy|999999999999|80|Attacker','Attacker')
assert(#DPS.GetDpsBoard('dummy')==before,'legacy enormous/no-duration DPS was accepted')
print('safe v6 compatibility, localized protocol 7 wire, and legacy rejection -- OK')
