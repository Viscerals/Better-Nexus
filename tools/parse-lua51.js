"use strict";

const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const root = path.resolve(process.argv[2] || process.cwd());
const includeTests = process.argv.includes("--tests");
const ignoredDirectories = new Set([
    ".git",
    ".tools",
    "build",
    "dist",
    "node_modules",
]);
const failures = [];
let parsed = 0;

function parseFile(fullPath) {
    try {
        luaparse.parse(fs.readFileSync(fullPath, "utf8"), {
            luaVersion: "5.1",
        });
        parsed += 1;
    } catch (error) {
        failures.push(`${path.relative(root, fullPath) || path.basename(fullPath)}: ${error.message}`);
    }
}

function visit(directory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
        .sort((left, right) => left.name.localeCompare(right.name, "en"));
    for (const entry of entries) {
        if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
        if (entry.isDirectory() && !includeTests && entry.name === "tests") continue;
        const fullPath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
            visit(fullPath);
        } else if (entry.isFile() && entry.name.endsWith(".lua")) {
            parseFile(fullPath);
        }
    }
}

if (fs.statSync(root).isFile()) parseFile(root);
else visit(root);
for (const failure of failures) console.error(failure);
console.log(`Lua 5.1 parse: ${parsed} passed, ${failures.length} failed`);
process.exit(failures.length === 0 ? 0 : 1);
