-- #63: the Wishlist editor's two lists (catalog and Selected Echoes) never
-- scroll past their last full window. ClampScroll and ClampPick corrected
-- the offset only when it was at or beyond the row count, so a list that
-- shrank (a search, a filter, a removal) or a mouse wheel that moved 3 rows
-- at a time left a partly empty window. Both now clamp to
-- max(0, count - visible) whenever the offset is above it.
--
-- The real controller with an injected state store (the wishlist.lua shape).
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H=dofile('tests/prototype/harness.lua');H.Boot()
local A=Nexus.GameAdapter
local backing={};local settings={}
local store={State=function() return backing end,Settings=function() return settings end}
local adapter={};for k,v in pairs(A) do adapter[k]=v end
A.Init({},store)
local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,
 accountRoot=function()return {}end,notify=function() end})
c.Initialize(adapter)

for _,pair in ipairs({{'catalog list',c.SetScrollOffset,c.ClampScroll,c.AdjustScroll},
                      {'Selected Echoes',c.SetPickOffset,c.ClampPick,c.AdjustPick}}) do
 local name,Set,Clamp,Adjust=pair[1],pair[2],pair[3],pair[4]
 -- The reported case: 20 rows, 10 visible, offset 15.
 Set(15)
 check(Clamp(20,10)==10,name..': offset 15 of 20 rows with 10 visible clamps to 10: '..Clamp(20,10))
 -- An offset inside the last full window is kept.
 Set(7)
 check(Clamp(20,10)==7,name..': an offset with a full window is kept: '..Clamp(20,10))
 -- The list shrinks under a scrolled view (a search).
 Set(10)
 check(Clamp(12,10)==2,name..': a shrunk list clamps to its last full window: '..Clamp(12,10))
 -- Fewer rows than the window: the top.
 Set(3)
 check(Clamp(4,10)==0,name..': a list shorter than the window shows from the top: '..Clamp(4,10))
 -- The wheel moves 3 rows at a time; scrolling down many times stops at
 -- the last full window.
 Set(0)
 for _=1,20 do Adjust(-1);Clamp(20,10) end
 check(Clamp(20,10)==10,name..': the wheel stops at the last full window: '..Clamp(20,10))
 -- An empty list.
 Set(5)
 check(Clamp(0,10)==0,name..': an empty list is at the top: '..Clamp(0,10))
end

print('PASS wishlist_scroll_clamp checks='..checks)
