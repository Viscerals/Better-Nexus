-- Full-UI localization, global v4 contract amendment: nine long paragraphs
-- are complete translations, not 256-byte cuts. Six static texts are blocks
-- (at most 1024 bytes) and three templates have lines = true (a 1024-byte
-- raw template, result at most 2048 bytes). Driven through their real
-- receivers after the real TOC boot (format5_support):
--  1. Long pseudo pack (every letter run doubled, so each of the nine is
--     above 256 bytes and within its bound): each receiver shows the whole
--     paragraph: the extra-copies list note (wrapped, scrolled), the Language
--     menu and Settings rows (one row per line) and the saved-choice chat
--     line, the Details hover, the size row hover, the Orb mini panel hover,
--     the Auto line of a save confirmation, the context-changed popup and
--     the import chat lines. Showing, hovering and reading write no saved
--     data, send nothing and act on nothing.
--  2. Invalid (above the bound, or a "|") and missing entries show the exact
--     English.
--  3. English: the exact English bytes (eight unchanged, the language scope
--     note as amended in v4) at the same receivers.
-- Synthetic offline evidence only: no native font, glyph, layout or client
-- popup claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end

local NINE={'panel.body.extra_list_note','panel.note.language_scope','panel.tooltip.details_body','panel.tooltip.size_explained',
 'orb.tooltip.mini_missing','editor.popup.auto_replace_paused','editor.popup.context_changed','editor.chat.imported_draft_many',
 'editor.chat.imported_draft_one',
 -- R5 (Source86): the tenth paragraph, the unpaused Auto line (same contract move).
 'editor.popup.auto_replace'}
-- The v2 English bytes of the eight unchanged paragraphs, and the v4 scope note.
local ENGLISH={
 ['panel.body.extra_list_note']="Rolled copies above your exact Wishlist targets, including unrequested or different-quality copies. This is a comparison, not a delete action. Locked copies protected by this Saved Build are never listed here.",
 ['panel.note.language_scope']="Nexus shows its own text in the selected language where a draft translation exists; text without one stays in English.\nGame names, player names and diagnostic data are not translated.\nTranslations are drafts pending fluent and native review.",
 ['panel.tooltip.details_body']="Shows or hides the details under the bar: still needed, missing tomes, extra copies and locked targets, with the Echo names behind them. It changes only what this panel shows; the counts and your build stay the same.",
 ['panel.tooltip.size_explained']="Makes this panel larger or smaller, 50% to 150%. Other Nexus windows, the Wishlist overlay, the game's difficulty HUD and your UI scale keep their own size. A screen too small for the size shows it smaller until it fits.",
 ['orb.tooltip.mini_missing']="Copies, not Echo families: the rolled target copies this run still needed at its latest check. Locked targets are not counted, because Orbs cannot change locked Echoes. Unavailable is not 0, and 0 does not mean the whole build is complete.",
 ['editor.popup.auto_replace_paused']="Auto is ON (paused at its last update: {reason}; it acts again when that clears): when {label} is active and a finished run at level 80 passes Auto's save checks, Nexus may replace that Saved Build with the run; this save can make Auto check again.",
 ['editor.popup.context_changed']="The character or selected Saved Build changed while your Plan draft was hidden. Discard draft deletes that unsaved draft and opens Plan for the current character and Saved Build, without it. Keep draft leaves it set aside as it is.",
 ['editor.chat.imported_draft_many']="imported {count} Echo entries as new wishlist '{name}'. Review this draft; Create & assign saves it and assigns it to the loadout shown by the editor, Create unassigned saves it without an assignment.",
 ['editor.chat.imported_draft_one']="imported {count} Echo entry as new wishlist '{name}'. Review this draft; Create & assign saves it and assigns it to the loadout shown by the editor, Create unassigned saves it without an assignment.",
 ['editor.popup.auto_replace']="Auto is ON: when {label} is active and a finished run at level 80 passes Auto's save checks, Nexus may replace that Saved Build with the run; this save can make Auto check again.",
}
local BOUND={['editor.popup.auto_replace_paused']=1024,['editor.popup.auto_replace']=1024,['editor.chat.imported_draft_many']=1024,['editor.chat.imported_draft_one']=1024}

