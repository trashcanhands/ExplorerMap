local ExplorerMap = {}
ExplorerMap.db = {}
ExplorerMap.mapIcons = {}
local mapIsOpen = false
local lastMapKey = ""

local function GetCurrentMapInfo()
    local zone = GetRealZoneText()
    local continent = GetCurrentMapContinent()
    local zoneID = GetCurrentMapZone()
    local mapKey = (continent or "nil") .. "_" .. (zoneID or "nil")
    return zone, continent, zoneID, mapKey
end

local function IsQuestActive(questName)
    if not questName then return false end
    
    local numQuests = GetNumQuestLogEntries()
    for i = 1, numQuests do
        local title, level, tag, isHeader, isCollapsed = GetQuestLogTitle(i)
        if title and title == questName and not isHeader then
            return true
        end
    end
    return false
end

local function UpdateNPCQuestStatus(npc)
    if not npc.questInfo or not npc.questInfo.availableQuests then
        return false
    end
    
    local changed = false
    local questsToMove = {}
    
    for i = table.getn(npc.questInfo.availableQuests), 1, -1 do
        local questName = npc.questInfo.availableQuests[i]
        if IsQuestActive(questName) then
            local alreadyActive = false
            if npc.questInfo.activeQuests then
                for j = 1, table.getn(npc.questInfo.activeQuests) do
                    if npc.questInfo.activeQuests[j] == questName then
                        alreadyActive = true
                        break
                    end
                end
            end
            
            if not alreadyActive then
                table.insert(questsToMove, questName)
                table.remove(npc.questInfo.availableQuests, i)
                changed = true
            else
                table.remove(npc.questInfo.availableQuests, i)
                changed = true
            end
        end
    end
    
    if table.getn(questsToMove) > 0 then
        if not npc.questInfo.activeQuests then
            npc.questInfo.activeQuests = {}
        end
        for i = 1, table.getn(questsToMove) do
            table.insert(npc.questInfo.activeQuests, questsToMove[i])
        end
    end
    
    return changed
end

local function CheckAllNPCQuestStatus()
    local anyChanges = false
    
    for zoneName, npcs in pairs(ExplorerMap.db) do
        for key, npc in pairs(npcs) do
            if UpdateNPCQuestStatus(npc) then
                anyChanges = true
            end
        end
    end
    
    if anyChanges then
        lastMapKey = ""
    end
end

local function CheckForAbandonedQuests()
    for zoneName, npcs in pairs(ExplorerMap.db) do
        for key, npc in pairs(npcs) do
            if npc.questInfo and npc.questInfo.activeQuests then
                local questsToRestore = {}
                
                for i = table.getn(npc.questInfo.activeQuests), 1, -1 do
                    local questName = npc.questInfo.activeQuests[i]
                    
                    if not IsQuestActive(questName) then
                        table.remove(npc.questInfo.activeQuests, i)
                        
                        local wasCompleted = false
                        for checkZone, checkNpcs in pairs(ExplorerMap.db) do
                            for checkKey, checkNpc in pairs(checkNpcs) do
                                if checkNpc.questInfo and checkNpc.questInfo.completedQuests then
                                    for j = 1, table.getn(checkNpc.questInfo.completedQuests) do
                                        if checkNpc.questInfo.completedQuests[j] == questName then
                                            wasCompleted = true
                                            break
                                        end
                                    end
                                end
                                if wasCompleted then break end
                            end
                            if wasCompleted then break end
                        end
                        
                        if not wasCompleted then
                            table.insert(questsToRestore, questName)
                        end
                    end
                end
                
                for i = 1, table.getn(questsToRestore) do
                    if not npc.questInfo.availableQuests then
                        npc.questInfo.availableQuests = {}
                    end
                    table.insert(npc.questInfo.availableQuests, questsToRestore[i])
                end
                
                if table.getn(questsToRestore) > 0 then
                    lastMapKey = ""
                end
            end
        end
    end
end

