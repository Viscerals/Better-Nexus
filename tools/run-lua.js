"use strict";

const fs = require("fs");
const path = require("path");
const fengari = require("fengari");

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

function ioOpen(state) {
    const raw = lauxlib.luaL_checkstring(state, 1);
    const filePath = path.resolve(process.cwd(), to_jsstring(raw));
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
lua.lua_pushcfunction(L, ioOpen);
lua.lua_setfield(L, -2, to_luastring("open"));
lua.lua_pop(L, 1);

const prelude = [
    "unpack = unpack or table.unpack",
    "math.atan2 = math.atan2 or math.atan",
    "package.preload.bit = function() return {} end",
].join("; ");

let status = lauxlib.luaL_loadstring(L, to_luastring(prelude));
if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
if (status !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
}

const script = process.argv[2];
if (!script) {
    console.error("usage: node tools/run-lua.js <script.lua>");
    process.exit(2);
}

status = lauxlib.luaL_loadfile(L, to_luastring(script));
if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
if (status !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
}