local H
local function Boot(mode,entries)
 if mode~='english' then S.InstallBootHook(mode,entries) end
 H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
 for _=1,20 do H.Advance(.05,.05) end
 Nexus.Panel.Show()
 return H
end
local function Fill(template,args)
 return (template:gsub('{(%l[%w_]*)}',function(name) return tostring(args[name]) end))
end
local function Has(lines,text)
 for _,line in ipairs(lines) do if line==text then return true end end
 return false
end
local function Lines(text)
 local out={}
 for line in (text..'\n'):gmatch('([^\n]*)\n') do if line~='' then out[#out+1]=line end end
 return out
end
local function Up(fn,name)
 for i=1,200 do
  local n,v=debug.getupvalue(fn,i)
  if n==nil then return nil end
  if n==name then return v end
 end
end
local function Renderer()
 for _,fn in pairs(Nexus.WishlistEditor) do
  if type(fn)=='function' then
   local r=Up(fn,'wishlistRenderer')
   if r then return r end
  end
 end
end
local function Snapshot()
 return F.Serialize(NexusDB)..'|'..#H.sent..'|'..#H.actions
end
-- Each receiver with the text it should show for key (the pack entry, or
-- the English). want(key) gives that text.
local function Receivers(want,tag)
 local P=Nexus.Panel
 -- 1. The extra-copies list note: the whole paragraph, wrapped in the
 -- scrolled child above the names.
 P.ShowExtraList()
 local list=P._extraList
 check(list and list:IsShown() and list.note:GetText()==want('panel.body.extra_list_note'),
  tag..': the extra-copies list note is the whole paragraph: '..tostring(list and list.note:GetText()))
 check(list.note:GetParent()==list.child and list.child:GetHeight()>=list.note:GetHeight(),tag..': the note sits in the scrolled child, which holds its height')
 list:Hide()
 -- 2. The scope note: one Language menu row per line, in order; the Settings
 -- window's language rows; the saved-choice chat line joins the lines.
 local lines=Lines(want('panel.note.language_scope'))
 check(#lines==3,tag..': the scope note has its three lines')
 local rows=P.LanguageMenuItems(function(f) return f end)
 local at
 for i,row in ipairs(rows) do if row.text==lines[1] then at=i end end
 check(at and rows[at+1].text==lines[2] and rows[at+2].text==lines[3] and rows[at].disabled and rows[at+2].notCheckable,
  tag..': the Language menu shows each scope line as its own disabled row')
 local settings={}
 for _,row in ipairs(Nexus.SettingsWindow.Rows('language')) do settings[#settings+1]=row.text end
 check(Has(settings,lines[1]) and Has(settings,lines[2]) and Has(settings,lines[3]),tag..': the Settings window lists the same three rows')
 local said=P.LanguageResultText({state='saved',pending=true,id='frFR'})
 check(said:find(table.concat(lines,' '),1,true)~=nil and not said:find('\n',1,true),tag..': the saved-choice line says the whole note on one line')
 -- 3. The Details hover.
 local details=P.EnsurePlayWidgets().details
 check(Has(S.CaptureTooltip(details:GetScript('OnEnter'),details),want('panel.tooltip.details_body')),tag..': the Details hover carries the whole paragraph')
 -- 4. The size row's hover.
 check(P.PanelSizeMenuItem().tooltipText==want('panel.tooltip.size_explained'),tag..': the size row hover carries the whole paragraph')
 -- 5. The Orb mini panel's missing-line hover.
 local mini=Nexus.OrbPanel.ShowMini()
 check(Has(S.CaptureTooltip(mini.missingHit:GetScript('OnEnter'),mini.missingHit),want('orb.tooltip.mini_missing')),
  tag..': the Orb mini hover carries the whole paragraph')
 Nexus.OrbPanel.HideMini()
 -- 6. The Auto line of a save confirmation (Auto ON, held; only the Auto
 -- facts the renderer reads are supplied).
 local R=assert(Renderer(),'the editor renderer')
 local on,held,settingsFn=R.AutoIsOn,R.AutoHeldReason,Nexus.Store.Settings
 R.AutoIsOn=function() return true end
 R.AutoHeldReason=function() return 'Qv held reason' end
 -- A copy: the stub must not write the live settings table.
 Nexus.Store.Settings=function() local s={};for k,v in pairs(settingsFn()) do s[k]=v end;s.autoSave=true;return s end
 local line=R.AutoConsentLine('Qv Build')
 R.AutoIsOn,R.AutoHeldReason,Nexus.Store.Settings=on,held,settingsFn
 local wantLine=Fill(want('editor.popup.auto_replace_paused'),{reason='Qv held reason',label='Qv Build'})
 check(line:sub(1,#wantLine)==wantLine,tag..': the confirmation Auto line is the whole paragraph with its slots: '..line)
 -- 6b. Unpaused (the tenth paragraph): the destination label the
 -- confirmation itself composes (M.DestinationLabel), a long player name.
 local label=R.DestinationLabel({kind='savedBuild',slot=2,name=string.rep('N',600)..' Qv'})
 R.AutoIsOn=function() return true end
 R.AutoHeldReason=function() return nil end
 Nexus.Store.Settings=function() local s={};for k,v in pairs(settingsFn()) do s[k]=v end;s.autoSave=true;return s end
 local unpaused=R.AutoConsentLine(label)
 R.AutoIsOn,R.AutoHeldReason,Nexus.Store.Settings=on,held,settingsFn
 local wantUnpaused=Fill(want('editor.popup.auto_replace'),{label=label})
 check(#label>600 and unpaused:sub(1,#wantUnpaused)==wantUnpaused and unpaused:find('600',1,true)==nil,
  tag..': the unpaused Auto line is the whole paragraph with the whole composed label: '..unpaused:sub(1,160))
 -- 7. The context-changed popup.
 local dialog=StaticPopupDialogs.NEXUS_WORKSPACE_CONTEXT_CHANGED
 check(dialog.text==want('editor.popup.context_changed'),tag..': the context-changed popup says the whole paragraph')
 return wantLine
end
local function ImportLines(want,tag)
 local code='EBH1:200001.1.1,200002.2.1,200003.3.1:MAGE:Untyped'
 local chat=S.CaptureChat(function() Nexus.WishlistEditor.ImportEBH1String(code,'Qv Import') end)
 local many='|cff4dff80Nexus:|r '..Fill(want('editor.chat.imported_draft_many'),{count=3,name='Qv Import'})
 check(Has(chat,many),tag..': the import chat line says the whole paragraph: '..table.concat(chat,' | '))
 if NexusEditorFrame then NexusEditorFrame:Hide() end
 code='EBH1:200004.1.1:MAGE:Untyped'
 chat=S.CaptureChat(function() Nexus.WishlistEditor.ImportEBH1String(code,'Qv One') end)
 local one='|cff4dff80Nexus:|r '..Fill(want('editor.chat.imported_draft_one'),{count=1,name='Qv One'})
 check(Has(chat,one),tag..': the one-entry import chat line says the whole paragraph: '..table.concat(chat,' | '))
 if NexusEditorFrame then NexusEditorFrame:Hide() end
 return #many,#one
end

------------------------------------------------------------------------------
-- 1. Long pseudo pack: complete paragraphs above 256 bytes
------------------------------------------------------------------------------
local entries=S.PseudoEntries('long')
for _,key in ipairs(NINE) do
 local v=entries[key]
 check(#v>256 and #v<=(BOUND[key] or 1024),'long entry of '..key..' is above 256 bytes and within its bound: '..#v)
end
Boot('long',entries)
check(Nexus.Localization.ActiveLanguage()=='frFR','pseudo pack active')
for _,key in ipairs(NINE) do
 check(Nexus.Localization.Kind(key)==(BOUND[key] and 'template' or 'block'),'v4 contract kind of '..key)
end
local before=Snapshot()
local auto=Receivers(function(key) return entries[key] end,'long')
check(#auto>256,'the rendered Auto line is above 256 bytes: '..#auto)
check(Snapshot()==before,'showing, hovering and reading the nine write nothing, send nothing and act on nothing')
local sent0,acted0=#H.sent,#H.actions
local many,one=ImportLines(function(key) return entries[key] end,'long')
check(many>256 and one>256,'the rendered import lines are above 256 bytes: '..many..'/'..one)
check(#H.sent==sent0 and #H.actions==acted0,'the imports send nothing and run no game action')

------------------------------------------------------------------------------
-- 2. Invalid and missing entries fall back to the exact English
------------------------------------------------------------------------------
local bad=S.PseudoEntries('long')
for i,key in ipairs(NINE) do
 if i%3==0 then bad[key]=nil
 elseif i%3==1 then bad[key]=string.rep('Wort ',210)..(BOUND[key] and '{count}{name}{reason}{label}' or '')
 else bad[key]=S.OPEN..'mit | Strich'..S.CLOSE end
end
check(#bad['panel.body.extra_list_note']>1024,'an invalid entry above the 1024-byte bound is offered')
Boot('wrap',bad)
for _,key in ipairs(NINE) do
 local text,source
 if BOUND[key] then
  local fields={count=Nexus.Localization.Count(2),name='Qv',reason='Qv',label='Qv'}
  local args={}
  for _,f in ipairs(key:find('imported') and {'count','name'} or key=='editor.popup.auto_replace' and {'label'} or {'reason','label'}) do args[f]=fields[f] end
  text,source=Nexus.Localization.Format(key,args)
  check(source=='base' and text==Fill(ENGLISH[key],{count=2,name='Qv',reason='Qv',label='Qv'}),'fallback: '..key..' shows its exact English')
 else
  text,source=Nexus.Localization.Text(key)
  check(source=='base' and text==ENGLISH[key],'fallback: '..key..' shows its exact English')
 end
end
Receivers(function(key) return ENGLISH[key] end,'fallback')

-- The tenth paragraph at its bounds, through the confirmation's own
-- AutoConsentLine (Auto ON, not held; only the Auto facts are supplied).
-- A label is a text slot of at most 1024 bytes and a translation at most
-- 1024 bytes, so a result is at most 2041 bytes: resultLimit 2048 suffices.
-- A composed label above the slot bound (a 1024-byte name inside "Saved
-- Build '...' (slot N)") cannot be a slot: the exact English sentence with
-- the whole label is shown, never the seam's "cannot be shown" status.
do
 local big=S.PseudoEntries()
 local pad=1020-#S.OPEN-#S.CLOSE-#'{label}'
 big['editor.popup.auto_replace']=S.OPEN..string.rep('L',pad)..'{label}'..S.CLOSE
 check(#big['editor.popup.auto_replace']==1020,'a valid translation near the 1024-byte raw bound')
 Boot('wrap',big)
 local R=assert(Renderer(),'the editor renderer')
 local on,held,settingsFn=R.AutoIsOn,R.AutoHeldReason,Nexus.Store.Settings
 R.AutoIsOn=function() return true end
 R.AutoHeldReason=function() return nil end
 Nexus.Store.Settings=function() local s={};for k,v in pairs(settingsFn()) do s[k]=v end;s.autoSave=true;return s end
 local over=R.DestinationLabel({kind='savedBuild',slot=2,name=string.rep('N',1024)})
 local line=R.AutoConsentLine(over)
 local english=Fill(ENGLISH['editor.popup.auto_replace'],{label=over})
 check(#over>1024 and line:sub(1,#english)==english,'a label above the 1024-byte slot: the exact English sentence with the whole label ('..#over..' bytes): '..line:sub(1,80))
 local fits=string.rep('N',1024)
 line=R.AutoConsentLine(fits)
 local want=Fill(big['editor.popup.auto_replace'],{label=fits})
 check(#want==2037 and line:sub(1,#want)==want,'a 1024-byte label with a 1020-byte translation: the whole translation ('..#want..' bytes)')
 R.AutoIsOn,R.AutoHeldReason,Nexus.Store.Settings=on,held,settingsFn
end

------------------------------------------------------------------------------
-- 3. English: the exact bytes at the same receivers
------------------------------------------------------------------------------
Boot('english')
check(Nexus.Localization.ActiveLanguage()=='enUS','English session')
local english=S.English()
for _,key in ipairs(NINE) do check(english[key]==ENGLISH[key],'English bytes of '..key) end
before=Snapshot()
Receivers(function(key) return ENGLISH[key] end,'English')
check(Snapshot()==before,'English: showing, hovering and reading write nothing')
ImportLines(function(key) return ENGLISH[key] end,'English')

------------------------------------------------------------------------------
-- 4. Source16 (global v6): RU source-fit contracts. Fourteen one-line
-- templates move to lines = true (raw template up to 1024 bytes, result up to
-- 2048): a complete candidate above 256 bytes is shown whole by its real
-- presentation (the Orb book, the Wishlist chat phrasebook, the controller's
-- typed notices), still one line; an over-bound candidate shows the exact
-- English. maybe_sent keeps its existing lines = true contract (control).
------------------------------------------------------------------------------
local RU_LINES={'orb.runtime.blocked_submitted_unresolved','orb.runtime.blocked_unattributable_next','editor.notify.already_created',
 'editor.notify.assignment_changed_open','editor.notify.destination_empty','editor.notify.host_error',
 'editor.notify.import_overflow_unassigned','editor.notify.lock_design_collisions','editor.notify.lock_slots_unstated',
 'editor.notify.saved_session_only','editor.notify.saved_unassigned_opened','editor.notify.server_slot_stale',
 'editor.notify.server_slot_stale_missing','editor.notify.lock_slots_occupied'}
local RU_ARGS={
 ['orb.runtime.blocked_submitted_unresolved']={subject='Ordinary rolling'},
 ['orb.runtime.blocked_unattributable_next']={subject='A new Orb run',next_step='Stop this Orb run first, then open'},
 ['editor.notify.already_created']={name="Qv {Plan} 100%"},
 ['editor.notify.assignment_changed_open']={destination="Saved Build 2"},
 ['editor.notify.destination_empty']={slot='3'},
 ['editor.notify.host_error']={name="Qv {Plan} 100%"},
 ['editor.notify.import_overflow_unassigned']={max=79,count=4},
 ['editor.notify.lock_design_collisions']={count=2},
 ['editor.notify.lock_slots_unstated']={max=6},
 ['editor.notify.saved_session_only']={count=12},
 ['editor.notify.saved_unassigned_opened']={name="Qv {Plan} 100%"},
 ['editor.notify.server_slot_stale']={slot='4'},
 ['editor.notify.server_slot_stale_missing']={slot='4'},
 ['editor.notify.lock_slots_occupied']={count=6},
 ['editor.notify.maybe_sent']={name="Qv {Plan} 100%"},
}
local TYPED={['editor.notify.already_created']=true,['editor.notify.host_error']=true,['editor.notify.saved_unassigned_opened']=true,
 ['editor.notify.assignment_changed_open']=true,['editor.notify.maybe_sent']=true}
local NOTIFY_TAG='|cffff9040Nexus:|r '
local function LongCandidate(english)
 local text=S.OPEN..english..' '..string.rep('complete facts kept ',16)..S.CLOSE
 assert(#text>256 and #text<=1024,'SETUP a long candidate within the bound')
 return text
end
-- What the real presentation shows for `key` (raw producer English filled
-- from the same values; the presentation reads only the raw text, or the
-- controller's typed record for the name-bearing notices).
local function Present(key,english)
 local args=RU_ARGS[key]
 local raw=Fill(english,args)
 if key:sub(1,4)=='orb.' then return (Nexus.OrbPanel.Phrase(raw)),raw end
 local controller=Nexus.WishlistInternals and Nexus.WishlistInternals.Controller
 if TYPED[key] then
  local typed={key=key,args={}}
  for k,v in pairs(args) do typed.args[k]=v end
  return controller.SayTyped(NOTIFY_TAG..raw,typed),raw
 end
 return (controller.NotifyPhrase(NOTIFY_TAG..raw)),raw
end
local EN4=S.English()
do
 local entries=S.PseudoEntries()
 for _,key in ipairs(RU_LINES) do entries[key]=LongCandidate(EN4[key]) end
 entries['editor.notify.maybe_sent']=LongCandidate(EN4['editor.notify.maybe_sent'])
 Boot('wrap',entries)
 local before={db=F.Serialize(NexusDB),legacy=F.Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions}
 for _,key in ipairs(RU_LINES) do
  local shown=Present(key,EN4[key])
  local args={}
  for k,v in pairs(RU_ARGS[key]) do args[k]=v end
  if key:sub(1,4)=='orb.' then
   args.subject=S.OPEN..args.subject..S.CLOSE
   if args.next_step then args.next_step=S.OPEN..args.next_step..S.CLOSE end
  end
  local want=(key:sub(1,4)=='orb.' and '' or NOTIFY_TAG)..Fill(entries[key],args)
  check(shown==want and #shown>256+#NOTIFY_TAG and not shown:find('\n',1,true),'S16 RU lines: '..key..' shows its complete candidate above 256 bytes on one line: '..tostring(shown):sub(1,120))
 end
 local key='editor.notify.maybe_sent'
 local shown=Present(key,EN4[key])
 check(shown==NOTIFY_TAG..Fill(entries[key],RU_ARGS[key]),'S16 RU control: maybe_sent keeps its lines contract and its raw name: '..tostring(shown):sub(1,120))
 local after={db=F.Serialize(NexusDB),legacy=F.Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions}
 for k,v in pairs(before) do check(after[k]==v,'S16 RU lines: presenting is passive: '..k) end
end
do
 local entries=S.PseudoEntries()
 for _,key in ipairs(RU_LINES) do entries[key]=S.OPEN..EN4[key]..string.rep(' x',520)..S.CLOSE end
 Boot('wrap',entries)
 for _,key in ipairs(RU_LINES) do
  local shown,raw=Present(key,EN4[key])
  check(#entries[key]>1024 and not shown:find(' x x x',1,true),'S16 RU lines: an over-bound '..key..' candidate is not shown: '..tostring(shown):sub(1,100))
  if key:sub(1,4)=='orb.' then
   local tail=raw:match('.*(/nexus orbs.*)$')
   check(shown:find(tail,1,true)~=nil,'S16 RU lines: '..key..' over-bound keeps the exact English sentence: '..tostring(shown):sub(1,100))
  else
   check(shown==NOTIFY_TAG..raw,'S16 RU lines: '..key..' over-bound shows the exact English: '..tostring(shown):sub(1,100))
  end
 end
end
do
 Boot('english')
 for _,key in ipairs(RU_LINES) do
  local shown,raw=Present(key,EN4[key])
  check(shown==(key:sub(1,4)=='orb.' and '' or NOTIFY_TAG)..raw,'S16 RU English: '..key..' is the exact English: '..tostring(shown):sub(1,100))
 end
end

print('l10n_long_paragraphs: '..checks..' checks')