local function OnQuestTurnInDetected(questName, npcName, x, y, zone, subzone)
    if not npcName then return end
    
    local currentTime = time()
    local currentZone, continent, zoneID, mapKey = GetCurrentMapInfo()
    
    if not ExplorerMap.db[zone] then
        ExplorerMap.db[zone] = {}
    end
    
    local npcKey = npcName .. "_" .. math.floor(x*10000) .. "_" .. math.floor(y*10000)
    
    if not ExplorerMap.db[zone][npcKey] then
        ExplorerMap.db[zone][npcKey] = {
            name = npcName,
            x = x,
            y = y,
            subzone = subzone,
            continent = continent,
            zoneID = zoneID,
            mapKey = mapKey,
            questInfo = {
                availableQuests = {},
                activeQuests = {},
                completedQuests = {},
                turnInQuests = {}
            },
            discovered = currentTime
        }
    end
    
    local npc = ExplorerMap.db[zone][npcKey]
    
    if not npc.questInfo.turnInQuests then
        npc.questInfo.turnInQuests = {}
    end
    
    local alreadyThere = false
    for i = 1, table.getn(npc.questInfo.turnInQuests) do
        if npc.questInfo.turnInQuests[i] == questName then
            alreadyThere = true
            break
        end
    end
    
    if not alreadyThere then
        table.insert(npc.questInfo.turnInQuests, questName)
        DEFAULT_CHAT_FRAME:AddMessage("Turn-in point discovered: " .. npcName .. " for " .. questName)
        lastMapKey = ""
    end
end

local function OnQuestCompleted(questName)
    local npcName = UnitName("target")
    local x, y = GetPlayerMapPosition("player")
    local zone = GetZoneText()
    local subzone = GetSubZoneText()
    
    if npcName and x > 0 and y > 0 then
        OnQuestTurnInDetected(questName, npcName, x, y, zone, subzone)
    end
    
    for zoneName, npcs in pairs(ExplorerMap.db) do
        for key, npc in pairs(npcs) do
            local hadThisQuest = false
            
            if npc.questInfo and npc.questInfo.activeQuests then
                for i = table.getn(npc.questInfo.activeQuests), 1, -1 do
                    if npc.questInfo.activeQuests[i] == questName then
                        table.remove(npc.questInfo.activeQuests, i)
                        hadThisQuest = true
                        break
                    end
                end
			end
                -- ✅ NEW: remove it from turnInQuests too
                if npc.questInfo.turnInQuests then
                    for i = table.getn(npc.questInfo.turnInQuests), 1, -1 do
                        if npc.questInfo.turnInQuests[i] == questName then
                            table.remove(npc.questInfo.turnInQuests, i)
                        end
                    end
                end
            if hadThisQuest then
                if not npc.questInfo.completedQuests then
                    npc.questInfo.completedQuests = {}
                end
                table.insert(npc.questInfo.completedQuests, questName)
                lastMapKey = ""
            end
        end
    end
end

local function CategorizeQuests(questInfo)
    if not questInfo then
        return nil
    end
    
    return {
        availableQuests = questInfo.availableQuests or {},
        activeQuests = questInfo.activeQuests or {},
        completedQuests = questInfo.completedQuests or {},
        turnInQuests = questInfo.turnInQuests or {}
    }
end

local function GetNPCIconType(npcData)
    if not npcData.questInfo then
        return "hidden"
    end
    
    local categorized = CategorizeQuests(npcData.questInfo)
    if not categorized then
        return "hidden"
    end
    
    local hasAvailable = table.getn(categorized.availableQuests) > 0
    local hasActive = table.getn(categorized.activeQuests) > 0
    local hasTurnIn = table.getn(categorized.turnInQuests) > 0
    
    if hasAvailable then
        return "available"
    elseif hasActive or hasTurnIn then
        return "turnin"
    else
        return "hidden"
    end
end

local function GetIconDisplay(iconType)
    local displays = {
        available = {
            texture = "Interface\\GossipFrame\\AvailableQuestIcon",
            r = 1, g = 1, b = 0,
            size = {12, 16}
        },
        turnin = {
            texture = "Interface\\GossipFrame\\ActiveQuestIcon",
            r = 1, g = 1, b = 1,
            size = {12, 16}
        }
    }
    
    return displays[iconType]
