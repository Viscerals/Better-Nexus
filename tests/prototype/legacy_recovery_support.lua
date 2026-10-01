-- Shared synthetic fixtures for the explicit keep-current / preserve-legacy
-- recovery tests (control BN-CONTROL-LEGACY-RECOVERY-20261001-008). Real TOC
-- boot through format5_support; synthetic data only; no profile is read.
local F=dofile('tests/prototype/format5_support.lua')
local S={F=F,STORE='nexusLegacyPreservationV1'}
local base
-- A committed format-2 current profile (authority bundle present).
function S.Current()
 if not base then
  F.Boot(F.Database({version=2}))
  assert(Nexus.StartupStatus().coreReady,'fixture: the base profile starts')
  base=F.Serialize(NexusDB)
 end
 local db=assert(loadstring('return '..base))()
 -- The receipt a reporter's profile retains: completed, decision noLegacy.
 db.nexusStoreMigrations={wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}}
 return db
end
-- A distinct, non-empty legacy table (one character); `tag` makes another value.
function S.Legacy(tag)
 tag=tag or ''
 return {settingsVersion=1,
  chars={['LegacyAlt'..tag]={loadoutWishlists={[1]={slot=1,name='Old plan'..tag,echoes={{spellId=300001,quality=2,stacks=1}}}},note='legacy'..tag}},
  customLegacy={keep=true,list={1,2,3}},[7]='numeric key',flag=false}
end
function S.Start(db,legacy)
 return F.Boot(db,function() WishlistRealizerDB=legacy end)
end
function S.Say(H,command)
 local first=#H.chat+1
 SlashCmdList.NEXUS(command)
 return table.concat(H.chat,'\n',first)
end
function S.Plain(text) return (tostring(text):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
function S.Code(H) return S.Plain(S.Say(H,'legacy')):match('/nexus legacy keep (%x+)') end
function S.Seam() return Nexus.MainInternals.AuthorityBootstrap.Preserve end
function S.Copy(value) return assert(loadstring('return '..F.Serialize(value)))() end
function S.Entries(db)
 local store=rawget(db,S.STORE)
 local list={}
 if type(store)=='table' and type(store.entries)=='table' then
  for key,entry in pairs(store.entries) do list[#list+1]=key end
 end
 table.sort(list)
 return list
end
-- A valid preservation entry for `value`.
function S.Entry(value)
 local snapshot=assert(S.Seam().Snapshot(value))
 return snapshot.digest,{version=1,source='WishlistRealizerDB',digest=snapshot.digest,
  tables=snapshot.tables,bytes=snapshot.bytes,value=snapshot.copy}
end
function S.Without(db,...)
 local copy=S.Copy(db)
 for _,key in ipairs({...}) do copy[key]=nil end
 return F.Serialize(copy)
end
return S
