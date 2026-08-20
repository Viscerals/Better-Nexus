"use strict";

const assert = require("assert");
const fs = require("fs");
const {
    injectRuntimeBuildLabel,
    validateRuntimeBuildLabel,
} = require("../tools/inject-runtime-build-label.js");

const toc = fs.readFileSync("Nexus.toc", "utf8");
const upstream = fs.readFileSync("UPSTREAM.md", "utf8");
const readme = fs.readFileSync("README.md", "utf8");
const release = fs.readFileSync("data/Release.lua", "utf8");

const author = toc.match(/^## Author:\s*(.+)$/m);
assert(author, "Nexus.toc is missing Author metadata");
assert.strictEqual(author[1].trim(), "Valentine",
    "future TOC-derived packages would not expose Author: Valentine");
assert(/Upstream author recorded by the addon:\s*Boganic/.test(upstream),
    "upstream Boganic attribution was removed");
assert(/Current TOC maintainer metadata:\s*Valentine/.test(upstream),
    "current TOC maintainer metadata is not documented beside provenance");
assert(/upstream\s+author\s+attribution.*UPSTREAM\.md/is.test(readme),
    "README no longer routes users to upstream attribution");

assert(/^\s*buildLabel = "source",$/m.test(release),
    "source checkout runtime build label is not the deterministic fallback");
const privateLabel = "test.13-abcdef0";
assert.strictEqual(validateRuntimeBuildLabel(privateLabel), privateLabel,
    "private runtime label contract rejected the planned package identity");
const generated = injectRuntimeBuildLabel(release, privateLabel);
const sourceLines = release.split(/\r?\n/);
const generatedLines = generated.split(/\r?\n/);
assert.strictEqual(generatedLines.length, sourceLines.length,
    "runtime label injection changed file line structure");
const changed = [];
for (let index = 0; index < sourceLines.length; index += 1) {
    if (sourceLines[index] !== generatedLines[index]) changed.push(index);
}
assert.strictEqual(changed.length, 1,
    "private package must differ from reviewed Release.lua on exactly one line");
assert.strictEqual(sourceLines[changed[0]], '    buildLabel = "source",');
assert.strictEqual(generatedLines[changed[0]],
    '    buildLabel = "test.13-abcdef0",');
assert(generated.includes('version = "1.20.0-beta.1"')
    && /^## Version:\s*1\.20\.0-beta\.1$/m.test(toc),
    "private identity changed the public version");
assert.throws(() => injectRuntimeBuildLabel(release, "unsafe|label"),
    /invalid runtime build label/,
    "unsafe package identity was accepted");
for (const invalid of ["test.13-ABCDEF0", "test.13-abcdef",
    "test.13-abcdef0123456", "development", "test.13-private"]) {
    assert.throws(() => injectRuntimeBuildLabel(release, invalid),
        /invalid runtime build label/,
        `invalid private identity was accepted: ${invalid}`);
}
assert.throws(() => injectRuntimeBuildLabel(
    release.replace('    buildLabel = "source",', ""), privateLabel),
    /expected exactly one runtime build label anchor; found 0/,
    "missing package identity anchor was accepted");
assert.throws(() => injectRuntimeBuildLabel(
    `${release}\n    buildLabel = "source",`, privateLabel),
    /expected exactly one runtime build label anchor; found 2/,
    "duplicate package identity anchors were accepted");
for (const misleadingAnchor of [
    `-- ${'    buildLabel = "source",'}\nreturn true`,
    `${'    buildLabel = "source",'} -- trailing text`,
    `local text = '${'    buildLabel = "source",'}'`,
]) {
    assert.throws(() => injectRuntimeBuildLabel(misleadingAnchor, privateLabel),
        /expected exactly one runtime build label anchor; found 0/,
        "non-line package identity anchor was accepted");
}
const crlfGenerated = injectRuntimeBuildLabel(
    release.replace(/\r?\n/g, "\r\n"), privateLabel);
assert(crlfGenerated.includes('\r\n    buildLabel = "test.13-abcdef0",\r\n'),
    "CRLF package identity injection did not preserve line structure");

function assertOnlyLabelBytesChanged(source, label) {
    const anchor = '    buildLabel = "source",';
    const occurrence = source.indexOf(anchor);
    assert.notStrictEqual(occurrence, -1, "fixture omitted active anchor");
    assert.strictEqual(source.indexOf(anchor, occurrence + 1), -1,
        "fixture has multiple active anchors");
    const expected = source.slice(0, occurrence)
        + `    buildLabel = "${label}",`
        + source.slice(occurrence + anchor.length);
    assert.strictEqual(injectRuntimeBuildLabel(source, label), expected,
        "runtime label injection changed bytes outside the label value");
}

for (const fixture of [
    'return {\n    buildLabel = "source",\n}\n',
    'return {\r\n    buildLabel = "source",\r\n}\r\n',
    'return {\r\n    buildLabel = "source",\n}\r\n',
    'return {\r\r\n    buildLabel = "source",\r\r\n}\r\r\n',
]) {
    assertOnlyLabelBytesChanged(fixture, privateLabel);
}
for (const lookalike of [
    '--    buildLabel = "source",\nreturn true\n',
    'local text = \'    buildLabel = "source",\'\nreturn text\n',
]) {
    assert.throws(() => injectRuntimeBuildLabel(lookalike, privateLabel),
        /expected exactly one runtime build label anchor; found 0/);
}

console.log("package metadata: Author=Valentine; source/private runtime identity is one controlled Release.lua line; upstream Boganic attribution preserved");
