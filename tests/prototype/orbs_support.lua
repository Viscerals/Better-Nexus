local H=dofile('tests/prototype/harness.lua')
H.AddEcho(410001,'Disposable A',1,4,4100)
H.AddEcho(410002,'Desired A',2,3,4101)
H.AddEcho(410003,'Disposable B',0,4,4102)
H.AddEcho(410004,'Desired B',3,2,4103)
H.AddEcho(410005,'Protected low',0,3,4104)
H.AddEcho(410006,'Excess high',3,3,4104)
H.AddEcho(410007,'Permanent',2,1,4105)
H.AddEcho(410008,'Unsafe fallback',1,1,4106)
H.granted={['Disposable A']={{spellId=410001,quality=1}},['Disposable B']={{spellId=410003,quality=0}}}
H.orbs={charges=10,known=true,offer=false,mode='accept',requests=0}
local O=H.orbs
ProjectEbonhold.OrbService={
 IsStateKnown=function()return O.known end,
 GetCharges=function()return O.charges end,
 IsOfferPending=function()return O.offer end,
 ConfirmSpend=function(id,n)
  H.actions[#H.actions+1]={'orb-spend',id,n};O.spends=(O.spends or 0)+1;O.source=id
  if O.mode=='throw'then error('synthetic ambiguous submit')end
  if O.mode=='refuse'then return false end
  return true
 end,
 RequestCharges=function()O.requests=O.requests+1;return true end,
}
H.Boot();local A=Nexus.GameAdapter;local M=Nexus.OrbRuntime
local function setplan(entries)
 local ok,err=A.SetFirstLoadoutWishlistIdentity('Orb test',entries);assert(ok,err)
 local yes,e=M.UseAssignedWishlist();assert(yes,e)
end
function H.OrbPlan(entries)
 setplan(entries or {{spellId=410002,quality=2,stacks=1}})
end
function H.Count(kind)local n=0;for _,a in ipairs(H.actions)do if a[1]==kind then n=n+1 end end;return n end
function H.Approve(limit,recycle,single)
 assert(M.SetLimit(limit or 2));assert(M.SetRecycle(recycle==true));assert(M.SuggestSources())
 local p,err=M.Prepare(single and 'single' or 'auto');assert(p,err);H.lastApproval=p
 local ok,e=M.Confirm(p.token);assert(ok,e);return p
end
function H.Offer(cards)
 O.charges=O.charges-1;O.offer=true
 H.Board(cards or {{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 M.Pump()
end
function H.Result(id,q,sameReference)
 local source=O.source;local out=H.Clone(H.granted);local removed=false
 for _,entries in pairs(out)do for i=#entries,1,-1 do if not removed and entries[i].spellId==source then table.remove(entries,i);removed=true end end end
 assert(removed,'fake service removes one actual source')
 out[H.names[id]]=out[H.names[id]] or {};table.insert(out[H.names[id]],{spellId=id,quality=q})
 if sameReference then
  for k in pairs(H.granted)do H.granted[k]=nil end
  for k,v in pairs(out)do H.granted[k]=v end
 else H.granted=out end
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.Notify();A.Poll();M.Pump()
end
H.A=A;H.M=M;H.O=O
return H
