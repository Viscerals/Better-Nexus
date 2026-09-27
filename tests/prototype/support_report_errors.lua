-- AUD-07: a support report has to show what a recorded Lua error SAID. The
-- error owner keeps {timestamp, source, message} newest last; the report
-- lists the newest entries first, bounded (5 by default, 20 extended), says
-- how many older ones it left out, and tells errors of this session from
-- errors retained from an earlier one. Only those three fields are read, so
-- no other saved field reaches a ticket, and a malformed entry or a failing
-- owner costs only its own line or section.
--
-- Real TOC boot, real Errors owner, real summary and prepared-file builders;
-- synthetic data only. Nothing is sent, loaded or written to disk here.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Boot(db)
 local H=F.Boot(db)
 for _=1,20 do H.Advance(.5,.5) end
 return H
end
local function File(extended)
 local report,why=Nexus.SupportReport.Prepare({extended=extended},4000)
 assert(report,'the report is prepared: '..tostring(why))
 return table.concat(report.chunks,''),report
end
local function Summary()return (Nexus.SupportReport.Summary())end
local function Section(text)
 local start=text:find('-- recorded Lua errors',1,true)
 if not start then return nil end
 local stop=text:find('\n\n',start,true) or #text+1
 return text:sub(start,stop-1)
end
local function Lines(text)
 local out={}
 for line in ((text or '')..'\n'):gmatch('(.-)\n')do out[#out+1]=line end
 return out
end
local function When(ts)return os.date('!%Y-%m-%d %H:%M:%S',ts)..' UTC'end
local function Clean(text,label)
 local bad,at
 for index=1,#text do
  local byte=text:byte(index)
  if byte<32 and byte~=10 then bad,at=byte,index;break end
 end
 check(bad==nil,label..': control byte '..tostring(bad)..' at '..tostring(at))
end
-- Every byte sequence is complete UTF-8: a shortened message never ends in
-- half a character.
local function ValidUtf8(text)
 local index=1
 while index<=#text do
  local byte=text:byte(index);local extra
  if byte<0x80 then extra=0 elseif byte>=0xC2 and byte<=0xDF then extra=1
  elseif byte>=0xE0 and byte<=0xEF then extra=2 elseif byte>=0xF0 and byte<=0xF4 then extra=3
  else return false,index end
  for k=1,extra do
   local c=text:byte(index+k)
   if not c or c<0x80 or c>0xBF then return false,index end
  end
  index=index+extra+1
 end
 return true
end

local db=F.Database()
local H=Boot(db)
check(Nexus.MainInternals.SavedRootReadOnlyV1()==nil,'SETUP: the ordinary profile is writable')
local Errors=assert(Nexus.Errors,'the error owner is loaded')
check(#Errors.History()==0,'SETUP: no error is recorded yet')

-- 1. One real error, recorded through the owner the addon uses. The report
-- line is its time, where it came from, and what it said.
local MSG=[[Interface\AddOns\Nexus\core\Sync.lua:2010: attempt to index field 'grant' (a nil value)]]
check(Errors.Record('Sync.Admission',MSG)==true,'SETUP: the error is recorded')
local entry=Errors.History()[1]
local expected='  1. '..When(entry.timestamp)..', this session, Sync.Admission: '..MSG
local text=File(false)
local lines=Lines(Section(text))
check(lines[2]==expected,'AUD-07 one real error: the report line carries the recorded message: '
 ..tostring(lines[2])..' ~= '..expected)
check(text:find('unreadable table',1,true)==nil,'AUD-07 one real error: the entry table is not called the error')
check(lines[1]=='-- recorded Lua errors (1 retained; 1 this session; newest first) --',
 'the header counts retained and this-session errors: '..tostring(lines[1]))
check(#lines==2,'and lists nothing else: '..#lines)
local summary=Summary()
check(summary:find('Recorded Lua errors retained: 1 (1 this session)',1,true)~=nil,
 'the summary counts retained and this-session errors')
check(summary:find('Newest recorded Lua error: '..When(entry.timestamp)..', this session, Sync.Admission: '..MSG,1,true)~=nil,
 'AUD-07 the summary carries the newest recorded message')

-- 2. Empty history: a count of zero and no entry line.
check(Errors.Clear()==true,'SETUP: the history is cleared')
text=File(false);lines=Lines(Section(text))
check(lines[1]=='-- recorded Lua errors (0 retained; 0 this session; newest first) --' and #lines==1,
 'empty history: the header says zero and nothing is listed: '..tostring(lines[1])..' / '..#lines)
summary=Summary()
check(summary:find('Recorded Lua errors retained: 0 (0 this session)',1,true)~=nil,'empty history: the summary says zero')
check(summary:find('a refusal is not an error',1,true)~=nil,'and still explains that a refusal is not an error')
check(summary:find('Newest recorded Lua error',1,true)==nil,'and names no newest error')

-- 3. More than the default limit: newest first, five of them, and the rest
-- declared rather than dropped silently. The owner retains 20 of 25.
for index=1,25 do
 H.Advance(1,1)
 Errors.Record('Synthetic',string.format('synthetic error %02d',index))
end
local history=Errors.History()
check(#history==20 and history[20].message=='synthetic error 25','SETUP: the owner retains the newest 20 of 25')
text=File(false);lines=Lines(Section(text))
check(lines[1]=='-- recorded Lua errors (20 retained; 20 this session; newest first) --',
 'default: header: '..tostring(lines[1]))
for rank=1,5 do
 local e=history[21-rank]
 check(lines[rank+1]=='  '..rank..'. '..When(e.timestamp)..', this session, Synthetic: synthetic error '..string.format('%02d',26-rank),
  'default: newest-first entry '..rank..': '..tostring(lines[rank+1]))
end
check(lines[7]=='  [15 older recorded error(s) not shown; the extended report lists up to 20]',
 'default: the truncation is declared: '..tostring(lines[7]))
check(#lines==7,'default: five entries and one note: '..#lines)
text=File(true);lines=Lines(Section(text))
check(#lines==21,'extended: all 20 retained entries, no note: '..#lines)
check(lines[2]:find('synthetic error 25',1,true) and lines[21]:find('synthetic error 06',1,true),
 'extended: newest first down to the oldest retained: '..lines[2]..' .. '..lines[21])

-- 4. More than the extended limit, from an owner that hands back more than
-- 20: the extended report still stops at 20 and says how many it left out.
local realErrors=Nexus.Errors
local many={}
for index=1,27 do many[index]={timestamp=1700001000+index,source='Many',message='many '..index} end
Nexus.Errors={History=function()return many end,SessionCount=function()return 3 end}
text=File(true);lines=Lines(Section(text))
check(lines[1]=='-- recorded Lua errors (27 retained; 3 this session; newest first) --','extended over limit: header: '..tostring(lines[1]))
check(lines[2]=='  1. '..When(1700001027)..', this session, Many: many 27','extended over limit: newest first: '..tostring(lines[2]))
check(lines[4]=='  3. '..When(1700001025)..', this session, Many: many 25','extended over limit: the third is this session: '..tostring(lines[4]))
check(lines[5]=='  4. '..When(1700001024)..', earlier session, Many: many 24','extended over limit: the fourth is retained from earlier: '..tostring(lines[5]))
check(lines[22]=='  [7 older recorded error(s) not shown]','extended over limit: the truncation is declared: '..tostring(lines[22]))
check(#lines==22,'extended over limit: 20 entries and one note: '..#lines)
text=File(false);lines=Lines(Section(text))
check(#lines==7 and lines[7]=='  [22 older recorded error(s) not shown; the extended report lists up to 20]',
 'default over limit: five entries and the declared rest: '..tostring(lines[7]))

-- 5. Malformed and legacy entries from an owner that did not sanitise them:
-- each costs at most its own line, and only message, source and time are read.
Nexus.Errors={History=function()return {
 'bare legacy message',
 {error='legacy error field',t=1700000500},
 {message={nested=true},source={}},
 42,
 setmetatable({},{__index=function()error('hostile entry')end}),
 {source='only-source'},
 {message='kept',source='s',secret='PRIVATE-FIELD-VALUE',stack=[[C:\Users\Someone\private.lua]]},
}end}
local okMalformed,malformedText=pcall(File,true)
check(okMalformed,'malformed entries do not take the report away: '..tostring(malformedText))
lines=Lines(Section(malformedText))
local MALFORMED={
 '-- recorded Lua errors (7 retained; this session not known; newest first) --',
 '  1. time not recorded, s: kept',
 '  2. time not recorded, only-source: no message recorded',
 '  3. entry unreadable',
 '  4. entry unreadable (number)',
 '  5. time not recorded, unreadable table: unreadable table',
 '  6. '..When(1700000500)..', unknown source: legacy error field',
 '  7. time not recorded, unknown source: bare legacy message',
}
for index,want in ipairs(MALFORMED)do
 check(lines[index]==want,'malformed entry line '..index..': '..tostring(lines[index])..' ~= '..want)
end
check(#lines==#MALFORMED,'malformed: one line per entry: '..#lines)
check(malformedText:find('PRIVATE-FIELD-VALUE',1,true)==nil and malformedText:find('Someone',1,true)==nil,
 'an entry field other than message, source and time never reaches the report')
local okMalformedSummary,malformedSummary=pcall(Summary)
check(okMalformedSummary and malformedSummary:find('Newest recorded Lua error: time not recorded, s: kept',1,true)~=nil,
 'the summary survives malformed entries: '..tostring(malformedSummary))

-- 6. A failing or missing owner costs the error lines, never the report.
local failing={
 {'raising History',{History=function()error('provider failure')end}},
 {'non-table History',{History=function()return 'not a list' end}},
 {'hostile owner',setmetatable({},{__index=function()error('hostile owner')end})},
 {'missing owner',nil},
}
for _,case in ipairs(failing)do
 Nexus.Errors=case[2]
 local okSummary,summaryText=pcall(Summary)
 check(okSummary and type(summaryText)=='string','provider '..case[1]..': the summary is kept: '..tostring(summaryText))
 check(summaryText:find('Recorded Lua errors: not available',1,true)~=nil,
  'provider '..case[1]..': the summary says the errors are not available, not zero')
 local okFile,fileText,report=pcall(File,true)
 check(okFile,'provider '..case[1]..': the prepared file is kept: '..tostring(fileText))
 check(fileText:find('[section errors was unavailable and is omitted]',1,true)~=nil,
  'provider '..case[1]..': the section is declared omitted')
 check(tostring(report.meta.omissions):find('errors',1,true)~=nil,
  'provider '..case[1]..': and listed in the header omissions: '..tostring(report.meta.omissions))
end
Nexus.Errors={History=function()return {{timestamp=1700000600,source='x',message='count unknown'}}end,
 SessionCount=function()error('count failure')end}
lines=Lines(Section(File(false)))
check(lines[1]=='-- recorded Lua errors (1 retained; this session not known; newest first) --'
 and lines[2]=='  1. '..When(1700000600)..', x: count unknown',
 'a failing session count leaves the entries listed and the origin unstated: '..tostring(lines[2]))
-- Only a wall-clock time is shown as a date; anything else that is not a
-- positive finite number is "not recorded".
Nexus.Errors={History=function()return {
 {timestamp=0/0,source='nan',message='m'},{timestamp=math.huge,source='inf',message='m'},
 {timestamp=-5,source='negative',message='m'},{timestamp=123.5,source='uptime',message='m'},
 {timestamp='1700000000',source='text',message='m'},
}end}
lines=Lines(Section(File(true)))
local STAMPS={'  1. time not recorded, text: m','  2. t=123.5, uptime: m','  3. time not recorded, negative: m',
 '  4. time not recorded, inf: m','  5. time not recorded, nan: m'}
for index,want in ipairs(STAMPS)do
 check(lines[index+1]==want,'timestamp case '..index..': '..tostring(lines[index+1])..' ~= '..want)
end
-- A field other than message, source and time is not a source either.
Nexus.Errors={History=function()return {{message='only message',secret='PRIVATE-FIELD-VALUE',
 stack=[[C:\Users\Someone\private.lua]],path=[[C:\Users\Someone]]}}end}
local privateText=File(true);lines=Lines(Section(privateText))
check(lines[2]=='  1. time not recorded, unknown source: only message','an entry without a source names none: '..tostring(lines[2]))
check(privateText:find('PRIVATE-FIELD-VALUE',1,true)==nil and privateText:find('Someone',1,true)==nil,
 'and none of its other fields reaches the report')
Nexus.Errors=realErrors
-- A Record that fails to write is not an error of this session.
local counted=Errors.SessionCount()
local writable=Nexus.MainInternals.WritableRootV1
Nexus.MainInternals.WritableRootV1=function()error('write refused')end
local recorded=Errors.Record('Refused','not retained')
Nexus.MainInternals.WritableRootV1=writable
check(recorded==false and Errors.SessionCount()==counted,
 'a failed Record does not count as this session: '..tostring(recorded)..' '..tostring(Errors.SessionCount())..' vs '..tostring(counted))

-- 7. UTF-8, line breaks and text that looks like formatting. A line break
-- cannot forge a report line, a format directive is not interpreted, and a
-- long message is cut on a character boundary and says so.
check(Errors.Clear()==true,'SETUP: cleared for the text cases')
Errors.Record('Fmt','first line\nsecond line\r\tthird %s %d %% |cffff0000red|r |Hitem:1|h[x]|h Ünïcödé ✓ Ошибка')
Errors.Record('Long',string.rep('Ж',200))
Errors.Record('Ascii',string.rep('A',300))
history=Errors.History()
text=File(false);lines=Lines(Section(text))
check(lines[2]=='  1. '..When(history[3].timestamp)..', this session, Ascii: '..string.rep('A',237)..'...',
 'a long message is bounded and marked: '..tostring(lines[2]))
check(lines[3]=='  2. '..When(history[2].timestamp)..', this session, Long: '..string.rep('Ж',118)..'...',
 'a long UTF-8 message is cut on a character boundary: '..tostring(lines[3]))
check(lines[4]=='  3. '..When(history[1].timestamp)..', this session, Fmt: first line second line  third %s %d %% |cffff0000red|r |Hitem:1|h[x]|h Ünïcödé ✓ Ошибка',
 'line breaks become spaces; UTF-8 and formatting-looking text survive literally: '..tostring(lines[4]))
check(#lines==4,'three entries, three lines: '..#lines)
-- Three- and four-byte characters: the cut steps back over a whole character.
Errors.Record('Tri','A'..string.rep('✓',100))
Errors.Record('Emoji','AA'..string.rep('😀',70))
text=File(false);lines=Lines(Section(text))
check(lines[2]:sub(-(2+58*4+3))=='AA'..string.rep('😀',58)..'...',
 'a long message of 4-byte characters is cut on a character boundary: '..tostring(lines[2]))
check(lines[3]:sub(-(1+78*3+3))=='A'..string.rep('✓',78)..'...',
 'a long message of 3-byte characters is cut on a character boundary: '..tostring(lines[3]))
local cutValid,cutAt=ValidUtf8(text)
check(cutValid,'the report with 3- and 4-byte cuts is valid UTF-8: byte '..tostring(cutAt))
local valid,at=ValidUtf8(text)
check(valid,'the whole report is valid UTF-8: byte '..tostring(at))
Clean(text,'text cases file')
summary=Summary()
Clean(summary,'text cases summary')
check(ValidUtf8(summary),'the summary is valid UTF-8')

-- 8. Preparing either report changes no saved data.
local before=F.Serialize(NexusDB)
Summary();File(false);File(true)
check(F.Serialize(NexusDB)==before,'preparing reports writes nothing into the saved root')
H.Fire('PLAYER_LOGOUT')

-- 9. A protected (read-only) profile: its saved history is listed as earlier,
-- this session's error as this session, and the saved root stays identical.
local protected=F.Database({version=6,mutate=function(d)
 d.settingsVersion=6
 d.errorHistory={{timestamp='2026-09-01 10:00:00',source='saved-src',message='saved legacy-time error'},
  {error='saved legacy-shape error',t=1690000100,source='saved-src'},
  {timestamp=1690000200,source='saved-src',message='saved error two'}}
end})
local input=F.Serialize(protected)
H=Boot(protected)
check(Nexus.MainInternals.SavedRootReadOnlyV1()~=nil,'SETUP: the future-format profile is read-only')
check(Nexus.Errors.Record('Session','protected session error')==true,'SETUP: a session error is recorded')
local now=Nexus.Errors.History()
text=File(true);lines=Lines(Section(text))
local PROTECTED={
 '-- recorded Lua errors (4 retained; 1 this session; newest first) --',
 '  1. '..When(now[4].timestamp)..', this session, Session: protected session error',
 '  2. '..When(1690000200)..', earlier session, saved-src: saved error two',
 '  3. '..When(1690000100)..', earlier session, saved-src: saved legacy-shape error',
 '  4. time not recorded, earlier session, saved-src: saved legacy-time error',
}
for index,want in ipairs(PROTECTED)do
 check(lines[index]==want,'protected profile line '..index..': '..tostring(lines[index])..' ~= '..want)
end
summary=Summary()
check(summary:find('Recorded Lua errors retained: 4 (1 this session)',1,true)~=nil,'protected profile: the summary counts both')
File(false)
H.Fire('PLAYER_LOGOUT')
check(F.Serialize(NexusDB)==input,'protected profile: the saved root is byte-identical after reports and logout')
print('PASS AUD-07 support reports show recorded Lua errors newest first, bounded, this session vs earlier, and write nothing checks='..checks)
