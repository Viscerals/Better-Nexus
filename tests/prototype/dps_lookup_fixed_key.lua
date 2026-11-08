-- FindCharacterRow (core/DpsCapture.lua) fixed-name key hoist.
-- SETUP: loads the real core/Identity.lua, core/DiagnosticHistory.lua and
-- core/DpsCapture.lua directly from the checkout root (no TOC start-up, no
-- Packs, no SavedVariables, no game action). The private FindCharacterRow
-- closure is bound through debug.getupvalue on its actual caller
-- DPS.GetCharacterBest, and rows are injected into the actual
-- CharacterBestStore producer so both public callers (DPS.GetCharacterBest,
-- DPS.GetPlayerInfo) exercise the same scan. Identity.PlayerKey is wrapped by
-- a counter that delegates to the real function, so every key semantic is the
-- real one.
-- EXPECT (fails before the hoist): a fallback scan over 64 candidate rows
-- normalizes the fixed probe name at most once beyond the direct-lookup entry
-- work, and the fixed-name work seen through both public callers does not
-- scale with the row count.
-- GUARD (holds before and after): every candidate row is still normalized
-- exactly once per scan; match results for ordinary, realm-qualified,
-- case-variant, UTF-8, invalid, a valid player named "Invalid", legacy
-- collisions, strongest match (dps, then earlier ts, then fingerprint),
-- direct-key precedence, nil/non-string inputs and no-match are the
-- documented ones.
-- Counts are offline operation counts on synthetic rows, not native timing.
-- Optional arg[1]: alternate core/DpsCapture.lua path for an offline
-- base/candidate comparison from the same checkout root.
local DPS_PATH = (arg and arg[1]) or 'core/DpsCapture.lua'

local failures, checks = 0, 0
local function Report(kind, ok, label, detail)
  checks = checks + 1
  if not ok then failures = failures + 1 end
  print(kind, ok and 'PASS' or 'FAIL', label, detail ~= nil and tostring(detail) or '')
  return ok
end
local function Setup(ok, label, detail)
  if not ok then print('SETUP', 'FAIL', label, tostring(detail)); os.exit(2) end
end
local function Expect(ok, label, detail) return Report('EXPECT', ok, label, detail) end
local function Guard(ok, label, detail) return Report('GUARD', ok, label, detail) end

local function Upvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if n == nil then return nil end
    if n == name then return v end
    i = i + 1
  end
end

-- Synthetic realm-local client: a defined realm name and a local character.
GetRealmName = function() return 'Ebonhold' end
UnitName = function() return 'SyntheticSelf' end
Nexus = nil; NexusDB = nil
dofile('core/Identity.lua')
dofile('core/DiagnosticHistory.lua')
dofile(DPS_PATH)
local Identity, DPS = Nexus.Identity, Nexus.DpsCapture
Setup(type(DPS) == 'table' and type(DPS.GetCharacterBest) == 'function', 'DpsCapture loaded from ' .. DPS_PATH)
local Find = Upvalue(DPS.GetCharacterBest, 'FindCharacterRow')
local Store = Upvalue(DPS.GetCharacterBest, 'CharacterBestStore')
Setup(type(Find) == 'function', 'FindCharacterRow is an upvalue of DPS.GetCharacterBest')
Setup(type(Store) == 'function', 'CharacterBestStore is an upvalue of DPS.GetCharacterBest')
do
  local info = debug.getinfo(Find, 'S')
  local fh = assert(io.open(DPS_PATH, 'rb'))
  local n, defLine = 0, nil
  for line in fh:lines() do n = n + 1; if n == info.linedefined then defLine = line; break end end
  fh:close()
  Setup(defLine and defLine:find('local function FindCharacterRow', 1, true) ~= nil,
    'closure binds to "local function FindCharacterRow"', 'line ' .. tostring(info.linedefined))
  print('OBSERVED', 'FindCharacterRow lines', info.linedefined .. '-' .. info.lastlinedefined, DPS_PATH)
end

local function Row(player, dps, ts, fp)
  return {player = player, dps = dps, ts = ts, fingerprint = fp, duration = 45, buildId = 'b-' .. tostring(fp)}
end
local function Fp(row) return row and (row.fingerprint or '?') or 'nil' end
local U = string.char
local AE_UPPER, AE_LOWER = U(195, 132), U(195, 164) -- "A with diaeresis", upper and lower (distinct bytes)

----------------------------------------------------------------------------
-- Match-result guards (explicit expected winners).
----------------------------------------------------------------------------
local function AddFillers(rows, count)
  for i = 1, count do
    rows['filler' .. i .. '@realm' .. (i % 7)] = Row('Filler' .. i, 100 + i, 1000 + i, 'fp-f' .. i)
  end
  return rows
