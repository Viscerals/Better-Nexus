-- Issue #25 sub-defect, regression-first: a copy page that the display
-- validator refuses is shown blank, and nothing says so. ui/LogViewer.lua
-- InertCopyText returns "" when Identity.DisplaySafeText refuses the page (a
-- TAB or another control character, invalid UTF-8, a combining or invisible
-- mark), while RenderCopyPage still shows the ordinary "Page i/N | ... | copy
-- pages in order" status.
-- Healthy behaviour (EXPECT, fails at 8eb6a3a): such a page is not blank; the
-- page area itself says that the page is not shown, and the viewer says why
-- (in the page area or the status line); it says so again when the reader
-- comes back to that page.
-- Unchanged (GUARD, holds at 8eb6a3a): the validator still refuses these
-- texts (no validation policy change); no text of the refused page or of an
-- earlier page is shown in its place (no partial, sanitized or escaped copy:
-- the display inverse stays "||" -> "|"); the complete provider text is kept
-- (bytes and page count); the status line still shows the page position; both
-- page buttons stay usable on the refused page, and the ordinary pages around
-- it are shown exactly, every "|" doubled and nothing else changed, with the
-- copy-in-order instruction; ordinary text with structural pipes and adjacent
-- empty fields is unchanged; page navigation sends nothing; no game action.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, the real LogViewer window, edit box, status line and page
-- buttons; the provider is set through the public LogViewer.Init seam, as
-- diagnostics.lua does. Artificial texts only. Every check reads the offline
-- edit box (GetText): nothing here shows what native Ctrl-C copies (raw or
-- rendered "||"), and no clipboard claim is made; issue #25 stays open on
-- that native evidence. Output is printable ASCII: other bytes print as \ddd.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('triage_copy_refusal')
local LV,ID=assert(Nexus.LogViewer),assert(Nexus.Identity)
local actions0,sent0=#H.actions,#H.sent

-- Printable ASCII form of a value for the report: every byte outside
-- 0x20-0x7E as \ddd; long text is cut, with its length.
local function Ascii(v,limit)
 local s=V.printable(v);limit=limit or 160
 local out=s:sub(1,limit):gsub('[^\32-\126]',function(c) return string.format('\\%03d',c:byte()) end)
 if #s>limit then out=out..'...('..#s..' bytes)' end
 return out
end

local PAGE=tonumber(LV.PageInfo().pageBytes)
C.setup(PAGE~=nil and PAGE>=1000,'fixture: the copy page size is known',PAGE)
PAGE=PAGE or 16000
local calls,current=0,''
LV.Init(function() calls=calls+1;return current end)
local function Info() return LV.PageInfo() end
local function Visible()
 local box=NexusLogScroll and NexusLogScroll.scrollChild
 return box and tostring(box:GetText() or '') or ''
