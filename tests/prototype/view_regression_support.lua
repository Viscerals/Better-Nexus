-- Shared helpers of the regressions for the twelve reproduced P3 view and
-- interaction findings (F-S2-1 .. F-S5-1): a reporting checker, colour-code
-- stripping, frame lookup, a bounded Leaderboard settle, a fake unit tooltip
-- boundary and the text predicates of the Saved Build selector. Not a test
-- itself: the name ends in _support, so tools/ci_check.py does not list it.
-- Loading it reads and changes nothing; every helper acts only on what a test
-- passes in or on the globals it restores before returning. Synthetic data only.
local V={}

local function printable(v)
 local ok,s=pcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
V.printable=printable

-- Every check is evaluated and reported; finish() fails at the end if any did
-- not hold. SETUP: the fixture reached its state (a SETUP failure is not red
-- evidence; investigate it first). EXPECT: healthy behaviour that does not
-- hold at the baseline (the reproduced defect). GUARD: behaviour that already
-- holds at the baseline and must keep holding. A scenario that raises is
-- reported and the later scenarios still run.
function V.Checker(name)
 local C={failures={},n={setup=0,expect=0,guard=0},bad={setup=0,expect=0,guard=0},raised=0}
 local function check(kind,ok,label,detail)
  C.n[kind]=C.n[kind]+1
  if ok then return true end
  C.bad[kind]=C.bad[kind]+1
  local line=kind:upper()..' '..label..(detail~=nil and (' ['..printable(detail)..']') or '')
  C.failures[#C.failures+1]=line
  print('FAIL '..line)
  return false
 end
 function C.setup(ok,label,detail) return check('setup',ok and true or false,label,detail) end
 function C.expect(ok,label,detail) return check('expect',ok and true or false,label,detail) end
 function C.guard(ok,label,detail) return check('guard',ok and true or false,label,detail) end
 function C.scenario(label,fn)
  local ok,err=pcall(fn)
  if not ok then
   C.raised=C.raised+1
   local line='RAISED '..label..': '..printable(err)
   C.failures[#C.failures+1]=line
   print('FAIL '..line)
  end
  return ok
 end
 function C.finish(note)
  print(string.format('SUMMARY %s: expectations held %d of %d; guards held %d of %d; setup held %d of %d; scenarios raised %d',
   name,C.n.expect-C.bad.expect,C.n.expect,C.n.guard-C.bad.guard,C.n.guard,C.n.setup-C.bad.setup,C.n.setup,C.raised))
  if #C.failures>0 then
   error(name..': '..#C.failures..' check(s) failed ('..C.bad.expect..' expectation, '..C.bad.guard..' guard, '
    ..C.bad.setup..' setup, '..C.raised..' raised); first: '..C.failures[1],0)
  end
  print('PASS '..name..(note and (' '..note) or '')..' checks='..(C.n.setup+C.n.expect+C.n.guard))
 end
 return C
end

-- Text without the client's colour codes.
function V.Plain(text)
 return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))
end

