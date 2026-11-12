-- Appearance is two presentation-only choices: a style (Nexus Vista, the
-- default, or Nexus Slate, the test.9094 look) and a colour. A player who
-- never chose gets Nexus Vista; an explicit saved choice is kept; a value this
-- build does not know is shown as kept and is never rewritten; only an
-- explicit selection writes, through the Store settings owner, and a refusal
-- applies to this session only. Repainting reuses what exists, a selection
-- reads without colour, and the difficulty / Soul Ash card keeps its own look.
-- Real TOC boot, Store and panels; synthetic data; no gameplay.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Boot(mutate)return F.Boot(F.Database({mutate=mutate}),F.OrbService)end
local function Settings()return F.Serialize(NexusDB.settings)end
local function Without(keys)
 local copy={};for k,v in pairs(NexusDB.settings)do if not keys[k]then copy[k]=v end end
 return F.Serialize(copy)
end

-- 1. The pure mapping.
local H=Boot()
local T=assert(Nexus.Theme,'the appearance module is loaded')
local r=T.Resolve(nil,nil)
check(r.style.id=='vista' and r.palette.id=='amethyst' and not r.explicitStyle and not r.explicitPalette,
 'no saved choice: Nexus Vista with Nexus Amethyst purple')
r=T.Resolve('slate',nil)
check(r.style.id=='slate' and r.palette.id=='graphite' and r.explicitStyle,
 'an explicit Nexus Slate keeps the test.9094 colours')
-- Slate keeps the test.9094 literals, but the Orb windows that test.9094 left
-- plain now use it too: its description says so instead of "unchanged".
local slateTip
for _,item in ipairs(T.MenuItems())do if item.text=='Nexus Slate' then slateTip=item.tooltipText end end
check(slateTip and slateTip:find('test.9094',1,true) and slateTip:find('Orb windows',1,true)
 and not slateTip:find('unchanged',1,true) and T.HELP:find('Orb windows',1,true) and not T.HELP:find('unchanged',1,true),
 'Slate is described as the test.9094 look that now also styles the Orb windows: '..tostring(slateTip))
r=T.Resolve('chronicle',{})
check(r.style.id=='vista' and r.palette.id=='amethyst' and r.unknownStyle and r.unknownPalette and r.savedStyle=='chronicle',
 'an unknown or malformed value falls back for display and is reported as unknown')

-- 2. No choice: Nexus Vista, and reading, the menu and styling write nothing.
local before=Settings()
check(T.Current().style=='vista' and T.Current().palette=='amethyst' and not T.Current().explicitStyle and not T.Current().explicitPalette,'the default is Nexus Vista with Nexus Amethyst')
T.Refresh();T.MenuItems();Nexus.OrbPanel.Show();Nexus.OrbPanel.ShowLog();Nexus.OrbPanel.Hide()
check(Settings()==before and NexusDB.settings.uiStyle==nil and NexusDB.settings.uiPalette==nil,
 'reading and showing the appearance writes nothing')

-- 3. Every colour has its exact name and a plain hue word; a check mark, not
-- a colour, marks the active entry. The style's own colours are named in its
-- Default row (section 12).
local NAMES={sapphire={'Nexus Sapphire','blue'},emerald={'Nexus Emerald','green'},
 amethyst={'Nexus Amethyst','purple'},ember={'Nexus Ember','orange'}}
local items=T.MenuItems()
for _,palette in ipairs(T.Palettes())do
 check(palette.label:match('^Nexus %u%l+$')~=nil,'a palette name is spaced properly: '..palette.label)
 check(type(palette.hue)=='string' and palette.hue~='','the palette has a hue word: '..palette.label)
 local expected=NAMES[palette.id]
 if expected then
  check(palette.label==expected[1] and palette.hue==expected[2],'the palette is named '..expected[1]..' ('..expected[2]..')')
 end
 local found=false
 for _,item in ipairs(items)do
  if item.text==palette.label..' ('..palette.hue..')'
   or item.text=='Default ('..palette.label..', '..palette.hue..')' then found=true end
 end
 check(found,'the menu shows the name with its hue: '..palette.label)
end
local styleChecked=0
for _,item in ipairs(items)do if item.checked and item.func then styleChecked=styleChecked+1 end end
check(styleChecked==2,'one style and one colour entry carry the check mark: '..styleChecked)

