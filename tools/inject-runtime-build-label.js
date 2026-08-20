"use strict";

const fs = require("fs");

const SOURCE_LINE = '    buildLabel = "source",';

function validateRuntimeBuildLabel(value) {
    if (value === "source") return value;
    if (typeof value !== "string"
        || !/^test\.\d+-[0-9a-f]{7,12}$/.test(value)) {
        throw new Error("invalid runtime build label");
    }
    return value;
}

function injectRuntimeBuildLabel(source, value) {
    if (typeof source !== "string") {
        throw new Error("Release.lua source must be text");
    }
    const label = validateRuntimeBuildLabel(value);
    const anchorPattern = /(^|\n)(    buildLabel = ")source(",(?=\r*\n|$))/g;
    const occurrences = [...source.matchAll(anchorPattern)].length;
    if (occurrences !== 1) {
        throw new Error(`expected exactly one runtime build label anchor; found ${occurrences}`);
    }
    return source.replace(anchorPattern, (match, lineStart, before, after) =>
        `${lineStart}${before}${label}${after}`);
}

if (require.main === module) {
    const [inputPath, outputPath, label] = process.argv.slice(2);
    if (!inputPath || !outputPath || !label) {
        throw new Error("usage: inject-runtime-build-label.js <input> <output> <label>");
    }
    const source = fs.readFileSync(inputPath, "utf8");
    fs.writeFileSync(outputPath, injectRuntimeBuildLabel(source, label), "utf8");
}

module.exports = {
    SOURCE_LINE,
    injectRuntimeBuildLabel,
    validateRuntimeBuildLabel,
};
