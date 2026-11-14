-- A player who sees "Catalog saved-build capture failed: SEMANTIC_ENVELOPE"
-- has to be able to hand support one thing. Two routes are driven here through
-- the real command, the real page and the real builder: a compact summary they
-- select and copy, and a report prepared for the isolated NexusSupport
-- component, which WoW writes to its own file at the next normal save boundary.
--
-- Nothing here writes a profile, claims a file exists on disk, reloads, logs
-- out, or sends anything anywhere. The storage component is driven as the
-- client would load it, and the offline result is NOT filesystem verification.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
NexusSupportDB=nil;NexusSupportStorage=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local support=assert(Nexus.SupportIncidents,'the incident owner is loaded')
local builder=assert(Nexus.SupportReport,'the report builder is loaded')
local function button(label,parent)
 for _,b in ipairs(H.frames)do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end
 end
 error('button not found: '..label)
end

-- The companion addon, loaded the way the client loads it on demand.
local companionLoads=0
local function loadCompanion()
 companionLoads=companionLoads+1
 dofile('companion/NexusSupport/Storage.lua')
 H.Fire('ADDON_LOADED','NexusSupport')
 return true
end
LoadAddOn=function(name)
 if name~='NexusSupport' then return false end
 return loadCompanion()
end

-- 1. A refusal is retained with its failure-time facts, and it is NOT an error.
support.Clear()
support.Record('catalog-refusal',{
 reason='SEMANTIC_ENVELOPE',producer='saved-build capture',origin='local',
 operation='saved-build capture',ticket='t-1',build='test.9999-abcdef0',
 representation='inline',counts={ordinary=81,locked=6,total=87},
 limits={ordinary=79,locked=6,total=85},
 readiness={generation=12,semanticGeneration=4},
 affected={{spellId=200701,quality=2,stacks=1,locked=true},{spellId=200751,quality=3,stacks=1}},
 committed=false,
 scope='this catalog write did not commit; earlier personal or public writes are not covered by this outcome',
})
check(support.Count()==1,'the refusal is retained: '..support.Count())
check(#Nexus.Errors.History()==0,'and the Errors page is still empty')
local incident=support.Latest()
check(incident.counts.ordinary==81 and incident.counts.total==87,
 'the counts are the ones from the failure: '..incident.counts.ordinary..'/'..incident.counts.total)
check(incident.committed==false,'the record states that nothing committed')

-- 2. The summary says the failure-time facts first, fits its budget, and never
-- claims anything the owner did not retain.
local body,meta=builder.Summary()
check(#body<=builder.SUMMARY_MAX_BYTES,
 'the summary fits the supported '..builder.SUMMARY_MAX_BYTES..' bytes: '..#body)
check(meta.bytes==#body,'and reports its own size: '..meta.bytes)
check(body:find('SEMANTIC_ENVELOPE',1,true)~=nil,'it names the refusal')
check(body:find('81 ordinary, 6 locked, 87 total',1,true)~=nil,'with the counted copies')
check(body:find('limits 79/6/85',1,true)~=nil,'and the limits that were enforced')
check(body:find('saved-build capture',1,true)~=nil,'it names the producer')
check(body:find('this write did not commit',1,true)~=nil,'and the terminal result')
check(body:find('a refusal is not an error',1,true)~=nil,
 'it explains why the Errors page is empty')
check(body:find('session-',1,true)~=nil,'the character is carried as a session alias')
check(body:find('PrototypeTester',1,true)==nil,'and not as the character name')
local unretained=builder.Summary({kind='catalog-refusal',reason='STORE_INVALID'})
check(unretained:find('not retained',1,true)~=nil,
 'an unobserved field says "not retained" instead of being filled in')

-- 3. The page opens from the real command, before initialization is required.
SlashCmdList.NEXUS('report')
local page=assert(NexusSupportReport,'/nexus report opens the support page')
check(page:IsShown(),'the page is shown')
check(page.incident:GetText():find('SEMANTIC_ENVELOPE',1,true)~=nil,
 'it shows the retained incident: '..page.incident:GetText():sub(1,60))
local actionsBefore=#H.actions
local dbBefore=NexusDB.communityBuilds and #NexusDB.communityBuilds or 0
button('Copy summary',page):Click()
check(page.copyBox:GetText():find('Nexus support summary',1,true)~=nil,
 'Copy summary fills the copy field')
check(page.copyBox:GetMaxLetters()==0,'the copy field has no letter limit')
check(page.copyNote:GetText():find('Nothing was sent anywhere',1,true)~=nil,
 'and states that nothing was sent: '..page.copyNote:GetText())
check(#H.actions==actionsBefore,'reading the report takes no game action')
check(companionLoads==0,'and reading does not load the storage component')

-- 4. Preparing the file loads the component, stores a complete report, and
-- claims only what is true.
check(page.storage:GetText():find('not loaded',1,true)~=nil,
 'the page says the component is not loaded yet: '..page.storage:GetText())
local prepared=assert(Nexus.SupportReportUI.PrepareFile(false),'the report is prepared')
check(companionLoads==1,'the component is loaded on demand exactly once: '..companionLoads)
check(type(NexusSupportDB)=='table' and type(NexusSupportDB.report)=='table',
 'the report is stored in the component variable, not in NexusDB')
check(NexusDB.supportReport==nil,'nothing was written into the main saved data')
check(prepared.chunkCount>=1,'the report has chunks: '..prepared.chunkCount)
check(prepared.bytes>0 and prepared.bytes==NexusSupportDB.report.meta.bytes,
 'the stored size matches the header: '..prepared.bytes)
check(prepared.checksum==builder.Checksum(NexusSupportDB.report.chunks),
 'the checksum covers the stored chunks in order')
for index,chunk in ipairs(NexusSupportDB.report.chunks) do
 check(#chunk<=builder.CHUNK_BYTES,'chunk '..index..' is within the '..builder.CHUNK_BYTES..' byte bound: '..#chunk)
end
check(page.prepared:GetText():find('is prepared in memory',1,true)~=nil,
 'the page says the report is prepared in memory: '..page.prepared:GetText())
check(page.prepared:GetText():find('not yet verified on disk',1,true)~=nil,
 'and that it is not verified on disk')
check(page.prepared:GetText():find('WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua',1,true)~=nil,
 'and points at the account file with a placeholder, not a guessed path')
check(page.prepared:GetText():find('Interface/AddOns',1,true)==nil,
 'never at the shipped addon file')

-- 5. The report carries the incident and the scope of the outcome.
local text=table.concat(NexusSupportDB.report.chunks,'')
check(text:find('SEMANTIC_ENVELOPE',1,true)~=nil,'the report contains the incident')
check(text:find('81 ordinary, 6 locked, 87 total',1,true)~=nil,'with its counts')
check(text:find('earlier personal or public writes are not covered',1,true)~=nil,
 'and the honest scope of the refusal')
check(NexusSupportDB.report.meta.format==builder.FORMAT,
 'the stored report declares its format: '..tostring(NexusSupportDB.report.meta.format))
check(NexusSupportDB.report.meta.build~=nil and NexusSupportDB.report.meta.id~=nil,
 'with the generating build and a report id')
check(NexusSupportDB.report.meta.omissions~=nil,'and what it omitted: '
 ..tostring(NexusSupportDB.report.meta.omissions))

-- 6. A second preparation replaces the report only when the new one completes.
local firstId=NexusSupportDB.report.meta.id
local realPrepare=builder.Prepare
builder.Prepare=function() return nil,'synthetic preparation failure' end
local failed,why=Nexus.SupportReportUI.PrepareFile(false)
builder.Prepare=realPrepare
check(failed==nil and why=='synthetic preparation failure','a failed preparation returns its reason')
check(NexusSupportDB.report.meta.id==firstId,
 'and the completed report from before is still stored: '..NexusSupportDB.report.meta.id)
check(page.prepared:GetText():find('previously stored report was kept',1,true)~=nil,
 'the page says so: '..page.prepared:GetText())
local second=assert(Nexus.SupportReportUI.PrepareFile(false),'a later complete preparation succeeds')
check(second.id~=firstId,'it gets its own report id: '..second.id)
check(NexusSupportDB.report.meta.id==second.id,'and replaces the stored one')

-- 7. Reopening verifies the stored report without claiming the old session.
button('Inspect prepared report',page):Click()
check(page.prepared:GetText():find('matches its own checksum in memory',1,true)~=nil,
 'the stored report verifies against its own checksum, and says only that: '..page.prepared:GetText())
check(page.prepared:GetText():find('verified as loaded',1,true)==nil,
 'it never says the file was read back from disk')
check(page.prepared:GetText():find('does not prove the session that made it still exists',1,true)~=nil,
 'and says what that does not prove')

-- 8. Storage that this version does not understand is left exactly as it is.
NexusSupportDB={format='from a newer build',report={meta={id='theirs'},chunks={'x'}}}
NexusSupportStorage=nil
companionLoads=0
local blocked,blockedWhy=Nexus.SupportReportUI.PrepareFile(false)
check(blocked==nil,'an incompatible store refuses the export: '..tostring(blockedWhy))
check(NexusSupportDB.report.meta.id=='theirs',
 'and the unknown data is untouched: '..tostring(NexusSupportDB.report.meta.id))
check(page.prepared:GetText():find('kept',1,true)~=nil or
 page.prepared:GetText():find('untouched',1,true)~=nil,
 'the page says the existing data was left alone: '..page.prepared:GetText())
local fallback=builder.Summary()
check(#fallback>0,'and the copy summary still works as the fallback: '..#fallback..' bytes')

-- 9. A missing component is not an error: the copy route stays available.
NexusSupportDB=nil;NexusSupportStorage=nil
LoadAddOn=function() return false end
local missing,missingWhy=Nexus.SupportReportUI.PrepareFile(false)
check(missing==nil and tostring(missingWhy):find('not installed',1,true)~=nil,
 'a missing component is reported plainly: '..tostring(missingWhy))
check(page.prepared:GetText():find('Use Copy summary instead',1,true)~=nil,
 'and the page offers the copy route: '..page.prepared:GetText())
button('Copy summary',page):Click()
check(page.copyBox:GetText():find('Nexus support summary',1,true)~=nil,
 'which still works with no component at all')

-- 10. Unicode, control characters and pipes survive the copy boundary intact.
support.Clear()
support.Record('catalog-refusal',{reason='STORE_INVALID',producer='share|local',
 detail='name with \1 control and | pipe and \195\169 accent',
 counts={ordinary=1,locked=0,total=1},committed=false})
local odd=builder.Summary()
check(odd:find('share|local',1,true)~=nil,
 'the copied text keeps a recorded label exactly: a pipe is not doubled into the ticket')
check(odd:find('share||local',1,true)==nil,'and is not escaped on its way there')
check(odd:find('\1',1,true)==nil,'a control character does not reach the report')
check(odd:find('\195\169',1,true)~=nil,'and non-ASCII text is preserved: accent kept')

-- 11. Bounds hold even when one incident is enormous, and the summary is cut
-- on a line boundary so a ticket never receives half an identifier.
support.Clear()
local wide={}
for i=1,400 do wide['key'..i]=i end
local many={}
for i=1,200 do many[#many+1]={spellId=2000000+i,quality=3,stacks=9} end
for i=1,20 do
 support.Record('catalog-refusal',{reason='WIDE'..i,producer=string.rep('p',400),
  operation=string.rep('o',400),detail=string.rep('d',400),scope=string.rep('s',400),
  counts={ordinary=79+i,locked=6,total=85+i},limits={ordinary=79,locked=6,total=85},
  readiness=wide,affected=many,committed=false})
end
local big,bigMeta=builder.Summary()
check(#big<=builder.SUMMARY_MAX_BYTES,
 'twenty large incidents still fit the summary bound: '..#big)
check(bigMeta.bytes==#big,'and the reported size is the real one: '..bigMeta.bytes)
local lastLine=big:match('[^' .. string.char(10) .. ']*$')
check(lastLine and (#lastLine==0 or lastLine:sub(1,1)~=' '),
 'the summary ends on a whole line: '..tostring(lastLine and lastLine:sub(1,40)))
local readinessKeys=0
for _ in pairs(support.Latest().readiness or {}) do readinessKeys=readinessKeys+1 end
check(readinessKeys<=13,'a large readiness map is bounded when retained: '..readinessKeys)
check(#support.Latest().affected<=support.MAX_TUPLES,
 'and so is the tuple list: '..#support.Latest().affected)

-- 12. A report that cannot fit its own bound says so and keeps the old one.
local storedBefore=NexusSupportDB and NexusSupportDB.report and NexusSupportDB.report.meta.id
local hugeReport=builder.Prepare({extended=true})
check(type(hugeReport)=='table','a large history still produces a report')
local hugeBytes=0
for _,chunk in ipairs(hugeReport.chunks) do hugeBytes=hugeBytes+#chunk end
check(hugeBytes<=builder.TOTAL_BYTES,
 'and it stays inside the supported total: '..hugeBytes..' of '..builder.TOTAL_BYTES)
check(hugeReport.meta.chunkCount==#hugeReport.chunks,'its header counts its own chunks')

-- 13. The copy route survives an owner that throws: it is the route a broken
-- install depends on.
local realStartup=Nexus.StartupStatus
Nexus.StartupStatus=function() error('isolated startup owner') end
local okSummary,brokenBody=pcall(builder.Summary)
Nexus.StartupStatus=realStartup
check(okSummary and type(brokenBody)=='string',
 'a failing startup owner does not take away Copy summary: '..tostring(brokenBody))
check(brokenBody:find('Nexus support summary',1,true)~=nil,'the summary is still a summary')
local realErrors=Nexus.Errors.History
Nexus.Errors.History=function() error('isolated errors owner') end
local okErrors=pcall(builder.Summary)
Nexus.Errors.History=realErrors
check(okErrors,'and neither does a failing Errors owner')

-- 14. A write that did NOT commit is never folded into one that did, and two
-- failures that differ in any retained field stay two incidents.
support.Clear()
local shared={reason='STORE_INVALID',producer='share',origin='local',
 operation='share',counts={ordinary=1,locked=0,total=1}}
local function record(extra)
 local fields={}
 for k,v in pairs(shared) do fields[k]=v end
 for k,v in pairs(extra or {}) do fields[k]=v end
 return support.Record('catalog-refusal',fields)
end
record({committed=false})
record({committed=true})
check(support.Count()==2,
 'a committed write and a refused one are two incidents: '..support.Count())
local committedStates={}
for _,entry in ipairs(support.History()) do
 committedStates[tostring(entry.committed)]=true
end
check(committedStates['false'] and committedStates['true'],
 'and each keeps its own outcome')
support.Clear()
record({committed=false,category='dummy'})
record({committed=false,category='lk'})
check(support.Count()==2,'two encounters are two incidents: '..support.Count())
support.Clear()
record({committed=false,limits={ordinary=79,locked=6,total=85}})
record({committed=false,limits={ordinary=60,locked=6,total=85}})
check(support.Count()==2,'two enforced envelopes are two incidents: '..support.Count())
support.Clear()
record({committed=false,readiness={activeSlot=1}})
record({committed=false,readiness={activeSlot=2}})
check(support.Count()==2,'two source readings are two incidents: '..support.Count())
support.Clear()
record({committed=false,affected={{spellId=1,quality=1,stacks=1}}})
record({committed=false,affected={{spellId=2,quality=1,stacks=1}}})
check(support.Count()==2,'two affected lists are two incidents: '..support.Count())
support.Clear()
record({committed=false,readiness={activeSlot=1}})
record({committed=false,readiness={activeSlot=1}})
check(support.Count()==1 and support.Latest().occurrences==2,
 'while a true repeat is still one incident with a count: '..support.Count())
-- A retained readiness value is TEXT the failing boundary supplied, so it can
-- contain the characters the description itself uses. Two different readings
-- must not describe themselves identically and be merged into one incident
-- that then states a source reading the second failure never had.
support.Clear()
record({committed=false,readiness={permanentSource='x;y=z'}})
record({committed=false,readiness={permanentSource='x',y='z'}})
check(support.Count()==2,
 'two readings that only look alike when joined are two incidents: '..support.Count())
-- A value the boundary supplied is retained SHORTENED and with its control
-- characters written out. Two readings that differ only in what shortening or
-- flattening would remove are still two readings.
support.Clear()
record({committed=false,readiness={note='x'..string.char(10)..'y'}})
record({committed=false,readiness={note='x y'}})
check(support.Count()==2,
 'a newline is not a space in a retained reading: '..support.Count())
support.Clear()
record({committed=false,readiness={note=string.rep('a',400)..'1'}})
record({committed=false,readiness={note=string.rep('a',400)..'2'}})
check(support.Count()==2,
 'two long readings that differ past the retained length are two readings: '..support.Count())
support.Clear()
record({committed=false,readiness={note=string.rep('a',400)}})
record({committed=false,readiness={note=string.rep('a',400)}})
check(support.Count()==1 and support.Latest().occurrences==2,
 'while the same long reading twice is still one: '..support.Count())
check(#tostring(support.Latest().readiness.note)<=240,
 'and what is retained is still bounded: '..#tostring(support.Latest().readiness.note))
-- A caller that hands over the RETAINED form of a longer value must not be
-- merged with it: the marker opens with a control byte, and every control
-- byte a caller supplies is escaped, so the retained form cannot be forged.
support.Clear()
record({committed=false,readiness={note=string.rep('a',400)}})
local retained=tostring(support.Latest().readiness.note)
record({committed=false,readiness={note=retained}})
check(support.Count()==2,
 'the retained form of a long reading is not the same reading: '..support.Count())
-- The marker is an IDENTITY device. It must never reach the text a player
-- copies into a ticket, or the prepared file, as the byte it is stored as.
support.Clear()
record({committed=false,readiness={note=string.rep('a',400)}})
local copied=builder.Summary()
check(copied:find(string.char(1),1,true)==nil,
 'no marker byte reaches the copied summary')
check(copied:find('(400B#',1,true)~=nil,
 'while the shortening is still stated in the text the reader sees')
check(copied:match('%.%.%.%(400B#%x%x%x%x%x%x%x%x%)')~=nil,
 'and the marker is WHOLE - bracket, byte count and checksum: '
 ..tostring(copied:match('%.%.%.%b()')))
local markerJob=builder.NewPreparation({extended=true})
local markerGuard=0
while builder.Step(markerJob)=='pending' and markerGuard<400 do markerGuard=markerGuard+1 end
local markerText=table.concat(markerJob.chunks or {},'')
check(markerText:find(string.char(1),1,true)==nil,
 'and none reaches the prepared file either')
-- The prepared-file route builds a topic from the incident. It must not raise
-- on an incident that is missing fields, and the marker must not reach the
-- payload, the stored header or the file the client writes.
support.Clear()
local bare=builder.NewPreparation({incident={id=1,occurrences=1}})
check(type(bare)=='table','a preparation for an incident with no kind or reason is built')
local bareGuard=0
while builder.Step(bare)=='pending' and bareGuard<400 do bareGuard=bareGuard+1 end
check(type(bare.report)=='table','and it completes: '..tostring(bare.report and 'yes'))
support.Clear()
record({committed=false,reason=string.rep('R',400)})
local topicJob=builder.NewPreparation({extended=true})
local topicGuard=0
while builder.Step(topicJob)=='pending' and topicGuard<400 do topicGuard=topicGuard+1 end
local topicText=table.concat(topicJob.chunks or {},'')
check(topicText:find(string.char(1),1,true)==nil,
 'a long reason does not put a marker byte into the prepared payload')
check(tostring(topicJob.report.meta.topic):find(string.char(1),1,true)==nil,
 'or into the stored header: '..tostring(topicJob.report.meta.topic):sub(1,60))
check(#tostring(topicJob.report.meta.topic)<=200,
 'and the header topic stays bounded: '..#tostring(topicJob.report.meta.topic))
-- A bound that is tighter than the value must not silently drop the statement
-- that the value was cut. The header would otherwise claim a complete value.
check(tostring(topicJob.report.meta.topic):match('%.%.%.%(400B#%x%x%x%x%x%x%x%x%)')~=nil,
 'the header topic keeps the WHOLE marker at its own tighter bound: '
 ..tostring(topicJob.report.meta.topic))
check(topicText:match('%.%.%.%(400B#%x%x%x%x%x%x%x%x%)')~=nil,
 'and so does the prepared payload')
-- The same for the incident KIND, which is read back through the same
-- converter and reaches both routes.
support.Clear()
support.Record(string.rep('K',400),{committed=false})
local kindSummary=builder.Summary()
check(kindSummary:find(string.char(1),1,true)==nil,
 'a long kind puts no marker byte into the copied summary')
check(kindSummary:match('%.%.%.%(40[0-9]B#%x%x%x%x%x%x%x%x%)')~=nil,
 'and its shortening is stated whole: '..tostring(kindSummary:match('%.%.%.%b()')))
local kindJob=builder.NewPreparation({extended=true})
local kindGuard=0
while builder.Step(kindJob)=='pending' and kindGuard<400 do kindGuard=kindGuard+1 end
local kindText=table.concat(kindJob.chunks or {},'')
check(kindText:find(string.char(1),1,true)==nil,
 'and none into the prepared payload')
-- The build label is an owner field like the rest: hostile or not, neither
-- route may be taken away and no control byte may reach the stored header.
local realRelease=Nexus.Release.buildLabel
Nexus.Release.buildLabel=setmetatable({},{__tostring=function() error('hostile') end})
local okLabelSummary=pcall(builder.Summary)
local okLabelFile,labelJob=pcall(builder.NewPreparation,{})
Nexus.Release.buildLabel='pkg'..string.char(10)..'LINE'..string.char(1)..'MARK'
local labelSummary=builder.Summary()
local labelJob2=builder.NewPreparation({})
local labelGuard=0
while builder.Step(labelJob2)=='pending' and labelGuard<400 do labelGuard=labelGuard+1 end
Nexus.Release.buildLabel=realRelease
check(okLabelSummary,'a hostile build label does not take the summary away')
check(okLabelFile,'or the prepared-file route')
check(labelSummary:find(string.char(1),1,true)==nil,
 'and a build label carrying the marker byte reaches the summary without it')
local labelLine
for line in labelSummary:gmatch('[^'..string.char(10)..']+') do
 if line:find('Build: ',1,true)==1 then labelLine=line end
end
check(labelLine~=nil and labelLine:find('pkg LINE MARK',1,true)~=nil,
 'its newline does not split the Build line in two: '..tostring(labelLine))
check(tostring(labelJob2.report.meta.build):find(string.char(1),1,true)==nil
 and tostring(labelJob2.report.meta.build):find(string.char(10),1,true)==nil,
 'or the stored header: '..tostring(labelJob2.report.meta.build))
-- The prepared file's own start-up scalars are converted like every other
-- value: a hostile field must not omit the whole section.
local realStartup=Nexus.StartupStatus
Nexus.StartupStatus=function()
 return {state='failed',coreReady=false,
  reason=setmetatable({},{__tostring=function() error('hostile') end})}
end
local hostileJob=builder.NewPreparation({extended=true})
local hostileGuard=0
while builder.Step(hostileJob)=='pending' and hostileGuard<400 do hostileGuard=hostileGuard+1 end
Nexus.StartupStatus=realStartup
local hostileText=table.concat(hostileJob.chunks or {},'')
check(hostileText:find('-- startup --',1,true)~=nil,
 'the start-up section is still written when one of its fields is hostile')
check(hostileText:find('state=failed',1,true)~=nil,
 'with the fields that ARE readable: '..hostileText:sub(1,120))
-- A retained KEY that had to be shortened says so, like a retained value.
support.Clear()
record({committed=false,readiness={[string.rep('k',60)..'1']='x'}})
record({committed=false,readiness={[string.rep('k',60)..'2']='x'}})
check(support.Count()==2,
 'two readings whose keys differ only past the cut are two readings: '..support.Count())
-- The incident kind is retained text: escaped and bounded like the rest.
support.Clear()
record({committed=false,kind='catalog-refusal'})
local longKind=support.Record(string.rep('K',400)..string.char(9),{committed=false})
check(longKind~=nil and #tostring(longKind.kind)<=240,
 'a long kind is bounded when retained: '..#tostring(longKind and longKind.kind))
check(tostring(longKind.kind):find(string.char(9),1,true)==nil,
 'and its control characters are escaped')
support.Clear()
record({committed=false,readiness={permanentSource=1}})
record({committed=false,readiness={permanentSource='1'}})
check(support.Count()==2,
 'a reading of the number 1 is not a reading of the text "1": '..support.Count())
support.Clear()
record({committed=false,readiness={a='b=c'}})
record({committed=false,readiness={['a=b']='c'}})
check(support.Count()==2,'and so are two readings that differ only in where the key ends: '
 ..support.Count())
support.Clear()
local caller={activeSlot=1}
for i=1,40 do caller['k'..i]=i end
record({committed=false,readiness=caller})
check(caller['(omitted keys)']==nil,"the caller's own map is not written into")
-- 13. This module does not trust its owners anywhere else, and it must not
-- trust them here. Summary, IncidentLines and NewPreparation are public and
-- take a caller's table, so a value carrying the marker byte followed by more
-- control bytes must not put them into the report or forge a line.
support.Clear()
local injected={id=1,occurrences=1,committed=false,
 kind='KIND'..string.char(1)..string.char(10)..'INJECTED',
 reason='REASON'..string.char(1)..string.char(7)..'BELL'}
local injectedSummary=builder.Summary(injected)
local badByte=nil
for index=1,#injectedSummary do
 local byte=injectedSummary:byte(index)
 if byte<32 and byte~=10 then badByte=byte end
end
check(badByte==nil,'no control byte from a caller value reaches the summary: '..tostring(badByte))
check(injectedSummary:find('INJECTED',1,true)~=nil,'the text itself is still shown')
local forged=nil
for line in injectedSummary:gmatch('[^'..string.char(10)..']+') do
 if line:find('^INJECTED') then forged=line end
end
check(forged==nil,'and it cannot forge a line of its own: '..tostring(forged))
local injectedJob=builder.NewPreparation({incident=injected,extended=true})
local injectedGuard=0
while builder.Step(injectedJob)=='pending' and injectedGuard<400 do injectedGuard=injectedGuard+1 end
local injectedText=table.concat(injectedJob.chunks or {},'')
local badPayload=nil
for index=1,#injectedText do
 local byte=injectedText:byte(index)
 if byte<32 and byte~=10 then badPayload=byte end
end
check(badPayload==nil,'nor the prepared payload: '..tostring(badPayload))

-- 14. A hostile owner CONTAINER, not only a hostile field: a metatable on the
-- owner table raises on the index itself.
do
 local realRelease,realEvidence=Nexus.Release,Nexus.LoadoutEvidence
 local raising=setmetatable({},{__index=function() error('hostile owner') end})
 Nexus.Release=raising
 local okRelease=pcall(builder.Summary)
 local okReleaseFile=pcall(builder.NewPreparation,{})
 Nexus.Release=realRelease
 Nexus.LoadoutEvidence=raising
 local okEvidence=pcall(builder.Summary)
 Nexus.LoadoutEvidence=realEvidence
 check(okRelease and okReleaseFile,'a raising release owner takes neither route away')
 check(okEvidence,'and neither does a raising evidence owner')
end

-- 15. The checksum detects order, and counts each chunk's position. Without
-- the per-chunk term, two different chunk splits of the same bytes agree.
check(builder.Checksum({'a','b'})~=builder.Checksum({'b','a'}),
 'the checksum is order sensitive')
check(builder.Checksum({'ab'})~=builder.Checksum({'a','b'}),
 'and counts where each chunk ends')
check(builder.Checksum({})==builder.Checksum({}),'and is stable for the same input')
-- The VALUE is pinned, not only its properties: tools/decode_support_report.py
-- recomputes this same function in Python, so a change here that nothing
-- notices would make every prepared file unreadable by the decoder.
check(builder.Checksum({'nexus'})=='08b90235',
 'the checksum is the one the data-only decoder computes: '..builder.Checksum({'nexus'}))
check(builder.Checksum({'a','b'})=='025100c7',
 'for a split list too: '..builder.Checksum({'a','b'}))

-- 15b. The Orb section prints owner labels. They are owner text like any
-- other: bounded, and never a control byte in the payload.
do
 local realHistory=Nexus.OrbHistory
 local realRuntime=Nexus.OrbRuntime and Nexus.OrbRuntime.RunLog
 if type(realHistory)=='table' then
  local realRows,realView=realHistory.Rows,realHistory.Report
  realHistory.Rows=function()
   return {{ordinal=1,
    source={label='SRC'..string.char(1)..string.char(10)..'FORGED'},
    replacement={label=string.rep('L',5000)},
    result={label='RES'..string.char(7)}}}
  end
  if Nexus.OrbRuntime then
   Nexus.OrbRuntime.RunLog=function() return {runId=1,state='FINISHED',entries={{}}} end
  end
  local orbJob=builder.NewPreparation({extended=true})
  local orbGuard=0
  while builder.Step(orbJob)=='pending' and orbGuard<400 do orbGuard=orbGuard+1 end
  realHistory.Rows,realHistory.Report=realRows,realView
  if Nexus.OrbRuntime then Nexus.OrbRuntime.RunLog=realRuntime end
  local orbText=table.concat(orbJob.chunks or {},'')
  local orbBad=nil
  for index=1,#orbText do
   local byte=orbText:byte(index)
   if byte<32 and byte~=10 then orbBad=byte end
  end
  check(orbBad==nil,'no control byte from an Orb label reaches the payload: '..tostring(orbBad))
  check(orbText:find(string.rep('L',200),1,true)==nil,
   'and an unbounded label is bounded before it is written')
 end
end

-- 16. The build label is bounded in the stored header, not only escaped.
do
 local realLabel=Nexus.Release.buildLabel
 Nexus.Release.buildLabel=string.rep('X',5000)
 local longJob=builder.NewPreparation({})
 local longGuard=0
 while builder.Step(longJob)=='pending' and longGuard<400 do longGuard=longGuard+1 end
 Nexus.Release.buildLabel=realLabel
 check(#tostring(longJob.report.meta.build)<=64,
  'a 5000-byte build label is bounded in the header: '..#tostring(longJob.report.meta.build))
end

-- 17. More than one chunk. Every bound holds across the split, and the
-- checksum still recomputes over the real chunk list.
support.Clear()
for index=1,20 do
 support.Record('catalog-refusal',{reason='R'..index,producer=string.rep('P',200),
  scope=string.rep('S',200),detail=string.rep('D',200),committed=false,
  counts={ordinary=79,locked=6,total=85},limits={ordinary=79,locked=6,total=85}})
end
local bigJob=builder.NewPreparation({extended=true})
local bigGuard=0
while builder.Step(bigJob)=='pending' and bigGuard<2000 do bigGuard=bigGuard+1 end
check(bigJob.report~=nil,'a large report completes')
check(bigJob.report.meta.chunkCount>1,
 'across more than one chunk: '..bigJob.report.meta.chunkCount)
local bigBytes=0
for _,chunk in ipairs(bigJob.report.chunks) do
 check(#chunk<=builder.CHUNK_BYTES,'each chunk stays within its bound: '..#chunk)
 bigBytes=bigBytes+#chunk
end
check(bigJob.report.meta.bytes==bigBytes,
 'the header byte count is the real one: '..bigJob.report.meta.bytes..' vs '..bigBytes)
check(bigJob.report.meta.checksum==builder.Checksum(bigJob.report.chunks),
 'and the checksum covers the real chunks in order')

-- 18. The poison sweep. One value, every owner these two routes read, and the
-- property rather than the site: a report a player can copy or hand over must
-- never carry a control byte, never gain a line its owner did not write,
-- never carry an unbounded segment, and never be lost to a failing owner.
do
 local POISON='SENTINEL'..string.char(1)..string.char(10)..string.char(7)
  ..string.char(0)..'|cffff0000|Hitem:1|h[pipe]|h|r'..string.rep('Z',600)
 local function hostile()
  return setmetatable({},{__tostring=function() error('hostile owner') end,
   __index=function() error('hostile index') end})
 end
 -- A header FIELD legitimately holds the value itself, so only the report
 -- text can be checked for a forged line; both are checked for control bytes
 -- and for an unbounded segment.
 local function clean(text,label)
  local badByte,badAt
  for index=1,#text do
   local byte=text:byte(index)
   if byte<32 and byte~=10 then badByte,badAt=byte,index;break end
  end
  check(badByte==nil,label..': control byte '..tostring(badByte)..' at '..tostring(badAt))
  -- The widest bound any single value gets in this file is 240 bytes, so a
  -- run past that is a segment that escaped its converter, not a long field.
  check(text:find(string.rep('Z',400),1,true)==nil,label..': an unbounded segment was written')
 end
 -- A value can only forge a line by carrying a line break, and a section that
 -- lists entries legitimately gives each one its own line. So the property is
 -- counted, not pattern-matched: the report must have exactly as many lines as
 -- the same report built from a value with no control bytes in it.
 local function lineCount(text)
  local count=0
  for _ in text:gmatch('[^'..string.char(10)..']+') do count=count+1 end
  return count
 end
 -- The same record and the same owners, with a control-byte-free value.
 local CLEAN='SENTINEL'..string.rep('Z',600)
 local baselineSummaryLines,baselinePayloadLines
 local saved={
  Release=Nexus.Release,LoadoutEvidence=Nexus.LoadoutEvidence,
  OrbRuntime=Nexus.OrbRuntime,OrbHistory=Nexus.OrbHistory,
  StartupStatus=Nexus.StartupStatus,Errors=Nexus.Errors,
  Storage=_G.NexusSupportStorage,UnitName=UnitName,
 }
 -- Every owner, poisoned one at a time, then all of them at once. The first
 -- pass uses the clean value and fixes the line counts every later pass has
 -- to match.
 local owners={'baseline','Release','LoadoutEvidence','OrbRuntime','OrbHistory',
  'StartupStatus','Errors','Storage','UnitName','all','raising'}
 for _,owner in ipairs(owners) do
  support.Clear()
  -- Enough incidents that the context list of OTHER incidents runs and the
  -- summary reaches its byte backstop, and tuples whose fields are poisoned
  -- rather than numeric.
  for copy=1,12 do
   support.Record(copy..POISON,{reason=copy..POISON,producer=POISON,scope=POISON,
    detail=POISON,operation=POISON,ticket=POISON,build=POISON,category=POISON,
    representation=POISON,origin=POISON,committed=false,
    readiness={[POISON]=POISON,generation=12},
    counts={ordinary=81,locked=6,total=87},limits={ordinary=79,locked=6,total=85},
    affected={{spellId=POISON,quality=POISON,stacks=POISON,locked={}},
     {spellId=1,quality=2,stacks=3,locked=true}}})
  end
  -- Every owner is substituted in every pass, with the poisoned value for the
  -- one under test and a control-byte-free value for the rest, so a count that
  -- changes can only be a line a value added.
  local function substitute(name,value,hostileOwner)
   if name=='Release' then Nexus.Release={buildLabel=value,version=value}
   elseif name=='LoadoutEvidence' then
    Nexus.LoadoutEvidence={SemanticLimits=function()
     return {ordinary=value,locked=value,total=value} end}
   elseif name=='OrbRuntime' then Nexus.OrbRuntime={RunLog=function()
     return {runId=value,state=value,spent=value,limit=value,total=value,entries={{}}} end}
   elseif name=='OrbHistory' then Nexus.OrbHistory={Rows=function()
     return {{ordinal=value,source={label=value},replacement={label=value},
      result={label=value}}} end,Report=function() return {} end}
   elseif name=='StartupStatus' then Nexus.StartupStatus=function()
     return {state='failed',coreReady=false,reason=value,phase=value,
      failure={stage=value,detail=value,cause=value,owner=value,error=value,
       row=value,formatClass=value,formatVersion=value,formatField=value,
       legacyClass=value,keyWidth={path=value,depth=value,keyType=value,
        keyBytes=value,valueType=value,limit=value,exception=value}}} end
   elseif name=='Errors' then Nexus.Errors={History=function() return {value,value} end}
   elseif name=='Storage' then
    _G.NexusSupportStorage={Replace=function() return true end,
     Status=function() return {loaded=true,ready=true,reason=value} end}
   elseif name=='UnitName' then UnitName=function() return value end
   end
  end
  for _,each in ipairs(owners) do
   if each~='baseline' and each~='all' then
    local poisoned=owner=='all' or owner==each
    substitute(each, poisoned and POISON or CLEAN, poisoned)
    if owner=='raising' then
     if each=='LoadoutEvidence' then Nexus.LoadoutEvidence=hostile()
     elseif each=='Storage' then _G.NexusSupportStorage=hostile()
     elseif each=='UnitName' then UnitName=function() error('hostile client') end
     elseif each=='Release' then Nexus.Release=hostile()
     elseif each=='Errors' then Nexus.Errors=hostile()
     elseif each=='OrbRuntime' then Nexus.OrbRuntime=hostile()
     elseif each=='OrbHistory' then Nexus.OrbHistory=hostile()
     elseif each=='StartupStatus' then Nexus.StartupStatus=function() error('hostile owner') end
     end
    end
   end
  end
  -- A CALLER's incident: nothing sanitised it first, so the report-side
  -- converters are the only thing between it and the page.
  local callerIncident={id=POISON,kind=POISON,reason=POISON,producer=POISON,
   origin=POISON,operation=POISON,ticket=POISON,build=POISON,category=POISON,
   representation=POISON,scope=POISON,detail=POISON,occurrences=POISON,
   firstAt=POISON,lastAt=POISON,affectedOmitted=POISON,committed=false,
   counts={ordinary=POISON,locked=POISON,total=POISON},
   limits={ordinary=POISON,locked=POISON,total=POISON},
   readiness={[POISON]=POISON},
   affected={{spellId=POISON,quality=POISON,stacks=POISON,locked=POISON}}}
  local okCaller,callerText=pcall(builder.Summary,callerIncident)
  check(okCaller,'poisoned '..owner..': a caller incident does not take the summary away: '
   ..tostring(callerText))
  clean(callerText,'poisoned '..owner..' caller summary')
  local okCallerFile,callerJob=pcall(builder.NewPreparation,{incident=callerIncident,extended=true})
  check(okCallerFile,'poisoned '..owner..': nor the prepared-file route')
  if okCallerFile and type(callerJob)=='table' then
   local callerGuard=0
   while builder.Step(callerJob)=='pending' and callerGuard<800 do callerGuard=callerGuard+1 end
   clean(table.concat(callerJob.chunks or {},''),'poisoned '..owner..' caller payload')
  end
  local okSummary,summaryText=pcall(builder.Summary)
  local okStatus=pcall(builder.StorageStatus)
  local okNotice,noticeText=pcall(builder.WrittenNotice,{id=POISON})
  local okJob,job=pcall(builder.NewPreparation,{extended=true})
  local payload=''
  if okJob and type(job)=='table' then
   local guard=0
   while builder.Step(job)=='pending' and guard<800 do guard=guard+1 end
   payload=table.concat(job.chunks or {},'')
  end
  for key,value in pairs(saved) do
   if key=='Storage' then _G.NexusSupportStorage=value
   elseif key=='UnitName' then UnitName=value
   else Nexus[key]=value end
  end
  check(okSummary,'poisoned '..owner..': the summary route is not lost: '..tostring(summaryText))
  check(okStatus,'poisoned '..owner..': the storage status is not lost')
  check(okNotice,'poisoned '..owner..': the written notice is not lost')
  if okNotice and type(noticeText)=='string' then
   clean(noticeText,'poisoned '..owner..' written notice')
  end
  check(okJob,'poisoned '..owner..': the prepared-file route is not lost: '..tostring(job))
  check(type(summaryText)=='string' and #summaryText<=builder.SUMMARY_MAX_BYTES,
   'poisoned '..owner..': the summary still fits its bound: '..#tostring(summaryText))
  -- The context list of OTHER incidents is what the fixture used to miss
  -- entirely: with one incident the loop never ran, so the five converters in
  -- it were asserted by nothing. The 8000-byte backstop below it cannot be
  -- reached at all while the owner bounds every field to 240 and keeps at
  -- most 20 incidents; that is stated in the commit rather than forced here.
  check(summaryText:find('Other retained incidents this session',1,true)~=nil,
   'poisoned '..owner..': the context list is in the summary')
  local contextRows=0
  for _ in summaryText:gmatch(string.char(10)..'  %d+%. ') do contextRows=contextRows+1 end
  local omittedNote=summaryText:match('%[(%d+) context line%(s%) omitted')
  check(contextRows>=1,
   'poisoned '..owner..': and it really lists the other incidents: '..contextRows)
  check(contextRows+(tonumber(omittedNote) or 0)>=11,
   'poisoned '..owner..': every other incident is either listed or declared omitted: '
   ..contextRows..'+'..tostring(omittedNote))
  check(omittedNote==nil or summaryText:find('use Prepare report file',1,true)~=nil,
   'poisoned '..owner..': and the omission says where the whole report is')
  -- A retained tuple flag is a boolean, whatever the caller handed over.
  local retainedTuple=support.Latest() and (support.Latest().affected or {})[1]
  check(retainedTuple==nil or retainedTuple.locked==nil or retainedTuple.locked==true,
   'poisoned '..owner..': a retained tuple flag is a boolean: '
   ..type(retainedTuple and retainedTuple.locked))
  clean(summaryText,'poisoned '..owner..' summary')
  clean(payload,'poisoned '..owner..' payload')
  if owner=='baseline' then
   baselineSummaryLines,baselinePayloadLines=lineCount(summaryText),lineCount(payload)
   check(baselineSummaryLines>0 and baselinePayloadLines>0,
    'the baseline report has lines to compare against: '..baselineSummaryLines
    ..'/'..baselinePayloadLines)
  else
   -- A poisoned owner may cost its OWN line - a failing owner loses only
   -- what it was going to say - but no value may ADD one.
   check(owner=='raising' or lineCount(summaryText)<=baselineSummaryLines,
    'poisoned '..owner..': the summary gained a line: '..lineCount(summaryText)
    ..' vs '..baselineSummaryLines)
   check(owner=='raising' or lineCount(payload)<=baselinePayloadLines,
    'poisoned '..owner..': the payload gained a line: '..lineCount(payload)
    ..' vs '..baselinePayloadLines)
  end
  if okJob and type(job)=='table' and type(job.report)=='table' then
   for field,value in pairs(job.report.meta or {}) do
    if type(value)=='string' then clean(value,'poisoned '..owner..' meta.'..field) end
   end
  end
 end
end

-- 19. The public entries accept a CALLER's incident. One whose own fields
-- raise on __index, or whose sub-tables do, must cost that incident only.
do
 local hostileIncident=setmetatable({},{__index=function() error('hostile row') end})
 local okHostileSummary,hostileText=pcall(builder.Summary,hostileIncident)
 check(okHostileSummary,'a hostile caller incident does not take the summary away: '
  ..tostring(hostileText))
 local okHostileFile=pcall(builder.NewPreparation,{incident=hostileIncident})
 check(okHostileFile,'or the prepared-file route')
 local okHostileLines,hostileLines=pcall(builder.IncidentLines,hostileIncident)
 check(okHostileLines and type(hostileLines)=='table','or the incident lines themselves')
 local nested={id=1,kind='catalog-refusal',reason='R',occurrences=1,
  counts=setmetatable({},{__index=function() error('hostile counts') end}),
  affected={setmetatable({},{__index=function() error('hostile tuple') end})}}
 local okNested,nestedText=pcall(builder.Summary,nested)
 check(okNested,'and neither does a hostile sub-table: '..tostring(nestedText))
end

-- 20. The escape the page depends on, pinned: a recorded label must not be
-- able to inject a colour or hyperlink sequence into a font string.
check(builder.Escape('a|b')=='a||b','one pipe is escaped')
check(builder.Escape('|cffff0000|Hitem:1|h[x]|h|r')=='||cffff0000||Hitem:1||h[x]||h||r',
 'and every pipe of an escape sequence is: '..builder.Escape('|cffff0000|Hitem:1|h[x]|h|r'))
check(builder.Escape('plain')=='plain','while ordinary text is unchanged')

-- 21. The page. It must not reach into the storage component for itself, and
-- a component that answers some entries and not others must not take the page
-- away - which is exactly the shape the sweep installs.
do
 local realStorage=_G.NexusSupportStorage
 local PAGEPOISON='PAGE'..string.char(1)..string.char(10)..string.rep('Y',600)
 for _,shape in ipairs({
  -- An incompatible component: the page says so and stops there.
  {Latest=function() return {} end,
   Status=function() return {loaded=true,ready=true,incompatible=PAGEPOISON} end},
  -- A working component whose stored report describes itself in poison: the
  -- page reaches the stored summary, so every field of it is converted.
  {Latest=function() return {id=PAGEPOISON,bytes=PAGEPOISON,
    chunkCount=PAGEPOISON,checksum=PAGEPOISON} end,
   Status=function() return {loaded=true,ready=true} end},
  {Replace=function() return true end,Status=function() return {loaded=true,ready=true} end},
  {Latest=function() error('hostile latest') end,
   Status=function() return {loaded=true,ready=true} end},
  {Status=function() return setmetatable({},{__index=function() error('hostile status') end}) end},
  setmetatable({},{__index=function() error('hostile component') end}),
  'not a table',
 }) do
  _G.NexusSupportStorage=shape
  local okPage=pcall(function() Nexus.SupportReportUI.Show() end)
  check(okPage,'a partial or hostile storage component does not take the page away')
  local line=page.storage and page.storage:GetText() or ''
  check(type(line)=='string' and #line>0,'and the page still says something about storage')
  local pageBad
  for index=1,#line do
   local byte=line:byte(index)
   if byte<32 and byte~=10 then pageBad=byte;break end
  end
  check(pageBad==nil,'the storage line carries no control byte: '..tostring(pageBad))
  check(line:find(string.rep('Y',400),1,true)==nil,
   'and nothing unbounded from the component reaches it')
 end
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 22. The storage component is read ONE lookup and call at a time, inside a
-- pcall, and everything it returns is copied. A component whose __index
-- answers once and then raises is the shape that proves both.
do
 local realStorage=_G.NexusSupportStorage
 local builderRef=builder
 local function stateful(entries)
  local answered={}
  return setmetatable({},{__index=function(_,key)
   if answered[key] then error('second read of '..tostring(key)) end
   answered[key]=true
   return entries[key]
  end})
 end
 _G.NexusSupportStorage=stateful({
  Latest=function() return {id='S',bytes=1,chunkCount=1,checksum='abcd1234'} end,
  Read=function() return {chunks={'x'}} end,
  Status=function() return {loaded=true,ready=true} end,
  Replace=function() return true,{bytes=1,chunkCount=1,checksum='abcd1234'} end})
 local okStored,stored=pcall(builderRef.StoredSummary)
 check(okStored,'a component whose __index answers once does not raise: '..tostring(stored))
 local okReport=pcall(builderRef.StoredReport)
 check(okReport,'and neither does the stored-report reader')
 local okStatus2=pcall(builderRef.StorageStatus)
 check(okStatus2,'nor the status reader')
 local okStore2=pcall(builderRef.Store,{chunks={'x'}})
 check(okStore2,'nor the store route')
 local okPage2=pcall(function() Nexus.SupportReportUI.Show() end)
 check(okPage2,'nor the page')
 -- What it returns is a shape this addon owns, not the component's table.
 local componentTable={id='T',bytes=2,chunkCount=1,checksum='dead',extra='leak'}
 _G.NexusSupportStorage={Latest=function() return componentTable end,
  Read=function() return {chunks={'x'}} end,
  Status=function() return {loaded=true,ready=true} end}
 local owned=builderRef.StoredSummary()
 check(owned~=componentTable,'the stored summary is not the component table')
 check(owned.extra==nil,'and carries no field this addon did not ask for')
 check(getmetatable(owned)==nil,'and no metatable of theirs')
 -- A component that says it is NOT incompatible is compatible.
 _G.NexusSupportStorage={Replace=function() return true,{} end,
  Status=function() return {loaded=true,ready=true,incompatible=false,reason=false} end}
 local status=builderRef.StorageStatus()
 check(status.incompatible==nil,'incompatible=false is not an incompatibility: '
  ..tostring(status.incompatible))
 check(status.reason==nil,'and reason=false is not a reason: '..tostring(status.reason))
 check(status.loaded==true and status.ready==true,'while the rest of the status is kept')
 -- A component that says nothing is not loaded.
 _G.NexusSupportStorage={Replace=function() return true,{} end,
  Status=function() return {} end}
 local silent=builderRef.StorageStatus()
 check(silent.loaded==true and silent.ready==false,
  'a component that ANSWERS is loaded, and says for itself whether it is ready: '
  ..tostring(silent.loaded)..'/'..tostring(silent.ready))
 _G.NexusSupportStorage=nil
 local absent=builderRef.StorageStatus()
 check(absent.loaded==false and absent.ready==false,
  'while a component that is not there is neither: '
  ..tostring(absent.loaded)..'/'..tostring(absent.ready))
 -- Bounds on what the component can put on the page.
 local LONG=string.rep('W',900)
 _G.NexusSupportStorage={Latest=function()
   return {id=LONG,bytes=LONG,chunkCount=LONG,checksum=LONG} end,
  Read=function() return {chunks={'x'}} end,
  Status=function() return {loaded=true,ready=true} end}
 local bounded=builderRef.StoredSummary()
 check(#bounded.id<=48 and #bounded.bytes<=24 and #bounded.chunkCount<=16
  and #bounded.checksum<=24,'every stored-summary field is bounded: '..#bounded.id
  ..'/'..#bounded.bytes..'/'..#bounded.chunkCount..'/'..#bounded.checksum)
 -- The page's own Inspect handler reads the same owned shape.
 Nexus.SupportReportUI.Show()
 local inspect
 for _,b in ipairs(H.frames) do
  if b.kind=='Button' and b:GetText()=='Inspect prepared report' then inspect=b end
 end
 check(inspect~=nil,'the Inspect control exists')
 local okInspect=pcall(function() inspect:Click() end)
 check(okInspect,'and a hostile component does not take it away')
 local inspectText=page.prepared and page.prepared:GetText() or ''
 check(inspectText:find(string.rep('W',200),1,true)==nil,
  'nothing unbounded from the component reaches the page: '..#inspectText)
 local inspectBad
 for index=1,#inspectText do
  local byte=inspectText:byte(index)
  if byte<32 and byte~=10 then inspectBad=byte;break end
 end
 check(inspectBad==nil,'and no control byte either: '..tostring(inspectBad))
 _G.NexusSupportStorage=setmetatable({},{__index=function() error('hostile component') end})
 check(pcall(function() inspect:Click() end),'a raising component does not take Inspect away')
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 23. The prepared-file route survives a component that returns less than the
-- one shipped with this addon does.
do
 local realStorage=_G.NexusSupportStorage
 _G.NexusSupportStorage={Replace=function() return true end,
  Status=function() return {loaded=true,ready=true} end,
  Latest=function() return nil end,Read=function() return nil end}
 local okBare=pcall(function() return Nexus.SupportReportUI.PrepareFile(false) end)
 check(okBare,'a component that returns no header does not break the file route')
 _G.NexusSupportStorage=realStorage
end

-- 24. A stored copy that no longer agrees with its own checksum must SAY so.
-- The verdict is false, not absent, and "false or nil" cannot carry it.
do
 local realStorage=_G.NexusSupportStorage
 local intact={id='R-1',bytes=3,chunkCount=1,checksum=builder.Checksum({'abc'})}
 _G.NexusSupportStorage={
  Latest=function() return intact end,
  Read=function() return {chunks={'abc'}} end,
  Status=function() return {loaded=true,ready=true} end}
 local good=builder.StoredReport()
 check(good~=nil and good.matches==true,'an intact stored copy verifies: '
  ..tostring(good and good.matches))
 -- The same header, one byte of the stored copy changed.
 _G.NexusSupportStorage={
  Latest=function() return intact end,
  Read=function() return {chunks={'abd'}} end,
  Status=function() return {loaded=true,ready=true} end}
 local bad=builder.StoredReport()
 check(bad~=nil,'a corrupted stored copy is still readable')
 check(bad.matches==false,'and its verdict is FALSE, not absent: '..tostring(bad.matches))
 check(bad.recomputed~=nil and bad.recomputed~=bad.checksum,
  'the recomputed checksum differs from the stored one: '..tostring(bad.recomputed))
 Nexus.SupportReportUI.Show()
 local inspect
 for _,b in ipairs(H.frames) do
  if b.kind=='Button' and b:GetText()=='Inspect prepared report' then inspect=b end
 end
 inspect:Click()
 local said=page.prepared:GetText()
 check(said:find('CHECKSUM MISMATCH',1,true)~=nil,
  'and the page says so in words: '..said:sub(1,160))
 -- A component that cannot be read at all states nothing either way.
 _G.NexusSupportStorage={
  Latest=function() return intact end,
  Read=function() return nil end,
  Status=function() return {loaded=true,ready=true} end}
 local unknown=builder.StoredReport()
 check(unknown~=nil and unknown.matches==nil,
  'an unreadable stored copy claims neither: '..tostring(unknown.matches))
 -- A Read that RAISES is not a mismatch: the error text is not a checksum.
 _G.NexusSupportStorage={
  Latest=function() return intact end,
  Read=function() error('the component exploded') end,
  Status=function() return {loaded=true,ready=true} end}
 local raised=builder.StoredReport()
 check(raised~=nil and raised.matches==nil,
  'a component whose Read raises does not produce a mismatch verdict: '
  ..tostring(raised.matches))
 check(raised.recomputed==nil,'and no error text is kept as a checksum: '
  ..tostring(raised.recomputed))
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 25. What the component sends comes back as a verdict and a copied header,
-- never as its own table, and its text is escaped before it is displayed.
do
 local realStorage=_G.NexusSupportStorage
 local theirs={partial=true,omissions='|cffff0000|Hitem:1|h[x]|h|r',
  bytes={},chunkCount=2,id='ID|PIPE',secret='leak'}
 _G.NexusSupportStorage={Replace=function() return theirs,theirs end,
  Status=function() return {loaded=true,ready=true} end,
  Latest=function() return {id='ID|PIPE',bytes=1,chunkCount=1,checksum='c'} end,
  Read=function() return {chunks={'x'}} end}
 local stored,meta=builder.Store({chunks={'x'}})
 check(stored==true,'the store verdict is a boolean, not their table: '..type(stored))
 check(meta~=theirs,'and the header is a copy')
 check(meta.secret==nil,'carrying no field this addon did not ask for')
 check(meta.bytes==nil,'a header field of the wrong type is dropped, not passed on')
 check(meta.chunkCount==2,'while a good one keeps its type: '..type(meta.chunkCount))
 check(meta.partial==true,'and the partial flag survives')
 -- The page displays it escaped, like everything else it shows.
 Nexus.SupportReportUI.Show()
 local line=page.storage:GetText()
 check(line:find('||',1,true)~=nil or line:find('|',1,true)==nil,
  'the storage line escapes a pipe from the component: '..line:sub(1,120))
 local prepared=Nexus.SupportReportUI.PrepareFile(false)
 local note=page.prepared:GetText()
 check(note:find('This report is partial',1,true)~=nil,
  'a partial header is declared on the page: '..note:sub(1,160))
 check(not note:find('|c',1,true) or note:find('||c',1,true)~=nil,
  'and the omission text is escaped: '..note:sub(1,160))
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 26. A component entry that is not a function is not a component.
do
 local realStorage=_G.NexusSupportStorage
 _G.NexusSupportStorage={Replace='not a function',Status='not a function'}
 local status=builder.StorageStatus()
 check(status.loaded==false,'a non-function entry is not a loaded component: '
  ..tostring(status.loaded))
 local stored,why=builder.Store({chunks={'x'}})
 check(stored==nil and tostring(why):find('not loaded',1,true)~=nil,
  'and the store route says which: '..tostring(why))
 _G.NexusSupportStorage=realStorage
end

-- 27. No heap address reaches a report.
check(builder.Summary({kind={},reason=print,producer=coroutine.create(function() end)})
 :find('0x',1,true)==nil,'a table, function or coroutine is named, not addressed')

-- 28. A component states why it refused. That reason is what the player is
-- shown - the shipped component refuses that way in every failure it has.
do
 local realStorage=_G.NexusSupportStorage
 _G.NexusSupportStorage={
  Replace=function() return nil,'the saved data was written by a newer version (99)' end,
  Status=function() return {loaded=true,ready=true} end}
 local stored,why=builder.Store({chunks={'x'}})
 check(stored==nil,'a refusing component does not report a stored report')
 check(tostring(why):find('newer version (99)',1,true)~=nil,
  'and its own words reach the caller: '..tostring(why))
 Nexus.SupportReportUI.Show()
 local prepared,pageWhy=Nexus.SupportReportUI.PrepareFile(false)
 check(prepared==nil,'the page does not claim a file was prepared')
 check(page.prepared:GetText():find('newer version (99)',1,true)~=nil,
  'and says why, in the component words: '..page.prepared:GetText():sub(1,140))
 -- A component that refuses with no words at all still gets a sentence.
 _G.NexusSupportStorage={Replace=function() return nil end,
  Status=function() return {loaded=true,ready=true} end}
 local _,bare=builder.Store({chunks={'x'}})
 check(type(bare)=='string' and #bare>0,'a silent refusal still states something: '..tostring(bare))
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 29. Every value the page displays is escaped ONCE: not zero times, which
-- lets a component colour the page, and not twice, which corrupts the text.
do
 local realStorage=_G.NexusSupportStorage
 local COLOUR='|cffff0000RED|r'
 _G.NexusSupportStorage={
  Replace=function() return true,{id=COLOUR,bytes=1,chunkCount=1,checksum='c'} end,
  Status=function() return {loaded=true,ready=true,incompatible=false} end,
  Latest=function() return {id=COLOUR,bytes=1,chunkCount=1,checksum='c'} end,
  Read=function() return {chunks={'x'}} end}
 Nexus.SupportReportUI.Show()
 Nexus.SupportReportUI.PrepareFile(false)
 local notice=page.prepared:GetText()
 check(notice:find('||cffff0000',1,true)~=nil,
  'the written notice escapes the component id once: '..notice:sub(1,120))
 check(notice:find('||||c',1,true)==nil,'and not twice')
 -- The incompatible sentence on the prepare path, which had none.
 _G.NexusSupportStorage={
  Replace=function() return true,{} end,
  Status=function() return {loaded=true,ready=true,incompatible=COLOUR} end}
 Nexus.SupportReportUI.Show()
 Nexus.SupportReportUI.PrepareFile(false)
 local refused=page.prepared:GetText()
 check(refused:find('||cffff0000',1,true)~=nil,
  'the prepare refusal escapes it too: '..refused:sub(1,140))
 check(refused:find('||||c',1,true)==nil,'once, not twice')
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 30. "Loaded" means the same thing in the status, on the page and on the
-- file route. A component that is there but not ready must not be called
-- ready by the page.
do
 local realStorage=_G.NexusSupportStorage
 local shapes={
  {name='answers, not ready',component={Replace=function() return true,{} end,
    Status=function() return {loaded=false,ready=false,reason='still loading'} end},
   loaded=true,ready=false},
  {name='answers with nonsense',component={Replace=function() return true,{} end,
    Status=function() return 'fine' end},loaded=true,ready=false},
  {name='status raises',component={Replace=function() return true,{} end,
    Status=function() error('no') end},loaded=true,ready=false},
  {name='no status entry',component={Replace=function() return true,{} end},
   loaded=false,ready=false},
  {name='absent',component=nil,loaded=false,ready=false},
 }
 for _,shape in ipairs(shapes) do
  _G.NexusSupportStorage=shape.component
  local status=builder.StorageStatus()
  check(status.loaded==shape.loaded,shape.name..': loaded is '..tostring(shape.loaded)
   ..', got '..tostring(status.loaded))
  check(status.ready==shape.ready,shape.name..': ready is '..tostring(shape.ready)
   ..', got '..tostring(status.ready))
  Nexus.SupportReportUI.Show()
  local line=page.storage:GetText()
  if not status.ready then
   check(line:find('ready; no report',1,true)==nil,
    shape.name..': the page does not call it ready: '..line:sub(1,120))
  end
 end
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 31. The copied header is bounded too, not only the stored summary.
do
 local realStorage=_G.NexusSupportStorage
 local LONG=string.rep('H',900)
 _G.NexusSupportStorage={
  Replace=function() return true,{id=LONG,build=LONG,topic=LONG,checksum=LONG,
   omissions=LONG,bytes=1,chunkCount=1} end,
  Status=function() return {loaded=true,ready=true} end}
 local _,meta=builder.Store({chunks={'x'}})
 for _,field in ipairs({'id','build','topic','checksum','omissions'}) do
  check(#tostring(meta[field])<=120,'the copied header bounds '..field..': '
   ..#tostring(meta[field]))
 end
 _G.NexusSupportStorage=realStorage
end

-- 32. A healthy start-up has NO reason, and the owner says so with the
-- boolean false rather than nil. The report must omit the line, not print
-- the word "false" - on both routes, in the very line this work added.
do
 local realStatus=Nexus.StartupStatus
 Nexus.StartupStatus=function()
  return {state='ready',coreReady=true,phase='complete',reason=false}
 end
 local healthy=builder.Summary()
 check(healthy:find('reason: false',1,true)==nil,
  'the copyable summary states no reason when there is none: '
  ..tostring(healthy:match('[^'..string.char(10)..']*reason[^'..string.char(10)..']*')))
 check(healthy:find('Startup: state ready',1,true)~=nil,'while the state is still stated')
 local healthyJob=builder.NewPreparation({extended=true})
 local healthyGuard=0
 while builder.Step(healthyJob)=='pending' and healthyGuard<400 do healthyGuard=healthyGuard+1 end
 local healthyText=table.concat(healthyJob.chunks or {},'')
 check(healthyText:find('reason=false',1,true)==nil,
  'and the prepared file does not either: '
  ..tostring(healthyText:match('reason=[^'..string.char(10)..']*')))
 check(healthyText:find('state=ready',1,true)~=nil,'while it still carries the state')
 -- coreReady=false is a real answer and must survive the same guard.
 Nexus.StartupStatus=function()
  return {state='failed',coreReady=false,reason='SOURCE_KEY_WIDTH_EXCEEDED'}
 end
 local failedJob=builder.NewPreparation({extended=true})
 local failedGuard=0
 while builder.Step(failedJob)=='pending' and failedGuard<400 do failedGuard=failedGuard+1 end
 local failedText=table.concat(failedJob.chunks or {},'')
 check(failedText:find('coreReady=false',1,true)~=nil,
  'core ready false is still written: '..failedText:sub(1,200))
 check(failedText:find('reason=SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,
  'and a real reason still reaches the file')
 check(builder.Summary():find('reason: SOURCE_KEY_WIDTH_EXCEEDED',1,true)~=nil,
  'and the summary')
 Nexus.StartupStatus=realStatus
end

-- 33. Every "Not prepared" line the page writes is escaped, whatever supplied
-- the words - the three of them, not two of the three.
do
 local realStorage=_G.NexusSupportStorage
 _G.NexusSupportStorage={
  Replace=function() return nil,'refused: |cffff0000RED|r' end,
  Status=function() return {loaded=true,ready=true} end}
 Nexus.SupportReportUI.Show()
 Nexus.SupportReportUI.PrepareFile(false)
 local refusal=page.prepared:GetText()
 check(refusal:find('||cffff0000',1,true)~=nil,
  'a component refusal is escaped on the page: '..refusal:sub(1,140))
 check(refusal:find('||||c',1,true)==nil,'once, not twice')
 _G.NexusSupportStorage=realStorage
 Nexus.SupportReportUI.Show()
end

-- 34. v23 (C): the Build Library and this page, opened in either order, never
-- draw over each other (native 163028 showed them overlapping: both are
-- DIALOG level 50 and the Library's controls reach level 70). The window
-- opened last is shown in full: the other is hidden for display only through
-- its own public Hide, or lies wholly below it in the same DIALOG strata. The
-- PROPOSED minimal owned route: SupportReportUI.Show hides the Library through
-- Nexus.CommunityBuilds.Hide when it is shown, and the Library's Show hides
-- this page through Nexus.SupportReportUI.Hide; no strata, window-manager or
-- CloseOtherWindows change, and opening this page closes no other window (the
-- Wishlist Editor stays). Every piece of state each owns is kept across both
-- orders: the Library's search text, selected build and the open Share form
-- with its typed draft; this page's copied summary, notes, incident, the
-- private-details box and the stored report. Nothing is prepared, sent or
-- synced and no game action is taken. Fixture (read in source): the page is
-- ready (section 3 waits for it), so CommunityBuilds.Show and ShowPostBuild
-- pass WaitForStartup and build the renderer lazily (CommunityBuilds.lua
-- 53-55, 237-251, 361-412); ShowPostBuild opens NexusPostPopup even without a
-- Wishlist and toggles it closed when it is already open, so it is called
-- once (CommunityRenderer.lua 1816-1857). The Library is DIALOG level 50 with
-- controls at +10 and +20 (3205, 3444, 3478, 4028). In-flight Share status is
-- UNVERIFIED here: it needs a submitted Share (a send), and this fixture has no
-- supported seam that holds one without acting. Misses are collected, then
-- raised together.
do
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local CB,UI=Nexus.CommunityBuilds,Nexus.SupportReportUI
 local function descendant(f,parent) while f do if f==parent then return true end;f=f:GetParent() end;return false end
 local function Highest(win)
  local top=win:GetFrameLevel()
  for _,f in ipairs(H.frames) do
   if f~=win and f.kind~='Texture' and f.kind~='FontString' and f:IsVisible() and descendant(f,win) then
    top=math.max(top,f:GetFrameLevel())
   end
  end
  return top
 end
 local function Clear(front,back,tag)
  expect(front~=nil and front:IsShown(),tag..': the window opened last is shown')
  if not (front and back) then return end
  expect(front:GetFrameStrata()=='DIALOG' and back:GetFrameStrata()=='DIALOG',tag..': both keep the DIALOG strata')
  if back:IsShown() then
   local top=Highest(back)
   expect(front:GetFrameLevel()>top and Highest(front)<128,
    tag..': the window opened last is drawn wholly above the other or the other is hidden (front '
    ..front:GetFrameLevel()..', other window reaches '..top..')')
  end
 end
 local function SupportState()
  local report=NexusSupportDB and NexusSupportDB.report
  return table.concat({tostring(page.copyBox:GetText()),tostring(page.copyNote:GetText()),tostring(page.prepared:GetText()),
   tostring(page.incident:GetText()),tostring(page.advanced:GetChecked()),
   tostring(report and report.meta and report.meta.id),tostring(report and report.chunks and #report.chunks)},'\n--\n')
 end
 local function LibraryState()
  local search,popup=_G.NexusBuildsSearch,_G.NexusPostPopup
  local title=popup and popup._postTitleBox
  -- The draft as the Share form itself submits it (its raw-text accessor,
  -- CommunityRenderer ConfigureSafeEditableText), and as shown.
  local draft=title and (type(title._NexusRawText)=='function' and title:_NexusRawText() or title:GetText())
  return table.concat({tostring(search and search:GetText()),tostring(popup and popup:IsShown() or false),
   tostring(draft),tostring(title and title:GetText()),
   tostring(CB and CB.GetSelectedBuildForPanelKey and CB.GetSelectedBuildForPanelKey())},'\n--\n')
 end
 -- The Library's public entries, guarded so a raise is reported, not fatal.
 local function Library(name)
  local ok,why=pcall(CB and CB[name] or error)
  expect(ok,'Nexus.CommunityBuilds.'..name..' runs ('..tostring(why)..')')
 end
 -- Set up each window's own state through its real controls (typed text).
 UI.Hide()
 Library('Show')
 local lib=_G.NexusCommunityBuildsFrame
 expect(lib~=nil and lib:IsShown(),'SETUP: the Build Library opens through Nexus.CommunityBuilds.Show')
 local search=_G.NexusBuildsSearch
 expect(search~=nil,'SETUP: the Library search box')
 if search then search:SetText('');search:Insert('v23 kept search') end
 Library('ShowPostBuild')
 local popup=_G.NexusPostPopup
 expect(popup~=nil and popup:IsShown() and popup._postTitleBox~=nil,'SETUP: the Share form is open')
 if popup and popup._postTitleBox then popup._postTitleBox:SetText('');popup._postTitleBox:Insert('v23 kept draft') end
 local typed=popup and popup._postTitleBox and type(popup._postTitleBox._NexusRawText)=='function'
  and popup._postTitleBox:_NexusRawText()
 expect(typed=='v23 kept draft','SETUP: the Share form holds the typed draft ('..tostring(typed)..')')
 expect(search==nil or search:GetText()=='v23 kept search','SETUP: the search box holds the typed search')
 Library('Show')
 UI.Show();button('Copy summary',page):Click();UI.Show()
 local libBase,supBase=LibraryState(),SupportState()
 expect(supBase:find('Nexus support summary',1,true)~=nil,'SETUP: the copied summary is in this page\'s buffer')
 local acts,sent,loads=#H.actions,#H.sent,companionLoads
 -- Library, then this page (counted: this page's own Show closes nothing).
 local realClose=Nexus.Panel and Nexus.Panel.CloseOtherWindows
 local closes=0
 Library('Show')
 expect(lib==nil or lib:IsShown(),'SETUP: the Library is open again')
 if realClose then Nexus.Panel.CloseOtherWindows=function(...) closes=closes+1;return realClose(...) end end
 UI.Show()
 if realClose then Nexus.Panel.CloseOtherWindows=realClose end
 Clear(page,lib,'Library, then Support')
 expect(closes==0,'opening Support uses no blanket close of other windows ('..closes..' calls)')
 expect(LibraryState()==libBase,'Library, then Support: the search, selection and Share draft are kept')
 expect(SupportState()==supBase,'Library, then Support: the copied summary and report state are kept')
 -- This page, then the Library.
 UI.Show();Library('Show')
 Clear(lib,page,'Support, then Library')
 expect(LibraryState()==libBase,'Support, then Library: the search, selection and Share draft are kept')
 -- Both again: the real command for this page, the public Show for the Library.
 SlashCmdList.NEXUS('report')
 Clear(page,lib,'Library, then /nexus report')
 expect(SupportState()==supBase,'reopened Support keeps its copied summary and report state')
 Library('Show')
 Clear(lib,page,'/nexus report, then Library')
 expect(LibraryState()==libBase,'reopened Library keeps its search, selection and Share draft')
 -- Opening this page leaves another Nexus window, here the Wishlist Editor
 -- with its draft, open.
 Library('Hide');UI.Hide()
 SlashCmdList.NEXUS('editor')
 local editor=_G.NexusEditorFrame
 if editor and editor:IsShown() then
  UI.Show()
  expect(editor:IsShown(),'opening Support leaves the Wishlist Editor open')
  editor:Hide()
 end
 expect(#H.actions==acts and #H.sent==sent and companionLoads==loads,
  'switching between the two windows takes no game action, sends nothing and loads no storage')
 if popup then popup:Hide() end
 UI.Show()
 if #misses>0 then error('v23 Library/Support order: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0) end
end

-- 35. v26 (native X1, test.163031): the client's own "Select an Echo" control,
-- PerkChooseButton (read-only on 3.3.5 / 12340: DIALOG strata, level 110,
-- parent UIParent, shown, anchored TOP to ProjectEbonholdPerkFrame BOTTOM
-- 0,-50), covers the Reference body (Help, DIALOG 40) and the Support page and
-- Build Library (DIALOG 50). Contract: while that one known frame is shown in
-- the same DIALOG strata, every owned frame of a shown Help, Library or Support
-- window that draws in DIALOG stands above it (above 110), no owned frame goes
-- past 127 (the band the existing layer tests keep below the observed native
-- 128/129 parent/child failure), and the window's own tree keeps its
-- parent/child and sibling order. When the window hides, its default levels
-- come back. When the frame is absent, hidden, in another strata, not a frame,
-- or cannot be read, every owned level stays the default. The foreign frame is
-- never changed, clicked or scripted. No owned frame changes strata; the owned
-- Share form (FULLSCREEN_DIALOG) stays above its Library and the dropdown
-- shield below it. Repeated opens give the same levels and add no frame or
-- hook. Nothing enumerates frames, acts, sends or writes settings.
-- Fixture (stated, not native): a fresh real session in which a frame created
-- with a parent other than UIParent starts one level above its parent and
-- draws in its parent's strata unless it sets its own (client creation
-- semantics; stop_sharing_layer_support models the same strata inheritance).
-- The harness has neither by itself: an unlevelled child reads 1 and strata
-- MEDIUM. Not modelled (UNKNOWN natively): whether the client moves children
-- when a parent's level changes later; so the owned levels are read as the
-- frames report them. Misses are collected, then raised together.
do
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local PERK,CEILING=110,127
 local RANK={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusSupportDB=nil;NexusSupportStorage=nil
 local H2=dofile('tests/prototype/harness.lua')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template,...)
  local f=create(kind,name,parent,template,...)
  local p=parent;if type(p)=='string' then p=_G[p] end
  if type(p)=='table' and p~=UIParent and kind~='Font' then
   rawset(f,'frameLevel',(tonumber(p:GetFrameLevel()) or 0)+1)
   rawset(f,'GetFrameStrata',function(self)
    local own=rawget(self,'strata');if own then return own end
    local q=self:GetParent();return q and q:GetFrameStrata() or 'MEDIUM'
   end)
  end
  return f
 end
 -- Any frame enumeration by the addon is counted (none is expected).
 local enumerations,hadEnumerate=0,EnumerateFrames
 EnumerateFrames=function(...) enumerations=enumerations+1;if hadEnumerate then return hadEnumerate(...) end end
 NexusDB=T.Profile(0,0)
 T.Load();H2.Fire('ADDON_LOADED','Nexus');H2.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H2,function()return Nexus.StartupStatus().state=='ready' end)
 local function Serialize(v,seen)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
  local out={'{'};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen)..',' end
  seen[v]=nil;return table.concat(out)..'}'
 end
 local Help,CB,UI=Nexus.Help,Nexus.CommunityBuilds,Nexus.SupportReportUI
 local acts,sent,settings=#H2.actions,#H2.sent,Serialize(NexusDB.settings)
 local function descendant(f,root)
  local p=f:GetParent()
  while p do if p==root then return true end;p=p:GetParent() end
  return false
 end
 local function Tree(win)
  local out={win}
  for _,f in ipairs(H2.frames) do if f~=win and descendant(f,win) then out[#out+1]=f end end
  return out
 end
 local function Levels(win)
  local t={}
  for _,f in ipairs(Tree(win)) do t[f]={level=f:GetFrameLevel(),strata=f:GetFrameStrata()} end
  return t
 end
 local function Btn(win,label)
  for _,b in ipairs(H2.frames) do if b.kind=='Button' and b:GetParent()==win and b:GetText()==label then return b end end
 end
 -- GUARD form: every frame of the default record keeps its level and strata.
 local function Same(tag,win,base)
  local changed,n=0,0
  for f,b in pairs(base) do
   n=n+1
   if f:GetFrameLevel()~=b.level or f:GetFrameStrata()~=b.strata then changed=changed+1 end
  end
  expect(n>0 and changed==0,tag..': every owned frame keeps its default level and strata ('..changed..' of '..n..' changed)')
 end
 local function sign(x) return x>0 and 1 or x<0 and -1 or 0 end
 -- EXPECT form: above the shown frame, within the band, order and strata kept.
 local function Raised(tag,win,base)
  local tree,inTree,byParent={},{},{}
  tree=Tree(win)
  local n,below,over,strata,lo,hi=0,0,0,0,math.huge,-math.huge
  for _,f in ipairs(tree) do
   inTree[f]=true
   local b=base[f]
   if b and f:GetFrameStrata()~=b.strata then strata=strata+1 end
   if f:GetFrameStrata()=='DIALOG' then
    local L=tonumber(f:GetFrameLevel()) or 0
    n=n+1;lo=math.min(lo,L);hi=math.max(hi,L)
    if L<=PERK then below=below+1 end
    if L>CEILING then over=over+1 end
   end
   if f~=win then local p=f:GetParent();byParent[p]=byParent[p] or {};table.insert(byParent[p],f) end
  end
  local flipped=0
  local function pair(a,c)
   local ba,bc=base[a],base[c]
   if ba and bc and sign(ba.level-bc.level)~=sign(a:GetFrameLevel()-c:GetFrameLevel()) then flipped=flipped+1 end
  end
  for p,kids in pairs(byParent) do
   for i,c in ipairs(kids) do
    if inTree[p] then pair(p,c) end
    for j=i+1,#kids do pair(c,kids[j]) end
   end
  end
  expect(n>0 and below==0,tag..': every owned DIALOG frame stands above the shown PerkChooseButton at '..PERK
   ..' ('..below..' of '..n..' at or below it; owned levels '..tostring(lo)..'-'..tostring(hi)..')')
  expect(over==0,tag..': no owned frame goes past '..CEILING..' ('..over..' over)')
  expect(flipped==0,tag..': the window keeps its parent/child and sibling order ('..flipped..' pairs reversed)')
  expect(strata==0,tag..': no owned frame changes strata ('..strata..' changed)')
 end
 local function NoDrift(tag,ref)
  local changed,n=0,0
  for f,r in pairs(ref) do n=n+1;if f:GetFrameLevel()~=r.level then changed=changed+1 end end
  expect(changed==0,tag..': a repeated open gives the same levels ('..changed..' of '..n..' moved)')
 end

 -- a. No such frame: the default levels, recorded through the real paths.
 check(_G.PerkChooseButton==nil,'v26 SETUP: no PerkChooseButton in this session yet')
 Help.Show('start')
 local help=assert(NexusHelpWindow,'v26 SETUP: the Help window')
 local baseHelp=Levels(help)
 local helpClose=assert(Btn(help,'Close'),'v26 SETUP: Help Close')
 check(help:GetFrameStrata()=='DIALOG' and help:GetFrameLevel()==40,'v26 SETUP: Help is DIALOG 40 by default')
 helpClose:Click()
 check(select(1,pcall(CB.Show)),'v26 SETUP: the Build Library opens through Nexus.CommunityBuilds.Show')
 local lib=assert(NexusCommunityBuildsFrame,'v26 SETUP: the Library window')
 check(lib:GetFrameStrata()=='DIALOG' and lib:GetFrameLevel()==50,'v26 SETUP: the Library is DIALOG 50 by default')
 local baseLib=Levels(lib)
 UI.Show()
 local sup=assert(NexusSupportReport,'v26 SETUP: the Support page')
 check(sup:GetFrameStrata()=='DIALOG' and sup:GetFrameLevel()==50 and not lib:IsShown(),
  'v26 SETUP: Support is DIALOG 50 by default and its opening hid the Library')
 local baseSup=Levels(sup)
 local supClose=assert(Btn(sup,'Close'),'v26 SETUP: Support Close')
 supClose:Click()
 Help.Show('start');Same('absent: Help',help,baseHelp);helpClose:Click()
 CB.Show();Same('absent: Library',lib,baseLib);CB.Hide()
 UI.Show();Same('absent: Support',sup,baseSup);supClose:Click()

 -- The known frame, as the client reported it. Its mutators count any call
 -- from the addon; the test changes it only through the methods kept here.
 local anchor=_G.ProjectEbonholdPerkFrame or CreateFrame('Frame','ProjectEbonholdPerkFrame',UIParent)
 local perk=CreateFrame('Button','PerkChooseButton',UIParent)
 perk:SetFrameStrata('DIALOG');perk:SetFrameLevel(PERK);perk:SetPoint('TOP',anchor,'BOTTOM',0,-50)
 perk:SetText('Select an Echo')
 local clicks=0;local onClick=function() clicks=clicks+1 end
 perk:SetScript('OnClick',onClick);perk:Show()
 local real={}
 for _,m in ipairs({'Show','Hide','SetFrameStrata','SetFrameLevel'}) do real[m]=perk[m] end
 local touched,touchedNames=0,{}
 for _,m in ipairs({'SetFrameLevel','SetFrameStrata','SetPoint','ClearAllPoints','SetAllPoints','SetParent','Show','Hide',
  'SetShown','Click','SetScript','HookScript','EnableMouse','SetAlpha','Raise','Lower','SetToplevel','Enable','Disable',
  'SetSize','SetWidth','SetHeight','SetText'}) do
  local orig=perk[m]
  rawset(perk,m,function(self,...)
   touched=touched+1;touchedNames[#touchedNames+1]=m
   if type(orig)=='function' then return orig(self,...) end
  end)
 end
 local function Snapshot()
  local a=perk.points[1] or {}
  return table.concat({tostring(rawget(perk,'strata')),tostring(rawget(perk,'frameLevel')),tostring(rawget(perk,'shown')),
   tostring(perk:GetParent()==UIParent),tostring(#perk.points),tostring(a[1]),tostring(a[2]==anchor),tostring(a[3]),
   tostring(a[4]),tostring(a[5]),tostring(perk.scripts.OnClick==onClick),tostring(perk:GetText())},'|')
 end
 local perkBefore=Snapshot()

 -- b. Shown in DIALOG at 110: Help, its return, Close, repeated opens.
 local returned=0
 Help.Show('start',function() returned=returned+1 end)
 Raised('shown: Help',help,baseHelp)
 local helpRaised,frames=Levels(help),#H2.frames
 local nextPage=Btn(help,'Next')
 if nextPage then nextPage:Click();NoDrift('shown: Help after a page change',helpRaised) end
 helpClose:Click()
 check(returned==1 and not help:IsShown(),'v26 GUARD: closing Help tells the window it stepped aside for, once')
 Same('shown, after Help closed',help,baseHelp)
 local onShow,onHide
 for i=1,4 do
  Help.Show('start')
  NoDrift('shown: Help open '..(i+1),helpRaised)
  if i==1 then onShow,onHide=help.scripts.OnShow,help.scripts.OnHide end
  helpClose:Click()
 end
 expect(#H2.frames==frames,'shown: repeated Help opens make no frame ('..frames..' -> '..#H2.frames..')')
 expect(help.scripts.OnShow==onShow and help.scripts.OnHide==onHide,'shown: repeated Help opens add no hook')

 -- c. Shown: the Library and Support in both orders, the Share form and draft.
 CB.Show()
 Raised('shown: Library',lib,baseLib)
 local libRaised=Levels(lib)
 pcall(CB.ShowPostBuild)
 local popup=_G.NexusPostPopup
 check(popup~=nil and popup:IsShown() and popup._postTitleBox~=nil,'v26 SETUP: the Share form is open over the Library')
 popup._postTitleBox:SetText('');popup._postTitleBox:Insert('v26 kept draft')
 local function Draft() return popup._postTitleBox:_NexusRawText() end
 local function PopupAbove(tag)
  expect(popup:IsShown() and (RANK[popup:GetFrameStrata()] or 0)>(RANK[lib:GetFrameStrata()] or 0),
   tag..': the Share form still stands above its Library ('..popup:GetFrameStrata()..' over '..lib:GetFrameStrata()..')')
  local shield=_G.NexusBuildDropdownShield
  expect(shield==nil or (shield:GetFrameStrata()=='DIALOG' and shield:GetFrameLevel()<lib:GetFrameLevel()),
   tag..': the dropdown shield stays in DIALOG below the Library')
 end
 PopupAbove('shown: Library')
 UI.Show()
 expect(not lib:IsShown() and sup:IsShown(),'shown: Library, then Support: the handoff still shows Support alone')
 Raised('shown: Support (Library, then Support)',sup,baseSup)
 Same('shown: Library hidden by Support',lib,baseLib)
 expect(popup:IsShown() and Draft()=='v26 kept draft','shown: the Share form and its draft are kept')
 CB.Show()
 expect(lib:IsShown() and not sup:IsShown(),'shown: Support, then Library: the handoff still shows the Library alone')
 Raised('shown: Library (Support, then Library)',lib,baseLib)
 NoDrift('shown: Library reopened',libRaised)
 Same('shown: Support hidden by the Library',sup,baseSup)
 PopupAbove('shown: Library reopened')
 expect(Draft()=='v26 kept draft','shown: the draft is kept through both orders')
 CB.Hide()
 Same('shown: Library hidden',lib,baseLib)
 popup:Hide()

 -- d. Hidden, another strata, unreadable, or not a frame: the defaults.
 local function Defaults(tag)
  local ok=pcall(Help.Show,'start')
  expect(ok,tag..': Help opens without an error')
  Same(tag..': Help',help,baseHelp);helpClose:Click()
  ok=pcall(CB.Show)
  expect(ok,tag..': the Library opens without an error')
  Same(tag..': Library',lib,baseLib);CB.Hide()
  ok=pcall(UI.Show)
  expect(ok,tag..': Support opens without an error')
  Same(tag..': Support',sup,baseSup);supClose:Click()
 end
 real.Hide(perk);Defaults('hidden')
 real.Show(perk)
 for _,strata in ipairs({'HIGH','FULLSCREEN'}) do
  real.SetFrameStrata(perk,strata);Defaults('shown in '..strata)
 end
 real.SetFrameStrata(perk,'DIALOG')
 local bad={
  {'level raises','GetFrameLevel',function() error('synthetic level read failure') end},
  {'level not a number','GetFrameLevel',function() return 'high' end},
  {'level NaN','GetFrameLevel',function() return 0/0 end},
  {'level infinite','GetFrameLevel',function() return math.huge end},
  {'strata raises','GetFrameStrata',function() error('synthetic strata read failure') end},
  {'shown raises','IsShown',function() error('synthetic shown read failure') end},
 }
 for _,case in ipairs(bad) do
  rawset(perk,case[2],case[3]);Defaults('unreadable ('..case[1]..')');rawset(perk,case[2],nil)
 end
 _G.PerkChooseButton='not a frame';Defaults('not a frame')
 _G.PerkChooseButton=nil;Defaults('absent again')
 _G.PerkChooseButton=perk

 -- f. R1 (both original reviews, NOT_CLEAR): two owned windows shown at once
 -- through the real routes, with the control shown in DIALOG at 110. Opening
 -- the Library (CommunityBuilds.Show, as the main panel's Builds hub does)
 -- or Support (as the Options menu does) leaves Help shown, and Help opened
 -- from the Options menu leaves the Library shown: the routes are kept as
 -- they are and nothing here hides a window to avoid the case. Contract:
 -- every shown owned DIALOG frame of both windows is above 110 and no higher
 -- than 127 (Raised, per window, as above); every cross-window pair keeps the
 -- sense of its default difference (Family), so Help's highest DIALOG level
 -- stays below the Library's or Support's lowest, as at the defaults (Help
 -- 39-42, the Library and Support 49-70); each hide gives that window its
 -- exact defaults back (Same) and leaves the other lifted in its own order.
 -- Page changes, a Library render, the Share form and repeated cycles keep
 -- the levels (NoDrift) and add no frame or hook.
 local function DialogFrames(win,base)
  local out={}
  for _,f in ipairs(Tree(win)) do
   if f:GetFrameStrata()=='DIALOG' then out[#out+1]={f=f,d=base[f] and base[f].level} end
  end
  return out
 end
 local function Family(tag,a,baseA,b,baseB)
  local flipped,n=0,0
  for _,x in ipairs(DialogFrames(a,baseA)) do
   for _,y in ipairs(DialogFrames(b,baseB)) do
    if x.d and y.d then
     n=n+1
     if sign(x.d-y.d)~=sign(x.f:GetFrameLevel()-y.f:GetFrameLevel()) then flipped=flipped+1 end
    end
   end
  end
  expect(n>0 and flipped==0,tag..': every cross-window pair keeps the order of its default levels ('..flipped..' of '..n..' pairs reversed or tied)')
 end
 local function Below(tag,low,baseLow,high,baseHigh,name)
  local lowTop,lowTopDefault,highBottom,highBottomDefault=-math.huge,-math.huge,math.huge,math.huge
  for _,x in ipairs(DialogFrames(low,baseLow)) do
   lowTop=math.max(lowTop,x.f:GetFrameLevel());if x.d then lowTopDefault=math.max(lowTopDefault,x.d) end
  end
  for _,y in ipairs(DialogFrames(high,baseHigh)) do
   highBottom=math.min(highBottom,y.f:GetFrameLevel());if y.d then highBottomDefault=math.min(highBottomDefault,y.d) end
  end
  if lowTopDefault<highBottomDefault then
   expect(lowTop<highBottom,tag..': Help\'s highest DIALOG level ('..tostring(lowTop)..') stays below the '..name
    ..'\'s lowest ('..tostring(highBottom)..'), as at the defaults ('..tostring(lowTopDefault)..' below '..tostring(highBottomDefault)..')')
  end
 end
 local function Both(tag,other,baseOther,name)
  expect(help:IsShown() and other:IsShown(),tag..': the route keeps Help and the '..name..' both shown')
  Raised(tag..': Help',help,baseHelp)
  Raised(tag..': '..name,other,baseOther)
  Family(tag,help,baseHelp,other,baseOther)
  Below(tag,help,baseHelp,other,baseOther,name)
 end
 local hookHelpShow,hookHelpHide=help.scripts.OnShow,help.scripts.OnHide
 local hookLibHide,hookSupHide=lib.scripts.OnHide,sup.scripts.OnHide
 local familyFrames
 local firstHelp,firstLib
 for cycle=1,3 do
  -- Help, then the Library (Help stays shown).
  local tag='R1 cycle '..cycle..', Help then Library'
  Help.Show('start');CB.Show()
  Both(tag,lib,baseLib,'Library')
  if cycle==1 then firstHelp,firstLib=Levels(help),Levels(lib)
  else NoDrift(tag..': Help',firstHelp);NoDrift(tag..': Library',firstLib) end
  -- A page change, a Library render and the Share form keep the family.
  if nextPage then nextPage:Click() end
  pcall(CB.Refresh)
  if cycle==1 then
   pcall(CB.ShowPostBuild)
   expect(popup:IsShown(),tag..': the Share form opens over the Library')
   popup._postTitleBox:SetText('');popup._postTitleBox:Insert('v26 r1 draft')
   PopupAbove(tag)
  end
  Both(tag..', after a page change and a render',lib,baseLib,'Library')
  NoDrift(tag..': Library after a render',firstLib)
  if cycle==1 then
   expect(Draft()=='v26 r1 draft',tag..': the Share draft is kept')
   popup:Hide()
  end
  CB.Hide()
  Same(tag..': the Library hidden over Help',lib,baseLib)
  expect(help:IsShown(),tag..': Help stays shown when the Library hides')
  Raised(tag..': Help alone again',help,baseHelp)
  helpClose:Click()
  Same(tag..': Help closed',help,baseHelp)
  -- Help, then Support (Help stays shown).
  tag='R1 cycle '..cycle..', Help then Support'
  Help.Show('start');UI.Show()
  Both(tag,sup,baseSup,'Support page')
  supClose:Click()
  Same(tag..': Support closed over Help',sup,baseSup)
  expect(help:IsShown(),tag..': Help stays shown when Support closes')
  Raised(tag..': Help alone again',help,baseHelp)
  helpClose:Click()
  Same(tag..': Help closed',help,baseHelp)
  -- The Library, then Help (the Library stays shown).
  tag='R1 cycle '..cycle..', Library then Help'
  CB.Show();Help.Show('start')
  Both(tag,lib,baseLib,'Library')
  helpClose:Click()
  Same(tag..': Help closed over the Library',help,baseHelp)
  expect(lib:IsShown(),tag..': the Library stays shown when Help closes')
  Raised(tag..': Library alone again',lib,baseLib)
  CB.Hide()
  Same(tag..': the Library closed',lib,baseLib)
  -- Help, the Library, then Support: the handoff hides the Library only.
  tag='R1 cycle '..cycle..', Help, Library, then Support'
  Help.Show('start');CB.Show();UI.Show()
  expect(not lib:IsShown(),tag..': the Library/Support handoff still hides the Library')
  Same(tag..': the Library handed off',lib,baseLib)
  Both(tag,sup,baseSup,'Support page')
  supClose:Click();helpClose:Click()
  Same(tag..': Support closed',sup,baseSup)
  Same(tag..': Help closed',help,baseHelp)
  -- Frames a first use may make lazily are counted after the first cycle.
  if cycle==1 then familyFrames=#H2.frames end
 end
 expect(#H2.frames==familyFrames,'R1: cycles 2 and 3 make no frame ('..tostring(familyFrames)..' -> '..#H2.frames..')')
 expect(help.scripts.OnShow==hookHelpShow and help.scripts.OnHide==hookHelpHide
  and lib.scripts.OnHide==hookLibHide and sup.scripts.OnHide==hookSupHide,'R1: the cycles add no hook')

 -- g. Standards A4: an owned child whose object type cannot be read. A walk
 -- that cannot tell what an owned child is must not lift around it (it
 -- would stay at its default under a lifted parent): the whole lift is
 -- refused and every owned level keeps its default. The mock is a bounded
 -- instance method on one real Help button and is removed after the case.
 local victim=assert(nextPage,'v26 SETUP: Help\'s Next button, an owned child')
 rawset(victim,'GetObjectType',function() error('synthetic object type read failure') end)
 local okA4=pcall(Help.Show,'start')
 expect(okA4,'A4: Help opens without an error while a child\'s type cannot be read')
 Same('A4: an unreadable owned child refuses the whole lift',help,baseHelp)
 helpClose:Click()
 rawset(victim,'GetObjectType',nil)
 Help.Show('start')
 Raised('A4: once the type reads again, Help lifts',help,baseHelp)
 helpClose:Click()
 Same('A4: and closes to its defaults',help,baseHelp)

 -- h. Standards A3: a level write that fails once while Help gives its
 -- levels back. A later open must not take a level left raised as a
 -- default: with the control gone Help shows its exact defaults, and with
 -- it shown again Help lifts in its default order and closes to its
 -- defaults. The mock is a bounded instance method on Help's real scroll
 -- frame that fails while armed, and is removed before the later opens.
 local scrollFrame=assert(NexusHelpScroll,'v26 SETUP: Help\'s scroll frame')
 local regionSet=scrollFrame.SetFrameLevel
 local armed=false
 rawset(scrollFrame,'SetFrameLevel',function(self,value)
  if armed then error('synthetic transient level write failure') end
  return regionSet(self,value)
 end)
 Help.Show('start')
 Raised('A3: Help lifts before the failing restore',help,baseHelp)
 armed=true
 local okClose=pcall(function() helpClose:Click() end)
 armed=false
 rawset(scrollFrame,'SetFrameLevel',nil)
 expect(okClose and not help:IsShown(),'A3: Help closes without an error when one level write fails')
 real.Hide(perk)
 Help.Show('start')
 Same('A3: with the control gone, the next open shows the exact defaults',help,baseHelp)
 helpClose:Click()
 real.Show(perk)
 Help.Show('start')
 Raised('A3: with the control shown again, Help lifts in its default order',help,baseHelp)
 helpClose:Click()
 Same('A3: and closes to its exact defaults',help,baseHelp)

 -- i. Spec R2 (r1 review): a family refusal, then one member hides. With the
 -- control shown and the Library open and lifted, Help opens while one of its
 -- own children cannot say what it is (part g's bounded mock on the real
 -- Next button). The whole family is refused: Help and the Library both keep
 -- their exact defaults. Help then closes (the mock still in place) and the
 -- mock is removed. The Library, still shown and able to fit on its own,
 -- must be lifted again by that hide itself: the 0.25 s check is not driven
 -- and the Library is not reopened. Its own close then restores its defaults.
 -- No window is hidden or shown here other than by these real routes.
 CB.Show()
 Raised('R2: the Library alone is lifted before Help opens',lib,baseLib)
 rawset(victim,'GetObjectType',function() error('synthetic object type read failure') end)
 local okR2=pcall(Help.Show,'start')
 expect(okR2 and help:IsShown() and lib:IsShown(),'R2: Help opens without an error and the Library stays shown')
 Same('R2: a refused family keeps Help at its defaults',help,baseHelp)
 Same('R2: a refused family also restores the Library to its defaults',lib,baseLib)
 helpClose:Click()
 rawset(victim,'GetObjectType',nil)
 expect(not help:IsShown() and lib:IsShown(),'R2: Help closed and the Library is still shown')
 Raised('R2: once Help hides, the still-shown Library is lifted again (no tick, no reopen)',lib,baseLib)
 CB.Hide()
 Same('R2: the Library then closes to its exact defaults',lib,baseLib)
 Same('R2: Help stays at its exact defaults',help,baseHelp)
 expect(help.scripts.OnShow==hookHelpShow and help.scripts.OnHide==hookHelpHide
  and lib.scripts.OnHide==hookLibHide and sup.scripts.OnHide==hookSupHide,'R2: no hook is added')

 -- e. The foreign frame is untouched; nothing else happened.
 expect(touched==0,'the PerkChooseButton is never changed by the addon ('..touched..' calls: '..table.concat(touchedNames,',')..')')
 expect(clicks==0,'the PerkChooseButton is never clicked ('..clicks..')')
 expect(Snapshot()==perkBefore,'the PerkChooseButton keeps its strata, level, shown state, parent, anchor, OnClick and label')
 expect(enumerations==0,'no frame is enumerated ('..enumerations..')')
 expect(#H2.actions==acts and #H2.sent==sent and Serialize(NexusDB.settings)==settings and NexusSupportDB==nil,
  'no game action, send, settings write or support storage write')
 EnumerateFrames=hadEnumerate
 if #misses>0 then error('v26 owned dialogs over PerkChooseButton: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0) end
end

-- 36. r2 (Standards review of r1, required): a frame the Library creates
-- while it is lifted, with its level copied from a sibling. The detail
-- status frame is made once, lazily, by the real ShowDetailStatus
-- (CommunityRenderer): a child of the detail panel's parent, given the
-- detail panel's own level. Contract: whenever it first appears, it stays
-- level with its detail panel while the Library is lifted over the shown
-- PerkChooseButton, it goes back to the detail panel's exact default level
-- when the Library hides, and it stays there on later opens with the control
-- gone; a repeat cycle gives the same. Nothing acts, sends, writes settings
-- or support storage, or touches the control.
-- Route: a fresh real session; Help, Support and Panel routes are not used.
-- The Library is opened through Nexus.CommunityBuilds.Show (its M.Show lifts
-- it) and rendered again through Nexus.CommunityBuilds.Refresh (a real
-- render; RefreshDetailPanel with no selection calls ShowDetailStatus).
-- Fixture (named): every render reaches RefreshDetailPanel except one that
-- fails its projection read (RenderRefresh returns at the projection
-- failure). So, while armed, the Library projection's List answers
-- nil, nil, 'synthetic projection failure' (SortedBuilds then returns that
-- error); this is how the first opens happen without a status frame. The
-- projection object is reached by wrapping Nexus.CommunityInternals.Projection.New
-- after the files load and before start-up runs, and the wrapper is removed
-- at the end. Creation semantics are modelled as in section 35 (a child
-- starts one level above its parent and draws in its parent's strata).
-- Misses are collected, then raised together.
do
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local PERK,CEILING=110,127
 -- Session isolation (r2 fixture correction): section 35 leaves its own
 -- synthetic PerkChooseButton shown in DIALOG at 110, and its anchor frame,
 -- as globals of an earlier harness. A fresh harness does not clear them, so
 -- this section's 'control absent' first open would be lifted. Both test
 -- globals are removed here, before this session starts; no runtime state is
 -- changed. This section's own control is made later and removed at its end.
 _G.PerkChooseButton=nil
 _G.ProjectEbonholdPerkFrame=nil
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusSupportDB=nil;NexusSupportStorage=nil
 local H3=dofile('tests/prototype/harness.lua')
 check(_G.PerkChooseButton==nil and _G.ProjectEbonholdPerkFrame==nil,
  'r2 SETUP: no PerkChooseButton or anchor is left from an earlier section when this session starts')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template,...)
  local f=create(kind,name,parent,template,...)
  local p=parent;if type(p)=='string' then p=_G[p] end
  if type(p)=='table' and p~=UIParent and kind~='Font' then
   rawset(f,'frameLevel',(tonumber(p:GetFrameLevel()) or 0)+1)
   rawset(f,'GetFrameStrata',function(self)
    local own=rawget(self,'strata');if own then return own end
    local q=self:GetParent();return q and q:GetFrameStrata() or 'MEDIUM'
   end)
  end
  return f
 end
 local enumerations,hadEnumerate=0,EnumerateFrames
 EnumerateFrames=function(...) enumerations=enumerations+1;if hadEnumerate then return hadEnumerate(...) end end
 NexusDB=T.Profile(0,0)
 T.Load()
 -- The projection read that the first opens fail (see Fixture above).
 local factory=Nexus.CommunityInternals and Nexus.CommunityInternals.Projection
 check(type(factory)=='table' and type(factory.New)=='function','r2 SETUP: the Library projection factory is loaded')
 local realNew,failing,wrapped=factory.New,false,0
 factory.New=function(...)
  local object=realNew(...)
  if type(object)=='table' and type(object.List)=='function' then
   local list=object.List
   object.List=function(...)
    if failing then return nil,nil,'synthetic projection failure' end
    return list(...)
   end
   wrapped=wrapped+1
  end
  return object
 end
 H3.Fire('ADDON_LOADED','Nexus');H3.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H3,function()return Nexus.StartupStatus().state=='ready' end)
 local function Serialize(v,seen)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
  local out={'{'};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen)..',' end
  seen[v]=nil;return table.concat(out)..'}'
 end
 local CB=Nexus.CommunityBuilds
 local acts,sent,settings=#H3.actions,#H3.sent,Serialize(NexusDB.settings)

 -- a. With the control absent, the first open fails its projection read:
 -- the Library and its detail panel exist at their defaults, with no
 -- detail status frame yet.
 check(_G.PerkChooseButton==nil,'r2 SETUP: the control is absent before the first open (no stale test control)')
 failing=true
 check(select(1,pcall(CB.Show)),'r2 SETUP: the Build Library opens through Nexus.CommunityBuilds.Show')
 local lib=assert(NexusCommunityBuildsFrame,'r2 SETUP: the Library window')
 local detail=assert(lib._detailPanel,'r2 SETUP: the Library detail panel')
 check(wrapped>=1,'r2 SETUP: the Library projection was made after the fixture was in place')
 check(detail._nexusStatus==nil,'r2 SETUP: no detail status frame exists after a failed first render')
 check(lib:GetFrameLevel()==50,'r2 SETUP: the Library is at its default level 50')
 local detailDefault=detail:GetFrameLevel()
 check(type(detailDefault)=='number' and detailDefault>50 and detailDefault<=PERK,
  'r2 SETUP: the detail panel has its default level above the window ('..tostring(detailDefault)..')')
 CB.Hide()

 -- The known control, shown, with its mutators counted (as section 35).
 local anchor=_G.ProjectEbonholdPerkFrame or CreateFrame('Frame','ProjectEbonholdPerkFrame',UIParent)
 local perk=CreateFrame('Button','PerkChooseButton',UIParent)
 perk:SetFrameStrata('DIALOG');perk:SetFrameLevel(PERK);perk:SetPoint('TOP',anchor,'BOTTOM',0,-50)
 perk:SetText('Select an Echo')
 local clicks=0;local onClick=function() clicks=clicks+1 end
 perk:SetScript('OnClick',onClick);perk:Show()
 local real={Show=perk.Show,Hide=perk.Hide}
 local touched,touchedNames=0,{}
 for _,m in ipairs({'SetFrameLevel','SetFrameStrata','SetPoint','ClearAllPoints','SetAllPoints','SetParent','Show','Hide',
  'SetShown','Click','SetScript','HookScript','EnableMouse','SetAlpha','Raise','Lower','SetToplevel','Enable','Disable',
  'SetSize','SetWidth','SetHeight','SetText'}) do
  local orig=perk[m]
  rawset(perk,m,function(self,...)
   touched=touched+1;touchedNames[#touchedNames+1]=m
   if type(orig)=='function' then return orig(self,...) end
  end)
 end
 local function Snapshot()
  local a=perk.points[1] or {}
  return table.concat({tostring(rawget(perk,'strata')),tostring(rawget(perk,'frameLevel')),tostring(rawget(perk,'shown')),
   tostring(perk:GetParent()==UIParent),tostring(#perk.points),tostring(a[1]),tostring(a[2]==anchor),tostring(a[3]),
   tostring(a[4]),tostring(a[5]),tostring(perk.scripts.OnClick==onClick),tostring(perk:GetText())},'|')
 end
 local perkBefore=Snapshot()

 -- b. With the control shown, the Library opens and is lifted, its first
 -- render still failing the projection read, so the status frame does not
 -- exist yet when the lift is made.
 check(select(1,pcall(CB.Show)),'r2 SETUP: the Library opens again with the control shown')
 check(detail._nexusStatus==nil,'r2 SETUP: still no detail status frame when the Library is lifted')
 check(lib:GetFrameLevel()>PERK and detail:GetFrameLevel()>PERK,
  'r2 SETUP: the Library and its detail panel are lifted over the control ('..lib:GetFrameLevel()..', '..detail:GetFrameLevel()..')')

 -- c. The real render that makes the status frame while lifted.
 failing=false
 pcall(CB.Refresh)
 local status=detail._nexusStatus
 check(status~=nil,'r2 SETUP: a real render made the detail status frame (no selection)')
 local function Level(tag)
  expect(status:GetFrameLevel()==detail:GetFrameLevel(),
   tag..': the detail status frame stays level with its detail panel ('..tostring(status:GetFrameLevel())..' and '..tostring(detail:GetFrameLevel())..')')
  expect(status:GetFrameLevel()>PERK and status:GetFrameLevel()<=CEILING,
   tag..': the detail status frame is above the control and at most '..CEILING..' ('..tostring(status:GetFrameLevel())..')')
 end
 local function Default(tag)
  expect(detail:GetFrameLevel()==detailDefault,
   tag..': the detail panel is back at its default '..tostring(detailDefault)..' ('..tostring(detail:GetFrameLevel())..')')
  expect(status:GetFrameLevel()==detailDefault,
   tag..': the detail status frame is at the detail panel\'s exact default '..tostring(detailDefault)..' ('..tostring(status:GetFrameLevel())..')')
 end
 Level('lifted, after the status frame is made')
 pcall(CB.Refresh)
 Level('lifted, after another render')
 CB.Hide()
 Default('the Library hidden')

 -- d. Later opens with the control gone, then a repeat cycle with it shown.
 real.Hide(perk)
 check(select(1,pcall(CB.Show)),'r2 SETUP: the Library opens with the control hidden')
 Default('a later open with the control hidden')
 CB.Hide()
 real.Show(perk)
 for cycle=1,2 do
  check(select(1,pcall(CB.Show)),'r2 SETUP: the Library opens in repeat cycle '..cycle)
  Level('repeat cycle '..cycle..', lifted')
  pcall(CB.Refresh)
  Level('repeat cycle '..cycle..', lifted after a render')
  CB.Hide()
  Default('repeat cycle '..cycle..', hidden')
  real.Hide(perk)
  check(select(1,pcall(CB.Show)),'r2 SETUP: the Library opens with the control hidden in cycle '..cycle)
  Default('repeat cycle '..cycle..', opened with the control hidden')
  CB.Hide()
  real.Show(perk)
 end

 -- e. Nothing else happened, and the control is untouched.
 factory.New=realNew
 expect(touched==0,'r2: the PerkChooseButton is never changed by the addon ('..touched..' calls: '..table.concat(touchedNames,',')..')')
 expect(clicks==0,'r2: the PerkChooseButton is never clicked ('..clicks..')')
 expect(Snapshot()==perkBefore,'r2: the PerkChooseButton keeps its strata, level, shown state, parent, anchor, OnClick and label')
 expect(enumerations==0,'r2: no frame is enumerated ('..enumerations..')')
 expect(#H3.actions==acts and #H3.sent==sent and Serialize(NexusDB.settings)==settings and NexusSupportDB==nil,
  'r2: no game action, send, settings write or support storage write')
 EnumerateFrames=hadEnumerate
 -- Fixture cleanup: this section's own test control and anchor are not left
 -- behind as globals (checked above first, so no guard is skipped).
 _G.PerkChooseButton=nil
 _G.ProjectEbonholdPerkFrame=nil
 if #misses>0 then error('r2 late detail status over PerkChooseButton: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0) end
end

-- 37. r3 (Spec R3 on r2): the same late detail status frame, made on the
-- render's PENDING return and first walked by a responsive re-layout. In
-- RenderRefresh, a projection read whose third value is "pending" takes the
-- pending path (SortedBuilds passes List's err through; RenderRefresh then
-- calls RenderSyncStatus and RefreshDetailPanel(SelectedId(), true) and
-- returns false, "pending"), so ShowDetailStatus makes the status frame at
-- the detail panel's lifted level and no ReapplyOwned follows. The next walk
-- is then the one inside ApplyCommunityLayout, which also rewrites the detail
-- panel to window + 10. Contract (as section 36): the status frame stays
-- level with its detail panel while lifted, within 111-127, and both are at
-- the detail panel's exact default on hide and on later control-absent opens;
-- once more after a repeat. Nothing acts, sends, writes settings or support
-- storage, or touches the control.
-- Route: a fresh real session (section 36's named projection fixture, now
-- with a 'pending' mode). The re-layout is a real one: the harness UIParent
-- size changes, so the next real render's ApplyResponsiveLayout(false) sees a
-- new viewport key and runs ApplyCommunityLayout; that render also takes the
-- pending path, so no completed render comes before the re-layout. SETUP
-- checks prove each step (status absent when lifted, made by a render that
-- returned false, 'pending', and a changed layout key).
do
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local PERK,CEILING=110,127
 -- Session isolation, as section 36: no test control or anchor of an
 -- earlier section is carried into this session.
 _G.PerkChooseButton=nil
 _G.ProjectEbonholdPerkFrame=nil
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusSupportDB=nil;NexusSupportStorage=nil
 local H4=dofile('tests/prototype/harness.lua')
 check(_G.PerkChooseButton==nil and _G.ProjectEbonholdPerkFrame==nil,
  'r3 SETUP: no PerkChooseButton or anchor is left from an earlier section when this session starts')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template,...)
  local f=create(kind,name,parent,template,...)
  local p=parent;if type(p)=='string' then p=_G[p] end
  if type(p)=='table' and p~=UIParent and kind~='Font' then
   rawset(f,'frameLevel',(tonumber(p:GetFrameLevel()) or 0)+1)
   rawset(f,'GetFrameStrata',function(self)
    local own=rawget(self,'strata');if own then return own end
    local q=self:GetParent();return q and q:GetFrameStrata() or 'MEDIUM'
   end)
  end
  return f
 end
 local enumerations,hadEnumerate=0,EnumerateFrames
 EnumerateFrames=function(...) enumerations=enumerations+1;if hadEnumerate then return hadEnumerate(...) end end
 NexusDB=T.Profile(0,0)
 T.Load()
 -- The projection read (section 36's fixture): 'fail' answers a failure,
 -- 'pending' answers nil, nil, "pending" (the value RenderRefresh's pending
 -- path compares with), nil reads the real projection.
 local factory=Nexus.CommunityInternals and Nexus.CommunityInternals.Projection
 check(type(factory)=='table' and type(factory.New)=='function','r3 SETUP: the Library projection factory is loaded')
 local realNew,mode,wrapped=factory.New,nil,0
 factory.New=function(...)
  local object=realNew(...)
  if type(object)=='table' and type(object.List)=='function' then
   local list=object.List
   object.List=function(...)
    if mode=='fail' then return nil,nil,'synthetic projection failure' end
    if mode=='pending' then return nil,nil,'pending' end
    return list(...)
   end
   wrapped=wrapped+1
  end
  return object
 end
 H4.Fire('ADDON_LOADED','Nexus');H4.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H4,function()return Nexus.StartupStatus().state=='ready' end)
 local function Serialize(v,seen)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
  local out={'{'};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen)..',' end
  seen[v]=nil;return table.concat(out)..'}'
 end
 local CB=Nexus.CommunityBuilds
 local acts,sent,settings=#H4.actions,#H4.sent,Serialize(NexusDB.settings)
 local uiWidth,uiHeight=UIParent:GetWidth(),UIParent:GetHeight()

 -- a. Control absent; the first open fails its projection read: defaults,
 -- no status frame.
 check(_G.PerkChooseButton==nil,'r3 SETUP: the control is absent before the first open')
 mode='fail'
 check(select(1,pcall(CB.Show)),'r3 SETUP: the Build Library opens through Nexus.CommunityBuilds.Show')
 local lib=assert(NexusCommunityBuildsFrame,'r3 SETUP: the Library window')
 local detail=assert(lib._detailPanel,'r3 SETUP: the Library detail panel')
 check(wrapped>=1,'r3 SETUP: the Library projection was made after the fixture was in place')
 check(detail._nexusStatus==nil,'r3 SETUP: no detail status frame exists after a failed first render')
 check(lib:GetFrameLevel()==50,'r3 SETUP: the Library is at its default level 50')
 local detailDefault=detail:GetFrameLevel()
 check(type(detailDefault)=='number' and detailDefault>50 and detailDefault<=PERK,
  'r3 SETUP: the detail panel has its default level above the window ('..tostring(detailDefault)..')')
 CB.Hide()

 -- The known control, shown, with its mutators counted (as sections 35-36).
 local anchor=_G.ProjectEbonholdPerkFrame or CreateFrame('Frame','ProjectEbonholdPerkFrame',UIParent)
 local perk=CreateFrame('Button','PerkChooseButton',UIParent)
 perk:SetFrameStrata('DIALOG');perk:SetFrameLevel(PERK);perk:SetPoint('TOP',anchor,'BOTTOM',0,-50)
 perk:SetText('Select an Echo')
 local clicks=0;local onClick=function() clicks=clicks+1 end
 perk:SetScript('OnClick',onClick);perk:Show()
 local real={Show=perk.Show,Hide=perk.Hide}
 local touched,touchedNames=0,{}
 for _,m in ipairs({'SetFrameLevel','SetFrameStrata','SetPoint','ClearAllPoints','SetAllPoints','SetParent','Show','Hide',
  'SetShown','Click','SetScript','HookScript','EnableMouse','SetAlpha','Raise','Lower','SetToplevel','Enable','Disable',
  'SetSize','SetWidth','SetHeight','SetText'}) do
  local orig=perk[m]
  rawset(perk,m,function(self,...)
   touched=touched+1;touchedNames[#touchedNames+1]=m
   if type(orig)=='function' then return orig(self,...) end
  end)
 end
 local function Snapshot()
  local a=perk.points[1] or {}
  return table.concat({tostring(rawget(perk,'strata')),tostring(rawget(perk,'frameLevel')),tostring(rawget(perk,'shown')),
   tostring(perk:GetParent()==UIParent),tostring(#perk.points),tostring(a[1]),tostring(a[2]==anchor),tostring(a[3]),
   tostring(a[4]),tostring(a[5]),tostring(perk.scripts.OnClick==onClick),tostring(perk:GetText())},'|')
 end
 local perkBefore=Snapshot()
 local function Level(tag)
  local status=detail._nexusStatus
  expect(status~=nil and status:GetFrameLevel()==detail:GetFrameLevel(),
   tag..': the detail status frame stays level with its detail panel ('..tostring(status and status:GetFrameLevel())..' and '..tostring(detail:GetFrameLevel())..')')
  expect(status~=nil and status:GetFrameLevel()>PERK and status:GetFrameLevel()<=CEILING
   and detail:GetFrameLevel()>PERK and detail:GetFrameLevel()<=CEILING,
   tag..': both are above the control and at most '..CEILING..' ('..tostring(status and status:GetFrameLevel())..', '..tostring(detail:GetFrameLevel())..')')
 end
 local function Default(tag)
  local status=detail._nexusStatus
  expect(detail:GetFrameLevel()==detailDefault,
   tag..': the detail panel is back at its default '..tostring(detailDefault)..' ('..tostring(detail:GetFrameLevel())..')')
  expect(status~=nil and status:GetFrameLevel()==detailDefault,
   tag..': the detail status frame is at the detail panel\'s exact default '..tostring(detailDefault)..' ('..tostring(status and status:GetFrameLevel())..')')
 end
 -- A real responsive re-layout before any completed render: a new UIParent
 -- size, then a real render that takes the pending path again.
 local sizes={{1600,900},{1280,800}}
 local function Relayout(tag,i)
  local before=lib._nexusRuntimeLayoutKey
  UIParent:SetSize(sizes[i][1],sizes[i][2])
  mode='pending'
  local ok,result,why=pcall(CB.Refresh)
  check(ok and result==false and why=='pending','r3 SETUP: '..tag..': the re-layout render took the pending path ('..tostring(result)..', '..tostring(why)..')')
  check(lib._nexusRuntimeLayoutKey~=nil and lib._nexusRuntimeLayoutKey~=before,
   'r3 SETUP: '..tag..': a real responsive re-layout ran (the layout key changed)')
 end

 -- b. Control shown; the open is lifted with no status frame yet.
 mode='fail'
 check(select(1,pcall(CB.Show)),'r3 SETUP: the Library opens again with the control shown')
 check(detail._nexusStatus==nil,'r3 SETUP: still no detail status frame when the Library is lifted')
 check(lib:GetFrameLevel()>PERK and detail:GetFrameLevel()>PERK,
  'r3 SETUP: the Library and its detail panel are lifted over the control ('..lib:GetFrameLevel()..', '..detail:GetFrameLevel()..')')

 -- c. One real render takes the pending path and makes the status frame
 -- (not walked: that path returns before the render's own re-apply).
 mode='pending'
 local okPending,pendingResult,pendingWhy=pcall(CB.Refresh)
 check(okPending and pendingResult==false and pendingWhy=='pending',
  'r3 SETUP: the render took the pending path ('..tostring(pendingResult)..', '..tostring(pendingWhy)..')')
 check(detail._nexusStatus~=nil,'r3 SETUP: the pending render made the detail status frame')

 -- d. The responsive re-layout is the first walk; then hide and reopen.
 Relayout('first re-layout',1)
 Level('lifted, after the pending render and a re-layout')
 CB.Hide()
 Default('the Library hidden')
 real.Hide(perk)
 mode=nil
 check(select(1,pcall(CB.Show)),'r3 SETUP: the Library opens with the control hidden')
 Default('a later open with the control hidden')
 CB.Hide()

 -- e. Repeat once: lifted again (no completed render), a re-layout, hide,
 -- then a control-absent open.
 real.Show(perk)
 mode='pending'
 check(select(1,pcall(CB.Show)),'r3 SETUP: the Library opens in the repeat')
 Relayout('repeat re-layout',2)
 Level('repeat, lifted after a re-layout')
 CB.Hide()
 Default('repeat, hidden')
 real.Hide(perk)
 mode=nil
 check(select(1,pcall(CB.Show)),'r3 SETUP: the Library opens with the control hidden in the repeat')
 Default('repeat, opened with the control hidden')
 CB.Hide()
 real.Show(perk)

 -- f. Nothing else happened; the control is untouched; fixtures restored.
 factory.New=realNew
 mode=nil
 UIParent:SetSize(uiWidth,uiHeight)
 expect(touched==0,'r3: the PerkChooseButton is never changed by the addon ('..touched..' calls: '..table.concat(touchedNames,',')..')')
 expect(clicks==0,'r3: the PerkChooseButton is never clicked ('..clicks..')')
 expect(Snapshot()==perkBefore,'r3: the PerkChooseButton keeps its strata, level, shown state, parent, anchor, OnClick and label')
 expect(enumerations==0,'r3: no frame is enumerated ('..enumerations..')')
 expect(#H4.actions==acts and #H4.sent==sent and Serialize(NexusDB.settings)==settings and NexusSupportDB==nil,
  'r3: no game action, send, settings write or support storage write')
 EnumerateFrames=hadEnumerate
 _G.PerkChooseButton=nil
 _G.ProjectEbonholdPerkFrame=nil
 if #misses>0 then error('r3 pending detail status re-laid out over PerkChooseButton: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0) end
end

print('PASS support_report: one incident, one summary under 8000 bytes, and one prepared file that claims only what is true checks='..checks)
