-- A Share keeps the exact Echo roles of its source. test.9027 copied only
-- spellId/quality/stacks into the ordinary list: 78 ordinary + 6 permanent
-- became 84 ordinary and the real catalog refused it SEMANTIC_ENVELOPE after a
-- prolonged wait; 41 + 6 was stored as 47 ordinary with the roles lost.
-- Real TOC, adapter, controller, renderer, catalog and Sync. The source is the
-- synthetic server slot mirror, chosen through the real Share form and its
-- source menu unless a case says otherwise. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
local H,C,puts,shares,printed
local function Rows(ordinary,locked,explicit,first)
 local rows={}
 for i=1,ordinary+locked do
  local permanent=i>ordinary
  rows[i]={spellId=(first or 200000)+i,quality=i%4,stacks=1}
  if permanent then rows[i].locked=true elseif explicit then rows[i].locked=false end
 end
 return rows
end
local function Boot(slots,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPostPopup=nil
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80
 NexusDB=T.Profile(0,0)
 H.perks.serverActiveSlot=active or 0
 H.perks.serverBuildSlots=slots
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 C=Nexus.BuildCatalog
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
 puts,shares,printed={},{},{}
 local put=C.Put
 C.Put=function(record,...)puts[#puts+1]=H.Clone(record);return put(record,...)end
 local broadcast=Nexus.Sync.BroadcastBuildSummary
 Nexus.Sync.BroadcastBuildSummary=function(record,...)shares[#shares+1]=H.Clone(record);return broadcast(record,...)end
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
-- The real form. sourceName selects through the real source menu.
local function Share(title,sourceName)
 Nexus.CommunityBuilds.ShowPostBuild()
 local p=assert(NexusPostPopup);assert(p:IsVisible(),'actual Share form opens')
 local label
 if sourceName then
  p._postWishlistBtn:Click()
  local button;button,label=MenuButton(sourceName)
  assert(button,'source menu lists '..sourceName);button:Click()
 end
 p._postTitleBox:_NexusSetRawText(title)
 p._postDescBox:_NexusSetRawText('Synthetic role regression')
 assert(p._postGoBtn:IsVisible() and p._postGoBtn:IsEnabled(),'actual Share button usable')
 local real=print;print=function(...)local t={};for i=1,select('#',...)do t[#t+1]=tostring((select(i,...)))end;printed[#printed+1]=table.concat(t,' ')end
 p._postGoBtn:Click();print=real
 return p,label
end
local function Settle(id)
 T.Until(H,function()local s=Nexus.CommunityBuilds.ShareStatus(id);return s and s.localPending==false end,30000)
 return Nexus.CommunityBuilds.ShareStatus(id)
end
local function Population(rows,wantLocked)
 local totals,parts={},{}
 for _,e in ipairs(rows or {})do
  if wantLocked==nil or (e.locked==true)==wantLocked then
   local k=e.spellId..':'..tostring(e.quality)..':';totals[k]=(totals[k] or 0)+(e.stacks or 1)
  end
 end
 for k,n in pairs(totals)do parts[#parts+1]=k..n end
 table.sort(parts);return table.concat(parts,','),#parts
end
local function Copies(rows)local n=0;for _,e in ipairs(rows or {})do n=n+(e.stacks or 1)end;return n end
-- One accepted Share: exact ordinary and permanent populations in the stored
-- record and in the record handed to transport; nothing in the wrong list.
local function Accepted(name,source,ordinary,locked)
 local status=assert(Nexus.CommunityBuilds.ShareStatus(),name..': the Share was accepted')
 local final=Settle(status.id)
 assert(final.localSaved and final.queueReason~='SEMANTIC_ENVELOPE',name..': saved locally, never refused for its roles: '..tostring(final.queueReason))
 local record=assert(C.Get(status.id),name..': stored record')
 assert(Copies(record.echoes)==ordinary and Copies(record.lockedEchoes)==locked,name..': exact role copy counts '..Copies(record.echoes)..'/'..Copies(record.lockedEchoes))
 assert(Population(record.echoes)==Population(source,false),name..': exact ordinary ID, quality and copies')
 assert(Population(record.lockedEchoes)==Population(source,true),name..': exact permanent ID, quality and copies')
 for _,e in ipairs(record.echoes)do assert(e.locked==nil or e.locked==false,name..': no permanent row in the ordinary identity list')end
 for _,e in ipairs(record.lockedEchoes or {})do assert(e.locked==true,name..': permanent rows stay marked')end
 assert(#puts==1 and #shares==1 and shares[1].id==status.id,name..': one local write, one transport hand-off')
 assert(Copies(shares[1].echoes)==ordinary and Copies(shares[1].lockedEchoes)==locked,name..': transport receives the same roles')
 assert(final.ordinaryCopies==ordinary and final.permanentCopies==locked,name..': status states the real role counts')
 return record,final
end
-- One refusal before anything is accepted: no pending operation, no write, no
-- send, source and draft kept, real counts in the message.
local function Refused(name,p,before,...)
 assert(Nexus.CommunityBuilds.ShareStatus()==nil,name..': nothing was accepted or retained')
 assert(#puts==0 and #shares==0,name..': no catalog write and no send')
 assert(p:IsShown() and p._postTitleBox:_NexusRawText()~='',name..': the form and its draft stay')
 assert(T.Equal(before,H.perks.serverBuildSlots),name..': source unchanged')
 local line=assert(printed[#printed],name..': the refusal is shown')
 for _,text in ipairs({...})do assert(line:find(text,1,true),name..': message states "'..text..'": '..line)end
 assert(not line:find('SEMANTIC_ENVELOPE',1,true),name..': raw code is not the user message')
 for i=1,40 do H.Advance(.05,.05)end
 assert(Nexus.CommunityBuilds.ShareStatus()==nil and #puts==0,name..': nothing starts later')
 return line
end
local function Slot(name,rows)return {[102]={name=name,verified=false,echoes=rows}}end

-- 1. The reported synthetic populations, flags as in the supplied probe (true / absent).
for _,case in ipairs({{78,6},{79,6},{41,6},{41,0},{1,1}})do
 local name=string.format('ROLES-%d-%d',case[1],case[2])
 local rows=Rows(case[1],case[2])
 Boot(Slot(name,rows))
 local before=H.Clone(H.perks.serverBuildSlots)
 local _,label=Share(name,name)
 Accepted(name,rows,case[1],case[2])
 if case[2]>0 then assert(label:find(case[1]..' / 79 + '..case[2]..' / 6 permanent',1,true),'source menu states both role counts: '..label)
 else assert(label:find(case[1]..' / 79',1,true) and not label:find('permanent',1,true),label)end
 assert(T.Equal(before,H.perks.serverBuildSlots) and #H.actions==0,name..': source and game state untouched')
 print('PASS '..name..': roles preserved through the real form, catalog and transport hand-off')
end

-- 2. Explicit server booleans (true / false on every row).
local rows=Rows(78,6,true)
assert(rows[1].locked==false and rows[84].locked==true,'fixture: every row carries a boolean')
Boot(Slot('ROLES-BOOLEAN',rows));Share('ROLES-BOOLEAN','ROLES-BOOLEAN');Accepted('boolean flags',rows,78,6)
print('PASS explicit boolean flags')

-- 3. Counted copies. 79 ordinary copies in 21 rows, 6 permanent copies in 2 rows;
-- one ID is both ordinary and permanent and stays two separate role tuples.
rows={}
for i=1,19 do rows[i]={spellId=200100+i,quality=i%4,stacks=4}end
rows[20]={spellId=200120,quality=2,stacks=2};rows[21]={spellId=200121,quality=1,stacks=1}
rows[22]={spellId=200120,quality=2,stacks=3,locked=true};rows[23]={spellId=200130,quality=3,stacks=3,locked=true}
Boot(Slot('ROLES-STACKS',rows));Share('ROLES-STACKS','ROLES-STACKS')
local record=Accepted('counted stacks',rows,79,6)
assert(#record.echoes==21 and #record.lockedEchoes==2,'rows are not expanded, merged across roles or trimmed')
print('PASS counted stacks: 79 ordinary / 6 permanent copies exact')

-- 4. Separate-role source (the Saved Build shape), through the real public entry.
local ordinary,permanent=Rows(78,0),Rows(0,6,nil,200500)
Boot(Slot('UNUSED',Rows(3,0)))
local source={name='ROLES-SEPARATE',echoes=ordinary,lockedEchoes=permanent}
local baseline=H.Clone(source)
local ok=Nexus.CommunityBuilds.PostCurrentWishlist('ROLES-SEPARATE','Synthetic',source,'MAGE')
assert(ok,'separate-role source accepted')
local all={};for _,e in ipairs(ordinary)do all[#all+1]=e end;for _,e in ipairs(permanent)do all[#all+1]=e end
Accepted('separate lists',all,78,6)
assert(T.Equal(source,baseline),'the selected source table is not modified')
print('PASS separate permanent list')

-- 5. Duplicate representation. The same permanent population stated inline and
-- separately is counted once. Two different statements are refused, not summed.
local inline=Rows(78,6)
permanent={};for i=79,84 do permanent[#permanent+1]={spellId=inline[i].spellId,quality=inline[i].quality,stacks=1}end
Boot(Slot('UNUSED',Rows(3,0)))
assert(Nexus.CommunityBuilds.PostCurrentWishlist('ROLES-TWICE','Synthetic',{name='ROLES-TWICE',echoes=inline,lockedEchoes=permanent},'MAGE'))
Accepted('stated twice, same population',inline,78,6)
Boot(Slot('UNUSED',Rows(3,0)))
permanent[1]={spellId=200999,quality=1,stacks=1}
local accepted,message=Nexus.CommunityBuilds.PostCurrentWishlist('ROLES-CONFLICT','Synthetic',{name='ROLES-CONFLICT',echoes=inline,lockedEchoes=permanent},'MAGE')
assert(accepted==false and message:find('two lists that do not agree',1,true) and Nexus.CommunityBuilds.ShareStatus()==nil and #puts==0,'conflicting statements are refused before acceptance: '..tostring(message))
print('PASS duplicate representation: counted once or refused, never summed')

-- 6. Oversized or unresolved sources are refused at the button, with real counts.
rows=Rows(86,0,true)
Boot(Slot('ROLES-86-ORDINARY',rows));local before=H.Clone(H.perks.serverBuildSlots)
assert(Nexus.PeerDebug.Start('')~=false)
local p=Share('ROLES-86-ORDINARY','ROLES-86-ORDINARY')
print('MESSAGE '..Refused('86 explicit ordinary: no role choice can help',p,before,'86 ordinary and 0 permanent','(86 total)','79 ordinary, 6 permanent and 85 total'))
assert(Nexus.PeerDebug.Report():find('SEMANTIC_ENVELOPE ordinary=86 permanent=0 total=86',1,true),'the raw code and counts stay in the diagnostic report')
rows=Rows(80,5)
Boot(Slot('ROLES-80-5',rows));before=H.Clone(H.perks.serverBuildSlots)
p=Share('ROLES-80-5','ROLES-80-5')
Refused('80 ordinary / 5 permanent',p,before,'80 ordinary and 5 permanent')
Boot(Slot('UNUSED',Rows(3,0)));before=H.Clone(H.perks.serverBuildSlots)
accepted,message=Nexus.CommunityBuilds.PostCurrentWishlist('ROLES-7','Synthetic',{name='ROLES-7',echoes=Rows(40,7)},'MAGE')
assert(accepted==false and message:find('40 ordinary and 7 permanent',1,true) and #puts==0,'seven permanent copies are refused, none dropped: '..tostring(message))
-- 84 copies with no role stated anywhere: not 84 ordinary, not a guess.
rows=Rows(84,0)
Boot(Slot('ROLES-UNSTATED',rows));before=H.Clone(H.perks.serverBuildSlots)
p=Share('ROLES-UNSTATED','ROLES-UNSTATED')
local unresolved=Refused('84 unstated',p,before,'has 84 Echo copies','does not say which copies are permanent','at most 79 ordinary copies','Missing evidence:','Wishlist Editor and choose its permanent Echoes','active loadout','Nothing was shared')
print('MESSAGE '..unresolved)
print('PASS refusals: before acceptance, real counts, draft and source kept')

-- 7. The same 84-copy mirror becomes shareable only through the adapter's own
-- confirmed role choice for that exact content; the six chosen rows are permanent.
local A=Nexus.GameAdapter
local candidate
for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
assert(candidate and A.WishlistEvidenceState(candidate)=='evidence-pending','fixture: the adapter also reports roles pending')
local chosen={}
for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
assert(A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed'),'fixture: real role confirmation')
p._postGoBtn:Click()
-- Review F9: the roles come from the adapter; ID, copies AND the quality that the selected source states stay the source's.
local expected={};for i,e in ipairs(rows)do expected[i]={spellId=e.spellId,quality=e.quality,stacks=1,locked=i>78 or nil}end
Accepted('confirmed design roles',expected,78,6)
print('PASS confirmed-design roles resolve the same draft without retyping')

-- 8. Source change. The menu selection decides; a later edit of the chosen
-- source cannot change the approved record.
local first,second=Rows(10,0),Rows(20,4,nil,200300)
Boot({[101]={name='ROLES-FIRST',verified=false,echoes=first},[102]={name='ROLES-SECOND',verified=false,echoes=second}})
Share('ROLES-SECOND','ROLES-SECOND')
local status=assert(Nexus.CommunityBuilds.ShareStatus())
H.perks.serverBuildSlots[102].echoes=Rows(5,0,nil,200700)
record=Accepted('selected second source',second,20,4)
assert(record.title=='ROLES-SECOND','the record is the selected source, not the first listed one')
print('PASS source change: selected source shared exactly; later source edit does not alter it')

-- 9. Review F3: the server mirror that marks EVERY row false (80-85 copies). The adapter
-- does not take that as role evidence. Unconfirmed: refused with the real counts.
-- With the adapter's confirmed role choice for that exact content: shared as 78/6.
rows=Rows(84,0,true)
Boot(Slot('ROLES-ALL-FALSE',rows));before=H.Clone(H.perks.serverBuildSlots)
p=Share('ROLES-ALL-FALSE','ROLES-ALL-FALSE')
-- Review N2 (P2): not a counts-only refusal. It names the missing role information and the supported ways.
local allFalse=Refused('84 explicit false, unconfirmed',p,before,'has 84 Echo copies','marks all of them as ordinary, which is not role information','up to 6 of them must be permanent Echoes','Missing evidence:','Wishlist Editor and choose its permanent Echoes','active loadout')
assert(not allFalse:find('84 ordinary and 0 permanent',1,true),'not the counts-only message')
assert(Nexus.PeerDebug.Start('')~=false);p._postGoBtn:Click()
assert(Nexus.PeerDebug.Report():find('roles unresolved (ordinary=84 permanent=0 total=84)',1,true),'the counts stay in the diagnostic record')
A=Nexus.GameAdapter;candidate=nil
for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
assert(candidate,'fixture: the adapter lists the all-false mirror')
chosen={};for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
assert(A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed'),'fixture: real role confirmation')
p._postGoBtn:Click()
expected={};for i,e in ipairs(rows)do expected[i]={spellId=e.spellId,quality=e.quality,stacks=1,locked=i>78 or nil}end
Accepted('all-false mirror with confirmed roles',expected,78,6)
print('PASS all-false mirror: refused unconfirmed, shared 78/6 when the adapter has the confirmed roles')
-- Review S2: a Saved Build slot has no role choice in the Wishlist Editor. Its message names only the active-loadout way.
rows=Rows(84,0)
Boot({[3]={name='ROLES-SAVED-BUILD',verified=true,echoes=rows}});before=H.Clone(H.perks.serverBuildSlots)
local _,savedLabel
p,savedLabel=Share('ROLES-SAVED-BUILD','ROLES-SAVED-BUILD')
assert(savedLabel:find('[Saved Build]',1,true),'fixture: listed as a Saved Build: '..tostring(savedLabel))
local savedLine=Refused('84 copies in a Saved Build',p,before,'has 84 Echo copies','Missing evidence:','make this Saved Build your active loadout')
assert(not savedLine:find('Wishlist Editor',1,true),'the Wishlist Editor way is not offered for a Saved Build: '..savedLine)
print('PASS Saved Build source: only the supported way is named')

-- 10. Review m10: confirmed roles of OTHER content on the same slot never apply to a stale selection.
rows=Rows(84,0)
Boot(Slot('ROLES-STALE',rows));before=nil
Nexus.CommunityBuilds.ShowPostBuild();p=assert(NexusPostPopup)
p._postWishlistBtn:Click();assert(MenuButton('ROLES-STALE')):Click()            -- the form now holds the first content
local other=Rows(84,0,nil,200400)
H.perks.serverBuildSlots[102].echoes=other;H.Notify();A=Nexus.GameAdapter;A.Poll()
candidate=nil;for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
chosen={};for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
assert(candidate.echoes[1].spellId==200401 and A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed'),'fixture: roles confirmed for the NEW content of the slot')
p._postTitleBox:_NexusSetRawText('ROLES-STALE');printed={}
local real=print;print=function(...)local t={};for i=1,select('#',...)do t[#t+1]=tostring((select(i,...)))end;printed[#printed+1]=table.concat(t,' ')end
p._postGoBtn:Click();print=real
assert(Nexus.CommunityBuilds.ShareStatus()==nil and #puts==0 and printed[#printed]:find('does not say which copies are permanent',1,true),'roles of other content are not applied: '..tostring(printed[#printed]))
print('PASS stale selection: roles of other content on the same slot are refused')

-- 11. Review F6: the adapter omitted an unreadable server row. The rest is not the complete source.
rows=Rows(40,6);rows[46].spellId='not-a-number'
Boot(Slot('ROLES-INCOMPLETE',rows));before=H.Clone(H.perks.serverBuildSlots)
p=Share('ROLES-INCOMPLETE','ROLES-INCOMPLETE')
Refused('unreadable server row',p,before,'cannot be read','not complete')
print('PASS incomplete mirror is refused; no permanent row is dropped silently')

-- 12. Review F7/F8/F12: every row is checked before acceptance; a hole hides nothing.
Boot(Slot('UNUSED',Rows(3,0)))
local function Direct(name,source,...)
 local ok,message=Nexus.CommunityBuilds.PostCurrentWishlist(name,'Synthetic',source,'MAGE')
 assert(ok==false and Nexus.CommunityBuilds.ShareStatus()==nil and #puts==0,name..': refused before acceptance, no catalog write')
 for _,text in ipairs({...})do assert(tostring(message):find(text,1,true),name..': '..tostring(message))end
 assert(not tostring(message):find('MALFORMED_ROW',1,true),name..': no raw catalog code')
end
local bad=Rows(10,2);bad[12].spellId=nil
Direct('ROLES-BAD-ID',{name='ROLES-BAD-ID',echoes=bad},'cannot be read')
bad=Rows(10,0);bad[3].stacks='2'
Direct('ROLES-STRING-COPIES',{name='ROLES-STRING-COPIES',echoes=bad},'cannot be read')
bad=Rows(10,0);bad[4].stacks=0
Direct('ROLES-ZERO-COPIES',{name='ROLES-ZERO-COPIES',echoes=bad},'cannot be read')
bad=Rows(10,0);bad[5].stacks=1.5
Direct('ROLES-FRACTION',{name='ROLES-FRACTION',echoes=bad},'cannot be read')
bad=Rows(10,0);bad[6].locked='yes'
Direct('ROLES-TEXT-FLAG',{name='ROLES-TEXT-FLAG',echoes=bad},'cannot be read')
bad=Rows(10,0);bad[12]={spellId=200012,quality=0,stacks=1}                       -- hole at 11
Direct('ROLES-SPARSE',{name='ROLES-SPARSE',echoes=bad},'cannot be read')
Direct('ROLES-BAD-PERMANENT',{name='ROLES-BAD-PERMANENT',echoes=Rows(10,0),lockedEchoes={{spellId=-4,stacks=1}}},'permanent Echo row that cannot be read')
-- locked=1 is the second spelling the catalog's own envelope reads as permanent.
local one=Rows(10,0);one[11]={spellId=200011,quality=1,stacks=2,locked=1}
assert(Nexus.CommunityBuilds.PostCurrentWishlist('ROLES-ONE','Synthetic',{name='ROLES-ONE',echoes=one},'MAGE'))
one[11].locked=true;Accepted('locked=1',one,10,2)
print('PASS row validation before acceptance')

-- 13. Review N3: array shape. A key outside 1..n cannot hide a hole; a present separate list must be a list;
-- a copy count is read as stated.
Boot(Slot('UNUSED',Rows(3,0)))
local holed={[0]={spellId=200050,quality=0,stacks=1},[1]={spellId=200001,quality=1,stacks=1},[3]={spellId=200003,quality=3,stacks=1,locked=true}}
Direct('ROLES-ZERO-KEY',{name='ROLES-ZERO-KEY',echoes=holed},'cannot be read')
local hidden={{spellId=200001,quality=1,stacks=1},nil,{spellId=200003,quality=3,stacks=1,locked=true}};hidden[0]={spellId=200050,quality=0,stacks=1}
Direct('ROLES-ZERO-KEY-HIDES-HOLE',{name='ROLES-ZERO-KEY-HIDES-HOLE',echoes=hidden},'cannot be read')
bad=Rows(10,0);bad[2.5]={spellId=200040,quality=0,stacks=1}
Direct('ROLES-FRACTION-KEY',{name='ROLES-FRACTION-KEY',echoes=bad},'cannot be read')
Direct('ROLES-LIST-IS-TEXT',{name='ROLES-LIST-IS-TEXT',echoes=Rows(10,0),lockedEchoes='200011'},'form that cannot be read')
bad=Rows(10,0);bad[4].stacks=false
Direct('ROLES-FALSE-COPIES',{name='ROLES-FALSE-COPIES',echoes=bad},'cannot be read')
Direct('ROLES-HOLE-IN-PERMANENT',{name='ROLES-HOLE-IN-PERMANENT',echoes=Rows(10,0),lockedEchoes={[2]={spellId=200011,quality=1,stacks=1}}},'permanent Echo row that cannot be read')
print('PASS array shape')

-- 14. Review F9 / N4 / mutant n12: qualities. The harness catalog states quality i%4 for Echo i; this source states another.
local function Shifted(n)local r=Rows(n,0);for i,e in ipairs(r)do e.quality=(i+1)%4 end;return r end
rows=Shifted(84)
Boot(Slot('ROLES-QUALITY',rows))
A=Nexus.GameAdapter;candidate=nil
for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
assert(candidate.echoes[1].quality~=rows[1].quality,'fixture: the adapter candidate carries the catalog quality, the source another')
chosen={};for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
assert(A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed'))
Share('ROLES-QUALITY','ROLES-QUALITY')
expected={};for i,e in ipairs(rows)do expected[i]={spellId=e.spellId,quality=e.quality,stacks=1,locked=i>78 or nil}end
Accepted('source quality kept on the adapter-resolved path',expected,78,6)
-- One Echo ID with two stated qualities, 84 copies, roles confirmed by ID only: which quality is permanent is not known.
rows=Rows(82,0);rows[83]={spellId=200001,quality=2,stacks=1};rows[84]={spellId=200001,quality=3,stacks=1}
Boot(Slot('ROLES-MIXED',rows));before=H.Clone(H.perks.serverBuildSlots)
A=Nexus.GameAdapter;candidate=nil
for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then candidate=c end end
if candidate then
 chosen={};for i,e in ipairs(candidate.echoes)do chosen[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=i>78}end
 A.ConfirmWishlistRoles(candidate,chosen,'user-confirmed')
end
p=Share('ROLES-MIXED','ROLES-MIXED')
local status=Nexus.CommunityBuilds.ShareStatus()
if status then
 -- Accepted only when the role evidence matches the exact ID-and-quality content.
 local record=Accepted('mixed qualities with exact evidence',(function()local e={};for i,r in ipairs(rows)do e[i]={spellId=r.spellId,quality=r.quality,stacks=1,locked=i>78 or nil}end;return e end)(),78,6)
 assert(record)
else
 Refused('mixed qualities without exact evidence',p,before,'Missing evidence:')
end
print('PASS qualities: the source quality is kept; mixed qualities are never guessed')

