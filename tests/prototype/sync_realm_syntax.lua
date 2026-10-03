-- A transport sender is Name-Realm. The character name keeps its strict
-- grammar; the realm uses the one RealmKey grammar, which also allows the
-- parentheses of a real realm such as "Rogue-Lite (Live)". Before this was
-- split, ValidPlayer applied the character rules to the whole token, so a
-- qualified sender with a parenthesised realm was refused in PlayerKey,
-- SameTransportSender and the inbound envelope, before TransportOwns could
-- compare it with the (already accepted) owner key.
--
-- Authority does not change: ownership is still exact canonical equality of
-- name@realm taken from the ACTUAL sender; a bare actual sender never proves an
-- owner; nothing is stripped, aliased or borrowed. Synthetic names only; no
-- native API, account data or network. Part 1 is the identity grammar, part 2
-- the record-coherence callers, part 3 the real CHANNEL receive path.
local failures, checks = {}, 0
local function check(ok, label)
 checks=checks+1
 if not ok then failures[#failures+1]=label;print('FAIL '..label) end
end
dofile('core/Identity.lua')
local I=Nexus.Identity
local function Q(s) return string.format('%q',s) end

-- Part 1a: realms that must be accepted, with exact canonical identities.
local REALMS={
 {'Ebonhold','ebonhold'},{'Rogue-LiteLive','rogue-litelive'},
 {'Rogue-Lite(Live)','rogue-lite(live)'},{'X(Y)','x(y)'},
 {'ROGUE-LITE(LIVE)','rogue-lite(live)'},{"Mal'Ganis",'mal\'ganis'},
 {'Realm_2','realm_2'},
 {'X(Y)-Z','x(y)-z'},
}
for _,case in ipairs(REALMS) do
 local realm,key=case[1],case[2]
 local sender='Probe-'..realm
 local owner=I.OwnerKey('Probe',realm)
 check(owner=='probe@'..key,'owner key '..realm)
 check(I.ValidPlayer(sender)==true,'ValidPlayer accepts '..sender)
 check(I.PlayerKey(sender,true)=='probe-'..key,'PlayerKey(full) '..sender)
 check(I.PlayerKey(sender)=='probe','PlayerKey(short) '..sender)
 check(I.DisplayPlayer(sender)=='Probe','DisplayPlayer '..sender)
 check(I.CanonicalOwnerFromTransport(sender)=='probe@'..key,'canonical owner from transport '..sender)
 check(I.TransportOwns(owner,sender)==true,'matching actual sender owns '..sender)
 check(I.TransportOwns(owner,sender:upper())==true,'ASCII case folds '..sender)
 check(I.SameTransportSender(sender,sender)==true,'identical envelope '..sender)
 check(I.SameTransportSender(sender,sender:upper())==true,'envelope folds ASCII case '..sender)
 check(I.SamePlayer(sender,'Probe')==true,'same player ignores realm '..sender)
end
-- The durable form of the configured realm text drops its whitespace only
-- because it is trusted local input; the transport form must already match.
check(I.OwnerKey('Probe','Rogue-Lite (Live)')=='probe@rogue-lite(live)','trusted local realm whitespace')
check(I.TransportOwns('probe@rogue-lite(live)','Probe-Rogue-Lite(Live)')==true,'configured realm owns its sender')

-- Part 1b: authority boundaries. Each of these must stay false/nil.
local owner
for _,realm in ipairs({'Ebonhold','Rogue-Lite(Live)','Rogue-LiteLive'}) do
 owner=I.OwnerKey('Probe',realm)
 check(not I.TransportOwns(owner,'Other-'..realm),'wrong name never owns '..realm)
 check(not I.TransportOwns(owner,'Probe-OtherRealm'),'wrong realm never owns '..realm)
 check(not I.TransportOwns(owner,'Probe'),'bare sender never owns '..realm)
 check(not I.TransportOwns(owner,nil),'nil sender never owns '..realm)
 check(not I.SameTransportSender('Probe-'..realm,'Other-'..realm),'envelope other name '..realm)
 check(not I.SameTransportSender('Probe-'..realm,'Probe-OtherRealm'),'envelope other realm '..realm)
end
for _,pair in ipairs({
 {'Probe-Rogue-Lite(Live)','Probe-Rogue-LiteLive'},
 {'Probe-Rogue-LiteLive','Probe-Rogue-Lite(Live)'},
 {'Probe-Rogue-Lite(Live)','Probe-Rogue-Lite(Liv)'},
 {'Probe-Rogue-Lite(Live)','Probe-Rogue-Lite-Live'},
 {'Probe-X(Y)','Probe-XY'},{'Probe-X(Y)','Probe-X-Y'},
}) do
 local a,b=pair[1],pair[2]
 check(I.CanonicalOwnerFromTransport(a)~=I.CanonicalOwnerFromTransport(b),'no punctuation alias '..a..' vs '..b)
 check(not I.TransportOwns(I.CanonicalOwnerFromTransport(a),b),'alias cannot own '..a..' / '..b)
 check(not I.SameTransportSender(a,b),'alias envelope refused '..a..' / '..b)
end
check(not I.TransportOwns('probe@rogue-lite(live)','Probe-Rogue-LiteLive'),'owner with parentheses vs stripped sender')
check(not I.TransportOwns('probe@rogue-litelive','Probe-Rogue-Lite(Live)'),'stripped owner vs sender with parentheses')

-- Part 1c: malformed or spoofing tokens. No grammar, key or authority.
local MALFORMED={
 'Pro(be)','Pro(be)-Ebonhold','(Probe)-Ebonhold','Probe(-Ebonhold',
 'Probe@evil','Probe-Ebonhold@evil','Probe-Rogue-Lite(Live)@evil',
 'Probe|evil','Probe-Ebonhold|evil','Probe-Rogue-Lite(Live)|evil',
 'Probe\nEvil','Probe-Ebonhold\n','Probe-Rogue-Lite(Live)\n','Probe\tEvil','Probe-Ebonhold\t',
 'Probe--Ebonhold','Probe-Rogue--Lite(Live)','-Probe','-Ebonhold','Probe-','Probe-Realm-','Probe--',
 'Probe-Rogue-Lite (Live)','Probe -Ebonhold','Probe- Ebonhold','Probe-Rogue-Lite\194\160(Live)',
 'Probe-Rogue-Lite\226\128\168(Live)','Probe-Rogue-Lite\226\128\169(Live)',
 'Probe-Ebonhold\226\128\174','Probe-Rogue-Lite(Live)\226\128\174','Pro\226\128\174be-Ebonhold',
 'Probe-Rogue-Lite(\226\128\171Live)','Probe-\226\128\139Ebonhold','Probe-Rogue-Lite\239\187\191(Live)',
 'Probe-\255','Probe-Rogue-Lite(Liv\255)','Probe-Ebonhold\192\175','Probe-\226\128','Pro\255be-Ebonhold',
 'Probe-Rogue.Lite(Live)','Probe-Rogue/Lite(Live)','Probe-[Live]','Probe-{Live}','Probe-Ebon,hold',
 '','-',
 'Probe-Rogue-Lite(Live)-','Probe-(Live)--x','Probe-\195\131\194\169','Pro\195\131\194\169be-Ebonhold',
 string.rep('P',81),'Probe-'..string.rep('R',72)..'(Y)',
}
for _,bad in ipairs(MALFORMED) do
 local label=Q(bad)
 check(I.ValidPlayer(bad)==false,'ValidPlayer refuses '..label)
 check(I.PlayerKey(bad)==nil and I.PlayerKey(bad,true)==nil,'PlayerKey refuses '..label)
 check(I.DisplayPlayer(bad)==nil,'DisplayPlayer refuses '..label)
 check(I.CanonicalOwnerFromTransport(bad)==nil,'no canonical owner from '..label)
 check(not I.TransportOwns('probe@ebonhold',bad) and not I.TransportOwns('probe@rogue-lite(live)',bad),'no authority from '..label)
 check(not I.SameTransportSender(bad,'Probe-Ebonhold') and not I.SameTransportSender('Probe-Ebonhold',bad),'envelope refuses '..label)
end
-- Pinned, pre-existing RealmKey behaviour: parentheses are not required to balance
-- or to follow a letter. Authority is exact string equality of the canonical
-- realm, so such a realm only ever owns its own identical spelling.
check(I.ValidPlayer('Probe-Rogue-Lite(Live')==true and I.ValidPlayer('Probe-(Live)')==true,'unbalanced or leading parenthesis is a valid realm spelling')
check(I.TransportOwns('probe@rogue-lite(live','Probe-Rogue-Lite(Live')==true,'unbalanced realm owns only itself')
check(not I.TransportOwns('probe@rogue-lite(live','Probe-Rogue-Lite(Live)') and not I.TransportOwns('probe@rogue-lite(live)','Probe-Rogue-Lite(Live'),'unbalanced realm never aliases the balanced one')
-- Byte bound: the whole qualified token is at most 80 bytes.
local limit='Probe-'..string.rep('R',71)..'(Y)'
check(#limit==80 and I.ValidPlayer(limit)==true,'80-byte qualified token is accepted')
check(I.ValidPlayer(limit..'Z')==false,'81-byte qualified token is refused')
check(I.ValidPlayer(string.rep('P',80))==true and I.ValidPlayer(string.rep('P',81))==false,'bare name byte bound')
-- Owner keys keep their own grammar.
check(I.CanonicalOwnerKey('PROBE@ROGUE-LITE(LIVE)')=='probe@rogue-lite(live)','owner key ASCII case folds')
for _,bad in ipairs({'pro(be)@ebonhold','probe@rogue-lite (live)','probe@@ebonhold','probe@','@ebonhold','probe-x@ebonhold','probe@eb\nonhold','probe@ebon|hold'}) do
 check(I.CanonicalOwnerKey(bad)==nil,'owner key refuses '..Q(bad))
end

-- Part 2: coherent record identity uses the same transport grammar.
local ownerKey='probe@rogue-lite(live)'
local function record(fields)
 local r={ownerKey=ownerKey,realm='Rogue-Lite (Live)'};for k,v in pairs(fields) do r[k]=v end;return r
end
check(I.CoherentRecordOwnerKey(record({author='Probe-Rogue-Lite(Live)'}))==ownerKey,'coherent record with qualified author')
check(I.CoherentRecordOwnerKey(record({author='Probe'}))==ownerKey,'coherent record with bare author')
check(I.CoherentRecordOwnerKey(record({author='Other-Rogue-Lite(Live)'}))==nil,'record author of another name refused')
check(I.CoherentRecordOwnerKey(record({author='Probe-Ebonhold'}))==nil,'record author of another realm refused')
check(I.CoherentRecordOwnerKey(record({author='Probe-Rogue-LiteLive'}))==nil,'record author alias without parentheses refused')
check(I.CoherentRecordOwnerKey(record({author='Pro(be)-Rogue-Lite(Live)'}))==nil,'record author with parenthesised name refused')
check(I.VerifiedOwnerKey(record({author='Probe-Rogue-Lite(Live)',ownerVerified=true}))==ownerKey,'verified record keeps its key')
check(I.VerifiedOwnerKey(record({author='Probe-Rogue-Lite(Live)'}))==nil,'unverified record has no verified key')

-- Part 3: the real CHANNEL receive path. Production files are loaded unchanged.
-- Same content, fresh IDs; only the owner/sender realm changes.
local P=dofile('tests/prototype/sync_pair_support.lua')
P.Boot({'Receiver','Idle'},0)
local B=P.A
local serial=0
local function deliver(realm,wireSender,actual,id,stamp,ownerOverride,authorOverride)
 serial=serial+1
 local N=B.e.Nexus
 local name='Probe'
 local sender=wireSender or (name..'-'..realm)
 local payload={id=id or ('realm-syntax-'..serial),t='Synthetic realm syntax',a=authorOverride or name,
  o=ownerOverride or N.Identity.OwnerKey(name,realm),c='MAGE',m=stamp or (1700000200+serial),
  e={{200001,1,3}},lv=1,le={{200085,1,1}}}
 local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local chunks={};for i=1,#b64,150 do chunks[#chunks+1]=b64:sub(i,i+149)end
 for i,chunk in ipairs(chunks) do
  P.Channel(B,string.format('WLRB|%s|%s|%d|%d/%d|%s',sender,payload.id,payload.m,i,#chunks,chunk),actual or sender)
 end
 for _=1,300 do P.Step() end
 return N.BuildCatalog.Get(payload.id),payload
end
for _,realm in ipairs({'Ebonhold','Rogue-LiteLive','Rogue-Lite(Live)'}) do
 local row,payload=deliver(realm)
 check(row~=nil,'CHANNEL stores matching owner '..realm)
 check(row and row.ownerVerified==true and row.ownerKey==payload.o and row.relaySender==nil and row.claimedOwnerKey==nil,'CHANNEL verified ownership '..realm)
 check(row and row.echoes[1].spellId==200001 and row.echoes[1].quality==1 and row.echoes[1].stacks==3
  and row.lockedEchoes[1].spellId==200085 and row.lockedAuthorityProven==true,'CHANNEL exact ordinary and locked roles '..realm)
end
-- Wire and actual sender must agree.
check(deliver('Ebonhold','Probe-Ebonhold','Other-Ebonhold')==nil,'CHANNEL wire/actual name mismatch stores nothing')
check(deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)','Other-Rogue-Lite(Live)')==nil,'CHANNEL parenthesised wire/actual name mismatch stores nothing')
check(deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)','Probe-Rogue-Lite(Liv)')==nil,'CHANNEL envelope realm mismatch stores nothing')
check(deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)','Probe-Rogue-LiteLive')==nil,'CHANNEL punctuation-stripped actual realm stores nothing')
check(deliver('Rogue-LiteLive','Probe-Rogue-LiteLive','Probe-Rogue-Lite(Live)')==nil,'CHANNEL punctuation-added actual realm stores nothing')
-- Malformed actual senders never reach storage.
for _,bad in ipairs({'Probe-Rogue-Lite (Live)','Probe-Rogue-Lite(Live)\226\128\174','Probe-Rogue-Lite(\255)','Pro(be)-Rogue-Lite(Live)','Probe-Rogue-Lite(Live)@x'}) do
 check(deliver('Rogue-Lite(Live)',bad,bad)==nil,'CHANNEL malformed sender stores nothing '..Q(bad))
 -- Also with a well-formed wire sender and only the actual sender malformed.
 check(deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)',bad)==nil,'CHANNEL malformed actual sender stores nothing '..Q(bad))
end
-- A bare actual sender is never owner authority, with or without a realm claim.
local short=deliver('Rogue-Lite(Live)','Probe','Probe')
check(short and short.ownerVerified~=true and short.ownerKey==nil and short.claimedOwnerKey=='probe@rogue-lite(live)','CHANNEL bare sender stays an unverified claim')
local bareWire=deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)','Probe')
check(bareWire==nil or (bareWire.ownerVerified~=true and bareWire.ownerKey==nil),'CHANNEL bare actual sender never verifies a qualified wire sender')
-- A relayer cannot assert someone else\'s owner key, in either realm spelling.
local relay=deliver('Rogue-Lite(Live)','Other-Rogue-Lite(Live)','Other-Rogue-Lite(Live)')
check(relay==nil or (relay.ownerVerified~=true and relay.ownerKey==nil),'CHANNEL relayed claim is not verified')
local crossRealm=deliver('Ebonhold','Probe-Rogue-Lite(Live)','Probe-Rogue-Lite(Live)')
check(crossRealm==nil or (crossRealm.ownerVerified~=true and crossRealm.ownerKey==nil),'CHANNEL owner key of another realm is not verified')
-- An owner key whose realm differs only by parentheses is never verified.
local strippedOwner=deliver('Rogue-Lite(Live)','Probe-Rogue-Lite(Live)','Probe-Rogue-Lite(Live)',nil,nil,'probe@rogue-litelive')
check(strippedOwner==nil or (strippedOwner.ownerVerified~=true and strippedOwner.ownerKey==nil),'CHANNEL stripped owner key is not verified for a parenthesised sender')
local addedOwner=deliver('Rogue-LiteLive','Probe-Rogue-LiteLive','Probe-Rogue-LiteLive',nil,nil,'probe@rogue-lite(live)')
check(addedOwner==nil or (addedOwner.ownerVerified~=true and addedOwner.ownerKey==nil),'CHANNEL parenthesised owner key is not verified for a stripped sender')
-- A qualified author must be exactly the owner and sender.
local qa=deliver('Rogue-Lite(Live)',nil,nil,nil,nil,nil,'Probe-Rogue-Lite(Live)')
check(qa and qa.ownerVerified==true and qa.ownerKey=='probe@rogue-lite(live)','CHANNEL exact qualified author is verified')
for _,author in ipairs({'Probe-Rogue-LiteLive','Probe-Ebonhold','Other-Rogue-Lite(Live)','Pro(be)-Rogue-Lite(Live)'}) do
 local row=deliver('Rogue-Lite(Live)',nil,nil,nil,nil,nil,author)
 check(row==nil or (row.ownerVerified~=true and row.ownerKey==nil),'CHANNEL mismatched qualified author is not verified '..author)
end
-- A newer relayed packet cannot overwrite an owner-verified record.
for _,realm in ipairs({'Ebonhold','Rogue-Lite(Live)'}) do
 local base,p=deliver(realm)
 check(base and base.ownerVerified==true,'overwrite negative starts owner-verified '..realm)
 local relayer='Impostor-'..realm
 local after=deliver(realm,relayer,relayer,p.id,p.m+1)
 check(after and after.lastModified==p.m and after.ownerKey==p.o and after.ownerVerified==true,'CHANNEL relayed newer overwrite cannot replace verified owner '..realm)
end
check(#P.A.H.actions==0 and #P.B.H.actions==0,'zero gameplay actions in harness')

print('RESULT '..(#failures==0 and 'PASS' or 'FAIL')..' checks='..checks..' failures='..#failures)
assert(#failures==0,table.concat(failures,'; '))
print('PASS sync realm syntax: a parenthesised realm is valid; ownership stays exact, actual-sender-bound and unaliased')
