-- Nexus: pure fixed-height virtual-list window math.

Nexus = Nexus or {}
local VirtualList = {}
Nexus.VirtualList = VirtualList

local function Finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then
        return fallback
    end
    return value
end

function VirtualList.Window(count, rowHeight, viewportHeight, offset, overscan)
    count = math.max(0, math.floor(Finite(count, 0)))
    rowHeight = math.max(1, Finite(rowHeight, 1))
    viewportHeight = math.max(1, Finite(viewportHeight, 1))
    overscan = math.max(0, math.floor(Finite(overscan, 0)))
    local contentHeight = count * rowHeight
    local maxOffset = math.max(0, contentHeight - viewportHeight)
    offset = tonumber(offset)
    if offset == math.huge then offset = maxOffset
    elseif not offset or offset ~= offset or offset == -math.huge then offset = 0 end
    offset = math.max(0, math.min(maxOffset, offset))
    if count == 0 then
        return {
            first=1, last=0, active=0, firstVisible=1, lastVisible=0,
            offset=0, maxOffset=0, contentHeight=0,
            rowHeight=rowHeight, viewportHeight=viewportHeight,
            overscan=overscan,
        }
    end
    local firstVisible = math.floor(offset / rowHeight) + 1
    local lastVisible = math.min(count,
        math.max(firstVisible, math.ceil((offset + viewportHeight) / rowHeight)))
    local first = math.max(1, firstVisible - overscan)
    local last = math.min(count, lastVisible + overscan)
    return {
        first=first, last=last, active=last-first+1,
        firstVisible=firstVisible, lastVisible=lastVisible,
        offset=offset, maxOffset=maxOffset, contentHeight=contentHeight,
        rowHeight=rowHeight, viewportHeight=viewportHeight,
        overscan=overscan,
    }
end