end
local function ScanRows()
  return {
    ['thrall@azeroth']     = Row('THRALL', 900, 200, 'fp-a'),
    ['thrall@draenor']     = Row('thrall', 1200, 300, 'fp-b'),
    ['thrall@frostmourne'] = Row('Thrall-Draenor', 1200, 100, 'fp-c'),
  }
end
local scan = AddFillers(ScanRows(), 61)
for _, probe in ipairs({'Thrall', 'thrall', 'THRALL', 'tHRaLL', 'Thrall-Draenor', 'Thrall-Ebonhold'}) do
  Guard(Fp(Find(scan, probe)) == 'fp-c', 'strongest scan match for probe "' .. probe .. '" (dps tie, earlier ts)', Fp(Find(scan, probe)))
end
Guard(Find(scan, 'Nobody') == nil, 'no-match scan returns nil')
Guard(Find({}, 'Thrall') == nil, 'empty rows return nil')
Guard(Fp(Find(scan, 'Filler3')) == 'fp-f3' and Fp(Find(scan, 'filler3')) == 'fp-f3', 'a filler row is found by its own name and case variant')

local direct = {['thrall@ebonhold'] = Row('Thrall', 500, 10, 'fp-current'), ['thrall'] = Row('Thrall', 700, 10, 'fp-legacy')}
Guard(Fp(Find(direct, 'Thrall')) == 'fp-current', 'current-realm key precedes the legacy key', Fp(Find(direct, 'Thrall')))
Guard(Fp(Find(direct, 'Thrall-Ebonhold')) == 'fp-current', 'a realm-qualified probe hits the current-realm key', Fp(Find(direct, 'Thrall-Ebonhold')))
Guard(Fp(Find({['thrall'] = direct['thrall']}, 'THRALL')) == 'fp-legacy', 'a legacy key hits directly for a case variant')
local collision = {['thrall'] = Row('Thrall', 100, 5, 'fp-weak-legacy'), ['thrall@azeroth'] = Row('Thrall', 9999, 5, 'fp-strong-remote')}
Guard(Fp(Find(collision, 'Thrall')) == 'fp-weak-legacy', 'a direct legacy hit precedes a stronger scan candidate', Fp(Find(collision, 'Thrall')))

local ties = {['thrall@a'] = Row('Thrall', 1000, 50, 'fp-t1'), ['thrall@b'] = Row('Thrall', 1000, 50, 'fp-t0'),
              ['thrall@c'] = Row('Thrall', 1000, 0, 'fp-t2'), ['thrall@d'] = Row('Thrall', 1000.9, 80, 'fp-t3')}
Guard(Fp(Find(ties, 'Thrall')) == 'fp-t0', 'equal floored dps and ts resolve by the smaller fingerprint', Fp(Find(ties, 'Thrall')))

local utf8 = {[AE_UPPER .. 'rzte@azeroth'] = Row(AE_UPPER .. 'RZTE', 300, 5, 'fp-u1'),
              [AE_LOWER .. 'rzte@azeroth'] = Row(AE_LOWER .. 'rzte', 400, 5, 'fp-u2')}
Guard(Fp(Find(utf8, AE_UPPER .. 'rzte')) == 'fp-u1', 'ASCII case folds while the non-ASCII byte stays exact (upper form)', Fp(Find(utf8, AE_UPPER .. 'rzte')))
Guard(Fp(Find(utf8, AE_UPPER .. 'RZTE')) == 'fp-u1', 'ASCII case folds while the non-ASCII byte stays exact (all caps)', Fp(Find(utf8, AE_UPPER .. 'RZTE')))
Guard(Fp(Find(utf8, AE_LOWER .. 'rzte')) == 'fp-u2', 'a different non-ASCII byte is a different player', Fp(Find(utf8, AE_LOWER .. 'rzte')))

local invalidNamed = {['invalid@azeroth'] = Row('INVALID', 300, 5, 'fp-inv-a'), ['invalid@draenor'] = Row('Invalid', 300, 5, 'fp-inv-b')}
Guard(Fp(Find(invalidNamed, 'Invalid')) == 'fp-inv-a' and Fp(Find(invalidNamed, 'INVALID')) == 'fp-inv-a',
  'a valid player named "Invalid" still matches by scan (smaller fingerprint on full tie)')
for _, probe in ipairs({'', 'Thr@ll', '-Thrall', 'Thrall--X', 'Thr all', string.rep('a', 81)}) do
  Guard(Find(invalidNamed, probe) == nil, 'invalid probe "' .. probe:sub(1, 12) .. '" never matches rows named Invalid', Fp(Find(invalidNamed, probe)))
