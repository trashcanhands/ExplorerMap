-- ExplorerMap Addon for Vanilla WoW 1.12
local ExplorerMap = {}
ExplorerMap.db = {}
ExplorerMap.mapIcons = {}
local lastSavedNPC = {}
local questLogSnapshot = {}

---------------------------------------------------
-- Helpers
---------------------------------------------------
local function TableLength(t)
    if not t then return 0 end
    local count = 0
    for _,_ in pairs(t) do count = count + 1 end
    return count
end

local function IsQuestInList(list, questName)
    if not list then return false end
    for i=1,TableLength(list) do
        if list[i]==questName then return true end
    end
    return false
end

local function RemoveQuestFromList(list, questName)
    if not list then return end
    for i=TableLength(list),1,-1 do
        if list[i]==questName then table.remove(list,i) end
    end
end

---------------------------------------------------
-- NPC Discovery
---------------------------------------------------
local function CreateNPCIfNeeded(npcName, x, y, zone, subzone)
    if not ExplorerMap.db[zone] then ExplorerMap.db[zone] = {} end
    
    if not subzone or subzone == "" then
        subzone = "Unknown Area"
    end
    
    local roundedX = math.floor(x*100)
    local roundedY = math.floor(y*100)
    local npcKey = npcName.."_"..roundedX.."_"..roundedY
    
    if not ExplorerMap.db[zone][npcKey] then
        for existingKey, existingNPC in pairs(ExplorerMap.db[zone]) do
            if existingNPC.name == npcName then
                local existingRoundedX = math.floor(existingNPC.x*100)
                local existingRoundedY = math.floor(existingNPC.y*100)
                local distance = math.abs(roundedX - existingRoundedX) + math.abs(roundedY - existingRoundedY)
                if distance <= 2 then
                    return existingNPC
                end
            end
        end
        
        local continent = GetCurrentMapContinent()
        local zoneID = GetCurrentMapZone()
        ExplorerMap.db[zone][npcKey] = {
            name = npcName,
            x = x,
            y = y,
            subzone = subzone,
            continent = continent,
            zoneID = zoneID,
            questInfo = { availableQuests = {}, activeQuests = {}, completedQuests = {}, questLevels = {} },
            discovered = time()
        }
    end
    return ExplorerMap.db[zone][npcKey]
end

---------------------------------------------------
-- Quest Handling
---------------------------------------------------
local function AddAvailableQuest(npc, questName, questLevel)
    if not IsQuestInList(npc.questInfo.availableQuests, questName) and
       not IsQuestInList(npc.questInfo.activeQuests, questName) and
       not IsQuestInList(npc.questInfo.completedQuests or {}, questName) then
        table.insert(npc.questInfo.availableQuests, questName)
        -- Store the quest level
        if not npc.questInfo.questLevels then npc.questInfo.questLevels = {} end
        if questLevel then
            npc.questInfo.questLevels[questName] = questLevel
        end
    end
end

local function CompleteQuest(npc, questName)
    RemoveQuestFromList(npc.questInfo.activeQuests, questName)
    RemoveQuestFromList(npc.questInfo.availableQuests, questName)
    
    if not npc.questInfo.completedQuests then
        npc.questInfo.completedQuests = {}
    end
    if not IsQuestInList(npc.questInfo.completedQuests, questName) then
        table.insert(npc.questInfo.completedQuests, questName)
    end
end

local function AcceptQuest(npc, questName)
    if IsQuestInList(npc.questInfo.availableQuests, questName) then
        RemoveQuestFromList(npc.questInfo.availableQuests, questName)
        if not IsQuestInList(npc.questInfo.activeQuests, questName) then
            table.insert(npc.questInfo.activeQuests, questName)
        end
    end
end

