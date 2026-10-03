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
