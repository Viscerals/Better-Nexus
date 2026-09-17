"use strict";

const fs = require("fs");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const runner = path.join(root, "tools", "run-lua.js");
const expectation = require("./lua-inventory.json");
const manualTests = new Map(expectation.manual.map((row) => [path.basename(row.path), row.reason]));
const discovered = fs.readdirSync(path.join(root, "tests"))
    .filter((name) => /^run_.*\.lua$/.test(name))
    .sort();
const tests = discovered.filter((name) => !manualTests.has(name));
function inventory() {
    return {
        discovered: discovered.length,
        runnable: tests.map((name) => `tests/${name}`),
        manual: [...manualTests.entries()].map(([name, reason]) => ({
            path: `tests/${name}`,
            reason,
        })),
    };
}

function auditInventory(value) {
    const expected = value.runnable;
    const seen = value.results.map((row) => row.path);
    const errors = [];
    if (new Set(expected).size !== expected.length) errors.push("duplicate scheduling");
    if (new Set(value.manual.map((row) => row.path)).size !== value.manual.length) errors.push("duplicate manual exclusions");
    if (value.discovered !== expected.length + value.manual.length) errors.push("discovery mismatch");
    if (new Set(seen).size !== seen.length) errors.push("duplicate results");
    for (const name of expected) if (!seen.includes(name)) errors.push(`missing: ${name}`);
    for (const row of value.results) {
        if (!expected.includes(row.path)) errors.push(`unexpected: ${row.path}`);
        if (row.result !== "pass" || row.exit_code !== 0 || !row.completed_at) errors.push(`not passed: ${row.path}`);
    }
    return { ok: errors.length === 0, errors };
}

function validateInventory(manifest, expectedCount = expectation.runnable.length) {
    const actual = [...manifest.runnable].sort();
    const expected = [...expectation.runnable].sort();
    if (expectedCount !== expected.length || actual.length !== expected.length
        || actual.some((name, i) => name !== expected[i])
        || new Set(expected).size !== expected.length
        || new Set(expectation.manual.map((row) => row.path)).size !== expectation.manual.length
        || expectation.manual.some((row) => expected.includes(row.path))
        || manifest.discovered !== expected.length + expectation.manual.length
        || !expectation.manual.every((row) => fs.existsSync(path.join(root, row.path)))) {
        throw new Error("incomplete or duplicate discovered inventory");
    }
}

function runtimeCommand(runtime, name) {
    if (runtime === "fengari") return { executable: process.execPath, args: [runner, name] };
    // Existing Windows offline setup embeds native LuaJIT through Lupa. It is
    // explicit, never an automatic fallback or a substitute for CI's luajit.
    if (runtime === "luajit-lupa") return {
        executable: process.env.NEXUS_LUAJIT_PYTHON || "python",
        args: ["-c", "from lupa.luajit21 import LuaRuntime;import sys;LuaRuntime().globals().dofile(sys.argv[1])", name],
    };
    return { executable: runtime, args: [name] };
}

