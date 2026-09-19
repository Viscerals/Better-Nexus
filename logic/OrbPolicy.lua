-- Independent single-Orb policy, behavior reference LoadoutPilot P103 MemoryMode.
-- No gameplay calls. Nexus keeps rolled and permanent roles and exact quality.
Nexus=Nexus or {}
local P={reference="LoadoutPilot 1.3.6 / P103 MemoryMode"};Nexus.OrbPolicy=P
local function key(id,q) return tostring(id)..":"..tostring(q) end
P.Key=key
local function integer(n,min) return type(n)=="number" and n==math.floor(n) and n<math.huge and n>=(min or 0) end
function P.Normalize(entries)
    if type(entries)~="table" or #entries<1 or #entries>170 then return nil,"Choose a resolved Wishlist first." end
    local targets,byKey,ordinary,locks={}, {},0,0
    for _,e in ipairs(entries) do
        if type(e)~="table" or not integer(e.spellId,1) or not integer(e.quality,0)
            or e.quality>255 or not integer(e.stacks or 1,1) then return nil,"The target list is invalid." end
        local n=e.stacks or 1;local role=e.locked==true and "permanent" or "rolled"
        local k=key(e.spellId,e.quality)..":"..role
        local t=byKey[k]
        if t then t.copies=t.copies+n else
            t={spellId=e.spellId,quality=e.quality,copies=n,role=role,key=key(e.spellId,e.quality)}
            targets[#targets+1]=t;byKey[k]=t
        end
        if role=="permanent" then locks=locks+n else ordinary=ordinary+n end
    end
    if ordinary>79 or locks>6 then return nil,"Targets exceed 79 rolled and 6 permanent copies. Confirm the permanent targets in the Wishlist editor." end
    return targets
end
function P.Progress(targets,s)
    local result={items={},remaining=0,permanentMissing=0,rolledMissing=0,targetSet={}}
    for _,t in ipairs(targets or {}) do
        local held=(t.role=="permanent" and s.locked or s.granted)[t.key] or 0
        local missing=math.max(0,t.copies-held)
        local e={spellId=t.spellId,quality=t.quality,copies=t.copies,key=t.key,role=t.role,owned=held,missing=missing}
        result.items[#result.items+1]=e
        result.targetSet[t.key]=true
        if t.role=="permanent" then result.permanentMissing=result.permanentMissing+missing
        else result.rolledMissing=result.rolledMissing+missing end
    end
    result.remaining=result.rolledMissing+result.permanentMissing
    return result
end
function P.Sources(targets,s,excluded)
    local needed,groups,qualities={},{},{}
    for _,t in ipairs(targets or {}) do
        -- A granted copy reserved for a future permanent slot is not also a
        -- rolled target copy. Only existing exact permanent ownership offsets it.
        local reserve=t.role=="rolled" and t.copies or math.max(0,t.copies-((s.locked or {})[t.key] or 0))
        needed[t.key]=(needed[t.key] or 0)+reserve
    end
    for k,count in pairs(s.granted or {}) do
        local id,q=k:match("^(%d+):(%d+)$");id,q=tonumber(id),tonumber(q)
        local row=s.catalog[id]
        if row and count>0 then
            if qualities[id] and qualities[id]~=q then qualities[id]=false
            elseif qualities[id]==nil then qualities[id]=q end
            local group=groups[row.group] or {};groups[row.group]=group
            group[#group+1]={key=k,spellId=id,quality=q,name=row.name,group=row.group,
                count=count,excess=math.max(0,count-(needed[k] or 0)),excluded=excluded and excluded[k]==true,
                sourceAvailable=row.sourceAvailable}
        end
    end
    local sources={}
    for _,g in pairs(groups) do
        table.sort(g,function(a,b)if a.quality~=b.quality then return a.quality<b.quality end;return a.spellId<b.spellId end)
        -- The game may remove the lowest owned quality in a family. Never jump
        -- over a protected low-quality copy to authorize a seemingly safe higher one.
        local first=g[1]
        if first and first.excess>0 and not first.excluded and first.sourceAvailable~=false then
            -- Passing only an ID cannot disambiguate locked/unlocked copies of
            -- that same identity on an undocumented client. Conservatively exclude it.
            local anyLocked=false
            for k,n in pairs(s.locked or {}) do if n>0 and tonumber(k:match("^(%d+):"))==first.spellId then anyLocked=true end end
            -- ConfirmSpend accepts only an ID. Multiple owned qualities of
            -- that ID cannot be approved by guessing which one it consumes.
            if not anyLocked and qualities[first.spellId]~=false then sources[#sources+1]=first end
        end
    end
    table.sort(sources,function(a,b)
        if a.quality~=b.quality then return a.quality<b.quality end
        if a.name~=b.name then return a.name<b.name end
        return a.spellId<b.spellId
    end)
    return sources
end
function P.Decide(board,progress,s,allowRecycle,excluded)
    local offered={}
    for i,c in ipairs(board or {}) do
        if c.selectable~=false then offered[key(c.spellId,c.quality)]=offered[key(c.spellId,c.quality)] or {index=i,card=c} end
    end
    for _,t in ipairs(progress.items or {}) do
        local c=t.role=="rolled" and t.missing>0 and offered[t.key]
        if c and s.catalog[t.spellId] and s.catalog[t.spellId].available and not (excluded and excluded[t.key]) then return {kind="TARGET",index=c.index,key=t.key,spellId=t.spellId,quality=t.quality} end
    end
    if allowRecycle then
        for i,c in ipairs(board or {}) do
            local k=key(c.spellId,c.quality);local row=s.catalog[c.spellId]
            local own=(s.granted[k] or 0)+(s.locked[k] or 0)
            if c.selectable~=false and row and row.available and not progress.targetSet[k]
                and not (excluded and excluded[k]) and own<(row.maxStack or 1) then
                return {kind="RECYCLE",index=i,key=k,spellId=c.spellId,quality=c.quality}
            end
        end
    end
    return nil,"No safe target or approved recyclable offer. Resolve the offer manually."
end
function P.SingleGain(before,removed,after)
    local expected={};for k,v in pairs(before or {}) do expected[k]=v end
    if not expected[removed] or expected[removed]<1 then return nil,"MISMATCH" end
    expected[removed]=expected[removed]-1
    local sum,result,seen=0,nil,{}
    for k,v in pairs(expected) do
        local d=(after[k] or 0)-v;seen[k]=true
        if d<0 then return nil,"MISMATCH" end
        if d>0 then sum=sum+d;result=k end
    end
    for k,v in pairs(after or {}) do if not seen[k] then
        if not integer(v,0) then return nil,"MISMATCH" end
        sum=sum+v;if v>0 then result=k end
    end end
    if sum==0 then return nil,"WAIT" end
    if sum~=1 then return nil,"MISMATCH" end
    return result,"CONFIRMED"
end