-- 4. A selected tab or view has a bar and a held highlight, not only a colour.
local tab=CreateFrame('Button',nil,UIParent);tab:SetText('Tab')
tab.GetFontString=function()return tab end
local locks=0;tab.LockHighlight=function()locks=locks+1 end;tab.UnlockHighlight=function()locks=locks-1 end
T.StyleButton(tab);T.SetSelected(tab,true)
check(tab._nexusSelectedBar and tab._nexusSelectedBar:IsShown() and locks==1,'a selection shows a bar and a held highlight')
T.SetSelected(tab,false)
check(not tab._nexusSelectedBar:IsShown() and locks==0,'and both go away together')

-- 5. Repainting reuses what exists: no texture, hook or tree walk is added,
-- and refreshes with no change re-resolve nothing.
local s0=T.Stats()
for _=1,10 do Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh();T.Refresh() end
local s1=T.Stats()
check(s1.resolves==s0.resolves,'unchanged refreshes resolve nothing: '..s0.resolves..' -> '..s1.resolves)
check(s1.treeWalks==s0.treeWalks and s1.nodesVisited==s0.nodesVisited,'and walk no frame tree')
local outcome,message=T.SetStyle('slate')
check(outcome=='durable' and message:find('Saved.',1,true),'an explicit choice is saved through the settings owner: '..tostring(message))
check(NexusDB.settings.uiStyle=='slate' and T.Current().style=='slate','the saved choice is in effect')
T.SetPalette('ember');T.Reapply();T.SetPalette(nil)
local s2=T.Stats()
check(s2.textures==s1.textures and s2.hooks==s1.hooks,'repainting adds no texture or hook: '
 ..s1.textures..'/'..s1.hooks..' -> '..s2.textures..'/'..s2.hooks)
check(s2.treeWalks==s1.treeWalks and s2.buttonsStyled==s1.buttonsStyled,'and restyles nothing from scratch')
check(s2.reapplies>s1.reapplies,'a change repaints the registry')
check(NexusDB.settings.uiPalette==nil,'returning to the style colours clears only the colour choice')
check(T.SetStyle('chronicle')==nil and NexusDB.settings.uiStyle=='slate','an unavailable style changes nothing')

-- 6. The difficulty / Soul Ash card is never painted.
Nexus.Panel.Show();H.Advance(.5)
local panel=assert(NexusPanel,'the HUD exists')
local card
for _,f in ipairs(H.frames)do if f._nexusThemeExempt and f:GetParent()==panel then card=f end end
check(card~=nil,'the protected card is marked exempt')
local painted=0
for _,m in ipairs({'SetBackdrop','SetBackdropColor','SetBackdropBorderColor'})do
 card[m]=function()painted=painted+1 end
end
T.StyleTree(panel);T.StyleTree(card);T.SetStyle('vista');T.SetPalette('amethyst');T.Reapply();T.SetPalette(nil)
check(painted==0,'no style or colour choice repaints the card: '..painted)
local function styledBelow(f)
 if f._nexusDarkStyled or f._nexusWindowStyled or f._nexusVirtualRowStyled then return true end
 for _,c in ipairs(f.children or {})do if styledBelow(c)then return true end end
 return false
end
check(not styledBelow(card),'and nothing inside it is restyled')