async function main(argv) {
    const manifest = { ...inventory(), results: [], result: "incomplete" };
    let runtime = "luajit";
    let timeoutSeconds = 600;
    let expectedCount = expectation.runnable.length;
    let selected = null, list = false;
    for (let index = 0; index < argv.length; index += 1) {
        const option = argv[index];
        if (option === "--runtime") runtime = argv[++index];
        else if (option === "--timeout-seconds") timeoutSeconds = Number(argv[++index]);
        else if (option === "--expected-count") expectedCount = Number(argv[++index]);
        else if (option === "--test") selected = argv[++index];
        else if (option === "--list") list = true;
        else throw new Error(`unknown argument: ${option}`);
    }
    if (!runtime || !Number.isInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 10500
        || !Number.isInteger(expectedCount) || expectedCount < 1) throw new Error("invalid inventory limits");
    validateInventory(manifest, expectedCount);
    if (list) { console.log(JSON.stringify(manifest)); return 0; }
    if (selected !== null) {
        if (!manifest.runnable.includes(selected)) throw new Error("selected test is outside the reviewed inventory");
        manifest.runnable = [selected];
        manifest.discovered = 1 + manifest.manual.length;
    }
    manifest.scope = selected === null ? "complete" : "selected";
    const output = path.join(root, "build", selected === null ? "lua-suite" : "lua-selected");
    const identity = spawnSync("git", ["-c", `safe.directory=${root.replace(/\\/g, "/")}`,
        "show", "-s", "--format=%H %T", "HEAD"], { cwd: root, encoding: "utf8", timeout: 5000 });
    const [head = "unknown", tree = "unknown"] = identity.status === 0 ? identity.stdout.trim().split(" ") : [];
    const version = runtime === "luajit-lupa" ? spawnSync(process.env.NEXUS_LUAJIT_PYTHON || "python",
        ["-c", "from lupa.luajit21 import LuaRuntime;import lupa;print('Lupa '+lupa.__version__+'; '+LuaRuntime().eval('jit.version'))"],
        { cwd: root, encoding: "utf8", timeout: 5000 }) : runtime === "fengari" ? { status: 0,
        stdout: `Fengari ${JSON.parse(fs.readFileSync(path.join(root, "package-lock.json"), "utf8")).packages["node_modules/fengari"].version}; Node ${process.version}`, stderr: "" }
        : spawnSync(runtime, [runtime === "luajit" ? "-v" : "--version"], { cwd: root, encoding: "utf8", timeout: 5000 });
    if (version.status !== 0) throw new Error(`runtime unavailable: ${runtime}`);
    Object.assign(manifest, { head, tree, platform: process.platform, architecture: process.arch,
        runtime, runtime_version: version.status === 0 ? (version.stdout + version.stderr).trim() : "unknown" });
    fs.mkdirSync(output, { recursive: true });
    const save = () => fs.writeFileSync(path.join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
    const safe = (text) => text.split(root).join("<repo>")
        .split(root.replace(/\\/g, "/")).join("<repo>")
        .replace(/[A-Z]:[\\/]Users[\\/][^\\/\s]+/gi, "<user-home>");
    let interrupted = null;
    let child = null;
    const terminate = (signal) => {
        interrupted = signal;
        if (!child || !child.pid) return;
        if (process.platform === "win32") {
            spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore" });
        } else {
            try { process.kill(-child.pid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
        }
    };
    const onTerm = () => terminate("cancelled");
    process.on("SIGTERM", onTerm);
    process.on("SIGINT", onTerm);
    try {
        save();
        console.log(`Lua inventory runtime=${runtime} runnable=${manifest.runnable.length} manual=${manifest.manual.length}`);
        for (const name of manifest.runnable) {
            if (interrupted) break;
            const { executable, args } = runtimeCommand(runtime, name);
            const row = { path: name, result: "running", started_at: new Date().toISOString(),
                runtime, command: safe([executable, ...args].join(" ")), completed_at: null,
                exit_code: null, log: `build/${selected === null ? "lua-suite" : "lua-selected"}/${path.basename(name)}.log` };
            manifest.results.push(row);
            save();
            console.log(`TEST START ${name} at=${row.started_at} runtime=${runtime} command=${row.command} log=${row.log}`);
            const logPath = path.join(root, row.log);
            fs.writeFileSync(logPath, "");
            const started = performance.now();
            const result = await new Promise((resolve) => {
                child = spawn(executable, args, { cwd: root, detached: process.platform !== "win32", stdio: ["ignore", "pipe", "pipe"] });
                const timer = setTimeout(() => terminate("timeout"), timeoutSeconds * 1000);
                for (const [kind, stream] of [["stdout", child.stdout], ["stderr", child.stderr]]) {
                    let pending = "";
                    stream.setEncoding("utf8");
                    const write = (text) => { const clean = safe(text); fs.appendFileSync(logPath, clean); process.stdout.write(clean); };
                    stream.on("data", (text) => {
                        pending += text;
                        fs.writeFileSync(`${logPath}.${kind}.partial.log`, safe(pending));
                        const boundary = pending.lastIndexOf("\n");
                        if (boundary >= 0) { write(pending.slice(0, boundary + 1)); pending = pending.slice(boundary + 1); }
                    });
                    stream.on("end", () => { if (pending) write(pending); fs.writeFileSync(`${logPath}.${kind}.partial.log`, ""); });
                }
                let spawnError = null;
                child.on("error", (error) => { spawnError = safe(error.message); });
                child.on("close", (code, signal) => { clearTimeout(timer); child = null; resolve({ code, signal, spawnError }); });
            });
            Object.assign(row, { completed_at: new Date().toISOString(), exit_code: result.code,
                duration_seconds: Math.round(performance.now() - started) / 1000,
                interruption: interrupted || result.signal || result.spawnError,
                result: interrupted ? interrupted : result.code === 0 ? "pass" : "fail" });
            save();
            console.log(`TEST END ${name} at=${row.completed_at} result=${row.result} exit=${row.exit_code} seconds=${row.duration_seconds} interruption=${row.interruption || "none"}`);
        }
        manifest.audit = auditInventory(manifest);
        manifest.result = manifest.audit.ok ? "pass" : "fail";
        save();
        console.log(`LUA INVENTORY RESULT ${JSON.stringify(manifest)}`);
        console.log(`Lua suite: ${manifest.results.filter((row) => row.result === "pass").length}/${manifest.runnable.length} passed`);
        for (const row of manifest.manual) console.log(`Lua suite manual skip: ${row.path} -- ${row.reason}`);
        for (const error of manifest.audit.errors) console.error(error);
        return manifest.audit.ok ? 0 : 1;
    } finally {
        process.removeListener("SIGTERM", onTerm);
        process.removeListener("SIGINT", onTerm);
    }
}

if (require.main === module) main(process.argv.slice(2)).then((code) => { process.exitCode = code; })
    .catch((error) => { console.error(error); process.exitCode = 1; });
module.exports = { auditInventory, inventory, validateInventory, runtimeCommand };
