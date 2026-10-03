-- Shared synthetic helpers for the 035 Orb tests (pick-evidence preservation and the
-- player-confirmed continuation). They extend the 034 scenarios of
-- orb_loadout_hold_support.lua (real Store, OrbRuntime, OrbAdapter, GameAdapter and
-- SupportReport; only the game services are synthetic) with game lifecycle events,
-- picks, a broken ownership read and failing persistence. Nothing here uses a real
-- character, account, SavedVariables file or game client.
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local R={S=S}

function R.Row()
 local key=Nexus.Store.CurrentOwnerKey()
 return key,NexusDB.chars[key]
end
-- The receipt exactly as the saved row holds it (not the Store's read copy).
function R.Saved()
 local _,row=R.Row()
 return row and row.orbRefinement and row.orbRefinement.pending or nil
end
function R.SavedRow(field)
 local _,row=R.Row()
 return row and row[field] or nil
end

-- Game lifecycle, as the owner's frame receives it. A loading screen is a leave and
-- an enter; a reload also ends the Lua state (R.Reload).
function R.Leaving(H) H.Fire('PLAYER_LEAVING_WORLD') end
function R.Entering(H) H.Fire('PLAYER_ENTERING_WORLD') end

-- A reload. The game client's Lua state restarts, so a hook that an earlier load
-- installed does not exist any more; the harness keeps the old wrapper, and the
-- adapter makes a superseded instance inert (see OrbAdapter, `A.Orbs~=O`).
function R.Reload(H,saved)
 return S.Reload(H,saved)
end

-- The game's own pick call, as the player's click reaches it. Counted, so a test can
-- tell the player's picks from a choice that Nexus itself would have sent.
function R.Pick(H,id)
 H.playerPicks=(H.playerPicks or 0)+1
 return H.service.SelectPerk(id)
end

-- A one-moment ownership read failure: the game's rolled list is unreadable. Returns
-- the function that restores it.
function R.BreakOwned(H)
 local good=H.granted
 H.granted=setmetatable({},{__index=function() return nil end})
 return function() H.granted=good end
end

-- Persistence failure: the Store reports that the row cannot be written durably.
function R.BreakStore()
 local store=Nexus.Store;local raw=store.StateWriteStatus
 store.StateWriteStatus=function() return {mode='unavailable',reason='database'} end
 return function() store.StateWriteStatus=raw end
end

-- Count what could reach the game from Nexus: spend and select calls (S.CountCalls).
-- calls.nexusSelects() is the number of SelectPerk calls that were NOT the player's
-- own picks (R.Pick) since the count began; calls.spend is the number of Orb spends.
function R.Calls(H)
 local calls=S.CountCalls(H);local base=H.playerPicks or 0
 calls.nexusSelects=function() return calls.select-((H.playerPicks or 0)-base) end
 return calls
end

-- The reported class, built from the deidentified shape of 034: a restored receipt
-- with a confirmed spend, no recorded choice, and the original offer gone (no board,
-- no pending offer). opts.latch (default true): the loadout hold is set, as reported;
-- false: the original slot is still the live slot. opts.slot, opts.known, opts.charges.
function R.Class(opts)
 opts=opts or {}
 local H,M,A,O=S.World(S.Shape(),{slot=opts.slot or 101,known=opts.known,latch=opts.latch~=false,
  charges=opts.charges or S.Shape().receipt.chargesBefore-1,open=false})
 -- opts.edit(savedReceipt,storeReceipt) changes the receipt as the next load reads it.
 if opts.edit then M=S.Reload(H,opts.edit) end
 return H,M,A,O
end

local ME='PrototypeTester'
R.ME=ME
R.PREFIX='AAM0x9'
-- A synthetic server for the transport model. It answers RequestCharges with a reply that
-- arrives at the NEXT update tick (never inside the request call), applies to the fake
-- OrbService what the game's own handler would (the charge count, and the pending count only
-- when the reply has a third field), and fires the packet to every frame, as the client does.
-- RequestGrantedPerks is answered with an ownership push (opcode 18). Nothing here says a
-- reply belongs to a request: the model delivers in order and a test can reorder, hold,
-- duplicate or drop. opts.body(n) may return the body of reply n; opts.mode:
-- 'auto' (default), 'hold' (replies wait for server.Release) or 'drop'.
function R.Server(H,opts)
 opts=opts or {}
 local server={mode=opts.mode or 'auto',queue={},requests=0,delivered=0,sender=ME,dist='WHISPER',
  pendingOffers=0,sent={},noCache=opts.noCache==true}
 local O=H.orbs
 local function Body(n)
  if opts.body then local b=opts.body(n,server);if b~=nil then return b end end
  return tostring(O.charges)..',0,'..tostring(server.pendingOffers)
 end
 local rawRequest=ProjectEbonhold.OrbService.RequestCharges
 ProjectEbonhold.OrbService.RequestCharges=function(...)
  server.requests=server.requests+1
  if server.mode~='drop' then server.queue[#server.queue+1]={op=1220,body=Body(server.requests)} end
  return rawRequest(...)
 end
 local rawGranted=H.service.RequestGrantedPerks
 H.service.RequestGrantedPerks=function(...)
  if server.mode~='drop' then server.queue[#server.queue+1]={op=18,body='x'} end
  return rawGranted(...)
 end
 -- The game's own handler: the charge count is replaced; the pending count only when a
 -- third field is present and is a number (the audited client reads a bad one as zero).
 function server.GameCache(body)
  local a,b,c=body:match('^([^,]*),([^,]*),?([^,]*)$')
  if a~=nil then O.charges=tonumber(a) or 0 end
  if body:find('^[^,]*,[^,]*,') then O.offer=(tonumber(c) or 0)>0 end
 end
 function server.Deliver(item,opts2)
  opts2=opts2 or {}
  if item.op==1220 and not opts2.noCache and not server.noCache then server.GameCache(item.body) end
  -- opts2.sender / opts2.dist: false means "no value at all" (nil), absent means the normal one.
  local sender,dist=server.sender,server.dist
  if opts2.sender~=nil then sender=opts2.sender end
  if opts2.dist~=nil then dist=opts2.dist end
  if sender==false then sender=nil end
  if dist==false then dist=nil end
  H.Fire('CHAT_MSG_ADDON',R.PREFIX,item.op..'	'..item.body,dist,sender)
  server.delivered=server.delivered+1
 end
 function server.Release(n)
  local count=0
  while #server.queue>0 and (not n or count<n) do
   server.Deliver(table.remove(server.queue,1));count=count+1
  end
  return count
 end
 local tick=CreateFrame('Frame')
 tick:SetScript('OnUpdate',function()
  if server.mode=='auto' then server.Release() end
 end)
 -- A packet that arrives on its own (not an answer to anything Nexus did).
 function server.Push(op,body,opts2) server.Deliver({op=op,body=body},opts2) end
 return server
end

-- Deep equality of two plain tables.
function R.Same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not R.Same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
function R.Keys(t)
 local out={};for k in pairs(t) do out[#out+1]=tostring(k) end;table.sort(out);return out
end
-- Every value of a table, recursively, is a number, boolean or short text.
function R.Plain(t,limit)
 limit=limit or 64
 for k,v in pairs(t) do
  local kt,vt=type(k),type(v)
  if kt~='string' and kt~='number' then return false,'key type '..kt end
  if vt=='table' then local ok,why=R.Plain(v,limit);if not ok then return false,why end
  elseif vt=='string' then if #v>limit then return false,'long text' end
  elseif vt~='number' and vt~='boolean' then return false,'value type '..vt end
 end
 return true
end
return R