-- The Reference document as the player sees it (ui/Help.lua v28 r3/r4: one
-- page is stored in the part pool w.parts, part 1 being w.body; each later
-- part is anchored TOPLEFT to the BOTTOMLEFT of the part before it, and the
-- page is split only at line breaks, the boundary line feed not stored).
-- Test-only reader of the actual shown FontStrings: the shown parts must be a
-- prefix of the pool (no hidden part between shown ones), and each shown part
-- after the first must be anchored under the previous one. Without a pool it
-- reads w.body alone. It never reads Help.PageText, the catalog or a hidden
-- retained text.
function V.HelpParts(w)
 w=w or _G.NexusHelpWindow
 if not w then return nil,'no Reference window' end
 local pool=type(w.parts)=='table' and #w.parts>0 and w.parts or {w.body}
 local shown,hidden={},nil
 for i,fs in ipairs(pool) do
  if fs and fs:IsShown() then
   if hidden then return nil,'shown part '..i..' after hidden part '..hidden end
   if i>1 then
    local point,rel,relPoint=fs:GetPoint(1)
    if point~='TOPLEFT' or rel~=pool[i-1] or relPoint~='BOTTOMLEFT' then
     return nil,'part '..i..' is not anchored under part '..(i-1)
    end
   end
   shown[#shown+1]=fs
  else
   hidden=hidden or i
  end
 end
 if #shown==0 then return nil,'no shown part' end
 return shown
end
-- The exact stored document: the shown parts' GetText joined by the boundary
-- line feed. A broken part order or an empty document raises (a scenario
-- reports it as RAISED, an assert-style test stops).
function V.HelpDocument(w)
 local parts,why=V.HelpParts(w)
 if not parts then error('HelpDocument: '..tostring(why),2) end
 local out={}
 for i,fs in ipairs(parts) do out[i]=fs:GetText() or '' end
 return table.concat(out,'\n')
end
-- The visible text of the document, for substring checks: the client's escape
-- '||' is the one '|' it shows, and colour codes are not visible. The escape is
-- decoded first, so an escaped command such as 'adaptive||released' is never
-- read as a colour reset.
function V.HelpShown(w)
 local s=V.HelpDocument(w):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 return (s:gsub('\1','|'))
end
-- The accepted v23 reference-page form (H.FormatReference), restated
-- independently for exact checks: the page title as a heading in the heading
-- gold, a blank line, then the page text with every '|' written '||'.
function V.HelpReferenceExpected(title,text)
 return '|cffffd100'..tostring(title)..'|r\n\n'..(tostring(text):gsub('|','||'))
end

-- The Orb mini panel's lines (ui/OrbPanel.lua, accepted layout: each status
-- line holds at most a character budget of two estimated rows at the panel's
-- current width, wraps at word boundaries (which can take more rows) and is as
-- tall as the client measures its wrapped text; lines stack one under another;
-- the control row stands below the closing note). The harness measures no
-- wrap (GetStringHeight is a constant), so a test declares its own model of
-- the client: `char` units per visible character and `line` units per row.
-- Test-only; the text, the widths and the expected results stay the product's.
V.MINI_LINE_MODEL={char=7,line=14}
V.MINI_LINE_KEYS={'state','reason','usage','pending','missing','notice','note'}
-- Visible characters of a line: '||' shows one '|', colour codes none, a
-- UTF-8 character counts once.
function V.MiniVisible(text)
 local s=tostring(text or ''):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 return (s:gsub('\1','|'))
end
function V.MiniChars(text) return #(V.MiniVisible(text):gsub('[\128-\191]','')) end
-- Rows of a text at a width under the model: greedy word wrap, a word longer
-- than a row broken across rows.
function V.ModelRows(text,width,char)
 text=V.MiniVisible(text)
 if text=='' then return 0 end
 local per=math.max(1,math.floor((tonumber(width) or 0)/char))
 local rows=0
 for row in (text..'\n'):gmatch('(.-)\n') do
  rows=rows+1
  local used=0
  for word in row:gmatch('%S+') do
   local n=#(word:gsub('[\128-\191]',''))
   local gap=used>0 and 1 or 0
   if used>0 and used+gap+n>per then rows=rows+1;used=0;gap=0 end
   while n>per do rows=rows+1;n=n-per end
   used=used+gap+n
  end
 end
 return rows
end
-- Installs the model's GetStringHeight on the mini's own lines only and lays
-- the mini out again through its own layout (mini._nexusStack, which runs when
-- a shown text changed). Returns a function that removes the stand-ins. That
-- reflow after installing the model is an explicit offline setup step, not
-- evidence of how the native client's fonts settle; no text or dimension of a
-- widget is set by the test.
function V.UseMiniLineModel(mini,model)
 model=model or V.MINI_LINE_MODEL
 local saved={}
 for _,key in ipairs(V.MINI_LINE_KEYS) do
  local fs=mini[key]
  if fs then
   saved[fs]=rawget(fs,'GetStringHeight') or false
   rawset(fs,'GetStringHeight',function(self) return V.ModelRows(self:GetText(),self:GetWidth(),model.char)*model.line end)
  end
 end
 if type(mini._nexusStack)=='function' then
  local keep=mini.note:GetText()
  mini.note:SetText('');mini._nexusStack()
  mini.note:SetText(keep);mini._nexusStack()
 end
 return function()
  for fs,prior in pairs(saved) do rawset(fs,'GetStringHeight',prior or nil) end
 end
