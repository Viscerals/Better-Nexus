-- Full UI localization, family "usertext" (core/UserText.lua): every visible
-- output of UserText passes the Nexus.Localization seam at call time.
-- Drives T.Message / T.Annotation / T.Details with the real raw producer
-- inputs the existing tests use, plus the destination, setup, status, count,
-- record and term words, in three seams within one boot:
--   pseudo  the session pseudo pack (tests/prototype/l10n_pseudo_support.lua)
--   english a fresh English-only seam (no pack)
--   absent  Nexus.Localization = nil (the code's own English)
-- english must equal absent byte for byte (the catalog English is the exact
-- code English); pseudo must be fully marked except data slots and the
-- documented legacy rewrite chain. A raw producer input is never translated
-- and translated output is never converted again: one real Panel render and
-- SetStatus show the presented text on the displayed FontString and the
-- Options hover exactly once. Synthetic offline evidence only: no native
-- client, glyph, font or fluency claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
S.InstallBootHook()
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local T=assert(Nexus.UserText,'UserText loaded')
local PSEUDO=assert(Nexus.Localization)
check(PSEUDO.ActiveLanguage()=='frFR','SETUP the pseudo pack is the session language')
local diag=PSEUDO.Diagnostics().base
check(diag.undeclared==0 and diag.missingDeclared==0 and diag.rejected==0,'SETUP composed catalog: no undeclared, missing or rejected English entry')

-- A fresh English-only seam (no pack): the English the catalog gives.
local realPacks=Nexus.LocalizationPacks
Nexus.LocalizationPacks=nil
assert(pcall(dofile,'core/Localization.lua'))
local ENGLISH=Nexus.Localization
Nexus.LocalizationPacks=realPacks
Nexus.Localization=PSEUDO
check(ENGLISH~=PSEUDO and ENGLISH.ActiveLanguage()=='enUS','SETUP a separate English seam')

-- This family's keys: the composed English keys under its prefixes, except the
-- five original reasons (owned by issues #123/#142, unchanged here).
local ORIGINAL={['reason.save_in_progress']=true,['reason.list_preparing']=true,['reason.saved_data_reading']=true,
 ['reason.wait_three_choices']=true,['reason.wait_pending_pick_count']=true}
local english=S.English()
local FAMILY,familyCount={},0
for key in pairs(english)do
 if (key:find('^reason%.') or key:find('^term%.') or key:find('^count%.') or key:find('^usertext%.')) and not ORIGINAL[key] then
  FAMILY[key]=true;familyCount=familyCount+1
 end
end
check(familyCount>=250,'SETUP the usertext family keys are in the composed catalog ('..familyCount..')')

-- Record every key UserText asks the pseudo seam for.
local hit={}
local realText,realFormat=PSEUDO.Text,PSEUDO.Format
PSEUDO.Text=function(key,...) hit[key]=true;return realText(key,...) end
PSEUDO.Format=function(key,...) hit[key]=true;return realFormat(key,...) end

-- Fixture data (never translated): the narrow allowlist of data words.
local DATA={Zorblax=true,Qwyn=true,Vexmor=true,Tomeqa=true,WEIRD_STATE=true,Kraal=true}
local function allow(word) return DATA[word]==true end
local CATALOG={levers={[7]={tomeName='Tomeqa'}}}
local adapter=Nexus.GameAdapter
local realCatalog=adapter.Catalog

local function flat(out,v)
 if type(v)=='string' then out[#out+1]=v
 elseif type(v)=='table' then
  if v.rows then for _,r in ipairs(v.rows)do flat(out,r.label);flat(out,r.text) end
  else
   for _,x in ipairs(v)do
    if type(x)=='table' and (x.label or x.value) then
     flat(out,x.label);flat(out,x.value);flat(out,x.compact);flat(out,x.minimum)
    else flat(out,x) end
   end
  end
 end
 return out
end
-- One corpus entry: label, a function returning visible values, and pending
-- (true: the output is the documented legacy rewrite of producer English).
local corpus={}
local function add(label,fn,pending) corpus[#corpus+1]={label=label,fn=fn,pending=pending} end
local function msg(raw,pending) add('Message '..raw,function() return T.Message(raw) end,pending) end

-- Raw producer reasons (the reasons table and the inputs existing tests use).
for _,raw in ipairs({'unsynced','waiting for owned-echo sync','waiting for owned-state sync','no wishlist set - advisor only',
 'no wishlist','pending-pick count','Orb state active or unknown','orb state not yet known','orb state unknown',
 'orb state unavailable','orb state capability missing','Orb offer active -- manual action required',
 'Take wanted Echo (EchoWeaver)','Take available Echo (EchoWeaver)','Freeze wanted Echo before search (EchoWeaver)',
 'Banish to find Wishlist targets (EchoWeaver)','Reroll: no requested Echo on board (EchoWeaver)',
 'Reroll: no needed Echo on board (EchoWeaver)','Take available filler (EchoWeaver)','Take filler; search unavailable (EchoWeaver)',
 'Wishlist complete; take filler (EchoWeaver)','Freeze one wanted Echo to keep a second wanted offer (EchoWeaver, experimental)',
 'Banish an unwanted Echo before Reroll (EchoWeaver, experimental)','Take the held wanted Echo instead of searching (EchoWeaver, experimental)',
 'Take wanted Echo','invalid wishlist','invalid loadout','ROOT_PENDING','SOURCE_KEY_WIDTH_EXCEEDED','preparing','cleaning','throttled',
 'armed (guaranteed queue live)','Activate did not guarantee -- treating as unarmed','bracket fishing: reroll filler guarantee',
 'tight horizon','drain guaranteed queue','Tome levers','flag demotions cleared (they re-arm on fresh evidence)',
 'waiting: unsynced','L3 -- tight horizon','disabling off-wishlist tome lever 12345','disabling off-wishlist tome lever 7',
 're-enabling wishlist tome lever 7','re-enabling wishlist tome lever 99','lever 7: non-conformant data','lever 8: ',
 'wishlist does not exactly match the verified active loadout; locked roles remain unknown.',
 'awaiting authoritative lock evidence','waiting for authoritative locked-Echo evidence',
 'waiting for synchronized permanent locked-Echo evidence','waiting for the server mirror','payload changed','preview is stale',
 'exact wishlist progress regressed 25 (gained 6, shed 31 exact stacks)','exact wishlist progress regressed 0 (gained 0, shed 0 exact stacks)',
 'cleanup-only save added new excess/wrong-quality pollution','no net gain','coverage lost: 200001','MISSING_UNKNOWN_CODE',
 'MISSING_REVIEW_CODE'})do msg(raw) end
-- The legacy in-text rewrite chain over producer-composed English (pending:
-- converted later together with its producers).
for _,raw in ipairs({'tight horizon: take guaranteed','TARGET: Zorblax (synced)','queue UNARMED','MISSING_REVIEW_CODE ARMED','OWNED this run: 3 (not synced yet)',
 'Take filler; search unavailable','scan tome lever 4'})do msg(raw,true) end
for _,code in ipairs({'wanted','returns later','banked','filler','low quality','target met','wrong quality','target satisfied','frozen'})do
 add('Annotation '..code,function() return T.Annotation(code) end)
end
add('Annotation falls back to Message',function() return T.Annotation('tight horizon') end)
add('Details code',function() return T.Details('CODE_X') end)
add('Details nil',function() return T.Details(nil) end)
add('SavedBuildLabel',function() return {T.SavedBuildLabel(2,'Zorblax'),T.SavedBuildLabel(3),T.SavedBuildLabel(nil,'Qwyn')} end)
-- Every destination kind, state and Wishlist state, captured and Preview.
local descriptors={}
local wishlistStates={'assigned','unassigned','unavailable','restoring',false}
local function D(d) descriptors[#descriptors+1]=d end
for _,state in ipairs({'unavailable','empty','active','inactive','unconfirmed','none'})do
 for _,slot in ipairs({2,false})do
  for _,named in ipairs({true,false})do
   local d={kind='savedBuild',slot=slot or nil,name=named and 'Zorblax' or nil,character='Kraal'}
   if state=='unavailable' then d.unavailable=true elseif state=='empty' then d.empty=true
   elseif state=='active' then d.active=true elseif state=='inactive' then d.active=false
   elseif state=='unconfirmed' then d.unconfirmed=true end
   D(d)
  end
 end
end
for _,kind in ipairs({'firstRun','unconfirmed','unknown','restoring','none'})do
 D(kind=='restoring' and {kind='unknown',reason='restoring'} or {kind=kind})
end
local expanded={}
for _,d in ipairs(descriptors)do
 for _,ws in ipairs(wishlistStates)do
  for _,named in ipairs({true,false})do
   for _,captured in ipairs({true,false})do
    for _,preview in ipairs({true,false})do
     local c={};for k,v in pairs(d)do c[k]=v end
     c.wishlistState=ws or nil;c.wishlist=named and 'Qwyn' or nil;c.captured=captured;c.preview=preview
     expanded[#expanded+1]=c
    end
   end
  end
 end
end
add('DestinationFields x'..#expanded,function()
 local out={}
 for _,d in ipairs(expanded)do local f,t=T.DestinationFields(d);flat(out,f);flat(out,t) end
 return out
end)
add('DestinationLines x'..#expanded,function()
 local out={}
 for _,d in ipairs(expanded)do flat(out,T.DestinationLines(d)) end
 return out
end)
-- Setup checklist and status lines.
local setupFacts={{startup='loading'},{startup='broken'},{startup='ready'}}
for _,d in ipairs(descriptors)do
 for _,ws in ipairs(wishlistStates)do
  for _,named in ipairs({true,false})do
   local c={};for k,v in pairs(d)do c[k]=v end
   c.wishlistState=ws or nil;c.wishlist=named and 'Qwyn' or nil
   setupFacts[#setupFacts+1]={startup='ready',destination=c}
  end
 end
end
add('SetupChecklist x'..#setupFacts,function()
 local out={}
 for _,f in ipairs(setupFacts)do flat(out,T.SetupChecklist(f)) end
 for _,status in ipairs({'done','todo','waiting','unknown','info'})do out[#out+1]=T.CHECK_MARKS[status] end
 return out
end)
-- 'none' stands for an absent Orb fact (nil), 'unread' for nil with
-- orbObserved=false; every other entry is passed as it is.
local orbFacts={false,'none','unread',{running=true},{restored=true,pending=true},{state='RECOVERY'},{state='WEIRD_STATE'},{},
 {pending=true,operation='Vexmor',reason='Kraal halted'},{state='PAUSED',reason='Kraal halted.'}}
for _,s in ipairs({'PAUSED','STOPPED','LIMIT','FINISHED','COMPLETE','ROLLED_COMPLETE','OUT_OF_ORBS','NO_SOURCES'})do
 orbFacts[#orbFacts+1]={state=s,pending=true}
end
add('StatusLines',function()
 local out={}
 for i,fact in ipairs(orbFacts)do
  local orb,observed=fact,nil
  if fact=='none' then orb=nil elseif fact=='unread' then orb,observed=nil,false end
  for _,auto in ipairs({'on','off','unknown'})do
   for _,mode in ipairs({'automatic','manual','off','weird'})do
    local facts={syncMode=mode,orb=orb,orbObserved=observed}
    if auto=='on' then facts.auto=true;if i%2==0 then facts.autoNote='Zorblax' end
    elseif auto=='off' then facts.auto=false end
    if i%2==0 then facts.syncExplicit=false end
    flat(out,T.StatusLines(facts))
   end
  end
 end
 return out
end)
add('Counts',function()
 local out={}
 for _,kind in ipairs({'planned','run','savedBuild','locked','families','weird'})do
  out[#out+1]=T.CountText(kind,12,79);out[#out+1]=T.CountText(kind,0,5);out[#out+1]=T.CountText(kind,nil,79);out[#out+1]=T.CountText(kind,3,0)
  out[#out+1]=T.COUNT_UNITS[kind]
 end
 for _,compact in ipairs({true,false})do
  out[#out+1]=T.RunProgressText(4,6,2,compact);out[#out+1]=T.RunProgressText(4,6,0,compact);out[#out+1]=T.RunProgressText(nil,6,1,compact)
 end
 return out
end)
add('Records',function()
 local out={T.BEST_KNOWN,T.RECORD_SCOPE,T.LEADERBOARD_SCOPE,T.GLOSSARY,T.OwnerLine({ownerVerified=true}),T.OwnerLine({ownerVerified=false})}
 for _,c in ipairs({'lk','dummy','combined'})do out[#out+1]=T.CategoryName(c) end
 flat(out,T.RecordDetailParts({category='lk',duration=125,level=80,ts=86400*365}))
 return out
end)
add('Terms',function()
 local out={}
 for _,name in ipairs({'options','menuAndStatus','bestKnown','showRecords','myBuildsPage','mineScope','firstRun'})do out[#out+1]=T.Terms[name] end
 return out
end)

local function run(entry)
 adapter.Catalog=function() return CATALOG end
 local ok,v=pcall(entry.fn)
 adapter.Catalog=realCatalog
 assert(ok,v)
 return flat({},v)
end
local function withSeam(seam,fn)
 local saved=Nexus.Localization
 Nexus.Localization=seam
 local ok,v=pcall(fn)
 Nexus.Localization=saved
 assert(ok,v)
 return v
end

-- Passivity: saved tables and effect counters before the whole drive.
local function same(a,b,seen)
 if type(a)~='table' or type(b)~='table' then return a==b end
 seen=seen or {};if seen[a] then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a)do if not same(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local db0,wr0=H.Clone(NexusDB),H.Clone(WishlistRealizerDB)
local before={actions=#H.actions,sent=#H.sent,chat=#H.chat,popup=H.popup}

local totalValues,pendingValues=0,0
for _,entry in ipairs(corpus)do
 local pseudo=run(entry)
 local eng=withSeam(ENGLISH,function() return run(entry) end)
 local absent=withSeam(nil,function() return run(entry) end)
 check(#pseudo==#eng and #eng==#absent and #eng>0,'SETUP same value count in each seam: '..entry.label)
 local differs=0
 for i=1,#eng do
  totalValues=totalValues+1
  if eng[i]~=absent[i] then
   error('English seam differs from the code English: '..entry.label..'\n  seam:   '..eng[i]..'\n  absent: '..absent[i])
  end
  if entry.pending then
   pendingValues=pendingValues+1
   if pseudo[i]~=eng[i] then error('pending legacy rewrite is not plain English: '..entry.label) end
  else
   local word=S.LooksUntranslated(pseudo[i],allow)
   if word then error('unmarked English "'..word..'" under the pseudo pack: '..entry.label..'\n  '..pseudo[i]) end
   if pseudo[i]~=eng[i] then differs=differs+1 end
  end
 end
 checks=checks+1
 if not entry.pending then check(differs>0,'pseudo text reaches the output: '..entry.label) end
end
check(totalValues>4000,'the corpus drives '..totalValues..' visible values ('..pendingValues..' documented pending)')

-- Every family key was asked for by the corpus (no unreachable or unbound key).
local missing={}
for key in pairs(FAMILY)do if not hit[key] then missing[#missing+1]=key end end
table.sort(missing)
check(#missing==0,'every usertext key is reached by a real UserText call; missing: '..table.concat(missing,', '))
for key in pairs(hit)do check(english[key]~=nil,'only catalog keys are asked for: '..key) end
check(PSEUDO.Diagnostics().misses==0,'the pseudo session resolved every key without a fallback')

-- Exact English of representative existing expectations (English seam).
withSeam(ENGLISH,function()
 for _,case in ipairs({
  {T.Message('unsynced'),'Waiting for current Echo data from the server - automatic choices paused'},
  {T.Message('Take wanted Echo (EchoWeaver)'),'Take a needed Echo'},
  {T.Message('MISSING_UNKNOWN_CODE'),'This action is not available yet. Check the status or diagnostics. Details: MISSING_UNKNOWN_CODE'},
  {T.Message('exact wishlist progress regressed 25 (gained 6, shed 31 exact stacks)'),'Not saved: this run matches 25 fewer Wishlist copies (6 gained, 31 fewer than the saved build).'},
  {T.Message('Reroll: no needed Echo on board (EchoWeaver)'),'Reroll: no Echo on this board is still needed'},
  {T.Message('disabling off-wishlist tome lever 12345'),'Disabling off-Wishlist Echo-availability control #12345'},
  {T.Message('L3 -- tight horizon'),'L3 -- Few selections remain'},
  {T.Annotation('returns later'),'Not taken now; a later offer is not guaranteed'},
  {T.Details('X'),'Details: X'},{T.Details(),'Details: unknown'},
  {T.CountText('run',12,79),'12 / 79 rolled copies this run'},{T.CountText('run',nil,79),'Rolled copies this run: unavailable'},
  {T.CountText('weird',1,2),'1 / 2 copies'},{T.CountText('weird',1,0),'Copies: unavailable'},
  {T.RunProgressText(4,6,2,true),'4 / 6 rolled, 2 to lock'},{T.COUNT_UNITS.savedBuild,'Wishlist copies in this Saved Build'},
  {T.SavedBuildLabel(2,'Fire PvE'),"Saved Build 'Fire PvE' (slot 2)"},{T.Terms.firstRun,'first-run target'},
  {T.BEST_KNOWN,'Best known'},{T.CHECK_MARKS.todo,'[to do]'},
 })do check(case[1]==case[2],'exact English: '..case[2]) end
 check(T.COUNT_UNITS.copies==nil and T.CHECK_MARKS.weird==nil and T.Terms.weird==nil and T.NOT_A_FIELD==nil,'proxies name only their known entries')
end)

-- Counts and knownness under the pseudo pack: zero is 0, unknown is never 0.
check(T.CountText('run',0,5)==S.OPEN..'0 / 5 rolled copies this run'..S.CLOSE,'zero count shows 0 inside the translated line')
local unknown=T.CountText('run',nil,5)
check(unknown==S.OPEN..'Rolled copies this run: unavailable'..S.CLOSE and not unknown:find('0',1,true),'unknown count is the distinct unavailable line, never 0')
check(PSEUDO.Format('count.run_progress',{have=PSEUDO.Count(nil),want=PSEUDO.Count(5)})==S.OPEN..'? / 5 rolled copies this run'..S.CLOSE,'an unknown count slot shows ?')
check(T.CountText('run',3,0)==S.OPEN..'Rolled copies this run: unavailable'..S.CLOSE,'an unknown total is unavailable, not 3 / 0')
-- Names are inserted verbatim: long, non-ASCII and escaped-pipe names.
local accented='\195\156n\195\175c\195\184d\195\169 \197\156tar'
check(T.SavedBuildLabel(2,accented)==S.OPEN.."Saved Build '"..accented.."' (slot 2)"..S.CLOSE,'non-ASCII name verbatim in the translated label')
local long=string.rep('Zorblax ',120)
local fields=T.DestinationFields({kind='savedBuild',slot=4,name=long,wishlist='A|B',wishlistState='assigned'})
check(fields[2].value==S.OPEN..long..' (slot 4)'..S.CLOSE,'a 960-byte name verbatim in the translated cell')
check(fields[3].value==S.OPEN..'A||B (assigned)'..S.CLOSE and fields[3].minimum=='A||B','an escaped pipe in a name stays the escaped pair; the bare-name minimum is data only')
-- I-01: a shortened name never splits its escaped pipe pair, in every seam and
-- at every cut. The cut name stays a data slot: verbatim in the translated
-- label, and byte-identical between the English seam and the code English.
local function paired(text)
 if type(text)~='string' then return false end
 for run in text:gmatch('|+')do if #run%2~=0 then return false end end
 return true
end
local piped='Zorblax|Qwyn'
for n=1,#'Zorblax||Qwyn'+1 do
 local shown=T.SafeName(piped,n)
 local eng=withSeam(ENGLISH,function() return T.SavedBuildLabel(2,piped,n) end)
 local absent=withSeam(nil,function() return T.SavedBuildLabel(2,piped,n) end)
 check(paired(shown) and T.SavedBuildLabel(2,piped,n)==S.OPEN.."Saved Build '"..shown.."' (slot 2)"..S.CLOSE,
  'a cut piped name keeps its escaped pair, verbatim in the translated label (cut '..n..': '..tostring(shown)..')')
 check(eng==absent and eng=="Saved Build '"..shown.."' (slot 2)",'the English seam equals the code English for a cut piped name (cut '..n..')')
end
check(T.SafeName(piped,8)=='Zorblax...' and T.SafeName(piped,9)=='Zorblax||...' and T.SafeName(piped)=='Zorblax||Qwyn' and piped=='Zorblax|Qwyn',
 'the cut before a pair keeps neither pipe, the cut after it keeps both; the whole name and the raw input are unchanged')
-- The Auto note's own 200-letter cut, with the pair at letters 200-201.
local note=string.rep('Zorblax ',24)..'Zorblax|Qwyn'
local held=string.rep('Zorblax ',24)..'Zorblax...'
local function heldLine() return T.StatusLines({auto=true,autoNote=note})[1] end
local engHeld,absentHeld=withSeam(ENGLISH,heldLine),withSeam(nil,heldLine)
check(heldLine():find(held,1,true)~=nil and engHeld==absentHeld and paired(engHeld) and engHeld:find(held,1,true)~=nil,
 'the Auto note is cut before its escaped pair in every seam; English equals the code English')
-- A slot value above the seam's text-slot limit shows the exact English, not a refusal.
local huge=string.rep('Kraal ',200)
check(T.Message('payload changed '..huge)=='This draft changed. Reopen it and review the current targets before saving. Details: payload changed '..huge,'over-limit raw detail falls back to the exact English')
-- The raw code stays raw inside the translated support line.
local code=T.Message('MISSING_UNKNOWN_CODE')
check(S.IsPseudo(code) and code:find('Details: MISSING_UNKNOWN_CODE',1,true) and S.LooksUntranslated(code,allow)==nil,'the raw code is retained verbatim and the sentence is translated')
check(T.Details('RAW_CODE_7')==S.OPEN..'Details: RAW_CODE_7'..S.CLOSE,'Details: CODE keeps the code raw')
-- The five original reasons keep their mapping (they are not this family's keys).
check(T.Message('ROOT_MUTATION_PENDING')==S.OPEN..'Saving is still in progress; wait for its final result'..S.CLOSE and hit['reason.save_in_progress']==true,'original reason mapping unchanged (its own original key)')
-- Provenance: a seam reason carries it; a raw-slot template does not.
local text,localized=T.Message('unsynced')
check(S.IsPseudo(text) and localized==true,'a reason resolved through the seam carries localized provenance')
text,localized=T.Message('L3 -- unsynced')
check(text=='L3 -- '..S.OPEN..'Waiting for current Echo data from the server - automatic choices paused'..S.CLOSE and localized==true,'the level prefix keeps provenance for a seam reason')
text,localized=T.Message('MISSING_UNKNOWN_CODE')
check(localized==nil,'a raw-code template carries no provenance')
text,localized=withSeam(nil,function() return T.Message('unsynced') end)
check(text=='Waiting for current Echo data from the server - automatic choices paused' and localized==nil,'without the seam the code English has no provenance')

-- One real Panel render and SetStatus: the presented text reaches the displayed
-- FontString and the Options hover exactly once (never converted again).
Nexus.Panel.Show()
local raw='Freeze wanted Echo before search (EchoWeaver)'
local once=T.Message(raw)
local twice=T.Message(once)
check(once~=twice,'SETUP a second conversion would change this text (the legacy rewrite matches its English)')
local model={status=raw,recommendation=raw,cards={},auto=false,level=40,version=Nexus.VERSION,
 progress={wishlistName='Zorblax',total=2,owned=0,missing={},shed={},unknownTomes={},toLock={}}}
assert(Nexus.Panel.Render(model))
check(model.status==raw and model.recommendation==raw,'the raw producer reason stays the input')
check(NexusPanel._rollRec:GetText()==once and Nexus.Panel._lastModel.status==once,'the displayed recommendation FontString shows the single presentation')
local function hover()
 return table.concat(S.CaptureTooltip(function() NexusPanel._menuBtn.scripts.OnEnter(NexusPanel._menuBtn);NexusPanel._menuBtn.scripts.OnLeave(NexusPanel._menuBtn) end),'\n')
end
local lines=hover()
check(lines:find(once,1,true) and not lines:find(twice,1,true),'the Options hover shows the status presented once')
local again=H.Clone(Nexus.Panel._lastModel);assert(Nexus.Panel.Render(again))
check(NexusPanel._rollRec:GetText()==once and Nexus.Panel._lastModel.status==once,'re-rendering the committed copy presents from the recorded raw, not the translated text')
check(Nexus.Panel.SetStatus('throttled')==true and Nexus.Panel._lastModel.status==T.Message('throttled') and S.IsPseudo(Nexus.Panel._lastModel.status),'raw SetStatus presents the translated reason')
check(Nexus.Panel.StatusTooltipText()==T.Message('throttled') and hover():find(T.Message('throttled'),1,true),'the localized status reaches the hover with its provenance')

-- Passivity: nothing above saved, sent, acted, printed or opened a popup.
check(same(NexusDB,db0) and same(WishlistRealizerDB,wr0),'saved tables unchanged by every UserText call and render')
check(#H.actions==before.actions and #H.sent==before.sent and #H.chat==before.chat and H.popup==before.popup,'no game action, send, chat or popup')

-- Missing pack entries fall back to the exact English for those keys only.
PSEUDO.Text,PSEUDO.Format=realText,realFormat
local entries=S.PseudoEntries()
for _,key in ipairs({'reason.wait_echo_data','count.run_progress','usertext.value.build_active_cell','usertext.label.details'})do entries[key]=nil end
local partial,restore=S.Activate(nil,entries)
check(T.Message('unsynced')=='Waiting for current Echo data from the server - automatic choices paused','missing reason entry shows its exact English')
check(T.CountText('run',2,3)=='2 / 3 rolled copies this run' and T.CountText('planned',2,3)==S.OPEN..'2 / 3 rolled copies planned'..S.CLOSE,'missing template entry: exact English; others stay translated')
check(T.Details('C1')=='Details: C1' and T.Message('throttled')==S.OPEN..'Waiting for the permitted network send rate'..S.CLOSE,'missing Details entry: exact English with the raw code')
local cells=T.DestinationFields({kind='savedBuild',slot=1,name='Qwyn',active=true})
check(cells[4].value=='Active in the game' and cells[4].label==S.OPEN..'State'..S.CLOSE,'missing cell entry: exact English beside translated labels')
restore()
-- Long mode (an expanded-language model): no error and every value shown.
local longSeam,restoreLong=S.Activate('long')
local shown=0
for _,entry in ipairs(corpus)do
 for _,v in ipairs(run(entry))do check(type(v)=='string' and v~='','long mode shows a value: '..entry.label);shown=shown+1 end
end
-- The doubled glossary (about 1150 bytes) is above the 1024-byte block limit,
-- so the seam refuses that pseudo entry and the exact English is shown.
check(T.GLOSSARY==english['usertext.body.glossary'] and T.RECORD_SCOPE:find('Bestbest',1,true)~=nil,'long mode: an over-limit block shows its exact English; a fitting text shows the expanded text')
restoreLong()
check(shown==totalValues,'long mode shows the same number of values')
print('l10n_ui_usertext: '..checks..' checks; '..familyCount..' family keys; '..totalValues..' values')
