-- Checkpoint 10.1: keep the source-backed contract inventory complete without
-- loading or changing any runtime module.

local manifest = dofile("tests/module_contract_manifest.lua")

local function Read(path)
    local handle, err = io.open(path, "rb")
    assert(handle, "unable to read " .. tostring(path) .. ": " .. tostring(err))
    local value = handle:read("*a")
    handle:close()
    return value
end

local function Sorted(values)
    local out = {}
    for _, value in ipairs(values) do out[#out + 1] = value end
    table.sort(out)
    return out
end

local function Same(left, right, label)
    left, right = Sorted(left), Sorted(right)
    assert(#left == #right, string.format("%s count mismatch: source=%d manifest=%d",
        label, #left, #right))
    for index = 1, #left do
        assert(left[index] == right[index], string.format(
            "%s mismatch at %d: source=%s manifest=%s",
            label, index, tostring(left[index]), tostring(right[index])))
    end
end

local function CountLiteral(text, needle)
    local count, start = 0, 1
    while true do
        local found = text:find(needle, start, true)
        if not found then return count end
        count, start = count + 1, found + #needle
    end
end

local function SourceAssignedMembers(source, namespaces)
    local out, seen = {}, {}
    for namespace in pairs(namespaces) do
        local pattern = namespace .. "%.([%a_][%w_]*)%s*=%s*([^=])"
        for name in source:gmatch(pattern) do
            local symbol = namespace .. "." .. name
            if not seen[symbol] then
                seen[symbol] = true
                out[#out + 1] = symbol
            end
        end
    end
    return out
end

local function SourceSymbols(source, namespaces, assignedMembers)
    local out, seen = {}, {}
    local function Add(symbol)
        if not seen[symbol] then
            seen[symbol] = true
            out[#out + 1] = symbol
        end
    end
    for namespace in pairs(namespaces) do
        local pattern = "function%s+" .. namespace .. "%.([%a_][%w_]*)%s*%("
        for name in source:gmatch(pattern) do
            Add(namespace .. "." .. name)
        end
        local assigned = namespace .. "%.([%a_][%w_]*)%s*=%s*function%s*%("
        for name in source:gmatch(assigned) do
            Add(namespace .. "." .. name)
        end
    end
    for _, member in ipairs(assignedMembers) do
        if member.kind == "callable-alias" then
            assert(type(member.anchor) == "string" and source:find(member.anchor, 1, true),
                "callable alias lost source anchor " .. tostring(member.symbol))
            Add(member.symbol)
        end
    end
    return out
end

local callbackNeedles = {
    "SetScript(", "RegisterEvent(", "Subscribe(",
    "RegisterCallback", "hooksecurefunc",
}

local totalSymbols, totalAssigned, totalCallbacks, totalGroups = 0, 0, 0, 0
local seenIds = {}
local documentation = Read("docs/MODULAR_REFACTOR_CHARACTERIZATION.md")
for _, module in ipairs(manifest.modules) do
    assert(not seenIds[module.id], "duplicate manifest module " .. tostring(module.id))
    seenIds[module.id] = true
    local source = Read(module.path)
    local assignedSymbols = {}
    for _, member in ipairs(module.assignedMembers) do
        assert(type(member.symbol) == "string" and type(member.kind) == "string",
            module.id .. " has malformed assigned member")
        assignedSymbols[#assignedSymbols + 1] = member.symbol
        assert(documentation:find(
            "| `" .. member.symbol .. "` | `" .. member.kind .. "` |", 1, true),
            "characterization document missing assigned member " .. member.symbol)
    end
    Same(SourceAssignedMembers(source, module.namespaces), assignedSymbols,
        module.id .. " assigned namespace members")
    totalAssigned = totalAssigned + #assignedSymbols

    Same(SourceSymbols(source, module.namespaces, module.assignedMembers), module.symbols,
        module.id .. " public surface")
    for _, symbol in ipairs(module.symbols) do
        assert(documentation:find("| `" .. symbol .. "` |", 1, true),
            "characterization document missing " .. symbol)
    end
    totalSymbols = totalSymbols + #module.symbols

    local callbackCount = 0
    for _, needle in ipairs(callbackNeedles) do
        callbackCount = callbackCount + CountLiteral(source, needle)
    end
    assert(callbackCount == module.callbackSites, string.format(
        "%s callback-site mismatch: source=%d manifest=%d",
        module.id, callbackCount, module.callbackSites))

    local grouped = 0
    for _, group in ipairs(module.callbackGroups) do
        assert(type(group.id) == "string" and group.id ~= ""
            and type(group.count) == "number" and group.count > 0,
            module.id .. " has malformed callback group")
        assert(source:find(group.anchor, 1, true), string.format(
            "%s callback group %s lost anchor %s",
            module.id, group.id, tostring(group.anchor)))
        assert(documentation:find("| `" .. module.id .. "/" .. group.id .. "` |", 1, true),
            "characterization document missing callback group "
                .. module.id .. "/" .. group.id)
        grouped = grouped + group.count
        totalGroups = totalGroups + 1
    end
    assert(grouped == callbackCount, string.format(
        "%s callback groups cover %d/%d sites", module.id, grouped, callbackCount))
    totalCallbacks = totalCallbacks + callbackCount
end

assert(totalSymbols == 208, "unexpected eleven-module public-surface total")
assert(totalAssigned == 14, "unexpected assigned namespace-member total")
assert(totalCallbacks == 162, "unexpected eleven-module callback-site total")

local toc = Read("Nexus.toc")
assert(toc:find(manifest.savedVariables, 1, true),
    "dual SavedVariables declaration changed")
local cursor = 1
for _, entry in ipairs(manifest.tocTargetOrder) do
    local found = toc:find(entry, cursor, true)
    assert(found, "TOC target order missing or changed at " .. entry)
    cursor = found + #entry
end

print(string.format(
    "module contract inventory: modules=%d surfaces=%d assignedMembers=%d callbackSites=%d groups=%d unmapped=0 -- OK",
    #manifest.modules, totalSymbols, totalAssigned, totalCallbacks, totalGroups))