-- 7. A saved Nexus Slate is kept on a new session.
Boot(function(d)d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate' and T.Current().explicitStyle,'an explicit saved Slate stays Slate')
Nexus.OrbPanel.Show();T.MenuItems();T.Refresh()
check(Settings()==before,'and is not rewritten by reading it')

-- 8. A value this build does not know is kept, named, and never rewritten,
-- also when the player changes the other choice.
Boot(function(d)d.settings.uiStyle='nexus-chronicle-2';d.settings.uiPalette='aurora'end);T=Nexus.Theme
local c=T.Current()
check(c.style=='vista' and c.palette=='amethyst' and c.unknownStyle and c.unknownPalette,'an unknown saved value falls back to Vista/Amethyst for display')
local kept=0
for _,item in ipairs(T.MenuItems())do if item.text and item.text:find('it stays saved',1,true)then kept=kept+1 end end
check(kept==2,'the menu names both unknown values as kept: '..kept)
local unrelated=Without({uiPalette=true})
T.SetPalette('emerald')
check(NexusDB.settings.uiStyle=='nexus-chronicle-2','the unknown style is still saved')
check(NexusDB.settings.uiPalette=='emerald' and Without({uiPalette=true})==unrelated,
 'only the chosen key changed; every other setting is unchanged')

-- 9. A saved root this build keeps read-only: the saved choice is shown, a
-- new choice applies to this session only, and the saved data is unchanged.
Boot(function(d)d.settingsVersion=99;d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate','a read-only saved root keeps its explicit Slate')
outcome,message=T.SetStyle('vista')
check(outcome=='session' and message:find('this session only',1,true),'the choice is for this session only: '..tostring(message))
check(T.Current().style=='vista' and Settings()==before,'it applies now and the saved data is unchanged')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().style=='slate','after a reload the saved Slate is back')

-- 10. No settings owner: applied for this session, nothing saved.
Boot();T=Nexus.Theme
local owner=Nexus.MainInternals.StoreAuthorityOwner
Nexus.MainInternals.StoreAuthorityOwner=nil
outcome=T.SetPalette('emerald')
Nexus.MainInternals.StoreAuthorityOwner=owner
check(outcome=='unavailable' and NexusDB.settings.uiPalette==nil,'without an owner nothing is saved: '..tostring(outcome))
check(T.Current().palette=='emerald' and T.Current().sessionOnly,'and the colour applies for this session')
-- 11. New/unset choices get Amethyst without writing a saved preference;
-- explicit existing style/colour selections and unknown fields survive reload.
Boot();T=Nexus.Theme
before=Settings()
check(T.Current().palette=='amethyst','an unset preference uses the purple default')
T.Refresh();T.MenuItems();Nexus.Panel.Show();Nexus.OrbPanel.ShowMini();Nexus.OrbPanel.HideMini()
check(Settings()==before and NexusDB.settings.uiPalette==nil,'default display does not persist a new choice')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().palette=='amethyst' and not T.Current().explicitPalette,'unset stays unset and purple after reload')
for _,id in ipairs({'sapphire','emerald','amethyst','ember','auric','graphite'})do
 Boot(function(d)d.settings.uiStyle='vista';d.settings.uiPalette=id;d.settings.purpleDefaultSentinel='keep'end);T=Nexus.Theme
 before=Settings()
 check(T.Current().style=='vista' and T.Current().palette==id and T.Current().explicitPalette,'explicit '..id..' is preserved')
 T.Refresh();T.MenuItems();F.Reload(F.OrbService);T=Nexus.Theme
 check(T.Current().palette==id and Settings()==before and NexusDB.settings.purpleDefaultSentinel=='keep','explicit '..id..' persists without rewriting other fields')
end
Boot(function(d)d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate' and T.Current().palette=='graphite','an explicit existing Slate keeps its default Graphite colours')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().style=='slate' and T.Current().palette=='graphite' and Settings()==before,'explicit Slate survives reload without migration')
T.SetStyle('vista');T.SetPalette('sapphire');T.SetPalette(nil)
check(T.Current().palette=='amethyst' and NexusDB.settings.uiPalette==nil,'clearing a Vista colour choice returns to purple without storing the fallback')
Boot(function(d)d.settingsVersion=99;d.settings.uiStyle='vista';d.settings.uiPalette='sapphire'end);T=Nexus.Theme
before=Settings()
check(T.Current().palette=='sapphire','a future read-only saved root keeps its explicit non-purple palette')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().palette=='sapphire' and Settings()==before,'the future saved choice persists byte-for-byte through reload')

