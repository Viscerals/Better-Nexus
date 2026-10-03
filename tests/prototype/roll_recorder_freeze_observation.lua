-- The roll recorder's reading of the FIRST board after a Freeze (core/RollRecorder.lua), on synthetic
-- fixtures only: no game, no network, no private identifier. A first board that shows the spell as
-- justFrozen (J) is evidence that the Freeze was just observed, not that it survived and not that it
-- was lost: it is annotated "set:just". "set:kept" stays for a held (F) or carried (C) card and
-- "set:gone" for a spell that is not on the board at all. The sequences below are the observed
-- shapes: plain -> J -> C -> Take; ownership first seen after a LATER decision; truncated target
-- context; a final Take with no later observation; wait proposals with no intent; late joins.
Nexus=nil;NexusDB=nil
dofile('core/DiagnosticHistory.lua')
dofile('core/DiagnosticLogs.lua')
dofile('logic/Model.lua')
dofile('core/RollRecorder.lua')
local R,Logs=Nexus.RollRecorder,Nexus.DiagnosticLogs
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clockNow=100
local function Fresh()
 NexusDB={};R.Reset();Logs.Init(NexusDB)
 R.Configure({now=function()return clockNow end,epoch=function()return 1790000000 end})
end
local function Records() return Logs.Snapshot('rollTrace') end
UnitClass=function()return 'Mage','MAGE' end
Nexus.RuntimeBuildLabel=function()return 'test.0000-freeze-observation' end

-- Synthetic Echo ids: 1001 and 1002 are needed Wishlist targets, 2001..2003 are not.
local function Cards(list)
 local cards={}
 for i,c in ipairs(list)do cards[i]={spellId=c[1],quality=c[2] or 0,isFrozen=c.F,isCarried=c.C,justFrozen=c.J} end
 return {cards=cards,signature='sig'}
end
local function Ctx(board,action,o)
 o=o or {}
 local requested={}
 for i=1,(o.targets or 2)do requested[1000+i]=1 end
 return {
  state={allowBanish=true,allowReroll=true,allowFreeze=true},
  action=action,board=board,
  owned=o.owned or {synced=true,bySpell={}},locked={synced=true,bySpell={}},
  plan={requestedCounts=requested,lockedRequestedCounts={},explicitRoles=true},
  catalog={rows={},playerMask=1,levers={}},level=20,horizon=12,
  charges=o.charges or {banish=3,reroll=2,freeze=1,trustworthy=true},disabledLevers={},activeSlot=1,catalogRevision=1}
end
local function Act(kind,index,spell) return {type=kind,index=index,spellId=spell,reasonCode='SYNTHETIC',policyId='adaptive-0-settle-live1'} end
-- One executed action of a decision: prepared then accepted by the adapter.
local function Send(id,kind,index,spell)
 R.Intent(id,'prepared','intent_beat',{elapsed=0,type=kind,index=index,spellId=spell})
 R.Intent(id,'submitted','adapter_accepted',{elapsed=.4,mutation=true,type=kind,index=index,spellId=spell})
end
local function Snapshot(v,seen)
 if type(v)~='table' then return tostring(v) end
 seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=tostring(k)..'='..Snapshot(v[k],seen)end
 return '{'..table.concat(out,',')..'}'
end