end
-- Distance of a region's top below its parent's top (its TOPLEFT anchor).
function V.TopOf(region)
 local _,x,y=region:GetPoint(1)
 if type(x)~='number' then _,_,_,x,y=region:GetPoint(1) end
 return -(tonumber(y) or 0)
end
-- One mini line fits visibly under the model: its visible characters are
-- within the line's character budget (two ESTIMATED rows of the model at its
-- actual width, the product's MINI_CHARS rule), its allocated height covers
-- all of its wrapped rows, and the next element stands at or below its
-- bottom. The rows themselves are not capped at two: word wrap breaks only
-- between words, so a text within that character budget can still need three
-- or more rows (for example a 74-character reason in 37-character rows). The
-- product allocates the actual wrapped height for that (OrbPanel Fit), and
-- that height is what must cover the rows. Returns ok and a detail string.
function V.MiniLineFits(mini,key,nextRegion,model)
 model=model or V.MINI_LINE_MODEL
 local fs=mini[key]
 local text=fs:GetText() or ''
 local width=tonumber(fs:GetWidth()) or 0
 local per=math.max(1,math.floor(width/model.char))
 local chars,rows=V.MiniChars(text),V.ModelRows(text,width,model.char)
 local top,height=V.TopOf(fs),tonumber(fs:GetHeight()) or 0
 local below=nextRegion and V.TopOf(nextRegion) or math.huge
 local ok=chars<=2*per and height>=rows*model.line and below>=top+height
 return ok,('%s: %d chars (budget %d), %d rows, height %s, top %s, next %s'):format(key,chars,2*per,rows,
  tostring(height),tostring(top),tostring(below))
end

local function Pattern(text)
 return (tostring(text):lower():gsub('(%p)','%%%1'))
end

-- Does the text name `name` as a whole word (case-insensitive)?
function V.Names(text,name)
 return V.Plain(text):lower():find('%f[%w]'..Pattern(name)..'%f[%W]')~=nil
end

function V.Ordinal(n)
 local m10,m100=n%10,n%100
 if m10==1 and m100~=11 then return n..'st'
 elseif m10==2 and m100~=12 then return n..'nd'
 elseif m10==3 and m100~=13 then return n..'rd' end
 return n..'th'
end

function V.Count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end

------------------------------------------------------------------------
-- Frames the harness created (read only)
------------------------------------------------------------------------

