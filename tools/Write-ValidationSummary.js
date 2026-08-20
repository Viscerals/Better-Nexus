"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
    const out = {};
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--input") out.input = argv[++index];
        else if (arg === "--output-dir") out.outputDir = argv[++index];
        else throw new Error(`unknown argument: ${arg}`);
    }
    if (!out.input || !out.outputDir) {
        throw new Error("usage: Write-ValidationSummary.js --input <payload.json> --output-dir <directory>");
    }
    return out;
}

function boundedText(value, maximum = 240) {
    const text = String(value == null ? "" : value)
        .replace(/[\r\n\t]+/g, " ")
        .replace(/"safe\.directory=[^"]+"/gi, '"safe.directory=<repo>"')
        .replace(/(?<!")safe\.directory=(?:"[^"]+"|'[^']+'|\S+)/gi, "safe.directory=<repo>")
        .replace(/"[A-Za-z]:[\\/][^"]+"/g, '"<local-path>"')
        .replace(/[A-Za-z]:[\\/]\S+/g, "<local-path>")
        .replace(/\s+/g, " ")
        .trim();
    return text.slice(0, maximum);
}

function relativeLog(value) {
    const normalized = String(value || "").replace(/\\/g, "/");
    if (!/^logs\/[A-Za-z0-9._-]+\.log$/.test(normalized)) {
        throw new Error(`unsafe validation log path: ${boundedText(value)}`);
    }
    return normalized;
}

function normalize(payload) {
    if (payload.schema !== 1) throw new Error(`unsupported payload schema: ${payload.schema}`);
    const checks = [...(payload.checks || [])]
        .map((check) => ({
            id: boundedText(check.id, 80),
            result: boundedText(check.result, 20).toLowerCase(),
            count: boundedText(check.count || "0/0", 32),
            duration_seconds: Number(check.duration_seconds || 0),
            log: relativeLog(check.log),
            command: boundedText(check.command, 240),
            blocking: check.blocking !== false,
            reason: boundedText(check.reason, 200),
        }))
        .sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
    const failed = checks.filter((check) => check.result === "fail").length;
    const unavailable = checks.filter((check) => check.result === "unavailable").length;
    const skipped = checks.filter((check) => check.result === "skipped").length;
    const passed = checks.filter((check) => check.result === "pass").length;
    const blockingFailure = checks.some((check) => check.blocking && check.result !== "pass");
    return {
        schema: 1,
        mode: boundedText(payload.mode, 20),
        head: boundedText(payload.head, 40),
        result: blockingFailure ? "fail" : "pass",
        passed,
        failed,
        skipped,
        unavailable,
        duration_seconds: Number(payload.duration_seconds || 0),
        checks,
    };
}

function markdown(summary) {
    const lines = [
        `# Better-Nexus ${summary.mode} validation`,
        "",
        `Result: **${summary.result.toUpperCase()}** at \`${summary.head}\` — ${summary.passed} passed, ${summary.failed} failed, ${summary.unavailable} unavailable, ${summary.skipped} skipped in ${summary.duration_seconds}s.`,
        "",
        "| Check | Result | Count | Seconds | Detail |",
        "| --- | --- | ---: | ---: | --- |",
    ];
    for (const check of summary.checks) {
        const detail = check.result === "pass"
            ? ""
            : `${check.reason || check.command}; ${check.log}`;
        lines.push(`| ${check.id} | ${check.result} | ${check.count} | ${check.duration_seconds} | ${detail} |`);
    }
    return `${lines.join("\n")}\n`;
}

if (require.main === module) {
    const args = parseArgs(process.argv.slice(2));
    const payload = JSON.parse(fs.readFileSync(args.input, "utf8"));
    const summary = normalize(payload);
    fs.mkdirSync(args.outputDir, { recursive: true });
    fs.writeFileSync(path.join(args.outputDir, "summary.json"),
        `${JSON.stringify(summary, null, 2)}\n`, "utf8");
    fs.writeFileSync(path.join(args.outputDir, "summary.md"), markdown(summary), "utf8");
    process.stdout.write(`${JSON.stringify({
        result: summary.result,
        passed: summary.passed,
        failed: summary.failed,
        unavailable: summary.unavailable,
        skipped: summary.skipped,
    })}\n`);
}

module.exports = { boundedText, markdown, normalize, relativeLog };
