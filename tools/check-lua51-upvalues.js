"use strict";

// WoW 3.3.5a inherits Lua 5.1's hard limit of 60 upvalues per function.
// Fengari accepts up to 255, so syntax/load tests alone cannot enforce the
// client boundary. Compile with Fengari for prototype-accurate lexical capture
// resolution, then exclude Lua 5.3's synthetic _ENV capture to recover the
// equivalent Lua 5.1 upvalue count. Keep production functions at or below 48
// where practical, preserving a 12-upvalue margin below the hard limit.

const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const fengari = require("fengari");

const { lua, lauxlib, to_jsstring, to_luastring } = fengari;
const MAX_UPVALUES = 60;
const PRODUCTION_TARGET = 48;

function tString(value) {
    if (!value) return "";
    return to_jsstring(value.realstring);
}

function inferFunctionLabel(lines, lineNumber) {
    const line = lines[lineNumber - 1] || "";
    const patterns = [
        /\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)/,
        /\bfunction\s+([A-Za-z_][A-Za-z0-9_:.]*)/,
        /\b([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*function\b/,
    ];
    for (const pattern of patterns) {
        const match = line.match(pattern);
        if (match) return match[1];
    }
    return `<anonymous@${lineNumber}>`;
}

function compilePrototype(source, fileName) {
    // Preserve the dedicated Lua 5.1 syntax gate even though Fengari also
    // compiles the chunk: Fengari implements Lua 5.3 grammar.
    luaparse.parse(source, { luaVersion: "5.1" });

    const state = lauxlib.luaL_newstate();
    const status = lauxlib.luaL_loadbuffer(
        state,
        to_luastring(source),
        null,
        to_luastring(`@${fileName}`),
    );
    if (status !== lua.LUA_OK) {
        const message = to_jsstring(lua.lua_tostring(state, -1));
        throw new Error(message);
    }
    return state.stack[state.top - 1].value.p;
}

function auditSource(source, fileName, limit = MAX_UPVALUES) {
    const prototype = compilePrototype(source, fileName);
    const lines = source.split(/\r?\n/);
    const functions = [];

    function visit(current, depth) {
        const names = current.upvalues.map((row) => tString(row.name));
        const lua51Names = names.filter((name) => name !== "_ENV");
        const line = Number(current.linedefined) || 0;
        functions.push({
            file: fileName,
            line,
            lastLine: Number(current.lastlinedefined) || line,
            depth,
            name: line === 0 ? "<chunk>" : inferFunctionLabel(lines, line),
            count: lua51Names.length,
            upvalues: lua51Names,
            overLimit: lua51Names.length > limit,
            nearLimit: lua51Names.length > PRODUCTION_TARGET,
        });
        for (const child of current.p) visit(child, depth + 1);
    }

    visit(prototype, 0);
    return functions;
}

function tocLuaFiles(root, tocPath) {
    const fullToc = path.resolve(root, tocPath);
    const seen = new Set();
    const files = [];
    for (const raw of fs.readFileSync(fullToc, "utf8").split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith("#") || !/\.lua$/i.test(line)) continue;
        const relative = line.replace(/\\/g, "/");
        if (seen.has(relative)) throw new Error(`duplicate TOC Lua entry: ${relative}`);
        seen.add(relative);
        const fullPath = path.resolve(root, relative);
        if (!fs.existsSync(fullPath)) throw new Error(`missing TOC Lua entry: ${relative}`);
        files.push(relative);
    }
    if (files.length === 0) throw new Error(`no Lua entries found in ${tocPath}`);
    return files;
}

function auditToc(root, tocPath = "Nexus.toc", limit = MAX_UPVALUES) {
    const files = tocLuaFiles(root, tocPath);
    const functions = [];
    for (const relative of files) {
        const source = fs.readFileSync(path.resolve(root, relative), "utf8");
        functions.push(...auditSource(source, relative, limit));
    }
    const ranked = functions.slice().sort((left, right) =>
        right.count - left.count
        || left.file.localeCompare(right.file)
        || left.line - right.line);
    return {
        root,
        tocPath,
        limit,
        productionTarget: PRODUCTION_TARGET,
        fileCount: files.length,
        functionCount: functions.length,
        functions,
        highest: ranked[0] || null,
        violations: ranked.filter((row) => row.overLimit),
        nearLimit: ranked.filter((row) => row.nearLimit && !row.overLimit),
    };
}

function formatResult(result) {
    const highest = result.highest;
    const maxText = highest
        ? `${highest.count} at ${highest.file}:${highest.line} ${highest.name}`
        : "none";
    const lines = [
        `Lua 5.1 upvalue compatibility: ${result.fileCount} TOC files, `
            + `${result.functionCount} functions, max ${maxText}, `
            + `limit ${result.limit}, violations ${result.violations.length}`,
    ];
    for (const row of result.violations) {
        lines.push(`${row.file}:${row.line} ${row.name}: ${row.count} upvalues `
            + `(limit ${result.limit})`);
    }
    if (result.nearLimit.length > 0) {
        lines.push(`Production margin advisory (> ${result.productionTarget}):`);
        for (const row of result.nearLimit) {
            lines.push(`${row.file}:${row.line} ${row.name}: ${row.count} upvalues`);
        }
    }
    return lines.join("\n");
}

function main(argv) {
    let root = process.cwd();
    let tocPath = "Nexus.toc";
    let json = false;
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--toc") {
            tocPath = argv[index + 1];
            index += 1;
        } else if (arg === "--json") {
            json = true;
        } else if (!arg.startsWith("--")) {
            root = path.resolve(arg);
        } else {
            throw new Error(`unknown argument: ${arg}`);
        }
    }
    const result = auditToc(root, tocPath);
    console.log(json ? JSON.stringify(result, null, 2) : formatResult(result));
    return result.violations.length === 0 ? 0 : 1;
}

module.exports = {
    MAX_UPVALUES,
    PRODUCTION_TARGET,
    auditSource,
    auditToc,
    formatResult,
    tocLuaFiles,
};

if (require.main === module) {
    try {
        process.exitCode = main(process.argv.slice(2));
    } catch (error) {
        console.error(`Lua 5.1 upvalue compatibility failed: ${error.message}`);
        process.exitCode = 1;
    }
}
