-- Explicit two-stage Orb approval UI. Reading this window never spends.
Nexus=Nexus or {}
local UI={};Nexus.OrbPanel=UI
local frame,rows,targetRows,confirmation,approvalData
local sourcePage,targetPage,choice=1,1,1
local PAGE=6
local function text(parent,x,y,w,h,value)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",x,y);f:SetSize(w,h);f:SetJustifyH("LEFT");f:SetJustifyV("TOP");f:SetText(value or "");return f
end
local function button(parent,x,y,w,label,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn);b:EnableMouse(true)
    b:SetFrameLevel(parent:GetFrameLevel()+2);if Nexus.Theme and Nexus.Theme.StyleButton then Nexus.Theme.StyleButton(b) end
    return b
end
local function notify(ok,err)
    if frame then frame.notice:SetText(err or (ok and "Updated. Review the plan before spending." or "No change.")) end
    UI.Refresh()
end
local function safeName(s) return tostring(s or ""):gsub("|","||"):gsub("[%c]"," "):sub(1,100) end
local function quality(q) return ({[0]="Common","Uncommon","Rare","Epic","Legendary"})[q] or ("Quality "..tostring(q)) end
local function newWindow(name,w,h)
    local f=CreateFrame("Frame",name,UIParent);f:SetSize(w,h);f:SetPoint("CENTER",UIParent,"CENTER",0,0)
    f:SetFrameStrata("DIALOG");f:SetFrameLevel(120);f:EnableMouse(true);f:SetMovable(true)
    f:RegisterForDrag("LeftButton");f:SetScript("OnDragStart",function(self)self:StartMoving()end)
    f:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    f:SetBackdropColor(.035,.04,.05,1);f:SetBackdropBorderColor(.45,.4,.3,1);f:Hide()
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]=name
    return f
