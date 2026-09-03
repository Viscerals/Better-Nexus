"use strict";

// Package B catalog authority (issue #22) behavioral expected-red matrix.
//
// Every scenario below asserts a required Package B behavior through public
// production seams that already exist on the exact product base. Each one is
// executed against the base sources loaded into an isolated Lua state, where it
// must fail for its stated behavioral reason. These are behavioral oracles, not
// API-absence checks: no scenario references a symbol that Package B adds.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const fengari = require("fengari");

const ACCEPTED_BASE = "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f";
const repoRoot = path.resolve(process.cwd());

function git(...args) {
    return execFileSync("git", ["-c", `safe.directory=${repoRoot}`, ...args], {
        cwd: repoRoot,
        encoding: "utf8",
        maxBuffer: 32 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"],
    }).trimEnd();
}

const resolvedBase = git("rev-parse", ACCEPTED_BASE + "^{commit}").trim();
if (resolvedBase !== ACCEPTED_BASE) {
    throw new Error(`accepted prerequisite mismatch: ${resolvedBase}`);
}

const baseToc = git("show", `${ACCEPTED_BASE}:Nexus.toc`);
const productPaths = baseToc.split(/\r?\n/)
    .map((line) => line.trim().replace(/\\/g, "/"))
    .filter((line) => line && !line.startsWith("#") && line.endsWith(".lua"));

function productHashes() {
    const out = {};
    for (const relative of ["Nexus.toc", ...productPaths]) {
        const content = fs.readFileSync(path.join(repoRoot, relative));
        out[relative] = crypto.createHash("sha256").update(content).digest("hex");
    }
    return out;
}

const beforeHashes = productHashes();
const overlays = {};
for (const relative of productPaths) {
    overlays[relative] = git("show", `${ACCEPTED_BASE}:${relative}`) + "\n";
}

const { lua, lauxlib, lualib, to_jsstring, to_luastring } = fengari;
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function fileRead(state) {
    lua.lua_getfield(state, 1, to_luastring("_content"));
    return 1;
}

function fileClose(state) {
    lua.lua_pushboolean(state, true);
    return 1;
}

function currentFileOpen(state) {
    const raw = lauxlib.luaL_checkstring(state, 1);
    const filePath = path.resolve(repoRoot, to_jsstring(raw));
    try {
        const content = fs.readFileSync(filePath, "utf8");
        lua.lua_createtable(state, 0, 3);
        lua.lua_pushstring(state, to_luastring(content));
        lua.lua_setfield(state, -2, to_luastring("_content"));
        lua.lua_pushcfunction(state, fileRead);
        lua.lua_setfield(state, -2, to_luastring("read"));
        lua.lua_pushcfunction(state, fileClose);
        lua.lua_setfield(state, -2, to_luastring("close"));
        return 1;
    } catch (error) {
        lua.lua_pushnil(state);
        lua.lua_pushstring(state, to_luastring(String(error.message || error)));
        return 2;
    }
}

lua.lua_getglobal(L, to_luastring("io"));
lua.lua_pushcfunction(L, currentFileOpen);
lua.lua_setfield(L, -2, to_luastring("open"));
lua.lua_pop(L, 1);

lua.lua_createtable(L, 0, productPaths.length);
for (const [relative, source] of Object.entries(overlays)) {
    lua.lua_pushstring(L, to_luastring(source));
    lua.lua_setfield(L, -2, to_luastring(relative));
}
lua.lua_setglobal(L, to_luastring("NEXUS_ACCEPTED_BASE_SOURCES"));

function capturePrint(state) {
    const count = lua.lua_gettop(state);
    const parts = [];
    for (let index = 1; index <= count; index += 1) {
        lua.lua_getglobal(state, to_luastring("tostring"));
        lua.lua_pushvalue(state, index);
        if (lua.lua_pcall(state, 1, 1, 0) !== lua.LUA_OK) {
            return lua.lua_error(state);
        }
        parts.push(to_jsstring(lua.lua_tostring(state, -1)));
        lua.lua_pop(state, 1);
    }
    console.log(parts.join("\t"));
    return 0;
}
lua.lua_pushcfunction(L, capturePrint);
lua.lua_setglobal(L, to_luastring("print"));

