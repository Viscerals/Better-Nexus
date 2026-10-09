-- Shared fixtures for the Select follow-up regressions (independent review
-- F2-F4, F6, F8, F11). Real modules booted by select_recovery_support.lua
-- with the synthetic service; no game, network or private data.
local R=dofile('tests/prototype/select_recovery_support.lua')
local F={R=R,SIBLING=200091}
-- Two needed offers (targets X and Y): the adaptive policy Freezes X first.
F.TWO={{spellId=R.X,quality=2},{spellId=R.Y,quality=1},{spellId=R.Z,quality=0}}
function F.Plain(text) return ((text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
function F.Head() return F.Plain(NexusPanel._rollStatus:GetText()) end
-- The heading names a wait and does not present automation as acting.
function F.HeadWaits()
 local head=F.Head()
 return head:find('waiting',1,true)~=nil and not head:find('Active',1,true),head
end
-- The Auto button tooltip's "Now:" line (the effective state), or nil.
function F.NowLine()
 local lines={}
 rawset(GameTooltip,'AddLine',function(_,text) lines[#lines+1]=tostring(text) end)
 local ok,err=pcall(function() NexusPanel._autoBtn.scripts.OnEnter(NexusPanel._autoBtn) end)
 rawset(GameTooltip,'AddLine',nil)
 if not ok then error(err,0) end
 for _,line in ipairs(lines) do if line:find('^Now: ') then return line end end
 return nil
end
-- Adapter gates, getters and senders a passive reader must not call.
F.GATES={'InFlight','PendingActions','UnconfirmedLatch','GrantedCount','Owned','LockedOwned','RequestGranted',
 'RecheckSelect','Take','Banish','Freeze','Reroll','Ready','RivalDetected','AutoAcceptOn','OrdinaryBoardAllowed',
 'OrbBlockReason','Board','Poll','Charges','Horizon','Level','Slots','ExternalActionSeen','ConsumeUserAction'}
-- Runs fn while every client service, those adapter functions, the client
-- option getter, the add-on query and any Orb service member are counted, and
-- every Perks field read is counted; then restores them. Returns the call
-- names, the read count and pcall's results.
function F.Passive(A,fn)
 local calls,reads,saved={},0,{}
 local function wrap(t,k,label)
  local f=type(t)=='table' and rawget(t,k)
  if type(f)~='function' then return end
  saved[#saved+1]={t,k,f}
  t[k]=function(...) calls[#calls+1]=label..k;return f(...) end
 end
 local function wrapAll(t,label)
  if type(t)~='table' then return end
  local keys={};for k in pairs(t) do keys[#keys+1]=k end
  for _,k in ipairs(keys) do wrap(t,k,label) end
 end
 local pe=ProjectEbonhold
 wrapAll(pe.PerkService,'service.')
 for _,k in ipairs(F.GATES) do wrap(A,k,'adapter.') end
 wrap(ProjectEbonholdOptionsService,'GetSetting','options.')
 wrap(_G,'IsAddOnLoaded','client.')
 wrapAll(pe.OrbService,'orb.')
 local perks=pe.Perks
 pe.Perks=setmetatable({},{__index=function(_,k) reads=reads+1;return perks[k] end})
 local out={pcall(fn)}
 pe.Perks=perks
 for i=#saved,1,-1 do local s=saved[i];s[1][s[2]]=s[3] end
 return calls,reads,unpack(out)
end
-- Whether a status line and an effective reason carry the same whole wait
-- text (either one may add its own prefix or suffix).
function F.SameWait(status,reason)
 status,reason=tostring(status or ''),tostring(reason or '')
 if status=='' or reason=='' then return false end
 local body=status:match('^waiting: (.+)$') or status
 return status:find(reason,1,true)~=nil or reason:find(body,1,true)~=nil
end
-- An overdue own Select (Auto's Take of X) whose client flag cleared on the
-- same board without a grant, with read refreshes already sent. Returns the
-- effective reason of that wait and the wait as the status line words it.
function F.Rechecking(H,A)
 R.AutoSubmit(H)
 H.perks.pendingSelectSpellId=nil;H.Notify()
 for _=1,40 do H.Advance(.5);if (Nexus.AutomationEffectiveState().rechecks or 0)>=1 then break end end
 local e=Nexus.AutomationEffectiveState()
 local ordinal,phase,_,_,_,overdue=A.SelectUnresolved()
 assert(ordinal==1 and phase=='grant' and overdue and e.state=='rechecking' and e.rechecks>=1,
  'setup: an overdue own Select with rechecks sent: '..tostring(phase)..'/'..tostring(e.state))
 assert(type(e.reason)=='string' and e.reason~='','setup: the wait has a reason')
 return e.reason,H.runtime.StatusLine():match('^waiting: (.+)$')
end
-- A client Select that accepts even while its own flag is set (unknown
-- natively; the harness client refuses). Fixture only: it simulates the
-- client's result and replaces the hooked service. Returns its call count.
function F.AcceptingSelect(H)
 local n=0
 H.service.SelectPerk=function(id)
  n=n+1;H.perks.pendingSelectSpellId=id;H.actions[#H.actions+1]={'take',id};return true
 end
 return function() return n end
end
-- Every player action the decision log attached to a decision, "kind:arg".
function F.UserActions()
 local out={}
 for _,e in ipairs(Nexus.DiagnosticLogs.Snapshot('decision')) do
  for _,u in ipairs(type(e.user)=='table' and e.user or {}) do out[#out+1]=tostring(u.kind)..':'..tostring(u.arg) end
 end
 return out
end
-- The roll record's action lifecycle facts (decision rows and late rows).
function F.TraceIo()
 local out={}
 for _,r in ipairs(Nexus.DiagnosticLogs.Snapshot('rollTrace')) do if r.io then out[#out+1]=r.io end end
 return table.concat(out,',')
end
function F.Lifecycle()
 local stats=Nexus.RecomputeStats()
 return stats.lastActionLifecycle,stats.actionLifecycle
end
-- R.Boot with synthetic catalog rows added before the catalog is first built
-- (R.Boot loads the harness, then the add-on): the harness load is observed.
function F.BootWith(prepare,oldCopy)
 local load=dofile
 dofile=function(path) local h=load(path);if path=='tests/prototype/harness.lua' then prepare(h) end;return h end
 local ok,H,A=pcall(R.Boot,oldCopy)
 dofile=load
 if not ok then error(H,0) end
 return H,A
end
return F
