-- Full UI localization (issues #143-#148): the Settings window chooses its
-- Display and Notices rows from the panel's Options menu by stable semantic
-- identities, never by English titles or label substrings, so a translated
-- menu keeps every setting and its callback. The stale-click safeguard
-- (M.Activate re-reads the row and refuses a changed one) is retained.
-- Synthetic offline evidence; native NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local settings=assert(Nexus.SettingsWindow)
local panel=assert(Nexus.Panel)

local function ids(rows)
 local out={};for i,row in ipairs(rows) do out[i]=tostring(row.id) end;return table.concat(out,',')
end
local englishDisplay,englishNotices=settings.Rows('display'),settings.Rows('notices')
check(#englishDisplay==2,'SETUP English Display shows the DPS records and HUD rows: '..#englishDisplay)
check(#englishNotices>=1,'SETUP English Notices shows its rows')
check(englishDisplay[1].text:find('DPS records',1,true) and englishDisplay[2].text:find('Difficulty / Soul Ash HUD',1,true),
 'GUARD exact English Display rows are unchanged')
check(ids(englishDisplay)=='dps_records,hud_mode','EXPECT Display rows carry their stable identities')

-- A translated menu: every visible title, label and hover text differs from
-- the English (as any real pack would), while identities and callbacks stay.
local realMore=panel.MoreMenuItems
local function translate(items,seen)
 seen=seen or {}
 if seen[items] then return end;seen[items]=true
 for _,item in ipairs(items) do
  if type(item.text)=='string' then item.text='\194\171'..item.text:upper()..'\194\187' end
  if type(item.tooltipText)=='string' then item.tooltipText='\194\171'..item.tooltipText..'\194\187' end
  if type(item.tooltipTitle)=='string' then item.tooltipTitle='\194\171'..item.tooltipTitle..'\194\187' end
  if type(item.menuList)=='table' then translate(item.menuList,seen) end
 end
end
panel.MoreMenuItems=function(...) local items=realMore(...);translate(items);return items end
local display,notices=settings.Rows('display'),settings.Rows('notices')
check(#display==2 and ids(display)=='dps_records,hud_mode','EXPECT translated titles and labels keep both Display settings: '..#display)
check(#notices==#englishNotices,'EXPECT translated titles keep every Notices row: '..#notices)
check(display[1].action and display[1].text:find('\194\171',1,true),'EXPECT the translated Display row keeps its callback and shows translated text')

-- Explicit activation still goes through the owner; a changed row is refused.
local saved=Nexus.Panel.SavedLayoutRoot()
local before=saved.uiShowPerformance
check(settings.Activate(1,'not the current row text')==false and saved.uiShowPerformance==before,'GUARD stale click is refused and changes nothing')
settings.Select('display')
check(settings.Activate(1,display[1].text)==true and saved.uiShowPerformance~=before,'GUARD explicit click on the current translated row uses its own callback')
panel.MoreMenuItems=realMore
print('PASS l10n_settings_identity checks='..checks..' (synthetic; native NOT_RUN)')
