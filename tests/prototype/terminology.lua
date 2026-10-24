local H=dofile('tests/prototype/harness.lua');H.Boot()
local T=assert(Nexus.UserText);local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
check(T.Message('unsynced')=='Waiting for current Echo data from the server - automatic choices paused','ownership is not network Sync')
check(T.Message('Take wanted Echo (EchoWeaver)')=='Take a needed Echo','planner provenance outside action')
check(T.Message('ROOT_MUTATION_PENDING'):find('in progress',1,true),'pending is not failure or success')
check(T.Message('MISSING_UNKNOWN_CODE'):find('Details: MISSING_UNKNOWN_CODE',1,true),'unknown raw code retained without forced readiness')
local d=T.Message('exact wishlist progress regressed 25 (gained 6, shed 31 exact stacks)')
check(d:find('25 fewer Wishlist copies',1,true) and d:find('31 fewer',1,true),'save comparison retains exact counts')
check(not d:find('shed',1,true),'no confusing shed wording in save comparison')
check(T.Annotation('returns later')=='Not taken now; a later offer is not guaranteed','no unproven offer is said to return')
check(T.Message('wishlist does not exactly match the verified active loadout; locked roles remain unknown.'):find('Choose this Wishlist',1,true),'role wait has actionable explanation')
check(T.Message('cleanup-only save added new excess/wrong-quality pollution'):find('Not saved:',1,true),'save refusal stays refusal')
Nexus.Panel.Show()
local text={};for _,f in ipairs(H.frames)do
 if f.GetText then text[#text+1]=f:GetText()end
 for _,r in ipairs(f.regions or {})do if r.GetText then text[#text+1]=r:GetText() end end
end
local all=table.concat(text,'\n')
check(all:find('EXTRA COPIES',1,true),'panel actual extra-copy heading')
check(not all:find('TO SHED',1,true),'old main heading absent')
SlashCmdList.NEXUS('help');check(NexusHelpWindow.body:GetText():find('experimental',1,true),'help identifies experimental build')
local auto=Nexus.RecomputeStats().autoEnabled
Nexus.Help.Show('rolling');check(NexusHelpWindow.body:GetText():find('Target 2/current 5 means 3 extras',1,true),'extra-copy definition in help')
check(Nexus.RecomputeStats().autoEnabled==auto,'wording/navigation does not enable automation')
Nexus.QuickStart.Show();local help,orbs
for _,f in ipairs(H.frames)do if f:GetParent()==NexusQuickStart then
 if f:GetText()=='Help / Getting Started'then help=f end
 if f:GetText()=='Orbs / Lost Memories'then orbs=f end
end end
check(help and orbs,'persistent help and Orb entry points in welcome')
help:Click();check(NexusHelpWindow:IsShown(),'real welcome help button')
-- Raw policy implementation is retained, not rewritten by display mapping.
local raw='tight horizon';check(T.Message(raw)=='Few selections remain' and raw=='tight horizon','mapping leaves source reason unchanged')
-- Issue #123: English status localization seam. The three status reasons
-- resolve through Nexus.Localization with their existing English bytes; the
-- resolver falls back to the reviewed English base and keeps a bounded local
-- record. RED before the seam: the TOC lines and Nexus.Localization are absent.
local toc={};for line in io.lines('Nexus.toc')do toc[#toc+1]=(line:gsub('\r',''))end
local function tocIndex(entry)
 local found
 for i,line in ipairs(toc)do if line==entry then check(not found,'TOC lists once: '..entry);found=i end end
 return found
end
local dataAt,seamAt,textAt=tocIndex('data\\LocalizationEnglish.lua'),tocIndex('core\\Localization.lua'),tocIndex('core\\UserText.lua')
check(dataAt and seamAt and textAt and dataAt<seamAt and seamAt<textAt,'English data, then the seam, then UserText in the TOC')
local L=assert(Nexus.Localization,'localization seam loaded');checks=checks+1
local before={actions=#H.actions,sent=#H.sent,chat=#H.chat,popup=H.popup,auto=Nexus.RecomputeStats().autoEnabled}
local d0=L.Diagnostics()
check(d0.base.present and d0.base.accepted==3 and d0.base.rejected==0 and not d0.base.oversized,'English base loaded whole at boot')
check(d0.misses==0,'English boot resolved without any fallback')
local keys=L.Keys()
check(#keys==3 and keys[1]=='reason.list_preparing' and keys[2]=='reason.save_in_progress' and keys[3]=='reason.saved_data_reading','base holds exactly the three reviewed keys')
local env={};local chunk=setfenv and setfenv(assert(loadfile('data/LocalizationEnglish.lua')),env) or assert(loadfile('data/LocalizationEnglish.lua','t',env));chunk()
local data=env.Nexus and env.Nexus.LocalizationEnglish
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
check(count(env)==1 and count(env.Nexus)==1 and type(data)=='table' and getmetatable(data)==nil and count(data)==3,'English data file sets one plain table and calls nothing')
local cohort={
 {'ROOT_MUTATION_PENDING','reason.save_in_progress','Saving is still in progress; wait for its final result'},
 {'CURSOR_REQUIRED','reason.list_preparing','This list is still being prepared'},
 {'STORE_PENDING','reason.saved_data_reading','Reading your saved data'},
}
for _,case in ipairs(cohort)do
 local code,key,english=case[1],case[2],case[3]
 check(data[key]==english and L.Has(key),'reviewed data bytes: '..key)
 local text,source,why=L.Text(key);check(text==english and source=='base' and why==nil,'seam resolves reviewed English: '..key)
 check(T.Message(code)==english and T.Message(T.Message(code))==english,'UserText exact bytes, stable when normalized again: '..code)
 check(T.Message('waiting: '..code)==english and T.Message('L3 -- '..code)=='L3 -- '..english,'existing prefixes still reach the seam: '..code)
 check(T.Annotation(code)==english,'annotation fallback reaches the seam: '..code)
end
check(L.Diagnostics().misses==0,'ordinary resolution records nothing')
local live=Nexus.LocalizationEnglish
live['reason.list_preparing'],live['reason.added_later']='Changed after load','Added after load'
check(L.Text('reason.list_preparing')=='This list is still being prepared' and not L.Has('reason.added_later'),'English base is copied once at load')
live['reason.list_preparing'],live['reason.added_later']='This list is still being prepared',nil
local K,E,U='reason.list_preparing','This list is still being prepared',L.UNAVAILABLE
check(type(U)=='string' and U:find('%S') and not U:find('|',1,true) and #U<=L.MAX_TEXT_BYTES,'documented safe status is nonempty contract text')
local function resolves(key,pack,wantText,wantSource,wantWhy,label)
 local ok,text,source,why=pcall(L.Resolve,key,pack)
 check(ok and text==wantText and source==wantSource and why==wantWhy,label)
end
local misses=L.Diagnostics().misses
resolves(K,{[K]='Fixture list text'},'Fixture list text','candidate',nil,'supported fixture candidate replaces a reviewed key')
resolves(K,{[K]='Fixture \226\128\148 text'},'Fixture \226\128\148 text','candidate',nil,'well-formed UTF-8 candidate')
resolves(K,{[K]=string.rep('x',L.MAX_TEXT_BYTES)},string.rep('x',L.MAX_TEXT_BYTES),'candidate',nil,'candidate at the length limit')
resolves(K,{},E,'base','missing_candidate','missing candidate entry falls back to English')
resolves(K,{['reason.save_in_progress']='Other key'},E,'base','missing_candidate','another key does not stand in')
for i,bad in ipairs({'','   ','\t\n',42,true,{},function()return 'x' end,'Has|cffff0000colour','Line\nbreak','Nul\0byte',string.rep('x',L.MAX_TEXT_BYTES+1),'\255\254bad','\226\128'})do
 resolves(K,{[K]=bad},E,'base','invalid_candidate','invalid candidate falls back to English #'..i)
end
-- Review fix (issue #123): candidate and base text is shortest-form UTF-8 for
-- Unicode scalar values only. Exact bytes come from string.char, so the
-- fixture does not depend on this file's encoding. Every sample has no
-- control byte and no "|", has a non-space byte and fits the length limit,
-- so only the UTF-8 rule decides it. These are byte and Unicode validity
-- checks, not proof of native glyph rendering.
local B=string.char
-- Lead and continuation bytes in range, but not the shortest form of a scalar
-- value: both ends of the invalid second-byte range of E0, ED, F0 and F4.
local nonScalar={
 {'E0 80 80, overlong U+0000',B(0xE0,0x80,0x80)},
 {'E0 9F BF, overlong U+07FF',B(0xE0,0x9F,0xBF)},
 {'ED A0 80, surrogate U+D800',B(0xED,0xA0,0x80)},
 {'ED BF BF, surrogate U+DFFF',B(0xED,0xBF,0xBF)},
 {'F0 80 80 80, overlong U+0000',B(0xF0,0x80,0x80,0x80)},
 {'F0 8F BF BF, overlong U+FFFF',B(0xF0,0x8F,0xBF,0xBF)},
 {'F4 90 80 80, above U+10FFFF',B(0xF4,0x90,0x80,0x80)},
 {'F4 BF BF BF, above U+10FFFF',B(0xF4,0xBF,0xBF,0xBF)},
}
-- Invalid lead bytes, stray continuations, a bad later byte and truncation.
local malformed={
 {'C0 80, invalid lead',B(0xC0,0x80)},
 {'C1 BF, invalid lead',B(0xC1,0xBF)},
 {'F5 80 80 80, invalid lead',B(0xF5,0x80,0x80,0x80)},
 {'FF, invalid lead',B(0xFF)},
 {'80, stray continuation',B(0x80)},
 {'BF, stray continuation',B(0xBF)},
 {'C2 78, missing continuation',B(0xC2,0x78)},
 {'E1 41 80, bad second byte',B(0xE1,0x41,0x80)},
 {'E0 A0 41, bad third byte',B(0xE0,0xA0,0x41)},
 {'F0 90 41 80, bad third byte',B(0xF0,0x90,0x41,0x80)},
 {'F4 8F BF 41, bad fourth byte',B(0xF4,0x8F,0xBF,0x41)},
 {'E2 82, truncated',B(0xE2,0x82)},
 {'F0 9F 98, truncated',B(0xF0,0x9F,0x98)},
 {'F4 8F BF, truncated',B(0xF4,0x8F,0xBF)},
}
-- Both ends of each lead's valid range, ordinary non-ASCII text and ASCII.
-- U+FFFF and U+10FFFF are noncharacters but scalar values, so they pass.
local scalar={
 {'C2 80, U+0080',B(0xC2,0x80)},
 {'DF BF, U+07FF',B(0xDF,0xBF)},
 {'E0 A0 80, U+0800',B(0xE0,0xA0,0x80)},
 {'E0 BF BF, U+0FFF',B(0xE0,0xBF,0xBF)},
 {'E1 80 80, U+1000',B(0xE1,0x80,0x80)},
 {'EC BF BF, U+CFFF',B(0xEC,0xBF,0xBF)},
 {'ED 80 80, U+D000',B(0xED,0x80,0x80)},
 {'ED 9F BF, U+D7FF',B(0xED,0x9F,0xBF)},
 {'EE 80 80, U+E000',B(0xEE,0x80,0x80)},
 {'EF BF BF, U+FFFF',B(0xEF,0xBF,0xBF)},
 {'F0 90 80 80, U+10000',B(0xF0,0x90,0x80,0x80)},
 {'F0 BF BF BF, U+3FFFF',B(0xF0,0xBF,0xBF,0xBF)},
 {'F1 80 80 80, U+40000',B(0xF1,0x80,0x80,0x80)},
 {'F3 BF BF BF, U+FFFFF',B(0xF3,0xBF,0xBF,0xBF)},
 {'F4 80 80 80, U+100000',B(0xF4,0x80,0x80,0x80)},
 {'F4 8F BF BF, U+10FFFF',B(0xF4,0x8F,0xBF,0xBF)},
 {'ordinary non-ASCII text','Caf'..B(0xC3,0xA9)..' '..B(0xE2,0x80,0x94)..' '..B(0xE6,0x97,0xA5,0xE6,0x9C,0xAC)..' '..B(0xF0,0x9F,0x98,0x80)},
 {'ASCII text','Plain ASCII status text'},
}
-- Each sample alone, after ASCII (a truncation stays at the end), between
-- ASCII, and after valid two-, three- and four-byte scalars, so the check
-- must advance through the whole string.
local function contexts(s)
 return {{'alone',s},{'after ASCII','Ab '..s},{'between ASCII','Ab '..s..' cd'},
  {'after multi-byte scalars',B(0xC3,0xA9)..B(0xE2,0x80,0x94)..B(0xF0,0x9F,0x98,0x80)..s..'z'}}
end
local function isolated(t)
 return #t>=1 and #t<=L.MAX_TEXT_BYTES and t:find('%S')~=nil and not t:find('[%z\1-\31\127|]')
end
for _,group in ipairs({{'non-scalar',nonScalar},{'malformed',malformed}})do
 for _,case in ipairs(group[2])do for _,c in ipairs(contexts(case[2]))do
  local label=group[1]..' candidate falls back to English: '..case[1]..' ('..c[1]..')'
  check(isolated(c[2]),'fixture isolates the UTF-8 rule: '..label)
  resolves(K,{[K]=c[2]},E,'base','invalid_candidate',label)
 end end
end
for _,case in ipairs(scalar)do
 for _,c in ipairs(contexts(case[2]))do
  local label='scalar candidate is accepted: '..case[1]..' ('..c[1]..')'
  check(isolated(c[2]),'fixture isolates the UTF-8 rule: '..label)
  resolves(K,{[K]=c[2]},c[2],'candidate',nil,label)
 end
 resolves(K,{[K]='Ab '..case[2]..' '..B(0xBF)},E,'base','invalid_candidate','a stray byte after a scalar is still refused: '..case[1])
end
local touched=0
local trap=setmetatable({},{__index=function()touched=touched+1;return 'Injected text' end})
for i,pack in ipairs({'unsupported-pack',7,false,function()return {} end,trap,setmetatable({[K]='Wrapped text'},{})})do
 resolves(K,pack,E,'base','unsupported_pack','unsupported requested pack falls back to English #'..i)
end
check(touched==0,'pack metamethods are never invoked')
resolves('reason.not_reviewed',nil,U,'unavailable','unknown_key','unknown base key yields the safe status')
resolves('reason.not_reviewed',{['reason.not_reviewed']='Fixture'},U,'unavailable','unknown_key','a candidate never adds a key')
for i,key in ipairs({'Reading your saved data','',7,'reason..double','reason.','.reason','reason.9x',string.rep('a',70)..'.b'})do
 resolves(key,nil,U,'unavailable','invalid_key','invalid key yields the safe status #'..i)
end
resolves(nil,nil,U,'unavailable','invalid_key','nil key yields the safe status')
check(L.Diagnostics().misses==misses,'Resolve itself records nothing')
-- Text counts a non-scalar candidate as any other invalid candidate and
-- keeps no key for it.
do
 local t0=L.Diagnostics()
 local tx,ts,tw=L.Text(K,{[K]=B(0xED,0xA0,0x80)})
 local t1=L.Diagnostics()
 check(tx==E and ts=='base' and tw=='invalid_candidate','Text falls back to English for a surrogate candidate, never its bytes')
 check(t1.misses-t0.misses==1 and t1.byReason.invalid_candidate-t0.byReason.invalid_candidate==1 and t1.last=='invalid_candidate' and #t1.keys==#t0.keys and t1.keysNotKept==t0.keysNotKept,'a non-scalar candidate is counted as invalid_candidate and keeps no key')
end
local d1=L.Diagnostics()
for i=1,200 do L.Text('reason.fixture_miss_'..i)end
for _=1,50 do L.Text('reason.fixture_miss_1')end
check(L.Text(K,'unsupported-pack')==E and L.Text(K,{[K]='  '})==E,'Text falls back to English')
local d2=L.Diagnostics()
check(d2.misses-d1.misses==252 and d2.byReason.unknown_key-d1.byReason.unknown_key==250,'every miss is counted')
check(d2.byReason.unsupported_pack-d1.byReason.unsupported_pack==1 and d2.byReason.invalid_candidate-d1.byReason.invalid_candidate==1 and d2.last=='invalid_candidate','fallback reasons are counted')
check(#d2.keys<=L.MAX_DIAGNOSTIC_KEYS and d2.keysNotKept>d1.keysNotKept,'distinct missed keys stay bounded')
local copy=L.Diagnostics();copy.keys[1]='edited';copy.misses=-1;copy.byReason.unknown_key=-1
local d3=L.Diagnostics();check(d3.misses==d2.misses and d3.byReason.unknown_key==d2.byReason.unknown_key and d3.keys[1]~='edited','diagnostics are a copy')
local real,realData=Nexus.Localization,Nexus.LocalizationEnglish
local function reload(base)
 Nexus.LocalizationEnglish=base
 local ok=pcall(dofile,'core/Localization.lua');local module=Nexus.Localization
 Nexus.Localization,Nexus.LocalizationEnglish=real,realData
 return ok and module~=real and module or nil
end
local absent=assert(reload(nil),'loader without English data');checks=checks+1
check(#absent.Keys()==0 and not absent.Diagnostics().base.present and absent.Resolve(K)==absent.UNAVAILABLE,'without the English data every key is the safe status, without error')
local meta=assert(reload(setmetatable({},{__index=function()return E end})))
check(#meta.Keys()==0 and not meta.Diagnostics().base.present,'a base table with a metatable is not adopted')
local many={};for i=1,L.MAX_BASE_ENTRIES+1 do many['reason.entry_'..i]='Entry text' end
local big=assert(reload(many))
check(#big.Keys()==0 and big.Diagnostics().base.oversized,'an oversized base is not adopted')
local partial=assert(reload({['reason.save_in_progress']='Saving is still in progress; wait for its final result',['Bad Key']='Bad',['reason.blank']='  ',['reason.number']=5}))
local pd=partial.Diagnostics().base
check(#partial.Keys()==1 and pd.accepted==1 and pd.rejected==3 and select(3,partial.Resolve(K))=='unknown_key','invalid base entries are left out and counted')
-- Review fix (issue #123): the English base copied at load passes the same
-- text boundary. A non-scalar or malformed base entry is left out and
-- counted, is absent from Has and Keys, resolves to the safe status, and a
-- candidate cannot bring it back. reload() restores the real module and data.
do
 local invalidBase={['reason.save_in_progress']='Saving is still in progress; wait for its final result',
  ['reason.list_preparing']='This list is '..B(0xED,0xA0,0x80)..' prepared'}
 local rejected={'reason.list_preparing'}
 for _,group in ipairs({{'non_scalar',nonScalar},{'malformed',malformed}})do
  for i,case in ipairs(group[2])do
   for j,value in ipairs({case[2],'Ab '..case[2]..' cd'})do
    local key='reason.'..group[1]..'_'..i..'_'..j
    invalidBase[key]=value;rejected[#rejected+1]=key
   end
  end
 end
 check(count(invalidBase)==#rejected+1 and count(invalidBase)<=L.MAX_BASE_ENTRIES,'invalid base fixture stays within the entry limit')
 local refusing=assert(reload(invalidBase),'loader with non-scalar and malformed base entries');checks=checks+1
 local rd=refusing.Diagnostics().base
 check(rd.present and not rd.oversized and rd.accepted==1 and rd.rejected==#rejected,'non-scalar and malformed base entries are left out and counted')
 local rk=refusing.Keys()
 check(#rk==1 and rk[1]=='reason.save_in_progress' and refusing.UNAVAILABLE==U,'only the valid base entry is listed; the safe status is the same')
 local unknown0=refusing.Diagnostics().byReason.unknown_key
 for _,key in ipairs(rejected)do
  check(not refusing.Has(key),'rejected base key is absent from Has: '..key)
  local text,source,why=refusing.Resolve(key)
  check(text==U and source=='unavailable' and why=='unknown_key','rejected base key resolves to the safe status: '..key)
  text,source,why=refusing.Resolve(key,{[key]='Fixture replacement text'})
  check(text==U and source=='unavailable' and why=='unknown_key','a candidate cannot resurrect a rejected base key: '..key)
  check(refusing.Text(key)==U,'Text gives the safe status for a rejected base key: '..key)
 end
 check(refusing.Diagnostics().byReason.unknown_key-unknown0==#rejected,'each shown rejected base key is counted as unknown_key')
 local kept,keptSource,keptWhy=refusing.Resolve('reason.save_in_progress')
 check(kept=='Saving is still in progress; wait for its final result' and keptSource=='base' and keptWhy==nil,'the valid base entry beside them still resolves')
 Nexus.Localization=refusing
 local shownBad,shownGood=T.Message('CURSOR_REQUIRED'),T.Message('ROOT_MUTATION_PENDING')
 Nexus.Localization=real
 check(shownBad==U..' Details: CURSOR_REQUIRED','a non-scalar base text never reaches the player; the safe status and its code do')
 check(shownGood=='Saving is still in progress; wait for its final result','a valid base text beside it still reaches the player')
 local validBase,valid={},{}
 for i,case in ipairs(scalar)do
  for j,value in ipairs({case[2],'Ab '..case[2]..' cd'})do
   local key='reason.scalar_'..i..'_'..j
   validBase[key]=value;valid[#valid+1]=key
  end
 end
 table.sort(valid)
 check(#valid<=L.MAX_BASE_ENTRIES,'scalar base fixture stays within the entry limit')
 local accepting=assert(reload(validBase),'loader with scalar base entries');checks=checks+1
 local ad=accepting.Diagnostics().base
 check(ad.present and not ad.oversized and ad.accepted==#valid and ad.rejected==0,'every scalar base entry is accepted')
 local ak,listed=accepting.Keys(),true
 for i=1,#valid do listed=listed and ak[i]==valid[i] end
 check(#ak==#valid and listed,'every scalar base key is listed, sorted')
 for _,key in ipairs(valid)do
  local value,source,why=accepting.Resolve(key)
  check(accepting.Has(key) and value==validBase[key] and source=='base' and why==nil,'scalar base text resolves with its exact bytes: '..key)
 end
 check(#L.Keys()==3 and L.Has(K) and L.Resolve(K)==E,'the real English base is unchanged by the loader checks')
end
check(Nexus.Localization==real and Nexus.LocalizationEnglish==realData,'real seam and data restored after the loader checks')
Nexus.Localization=partial
check(T.Message('CURSOR_REQUIRED')==partial.UNAVAILABLE..' Details: CURSOR_REQUIRED','unknown base key reaches the player as the safe status with its code')
check(T.Message(T.Message('CURSOR_REQUIRED'))==T.Message('CURSOR_REQUIRED'),'safe status is stable when normalized again')
check(T.Message('ROOT_MUTATION_PENDING')=='Saving is still in progress; wait for its final result','a key the base holds still resolves')
Nexus.Localization=nil
check(T.Message('STORE_PENDING')=='This action is not available yet. Check the status or diagnostics. Details: STORE_PENDING','without the seam the code reads as any other unrecognized code')
Nexus.Localization=real
check(T.Message('STORE_PENDING')=='Reading your saved data' and L.Diagnostics().misses==d3.misses,'real seam restored with its record untouched')
check(#H.actions==before.actions and #H.sent==before.sent and H.popup==before.popup and #H.chat==before.chat,'seam acts, sends, asks and prints nothing')
check(Nexus.RecomputeStats().autoEnabled==before.auto,'seam changes no Automation state')
print('PASS terminology, state fidelity, counts and guide discoverability='..checks)