end
local function openConfirm(mode)
    local data,err=Nexus.OrbRuntime.Prepare(mode);if not data then notify(false,err);return end
    if not confirmation then
        confirmation=newWindow("NexusOrbApproval",610,505);confirmation:SetFrameStrata("FULLSCREEN_DIALOG");confirmation:SetFrameLevel(160)
        confirmation.title=text(confirmation,18,-18,570,24,"Approve this Orb run")
        confirmation.summary=text(confirmation,18,-50,570,94)
        local sf=CreateFrame("ScrollFrame",nil,confirmation,"UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT",20,-151);sf:SetSize(548,181)
        local child=CreateFrame("Frame",nil,sf);child:SetSize(526,181);sf:SetScrollChild(child)
        confirmation.sources=text(child,0,0,518,181);confirmation.sourceChild=child
        confirmation.check=CreateFrame("CheckButton",nil,confirmation,"UICheckButtonTemplate")
        confirmation.check:SetPoint("TOPLEFT",20,-347);confirmation.check:SetSize(26,26);confirmation.check:EnableMouse(true)
        confirmation.check:SetFrameLevel(164)
        text(confirmation,52,-349,530,50,"I approve the listed source copies and this spending limit. Stop prevents new submissions; it cannot undo a submitted Orb.")
        confirmation.closeNotice=text(confirmation,20,-400,570,38,"Closing the window does not stop an approved run. Use Pause or Stop.")
        confirmation.go=button(confirmation,205,-456,165,"Confirm & start",function()
            if not confirmation.check:GetChecked() or not approvalData then return end
            local ok,e=Nexus.OrbRuntime.Confirm(approvalData.token);approvalData=nil;confirmation:Hide();notify(ok,e)
        end)
        button(confirmation,385,-456,130,"Cancel",function()approvalData=nil;confirmation:Hide()end)
        confirmation:SetScript("OnHide",function()approvalData=nil end)
    end
    approvalData=data;confirmation.check:SetChecked(false)
    confirmation.summary:SetText("Wishlist: "..safeName(data.name).."\nMaximum: "..data.limit.." Orb(s), one per replacement. Balance: "..data.charges
        .."\nApproved source copies: "..data.sourceCopies.."; needed and permanent copies remain protected."
        .."\n"..(data.recycle and "Safe unwanted replacements may be selected and recycled." or "Recycling OFF: pause if the offer has no safe wanted target.")
        .."\nOrdinary Automation will be turned OFF and will not restart afterward.")
    local lines={"Approved sources (scroll to inspect the complete list):"}
    for _,v in ipairs(data.sources) do lines[#lines+1]=v.copies.." x "..safeName(v.name).." ("..quality(v.quality)..")" end
    confirmation.sources:SetText(table.concat(lines,"\n"));local height=math.max(181,#lines*27)
    confirmation.sources:SetHeight(height);confirmation.sourceChild:SetHeight(height);confirmation:Show()
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local ready=Nexus.StartupStatus and Nexus.StartupStatus()
    if not ready or not ready.coreReady then
        frame.status:SetText("Reading local saved data. Orb controls stay disabled; shared-library loading is not required.")
        for _,b in ipairs(frame.mutations) do b:Disable() end
        return
    end
    for _,b in ipairs(frame.mutations) do b:Enable() end
    local s=Nexus.OrbRuntime.Status();frame.snapshot=s
    local phase={IDLE="Not started",READY="Preparing the next source",WAIT_OFFER="Waiting for the Orb offer",WAIT_RESULT="Waiting for result confirmation",PAUSED="Paused",STOPPED="Stopped",COMPLETE="Targets complete",ROLLED_COMPLETE="Rolled targets complete; permanent targets remain",LIMIT="Run limit reached",OUT_OF_ORBS="No Orbs remain",NO_SOURCES="No approved sources remain",RECOVERY="Previous action needs checking"}
    frame.status:SetText((phase[s.state] or s.state).."\n"..(s.error or s.reason or "")
        .."\nBalance: "..tostring(s.charges or "unknown").."  |  Confirmed spent: "..s.spent.."  |  Unresolved exposure: "..s.reserved.."  |  Run limit: "..s.limit)
    frame.plan:SetText("Targets: "..safeName(s.config.name)..(s.progress and ("  -  "..s.progress.rolledMissing.." rolled copies still needed; "..s.progress.permanentMissing.." permanent copies unavailable to Orbs") or ""))
    if not frame.limit:HasFocus() then frame.limit:SetText(tostring((s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT") and s.limit or s.config.maxOrbs)) end
    frame.recycle:SetChecked(s.config.recycle)
    local items=s.progress and s.progress.items or {}
    targetPage=math.max(1,math.min(targetPage,math.max(1,math.ceil(#items/PAGE))))
    for i,r in ipairs(targetRows) do
        local index=(targetPage-1)*PAGE+i;local v=items[index];r.index=index
        if v then
            local c=s.catalog and s.catalog[v.spellId]
            r.label:SetText(safeName(c and c.name or v.spellId).." ("..quality(v.quality)..")\n"..v.owned.."/"..v.copies.." "..(v.role=="permanent" and "permanent targets" or "rolled copies"));r:Show()
        else r:Hide() end
    end
    frame.targetPage:SetText("Targets "..targetPage.."/"..math.max(1,math.ceil(#items/PAGE)).." - topmost missing target is preferred")
    local sources=s.sources or {};sourcePage=math.max(1,math.min(sourcePage,math.max(1,math.ceil(#sources/PAGE))))
    for i,r in ipairs(rows) do
        local v=sources[(sourcePage-1)*PAGE+i];r.key=v and v.key;r.max=v and v.excess or 0
        if v then
            r.label:SetText(safeName(v.name).." ("..quality(v.quality)..")\n"..v.excess.." safe excess / "..v.count.." owned")
            r.count:SetText(tostring(s.config.sources[v.key] or 0).." approved");r:Show()
        else r:Hide() end
    end
    frame.sourcePage:SetText("Sources "..sourcePage.."/"..math.max(1,math.ceil(#sources/PAGE)).." - only listed approved copies may be replaced")
    local busy=s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT"
    for _,b in ipairs(frame.configure) do if busy then b:Disable() else b:Enable() end end
    if s.pending and s.state=="STOPPED" then frame.notice:SetText("Resolve the game's offer manually. Stop cannot undo an accepted spend.") end
end
local function ensure()
    if frame then return end
    frame=newWindow("NexusOrbPanel",820,710);rows={};targetRows={};frame.mutations={};frame.configure={}
    text(frame,20,-18,670,28,"Orbs / Lost Memories - refine an existing rolled build")
    button(frame,748,-14,50,"Close",function() frame:Hide() end)
    frame.assigned=button(frame,20,-48,180,"Use assigned Wishlist",function()notify(Nexus.OrbRuntime.UseAssignedWishlist())end)
    frame.choose=button(frame,210,-48,200,"Choose saved Wishlist",function()
        local cs=Nexus.GameAdapter.GetWishlistCandidates()
        if #cs==0 then notify(false,"No saved Wishlists available. Create or resolve one in the editor.");return end
        if not frame.selector then
            frame.selector=newWindow("NexusOrbWishlistSelector",520,385);frame.selector:SetFrameStrata("FULLSCREEN_DIALOG");frame.selector:SetFrameLevel(150)
            text(frame.selector,20,-20,475,35,"Choose the Wishlist for this Orb plan")
            frame.selector.rows={}
            for i=1,8 do
                local row=button(frame.selector,20,-62-(i-1)*31,480,"",function()end)
                frame.selector.rows[i]=row
            end
            button(frame.selector,20,-325,110,"Previous",function()choice=math.max(1,choice-8);frame.selector.refresh()end)
            button(frame.selector,142,-325,90,"Next",function()choice=choice+8;frame.selector.refresh()end)
            button(frame.selector,390,-325,110,"Cancel",function()frame.selector:Hide()end)
        end
        local picker=frame.selector;picker.choices=cs
        picker.refresh=function()
            if choice>#picker.choices then choice=math.max(1,1+math.floor((#picker.choices-1)/8)*8)end
            for i,row in ipairs(picker.rows) do
                local c=picker.choices[choice+i-1]
                if c then row:SetText(safeName(c.name).." (slot "..tostring(c.slot)..")")
                    row:SetScript("OnClick",function()local ok,e=Nexus.OrbRuntime.SelectWishlist(c);if ok then picker:Hide()end;notify(ok,e)end);row:Show()
                else row:Hide()end
            end
        end
        picker.refresh();picker:Show()
    end)
    button(frame,420,-48,170,"Open Wishlist editor",function()Nexus.WishlistEditor.Show()end)
    button(frame,602,-48,92,"Recheck",function()notify(Nexus.OrbRuntime.Recheck())end)
    button(frame,702,-48,92,"Help",function()Nexus.Help.Show("orbs")end)
    frame.plan=text(frame,20,-86,775,44)
    text(frame,20,-130,365,22,"Desired targets (exact quality and copies)")
    text(frame,426,-130,375,22,"Replaceable sources - review each page")
    for i=1,PAGE do
        local y=-153-(i-1)*43
        local t=CreateFrame("Frame",nil,frame);t:SetSize(390,40);t:SetPoint("TOPLEFT",16,y);t:SetFrameLevel(122)
        t.label=text(t,4,-2,300,37)
        t.up=button(t,307,-4,32,"Up",function()notify(Nexus.OrbRuntime.MoveTarget(t.index,-1))end)
        t.down=button(t,342,-4,44,"Down",function()notify(Nexus.OrbRuntime.MoveTarget(t.index,1))end)
        targetRows[i]=t
        local r=CreateFrame("Frame",nil,frame);r:SetSize(380,40);r:SetPoint("TOPLEFT",423,y);r:SetFrameLevel(122)
        r.label=text(r,3,-2,220,36);r.count=text(r,253,-4,115,18)
        r.minus=button(r,225,-16,30,"-",function()
            local st=Nexus.OrbRuntime.Status();if r.key then notify(Nexus.OrbRuntime.SetSource(r.key,math.max(0,(st.config.sources[r.key] or 0)-1))) end
        end)
        r.plus=button(r,333,-16,30,"+",function()
            local st=Nexus.OrbRuntime.Status();if r.key then notify(Nexus.OrbRuntime.SetSource(r.key,math.min(r.max,(st.config.sources[r.key] or 0)+1))) end
        end)
        r.exclude=button(r,270,-18,58,"Exclude",function()if r.key then notify(Nexus.OrbRuntime.Exclude(r.key,true))end end)
        rows[i]=r
    end
    frame.targetPage=text(frame,20,-413,370,30);frame.sourcePage=text(frame,425,-413,375,30)
    button(frame,20,-445,75,"Previous",function()targetPage=math.max(1,targetPage-1);UI.Refresh()end)
    button(frame,103,-445,62,"Next",function()targetPage=targetPage+1;UI.Refresh()end)
    button(frame,177,-445,220,"Clear my source exclusions",function()notify(Nexus.OrbRuntime.ClearExclusions())end)
    button(frame,425,-445,75,"Previous",function()sourcePage=math.max(1,sourcePage-1);UI.Refresh()end)
    button(frame,508,-445,62,"Next",function()sourcePage=sourcePage+1;UI.Refresh()end)
    local suggest=button(frame,588,-445,205,"Suggest safe source pool",function()notify(Nexus.OrbRuntime.SuggestSources())end)
    frame.recycle=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate");frame.recycle:SetSize(25,25);frame.recycle:SetPoint("TOPLEFT",20,-477)
    frame.recycle:SetScript("OnClick",function(self)notify(Nexus.OrbRuntime.SetRecycle(self:GetChecked()==true))end)
    text(frame,48,-480,460,31,"Allow safe unwanted offers to be selected and recycled (explicit approval)")
    text(frame,527,-478,175,24,"Maximum Orbs this run:")
    frame.limit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate");frame.limit:SetSize(62,23);frame.limit:SetPoint("TOPLEFT",723,-474);frame.limit:SetAutoFocus(false)
    frame.limit:SetNumeric(true);frame.limit:SetMaxLetters(5)
    frame.limit:SetScript("OnEnterPressed",function(self)notify(Nexus.OrbRuntime.SetLimit(tonumber(self:GetText())));self:ClearFocus()end)
    frame.limit:SetScript("OnEscapePressed",function(self)self:ClearFocus();UI.Refresh()end)
    frame.start=button(frame,20,-512,126,"Review & start",function()
        local ok,e=Nexus.OrbRuntime.SetLimit(tonumber(frame.limit:GetText()));if not ok then notify(false,e);return end;openConfirm("auto")
    end)
    frame.single=button(frame,154,-512,140,"Review single Orb",function()openConfirm("single")end)
    frame.pause=button(frame,310,-512,80,"Pause",function()notify(Nexus.OrbRuntime.Pause())end)
    frame.resume=button(frame,399,-512,85,"Resume",function()notify(Nexus.OrbRuntime.Resume())end)
    frame.stop=button(frame,493,-512,80,"Stop",function()notify(Nexus.OrbRuntime.Stop())end)
    frame.increase=button(frame,587,-512,206,"Review increased run limit",function()
        local a,e=Nexus.OrbRuntime.PrepareLimitIncrease(tonumber(frame.limit:GetText()));if not a then notify(false,e);return end
        StaticPopupDialogs.NEXUS_ORB_INCREASE={text="Increase this run's Orb limit from "..a.old.." to "..a.limit.."? Usage and unresolved exposure will not reset.",button1="Confirm",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
            OnAccept=function()notify(Nexus.OrbRuntime.ConfirmLimit(a.token))end}
        StaticPopup_Show("NEXUS_ORB_INCREASE")
    end)
    frame.status=text(frame,20,-548,775,92);frame.notice=text(frame,20,-641,775,22)
    frame.closeNotice=text(frame,20,-675,775,26,"Closing the window does not stop an approved run. Use Pause or Stop.")
    frame.mutations={frame.start,frame.single,frame.pause,frame.resume,frame.stop,frame.increase,suggest,frame.choose,frame.assigned,frame.recycle}
    frame.configure={frame.start,frame.single,suggest,frame.choose,frame.recycle,frame.assigned}
    frame:SetScript("OnShow",function()UI.Refresh()end)
    local elapsed=0;frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;UI.Refresh()end end)
    frame:SetScript("OnHide",function()if confirmation then confirmation:Hide() end;if frame.selector then frame.selector:Hide()end end)
end
function UI.Show() ensure();frame:Show();UI.Refresh();return frame end
function UI.Hide() if frame then frame:Hide() end end
