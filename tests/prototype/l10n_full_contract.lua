-- Full UI localization contract (issues #143-#148, full visible-UI scope).
-- The bounded catalog extension of core/Localization.lua: the declaration and
-- entry cap (MAX_BASE_ENTRIES) for a complete measured UI catalog, the
-- "block" kind for long single-meaning paragraphs, and the "template" kind
-- whose named placeholders carry code-owned slot types ("count", the existing
-- known/unknown record, or "text", a code-supplied display value inserted
-- verbatim in one pass). The original "text" and "format" rules are kept
-- unchanged (tests/prototype/terminology.lua). Each fixture reloads the real
-- file with only its declaration block replaced, in memory. Synthetic offline
-- evidence; native glyph, font and layout behavior is NOT_RUN.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local L=assert(Nexus.Localization)
local U=L.UNAVAILABLE
local real,realData,realPacks=Nexus.Localization,Nexus.LocalizationEnglish,Nexus.LocalizationPacks

local source
do local f=assert(io.open('core/Localization.lua','rb'));source=f:read('*a');f:close() end
local OPEN,CLOSE='-- NEXUS-L10N-REGISTRY BEGIN','-- NEXUS-L10N-REGISTRY END'
local _,openEnd=source:find(OPEN,1,true)
if openEnd then openEnd=openEnd+#(source:match('^\r?\n',openEnd+1) or '') end
local closeStart=source:find('\n'..CLOSE,1,true)
check(openEnd and closeStart and openEnd<closeStart,'SETUP one declaration block')
local head,tail=source:sub(1,openEnd),source:sub(closeStart+1)

-- Loads the real file with `declarations` (key -> Lua literal) as its block,
-- `english` as the English base and `packs` as the optional packs.
local function load(declarations,english,packs)
 local lines={'local DECLARATIONS = {'}
 local keys={};for key in pairs(declarations) do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys) do lines[#lines+1]=('    ["%s"] = %s,'):format(key,declarations[key]) end
 lines[#lines+1]='}'
 local chunk=assert((loadstring or load)(head..table.concat(lines,'\n')..'\n'..tail,'=core/Localization.lua'))
 Nexus.LocalizationEnglish,Nexus.LocalizationPacks=english,packs
 local ok,err=pcall(chunk);local module=Nexus.Localization
 Nexus.Localization,Nexus.LocalizationEnglish,Nexus.LocalizationPacks=real,realData,realPacks
 assert(ok,err)
 return module
end
local TEXT='{kind = "text"}'
local BLOCK='{kind = "block"}'

-- 1. Cap: a complete measured UI catalog (thousands of meanings) fits a
-- bounded cap; one more fails closed exactly as the 64-entry pilot did.
check(type(L.MAX_BASE_ENTRIES)=='number' and L.MAX_BASE_ENTRIES==4096,'EXPECT the bounded full-UI cap is 4096 entries')
do
 local cap=L.MAX_BASE_ENTRIES
 local decl,eng={},{}
 for i=1,cap do local k='cap.entry_'..i;decl[k]=TEXT;eng[k]='Entry '..i end
 local full=load(decl,eng,nil)
 local b=full.Diagnostics().base
 check(b.present and b.accepted==cap and b.rejected==0 and not b.oversized and #full.Keys()==cap,'EXPECT exactly cap declared entries are admitted')
 check(full.Text('cap.entry_'..cap)=='Entry '..cap,'EXPECT the last entry at the cap resolves')
 eng['cap.entry_'..(cap+1)]='One more'
 local over=load(decl,eng,nil);b=over.Diagnostics().base
 check(b.oversized and b.accepted==0 and b.rejected==cap+1 and over.Text('cap.entry_1')==U,'GUARD cap+1 English entries fail closed')
 decl['cap.entry_'..(cap+1)]=TEXT;eng['cap.entry_'..(cap+1)]=nil
 local none=load(decl,eng,nil);b=none.Diagnostics().base
 check(not b.oversized and b.accepted==0 and b.undeclared==cap and #none.Keys()==0,'GUARD more than cap declarations declare nothing')
end

-- 2. Block kind: one meaning in several lines (LF only), at most 1024 bytes.
check(L.MAX_BLOCK_BYTES==1024,'EXPECT block limit is 1024 bytes')
do
 local para='First line of a paragraph.\nSecond line, with \195\169 and \208\150.\n\nAfter a blank line.'
 local long=string.rep('a',1023)..'\n'
 local decl={['help.body.sample']=BLOCK,['help.body.long']=BLOCK,['help.body.cr']=BLOCK,['help.body.pipe']=BLOCK,
  ['help.body.over']=BLOCK,['help.body.blank']=BLOCK,['help.label.one']=TEXT}
 local eng={['help.body.sample']=para,['help.body.long']=long,['help.body.cr']='A\r\nB',['help.body.pipe']='A|cffff0000B',
  ['help.body.over']=string.rep('b',1025),['help.body.blank']='\n \n',['help.label.one']='One line'}
 local packs={frFR={name='Fran\195\167ais',entries={['help.body.sample']='Premi\195\168re ligne.\nSeconde ligne.',
  ['help.body.long']='bad|pipe',['help.label.one']='Une\nligne'}}}
 local m=load(decl,eng,packs)
 local b=m.Diagnostics().base
 check(m.Kind('help.body.sample')=='block' and m.Resolve('help.body.sample')==para,'EXPECT a block keeps its exact bytes, LF included')
 check(m.Has('help.body.long') and #m.Resolve('help.body.long')==1024,'EXPECT a 1024-byte block is admitted')
 for _,k in ipairs({'help.body.cr','help.body.pipe','help.body.over','help.body.blank'}) do
  check(not m.Has(k),'GUARD block contract refuses '..k)
 end
 check(b.accepted==3 and b.rejected==4 and b.missingDeclared==4,'EXPECT block admission is counted like text')
 local t,s,r=m.Resolve('help.body.sample',{['help.body.sample']='Pack\nblock'})
 check(t=='Pack\nblock' and s=='candidate' and r==nil,'EXPECT a valid candidate block replaces the English block')
 t,s,r=m.Resolve('help.body.sample',{['help.body.sample']='Bad\rblock'})
 check(t==para and s=='base' and r=='invalid_candidate','GUARD an invalid candidate block falls back to English')
 t,s,r=m.Resolve('help.label.one',{['help.label.one']='Une\nligne'})
 check(t=='One line' and r=='invalid_candidate','GUARD a text key never admits a newline candidate')
 local row=m.Diagnostics().packs.rows[1]
 check(row and row.id=='frFR' and row.accepted==1 and row.rejected==2,'EXPECT pack copy uses the declared kind contract')
 check(m.InitializeActiveLanguage('frFR')=='frFR' and m.Text('help.body.sample')=='Premi\195\168re ligne.\nSeconde ligne.'
  and m.Text('help.body.long')==long and m.Text('help.label.one')=='One line','EXPECT active pack blocks with English fallback')
 check(select(3,m.Format('help.body.sample',{}))=='wrong_key_kind','GUARD a block is never formatted')
end

-- 3. Template kind: typed named slots, reorder, one pass, result limit.
check(L.MAX_TEMPLATE_RESULT_BYTES==2048 and L.MAX_SLOT_TEXT_BYTES==1024,'EXPECT template result and text slot bounds')
do
 local decl={
  ['orb.status.named']='{kind = "template", fields = {"name", "count"}, slots = {"text", "count"}, resultLimit = 300}',
  ['orb.status.small']='{kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 20}',
  ['help.body.lines']='{kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 600, lines = true}',
  ['bad.slot.type']='{kind = "template", fields = {"name"}, slots = {"number"}, resultLimit = 100}',
  ['bad.slot.count']='{kind = "template", fields = {"name", "count"}, slots = {"text"}, resultLimit = 100}',
  ['bad.result.limit']='{kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 4096}',
  ['bad.extra.field']='{kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 100, markup = true}',
  ['bad.lines.value']='{kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 100, lines = 1}',
  ['readout.charge_counts']='{fields = {"banish", "reroll", "freeze"}, kind = "format", slot = "count", resultLimit = 254}',
 }
 local eng={['orb.status.named']='{name} has {count} Echoes',['orb.status.small']='Hi {name}',
  ['help.body.lines']='Line one {name}\nLine two',['bad.slot.type']='X {name}',['bad.slot.count']='X {name} {count}',
  ['bad.result.limit']='X {name}',['bad.extra.field']='X {name}',['bad.lines.value']='X {name}',
  ['readout.charge_counts']='B:{banish} R:{reroll} F:{freeze}'}
 local packs={deDE={name='Deutsch',entries={['orb.status.named']='{count} Echos: {name}',['orb.status.small']='{name} {name}',
  ['help.body.lines']='Zeile {name}\nZwei'}}}
 local m=load(decl,eng,packs)
 local b=m.Diagnostics().base
 check(m.Kind('orb.status.named')=='template' and m.Kind('help.body.lines')=='template','EXPECT template kind is admitted')
 for _,k in ipairs({'bad.slot.type','bad.slot.count','bad.result.limit','bad.extra.field','bad.lines.value'}) do
  check(m.Kind(k)==nil,'GUARD malformed template declaration is left out: '..k)
 end
 check(b.accepted==4 and b.formatted==4 and b.undeclared==5,'EXPECT templates are counted as formatted entries')
 local args={name='Ash|cffff0000x|r {count}',count={known=true,value=0}}
 local t,s,r=m.Format('orb.status.named',args)
 check(t=='Ash|cffff0000x|r {count} has 0 Echoes' and s=='base' and r==nil,'EXPECT a text slot is inserted verbatim, once, never parsed again')
 t=m.Format('orb.status.named',{name='A',count={known=false}})
 check(t=='A has ? Echoes','EXPECT unknown count stays distinct from zero')
 t,s,r=m.Format('orb.status.named',{name='A',count=3})
 check(t==U and r=='invalid_arguments','GUARD a count slot still requires its typed record')
 t,s,r=m.Format('orb.status.named',{name=7,count={known=true,value=1}})
 check(t==U and r=='invalid_arguments','GUARD a text slot requires a string')
 t,s,r=m.Format('orb.status.named',{name=string.rep('n',1025),count={known=true,value=1}})
 check(t==U and r=='invalid_arguments','GUARD a text slot above 1024 bytes is refused')
 t,s,r=m.Format('orb.status.named',{name='A',count={known=true,value=1},extra='x'})
 check(t==U and r=='invalid_arguments','GUARD extra argument refused')
 t,s,r=m.Format('orb.status.small',{name=string.rep('n',30)})
 check(t==U and s=='unavailable' and r=='output_limit','GUARD English output above the declared limit is never cut')
 t,s,r=m.Format('orb.status.named',{name='A',count={known=true,value=2}},packs.deDE.entries)
 check(t=='2 Echos: A' and s=='candidate' and r==nil,'EXPECT a candidate may reorder typed slots')
 t,s,r=m.Format('orb.status.small',{name='A'},packs.deDE.entries)
 check(t=='Hi A' and s=='base' and r=='invalid_candidate','GUARD a repeated placeholder candidate falls back to English')
 t=m.Format('help.body.lines',{name='X'})
 check(t=='Line one X\nLine two','EXPECT a lines template keeps its LF')
 check(m.Diagnostics().packs.rows[1].accepted==2,'EXPECT pack templates are copied only when they compile')
 check(m.InitializeActiveLanguage('deDE')=='deDE' and m.Format('help.body.lines',{name='X'})=='Zeile X\nZwei'
  and m.Format('orb.status.small',{name='A'})=='Hi A','EXPECT active pack templates with English fallback')
 check(m.Format('readout.charge_counts',{banish={known=true,value=1},reroll={known=false},freeze={known=true,value=0}})=='B:1 R:? F:0','GUARD the charge format is unchanged beside templates')
 check(select(3,m.Text('orb.status.named'))=='format_requires_arguments','GUARD a template never resolves as static text')
end

-- 4. Count helper: known whole numbers, otherwise unknown; never zero-filled.
check(type(L.Count)=='function','EXPECT Count helper')
do
 local k,u,f=L.Count(4),L.Count(nil),L.Count(1.5)
 check(k.known==true and k.value==4,'EXPECT known count record')
 check(u.known==false and u.value==nil and f.known==false and L.Count(-1).known==false and L.Count(0/0).known==false,'EXPECT non-count values are unknown, not zero')
 check(L.Count(0).known==true and L.Count(0).value==0,'EXPECT zero is a known count')
end

-- 5. Display phrasebook (full-UI remainder): a producer keeps its raw
-- English (compared, recorded, sent); the display boundary maps that exact
-- English, or the producer's own format string, to a reviewed key. Captured
-- %d values become count slots, %s values text slots; an unmatched or
-- unavailable result shows the raw text unchanged. Pure; never raises.
check(type(L.Phrase)=='function' and type(L.PhraseBook)=='function','EXPECT phrasebook helpers')
do
 local decl={
  ['orb.status.plain']=TEXT,
  ['orb.status.counted']='{kind = "template", fields = {"have", "limit"}, slots = {"count", "count"}, resultLimit = 300}',
  ['orb.status.named']='{kind = "template", fields = {"name", "count"}, slots = {"text", "count"}, resultLimit = 300}',
  ['orb.status.kept']=TEXT,['orb.status.done']=TEXT,
  ['orb.status.pair']='{kind = "template", fields = {"name", "destination"}, slots = {"text", "text"}, resultLimit = 300}',
 }
 local eng={['orb.status.plain']='Session interrupted.',['orb.status.kept']=' Kept.',['orb.status.done']='Done.',
  ['orb.status.pair']="assigned '{name}' to {destination}.",
  ['orb.status.counted']='It lists {have} occupied records, more than the {limit} allowed.',
  ['orb.status.named']='{name} needs {count} more copies.'}
 local packs={frFR={name='Fran\195\167ais',entries={['orb.status.plain']='Session interrompue.',['orb.status.kept']=' Gard\195\169.',['orb.status.done']='Fini.',
  ['orb.status.pair']='DEST={destination};NAME={name}',
  ['orb.status.counted']='{limit} max, {have} vus.',['orb.status.named']='{name} : encore {count}.'}}}
 local m=load(decl,eng,packs)
 local book=m.PhraseBook({
  exact={['Session interrupted.']='orb.status.plain'},
  formats={
   {format='It lists %d occupied records, more than the %d allowed.',key='orb.status.counted',fields={'have','limit'}},
   {format='%s needs %d more copies.',key='orb.status.named',fields={'name','count'}},
  }})
 check(book.size==3,'EXPECT the book compiles every entry')
 local t,hit=m.Phrase('Session interrupted.',book)
 check(t=='Session interrupted.' and hit==true,'EXPECT English session: exact entry resolves to the same English')
 t,hit=m.Phrase('It lists 7 occupied records, more than the 6 allowed.',book)
 check(t=='It lists 7 occupied records, more than the 6 allowed.' and hit,'EXPECT a format entry renders its exact English')
 t,hit=m.Phrase('Something else entirely.',book)
 check(t=='Something else entirely.' and hit==false,'GUARD unmatched raw text is shown unchanged')
 t=m.Phrase(nil,book);check(t==nil,'GUARD nil stays nil')
 check(m.InitializeActiveLanguage('frFR')=='frFR','SETUP frFR active')
 t,hit=m.Phrase('Session interrupted.',book)
 check(t=='Session interrompue.' and hit,'EXPECT exact entry shows the active language')
 t=m.Phrase('It lists 7 occupied records, more than the 6 allowed.',book)
 check(t=='6 max, 7 vus.','EXPECT format captures become typed slots in the translation order')
 t=m.Phrase('Ash|cffff0000Red|r needs 3 more copies.',book)
 check(t=='Ash|cffff0000Red|r : encore 3.','EXPECT a text capture is inserted verbatim (escaped data kept)')
 t=m.Phrase('It lists x occupied records, more than the 6 allowed.',book)
 check(t=='It lists x occupied records, more than the 6 allowed.','GUARD a non-number never matches a %d slot')
 t=m.Phrase('It lists 7 occupied records, more than the 6 allowed. Extra',book)
 check(t=='It lists 7 occupied records, more than the 6 allowed. Extra','GUARD formats are anchored: trailing text is not dropped')
 local bad=m.PhraseBook({formats={{format='%q oops',key='orb.status.plain',fields={'x'}},{format='%d only',key='orb.status.counted',fields={'have','limit'}}}})
 check(bad.size==0,'GUARD unsupported conversions and field-count mismatches are left out')
 -- A field may name its own exact lookup (a finite set of code-owned values):
 -- only those exact values are shown through their keys; any other value
 -- (a player-named source) stays verbatim.
 local nb=m.PhraseBook({formats={{format='%s needs %d more copies.',key='orb.status.named',fields={'name','count'},
  nested={name={['Session interrupted.']='orb.status.plain'}}}}})
 check(m.Phrase('Session interrupted. needs 2 more copies.',nb)=='Session interrompue. : encore 2.','EXPECT a nested exact value is shown in the active language')
 check(m.Phrase('Plan A needs 2 more copies.',nb)=='Plan A : encore 2.','GUARD a value outside the nested map stays verbatim')
 -- nested = true: the captured value is shown through the same book.
 local rb=m.PhraseBook({exact={['Session interrupted.']='orb.status.plain'},
  formats={{format='%s needs %d more copies.',key='orb.status.named',fields={'name','count'},nested={name=true}}}})
 check(m.Phrase('Session interrupted. needs 4 more copies.',rb)=='Session interrompue. : encore 4.','EXPECT a nested=true value goes through the book')
 -- segments = true: a text made only of known units (single spaces between
 -- them kept) is shown unit by unit; any uncovered byte leaves it raw.
 local sb=m.PhraseBook({segments=true,exact={['Session interrupted.']='orb.status.plain',
  [' Kept.']='orb.status.kept',['Done.']='orb.status.done'}})
 check(sb.segments==true,'EXPECT a segment book')
 check(m.Phrase('Session interrupted. Kept.',sb)=='Session interrompue. Gard\195\169.','EXPECT a leading-space unit joins')
 check(m.Phrase('Session interrupted. Done.',sb)=='Session interrompue. Fini.','EXPECT a single space between units is kept')
 check(m.Phrase('Session interrupted. Unknown tail.',sb)=='Session interrupted. Unknown tail.','GUARD partial coverage shows the raw text unchanged')
 check(m.Phrase('Session interrupted.  Done.',sb)=='Session interrupted.  Done.','GUARD only one separating space is allowed')
 -- R5 (Source86): two text slots are recaptured only when the English has
 -- exactly one split; a value holding the format's own delimiter makes it
 -- ambiguous, and the raw text is kept rather than a guessed split.
 local pb=m.PhraseBook({formats={{format="assigned '%s' to %s.",key='orb.status.pair',fields={'name','destination'}}}})
 check(m.Phrase("assigned 'Alpha' to My Build.",pb)=='DEST=My Build;NAME=Alpha','EXPECT a unique split is recaptured and reordered')
 check(m.Phrase("assigned 'O'Brien' to My Build.",pb)=="DEST=My Build;NAME=O'Brien",'EXPECT an apostrophe alone keeps a unique split')
 local amb="assigned 'A' to B' to My Build."
 local shown,known=m.Phrase(amb,pb)
 check(shown==amb and known==false,'GUARD a delimiter inside a value: ambiguous split, raw text kept')
 shown,known=m.Phrase("assigned 'Alpha' to Build' to C.",pb)
 check(shown=="assigned 'Alpha' to Build' to C." and known==false,'GUARD a delimiter inside the other value: raw text kept')
end

-- Source16 (global v6): the declared contracts of the real catalog. Fourteen
-- templates are lines = true with result limit 2048, two static texts are
-- blocks, the offer paragraph's three keys each fit raw 1024 and, with the
-- largest text slot (1024 bytes), render within 2048. The catalog stays at or
-- below the unchanged 4096 cap.
do
 local function Declared(key)
  return source:match('\n    %["'..key:gsub('%.','%%.')..'"%] = (%b{}),')
 end
 for _,key in ipairs({'orb.runtime.blocked_submitted_unresolved','orb.runtime.blocked_unattributable_next','editor.notify.already_created',
  'editor.notify.assignment_changed_open','editor.notify.destination_empty','editor.notify.host_error',
  'editor.notify.import_overflow_unassigned','editor.notify.lock_design_collisions','editor.notify.lock_slots_unstated',
  'editor.notify.saved_session_only','editor.notify.saved_unassigned_opened','editor.notify.server_slot_stale',
  'editor.notify.server_slot_stale_missing','editor.notify.lock_slots_occupied','editor.notify.maybe_sent'}) do
  local d=Declared(key) or ''
  check(d:find('kind = "template"',1,true) and d:find('resultLimit = 2048',1,true) and d:find('lines = true',1,true),'S16 contract: '..key..' is a lines template, result 2048: '..d)
 end
 for _,key in ipairs({'orb.runtime.recovery_needs_fresh_reply','orb.status.headline_paused_continue','orb.recovery.offer_open_proposed_exits',
  'orb.recovery.offer_open_proposed_route'}) do
  check(Declared(key)=='{kind = "block"}','S16 contract: '..key..' is a block: '..tostring(Declared(key)))
 end
 check(Declared('editor.reason.every_saved_build_already_holds_a_plan_this')=='{kind = "text"}','S16 contract: RU-18 keeps its text contract (justified, fits 256)')
 local english=Nexus.LocalizationEnglish
 local n=0;for _ in pairs(english) do n=n+1 end
 check(n<=L.MAX_BASE_ENTRIES and L.MAX_BASE_ENTRIES==4096,'S16 contract: the catalog ('..n..') stays within the unchanged 4096 cap')
 local seg1,seg2,seg3=english['orb.recovery.offer_open_proposed'],english['orb.recovery.offer_open_proposed_exits'],english['orb.recovery.offer_open_proposed_route']
 check(#seg1<=1024 and #seg2<=1024 and #seg3<=1024,'S16 contract: each offer paragraph is within raw 1024')
 check(1024-#'{echo}'+1024<=2048,'S16 contract: paragraph 1 renders within 2048 with a 1024-byte Echo slot')
 local shown,source1=L.Format('orb.recovery.offer_open_proposed',{echo=string.rep('e',1024)})
 check(source1~='unavailable' and #shown<=2048,'S16 contract: paragraph 1 with a 1024-byte Echo name renders ('..#shown..' bytes)')
end

check(Nexus.Localization==real and Nexus.LocalizationEnglish==realData and Nexus.LocalizationPacks==realPacks,'GUARD real seam restored')
print('l10n_full_contract: '..checks..' checks')
