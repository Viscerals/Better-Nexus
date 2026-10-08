-- Synthetic saved data in the layout of Good Enough Nexus 1.96.6
-- (SchmidtCode/Good-Enough-Nexus 7bd6b86, core/Store.lua f3f43e4): settings
-- format 5, migrations 3-5 already applied, per-character rows keyed by the
-- plain character name, account ledger keyed by canonical name@realm.
-- Values are synthetic; no player data. Shared by the format-5 regressions.
local F={}
F.NAME,F.REALM,F.OWNER='PrototypeTester','Ebonhold','prototypetester@ebonhold'
F.PLAN={{spellId=200001,quality=1,stacks=2},{spellId=200002,quality=2,stacks=3},{spellId=200003,quality=3,stacks=1}}
F.PERMANENT=200050
function F.Key(echoes)
 local parts={}
 for _,e in ipairs(echoes)do parts[#parts+1]=tostring(e.spellId)..':'..tostring(e.stacks or 1)end
 table.sort(parts);return table.concat(parts,',')
end
function F.Row(extra)
 local echoes={}
 for i,e in ipairs(F.PLAN)do echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=false}end
 local key=F.Key(echoes)
 local row={tomeTogglePending={[7]={t=11,want=true}},flagDemotions={},recordedPicks={[200001]=1},
  loadoutWishlists={[1]={slot=1,key=key,name='Gen plan',echoes=echoes}},
  lockDesignTargetsBySlot={[key]={[F.PERMANENT]=true}},
  unknownGenField={keep='row'}}
 for k,v in pairs(extra or {})do row[k]=v end
 return row
end
function F.Database(o)
 o=o or {}
 local db={settingsVersion=o.version or 5,
  settings={autoPick=false,autoSave=false,syncMode='manual',syncOnlyWhileResting=true,
   syncSuspendInCombat=true,syncSuspendedInstanceTypes={party=true,raid=true},
   syncDirectExperimental=false,communityRetentionTopAverage=40,communityRetentionMaxTotal=500,
   customGenSetting={keep='settings'}},
  accountCharacters={[F.OWNER]={name=F.NAME,realm=F.REALM,class='MAGE',lastSeen=1700000000}},
  chars={[F.NAME]=F.Row()},
  genUnknownTopLevel={keep='top'},
  nexusNativeRecoveryArchiveF5={chars={[F.NAME]={archived=true}}}}
 if o.mutate then o.mutate(db) end
 return db
end
function F.Serialize(v,parents)
 if type(v)=='string'then return string.format('%q',v)end
 if type(v)=='number' then
  -- Literal forms that also load back: NaN and infinities included.
  if v~=v then return '(0/0)' elseif v==math.huge then return '(1/0)' elseif v==-math.huge then return '(-1/0)' end
  return string.format('%.17g',v)
 end
 if type(v)=='boolean'or v==nil then return tostring(v)end
 assert(type(v)=='table','only serializable synthetic data')
 parents=parents or {};assert(not parents[v],'cycle cannot be saved');parents[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
 local out={'{'};for _,k in ipairs(keys)do out[#out+1]='['..F.Serialize(k,parents)..']='..F.Serialize(v[k],parents)..','end
 out[#out+1]='}';parents[v]=nil;return table.concat(out)
end
-- Real TOC boot with the given saved table; returns the harness.
function F.Boot(db,before,early)
 Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua')
 NexusDB=db
 if before then before(H) end
 for line in io.lines('Nexus.toc')do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#')then
   assert(loadfile((line:gsub('\\','/'))))('Nexus',{})
   -- Optional test hook right after one file loads (fault injection only).
   if F.fileHooks and F.fileHooks[line] then F.fileHooks[line]() end
  end
 end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 if early then early(H) end -- before any scheduler turn
 for i=1,20000 do
  H.Advance(.05,.05)
  local s=Nexus.StartupStatus()
  if s.state~='pending' then break end
 end
 return H
end
-- Offline module reload with round-tripped literal data (not a client reload).
function F.Reload(before)
 local saved=F.Serialize(NexusDB)
 return F.Boot(assert(loadstring('return '..saved))(),before),saved
end
-- Fake Orb service (counted calls only; no game action), as in orb_stacked_copies.
function F.OrbService(H)
 H.orbs={charges=10,known=true,offer=false,requests=0}
 local O=H.orbs
 ProjectEbonhold.OrbService={
  IsStateKnown=function()return O.known end,
  GetCharges=function()return O.charges end,
  IsOfferPending=function()return O.offer end,
  ConfirmSpend=function(id,n)H.actions[#H.actions+1]={'orb-spend',id,n};O.source=id;return true end,
  RequestCharges=function()O.requests=O.requests+1;return true end,
 }
end
return F