end
Guard(Find(invalidNamed, nil) == nil and Find(invalidNamed, 42) == nil, 'nil and number probes never match by scan')

local messy = {['thrall@azeroth'] = Row(nil, 900, 1, 'fp-nilplayer'), ['x'] = 'string-entry', ['y'] = 42,
               ['thrall@draenor'] = Row(12345, 900, 1, 'fp-numplayer'), ['thrall@outland'] = Row('Thrall', 1, 1, 'fp-ok'),
               ['z'] = Row('Thrall', 'notanumber', nil, 'fp-nan')}
Guard(Fp(Find(messy, 'Thrall')) == 'fp-ok', 'nil/number players and non-table entries are skipped; a non-numeric dps loses', Fp(Find(messy, 'Thrall')))

----------------------------------------------------------------------------
-- Work counts through the real Identity.PlayerKey (every caller reaches it
-- through the Identity table field).
----------------------------------------------------------------------------
local PROBE = 'Thrall' -- no candidate row in scan/noMatch is byte-identical to the probe
local original = Identity.PlayerKey
local counts, candidateSet = nil, {}
Identity.PlayerKey = function(value, keepRealm)
  if value == PROBE then counts.fixed = counts.fixed + 1
  elseif type(value) == 'string' and candidateSet[value] then counts.candidate = counts.candidate + 1
  else counts.other = counts.other + 1 end
  return original(value, keepRealm)
end
local function Measure(label, rows, fn)
  candidateSet = {}
  local tableRows = 0
  for _, v in pairs(rows) do
    if type(v) == 'table' then tableRows = tableRows + 1; if type(v.player) == 'string' then candidateSet[v.player] = true end end
  end
  counts = {fixed = 0, candidate = 0, other = 0}
  local result = fn()
  print('OBSERVED', label, 'rows=' .. tableRows, 'fixed=' .. counts.fixed, 'candidate=' .. counts.candidate, 'other=' .. counts.other, 'result=' .. Fp(result))
  return counts, result, tableRows
end

local entry = Measure('direct_hit_current_realm', direct, function() return Find(direct, PROBE) end)
local entryFixed = entry.fixed
Guard(entry.candidate == 0, 'a direct hit scans no candidate', entry.candidate)
local noMatch = AddFillers({}, 64)
local nm = Measure('scan_64_no_match', noMatch, function() return Find(noMatch, PROBE) end)
Guard(nm.candidate == 64, 'a no-match scan normalizes each candidate exactly once', nm.candidate)
Expect(nm.fixed - entryFixed <= 1, 'no-match scan: at most one fixed-name normalization beyond entry work', nm.fixed - entryFixed)
local sc, found, rowsN = Measure('scan_64_three_matches', scan, function() return Find(scan, PROBE) end)
Guard(Fp(found) == 'fp-c' and rowsN == 64, 'the counted scan still returns the strongest match', Fp(found))
Guard(sc.candidate == 64, 'a matching scan normalizes each candidate exactly once', sc.candidate)
Expect(sc.fixed - entryFixed <= 1, 'fallback scan: at most one fixed-name normalization beyond entry work', sc.fixed - entryFixed)

-- Actual callers over the actual producer.
local store = Store()
store.dummy = AddFillers(ScanRows(), 61)
store.lk = {}
local pc, record = Measure('caller_GetCharacterBest', store.dummy, function() return DPS.GetCharacterBest('dummy', PROBE) end)
Guard(type(record) == 'table' and record.fingerprint == 'fp-c' and tonumber(record.dps) == 1200, 'DPS.GetCharacterBest returns the strongest scan match', Fp(record))
Guard(pc.candidate == 64, 'DPS.GetCharacterBest normalizes each candidate exactly once', pc.candidate)
Expect(pc.fixed < 64, 'DPS.GetCharacterBest fixed-name work does not scale with 64 rows', pc.fixed)
local pi, info = Measure('caller_GetPlayerInfo', store.dummy, function() return DPS.GetPlayerInfo(PROBE) end)
Guard(type(info) == 'table' and tonumber(info.dps) == 1200 and info.category == 'dummy', 'DPS.GetPlayerInfo ranks the strongest scan match', info and (tostring(info.dps) .. '/' .. tostring(info.category)) or 'nil')
Expect(pi.fixed < 64, 'DPS.GetPlayerInfo fixed-name work does not scale with 64 rows', pi.fixed)
Identity.PlayerKey = original

print(failures == 0 and 'PASS' or 'FAIL', 'dps_lookup_fixed_key', 'checks=' .. checks, 'failures=' .. failures)
if failures > 0 then os.exit(1) end
