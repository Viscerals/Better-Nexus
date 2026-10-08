-- Shared helpers of the ten-group repair batch regressions (batch_*.lua).
-- Not a test itself: the name ends in _support, so tools/ci_check.py does not
-- list it. Loading it reads and changes nothing; every helper acts only on what
-- a test passes in, and a global it replaces is restored before it returns.
-- Synthetic data only; no native Lua is ever loaded.
--
-- Output convention (the reporting checker of view_regression_support.lua):
--   SETUP  the fixture reached its state; a SETUP failure is NOT red evidence.
--   EXPECT healthy behaviour that does not hold at the 8c baseline (the defect).
--   GUARD  behaviour that already holds at 8c and must keep holding.
-- A scenario that raises is reported as RAISED and the later scenarios run.
local V=dofile('tests/prototype/view_regression_support.lua')
local B={V=V,printable=V.printable}

function B.Checker(name) return V.Checker(name) end

-- Advance the harness in 0.05 s steps until fn() holds; the step count, or nil
-- when the bound is reached first.
function B.Until(H,fn,limit)
 for i=1,limit or 2000 do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return fn() and (limit or 2000) or nil
end

-- Every line the global print receives while fn runs (arguments joined by a
-- space). The lines still reach the real print. Returns lines, ok, err.
function B.CapturePrint(fn,...)
 local lines,real={},print
 print=function(...)
  local parts={}
  for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
  lines[#lines+1]=table.concat(parts,' ')
  return real(...)
 end
 local ok,err=pcall(fn,...)
 print=real
 return lines,ok,err
end

-- Harness action rows of one kind ('lock', 'unlock', 'take', 'orb-spend' ...).
function B.Count(H,kind)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]==kind then n=n+1 end end
 return n
end

-- Every consequential harness action row: a game write of any kind.
function B.Mutations(H)
 return #H.actions
end

-- Text without the client's colour codes.
function B.Plain(text) return V.Plain(text) end

-- Every field of a value, nested tables included, in a stable order (a
-- byte-identity witness for stored records). Depth is bounded.
function B.Dump(v,depth)
 depth=depth or 0
 if type(v)~='table' then return type(v)..':'..V.printable(v) end
 if depth>8 then return '<deep>' end
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=V.printable(k)..'='..B.Dump(v[k],depth+1) end
 return '{'..table.concat(out,',')..'}'
end

return B
