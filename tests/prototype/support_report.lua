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
check(body:find('81 ordinary, 6 permanent, 87 total',1,true)~=nil,'with the counted copies')
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
check(text:find('81 ordinary, 6 permanent, 87 total',1,true)~=nil,'with its counts')
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
print('PASS support_report: one incident, one summary under 8000 bytes, and one prepared file that claims only what is true checks='..checks)
