-- ExplorerMap Addon for Vanilla WoW 1.12
local ExplorerMap = {}
ExplorerMap.db = {}
ExplorerMap.mapIcons = {}
local lastSavedNPC = {}
local questLogSnapshot = {}

DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap: Loading addon...")

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
    local npcKey = npcName.."_"..math.floor(x*10000).."_"..math.floor(y*10000)
    if not ExplorerMap.db[zone][npcKey] then
        local continent = GetCurrentMapContinent()
        local zoneID = GetCurrentMapZone()
        ExplorerMap.db[zone][npcKey] = {
            name = npcName,
            x = x,
            y = y,
            subzone = subzone,
            continent = continent,
            zoneID = zoneID,
            questInfo = { availableQuests = {}, activeQuests = {}, completedQuests = {} },
            discovered = time()
        }
    end
    return ExplorerMap.db[zone][npcKey]
end

---------------------------------------------------
-- Quest Handling (Updated)
---------------------------------------------------
local function AddAvailableQuest(npc, questName)
    if not IsQuestInList(npc.questInfo.availableQuests, questName) and
       not IsQuestInList(npc.questInfo.activeQuests, questName) and
       not IsQuestInList(npc.questInfo.completedQuests or {}, questName) then
        table.insert(npc.questInfo.availableQuests, questName)
    end
end

local function CompleteQuest(npc, questName)
    -- Remove from active and available lists
    RemoveQuestFromList(npc.questInfo.activeQuests, questName)
    RemoveQuestFromList(npc.questInfo.availableQuests, questName)
    
    -- Add to completed list
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
        -- Only add back to available if it's not completed
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
    icon:SetWidth(12)
    icon:SetHeight(16)
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
    local zone = GetRealZoneText()
    local continent = GetCurrentMapContinent()
    local zoneID = GetCurrentMapZone()
    
    -- Only show icons when zoomed into a specific zone, not continent view
    if not zoneID or zoneID == 0 then
        -- We're at continent level, hide all icons
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

    if not ExplorerMap.db[zone] then return end
    for _, npc in pairs(ExplorerMap.db[zone]) do
        local icon = CreateMapIcon(npc)
        if icon then table.insert(ExplorerMap.mapIcons, icon) end
    end
end

local function CheckWorldMap()
    if WorldMapFrame:IsVisible() then
        UpdateMapIcons()
    end
end

---------------------------------------------------
-- Quest Log Scanning 
---------------------------------------------------
local function ScanQuestLog()
    local currentQuests = {}
    local numQuests = GetNumQuestLogEntries()
    for i=1,numQuests do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
            currentQuests[title] = true
        end
    end

    -- Handle abandoned quests
    for questName,_ in pairs(questLogSnapshot) do
        if not currentQuests[questName] then
            for zone,npcs in pairs(ExplorerMap.db) do
                for _, npc in pairs(npcs) do
                    AbandonQuest(npc, questName)
                end
            end
        end
    end

    -- Handle newly accepted quests (only for NPCs that have this quest available)
    for questName,_ in pairs(currentQuests) do
        if not questLogSnapshot[questName] then
            -- This is a newly accepted quest
            for zone,npcs in pairs(ExplorerMap.db) do
                for _, npc in pairs(npcs) do
                    -- Only accept if this NPC actually had this quest available
                    if IsQuestInList(npc.questInfo.availableQuests, questName) then
                        AcceptQuest(npc, questName)
                    end
                end
            end
        end
    end

    questLogSnapshot = currentQuests
end

---------------------------------------------------
-- Event Handling (Vanilla Style)
---------------------------------------------------
local function CanSaveNPC(npcName, t)
    return not lastSavedNPC[npcName] or (t - lastSavedNPC[npcName] > 2)
end

local function OnEvent()
    DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Event fired: "..event)
    
    if event=="PLAYER_LOGIN" then
        local key = UnitName("player").."-"..GetRealmName()
        if not ExplorerMapDB then ExplorerMapDB = {} end
        if not ExplorerMapDB[key] then ExplorerMapDB[key] = {} end
        ExplorerMap.db = ExplorerMapDB[key]
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap loaded for "..UnitName("player").."!")
        
    elseif event=="QUEST_DETAIL" then
        local npcName = UnitName("target")
        local questTitle = GetTitleText()
        local x,y = GetPlayerMapPosition("player")
        local zone = GetRealZoneText()
        local subzone = GetSubZoneText()
        local t = time()
        
        if npcName and x>0 and y>0 and questTitle and CanSaveNPC(npcName,t) then
            local npc = CreateNPCIfNeeded(npcName,x,y,zone,subzone)
            AddAvailableQuest(npc, questTitle)
            lastSavedNPC[npcName] = t
        end
        
    elseif event=="QUEST_GREETING" then
        local npcName = UnitName("target")
        local x,y = GetPlayerMapPosition("player")
        local zone = GetRealZoneText()
        local subzone = GetSubZoneText()
        local t = time()
        if npcName and x>0 and y>0 and CanSaveNPC(npcName,t) then
            CreateNPCIfNeeded(npcName,x,y,zone,subzone)
            lastSavedNPC[npcName] = t
        end
        
    elseif event=="QUEST_COMPLETE" then
        local questTitle = GetTitleText()
        if questTitle then
            DEFAULT_CHAT_FRAME:AddMessage("DEBUG: Quest completed: "..questTitle)
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
frame:RegisterEvent("QUEST_COMPLETE")  -- Add this event
frame:SetScript("OnEvent", OnEvent)

---------------------------------------------------
-- OnUpdate Timer (Vanilla Style)
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
    if msg=="debug" then
        for zone,npcs in pairs(ExplorerMap.db) do
            DEFAULT_CHAT_FRAME:AddMessage("Zone: "..zone)
            for _,npc in pairs(npcs) do
                local av=TableLength(npc.questInfo.availableQuests)
                local ac=TableLength(npc.questInfo.activeQuests)
                DEFAULT_CHAT_FRAME:AddMessage(" - "..npc.name.." ["..av.." av, "..ac.." ac]")
            end
        end
    elseif msg=="refresh" then
        UpdateMapIcons()
    elseif msg=="clear" then
        local key = UnitName("player").."-"..GetRealmName()
        if ExplorerMapDB then ExplorerMapDB[key] = {} end
        ExplorerMap.db = {}
        DEFAULT_CHAT_FRAME:AddMessage("Cleared all NPCs for "..UnitName("player"))
    else
        DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer debug - Show NPCs")  
        DEFAULT_CHAT_FRAME:AddMessage("/explorer refresh - Refresh icons")
        DEFAULT_CHAT_FRAME:AddMessage("/explorer clear - Clear all data")
    end
end

DEFAULT_CHAT_FRAME:AddMessage("ExplorerMap: Addon loaded!")