local function AbandonQuest(npc, questName)
    if IsQuestInList(npc.questInfo.activeQuests, questName) then
        RemoveQuestFromList(npc.questInfo.activeQuests, questName)
        if not IsQuestInList(npc.questInfo.completedQuests or {}, questName) then
            AddAvailableQuest(npc, questName)
        end
    end
end

---------------------------------------------------
-- Map Icons
---------------------------------------------------
local function GetNPCIconType(npc)
    local hasAvailable = TableLength(npc.questInfo.availableQuests) > 0
    local hasActive = TableLength(npc.questInfo.activeQuests) > 0
    if hasAvailable then
        return "available"
    elseif hasActive then
        return "active"
    else
        return "hidden"
    end
end

local function CreateMapIcon(npc)
    local iconType = GetNPCIconType(npc)
    if iconType=="hidden" then return nil end

    local iconName = "ExplorerMap_Icon_"..math.random(1000,9999)
    local icon = CreateFrame("Button", iconName, WorldMapButton)
    icon:SetWidth(18)
    icon:SetHeight(22)
    icon:SetFrameStrata("TOOLTIP")
    icon:SetFrameLevel(100)

    local worldMapWidth = WorldMapButton:GetWidth()
    local worldMapHeight = WorldMapButton:GetHeight()
    icon:SetPoint("CENTER", WorldMapButton, "TOPLEFT", npc.x*worldMapWidth, -npc.y*worldMapHeight)

    local texture = icon:CreateTexture(nil,"OVERLAY")
    texture:SetAllPoints(icon)
    texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    
    if iconType == "available" then
        texture:SetVertexColor(1, 1, 0, 1.0)
    else
        texture:SetVertexColor(1, 0.5, 0, 1.0)
    end

    icon.npcData = npc

    icon:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(this.npcData.name, 0, 1, 0)
        if this.npcData.subzone and this.npcData.subzone~="" then
            GameTooltip:AddLine(this.npcData.subzone, 0.8, 0.8, 0.8)
        end
        local available = this.npcData.questInfo.availableQuests
        local active = this.npcData.questInfo.activeQuests
        if TableLength(available)>0 then
            GameTooltip:AddLine("Available Quests:", 1, 1, 0)
            for i=1,TableLength(available) do
                GameTooltip:AddLine("  "..available[i], 1, 1, 0)
            end
        end
        if TableLength(active)>0 then
            GameTooltip:AddLine("Active Quests:", 0.5, 1, 0.5)
            for i=1,TableLength(active) do
                GameTooltip:AddLine("  "..active[i], 0.7, 1, 0.7)
            end
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:Show()
    return icon
end

local function UpdateMapIcons()
    local currentContinent = GetCurrentMapContinent()
    local currentZoneID = GetCurrentMapZone()
    
    if not currentZoneID or currentZoneID == 0 then
        for _, icon in ipairs(ExplorerMap.mapIcons) do
            icon:Hide()
        end
        ExplorerMap.mapIcons = {}
        return
    end
    
    for _, icon in ipairs(ExplorerMap.mapIcons) do
        icon:Hide()
    end
    ExplorerMap.mapIcons = {}

    for zoneName, npcs in pairs(ExplorerMap.db) do
        for _, npc in pairs(npcs) do
            if npc.continent == currentContinent and npc.zoneID == currentZoneID then
                local icon = CreateMapIcon(npc)
                if icon then table.insert(ExplorerMap.mapIcons, icon) end
            end
        end
    end
end

local function CheckWorldMap()
    if WorldMapFrame:IsVisible() then
        UpdateMapIcons()
    end
end

---------------------------------------------------
-- GUI Creation
---------------------------------------------------
local ExplorerMapGUI = {}
ExplorerMapGUI.frame = nil
ExplorerMapGUI.isVisible = false
ExplorerMapGUI.collapsedZones = {}
ExplorerMapGUI.collapsedNPCs = {}
ExplorerMapGUI.collapsedSubzones = {}
ExplorerMapGUI.collapsedQuestSections = {}
ExplorerMapGUI.uiElements = {}