end

local function CreateMapIcon(npcData, x, y)
    local iconName = "ExplorerMap_Icon_" .. math.random(1000,9999)
    local icon = CreateFrame("Button", iconName, WorldMapButton)
    
    local iconType = GetNPCIconType(npcData)
    local display = GetIconDisplay(iconType)
    
    if not display then
        return nil
    end
    
    icon:SetWidth(display.size[1])
    icon:SetHeight(display.size[2])
    
    icon:SetFrameStrata("TOOLTIP")
    icon:SetFrameLevel(100)
    
    local worldMapWidth = WorldMapButton:GetWidth()
    local worldMapHeight = WorldMapButton:GetHeight()
    local iconX = x * worldMapWidth
    local iconY = -y * worldMapHeight
    
    icon:SetPoint("CENTER", WorldMapButton, "TOPLEFT", iconX, iconY)
    icon:EnableMouse(true)
    
    local texture = icon:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(icon)
    texture:SetTexture(display.texture)
    texture:SetVertexColor(display.r, display.g, display.b, 1.0)
    
    icon.npcName = npcData.name
    icon.npcSubzone = npcData.subzone
    icon.npcDiscovered = npcData.discovered
    icon.questInfo = npcData.questInfo
    icon.iconType = iconType
    
icon:SetScript("OnEnter", function()
    GameTooltip:Hide()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:SetText(this.npcName, 1, 1, 0)
    
    if this.npcSubzone and this.npcSubzone ~= "" then
        GameTooltip:AddLine(this.npcSubzone, 0.8, 0.8, 0.8)
    end
    
    local categorized = CategorizeQuests(this.questInfo)
    if categorized then
        local hasAvailable = table.getn(categorized.availableQuests) > 0
        local hasActive = table.getn(categorized.activeQuests) > 0
        
local hasTurnIn = table.getn(categorized.turnInQuests) > 0
local description

if hasAvailable then
    description = "Has Available Quests"
    GameTooltip:AddLine(description, 0.7, 0.7, 1)
elseif hasTurnIn then
    description = "Quest Turn-In Point"
    GameTooltip:AddLine(description, 1, 1, 0)
else
    description = "Has Active Quests"
    GameTooltip:AddLine(description, 0.7, 0.7, 1)
end
        
        if table.getn(categorized.availableQuests) > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Available:", 1, 1, 0)
            for i = 1, table.getn(categorized.availableQuests) do
                GameTooltip:AddLine("- " .. categorized.availableQuests[i], 1, 1, 1)
            end
        end
        
        if table.getn(categorized.activeQuests) > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Active:", 0, 1, 0)
            for i = 1, table.getn(categorized.activeQuests) do
                local questName = categorized.activeQuests[i]
                local isTurnIn = false
                
                for j = 1, table.getn(categorized.turnInQuests) do
                    if categorized.turnInQuests[j] == questName then
                        isTurnIn = true
                        break
                    end
                end
                
                if isTurnIn then
                    GameTooltip:AddLine("- " .. questName, 1, 1, 0)
                else
                    GameTooltip:AddLine("- " .. questName, 0.7, 1, 0.7)
                end
            end
        end
        
        if table.getn(categorized.turnInQuests) > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Turn In:", 1, 0.6, 0)
            for i = 1, table.getn(categorized.turnInQuests) do
                GameTooltip:AddLine("- " .. categorized.turnInQuests[i], 1, 0.8, 0.4)
            end
        end
    end
    
    GameTooltip:Show()
end)
    
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    icon:SetScript("OnClick", function()
        DEFAULT_CHAT_FRAME:AddMessage("CLICKED: " .. this.npcName)
    end)
    
    icon:Show()
    return icon
end

