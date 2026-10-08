-- The Journal association panel is refreshed by the scanner every 0.75 s
-- while the server Echo Journal is open. Each refresh used to resolve every
-- Wishlist candidate (the most expensive adapter read of the refresh,
-- about 0.65 ms offline) although only the picker shows them. Now the
-- candidates are read when the picker opens. The refresh still re-projects
-- the server slots and resolves the assignment on every tick, so the label
-- and the selector follow every change exactly as before, and the picker
-- lists the candidates as they are when it opens. The scanner frame ticks
-- in the harness, so each window below is real scanner time; adapter reads
-- are counted by a call hook over the whole window. Real Journal
-- reproduction (assignment_journal_picker), real adapter, real store.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
local realPrint=print;print=function() end
dofile('tests/prototype/assignment_journal_picker.lua')
print=realPrint;dofile=originalDofile
assert(H)
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local A,J=Nexus.GameAdapter,Nexus.JournalTab
-- Entries into the adapter reads of the refresh and the picker, by function
-- definition line (a call hook, robust to anything rebinding table fields).
local names={}
for _,name in ipairs({'GetWishlistCandidates','GetLoadoutWishlist','GetFirstRunWishlist'}) do
 names[debug.getinfo(A[name],'S').linedefined]=name
end
local counts={}
local function Hook()
 local info=debug.getinfo(2,'S')
 if info and tostring(info.source):find('GameAdapter',1,true) and names[info.linedefined] then
  counts[names[info.linedefined]]=(counts[names[info.linedefined]] or 0)+1
 end
end
local function Candidates() return counts.GetWishlistCandidates or 0 end
local function Assignment() return (counts.GetLoadoutWishlist or 0)+(counts.GetFirstRunWishlist or 0) end
-- A window of scanner time (frames of 0.05 s) with the hook active. The
-- optional change runs first, inside the window. The explicit refresh is
-- what the scanner itself does.
local function Window(frames,change)
 counts={}
 debug.sethook(Hook,'c')
 if change then change() end
 J.RefreshAssociations()
 for _=1,frames do H.Advance(.05,.05) end
 debug.sethook()
 return Candidates(),Assignment()
end
local function Label() return NexusLoadoutAssociationPanel.label:GetText() end
local function Selector() return NexusActiveWishlistSelector.text:GetText() end
-- Opens the picker with the hook active, collects the visible row labels,
-- closes it; returns the labels and the candidate reads the opening cost.
local function Picker()
 counts={}
 debug.sethook(Hook,'c')
 NexusActiveWishlistSelector:Click()
 debug.sethook()
 local reads=Candidates()
 check(NexusWishlistOnlyPicker:IsShown(),'fixture: the selector opens its picker')
 local labels={}
 for _,row in ipairs(NexusWishlistOnlyPicker.children) do
  if row.nameButton and row:IsVisible() then labels[#labels+1]=row.nameButton.text:GetText() end
 end
 NexusActiveWishlistSelector:Click()
 check(not NexusWishlistOnlyPicker:IsShown(),'fixture: the selector closes its picker')
 return table.concat(labels,'|'),reads
end

-- The Wishlist editor re-hides the server journal while it is shown.
NexusEditorFrame:Hide();for _=1,20 do H.Advance(.05,.05) end
local journal=ProjectEbonholdEchoJournal
journal:Show();for _=1,4 do H.Advance(.05,.05) end
check(journal:IsShown(),'fixture: the journal is shown')

-- 1. Ten seconds with nothing changed: the candidates are never walked; the
-- assignment is resolved once per refresh (the explicit one plus the
-- scanner's ticks), never more.
local candidates,assignment=Window(200)
check(NexusLoadoutAssociationPanel:IsShown() and Selector():find('Plan B',1,true),'fixture: the panel shows the assignment: '..Selector())
check(candidates==0,'a quiet open Journal never walks the Wishlist candidates: '..candidates)
check(assignment>=1 and assignment<=200/15+2,'the assignment is resolved once per refresh: '..assignment)

-- 2. Opening the picker reads the candidates once and lists the server
-- Wishlists.
local listed,reads=Picker()
check(reads==1,'opening the picker reads the candidates once: '..reads)
check(listed:find('Plan A',1,true)~=nil and listed:find('Plan B',1,true)~=nil,'the picker lists the server Wishlists: '..listed)

-- 3. An announced Wishlist slot rename (OnDataChanged): the refresh costs
-- no candidate walk, the recorded assignment keeps its name, and the
-- picker opened afterwards offers the new name.
local active=A.Slots().activeSlot
candidates=Window(40,function() H.perks.serverBuildSlots[102].name='Plan B renamed';H.Notify();A.Poll() end)
check(candidates==0,'an announced slot rename costs no candidate walk in the refresh: '..candidates)
check(Selector():find('Plan B',1,true)~=nil,'the recorded assignment keeps its name: '..Selector())
listed=Picker()
check(listed:find('Plan B renamed',1,true)~=nil,'the picker opened afterwards offers the renamed Wishlist: '..listed)

-- 4. The active Saved Build renamed in place with no client notice: the
-- label follows at the very next refresh (no frame advanced).
local activeName=A.Slots().bySlot[active].name
local renamedKey
for key,slot in pairs(H.perks.serverBuildSlots) do if slot.name==activeName then renamedKey=key end end
check(renamedKey~=nil,'fixture: the active Saved Build is a server slot: '..tostring(activeName))
H.perks.serverBuildSlots[renamedKey].name='Renamed Build'
counts={};debug.sethook(Hook,'c');J.RefreshAssociations();debug.sethook()
check(Candidates()==0,'the refresh after an unannounced rename walks no candidates')
check(Label():find('Renamed Build',1,true)~=nil,'the label shows the renamed Saved Build: '..Label())

-- 5. An assignment change through the adapter: the selector follows, with
-- no candidate walk in the refresh.
check(A.ClearLoadoutWishlist(active)==true,'fixture: the assignment is cleared')
candidates=Window(40)
check(candidates==0 and Selector():find('Select wishlist',1,true)~=nil,'clearing the assignment is shown without a candidate walk: '..Selector())
local wishes=A.GetWishlistCandidates()
check(#wishes>0 and A.SetLoadoutWishlist(active,wishes[1].slot,wishes[1])==true,'fixture: a Wishlist is assigned again')
candidates=Window(40)
check(candidates==0 and not Selector():find('Select wishlist',1,true),'re-assigning is shown without a candidate walk: '..Selector())

-- 6. Hidden journal: the panel hides and nothing is read; shown again: the
-- refresh resumes (slots and assignment), still without a candidate walk.
journal:Hide()
candidates,assignment=Window(40)
check(candidates==0 and assignment==0 and not NexusLoadoutAssociationPanel:IsShown(),'a hidden journal hides the panel without adapter reads')
journal:Show()
candidates,assignment=Window(40)
check(candidates==0 and assignment>=1 and NexusLoadoutAssociationPanel:IsShown(),'a shown journal refreshes the panel without a candidate walk: '..candidates..'/'..assignment)

-- 7. The host rebuilt the journal (a new frame object under the same global
-- name): the panel follows to the new frame.
local rebuilt=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
rebuilt:Show()
candidates=Window(40)
check(candidates==0 and NexusLoadoutAssociationPanel:GetParent()==rebuilt,'the panel is attached to the rebuilt journal frame without a candidate walk')

-- 8. A resize of the host: the panel is anchored to it; no candidate walk.
rebuilt:SetSize(900,700)
candidates=Window(40)
check(candidates==0,'a host resize walks no candidates')
print('PASS journal_association_lazy_candidates checks='..checks)
