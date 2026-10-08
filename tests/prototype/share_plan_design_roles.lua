-- A Wishlist made in the Wishlist Editor keeps its permanent targets beside its
-- server copy: the server Wishlist holds only the ordinary rows. Native check of
-- test.9028-4ef2b90 (2026-09-21): a 1 ordinary + 1 permanent editor Wishlist was
-- shared as 1 ordinary copy; the permanent Echo was dropped without a word,
-- because the saved plan design was read only above 79 copies.
-- Real TOC, adapter, editor Create path, controller, renderer, catalog and Sync.
-- The server copy of the new Wishlist is the uploaded rows only (no quality, no
-- permanent row), as the server returns it. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
local H,C,puts,shares,printed
local function Boot(slots)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPostPopup=nil
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80
 NexusDB=T.Profile(0,0)
 H.perks.serverActiveSlot=0
 H.perks.serverBuildSlots=slots or {}
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 C=Nexus.BuildCatalog
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
 puts,shares,printed={},{},{}
 local put=C.Put
 C.Put=function(record,...)puts[#puts+1]=H.Clone(record);return put(record,...)end
 -- A record committed inside a receiver batch is recorded exactly like a
 -- single put, so the counts below keep their meaning on both routes.
 local putBatch=C.PutBatch
 if type(putBatch)=='function' then
  C.PutBatch=function(requests,...)
   for _,request in ipairs(requests or {})do
    local record=type(request)=='table' and request.record or nil
    if record then puts[#puts+1]=H.Clone(record) end
   end
   return putBatch(requests,...)
  end
 end
 local broadcast=Nexus.Sync.BroadcastBuildSummary
 Nexus.Sync.BroadcastBuildSummary=function(record,...)shares[#shares+1]=H.Clone(record);return broadcast(record,...)end
end
local function Plan(ordinary,permanent)
 local e={}
 for i=1,ordinary do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 for i=1,permanent do local id=200081+i;e[#e+1]={spellId=id,quality=id%4,stacks=1,locked=true}end
 return e
end
-- The real editor: import the plan code, Create Wishlist, confirm. Returns the
-- rows that the editor uploaded to the server.
local function Create(name,ordinary,permanent)
 local W=Nexus.WishlistEditor
 local code=assert(Nexus.Codec.EncodeEBH1(Plan(ordinary,permanent),'MAGE',name))
 W.ImportEBH1String(code,name)
 local d=W.DebugDraftState()
 assert(d.pending==ordinary and d.pendingLock==permanent,name..': editor draft has '..ordinary..' ordinary / '..permanent..' locked')
 local before=#H.actions
 local b
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist' then b=f;break end end
 assert(b,'the real Create Wishlist button');b:Click();H.AcceptPopup()
 assert(not W.IsApplyPending(),name..': save completes')
 local upload
 for i=before+1,#H.actions do if H.actions[i][1]=='upload' then upload=H.actions[i] end end
 assert(upload and upload[3]==name,name..': one upload')
 H.now=H.now+3.1
 return upload[4]
end
-- The server copy of the uploaded Wishlist: IDs and copies only, every row false.
local function Mirror(ids)
 local rows={}
 for i,e in ipairs(ids)do
  local id=type(e)=='table' and (e.spellId or e.id or e[1]) or e
  local stacks=type(e)=='table' and (e.stacks or e.count or e[2]) or 1
  rows[i]={spellId=tonumber(id),stacks=tonumber(stacks) or 1,locked=false}
 end
 return rows
end
local function Publish(slot,name,rows)
 H.perks.serverBuildSlots[slot]={name=name,verified=false,echoes=rows}
 H.Notify();Nexus.GameAdapter.Poll();H.Advance(.5)
end
local function MenuButton(text)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() then
   for _,r in ipairs({f:GetRegions()})do
    if r.GetText and type(r:GetText())=='string' and r:GetText():find(text,1,true) then return f,r:GetText() end
   end
  end
 end
end
local function Open(sourceName)
 -- ShowPostBuild toggles; a refusal leaves the form open.
 if NexusPostPopup and NexusPostPopup:IsShown() then Nexus.CommunityBuilds.ShowPostBuild() end
 Nexus.CommunityBuilds.ShowPostBuild()
 local p=assert(NexusPostPopup);assert(p:IsVisible(),'actual Share form opens')
 p._postWishlistBtn:Click()
 local button,label=MenuButton('] '..sourceName..'  ')
 assert(button,'source menu lists '..sourceName);button:Click()
 return p,label
end
local function Click(p,title)
 p._postTitleBox:_NexusSetRawText(title)
 p._postDescBox:_NexusSetRawText('Synthetic plan-design role regression')
 local real=print;print=function(...)local t={};for i=1,select('#',...)do t[#t+1]=tostring((select(i,...)))end;printed[#printed+1]=table.concat(t,' ')end
 p._postGoBtn:Click();print=real
end
local function PreviewRows(p)
 local out={}
 for _,row in ipairs(p._previewRows)do if row:IsShown() then out[#out+1]=row.text:GetText() end end
 return out
end
local function Copies(rows)local n=0;for _,e in ipairs(rows or {})do n=n+(e.stacks or 1)end;return n end
local function Population(rows,withQuality)
 local totals,parts={},{}
 for _,e in ipairs(rows or {})do
  local k=tostring(e.spellId)..(withQuality and (':'..tostring(e.quality)) or '')
  totals[k]=(totals[k] or 0)+(e.stacks or 1)
 end
 for k,n in pairs(totals)do parts[#parts+1]=k..':'..n end
 table.sort(parts);return table.concat(parts,',')
end
local function Expected(ordinary,permanent)
 local o,l={},{}
 for _,e in ipairs(Plan(ordinary,permanent))do if e.locked then l[#l+1]=e else o[#o+1]=e end end
 return o,l
end
local function Accepted(name,ordinary,permanent)
 local status=assert(Nexus.CommunityBuilds.ShareStatus(),name..': the Share was accepted: '..tostring(printed[#printed]))
 T.Until(H,function()local s=Nexus.CommunityBuilds.ShareStatus(status.id);return s and s.localPending==false end,30000)
 local final=Nexus.CommunityBuilds.ShareStatus(status.id)
 assert(final.localSaved,name..': saved locally: '..tostring(final.queueReason))
 local record=assert(C.Get(status.id),name..': stored record')
 local o,l=Expected(ordinary,permanent)
 assert(Copies(record.echoes)==ordinary and Copies(record.lockedEchoes)==permanent,
  name..': stored role copies '..Copies(record.echoes)..' / '..Copies(record.lockedEchoes))
 assert(Population(record.echoes)==Population(o),name..': exact ordinary IDs and copies')
 for _,e in ipairs(record.echoes)do assert(e.locked==nil or e.locked==false,name..': no locked row in the ordinary list')end
 assert(Population(record.lockedEchoes,true)==Population(l,true),name..': exact locked ID, quality and copies')
 for _,e in ipairs(record.lockedEchoes or {})do assert(e.locked==true,name..': locked rows stay marked')end
 assert(#puts==1 and #shares==1 and shares[1].id==status.id,name..': one local write, one transport hand-off')
 assert(Copies(shares[1].lockedEchoes)==permanent and Population(shares[1].lockedEchoes,true)==Population(l,true),name..': transport receives the locked rows')
 assert(final.ordinaryCopies==ordinary and final.permanentCopies==permanent,name..': status records the real role counts')
 return record,final
end
local function Refused(name,p,...)
 assert(Nexus.CommunityBuilds.ShareStatus()==nil,name..': nothing was accepted or retained')
 assert(#puts==0 and #shares==0,name..': no catalog write and no send')
 assert(p:IsShown(),name..': the form stays')
 local line=assert(printed[#printed],name..': the refusal is shown')
 for _,text in ipairs({...})do assert(line:find(text,1,true),name..': message states "'..text..'": '..line)end
 for i=1,40 do H.Advance(.05,.05)end
 assert(Nexus.CommunityBuilds.ShareStatus()==nil and #puts==0,name..': nothing starts later')
 return line
end

-- 1. The native case: 1 ordinary + 1 permanent, made in the editor, shared from its server slot.
Boot()
local uploaded=Create('PLAN-1-1',1,1)
local mirror=Mirror(uploaded)
assert(#mirror==1 and mirror[1].spellId==200001,'fixture: the server copy holds only the ordinary row (as observed natively)')
Publish(102,'PLAN-1-1',mirror)
local assignment=Nexus.Store.State().firstRunWishlist
assert(type(assignment)=='table' and assignment.name=='PLAN-1-1','fixture: the editor assigned the plan (first-run path, no active Saved Build)')
local p,label=Open('PLAN-1-1')
assert(label:find('1 / 79 + 1 / 6 locked',1,true),'source menu states both role counts: '..label)
assert(p._previewSummary:GetText():find('Shares 1 ordinary + 1 locked Echo copies',1,true),'preview states the role counts: '..tostring(p._previewSummary:GetText()))
local rows=PreviewRows(p)
assert(#rows==2 and not rows[1]:find('(locked)',1,true) and rows[2]:find('(locked)',1,true),'preview lists the ordinary and the locked row: '..table.concat(rows,' | '))
Click(p,'PLAN-1-1')
local record,final=Accepted('1 ordinary + 1 locked',1,1)
assert(printed[#printed]:find('Roles: 1 ordinary + 1 locked Echo copies.',1,true),'chat line states the role counts: '..tostring(printed[#printed]))
T.Until(H,function()local s=Nexus.CommunityBuilds.ShareStatus(final.id);return s and (s.sendCompleted or s.queueAdmitted) end,30000)
Nexus.CommunityBuilds.ShowPostBuild();Nexus.CommunityBuilds.ShowPostBuild()
p=assert(NexusPostPopup)
assert(p._shareStatus:GetText():find('Roles: 1 ordinary + 1 locked Echo copies.',1,true),'form status line states the role counts: '..tostring(p._shareStatus:GetText()))
assert(T.Equal(H.perks.serverBuildSlots[102].echoes,mirror),'the server copy is unchanged')
print('PASS 1+1 editor Wishlist: locked row shared, counts disclosed in menu, preview, chat and form')

-- 2. 79 ordinary + 6 permanent through the same path.
Boot()
uploaded=Create('PLAN-79-6',79,6)
mirror=Mirror(uploaded);assert(Copies(mirror)==79,'fixture: the server copy holds the 79 ordinary copies only')
Publish(102,'PLAN-79-6',mirror)
p,label=Open('PLAN-79-6')
assert(label:find('79 / 79 + 6 / 6 locked',1,true),label)
Click(p,'PLAN-79-6')
Accepted('79 ordinary + 6 locked',79,6)
print('PASS 79+6 editor Wishlist: 85 copies shared with separate roles, limits unchanged')

-- 3. No saved design: a plain server Wishlist is shared as before (ordinary only).
Boot({[102]={name='PLAIN-1',verified=false,echoes={{spellId=200001,stacks=1,locked=false}}}})
p,label=Open('PLAIN-1')
local counts=label:sub(label:find('1 / 79',1,true) or 1)
assert(label:find('1 / 79',1,true) and not counts:find('locked',1,true)
 and not counts:find('/ 6',1,true),'a source with no locked copies states no locked role: '..label)
Click(p,'PLAIN-1')
local plain=Accepted('no saved design',1,0)
assert(plain.lockedEchoes==nil or #plain.lockedEchoes==0,'no locked row is invented')
assert(printed[#printed]:find('Roles: 1 ordinary + 0 locked Echo copies.',1,true),tostring(printed[#printed]))
print('PASS no saved design: unchanged ordinary-only Share, counts disclosed')

-- 4. Mismatch A: the form keeps its selection, then the server copy changes. The
-- saved design no longer belongs to one server Wishlist; the stale selection is refused.
Boot()
uploaded=Create('PLAN-STALE',1,1)
Publish(102,'PLAN-STALE',Mirror(uploaded))
p=Open('PLAN-STALE')
Publish(102,'PLAN-STALE',{{spellId=200001,stacks=1,locked=false},{spellId=200002,stacks=1,locked=false}})
Click(p,'PLAN-STALE')
Refused('stale selection',p,'cannot tell which server Wishlist','Nothing was shared')
print('PASS mismatch: a stale selection is refused, the locked row is not dropped')

-- 5. Mismatch B: two server Wishlists with the same name and rows. The design
-- cannot be bound to one of them; both are refused rather than shared without it.
Boot()
uploaded=Create('PLAN-TWIN',1,1)
H.perks.serverBuildSlots[101]={name='PLAN-TWIN',verified=false,echoes=Mirror(uploaded)}
Publish(102,'PLAN-TWIN',Mirror(uploaded))
p=Open('PLAN-TWIN')
Click(p,'PLAN-TWIN')
Refused('ambiguous server copy',p,'cannot tell which server Wishlist','Open the Wishlist in the Wishlist Editor and save it again')
print('PASS mismatch: an ambiguous server copy is refused')

-- 6. Conflict: the source itself states a different permanent row than its saved design.
Boot()
uploaded=Create('PLAN-CONFLICT',1,1)
Publish(102,'PLAN-CONFLICT',Mirror(uploaded))
-- The same shape as the source menu entry for slot 102, plus a separate permanent list.
local candidate={slot=102,name='PLAN-CONFLICT',sourceKind='Wishlist',echoes=Mirror(uploaded)}
candidate.lockedEchoes={{spellId=200089,quality=1,stacks=1}}
local ok,message=Nexus.CommunityBuilds.PostCurrentWishlist('PLAN-CONFLICT','Synthetic',candidate,'MAGE')
assert(ok==false and tostring(message):find('differ from its saved locked-target plan',1,true) and #puts==0 and Nexus.CommunityBuilds.ShareStatus()==nil,
 'conflicting role statements are refused before acceptance: '..tostring(message))
candidate.lockedEchoes={{spellId=200082,quality=2,stacks=1}}
ok,message=Nexus.CommunityBuilds.PostCurrentWishlist('PLAN-AGREE','Synthetic',candidate,'MAGE')
assert(ok,'the same locked row stated twice is counted once: '..tostring(message))
Accepted('agreeing statements',1,1)
print('PASS conflict: a different locked statement is refused; the same one is counted once')
assert(#H.actions==0 or (function()for _,a in ipairs(H.actions)do if a[1]~='upload' then return false end end;return true end)(),'no game action other than the editor uploads')

-- 7. Review F1 (P1): an editor plan WITHOUT permanent targets saves an empty design.
-- It is shared exactly as before: ordinary only, no refusal.
Boot()
uploaded=Create('PLAN-1-0',1,0)
Publish(102,'PLAN-1-0',Mirror(uploaded))
p,label=Open('PLAN-1-0')
local counts=label:sub(label:find('1 / 79',1,true) or 1)
assert(label:find('1 / 79',1,true) and not counts:find('locked',1,true)
 and not counts:find('/ 6',1,true),'a source with no locked copies states no locked role: '..label)
Click(p,'PLAN-1-0')
Accepted('editor plan without locked targets',1,0)
print('PASS 1+0 editor Wishlist: the empty saved design is not a refusal')

-- 8. Review F3: a design that no longer binds to one server Wishlist is refused
-- when the source has its name or its rows, instead of being dropped.
Boot()
uploaded=Create('PLAN-RENAMED',1,1)
Publish(102,'PLAN-RENAMED-ON-SERVER',Mirror(uploaded))
p=Open('PLAN-RENAMED-ON-SERVER')
Click(p,'PLAN-RENAMED')
Refused('renamed server copy',p,'renamed, changed or copied','Nothing was shared')
Boot()
uploaded=Create('PLAN-CHANGED',1,1)
Publish(102,'PLAN-CHANGED',{{spellId=200001,stacks=1,locked=false},{spellId=200002,stacks=1,locked=false}})
p=Open('PLAN-CHANGED')
Click(p,'PLAN-CHANGED')
Refused('changed server copy, selected again',p,'renamed, changed or copied','Nothing was shared')
-- A different Wishlist (other name, other rows) is not affected by that design.
Publish(103,'OTHER-LIST',{{spellId=200010,stacks=2,locked=false}})
p=Open('OTHER-LIST');printed={}
Click(p,'OTHER-LIST')
do
 local status=assert(Nexus.CommunityBuilds.ShareStatus(),'unrelated Wishlist: accepted: '..tostring(printed[#printed]))
 T.Until(H,function()local s=Nexus.CommunityBuilds.ShareStatus(status.id);return s and s.localPending==false end,30000)
 local record=assert(C.Get(status.id),'unrelated Wishlist: stored')
 assert(Population(record.echoes)=='200010:2' and Copies(record.lockedEchoes)==0,'unrelated Wishlist: shared exactly as its source, ordinary only')
end
print('PASS unbound design: refused for its own renamed or changed copy; unrelated Wishlists unchanged')

-- 9. A saved design that cannot be read is refused, not treated as no design.
Boot()
uploaded=Create('PLAN-UNREADABLE',1,1)
Publish(102,'PLAN-UNREADABLE',Mirror(uploaded))
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.firstRunWishlist.designRows={{spellId='not-a-number',stacks=1}}
end),'fixture: damaged saved design')
p=Open('PLAN-UNREADABLE')
Click(p,'PLAN-UNREADABLE')
Refused('unreadable saved design',p,'cannot be read','Nothing was shared')
print('PASS unreadable saved design is refused')

-- 10. Two saved assignments bound to the same server Wishlist with different designs.
Boot()
uploaded=Create('PLAN-DISAGREE',1,1)
Publish(102,'PLAN-DISAGREE',Mirror(uploaded))
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 local copy=H.Clone(s.firstRunWishlist);copy.assignmentId=tostring(copy.assignmentId)..'-second'
 copy.designRows={{spellId=200089,quality=1,stacks=1}}
 s.loadoutWishlists=s.loadoutWishlists or {};s.loadoutWishlists[1]=copy
end),'fixture: second assignment with another design')
p=Open('PLAN-DISAGREE')
Click(p,'PLAN-DISAGREE')
Refused('two designs that disagree',p,'two saved locked-target plans that do not agree','Nothing was shared')
print('PASS disagreeing saved designs are refused')

-- 12. Review N1 (P1): an EMPTY design next to a non-empty one for the same slot is
-- also a disagreement (the permanent target was removed for one loadout only).
Boot()
uploaded=Create('PLAN-EMPTY-VS-ONE',1,1)
Publish(102,'PLAN-EMPTY-VS-ONE',Mirror(uploaded))
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 local copy=H.Clone(s.firstRunWishlist);copy.assignmentId=tostring(copy.assignmentId)..'-second'
 copy.designRows={}
 s.loadoutWishlists=s.loadoutWishlists or {};s.loadoutWishlists[1]=copy
end),'fixture: second assignment of the same plan without its locked target')
p=Open('PLAN-EMPTY-VS-ONE')
Click(p,'PLAN-EMPTY-VS-ONE')
Refused('empty design beside a non-empty design',p,'two saved locked-target plans that do not agree','save the same locked targets','Nothing was shared')
print('PASS an empty and a non-empty design for one slot are refused')

-- 13. Review N2: a saved plan listed without a server Wishlist (its server copy is
-- gone) is its own source; its design supplies the permanent rows.
Boot()
Create('PLAN-NO-SERVER-COPY',1,1)
H.Notify();Nexus.GameAdapter.Poll();H.Advance(.5)
p,label=Open('PLAN-NO-SERVER-COPY')
assert(label:find('1 / 79 + 1 / 6 locked',1,true),'slot-less plan entry states both role counts: '..label)
Click(p,'PLAN-NO-SERVER-COPY')
Accepted('saved plan without a server copy',1,1)
print('PASS saved plan without a server copy shares its locked row')

-- 14. Review M1: the same slot-less plan with a design that cannot be read is refused,
-- not shared with 0 permanent copies.
Boot()
Create('PLAN-NO-COPY-DAMAGED',1,1)
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.firstRunWishlist.designRows={{spellId='not-a-number',stacks=1}}
end),'fixture: damaged saved design')
H.Notify();Nexus.GameAdapter.Poll();H.Advance(.5)
p=Open('PLAN-NO-COPY-DAMAGED')
Click(p,'PLAN-NO-COPY-DAMAGED')
Refused('slot-less plan with an unreadable design',p,'cannot be read','save its locked targets again','Nothing was shared')
print('PASS slot-less plan with an unreadable design is refused')

-- 11. Review F2: the >79 path (84 all-false rows, roles confirmed in the adapter).
-- The preview lists 78 ordinary and 6 permanent rows, none twice.
local rows84={};for i=1,84 do rows84[i]={spellId=200000+i,stacks=1,locked=false}end
Boot({[102]={name='PLAN-84',verified=false,echoes=rows84}})
local A=Nexus.GameAdapter;candidate=nil
for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
assert(candidate,'fixture: the adapter lists the 84-copy mirror')
local chosen={};for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
assert(A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed'),'fixture: real role confirmation')
p,label=Open('PLAN-84')
assert(label:find('78 / 79 + 6 / 6 locked',1,true),label)
assert(p._previewSummary:GetText():find('Shares 78 ordinary + 6 locked Echo copies',1,true),tostring(p._previewSummary:GetText()))
local shown=PreviewRows(p);local marked=0
for _,text in ipairs(shown)do if text:find('(locked)',1,true) then marked=marked+1 end end
assert(#shown==84 and marked==6,'preview lists each copy once: '..#shown..' rows, '..marked..' locked')
print('PASS >79 preview: 78 + 6 rows, none twice')
print('PASS share_plan_design_roles')
