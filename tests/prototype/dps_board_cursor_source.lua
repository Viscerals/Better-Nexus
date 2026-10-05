-- The DPS board cursor is bound to the DPS revision it started from: a DPS
-- change (a received record) invalidates a live cursor, a new cursor then
-- walks the updated board, and an unchanged board walks to completion. Real
-- boot, real DPS store, real inbound admission; synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local fx=L.New({players={
 {name='Alpha',class='MAGE',dps={dummy=48000}},
 {name='Bravo',class='PRIEST',dps={dummy=51000}},
}})
local H=F.Boot(fx:Install(F.Database({version=2})))
for _=1,240 do H.Advance(.5,.5) end
local D=Nexus.DpsCapture
local function Walk(cursor)
 for _=1,200 do
  local done,why=D.DpsBoardCursorNext(cursor)
  if why then return false,why end
  if done then return true end
 end
 return false,'unbounded'
end
local function Dps(cursor,name)
 for _,row in ipairs(cursor.rows) do if row.player==name then return row.dps end end
 return nil
end
-- 1. A complete walk of an unchanged board.
local cursor=D.BeginDpsBoardCursor('dummy')
check(type(cursor)=='table','a cursor is returned')
local done,why=Walk(cursor)
check(done==true and why==nil and #cursor.rows==2,'the walk completes with both rows: '..tostring(why)..' '..#cursor.rows)
check(Dps(cursor,'Alpha')==48000,'the walk shows the stored result: '..tostring(Dps(cursor,'Alpha')))
-- 2. A DPS revision (a received record) invalidates a live cursor, also one
-- that already walked part of the board.
local live=D.BeginDpsBoardCursor('dummy')
check(D.DpsBoardCursorNext(live)==false,'the live cursor took one step')
check(fx:Receive('Alpha','dummy',{dps=52000})==true,'fixture: a record is received')
done,why=D.DpsBoardCursorNext(live)
check(done==true and why=='DPS changed','a DPS revision invalidates the live cursor: '..tostring(why))
done,why=D.DpsBoardCursorNext(live)
check(done==true,'an invalidated cursor stays done')
-- 3. A new cursor walks the updated board to completion.
local again=D.BeginDpsBoardCursor('dummy')
done,why=Walk(again)
check(done==true and why==nil and #again.rows==2,'a new cursor completes: '..tostring(why))
check(Dps(again,'Alpha')==52000,'and shows the received result: '..tostring(Dps(again,'Alpha')))
-- 4. An unknown category gives no cursor; a finished cursor reports done.
check(D.BeginDpsBoardCursor('combined')==nil,'only dummy and lk boards have cursors')
check(D.DpsBoardCursorNext(again)==true,'a finished cursor reports done')
print('PASS dps_board_cursor_source checks='..checks)