-- 1. The observed sequence: plain board -> Freeze -> same ids with J -> Take another needed Echo
-- -> the held Echo returns as C -> Take the carried Echo, with no later observation.
Fresh()
local plain=Cards({{1001,1},{1002,2},{2001}})
local justBoard=Cards({{1001,1,J=true},{1002,2},{2002}})
local carriedBoard=Cards({{1001,1,C=true},{2003},{2001}})
local id1=R.Decision(Ctx(plain,Act('freeze',1,1001)))
Send(id1,'freeze',1,1001)
R.After({basis='next_board',board=justBoard})
local id2=R.Decision(Ctx(justBoard,Act('take',2,1002)))
Send(id2,'take',2,1002)
R.After({basis='next_board',board=carriedBoard})
local id3=R.Decision(Ctx(carriedBoard,Act('take',1,1001)))
Send(id3,'take',1,1001)
local rows=Records()
check(#rows==3 and rows[1].k=='D' and rows[2].k=='D' and rows[3].k=='D','three decision rows, no late rows in this sequence')
check(rows[1].sa=='f1.1001' and rows[1].af=='1001.1.J;1002.2.;2002.0.','the first board after the Freeze shows the Freeze spell as J: '..tostring(rows[1].af))
check(rows[1].fz=='set:just','a first J observation is "just frozen observed": '..tostring(rows[1].fz))
check(rows[1].fz~='set:gone' and rows[1].fz~='set:kept','a first J observation is neither gone nor kept')
check(rows[1].ao==nil and rows[1].fate==nil and rows[1].inc==nil,'the first J observation adds no ownership claim, fate or incompleteness')
check(rows[2].of=='1001.1.J;1002.2.;2002.0.' and rows[2].sa=='t2.1002' and rows[2].af=='1001.1.C;2003.0.;2001.0.','the next board shows the same Echo as C')
check(rows[2].fz=='held:kept','a later C observation is recorded separately as held:kept: '..tostring(rows[2].fz))
check(rows[1].fz~=rows[2].fz,'the first J and the later C stay distinguishable')
check(rows[3].sa=='t1.1001' and rows[3].of=='1001.1.C;2003.0.;2001.0.','the carried Echo is the final Take')
check(rows[3].cb==nil and rows[3].af==nil and rows[3].fz==nil and rows[3].ao==nil and rows[3].ac==nil and rows[3].fate==nil,
 'the final Take is right-censored: no outcome field exists, so none is claimed')
check(rows[3].io=='prepared:intent_beat@0.0=t1.1001,submitted:adapter_accepted@0.4!','the final Take keeps its lifecycle only')

-- 2. What counts as the Freeze spell, and the precedence of F and C over J.
local function FreezeThen(nextBoard)
 Fresh()
 local id=R.Decision(Ctx(plain,Act('freeze',1,1001)))
 Send(id,'freeze',1,1001)
 R.After({basis='next_board',board=nextBoard})
 return Records()[1]
end
check(FreezeThen(Cards({{1001,1,F=true},{1002,2},{2002}})).fz=='set:kept','F is kept')
check(FreezeThen(Cards({{1001,1,C=true},{1002,2},{2002}})).fz=='set:kept','C is kept')
check(FreezeThen(Cards({{1001,1,F=true,J=true},{1002,2},{2002}})).fz=='set:kept','F with J is still kept: the held state is the stronger observation')
check(FreezeThen(Cards({{1001,1,J=true},{1001,1,F=true},{2002}})).fz=='set:kept','one copy held and one just frozen: kept')
check(FreezeThen(Cards({{1001,1,F=true},{1001,1,J=true},{2002}})).fz=='set:kept','the same in the other order: kept')
check(FreezeThen(Cards({{1001,1,J=true},{1002,2},{2002}})).fz=='set:just','J alone is just frozen observed')
check(FreezeThen(Cards({{1001,1},{1002,2},{2002}})).fz=='set:gone','a plain card of the spell is gone, as before')
do
 local plainPresent=FreezeThen(Cards({{1001,1},{1002,2},{2002}}))
 check(plainPresent.fz=='set:gone' and plainPresent.af=='1001.1.;1002.2.;2002.0.','set:gone can be a PLAIN card still on the board: not observed frozen, carried or just frozen: '..tostring(plainPresent.af))
 local absent=FreezeThen(Cards({{1002,2},{2002},{2003}}))
 check(absent.fz=='set:gone' and not absent.af:find('1001.',1,true),'set:gone is also an absent spell; the two are told apart only by af')
end
check(FreezeThen(Cards({{1002,2},{2002},{2003}})).fz=='set:gone','an absent spell is gone, as before')
check(FreezeThen(Cards({{1002,2,J=true},{1001,1},{2002}})).fz=='set:gone','J on ANOTHER spell is not the submitted Freeze')
do
 Fresh()
 local before=FreezeThen(Cards({{1001,1,J=true},{1002,2},{2002}}))
 check(before.inc==nil,'the J observation marks nothing incomplete')
end

-- 3. A submitted Freeze that is ambiguous gets no survival annotation, J board or not.
Fresh()
local ida=R.Decision(Ctx(plain,Act('freeze',1,1001)))
Send(ida,'freeze',1,1001)
Send(ida,'take',2,1002)
R.After({basis='next_board',board=justBoard})
check(Records()[1].inc=='am' and Records()[1].fz==nil,'two submissions on a J board: ambiguous, no annotation: '..tostring(Records()[1].inc)..' '..tostring(Records()[1].fz))
Fresh()
ida=R.Decision(Ctx(plain,Act('freeze',1,1001)))
R.Intent(ida,'submitted','adapter_accepted',{elapsed=.4,mutation=true})
R.After({basis='next_board',board=justBoard})
check(Records()[1].inc=='am' and Records()[1].sa==nil and Records()[1].fz==nil,'an action-less submission on a J board: ambiguous, no annotation')
-- A Freeze that was only proposed is not an outcome on a J board either.
Fresh()
ida=R.Decision(Ctx(plain,Act('freeze',1,1001)))
R.Intent(ida,'prepared','intent_beat',{elapsed=0,type='freeze',index=1,spellId=1001})
R.Intent(ida,'superseded','board_changed_before_submit',{elapsed=.2,type='freeze',index=1,spellId=1001})
R.After({basis='next_board',board=justBoard})
check(Records()[1].sa==nil and Records()[1].fz==nil,'a proposed, never submitted Freeze gets no outcome on a J board')

-- 4. A held offer (decision board shows F, C or J) after a NON-Freeze action.
local function HeldThen(decisionBoard,nextBoard)
 Fresh()
 local id=R.Decision(Ctx(decisionBoard,Act('take',2,1002)))
 Send(id,'take',2,1002)
 R.After({basis='next_board',board=nextBoard})
 return Records()[1]
end
check(HeldThen(justBoard,carriedBoard).fz=='held:kept','J on the decision board, C after: kept')
check(HeldThen(justBoard,Cards({{1001,1,J=true},{2002},{2003}})).fz=='held:just','J on both boards: the Echo is still observed as just frozen, not gone')
check(HeldThen(justBoard,Cards({{1001,1},{2002},{2003}})).fz=='held:gone','J on the decision board, plain after: gone, as before')
check(HeldThen(carriedBoard,Cards({{1001,1,J=true},{2002},{2003}})).fz=='held:just','C on the decision board, J after: just frozen observed')

-- 5. Delayed ownership: a grant first observed after a LATER decision is never written onto the row
-- of the earlier action. ao is only the change between a row's own decision and its own first
-- observation, and it is read together with that row's own action.
-- ao is empty when the first observation shows no change in the recorded targets.
local function NoChange(row) return row.ao==nil or row.ao=='' end
local function Delayed(firstAction,firstSend,laterAction,laterSend,grantedSpell,board1,board2,board3)
 Fresh()
 local owned0={synced=true,bySpell={}}
 local idx=R.Decision(Ctx(board1,firstAction,{owned=owned0}))
 Send(idx,firstSend[1],firstSend[2],firstSend[3])
 R.After({basis='next_board',board=board2,owned=owned0})            -- the grant is not yet visible
 local idy=R.Decision(Ctx(board2,laterAction,{owned=owned0}))
 Send(idy,laterSend[1],laterSend[2],laterSend[3])
 R.After({basis='next_board',board=board3,owned={synced=true,bySpell={[grantedSpell]=1}}}) -- first seen here
 local out=Records()
 for _,r in ipairs(out)do check(r.ref==nil,'no late row is needed here') end
 return out[1],out[2]
end
do
 -- Take target A, then (later) Banish, ownership of A first observed after the Banish.
 local a,b=Delayed(Act('take',1,1001),{'take',1,1001},Act('banish',2,2001),{'banish',2,2001},1001,
  Cards({{1001,1},{1002,2},{2001}}),Cards({{2002},{2001},{2003}}),Cards({{2002},{2003},{1002,2}}))
 check(a.sa=='t1.1001','the first row is the Take of A')
 check(NoChange(a),'Take target A: the delayed grant is not attributed to the Take row: '..tostring(a.ao))
 check(b.sa=='b2.2001' and b.ao=='1001:+1','the grant first observed after the Banish appears only as an observation on the Banish row: '..tostring(b.ao))
 check(not (b.io or ''):find('t1.1001',1,true),'and the Banish row names no Take')
end
do
 -- Take a carried target B, then Banish, ownership of B first observed after the Banish.
 local a,b=Delayed(Act('take',1,1002),{'take',1,1002},Act('banish',3,2001),{'banish',3,2001},1002,
  Cards({{1002,2,C=true},{2001},{2002}}),Cards({{2003},{2002},{2001}}),Cards({{2003},{2001},{2002}}))
 check(a.sa=='t1.1002' and NoChange(a),'Take carried target B: no ownership change on the Take row')
 check(b.sa=='b3.2001' and b.ao=='1002:+1','the delayed grant of B is observed on the later Banish row only: '..tostring(b.ao))
end
do
 -- Take C (a carried needed Echo), then Reroll, ownership first observed after the Reroll.
 local a,b=Delayed(Act('take',1,1001),{'take',1,1001},Act('reroll',0,0),{'reroll',0,0},1001,
  Cards({{1001,1,C=true},{2001},{2002}}),Cards({{2003},{2002},{2001}}),Cards({{2001},{2002},{2003}}))
 check(a.sa=='t1.1001' and a.fz=='held:gone' and NoChange(a),'Take C: the C offer is not on the next board and no ownership is attributed: '..tostring(a.fz))
 check(b.sa=='r0.0' and b.ao=='1001:+1','the delayed grant is observed on the Reroll row only: '..tostring(b.ao))
end

-- 6. Truncated target context: 62 and 63 targets, 32 recorded. Absence is not negative proof.
for _,total in ipairs({62,63})do
 Fresh()
 local owned0={synced=true,bySpell={}}
 local id=R.Decision(Ctx(plain,Act('take',1,1001),{targets=total,owned=owned0}))
 Send(id,'take',1,1001)
 R.After({basis='next_board',board=Cards({{2001},{2002},{2003}}),owned={synced=true,bySpell={[1005]=1,[1040]=2}}})
 local row=Records()[1]
 local shown=0;for _ in row.tg:gmatch('[^;]+')do shown=shown+1 end
 check(row.tn==total and shown==32,total..' targets, 32 recorded: '..tostring(row.tn)..' '..shown)
 check(row.inc and ('.'..row.inc:gsub(',','.')..'.'):find('.tg.',1,true),'the cut is marked inc=tg: '..tostring(row.inc))
 check(row.tg:find('1005,',1,true)==1 or row.tg:find(';1005,',1,true)~=nil,'a shown target is recorded')
 check(row.tg:find('1040,',1,true)==nil,'an unshown target has no entry in tg')
 check(row.ao=='1005:+1','only recorded targets can show an ownership change; the +2 of the unshown 1040 is not in ao: '..tostring(row.ao))
 check(Records()[1].fz==nil,'a Take has no survival annotation')
end

-- 7. Wait and other proposals with no intent: observations, not executed actions.
Fresh()
local idw=R.Decision(Ctx(plain,{type='wait',reasonCode='WAIT_FOR_BOARD',policyId='adaptive-0-settle-live1'}))
R.After({basis='next_board',board=justBoard})
local waitRow=Records()[1]
check(waitRow.pr:find('wait:',1,true)==1,'a wait proposal is recorded as proposed')
check(waitRow.io==nil and waitRow.sa==nil and waitRow.cb=='next_board:no_intent','no intent: no lifecycle, no submitted action, basis names no intent: '..tostring(waitRow.cb))
check(waitRow.fz==nil,'a wait proposal gets no Freeze annotation, even when the next board shows J')
check(waitRow.af=='1001.1.J;1002.2.;2002.0.','the next board is still recorded as an observation')
Fresh()
R.Decision(Ctx(justBoard,{type='wait',reasonCode='WAIT_FOR_BOARD',policyId='adaptive-0-settle-live1'}))
R.After({basis='next_board',board=carriedBoard})
check(Records()[1].sa==nil and Records()[1].io==nil and Records()[1].fz=='held:kept','a wait on a held board records the held offer observation only: '..tostring(Records()[1].fz))
Fresh()
R.Decision(Ctx(plain,{type='wait',reasonCode='WAIT_FOR_BOARD',policyId='adaptive-0-settle-live1'}))
R.After({basis='board_cleared'})
check(Records()[1].cb=='board_cleared:no_intent' and Records()[1].af==nil,'no board after a wait: nothing is invented')

-- 8. Late joins: the recorder starts in the middle of a sequence. Observation-only limits.
Fresh()
check(R.After({basis='next_board',board=justBoard})==nil and #Records()==0,'an observation with no recorded decision writes nothing and invents none')
check(R.Intent('nonsense','confirmed','board_transition',{elapsed=1})==nil and #Records()==0,'a lifecycle fact with an unreadable decision id writes nothing')
-- A fact about a decision of an earlier session (a reload, a join) is kept only as its own linked row.
R.Intent('other-9','confirmed','board_transition',{elapsed=1})
check(#Records()==1 and Records()[1].k=='O' and Records()[1].ref==9 and Records()[1].s=='other' and Records()[1].fz==nil and Records()[1].af==nil,
 'a fact for an unseen decision is a linked late row with no observation fields')
-- The first recorded board already shows C (the Freeze happened before recording started).
Fresh()
local idl=R.Decision(Ctx(carriedBoard,Act('take',1,1001),{owned={synced=false,bySpell={}}}))
Send(idl,'take',1,1001)
R.After({basis='next_board',board=Cards({{2001},{2002},{2003}}),owned={synced=true,bySpell={[1001]=3}}})
local late=Records()[1]
check((','..tostring(late.inc)..','):find(',ow,',1,true)~=nil,'unsynced ownership at the join is marked inc=ow: '..tostring(late.inc))
check(late.fz=='held:gone' and late.sa=='t1.1001','the held card was observed and then absent: an observation of the next board only')
check(tostring(late.fz):find('set:',1,true)==nil,'no Freeze outcome is claimed for a Freeze the recorder never saw')
check(late.ao=='1001:+3','the first synced ownership shows as a change: read it with inc=ow, it is not a grant: '..tostring(late.ao))
-- A late lifecycle fact for a decision that is no longer open keeps its link and changes nothing else.
Fresh()
local idz=R.Decision(Ctx(plain,Act('freeze',1,1001)))
Send(idz,'freeze',1,1001)
R.After({basis='next_board',board=justBoard})
local decisionSeq=Records()[1].n
R.Decision(Ctx(justBoard,Act('take',2,1002)))
R.Intent(idz,'confirmed','board_transition',{elapsed=1.2,type='freeze',index=1,spellId=1001})
local lateRow=Records()[3]
check(lateRow.k=='O' and lateRow.ref==decisionSeq and (lateRow.io or ''):find('confirmed:board_transition',1,true),'a late lifecycle fact is its own linked row')
check(Records()[1].fz=='set:just' and lateRow.fz==nil and lateRow.af==nil,'it does not rewrite or add to the observation of the first row')

-- 9. The recorder still changes nothing it reads, with J boards.
Fresh()
local pristine=Ctx(justBoard,Act('freeze',1,1001));local reference=Snapshot(pristine)
local idp=R.Decision(pristine)
Send(idp,'freeze',1,1001)
R.After({basis='next_board',board=pristine.board,owned=pristine.owned,charges=pristine.charges})
check(Snapshot(pristine)==reference,'a J board and its context are not modified')

-- 10. The export keeps the raw flags and one column count; the legend explains the J annotation.
Fresh()
local ide=R.Decision(Ctx(plain,Act('freeze',1,1001)))
Send(ide,'freeze',1,1001)
R.After({basis='next_board',board=justBoard})
local text=R.Export()
check(text:find('|set:just|',1,true),'the export row carries set:just')
check(text:find('set:just',1,true) and text:find('just frozen observed',1,true) and text:find('not proof',1,true),'the legend defines set:just as observed, not proof')
check(text:find('NEXUS_ROLL_TRACE_1',1,true)==1,'the export schema number is unchanged: the value is additive')
-- The legend line states what each value means, matching the source and ADAPTIVE_ROLLING.md.
local legend
for line in text:gmatch('[^\n]+')do if line:find('D=decision',1,true)==1 then legend=line end end
check(legend~=nil,'the export has its legend line')
check(legend:find('set:gone = the matching target was not observed frozen, carried or just-frozen at the first observation (it may still be present as a plain card)',1,true),
 'the legend: set:gone is not observed frozen/carried/just-frozen and may be a plain card')
check(not legend:find('set:gone = not on the board',1,true) and not legend:find('not on the board',1,true),'the legend no longer says set:gone means not on the board')
check(legend:find('held:* is the same reading of a held offer after another action, and also appears on wait or no-intent rows',1,true),
 'the legend: held:* can also occur on wait or no-intent rows')
check(legend:find('set:just = the first board showed it as J, just frozen observed, not proof of the final result',1,true),'the legend keeps the set:just definition')
-- The documentation says the same.
local f=assert(io.open('docs/ADAPTIVE_ROLLING.md','rb'));local doc=f:read('*a'):gsub('%s+',' ');f:close()
check(doc:find('`set:gone` (the matching target was not observed frozen, carried or just-frozen at the first observation; it may still be present as a plain card)',1,true),'the docs: set:gone may be a plain card')
check(not doc:find('not on the first board in any frozen state',1,true),'the docs no longer use the older set:gone wording')
check(doc:find('and also appear on wait or no-intent rows',1,true),'the docs: held:* also appears on wait or no-intent rows')
print('PASS roll recorder freeze observation checks='..checks)
