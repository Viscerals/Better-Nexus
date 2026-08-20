"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const luaparse = require("luaparse");

const REQUIRED_DOCUMENTS = ["LICENSE.md", "AI_POLICY.md", "UPSTREAM.md"];

function normalizeSourcePath(value) {
    const normalized = String(value || "").replace(/\\/g, "/").trim();
    if (!normalized || normalized.startsWith("/") || /^[A-Za-z]:/.test(normalized)
        || normalized.split("/").includes("..") || normalized.includes("//")) {
        throw new Error(`unsafe package source path: ${normalized}`);
    }
    return normalized;
}

function tocFiles(root) {
    const toc = fs.readFileSync(path.join(root, "Nexus.toc"), "utf8");
    return toc.split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line && !line.startsWith("##"))
        .map(normalizeSourcePath);
}

function buildManifest(root) {
    const sources = ["Nexus.toc", ...tocFiles(root), ...REQUIRED_DOCUMENTS]
        .map(normalizeSourcePath);
    const seen = new Map();
    const entries = [];
    for (const relative of sources) {
        const folded = relative.toLowerCase();
        if (seen.has(folded)) {
            throw new Error(`case-fold duplicate package path: ${relative} and ${seen.get(folded)}`);
        }
        seen.set(folded, relative);
        const sourcePath = path.join(root, ...relative.split("/"));
        if (!fs.statSync(sourcePath).isFile()) throw new Error(`missing package source: ${relative}`);
        const bytes = fs.readFileSync(sourcePath);
        if (relative.endsWith(".lua")) {
            luaparse.parse(bytes.toString("utf8"), { luaVersion: "5.1" });
        }
        entries.push({
            path: `Nexus/${relative}`,
            bytes: bytes.length,
            sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
        });
    }
    entries.sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
    if (entries.some((entry) => !entry.path.startsWith("Nexus/"))) {
        throw new Error("package manifest escaped the Nexus root");
    }
    const manifestBytes = Buffer.from(entries
        .map((entry) => `${entry.sha256} ${entry.bytes} ${entry.path}`)
        .join("\n"), "utf8");
    return {
        schema: 1,
        root: "Nexus",
        files: entries.length,
        lua_files: entries.filter((entry) => entry.path.endsWith(".lua")).length,
        bytes: entries.reduce((sum, entry) => sum + entry.bytes, 0),
        sha256: crypto.createHash("sha256").update(manifestBytes).digest("hex"),
        substitutions: [],
        entries,
    };
}

function verifyTemporaryPackage(root) {
    const report = buildManifest(root);
    const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "better-nexus-package-"));
    const packageRoot = path.join(temporaryRoot, "Nexus");
    try {
        for (const entry of report.entries) {
            const relative = entry.path.slice("Nexus/".length);
            const sourcePath = path.join(root, ...relative.split("/"));
            const packagePath = path.join(packageRoot, ...relative.split("/"));
            const resolvedPackagePath = path.resolve(packagePath);
            if (!resolvedPackagePath.startsWith(`${path.resolve(packageRoot)}${path.sep}`)) {
                throw new Error(`temporary package path escaped Nexus root: ${relative}`);
            }
            fs.mkdirSync(path.dirname(packagePath), { recursive: true });
            fs.copyFileSync(sourcePath, packagePath);
            const packageBytes = fs.readFileSync(packagePath);
            const packageHash = crypto.createHash("sha256").update(packageBytes).digest("hex");
            if (packageBytes.length !== entry.bytes || packageHash !== entry.sha256) {
                throw new Error(`source/package byte mismatch: ${relative}`);
            }
            if (relative.endsWith(".lua")) {
                luaparse.parse(packageBytes.toString("utf8"), { luaVersion: "5.1" });
            }
        }
        const topLevels = fs.readdirSync(temporaryRoot).sort();
        if (topLevels.length !== 1 || topLevels[0] !== "Nexus") {
            throw new Error(`temporary package root mismatch: ${topLevels.join(",")}`);
        }
        report.package_parity = true;
        report.temporary_cleanup = true;
        return report;
    } finally {
        fs.rmSync(temporaryRoot, { recursive: true, force: true });
    }
}

if (require.main === module) {
    const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
    const report = verifyTemporaryPackage(root);
    process.stdout.write(`${JSON.stringify({
        schema: report.schema,
        root: report.root,
        files: report.files,
        lua_files: report.lua_files,
        bytes: report.bytes,
        sha256: report.sha256,
        substitutions: report.substitutions,
        package_parity: report.package_parity,
        temporary_cleanup: report.temporary_cleanup,
    })}\n`);
}

module.exports = { buildManifest, normalizeSourcePath, tocFiles, verifyTemporaryPackage };