end
local status
local function Status() return status and tostring(status:GetText() or '') or '' end
local function Accepted(text) return ID.DisplaySafeText(text,#text,true,true)~=nil end
local function Doubled(text) return (text:gsub('|','||')) end
-- Show `text` through the provider and the viewer's own repaint.
local function Load(tag,text)
 current=text
 local before=calls
 LV.Show('state');H.Advance(.15)
 C.setup(calls>before,tag..': fixture: the viewer repainted from the provider',calls-before)
end

-- What the text says, not its exact words (case and colour codes ignored).
local REFUSED={'not shown','not displayed','not copied','cannot be shown',"can't be shown",'could not be shown',
 'cannot be displayed',"can't be displayed",'could not be displayed','cannot be copied',"can't be copied",
 'cannot show',"can't show",'cannot display',"can't display",'cannot copy',"can't copy",'unable to show',
 'unable to display','unable to copy','refused','withheld','hidden','omitted','skipped','blocked','suppressed'}
local function SaysRefused(text)
 local l=V.Plain(text):lower()
 for _,w in ipairs(REFUSED) do if l:find(w,1,true) then return true end end
 return false
end
-- A cause. None of these is in the ordinary status line.
local REASONS={'%f[%a]control','%f[%a]character','utf%-?8','%f[%a]encod','%f[%a]invalid','%f[%a]malformed',
 '%f[%a]unsupported','%f[%a]unsafe','printable','%f[%a]combining','%f[%a]invisible','zero%-width',
 '%f[%a]bidi','%f[%a]tab%f[%A]','%f[%a]mark'}
local function GivesReason(text)
 local l=V.Plain(text):lower()
 for _,p in ipairs(REASONS) do if l:find(p) then return true end end
 return false
end
-- Does the text state page/pages ("p/n" or "p of n")?
local function ShowsPosition(text,page,pages)
 local l=V.Plain(text):lower()
 return l:find('%f[%d]'..page..'/'..pages..'%f[%D]')~=nil
  or l:find('%f[%d]'..page..' of '..pages..'%f[%D]')~=nil
end

-- A refused page: explicit (EXPECT), and nothing else in its place (GUARD).
local function Refused(tag,page,pages)
 local shown,line=Visible(),Status()
 print('OBSERVED '..tag..' page='..Ascii(Info().page)..'/'..Ascii(Info().pages)
  ..' area='..Ascii(shown)..' status='..Ascii(line))
 C.expect(V.Plain(shown):find('%S')~=nil,tag..': the page area is not left blank',Ascii(shown))
 C.expect(SaysRefused(shown),tag..': the page area says that this page is not shown',Ascii(shown))
 C.expect(GivesReason(shown..'\n'..line),tag..': and the viewer says why',Ascii(shown)..' / '..Ascii(line))
 C.guard(not shown:find('copyfixture',1,true),
  tag..': no text of this page or of an earlier page is shown in its place',Ascii(shown))
 C.guard(ShowsPosition(line,page,pages),tag..': the status line still shows page '..page..'/'..pages,Ascii(line))
end
-- An ordinary page: exactly its bytes, every "|" doubled and nothing else.
local function Ordinary(tag,raw,page,pages)
 local shown,line=Visible(),Status()
 C.guard(shown==Doubled(raw),tag..': the page is shown exactly, every "|" doubled',Ascii(shown))
 C.guard(ShowsPosition(line,page,pages) and line:lower():find('copy pages in order',1,true)~=nil,
  tag..': the status line shows page '..page..'/'..pages..' and the copy-in-order instruction',Ascii(line))
end
local navSent,navActions=0,0
local function Click(button)
 local sent,actions=#H.sent,#H.actions
 button:Click()
 navSent,navActions=navSent+#H.sent-sent,navActions+#H.actions-actions
end

-- Ordinary text: structural pipes, adjacent and trailing empty fields, and
-- pipe sequences that look like client markup.
local CONTROL=table.concat({'copyfixture-c0||','B|1|1700000000|40||5|','C|1|1|200001||2||',
 'L|1|an ordinary line with |cffff0000colour-looking|r and |Hlink-looking|h[text]|h parts',
 '|leading and trailing|','END|boards=1||audits=0|'},'\n')
C.setup(Accepted(CONTROL),'fixture: the validator accepts the ordinary control text')
Load('C',CONTROL)
local found=0
for _,r in ipairs({NexusLogViewer:GetRegions()}) do
 if r:GetObjectType()=='FontString' and tostring(r:GetText() or ''):find('^Page 1/1') then
  status,found=r,found+1
 end
end
C.setup(found==1,'fixture: the status line of the real viewer is found by its "Page 1/1" text',found)

C.scenario('C ordinary text with structural pipes and adjacent empty fields',function()
 print('OBSERVED C area='..Ascii(Visible())..' status='..Ascii(Status()))
 C.guard(Info().bytes==#CONTROL and Info().pages==1,'C: the complete text is kept on one page',Info().bytes)
 Ordinary('C',CONTROL,1,1)
 C.guard((Visible():gsub('||','|'))==CONTROL,
  'C: undoubling the shown text gives the provider bytes, adjacent empty fields included (offline GetText only)')
end)

-- Each text is refused only because of its trigger: the rest is accepted.
local CASES={
 {'R1 a TAB','E|1|copyfixture-r1|artificial','\t','text||'},
 {'R2 invalid UTF-8','E|2|copyfixture-r2|artificial','\255','text||'},
 {'R3 a combining mark','E|3|copyfixture-r3|artificial e','\204\129',' text||'},
}
for _,case in ipairs(CASES) do
 local tag,before,trigger,after=case[1],case[2],case[3],case[4]
 C.scenario(tag,function()
  local text=before..trigger..after
  C.setup(Accepted(before..after),tag..': fixture: the same text without '..Ascii(trigger)..' is accepted')
  C.guard(not Accepted(text),tag..': the display validator still refuses it (validation policy unchanged)')
  Load(tag,text)
  C.guard(Info().bytes==#text and Info().pages==1 and Info().page==1,
   tag..': the complete text is kept on one page',Info().bytes)
  Refused(tag,1,1)
 end)
end

-- Exactly `size` bytes of ASCII export-like rows (structural "|", adjacent
-- empty fields) after a first line naming `marker`. ASCII only, so the
-- viewer's page boundaries fall exactly every PAGE bytes.
local function Rows(marker,kind,size)
 local out={marker..'||\n'}
 local n,i=#out[1],0
 while n<size do
  i=i+1
  out[#out+1]=string.format('%s|%d|1700000000|40||%d||\n',kind,i,i%7)
  n=n+#out[#out]
 end
 return table.concat(out):sub(1,size)
end

C.scenario('M a refused page between two ordinary pages',function()
 local p1,clean=Rows('copyfixture-p1','B',PAGE),Rows('copyfixture-p2','E',PAGE)
 local mid=math.floor(PAGE/2)
 local p2=clean:sub(1,mid-1)..'\t'..clean:sub(mid+1)
 local p3=Rows('copyfixture-p3','C',1200)..'END|pages=3||'
 local raw=p1..p2..p3
 C.setup(#p1==PAGE and #p2==PAGE and not raw:find('[\128-\255]'),
  'M: fixture: pages 1 and 2 are one page each and the text is ASCII (exact page boundaries)')
 C.setup(Accepted(p1) and Accepted(p3) and Accepted(clean) and not Accepted(p2),
  'M: fixture: the validator accepts pages 1 and 3 and refuses page 2 only for its TAB')
 Load('M',raw)
 C.guard(Info().bytes==#raw and Info().pages==3 and Info().page==1,
  'M: the complete text is kept as three pages, from page 1',Ascii(Info().bytes)..' '..Ascii(Info().pages))
 Ordinary('M page 1',p1,1,3)
 local nextButton,previousButton=NexusLogNextPage,NexusLogPreviousPage
 C.setup(nextButton~=nil and previousButton~=nil and V.Plain(nextButton:GetText())=='Page >'
  and V.Plain(previousButton:GetText())=='< Page','M: fixture: the real "Page >" and "< Page" buttons exist')
 if not (nextButton and previousButton) then return end
 Click(nextButton)
 C.guard(Info().page==2,'M: "Page >" reaches the refused page 2',Info().page)
 Refused('M page 2',2,3)
 C.guard(previousButton:IsEnabled() and nextButton:IsEnabled(),'M: both page buttons stay usable on the refused page')
 Click(nextButton)
 C.guard(Info().page==3,'M: "Page >" leaves the refused page for page 3',Info().page)
 Ordinary('M page 3',p3,3,3)
 Click(previousButton)
 C.guard(Info().page==2,'M: "< Page" returns to page 2',Info().page)
 Refused('M page 2 again',2,3)
 Click(previousButton)
 C.guard(Info().page==1,'M: "< Page" returns to the ordinary page 1',Info().page)
 Ordinary('M page 1 again',p1,1,3)
 C.guard(navSent==0 and navActions==0,'M: page navigation sends nothing and performs no game action',
  navSent..'/'..navActions)
end)

-- Time passes for the repaints, so the start-up's in-memory Sync may add
-- transport records; none may carry text the viewer was given.
local function Leak()
 for i=sent0+1,#H.sent do
  for _,v in pairs(H.sent[i] or {}) do
   if type(v)=='string' and v:find('copyfixture',1,true) then return i end
  end
 end
 return nil
end
C.guard(#H.actions==actions0,'no game action',#H.actions-actions0)
C.guard(Leak()==nil,'no transport record carries any text the viewer was given',Leak())
print('OBSERVED in-memory synthetic transport records added while time passed='..(#H.sent-sent0))
C.finish('(a refused copy page says so; ordinary pages, navigation and the complete text are unchanged;'
 ..' offline GetText only, no native clipboard claim)')