local function GetQuestInfo(existingNPC)
    local questInfo = {
        availableQuests = {}
    }
    
    local function IsQuestCompleted(questName)
        if existingNPC and existingNPC.questInfo and existingNPC.questInfo.completedQuests then
            for i = 1, table.getn(existingNPC.questInfo.completedQuests) do
                if existingNPC.questInfo.completedQuests[i] == questName then
                    return true
                end
            end
        end
        return false
    end
    
    local questTitle = GetTitleText()
    if questTitle and questTitle ~= "" then
        if IsQuestActive(questTitle) or IsQuestCompleted(questTitle) then
            return nil
        else
            table.insert(questInfo.availableQuests, questTitle)
        end
        return questInfo
    end
    
    local numAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    if numAvailable > 0 then
        for i = 1, numAvailable do
            local questName = GetAvailableTitle and GetAvailableTitle(i)
            if questName and questName ~= "" then
                if not IsQuestActive(questName) and not IsQuestCompleted(questName) then
                    table.insert(questInfo.availableQuests, questName)
                end
            end
        end
    end
    
    return (table.getn(questInfo.availableQuests) > 0) and questInfo or nil
end

local function SaveNPCDiscovery(npcName, x, y, zone, subzone)
    local currentTime = time()
    local currentZone, continent, zoneID, mapKey = GetCurrentMapInfo()
    
    if not ExplorerMap.db[zone] then
        ExplorerMap.db[zone] = {}
    end
    
    local npcKey = npcName .. "_" .. math.floor(x*10000) .. "_" .. math.floor(y*10000)
    local questInfo = GetQuestInfo(ExplorerMap.db[zone][npcKey])
    
    if not questInfo then
        return false
    end
    
    if not ExplorerMap.db[zone][npcKey] then
        ExplorerMap.db[zone][npcKey] = {
            name = npcName,
            x = x,
            y = y,
            subzone = subzone,
            continent = continent,
            zoneID = zoneID,
            mapKey = mapKey,
            questInfo = questInfo,
            discovered = currentTime
        }
        
        local message = "Quest giver discovered: " .. npcName
        if questInfo.availableQuests and table.getn(questInfo.availableQuests) > 0 then
            message = message .. " (" .. table.getn(questInfo.availableQuests) .. " quest"
            if table.getn(questInfo.availableQuests) > 1 then
                message = message .. "s"
            end
            message = message .. ")"
        end
        DEFAULT_CHAT_FRAME:AddMessage(message)
        return true
    else
        local existing = ExplorerMap.db[zone][npcKey]
        UpdateNPCQuestStatus(existing)
        
        if questInfo.availableQuests then
            for i = 1, table.getn(questInfo.availableQuests) do
                local newQuest = questInfo.availableQuests[i]
                local alreadyKnown = false
                
                local allLists = {
                    existing.questInfo.availableQuests or {},
                    existing.questInfo.activeQuests or {},
                    existing.questInfo.completedQuests or {},
                    existing.questInfo.turnInQuests or {}
                }
                
                for _, list in ipairs(allLists) do
                    for j = 1, table.getn(list) do
                        if list[j] == newQuest then
                            alreadyKnown = true
                            break
                        end
                    end
                    if alreadyKnown then break end
                end
                
                if not alreadyKnown then
                    if not existing.questInfo.availableQuests then
                        existing.questInfo.availableQuests = {}
                    end
                    table.insert(existing.questInfo.availableQuests, newQuest)
                end
            end
        end
    end
    return false
end

local function UpdateMapIcons()
    local currentZone, currentContinent, currentZoneID, currentMapKey = GetCurrentMapInfo()
    
    if currentMapKey == lastMapKey then
        return
    end
    
    lastMapKey = currentMapKey
    
    for _, icon in ipairs(ExplorerMap.mapIcons) do
        icon:Hide()
    end
    ExplorerMap.mapIcons = {}
    
    for zoneName, npcs in pairs(ExplorerMap.db) do
        for key, npc in pairs(npcs) do
            local npcMapKey = npc.mapKey or ((npc.continent or "nil") .. "_" .. (npc.zoneID or "nil"))
            
            if npcMapKey == currentMapKey then
                local iconType = GetNPCIconType(npc)
                if iconType ~= "hidden" then
                    local icon = CreateMapIcon(npc, npc.x, npc.y)
                    if icon then
                        table.insert(ExplorerMap.mapIcons, icon)
                    end
                end
            end
        end
    end