-- 12. Per style, the style's own colours and any palette that paints the same
-- RGB are one "Default" row (tester: the top two colours look the same).
-- Equivalence is computed here from the painted colours, never from names;
-- every other colour keeps its row; one check mark; reading writes nothing and
-- never migrates a saved value; only an explicit choice writes.
local function painted(p)
 local d=p.disabledBorder or {p.border[1]*0.5,p.border[2]*0.5,p.border[3]*0.5}
 local out={}
 for _,c in ipairs({p.border,p.windowBorder,p.hover,p.accent,d})do
  for j=1,3 do out[#out+1]=string.format('%.6f',c[j]) end
 end
 return table.concat(out,',')
end
local function colourRows()
 local rows,inColour={},false
 for _,item in ipairs(T.MenuItems())do
  if item.isTitle then inColour=item.text=='Appearance: colour'
  elseif inColour then rows[#rows+1]=item end
 end
 return rows
end
local function rowNamed(rows,text)
 local found,n=nil,0
 for _,item in ipairs(rows)do if item.text==text then found=item;n=n+1 end end
 return found,n
end
local function checkedRows(rows)
 local out={}
 for _,item in ipairs(rows)do if item.checked and item.func then out[#out+1]=item end end
 return out
end
local function defaultText(own) return 'Default ('..own.label..', '..own.hue..')' end
for _,styleId in ipairs({'vista','slate'})do
 local own=T.PALETTES[T.STYLES[styleId].palette]
 check(painted(T.Resolve(styleId,nil).palette)==painted(T.Resolve(styleId,own.id).palette),
  styleId..': no saved colour and an explicit '..own.id..' paint the same RGB')
 local other
 for _,p in ipairs(T.Palettes())do if not other and painted(p)~=painted(own) then other=p end end
 check(other~=nil,'SETUP: '..styleId..' has a colour that paints differently')
 for _,case in ipairs({{tag='no saved colour'},{tag='explicit default',value=own.id},
  {tag='explicit other',value=other.id},{tag='unknown',value='aurora'}})do
  Boot(function(d)d.settings.uiStyle=styleId;d.settings.uiPalette=case.value;d.settings.defaultRowSentinel='keep'end)
  T=Nexus.Theme
  local label=styleId..', '..case.tag
  before=Settings()
  local rows=colourRows();T.Refresh();Nexus.OrbPanel.Show()
  check(Settings()==before and NexusDB.settings.uiPalette==case.value and NexusDB.settings.uiStyle==styleId,
   label..': reading and rendering the menu writes and migrates nothing')
  local default,n=rowNamed(rows,defaultText(own))
  check(default and n==1,label..': exactly one Default row names the style colours')
  for _,item in ipairs(rows)do
   check(not (item.text or ''):find('Style colours',1,true),label..': no separate "Style colours" row')
  end
  local distinct={}
  for _,p in ipairs(T.Palettes())do
   local _,m=rowNamed(rows,p.label..' ('..p.hue..')')
   if painted(p)==painted(own) then
    check(m==0,label..': '..p.id..' paints the Default colours and is not listed again')
   else
    check(m==1,label..': the distinct colour '..p.id..' keeps its own row')
    distinct[#distinct+1]=p
   end
  end
  check(#checkedRows(rows)<=1,label..': at most one colour carries the check mark')
  local checked=checkedRows(rows)[1]
  if case.value==nil or case.value==own.id then
   check(checked==default,label..': the Default row carries the check mark')
  elseif case.value==other.id then
   check(checked and checked.text==other.label..' ('..other.hue..')',label..': the saved distinct colour is checked')
  else
   local kept=false
   for _,item in ipairs(rows)do if (item.text or ''):find('it stays saved',1,true)then kept=true end end
   check(checked==nil and kept,label..': an unknown saved colour checks nothing and is named as kept')
  end
  F.Reload(F.OrbService);T=Nexus.Theme
  check(Settings()==before,label..': reopening keeps the saved values byte-for-byte')
 end
end
-- An intentional Default choice clears only the colour, through the owner.
Boot(function(d)d.settings.uiStyle='vista';d.settings.uiPalette='amethyst';d.settings.defaultRowSentinel='keep'end)
T=Nexus.Theme
local own=T.PALETTES[T.STYLES.vista.palette]
local unrelated2=Without({uiPalette=true})
local default=rowNamed(colourRows(),defaultText(own))
check(default and default.checked,'SETUP: an explicit default colour shows the checked Default row')
default.func()
check(NexusDB.settings.uiPalette==nil and Without({uiPalette=true})==unrelated2 and not T.Current().explicitPalette,
 'choosing Default clears only the saved colour')
check(rowNamed(colourRows(),defaultText(own)).checked and #checkedRows(colourRows())==1,'and Default alone stays checked')
-- An explicit default colour stays pinned across a style change until the
-- player chooses again; reopening keeps it.
Boot(function(d)d.settings.uiStyle='vista';d.settings.uiPalette='amethyst'end);T=Nexus.Theme
local slateOwn=T.PALETTES[T.STYLES.slate.palette]
local amethyst=T.PALETTES.amethyst
local slateItem
for _,item in ipairs(T.MenuItems())do if item.text=='Nexus Slate' then slateItem=item end end
check(slateItem and slateItem.func,'SETUP: the Slate style row')
slateItem.func()
check(NexusDB.settings.uiStyle=='slate' and NexusDB.settings.uiPalette=='amethyst','a style change keeps the saved explicit colour')
local function slateChecks(label)
 local rows=colourRows()
 local d=rowNamed(rows,defaultText(slateOwn))
 local a=rowNamed(rows,amethyst.label..' ('..amethyst.hue..')')
 check(T.Current().style=='slate' and T.Current().palette=='amethyst' and T.Current().explicitPalette,label..': Slate keeps the pinned colour')
 if painted(amethyst)~=painted(slateOwn) then
  check(d and not d.checked and a and a.checked and #checkedRows(rows)==1,label..': the pinned colour, not Slate Default, is checked')
 end
end
slateChecks('after the style change')
before=Settings()
F.Reload(F.OrbService);T=Nexus.Theme
slateChecks('after reopening')
check(Settings()==before,'reopening rewrites nothing')
T.SetStyle('vista')
check(NexusDB.settings.uiPalette=='amethyst' and rowNamed(colourRows(),defaultText(own)).checked,
 'back on Vista the pinned colour is still saved and shows as Default')
-- No saved colour follows the style: Slate then shows its own Default.
Boot(function(d)d.settings.uiStyle='vista'end);T=Nexus.Theme
T.SetStyle('slate')
check(NexusDB.settings.uiPalette==nil and rowNamed(colourRows(),defaultText(slateOwn)).checked,
 'without a saved colour Slate checks its own Default')
-- 13. The visual corrections of the main
-- panel: the panel's own labels take their colour from the appearance's
-- roles, explicitly. T.StyleTree styles buttons only, so a label kept the
-- colour its font object or a fixed literal gave it, whatever the style.
-- Now the title, names and values are the style's text colour; captions
-- and secondary labels are its muted colour; the selected offer's tag and
-- outline and the plan progress fill are the palette's accent, an
-- unselected tag is ordinary text and an offer's quality is muted. They are
-- registered through T.StyleLabel (no new Theme API), so a changed colour or
-- style repaints them at once, with no render, texture, hook or tree walk.
-- The exempt difficulty card's texts take no role: they state their own
-- white base under the card's colour codes and no choice repaints them.
-- The colour a text or a plain texture was last given is recorded here (the
-- harness keeps none); the expected colours are read from the appearance's
-- own resolved tables, never restated. These checks fail at aca67cf4 by
-- design (no panel label was registered, the selected row had no outline,
-- the card's texts stated no colour). Native colours and contrast: NOT RUN.
-- The exempt mark (Theme.lua's header and T.Exempt: a marked frame keeps its
-- own look, and styling never paints it): an offer row is painted by the
-- appearance now, so it carries no mark; the difficulty card keeps its own.
-- A tree walk that enters a row finds a plain frame with no control: it
-- styles no button and adds no texture, hook or region. At aca67cf4 the rows
-- were marked (their colours were fixed), so those checks fail there too.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local function Record()
 local RM=G.RegionMethods()
 local setColor,setTexture=rawget(RM,'SetTextColor'),rawget(RM,'SetTexture')
 RM.SetTextColor=function(self,r,g,b,a)
  rawset(self,'_shownColor',{r,g,b})
  if setColor then return setColor(self,r,g,b,a) end
 end
 RM.SetTexture=function(self,r,g,b,a)
  if type(r)=='number' then rawset(self,'_shownFill',{r,g,b,a}) end
  if setTexture then return setTexture(self,r,g,b,a) end
 end
end
H=F.Boot(F.Database(),function(h) F.OrbService(h);Record() end);T=Nexus.Theme
Nexus.Panel.Show()
local offer={status='ready',level=40,auto=false,
 cards={{text='Cinder Lattice (Epic) wanted',highlight=true},{text='Hollow Bell (Rare) wanted'},{text='Ashen Tithe (Uncommon)'}},
 recommendation='Take Cinder Lattice.',serverStatus={tier='HC3',mode='HC3',ash='1,240',gain='+45%'},
 progress={wishlistName='Synthetic roles plan',total=6,owned=2,missing={},shed={},toLock={},unknownTomes={}}}
check(Nexus.Panel.Render(offer)==true and NexusPanel~=nil and NexusPanel:IsShown(),'SETUP: a Play panel with a selected offer renders')
local hud=NexusPanel
local rows=assert(hud._offerCards,'SETUP: the offer rows exist')
check(rows[1]:IsShown() and rows[1]._nexusMarked==true and rows[2]._nexusMarked==false and (rows[2].tag:GetText() or '')~='',
 'SETUP: the first offer is the marked (selected) one and the second has a tag of its own')
local function Colour(region) return region and rawget(region,'_shownColor') or nil end
local function Same(c,want)
 return type(c)=='table' and type(want)=='table' and c[1]==want[1] and c[2]==want[2] and c[3]==want[3]
end
local function Say(c) return type(c)=='table' and (tostring(c[1])..', '..tostring(c[2])..', '..tostring(c[3])) or 'no colour was set' end
-- The plan progress caption: the text its fitted hover covers (the region
-- that hover's first anchor names).
local function Caption()
 local hit=hud._progressLabelHit
 local anchor=hit and hit.points and hit.points[1] and hit.points[1][2]
 return type(anchor)=='table' and anchor or nil
end
local function RolesHold(tag)
 local chosen=T.Resolve(NexusDB.settings.uiStyle,NexusDB.settings.uiPalette)
 local text,muted,accent=chosen.style.text,chosen.style.disabledText,chosen.palette.accent
 check(Same(Colour(hud._contextTitle),text),tag..': the title is the style text colour ('..Say(Colour(hud._contextTitle))..')')
 check(Same(Colour(hud._contextBuild),text) and Same(Colour(hud._contextWishlist),text),
  tag..': the Build and Wishlist names are the style text colour ('..Say(Colour(hud._contextBuild))..')')
 check(Same(Colour(hud._contextBuildCaption),muted) and Same(Colour(hud._contextWishlistCaption),muted),
  tag..': the Build and Wishlist captions are the muted colour ('..Say(Colour(hud._contextBuildCaption))..')')
 check(Same(Colour(hud._rollStatus),text),tag..': the offer heading is the style text colour ('..Say(Colour(hud._rollStatus))..')')
 check(Same(Colour(Caption()),muted),tag..': the plan progress caption is the muted colour ('..Say(Colour(Caption()))..')')
 check(Same(Colour(rows[1].tag),accent) and Same(Colour(rows[2].tag),text),
  tag..': the selected offer tag is the accent and an unselected tag ordinary text ('..Say(Colour(rows[1].tag))..' / '..Say(Colour(rows[2].tag))..')')
 check(Same(Colour(rows[1].quality),muted) and Same(Colour(rows[2].quality),muted),
  tag..': an offer quality is the muted colour ('..Say(Colour(rows[1].quality))..')')
 local edges,drawn=#(rows[1].outline or {}),0
 for _,edge in ipairs(rows[1].outline or {}) do
  if edge:IsShown() and Same(rawget(edge,'_shownFill'),accent) then drawn=drawn+1 end
 end
 check(edges==4 and drawn==4,tag..': the selected row outline is four edges in the accent ('..drawn..' of '..edges..')')
 local fill=hud._play and hud._play.fill
 check(fill~=nil and fill:IsShown() and Same(rawget(fill,'_shownFill'),accent),
  tag..': the plan progress fill is the accent ('..Say(fill and rawget(fill,'_shownFill'))..')')
end
check(T.Current().style=='vista' and T.Current().palette=='amethyst','SETUP: the default Nexus Vista with Nexus Amethyst')
RolesHold('Nexus Vista, Nexus Amethyst')
-- A changed colour, then a changed style: repainted through the registry at
-- once, with no render in between and nothing added.
local roleStats=T.Stats()
check(T.SetPalette('ember')=='durable' and T.Current().palette=='ember','SETUP: Nexus Ember is chosen')
RolesHold('Nexus Ember, with no render')
check(T.SetStyle('slate')=='durable' and T.Current().style=='slate' and T.Current().palette=='ember','SETUP: Nexus Slate keeps the chosen Ember')
RolesHold('Nexus Slate with Nexus Ember, with no render')
local roleStats2=T.Stats()
check(roleStats2.textures==roleStats.textures and roleStats2.hooks==roleStats.hooks and roleStats2.treeWalks==roleStats.treeWalks,
 'repainting the panel labels adds no texture or hook and walks no frame tree')
-- The exempt difficulty card: its three texts state a white base and no
-- choice repaints them.
local statusCard
for _,f in ipairs(H.frames)do if f._nexusThemeExempt and f:GetParent()==hud and f.intensityBar then statusCard=f end end
check(statusCard~=nil and statusCard:IsShown(),'SETUP: the difficulty card is shown')
local cardTexts={}
for _,region in ipairs(statusCard and statusCard.regions or {})do if region.kind=='FontString' then cardTexts[#cardTexts+1]=region end end
local white=#cardTexts>=3
for i=1,math.min(3,#cardTexts) do if not Same(Colour(cardTexts[i]),{1,1,1}) then white=false end end
check(white,'the difficulty card texts keep their own white base under every style and colour ('..Say(Colour(cardTexts[1]))..')')
-- The mark and what the appearance does agree: no offer row is marked, and
-- the card is.
local markedRows=0
for i=1,3 do if rows[i]._nexusThemeExempt~=nil then markedRows=markedRows+1 end end
check(markedRows==0,'no offer row carries the theme-exempt mark: the appearance paints its tag, quality and outline ('..markedRows..' marked)')
local exemptBefore=T.Stats().exemptTrees
check(statusCard~=nil and statusCard._nexusThemeExempt==true and T.StyleTree(statusCard)==statusCard
 and T.Stats().exemptTrees==exemptBefore+1,'the difficulty card keeps the mark: a tree walk does not enter it')
-- A walk that enters the rows (the styled mark of an earlier walk is cleared
-- first, so each row is really entered here).
local walk0=T.Stats()
local regionCount,sameRegions={},true
for i=1,3 do
 regionCount[i]=#(rows[i].regions or {})
 rows[i]._nexusDarkTreeStyled=nil
 T.StyleTree(rows[i])
end
local walk1=T.Stats()
for i=1,3 do if #(rows[i].regions or {})~=regionCount[i] then sameRegions=false end end
check(walk1.treeWalks==walk0.treeWalks+3 and walk1.exemptTrees==walk0.exemptTrees,
 'a tree walk enters each offer row: they are not exempt trees ('..(walk1.treeWalks-walk0.treeWalks)..' entered, '
 ..(walk1.exemptTrees-walk0.exemptTrees)..' exempt)')
-- What the walk visits in a row. The harness lists a created FontString or
-- Texture both as a region and as a child (layout_geometry_support, G.Shown),
-- so Theme.StyleTree's loop over GetChildren visits a row's own regions as
-- nodes here; the client's GetChildren answers frames only, of which a row
-- has none. The check that stood here asked for no visited node at all, which
-- no frame with a region can meet in this harness. What must hold either
-- way is stated instead: every node the walk visits in a row is one of that
-- row's own regions, a texture or a text and never a frame (so no control),
-- and the walk styles no button and adds no texture, hook or region.
local listed,foreign,frames=0,0,0
for i=1,3 do
 local own={}
 for _,region in ipairs(rows[i].regions or {}) do own[region]=true end
 for _,child in ipairs({rows[i]:GetChildren()}) do
  listed=listed+1
  if not own[child] then foreign=foreign+1 end
  if child.kind~='Texture' and child.kind~='FontString' then frames=frames+1 end
 end
end
check(walk1.nodesVisited-walk0.nodesVisited==listed and foreign==0 and frames==0,
 'and visits only the rows\' own textures and texts: a row holds no frame ('..(walk1.nodesVisited-walk0.nodesVisited)
 ..' visited, '..listed..' listed, '..foreign..' not a region of its row, '..frames..' frames)')
check(walk1.buttonsStyled==walk0.buttonsStyled and walk1.textures==walk0.textures and walk1.hooks==walk0.hooks and sameRegions,
 'and finds no control in a row: no button styled, no texture, hook or region added ('..(walk1.buttonsStyled-walk0.buttonsStyled)
 ..' buttons, '..(walk1.textures-walk0.textures)..' textures, '..(walk1.hooks-walk0.hooks)..' hooks, regions '
 ..(sameRegions and 'unchanged' or 'changed')..')')
RolesHold('after a tree walk through the offer rows')
T.SetStyle('vista');T.SetPalette(nil)
check(T.Current().style=='vista' and T.Current().palette=='amethyst','the default appearance is back')
RolesHold('Nexus Vista, Nexus Amethyst again')
print('PASS ui_theme_appearance: Vista/Amethyst by default, one Default row per style by painted colour, explicit and unknown choices kept, owner-routed writes, no repaint allocation, exempt card untouched checks='..checks)