-- Every frame the harness created that satisfies pred, in creation order.
function V.Frames(H,pred)
 local out={}
 for _,f in ipairs(H.frames) do
  local ok,match=pcall(pred,f)
  if ok and match then out[#out+1]=f end
 end
 return out
end

-- The one frame that satisfies pred; nil when none or several match, with
-- the number that matched.
function V.Frame(H,pred)
 local found=V.Frames(H,pred)
 if #found==1 then return found[1],1 end
 return nil,#found
end

-- The Button child of `parent` whose label reads `text` (colour codes ignored).
function V.Button(H,parent,text)
 return V.Frame(H,function(f)
  return f.kind=='Button' and f:GetParent()==parent and V.Plain(f:GetText())==text
 end)
end

------------------------------------------------------------------------
-- Leaderboard window
------------------------------------------------------------------------

-- Advance until the real Leaderboard window has bound a publication newer
-- than `since` (its VirtualStats().dataRefreshes when the change was made)
-- and has then stayed settled ("none" blocked reason) for `quiet` steps, so a
-- second publication that the same change causes has also been bound.
-- Returns the step count, or nil when the bound is reached.
function V.LeaderboardSettled(H,since,limit,quiet)
 local LB=Nexus.Leaderboard
 local calm=0
 for i=1,limit or 2000 do
  H.Advance(.05,.05)
  local v,d=LB.VirtualStats(),LB.DiagnosticSnapshot()
  if (since==nil or (tonumber(v.dataRefreshes) or 0)>since) and v.dataReady
   and d.blockedReason=='none' then
   calm=calm+1
   if calm>=(quiet or 10) then return i end
  else
   calm=0
  end
 end
 return nil
end

------------------------------------------------------------------------
-- Fake unit tooltip boundary (no native hook behaviour is assumed)
------------------------------------------------------------------------

V.UNIT='p3-fake-unit'

-- A fake unit tooltip with what the real annotation body reads (GetUnit,
-- NumLines, GetName and the global <name>TextLeft<i> line regions) and what it
-- writes (AddLine, Show). As in the client, the tooltip is reused: ClearLines
-- empties the line count while the line regions keep their last text (hidden,
-- not erased), so only lines 1..NumLines() describe the current unit. No
-- script runs here: neither OnTooltipSetUnit nor OnTooltipCleared is modelled
-- or relied on.
function V.Tooltip(name)
 local tip={name=name,lines={},regions={},shows=0}
 local function Region(i)
  local r=tip.regions[i]
  if not r then
   r={}
   function r:GetText() return self.text end
   function r:SetText(t) self.text=t end
   tip.regions[i]=r
   _G[tip.name..'TextLeft'..i]=r
  end
  return r
 end
 function tip:GetName() return self.name end
 function tip:GetUnit() return self.unitName,self.unit end
 function tip:NumLines() return #self.lines end
 function tip:AddLine(text) local i=#self.lines+1;self.lines[i]=text;Region(i):SetText(text) end
 function tip:Show() self.shows=self.shows+1 end
 function tip:ClearLines() self.lines={};self.unit,self.unitName=nil,nil end
 -- The client fills a unit tooltip before the annotation runs: the name line
 -- first, then the guild and level lines.
 function tip:SetUnitLines(unitName,lines)
  self:ClearLines()
  self.unit,self.unitName=V.UNIT,unitName
  for _,line in ipairs(lines) do self:AddLine(line) end
 end
 function tip:Release()
  for i=1,#self.regions do _G[self.name..'TextLeft'..i]=nil end
 end
 return tip
end

local function Pack(...) return {n=select('#',...),...} end

-- Run fn while the fake unit token answers as player `name`; every other unit
-- keeps the harness answers. The originals are restored before returning,
-- also when fn raises.
function V.WithUnit(name,fn,...)
 local realName,realIsPlayer=UnitName,UnitIsPlayer
 UnitName=function(unit,...)
  if unit==V.UNIT then return name,nil end
  return realName(unit,...)
 end
 UnitIsPlayer=function(unit,...)
  if unit==V.UNIT then return true end
  return realIsPlayer(unit,...)
 end
 local result=Pack(pcall(fn,...))
 UnitName,UnitIsPlayer=realName,realIsPlayer
 if not result[1] then error(result[2],0) end
 return unpack(result,2,result.n)
end

-- The real annotation body (Nexus.Nameplate._AugmentUnitTooltip) on the fake
-- tooltip, for the unit the tooltip currently shows. Returns the lines it
-- added and how often it called Show.
function V.Annotate(tip)
 local before,shows=#tip.lines,tip.shows
 V.WithUnit(tip.unitName,function() Nexus.Nameplate._AugmentUnitTooltip(tip) end)
 local added={}
 for i=before+1,#tip.lines do added[#added+1]=tip.lines[i] end
 return added,tip.shows-shows
end

-- The rank line among annotation lines, with the ordinal it shows.
function V.RankLine(lines)
 for _,line in ipairs(lines or {}) do
  local plain=V.Plain(line)
  if plain:find('on leaderboard',1,true) then return plain end
 end
 return nil
end

function V.ShowsRank(lines,n)
 local line=V.RankLine(lines)
 return line~=nil and line:find('%f[%w]'..V.Ordinal(n)..' on leaderboard')~=nil
end

------------------------------------------------------------------------
-- Saved Build selector text predicates (what the text claims, not its words)
------------------------------------------------------------------------

local NEGATIONS={'not ',"n't",'never','without','no longer'}

-- A sentence that says the action activates a Saved Build, or changes,
-- switches or swaps the active one, with no negation in that sentence. A
-- sentence that only mentions activation ("activate it in the game's own
-- window") makes no such claim. Returns true and the sentence, or false.
function V.ActivationPromise(text)
 local plain=V.Plain(text):lower()
 for sentence in (plain..'.'):gmatch('([^%.!?\n]+)') do
  local claims=sentence:find('%f[%a]activates%f[%A]')
   or sentence:find('%f[%a]chang%a*%s+%a*%s*active%f[%A]')
   or sentence:find('%f[%a]switch%a*%s+%a*%s*active%f[%A]')
   or sentence:find('%f[%a]swap%a*%s+%a*%s*active%f[%A]')
  if claims then
   local negated=false
   for _,word in ipairs(NEGATIONS) do
    if sentence:find(word,1,true) then negated=true end
   end
   if not negated then return true,sentence end
  end
 end
 return false
end

-- Does the label state that Saved Build `name` is the active one? Matches
-- "Active Loadout: One", "Active: One", "One (active)" and "One is (the)
-- active ..."; a label that names the active build separately, such as
-- "Editing: One (active: Six)", does not match.
function V.ClaimsActive(label,name)
 local l=V.Plain(label):lower()
 local n=Pattern(name)
 return l:find('active%s*%a*%s*:%s*'..n..'%f[%W]')~=nil
  or l:find('%f[%w]'..n..'%s*%(%s*active%s*%)')~=nil
  or l:find('%f[%w]'..n..'%s+is%s+the%s+active')~=nil
  or l:find('%f[%w]'..n..'%s+is%s+active')~=nil
end

-- Every line a GameTooltip owner script writes while fn runs. Only the
-- tooltip's text methods are observed (a fake observation boundary); they are
-- restored afterwards, also when fn raises.
function V.TooltipLines(fn,...)
 local lines={}
 local saved={}
 for _,key in ipairs({'SetText','AddLine','AddDoubleLine'}) do saved[key]=rawget(GameTooltip,key) end
 rawset(GameTooltip,'SetText',function(_,s) lines[#lines+1]=tostring(s or '') end)
 rawset(GameTooltip,'AddLine',function(_,s) lines[#lines+1]=tostring(s or '') end)
 rawset(GameTooltip,'AddDoubleLine',function(_,a,b) lines[#lines+1]=tostring(a or '')..' '..tostring(b or '') end)
 local result=Pack(pcall(fn,...))
 for key,value in pairs(saved) do rawset(GameTooltip,key,value) end
 for _,key in ipairs({'SetText','AddLine','AddDoubleLine'}) do
  if saved[key]==nil then rawset(GameTooltip,key,nil) end
 end
 return lines,result[1],result[2]
end

-- Bounded presentation observer. Sync.Stats initializes three diagnostic view
-- fields, so call it ONCE at setup and retain its live monotonic counter table.
-- RecomputeStats' adapter getters copy counters; Store.Settings is warmed here.
-- This observes the harness's modeled mutation APIs, not arbitrary deferred
-- client work or direct writes subsequently undone inside an unmodeled API.
function V.Same(a,b,seen)
 if type(a)~='table' or type(b)~='table'then return a==b end
 seen=seen or {};if seen[a]then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a)do if not V.Same(v,b[k],seen)then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function V.PresentationObserver(H)
 local O={events=0}
 local stats=Nexus.Sync.Stats()
 assert(type(stats)=='table' and type(stats.admittedPackets)=='number','SETUP: numeric transport admissions')
 Nexus.Store.Settings()
 local adapter=Nexus.GameAdapter
 local assignment=adapter.AssignmentActionSnapshot()
 assert(type(assignment.tokens)=='table' and next(assignment.tokens)~=nil,'SETUP: nonempty assignment tokens')
 function O.Snapshot()
  local runtime=Nexus.RecomputeStats()
  assert(type(stats.admittedPackets)=='number','transport admissions remain numeric')
  return {actions=#H.actions,sent=#H.sent,queued=stats.admittedPackets,chat=#H.chat,
   events=O.events,popup=H.popup,warning=Nexus.OverwriteWarning.IsOpen(),auto=runtime.autoEnabled,
   settings=H.Clone(Nexus.Store.Settings()),assignment=adapter.AssignmentActionSnapshot(),
   granted=H.grantedRequests,slots=H.slotRequests,
   pending=Nexus.Scheduler.Pending(),nextStepAt=runtime.nextStepAt}
 end
 -- Wrappers forward all returns/errors and are always removed before a caller
 -- (including C.scenario) receives an error. Count attempts, including a popup
 -- shown and hidden or a failed actor operation, rather than only final state.
 function O.Measure(fn,...)
  local saved,installed={},{}
  local function hook(owner,key)
   if type(owner)~='table' or type(owner[key])~='function'then return end
   installed[owner]=installed[owner] or {};if installed[owner][key]then return end
   installed[owner][key]=true
   local own,original=rawget(owner,key),owner[key]
   saved[#saved+1]={owner,key,own}
   owner[key]=function(...)O.events=O.events+1;return original(...)end
  end
  hook(_G,'print');hook(_G,'StaticPopup_Show');hook(_G,'SendChatMessage');hook(_G,'SendAddonMessage')
  for _,owner in ipairs({DEFAULT_CHAT_FRAME,UIErrorsFrame,ChatFrame1})do hook(owner,'AddMessage')end
  for _,key in ipairs({'RequestAuto','CancelAuto'})do hook(Nexus.OverwriteWarning,key)end
  for _,key in ipairs({'After','Every','Cancel'})do hook(Nexus.Scheduler,key)end
  hook(Nexus,'RequestRecompute');hook(Nexus,'DisableOrdinaryAutomation')
  local authority=Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
  hook(authority,'UpdateSettingsV1');hook(authority,'UpdateStateV1')
  for _,key in ipairs({'SelectPerk','BanishPerk','FreezePerk','RequestReroll','LockPerk','UnlockPerk',
   'ToggleTomeEcho','ActivateServerBuildSlot','SaveServerBuildSlot','UploadServerBuildSlot',
   'RequestServerBuildSlots','RequestGrantedPerks'})do hook(H.service,key)end
  for _,key in ipairs({'SetFirstRunWishlist','SetFirstRunWishlistIdentity','ClearFirstRunWishlist',
   'SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity','SetLoadoutWishlist','ClearLoadoutWishlist'})do hook(adapter,key)end
  for _,key in ipairs({'Start','Confirm','Prepare','ContinueConfirm','ConfirmLimit','Pause','Stop','Resume',
   'SetLimit','SetRecycle','SetSource','Exclude','ClearExclusions','Recheck'})do hook(Nexus.OrbRuntime,key)end
  local function restore()
   for i=#saved,1,-1 do local s=saved[i];rawset(s[1],s[2],s[3])end
  end
  local before,after
  local result=Pack(pcall(function(...)
   before=O.Snapshot()
   local value=Pack(pcall(fn,...))
   after=O.Snapshot()
   return value
  end,...))
  restore()
  if not result[1]then error(result[2],0)end
  return result[2],V.Same(before,after),before,after
 end
 function O.Quiet(label,fn,...)
  local result,quiet=O.Measure(fn,...)
  if not result[1]then error(result[2],0)end
  assert(quiet,'presentation effects: '..label)
  return unpack(result,2,result.n)
 end
 function O.Instrument()
  local log={render={},status={},calls=0,loud=0,errors=0}
  local render,status=Nexus.Panel.Render,Nexus.Panel.SetStatus
  local function enclosed(fn,...)
   local measured=Pack(pcall(O.Measure,fn,...))
   log.calls=log.calls+1
   if not measured[1]then log.errors=log.errors+1;error(measured[2],0)end
   local result,quiet=measured[2],measured[3]
   if not quiet then log.loud=log.loud+1 end
   if not result[1] or (fn==render and result[2]==false)then log.errors=log.errors+1 end
   if not result[1]then error(result[2],0)end
   return unpack(result,2,result.n)
  end
  Nexus.Panel.Render=function(model,...)
   log.render[#log.render+1]=H.Clone(model);return enclosed(render,model,...)
  end
  Nexus.Panel.SetStatus=function(value,...)
   log.status[#log.status+1]=value;return enclosed(status,value,...)
  end
  function log.restore()Nexus.Panel.Render,Nexus.Panel.SetStatus=render,status end
  function log.Run(fn,...)
   local result=Pack(pcall(fn,...));log.restore()
   if not result[1]then error(result[2],0)end
   assert(log.calls>0 and log.loud==0 and log.errors==0,'runtime presentation calls/errors/effects')
   return unpack(result,2,result.n)
  end
  return log
 end
 return O
end

return V