end

local function CheckWorldMap()
    if WorldMapFrame:IsVisible() then
        UpdateMapIcons()
    else
        lastMapKey = ""
    end
end

SLASH_EXPLORER1 = "/explorer"
SLASH_EXPLORER2 = "/exp"
SlashCmdList["EXPLORER"] = function(msg)
    if msg == "debug" then
        for zone, npcs in pairs(ExplorerMap.db) do
            DEFAULT_CHAT_FRAME:AddMessage("Zone: " .. zone)
            for key, npc in pairs(npcs) do
                local questText = ""
                if npc.questInfo then
                    local available = npc.questInfo.availableQuests and table.getn(npc.questInfo.availableQuests) or 0
                    local active = npc.questInfo.activeQuests and table.getn(npc.questInfo.activeQuests) or 0
                    local completed = npc.questInfo.completedQuests and table.getn(npc.questInfo.completedQuests) or 0
                    local turnin = npc.questInfo.turnInQuests and table.getn(npc.questInfo.turnInQuests) or 0
                    questText = " [" .. available .. "av/" .. active .. "ac/" .. completed .. "co/" .. turnin .. "ti]"
                end
                DEFAULT_CHAT_FRAME:AddMessage("  - " .. npc.name .. questText)
            end
        end
    elseif msg == "refresh" then
        lastMapKey = ""
        UpdateMapIcons()
    elseif msg == "clear" then
        local playerName = UnitName("player")
        local realmName = GetRealmName()
        local characterKey = playerName .. "-" .. realmName
        
        if ExplorerMapDB then
            ExplorerMapDB[characterKey] = {}
        end
        ExplorerMap.db = {}
        DEFAULT_CHAT_FRAME:AddMessage("Cleared all NPCs for " .. playerName)
    else
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer debug - Show NPCs")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer refresh - Refresh icons")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer clear - Clear all data")
    end
end

local lastSavedNPC = {}
local function CanSaveNPC(npcName, currentTime)
    if lastSavedNPC[npcName] and (currentTime - lastSavedNPC[npcName]) < 2 then
        return false
    end
    return true
end

local function OnEvent()
    local currentEvent = event
    
    if currentEvent == "PLAYER_LOGIN" then
        local playerName = UnitName("player")
        local realmName = GetRealmName()
        local characterKey = playerName .. "-" .. realmName
        
        if not ExplorerMapDB then
            ExplorerMapDB = {}
        end
        
        if not ExplorerMapDB[characterKey] then
            ExplorerMapDB[characterKey] = {}
        end
        
        ExplorerMap.db = ExplorerMapDB[characterKey]
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap loaded for " .. playerName .. "!")
        
    elseif currentEvent == "QUEST_GREETING" or currentEvent == "QUEST_DETAIL" then
        local npcName = UnitName("target")
        local x, y = GetPlayerMapPosition("player")
        local zone = GetZoneText()
        local subzone = GetSubZoneText()
        local currentTime = time()
        
        if npcName and x > 0 and y > 0 and CanSaveNPC(npcName, currentTime) then
            if SaveNPCDiscovery(npcName, x, y, zone, subzone) then
                lastSavedNPC[npcName] = currentTime
            end
        end
        
    elseif currentEvent == "QUEST_TURNED_IN" then
        local questTitle = GetTitleText()
        if questTitle and questTitle ~= "" then
            OnQuestCompleted(questTitle)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:SetScript("OnEvent", OnEvent)

local checkFrame = CreateFrame("Frame")
checkFrame.timer = 0
checkFrame:SetScript("OnUpdate", function()
    checkFrame.timer = checkFrame.timer + arg1
    if checkFrame.timer > 1.0 then
        checkFrame.timer = 0
        CheckAllNPCQuestStatus()
        CheckForAbandonedQuests()
        CheckWorldMap()
    end
end)