local function SaveGUIState()
    local key = UnitName("player").."-"..GetRealmName()
    if ExplorerMapDB and ExplorerMapDB[key] then
        if not ExplorerMapDB[key].guiState then
            ExplorerMapDB[key].guiState = {}
        end
        ExplorerMapDB[key].guiState.collapsedZones = ExplorerMapGUI.collapsedZones
        ExplorerMapDB[key].guiState.collapsedSubzones = ExplorerMapGUI.collapsedSubzones
        ExplorerMapDB[key].guiState.collapsedNPCs = ExplorerMapGUI.collapsedNPCs
        ExplorerMapDB[key].guiState.collapsedQuestSections = ExplorerMapGUI.collapsedQuestSections
    end
end

local function CreateGUI()
    if ExplorerMapGUI.frame then return end
    
    local frame = CreateFrame("Frame", "ExplorerMapGUIFrame", UIParent)
    frame:SetWidth(450)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	
	table.insert(UISpecialFrames, "ExplorerMapGUIFrame") --close on esc
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    title:SetText("Explorer's Map - Quest Givers")
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() ToggleGUI() end)
    
    local scrollFrame = CreateFrame("ScrollFrame", "ExplorerMapScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 15)
    
    local content = CreateFrame("Frame", "ExplorerMapContent", scrollFrame)
    content:SetWidth(400)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    
    ExplorerMapGUI.frame = frame
    ExplorerMapGUI.content = content
    ExplorerMapGUI.scrollFrame = scrollFrame
    
    frame:Hide()
end

local function ClearGUIContent()
    for _, element in ipairs(ExplorerMapGUI.uiElements) do
        if element.Hide then
            element:Hide()
        end
    end
    ExplorerMapGUI.uiElements = {}
end

local function AddUIElement(element)
    table.insert(ExplorerMapGUI.uiElements, element)
    return element
end

local function CreateClickableText(parent, text, x, y, color, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(350)
    button:SetHeight(16)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    
    local fontString = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint("LEFT", button, "LEFT", 0, 0)
    fontString:SetText(text)
    fontString:SetTextColor(color.r, color.g, color.b)
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    button:SetScript("OnEnter", function()
        fontString:SetTextColor(1, 1, 1)
    end)
    button:SetScript("OnLeave", function()
        fontString:SetTextColor(color.r, color.g, color.b)
    end)
    
    AddUIElement(button)
    return button
end

local function CreateStaticText(parent, text, x, y, color)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fontString:SetText(text)
    fontString:SetTextColor(color.r, color.g, color.b)
    AddUIElement(fontString)
    return fontString
end

local function UpdateGUIContent()
    if not ExplorerMapGUI.content then return end
    
    ClearGUIContent()
    
    local yPos = -10
    local lineHeight = 18
    local colors = {
        zone = {r=0.7, g=0.7, b=0.7},
        subzone = {r=0.6, g=0.8, b=0.6},
        npc = {r=0, g=1, b=0},
        questSection = {r=0.8, g=0.8, b=0.8},
        available = {r=1, g=1, b=0},
        active = {r=0.7, g=1, b=0.7}
    }
    
    local sortedZones = {}
    for zoneName, npcs in pairs(ExplorerMap.db) do
        if zoneName and zoneName ~= "" then
            local zoneHasQuests = false
            for _, npc in pairs(npcs) do
                if TableLength(npc.questInfo.availableQuests) > 0 or TableLength(npc.questInfo.activeQuests) > 0 then
                    zoneHasQuests = true
                    break
                end
            end
            if zoneHasQuests then
                table.insert(sortedZones, zoneName)
            end
        end
    end
    table.sort(sortedZones)
    
    for _, zoneName in ipairs(sortedZones) do
        local npcs = ExplorerMap.db[zoneName]
        local subzoneGroups = {}
        
        for _, npc in pairs(npcs) do
            if TableLength(npc.questInfo.availableQuests) > 0 or TableLength(npc.questInfo.activeQuests) > 0 then
                local subzoneName = npc.subzone
                if not subzoneName or subzoneName == "" then
                    subzoneName = "Undiscovered Area"
                end
                if not subzoneGroups[subzoneName] then
                    subzoneGroups[subzoneName] = {}
                end
                table.insert(subzoneGroups[subzoneName], npc)
            end
        end
        
        local isZoneCollapsed = ExplorerMapGUI.collapsedZones[zoneName]
        local zoneSymbol = isZoneCollapsed and "[+]" or "[-]"
        
        local zoneButton = CreateClickableText(
            ExplorerMapGUI.content,
            zoneSymbol .. " " .. zoneName,
            10, yPos,
            colors.zone,
            nil
        )
        
        zoneButton.zoneName = zoneName
        zoneButton:SetScript("OnClick", function()
            local zn = this.zoneName
            ExplorerMapGUI.collapsedZones[zn] = not ExplorerMapGUI.collapsedZones[zn]
			SaveGUIState()
            UpdateGUIContent()
        end)
        
        yPos = yPos - lineHeight - 3
        
        if not isZoneCollapsed then
            local sortedSubzones = {}
            for subzoneName, _ in pairs(subzoneGroups) do
                table.insert(sortedSubzones, subzoneName)
            end
            table.sort(sortedSubzones)
            
            for _, subzoneName in ipairs(sortedSubzones) do
                local subzoneNPCs = subzoneGroups[subzoneName]
                local subzoneKey = zoneName .. "_" .. subzoneName
                local isSubzoneCollapsed = ExplorerMapGUI.collapsedSubzones[subzoneKey]
                local subzoneSymbol = isSubzoneCollapsed and "[+]" or "[-]"
                
                local subzoneButton = CreateClickableText(
                    ExplorerMapGUI.content,
                    "  " .. subzoneSymbol .. " " .. subzoneName,
                    20, yPos,
                    colors.subzone,
                    nil
                )
                
                subzoneButton.subzoneKey = subzoneKey
                subzoneButton:SetScript("OnClick", function()
                    local sk = this.subzoneKey
                    ExplorerMapGUI.collapsedSubzones[sk] = not ExplorerMapGUI.collapsedSubzones[sk]
					SaveGUIState()
                    UpdateGUIContent()
                end)
                
                yPos = yPos - lineHeight
                
                if not isSubzoneCollapsed then
                    table.sort(subzoneNPCs, function(a, b) return a.name < b.name end)
                    
                    for _, npc in ipairs(subzoneNPCs) do
                        local npcKey = zoneName .. "_" .. subzoneName .. "_" .. npc.name
                        local isNPCCollapsed = ExplorerMapGUI.collapsedNPCs[npcKey]
                        local npcSymbol = isNPCCollapsed and "[+]" or "[-]"
                        
                        local npcButton = CreateClickableText(
                            ExplorerMapGUI.content,
                            "    " .. npcSymbol .. " " .. npc.name,
                            30, yPos,
                            colors.npc,
                            nil
                        )
                        
                        npcButton.npcKey = npcKey
                        npcButton:SetScript("OnClick", function()
                            local nk = this.npcKey
                            ExplorerMapGUI.collapsedNPCs[nk] = not ExplorerMapGUI.collapsedNPCs[nk]
							SaveGUIState()
                            UpdateGUIContent()
                        end)
                        
                        yPos = yPos - lineHeight
                        
                        if not isNPCCollapsed then
                            if TableLength(npc.questInfo.availableQuests) > 0 then
                                local availableKey = npcKey .. "_available"
                                local isAvailableCollapsed = ExplorerMapGUI.collapsedQuestSections[availableKey]
                                local availableSymbol = isAvailableCollapsed and "[+]" or "[-]"
                                
                                local availableButton = CreateClickableText(
                                    ExplorerMapGUI.content,
                                    "      " .. availableSymbol .. " Available Quests",
                                    40, yPos,
                                    colors.questSection,
                                    nil
                                )
                                
                                availableButton.questSectionKey = availableKey
                                availableButton:SetScript("OnClick", function()
                                    local qsk = this.questSectionKey
                                    ExplorerMapGUI.collapsedQuestSections[qsk] = not ExplorerMapGUI.collapsedQuestSections[qsk]
									SaveGUIState()
                                    UpdateGUIContent()
                                end)
                                
                                yPos = yPos - lineHeight
                                
                                if not isAvailableCollapsed then
                                    for i = 1, TableLength(npc.questInfo.availableQuests) do
                                        local questName = npc.questInfo.availableQuests[i]
                                        local level = npc.questInfo.questLevels and npc.questInfo.questLevels[questName]
                                        local displayText = "        - "
                                        if level then
                                            displayText = displayText .. "[" .. level .. "] "
                                        end
                                        displayText = displayText .. questName
                                        CreateStaticText(ExplorerMapGUI.content, displayText, 50, yPos, colors.available)
                                        yPos = yPos - lineHeight
                                    end
                                end
                            end
                            
                            if TableLength(npc.questInfo.activeQuests) > 0 then
                                local activeKey = npcKey .. "_active"
                                local isActiveCollapsed = ExplorerMapGUI.collapsedQuestSections[activeKey]
                                local activeSymbol = isActiveCollapsed and "[+]" or "[-]"
                                
                                local activeButton = CreateClickableText(
                                    ExplorerMapGUI.content,
                                    "      " .. activeSymbol .. " Active Quests",
                                    40, yPos,
                                    colors.questSection,
                                    nil
                                )
                                
                                activeButton.questSectionKey = activeKey
                                activeButton:SetScript("OnClick", function()
                                    local qsk = this.questSectionKey
                                    ExplorerMapGUI.collapsedQuestSections[qsk] = not ExplorerMapGUI.collapsedQuestSections[qsk]
									SaveGUIState()
                                    UpdateGUIContent()
                                end)
                                
                                yPos = yPos - lineHeight
                                
                                if not isActiveCollapsed then
                                    for i = 1, TableLength(npc.questInfo.activeQuests) do
                                        local questName = npc.questInfo.activeQuests[i]
                                        local level = npc.questInfo.questLevels and npc.questInfo.questLevels[questName]
                                        local displayText = "        - "
                                        if level then
                                            displayText = displayText .. "[" .. level .. "] "
                                        end
                                        displayText = displayText .. questName
                                        CreateStaticText(ExplorerMapGUI.content, displayText, 50, yPos, colors.active)
                                        yPos = yPos - lineHeight
                                    end
                                end
                            end
                        end
                        
                        yPos = yPos - 5
                    end
                end
                
                yPos = yPos - 8
            end
        end
        
        yPos = yPos - 8
    end
    
    local contentHeight = math.abs(yPos) + 30
    ExplorerMapGUI.content:SetHeight(contentHeight)
    ExplorerMapGUI.scrollFrame:UpdateScrollChildRect()
    
    local scrollBar = getglobal(ExplorerMapGUI.scrollFrame:GetName().."ScrollBar")
    if scrollBar and contentHeight <= ExplorerMapGUI.scrollFrame:GetHeight() then
        scrollBar:SetValue(0)
    end
end

function ToggleGUI()
    if not ExplorerMapGUI.frame then
        CreateGUI()
    end
    
    if ExplorerMapGUI.isVisible then
        ExplorerMapGUI.frame:Hide()
        ExplorerMapGUI.isVisible = false
    else
        UpdateGUIContent()
        ExplorerMapGUI.frame:Show()
        ExplorerMapGUI.isVisible = true
    end
end

---------------------------------------------------
-- Quest Log Scanning 
---------------------------------------------------
local function ScanQuestLog()
    local currentQuests = {}
    local questLevels = {}
    local numQuests = GetNumQuestLogEntries()
    for i=1,numQuests do
        local title, level, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
            currentQuests[title] = true
            questLevels[title] = level
        end
    end

    for zone, npcs in pairs(ExplorerMap.db) do
        for _, npc in pairs(npcs) do
            if not npc.questInfo then
                npc.questInfo = { availableQuests = {}, activeQuests = {}, completedQuests = {}, questLevels = {} }
            end
            if not npc.questInfo.questLevels then npc.questInfo.questLevels = {} end
            for questName, level in pairs(questLevels) do
                npc.questInfo.questLevels[questName] = level
            end
        end
    end

    for questName,_ in pairs(questLogSnapshot) do
        if not currentQuests[questName] then
            for zone,npcs in pairs(ExplorerMap.db) do
                for _, npc in pairs(npcs) do
                    if npc.questInfo then
                        AbandonQuest(npc, questName)
                    end
                end
            end
        end
    end

    for questName,_ in pairs(currentQuests) do
        if not questLogSnapshot[questName] then
            local questHandled = false
            for zone,npcs in pairs(ExplorerMap.db) do
                if questHandled then break end
                for _, npc in pairs(npcs) do
                    if npc.questInfo and IsQuestInList(npc.questInfo.availableQuests, questName) and not questHandled then
                        AcceptQuest(npc, questName)
                        questHandled = true
                        break
                    end
                end
            end
        end
    end

    questLogSnapshot = currentQuests
end

---------------------------------------------------
-- Data Management
---------------------------------------------------
local function CleanOldData()
    local cleaned = 0
    for zoneName, npcs in pairs(ExplorerMap.db) do
        for npcKey, npc in pairs(npcs) do
            if TableLength(npc.questInfo.availableQuests) == 0 and 
               TableLength(npc.questInfo.activeQuests) == 0 and
               TableLength(npc.questInfo.completedQuests) == 0 then
                ExplorerMap.db[zoneName][npcKey] = nil
                cleaned = cleaned + 1
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap: Cleaned " .. cleaned .. " empty NPCs")
end

---------------------------------------------------
-- Event Handling
---------------------------------------------------
local function CanSaveNPC(npcName, t)
    return not lastSavedNPC[npcName] or (t - lastSavedNPC[npcName] > 2)
end

local function OnEvent()
    if event=="PLAYER_LOGIN" then
    local key = UnitName("player").."-"..GetRealmName()
    if not ExplorerMapDB then ExplorerMapDB = {} end
    if not ExplorerMapDB[key] then ExplorerMapDB[key] = {} end
    ExplorerMap.db = ExplorerMapDB[key]
    
    if not ExplorerMapDB[key].guiState then
        ExplorerMapDB[key].guiState = {
            collapsedZones = {},
            collapsedSubzones = {},
            collapsedNPCs = {},
            collapsedQuestSections = {}
        }
    end
    
    ExplorerMapGUI.collapsedZones = ExplorerMapDB[key].guiState.collapsedZones
    ExplorerMapGUI.collapsedSubzones = ExplorerMapDB[key].guiState.collapsedSubzones
    ExplorerMapGUI.collapsedNPCs = ExplorerMapDB[key].guiState.collapsedNPCs
    ExplorerMapGUI.collapsedQuestSections = ExplorerMapDB[key].guiState.collapsedQuestSections
        
    elseif event=="QUEST_DETAIL" then
        SetMapToCurrentZone()
        local npcName = UnitName("target")
        local questTitle = GetTitleText()
        local x,y = GetPlayerMapPosition("player")
        local zone = GetRealZoneText()
        local subzone = GetSubZoneText()
        local t = time()
        
        --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: QUEST_DETAIL - NPC: "..(npcName or "nil")..", Quest: "..(questTitle or "nil")..", Coords: "..(x or 0)..",".. (y or 0)..", Zone: "..(zone or "nil"))
        
        if npcName and questTitle and zone then
            if x == 0 and y == 0 then
                --DEFAULT_CHAT_FRAME:AddMessage("WARNING: Got 0,0 coordinates, trying alternate method")
                SetMapToCurrentZone()
                x, y = GetPlayerMapPosition("player")
                --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Retry coords: "..x..","..y)
            end
            
            if x > 0 and y > 0 then
                local npc = CreateNPCIfNeeded(npcName,x,y,zone,subzone)
                
                local questLevel = nil
                local numQuests = GetNumQuestLogEntries()
                for i=1,numQuests do
                    local title, level, _, isHeader = GetQuestLogTitle(i)
                    if title and not isHeader and title == questTitle then
                        questLevel = level
                        break
                    end
                end
                
                AddAvailableQuest(npc, questTitle, questLevel)
                --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Added quest '"..questTitle.."' to NPC '"..npcName.."'")
                lastSavedNPC[npcName] = t
            else
                --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Failed validation - x:"..x.." y:"..y)
            end
        end
        
    elseif event=="QUEST_GREETING" then
        SetMapToCurrentZone()
        local npcName = UnitName("target")
        local x,y = GetPlayerMapPosition("player")
        local zone = GetRealZoneText()
        local subzone = GetSubZoneText()
        local t = time()
        
        --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: QUEST_GREETING - NPC: "..(npcName or "nil")..", Coords: "..(x or 0)..",".. (y or 0)..", Zone: "..(zone or "nil"))
        
        if npcName and zone and x > 0 and y > 0 and CanSaveNPC(npcName,t) then
            CreateNPCIfNeeded(npcName,x,y,zone,subzone)
            --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Created NPC '"..npcName.."' at greeting")
            lastSavedNPC[npcName] = t
        end
        
    elseif event=="QUEST_COMPLETE" then
        local questTitle = GetTitleText()
        if questTitle then
            --DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Completing quest '"..questTitle.."'")
            for zone,npcs in pairs(ExplorerMap.db) do
                for _, npc in pairs(npcs) do
                    CompleteQuest(npc, questTitle)
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_GREETING")  
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_COMPLETE")
frame:SetScript("OnEvent", OnEvent)

---------------------------------------------------
-- OnUpdate Timer
---------------------------------------------------
local checkFrame = CreateFrame("Frame")
checkFrame.timer = 0
checkFrame:SetScript("OnUpdate", function()
    checkFrame.timer = checkFrame.timer + arg1
    if checkFrame.timer > 1.0 then
        checkFrame.timer = 0
        ScanQuestLog()
        CheckWorldMap()
    end
end)

---------------------------------------------------
-- Slash Commands
---------------------------------------------------
SLASH_EXPLORER1 = "/explorer"
SLASH_EXPLORER2 = "/exp"
SlashCmdList["EXPLORER"] = function(msg)
    if msg=="gui" then
        ToggleGUI()
    elseif msg=="refresh" then
        UpdateMapIcons()
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap: Icons refreshed")
elseif msg=="clear" then
    local key = UnitName("player").."-"..GetRealmName()
    if ExplorerMapDB then 
        ExplorerMapDB[key] = {}
    end
    ExplorerMap.db = {}
    ExplorerMapGUI.collapsedZones = {}
    ExplorerMapGUI.collapsedSubzones = {}
    ExplorerMapGUI.collapsedNPCs = {}
    ExplorerMapGUI.collapsedQuestSections = {}
    DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap: All data cleared")
    elseif msg=="clean" then
        CleanOldData()
    else
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer gui - Open quest giver window")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer refresh - Refresh map icons")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer clear - Clear all data")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer clean - Remove NPCs with no quests")
    end
end


