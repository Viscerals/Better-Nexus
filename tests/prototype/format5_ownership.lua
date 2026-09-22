-- Known saved format 5: a plain-name row is carried into name@realm only with
-- established ownership. Ambiguous or unestablished rows are preserved,
-- unread, never merged or deleted. An existing canonical row always wins.
-- Real TOC boot and Store; synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local owner=function()return Nexus.MainInternals.StoreAuthorityOwner end

local function Case(label,mutate,expect)
 local db=F.Database({mutate=mutate})
 local originals={}
 for k,v in pairs(db.chars)do originals[k]=F.Serialize(v)end
 local ledger=F.Serialize(db.accountCharacters)
 F.Boot(db)
 check(Nexus.StartupStatus().coreReady,label..': local start-up completes')
 local status=Nexus.Store.StateWriteStatus()
 check(status.mode=='durable',label..': the known format is writable: '..tostring(status.reason))
 check((status.carriedFrom~=nil)==(expect.carry==true),label..': carry decision '..tostring(status.carriedFrom))
 local state=Nexus.Store.State()
 local hasPlan=type(state.loadoutWishlists)=='table' and type(state.loadoutWishlists[1])=='table'
  and state.loadoutWishlists[1].name=='Gen plan'
 check(hasPlan==(expect.plan==true),label..': the read shows the plan only when owned or already canonical')
 assert(owner().UpdateStateV1(function(row)row.ownershipProbe=label end))
 local canonical=NexusDB.chars[F.OWNER]
 check(type(canonical)=='table' and canonical.ownershipProbe==label,label..': the write is durable')
 check((canonical.savedFormatCarry~=nil)==(expect.carry==true),label..': the canonical row is a carry only when owned')
 for k,v in pairs(originals)do
  if k~=F.OWNER then check(F.Serialize(NexusDB.chars[k])==v,label..': row '..k..' is preserved unchanged')end
 end
 check(F.Serialize(NexusDB.accountCharacters)==ledger,label..': the ledger is unchanged')
 check(NexusDB.settingsVersion==5,label..': the saved marker is unchanged')
 if expect.after then expect.after(canonical) end
end

Case('owned row',nil,{carry=true,plan=true})
Case('same name on a second realm',function(db)
 db.accountCharacters['prototypetester@otherrealm']={name=F.NAME,realm='OtherRealm',class='PRIEST',lastSeen=1}
end,{carry=false,plan=false})
Case('no ledger row for this character',function(db)
 db.accountCharacters={['someoneelse@ebonhold']={name='SomeoneElse',realm=F.REALM}}
end,{carry=false,plan=false})
Case('ledger row names another realm',function(db)
 db.accountCharacters={[F.OWNER]={name=F.NAME,realm='OtherRealm'}}
end,{carry=false,plan=false})
Case('two case variants of the name',function(db)
 db.chars.prototypetester=F.Row({unknownGenField={keep='variant'}})
end,{carry=false,plan=false})
Case('legitimately missing row',function(db)db.chars={}end,{carry=false,plan=false})
Case('canonical row already present',function(db)
 db.chars[F.OWNER]={loadoutWishlists={},orbRefinement={pending={id='synthetic-pending',spent=1},exposure=1},canonicalOnly=true}
end,{carry=false,plan=false,after=function(canonical)
 check(canonical.canonicalOnly==true and canonical.orbRefinement.pending.id=='synthetic-pending'
  and canonical.orbRefinement.exposure==1,'canonical present: its pending receipt and exposure are kept, nothing merged')
 check(next(canonical.loadoutWishlists)==nil,'canonical present: the plain-name plan is not merged in')
end})
print('PASS format5_ownership: owned carry, second realm, no ledger, foreign realm, case variants, missing row, canonical wins checks='..checks)