const prelude = [
    "unpack = unpack or table.unpack",
    "math.atan2 = math.atan2 or math.atan",
    "package.preload.bit = function() return {} end",
    "local originalDofile = dofile",
    "local originalOpen = io.open",
    "local function normalized(filePath)",
    "  return type(filePath) == 'string' and filePath:gsub('\\\\', '/') or filePath",
    "end",
    "function dofile(filePath)",
    "  local name = normalized(filePath)",
    "  local source = NEXUS_ACCEPTED_BASE_SOURCES and NEXUS_ACCEPTED_BASE_SOURCES[name]",
    "  if source then",
    "    local chunk, why = load(source, '@' .. name)",
    "    if not chunk then error(why, 0) end",
    "    return chunk()",
    "  end",
    "  return originalDofile(filePath)",
    "end",
    "function io.open(filePath, mode)",
    "  local name = normalized(filePath)",
    "  local source = NEXUS_ACCEPTED_BASE_SOURCES and NEXUS_ACCEPTED_BASE_SOURCES[name]",
    "  if source then",
    "    return { read=function() return source end, close=function() return true end }",
    "  end",
    "  return originalOpen(filePath, mode)",
    "end",
].join("; ");

let status = lauxlib.luaL_loadstring(L, to_luastring(prelude));
if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
if (status !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

// Shared fixture bootstrap. It loads only base modules through public seams and
// leaves `Catalog`, `Owner`, `Build`, `Echoes`, and `FreshDatabase` in the state.
const BOOTSTRAP = [
    "local H = dofile('tests/harness.lua')",
    "dofile('data/BundledBuilds.lua')",
    "dofile('core/LoadoutEvidence.lua')",
    "dofile('core/BuildCatalog.lua')",
    "Catalog = assert(Nexus.BuildCatalog)",
    "Realm = (GetNormalizedRealmName()):lower()",
    "Owner = (UnitName('player')):lower() .. '@' .. Realm",
    "function FreshDatabase()",
    "  NexusDB = {communityBuilds={}, syncTombstones={}}",
    "  if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then",
    "    Nexus.LoadoutEvidence.Init(NexusDB)",
    "  end",
    "  Catalog.Init(NexusDB, nil)",
    "  return NexusDB",
    "end",
    "function Build(id, extra)",
    "  local row = {id=id, title='Expected red ' .. tostring(id), author=UnitName('player'),",
    "    ownerKey=Owner, ownerVerified=true, realm=Realm, class='MAGE', postedAt=1,",
    "    lastModified=1, isMine=true, echoes={{spellId=750001, quality=1, stacks=1}}}",
    "  for key, value in pairs(extra or {}) do row[key] = value end",
    "  return row",
    "end",
    "function Echoes(count, quality, stacks, locked)",
    "  local out = {}",
    "  for index = 1, count do",
    "    out[index] = {spellId=760000 + index, quality=quality or (index % 4),",
    "      stacks=stacks or 1, locked=locked or nil}",
    "  end",
    "  return out",
    "end",
].join("\n");

let bootstrapped = false;
function expectedRed(id, label, lines) {
    const source = (bootstrapped ? "" : BOOTSTRAP + "\n") + lines.join("\n");
    bootstrapped = true;
    lua.lua_settop(L, 0);
    let scenarioStatus = lauxlib.luaL_loadstring(L, to_luastring(source));
    if (scenarioStatus === lua.LUA_OK) {
        scenarioStatus = lua.lua_pcall(L, 0, 0, 0);
    }
    if (scenarioStatus === lua.LUA_OK) {
        throw new Error(`expected-red scenario unexpectedly passed: ${id} ${label}`);
    }
    const oracle = to_jsstring(lua.lua_tostring(L, -1));
    if (!oracle.includes(label)) {
        throw new Error(`missing expected-red oracle: ${id} ${label}; actual=${oracle}`);
    }
    console.log(`EXPECTED-RED ${id} confirmed=${label}`);
    console.log(`EXPECTED-RED ${id} oracle=${oracle}`);
}

expectedRed("ENV-01",
    "a loadout above 79 ordinary copies is admitted", [
    "FreshDatabase()",
    "local ok = Catalog.Put(Build('env-ordinary', {echoes=Echoes(80)}))",
    "local stored = NexusDB.communityBuilds['env-ordinary'] ~= nil",
    "assert(ok ~= true and not stored,",
    "  'a loadout above 79 ordinary copies is admitted: put=' .. tostring(ok)",
    "  .. ' durable=' .. tostring(stored))",
]);

expectedRed("ENV-02",
    "a loadout above 6 locked copies is admitted", [
    "FreshDatabase()",
    "local ok = Catalog.Put(Build('env-locked', {echoes={{spellId=751001,quality=1,stacks=1}},",
    "  lockedEchoes=Echoes(7, 3, 1, true)}))",
    "local stored = NexusDB.communityBuilds['env-locked'] ~= nil",
    "assert(ok ~= true and not stored,",
    "  'a loadout above 6 locked copies is admitted: put=' .. tostring(ok)",
    "  .. ' durable=' .. tostring(stored))",
]);

expectedRed("ENV-03",
    "a loadout above 85 total copies is admitted", [
    "FreshDatabase()",
    "local ok = Catalog.Put(Build('env-total', {echoes=Echoes(40, 2, 3)}))",
    "local stored = NexusDB.communityBuilds['env-total'] ~= nil",
    "assert(ok ~= true and not stored,",
    "  'a loadout above 85 total copies is admitted: put=' .. tostring(ok)",
    "  .. ' durable=' .. tostring(stored))",
]);

expectedRed("READ-01",
    "one-call collection read returns an unbounded copy", [
    "FreshDatabase()",
    "for index = 1, 300 do",
    "  NexusDB.communityBuilds['bulk-' .. index] = {id='bulk-' .. index, title='B' .. index,",
    "    author=UnitName('player'), ownerKey=Owner, ownerVerified=true, realm=Realm,",
    "    class='MAGE', postedAt=index, lastModified=index,",
    "    echoes={{spellId=770000 + index, quality=1, stacks=1}}}",
    "end",
    "Catalog.Init(NexusDB, nil)",
    "local rows, why = Catalog.All()",
    "local count = 0",
    "for _ in pairs(type(rows) == 'table' and rows or {}) do count = count + 1 end",
    "assert(rows == nil and why == 'CURSOR_REQUIRED',",
    "  'one-call collection read returns an unbounded copy: rows=' .. tostring(count)",
    "  .. ' refusal=' .. tostring(why))",
]);

expectedRed("SNAP-01",
    "the admitted canonical snapshot exposes unknown fields", [
    "FreshDatabase()",
    "NexusDB.communityBuilds['unknown-scope'] = {id='unknown-scope', title='U',",
    "  author=UnitName('player'), ownerKey=Owner, ownerVerified=true, realm=Realm,",
    "  class='MAGE', postedAt=1, lastModified=1, futureRowField='row-keep',",
    "  echoes={{spellId=780001, quality=1, stacks=1, futureTupleField='tuple-keep'}}}",
    "Catalog.Init(NexusDB, nil)",
    "local record = Catalog.Get('unknown-scope')",
    "local raw = NexusDB.communityBuilds['unknown-scope']",
    "local leakedRow = record ~= nil and record.futureRowField ~= nil",
    "local leakedTuple = record ~= nil and record.echoes ~= nil",
    "  and record.echoes[1] ~= nil and record.echoes[1].futureTupleField ~= nil",
    "local durable = raw.futureRowField == 'row-keep'",
    "  and raw.echoes[1].futureTupleField == 'tuple-keep'",
    "assert(not leakedRow and not leakedTuple and durable,",
    "  'the admitted canonical snapshot exposes unknown fields: row=' .. tostring(leakedRow)",
    "  .. ' tuple=' .. tostring(leakedTuple) .. ' durablePreserved=' .. tostring(durable))",
]);

expectedRed("TOMB-01",
    "a reloaded tombstone still admits a durable overlay write", [
    "FreshDatabase()",
    "assert(Catalog.Put(Build('tomb-reload')) == true, 'fixture row was not admitted')",
    "assert(Catalog.SetTombstone('tomb-reload',",
    "  {stamp=100, author=UnitName('player'), ownerKey=Owner, ownerVerified=true}) == true,",
    "  'fixture tombstone was not stored')",
    "assert(NexusDB.syncTombstones['tomb-reload'] ~= nil, 'fixture tombstone is not durable')",
    "NexusDB = {communityBuilds=NexusDB.communityBuilds, syncTombstones=NexusDB.syncTombstones}",
    "Catalog.Init(NexusDB, nil)",
    "local before = NexusDB.communityBuilds['tomb-reload']",
    "local ok = Catalog.Put(Build('tomb-reload', {postedAt=999, lastModified=999,",
    "  title='RESURRECTED'}))",
    "local after = NexusDB.communityBuilds['tomb-reload']",
    "assert(ok ~= true and after == before,",
    "  'a reloaded tombstone still admits a durable overlay write: put=' .. tostring(ok)",
    "  .. ' durableTitle=' .. tostring(after and after.title))",
]);

const afterHashes = productHashes();
if (JSON.stringify(afterHashes) !== JSON.stringify(beforeHashes)) {
    throw new Error("expected-red execution changed product bytes");
}

console.log(`EXPECTED-RED prerequisite=${ACCEPTED_BASE}`);
console.log("EXPECTED-RED product_bytes_unchanged=true");
console.log("Package B catalog authority exact-base expected red -- OK");
