-- F-S4-1 (P3), regression-first: a player whose tooltip already contains the
-- word "Nexus" still gets the Nexus badge and rank. The unit-tooltip
-- annotation (ui/Nameplate.lua) skips a tooltip that already carries its own
-- badge, but it tests every current line for the plain text "Nexus", so the
-- client's own name line ("Nexusthorn") or guild line ("<Nexus Wardens>")
-- suppresses the badge and the "Nth on leaderboard" line on every hover.
-- Healthy behaviour (EXPECT, fails at the baseline): a recognised player whose
-- name or guild line contains "Nexus" receives the badge and the correct rank
-- line from the real annotation body.
-- Unchanged (GUARD, holds at the baseline): an ordinary recognised player
-- receives both lines once and the tooltip is shown again; annotating the
-- same tooltip again adds nothing (the real badge deduplicates), also right
-- after an annotation of a "Nexus" name; a reused tooltip, cleared and filled
-- for another unit, is annotated even though its hidden line regions still
-- hold the previous unit's badge, and so is the same unit after a clear; an
-- unknown player gets nothing; no game action.
-- Real TOC boot, DPS owner, catalog and annotation body
-- (Nexus.Nameplate._AugmentUnitTooltip). The unit and the tooltip are fake
-- boundaries (view_regression_support V.Tooltip/V.WithUnit): no native hook
-- or OnTooltipCleared behaviour is assumed. Artificial names and guilds.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('tooltip_marker_name_guild')
local fx=L.New({players={
 {name='Alicia',class='MAGE',dps={dummy=40000},locked=0},
 {name='Nexusthorn',class='PRIEST',dps={dummy=30000},locked=0},
 {name='Bravo',class='PRIEST',dps={dummy=20000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database({version=2})))
for _=1,400 do H.Advance(.05,.05) end
local D=Nexus.DpsCapture
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
for i,name in ipairs({'Alicia','Nexusthorn','Bravo'}) do
 local info=D.GetPlayerInfo(name)
 C.setup(type(info)=='table' and info.rank==i,'fixture: the real DPS reader ranks '..name..' '..V.Ordinal(i),
  info and info.rank)
end

-- One tooltip, reused for every hover as the client reuses its tooltip.
local tip=V.Tooltip('ArtificialUnitTooltip')
local function Hover(name,guild)
 tip:SetUnitLines(name,{name,guild,'Level 80'})
 return V.Annotate(tip)
end
local function HasBadge(lines)
 for _,line in ipairs(lines) do
  if V.Plain(line):find('Nexus user',1,true)==1 then return true end
 end
 return false
end
local function Annotated(tag,lines,shows,rank,check)
 print('OBSERVED',tag,'added='..#lines,'shows='..shows,'rank line='..printable(V.RankLine(lines)))
 check(#lines==2 and HasBadge(lines) and V.ShowsRank(lines,rank) and shows==1,
  tag..': the badge and "'..V.Ordinal(rank)..' on leaderboard" are added once and the tooltip is shown',#lines)
end

C.scenario('T1 an ordinary recognised player',function()
 local lines,shows=Hover('Alicia','<Simple Guild>')
 Annotated('T1',lines,shows,1,C.guard)
 lines,shows=V.Annotate(tip)
 C.guard(#lines==0 and shows==0,'T1: annotating the same tooltip again adds nothing',#lines)
end)

C.scenario('T2 a name that contains "Nexus"',function()
 local lines,shows=Hover('Nexusthorn','<Simple Guild>')
 Annotated('T2',lines,shows,2,C.expect)
 lines,shows=V.Annotate(tip)
 C.guard(#lines==0 and shows==0,'T2: annotating the same tooltip again adds nothing',#lines)
end)

C.scenario('T3 a guild that contains "Nexus"',function()
 local lines,shows=Hover('Alicia','<Nexus Wardens>')
 Annotated('T3',lines,shows,1,C.expect)
 lines,shows=V.Annotate(tip)
 C.guard(#lines==0 and shows==0,'T3: annotating the same tooltip again adds nothing',#lines)
end)

C.scenario('T4 a reused tooltip for another unit',function()
 Hover('Alicia','<Simple Guild>')
 C.setup(tip:NumLines()==5,'T4: fixture: the previous unit was annotated',tip:NumLines())
 -- Cleared and filled for Bravo: lines 4 and 5 are hidden but keep their text.
 tip:SetUnitLines('Bravo',{'Bravo','<Simple Guild>','Level 80'})
 local stale=tip.regions[4] and V.Plain(tip.regions[4]:GetText()) or ''
 C.setup(tip:NumLines()==3 and stale:find('Nexus user',1,true)==1,
  'T4: fixture: a hidden line region still holds the previous unit\'s badge',stale)
 local lines,shows=V.Annotate(tip)
 Annotated('T4',lines,shows,3,C.guard)
 lines,shows=Hover('Alicia','<Simple Guild>')
 Annotated('T4 same unit after a clear',lines,shows,1,C.guard)
end)

C.scenario('T5 an unknown player',function()
 local lines,shows=Hover('Zedunknown','<Simple Guild>')
 C.guard(#lines==0 and shows==0,'T5: an unknown player gets no line',#lines)
end)

tip:Release()
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(a "Nexus" name or guild no longer suppresses the badge and rank; the real badge still deduplicates)')
