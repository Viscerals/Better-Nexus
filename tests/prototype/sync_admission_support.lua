-- Synthetic setup for deferred inbound admission regressions. Real TOC load,
-- real inbound decoder, real catalog transactions; no profile or network.
local T=dofile('tests/prototype/startup_support.lua')
local A={T=T}
function A.Boot(rows)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(rows or 5,0)
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 local C=Nexus.BuildCatalog
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
 -- Observe only. Every call and result passes through unchanged. A record
 -- submitted inside a receiver batch is counted exactly like a single put,
 -- so "one submission per item" keeps its meaning on both routes.
 H.puts={};H.batches={}
 local function Note(id,accepted,why,batched)
  if id==nil then return end
  local seen=H.puts[id] or {calls=0,accepted=0,refused=0,batched=0}
  seen.calls=seen.calls+1
  if batched then seen.batched=seen.batched+1 end
  if accepted then seen.accepted=seen.accepted+1
  else seen.refused=seen.refused+1;seen.lastRefusal=why end
  H.puts[id]=seen
 end
 local put=C.Put
 C.Put=function(record,options,...)
  local ok,why,ticket=put(record,options,...)
  Note(record.id,ok==true or (ok==nil and type(ticket)=='table'),why,false)
  return ok,why,ticket
 end
 local putBatch=C.PutBatch
 if type(putBatch)=='function' then
  C.PutBatch=function(requests,...)
   local ok,why,tickets=putBatch(requests,...)
   H.batches[#H.batches+1]={members=#(requests or {}),accepted=type(tickets)=='table'}
   for index,request in ipairs(requests or {})do
    local record=type(request)=='table' and request.record or nil
    Note(record and record.id,
     ok==nil and type(tickets)=='table' and tickets[index]~=nil,why,true)
   end
   return ok,why,tickets
  end
 end
 A.base=time()
 return H,C
end
function A.Summary(id,name,stamp,title,hash)
 local sender=name..'-Ebonhold'
 local data={id=id,t=title or ('Synthetic '..id),a=sender,
  o=Nexus.Identity.OwnerKey(name,'Ebonhold'),c='MAGE',m=stamp,h=hash or 'a1',n=3}
 return 'WLBI|'..sender..'|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data)),sender,data
end
function A.Receive(id,name,stamp,title,hash)
 local wire,sender,data=A.Summary(id,name,stamp,title,hash)
 Nexus.Sync.HandleIncoming(wire,sender)
 return data
end
-- One real earlier incoming summary owns the catalog transaction.
function A.Hold(C,id,name,stamp)
 local data=A.Receive(id or 'admission-holder',name or 'Holder',stamp or A.base)
 local status=C.ManualPreparationStatus()
 assert(status.relevant and not status.ready,'real earlier incoming summary owns catalog admission')
 return data
end
function A.Settled(H,C)
 T.Until(H,function()
  return C.ManualPreparationStatus().ready and Nexus.Sync.WorkState().deferredAdmissions==0
 end)
 H.Advance(5,.05)
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
end
return A
