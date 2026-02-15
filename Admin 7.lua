-- FINAL ADMIN GUI LOCAL SCRIPT (FIXED GEAR DETECT, PART GRAB KILL, LISTS, BB8 STABILITY)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService") -- Used for saving/loading
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local CollectionService = game:GetService("CollectionService")
-- State Variables
local SelectedPlayers = {}
local PlayerAutoTargetList = {} -- NEW: Players to ALWAYS target (Black/Grey)
local PlayerIgnoreList = {}   -- NEW: Players to NEVER target (Blue)
local Toggles = {}
local KillAuraEnabled = false
local KillAuraRadius = 20
local nan = 0 / 0
local AutoGearKill = true
local KorbloxToggle = false
local AntiBB8Toggle = false
local FFRemoveToggle = false 

-- Gear table
local gearTable = {
    DiamondBlade = {name="Diamond Blade Sword", id=173755801},
    SpaceSword = {name="SpaceSword", id=170903610},
    Balligator = {name="Balligator", id=292969458},
    RocketJumper = {name="RocketJumper", id=169602103},
    KorbloxSwordAndShield = {name="KorbloxSwordAndShield", id=68539623},
    StaffOfPitFire = {name="StaffOfPitFire", id=49491808},
    StepGun = {name="StepGun", id=34898883},
    NeonNinjaSword = {name="NeonNinjaSword", id=535104095},
	SwordOfTheBehemoth = { name = "Sword of the Behemoth", id = 93725362 },
    WormholeTunneler = { name = "WormholeTunneler", id = 34870758 }
}

-- Helper Functions

-- NEW: Functions to save and load lists
local function tableToString(tbl)
    local names = {}
    for name, _ in pairs(tbl) do
        table.insert(names, name)
    end
    return table.concat(names, ",")
end

local function stringToTable(str)
    local tbl = {}
    if type(str) ~= "string" then return tbl end
    for name in string.gmatch(str, "[^,]+") do
        tbl[name] = true
    end
    return tbl
end

local function saveLists()
    pcall(function()
        writefile("auto_target_list.txt", tableToString(PlayerAutoTargetList))
        writefile("ignore_list.txt", tableToString(PlayerIgnoreList))
    end)
end

local function loadLists()
    pcall(function()
        PlayerAutoTargetList = stringToTable(readfile("auto_target_list.txt"))
        PlayerIgnoreList = stringToTable(readfile("ignore_list.txt"))
    end)
end

local function fireEquipTool()
    local char,bp = getCharBP()
    if not (char and bp) then return end
    local tool = bp:FindFirstChild("Diamond Blade Sword")
    if tool then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = true end
        tool.Parent = char
        task.wait(0.01)
        tool.Parent = bp
        if hrp then hrp.Anchored = false end
    end
end
--========================================================--
--                 Gear Loading / Equipping               --
--========================================================--

-- Returns Character and Backpack
local function getCharBP()
    local char = LocalPlayer.Character
    local bp   = LocalPlayer:FindFirstChild("Backpack")
    return char, bp
end
local function platformNan(part)
    if part.Name == "StickyStep" then
        part.AssemblyLinearVelocity = Vector3.new(nan, nan, nan)
    end
end
-- Toggle asset remotely
local function ToggleAsset(id)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local toggle  = remotes and remotes:FindFirstChild("ToggleAsset")
    if toggle then
        pcall(function() toggle:InvokeServer(id) end)
    end
end

-- Check if you already have a gear
local function hasGear(gearName)
    local char, bp = getCharBP()
    if not char then return false end
    return (bp and bp:FindFirstChild(gearName)) or char:FindFirstChild(gearName)
end

-- Load / equip missing gear
local function loadGearIfMissing(gearId, gearName, debug)
    -- Skip if already have it
    if hasGear(gearName) then
        if debug then print("Already have:", gearName) end
        return true
    end

    -- Only toggle once to request the gear
    ToggleAsset(gearId)

    -- Wait briefly for it to appear
    local char, bp = getCharBP()
    local startTime = tick()
    local tool
    repeat
        tool = (bp and bp:FindFirstChild(gearName)) or (char and char:FindFirstChild(gearName))
        if tool then break end
        task.wait()
    until tick() - startTime >= 1 -- 1 second timeout

    if tool then
        if debug then print("Successfully loaded:", gearName) end
        return true
    else
        if debug then print("Failed to load:", gearName) end
        return false
    end
end

-- Equip / load all gears in the table
local function equipAllGears(gearTable, debug)
    for _, gear in pairs(gearTable) do
        loadGearIfMissing(gear.id, gear.name, debug)
        task.wait() -- tiny delay to prevent flooding
    end
end
-- NEW: Player Filtering Logic
local function isPlayerTargetable(p)
    if p == LocalPlayer then return false end
    
    -- Global ignore (Whitelist)
    if PlayerIgnoreList[p.Name] then return false end
    
    -- Global auto-target (Blacklist)
    if PlayerAutoTargetList[p.Name] then return true end
    
    -- Default selection (Green)
    return SelectedPlayers[p.Name] == true
end

local function getSelectedPlayers()
    local result = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if isPlayerTargetable(p) then
            table.insert(result, p)
        end
    end
    return result
end
local function getDiamondRemote()
    local char,bp = getCharBP()
    if not (char and bp) then return nil end
    local sword = bp:FindFirstChild("Diamond Blade Sword") or char:FindFirstChild("Diamond Blade Sword")
    if not sword then return nil end
    local script = sword:FindFirstChildOfClass("Script")
    return script and script:FindFirstChildOfClass("RemoteFunction")
end

local function getRocketRemote()
    local char,bp = getCharBP()
    if not (char and bp) then return nil end
    local rocket = bp:FindFirstChild("RocketJumper") or char:FindFirstChild("RocketJumper")
    return rocket and rocket:FindFirstChildOfClass("RemoteEvent")
end
task.spawn(function()
    loadLists()
    task.wait() -- allow character/backpack to exist
	equipAllGears(gearTable, true) -- true for debug logs
end)
-- Anti-AFK
Players.LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)
-- Loop Kill (Diamond Blade)
local function killPlayers(players)
    local diamondRemote = getDiamondRemote()
    if not diamondRemote then return end

    for _, p in ipairs(players) do
        local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                diamondRemote:InvokeServer(7, hum, math.huge)
            end)
        end
    end
end
-- Fallback chain: find the best target part
local function getTargetPart(pChar)
    return pChar:FindFirstChild("HumanoidRootPart")
        or pChar:FindFirstChild("Torso")
        or pChar:FindFirstChild("Head")
end

-- Explode loop using the chain
local function explodePlayers(players)
    local char, bp = getCharBP()
    local fireEvent = getRocketRemote(char, bp)
    if not fireEvent then return end

    for _, p in ipairs(players) do
        local pChar = p.Character
        if pChar then
            local target = getTargetPart(pChar)
            if target then
                local pos = target.Position
                pcall(function()
                    fireEvent:FireServer(pos, pos)
                    fireEvent:FireServer(pos + Vector3.new(0, 1, 0), pos)
                    fireEvent:FireServer(pos - Vector3.new(0, 0.1, 0), pos)
                end)
            end
        end
    end
end

--========================================================--
--                   Gear Detection Table                 --
--========================================================--
local gearDetectTable = {
    Balligator            = "Balligator",
    SpaceSword            = "SpaceSword",
    KorbloxSwordAndShield = "KorbloxSwordAndShield",
    RocketJumper          = "RocketJumper",
    DiamondBlade          = "Diamond Blade Sword",
    SwordOfTheBehemoth    = "Sword of the Behemoth",
    FireSword             = "FireSword",
    WormholeTunneler      = "WormholeTunneler"
}

--========================================================--
--                    Gear Detection Loop                 --
--========================================================--
task.spawn(function()
    local OFFSET_UP   = Vector3.new(0, 0, 0)
    local OFFSET_DOWN = Vector3.new(0, -0.1, 0)

    while true do
        task.wait()
        if not AutoGearKill then continue end

        local myChar = LocalPlayer.Character
        local myBp   = LocalPlayer:FindFirstChild("Backpack")
        if not (myChar and myBp) then continue end

        local diamondRemote = getDiamondRemote()
        local rocketEvent   = getRocketRemote(myChar, myBp)

        if not (diamondRemote or rocketEvent) then continue end

        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            if PlayerIgnoreList[player.Name] then continue end

            local pChar = player.Character
            local pBp   = player:FindFirstChild("Backpack")
            if not pChar then continue end

            --========================================================--
            --                  Check if player has gear              --
            --========================================================--
            local function hasGear(gearName)
                return (pBp and pBp:FindFirstChild(gearName))
                    or pChar:FindFirstChild(gearName)
            end

            local foundGear = false
            for _, gearName in pairs(gearDetectTable) do
                if hasGear(gearName) then
                    foundGear = true
                    break
                end
            end
            if not foundGear then continue end

            --========================================================--
            --                   Attack Logic                         --
            --========================================================--
            local hum  = pChar:FindFirstChildOfClass("Humanoid")
            local head = pChar:FindFirstChild("Head")
            if not hum or hum.Health <= 0 then continue end

            -- Diamond Remote Attack
            if diamondRemote then
                pcall(function()
                    diamondRemote:InvokeServer(7, hum, math.huge)
                end)
            end

            -- Rocket / Fire Event Attack
            if rocketEvent and head then
                pcall(function()
                    rocketEvent:FireServer(head.Position - OFFSET_DOWN, head.Position)
                    rocketEvent:FireServer(head.Position - OFFSET_UP,   head.Position)
                end)
            end
        end
    end
end)
-- Anti-BB8 Crasher Loop (STABLE - No Anchor, Teleport in Front)
task.spawn(function()
    while true do
        task.wait(0.05)
        if not AntiBB8Toggle then task.wait(0.5); continue end
        
        local char = LocalPlayer.Character
        local bp = LocalPlayer:FindFirstChild("Backpack")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not (char and bp and hrp and hrp.Parent) then task.wait(0.5); continue end
        
        local ninjaSword = char:FindFirstChild(gearTable.NeonNinjaSword.name)
        local ninjaHandle = ninjaSword and ninjaSword:FindFirstChild("Handle")
        
        if not (ninjaSword and ninjaHandle) then
              safeEquipGear(gearTable.NeonNinjaSword)
              continue
        end
        
        -- NEW: Teleport 2 studs IN FRONT of the handle to prevent collision/fling
        local TargetCFrame = ninjaHandle.CFrame * CFrame.new(0, 0, -2) 
        local partToTouch = nil
        
        for _, item in ipairs(workspace:GetChildren()) do
            if item.Name == "bb8" or (item:IsA("Model") and item.Name:match("_Robot")) then
                if item:IsA("BasePart") then partToTouch = item end
                if item:IsA("Model") then
                    partToTouch = item:FindFirstChild("Torso") or item:FindFirstChild("UpperTorso") or item:FindFirstChild("HumanoidRootPart") or item:FindFirstChildOfClass("BasePart")
                end
                if partToTouch and partToTouch:IsA("BasePart") then break end
            end
        end

        if partToTouch and partToTouch:IsA("BasePart") then
            pcall(function()
                -- No anchor needed
                partToTouch.CFrame = TargetCFrame
                TouchAndUnTouch(partToTouch, ninjaHandle)
            end)
        end
    end
end)


-- GUI Setup
local ScreenGui = Instance.new("ScreenGui", PlayerGui)
ScreenGui.Name = "AdminGUI"
ScreenGui.ResetOnSpawn = false 

local Frame = Instance.new("Frame", ScreenGui)
Frame.Size = UDim2.new(0,420,0,820) -- Height is the same as your last script
Frame.Position = UDim2.new(0,50,0,50)
Frame.BackgroundColor3 = Color3.fromRGB(60,0,150)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true

local Header = Instance.new("TextLabel", Frame)
Header.Size = UDim2.new(1,0,0,40)
Header.BackgroundColor3 = Color3.fromRGB(100,0,220)
Header.Text = "Stable Admin Panel"
Header.TextColor3 = Color3.fromRGB(255,255,255)
Header.TextScaled = true
Header.Font = Enum.Font.SourceSansBold

-- Player Dropdown
local PlayerDropdown = Instance.new("TextButton", Frame)
PlayerDropdown.Position = UDim2.new(0,10,0,50)
PlayerDropdown.Size = UDim2.new(0,400,0,30)
PlayerDropdown.Text = "Select Player(s) (Click to cycle)"
PlayerDropdown.BackgroundColor3 = Color3.fromRGB(120,0,220)
PlayerDropdown.TextColor3 = Color3.fromRGB(255,255,255)
PlayerDropdown.TextScaled = true

local PlayerMenu = Instance.new("ScrollingFrame", Frame)
PlayerMenu.Position = UDim2.new(0,10,0,80)
PlayerMenu.Size = UDim2.new(0,400,0,150)
PlayerMenu.BackgroundColor3 = Color3.fromRGB(80,0,180)
PlayerMenu.Visible = false
PlayerMenu.CanvasSize = UDim2.new(0,0,0,0)
PlayerMenu.ScrollBarThickness = 10

local Layout = Instance.new("UIListLayout", PlayerMenu)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0,5)

-- UPDATED Player Menu with 4-state click cycle
local function updatePlayerMenu()
    for _,c in ipairs(PlayerMenu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local y = 0
    for _,p in ipairs(Players:GetPlayers()) do
        local btn = Instance.new("TextButton", PlayerMenu)
        btn.Size = UDim2.new(1,0,0,30)
        btn.Position = UDim2.new(0,0,0,y)
        
        -- Player Selection/List Status Display
        local text = p.Name
        local bgColor = Color3.fromRGB(0, 100, 255) -- Default: Blue (Unselected)
        
        if SelectedPlayers[p.Name] then
            text = p.Name .. " (Selected)"
            bgColor = Color3.fromRGB(0, 200, 0) -- Selected: Green
        elseif PlayerAutoTargetList[p.Name] then
            text = p.Name .. " (Auto-Target)"
            bgColor = Color3.fromRGB(80, 80, 80) -- Blacklist/Auto-Target: Black/Grey
        elseif PlayerIgnoreList[p.Name] then
            text = p.Name .. " (Ignoring)"
            bgColor = Color3.fromRGB(100, 100, 255) -- Whitelist/Ignore: Light Blue
        end

        btn.Text = text
        btn.BackgroundColor3 = bgColor
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.TextScaled = true
        
        local function onPlayerClick()
            -- Cycle between Selected, Auto-Target, Ignore, and Off
            if SelectedPlayers[p.Name] then
                SelectedPlayers[p.Name] = nil
                PlayerAutoTargetList[p.Name] = true
            elseif PlayerAutoTargetList[p.Name] then
                PlayerAutoTargetList[p.Name] = nil
                PlayerIgnoreList[p.Name] = true
            elseif PlayerIgnoreList[p.Name] then
                PlayerIgnoreList[p.Name] = nil
            else
                SelectedPlayers[p.Name] = true
            end
            saveLists() -- Save lists every time you click
            updatePlayerMenu()
        end

        btn.MouseButton1Click:Connect(onPlayerClick)
        y = y + 35
    end
    PlayerMenu.CanvasSize = UDim2.new(0,0,0,y)
end

PlayerDropdown.MouseButton1Click:Connect(function()
    PlayerMenu.Visible = not PlayerMenu.Visible
    updatePlayerMenu()
end)

Players.PlayerAdded:Connect(updatePlayerMenu)
Players.PlayerRemoving:Connect(function()
    saveLists() -- Save when a player leaves
    updatePlayerMenu()
end)
updatePlayerMenu()
-- Humanoid cache setup
local humanoidCache = {}

local function trackPlayer(p)
    p.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        humanoidCache[p] = hum
    end)

    if p.Character then
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if hum then humanoidCache[p] = hum end
    end
end
for _, p in ipairs(Players:GetPlayers()) do
    trackPlayer(p)
end
Players.PlayerAdded:Connect(trackPlayer)

local function createLoopButton(name, action, yPos, autoEnable)
    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(0, 400, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.Text = name
    btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true

    Toggles[name] = false

local function startLoop()
    if Toggles[name] then
        task.spawn(function()
            while Toggles[name] do
                task.wait()

                local targets, count = {}, 0
                local selected = getSelectedPlayers()

                if type(selected) ~= "table" then
                    selected = {}
                end

                for _, p in ipairs(selected) do
                    local hum = humanoidCache[p]
                    if hum and (hum.Health > 0 or hum.Health ~= hum.Health) then
                        count += 1
                        targets[count] = p
                    end
                end

                if count > 0 then
                    local ok, err = pcall(action, targets)
                    if not ok then
                        warn("Loop error in", name, err)
                    end
                end
            end
        end)
    end
end

    btn.MouseButton1Click:Connect(function()
        Toggles[name] = not Toggles[name]
        btn.BackgroundColor3 = Toggles[name] and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)
        startLoop()
    end)

    -- ✅ Auto-enable if parameter is true
    if autoEnable then
        Toggles[name] = true
        btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        startLoop()
    end
end
-- Loop Buttons
createLoopButton("Loop Kill", killPlayers, 250, true)
createLoopButton("Loop Explode", explodePlayers, 290, true)

-- Kill Aura Button
local btnKillAura = Instance.new("TextButton", Frame)
btnKillAura.Size = UDim2.new(0,400,0,30)
btnKillAura.Position = UDim2.new(0,10,0,410)
btnKillAura.Text = "Toggle Kill Aura"
btnKillAura.BackgroundColor3 = Color3.fromRGB(255,0,0)
btnKillAura.TextColor3 = Color3.fromRGB(255,255,255)
btnKillAura.TextScaled = true
btnKillAura.MouseButton1Click:Connect(function()
    KillAuraEnabled = not KillAuraEnabled
    btnKillAura.BackgroundColor3 = KillAuraEnabled and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
end)

-- Equip All Button
local btnEquipAll = Instance.new("TextButton", Frame)
btnEquipAll.Size = UDim2.new(0,400,0,30) 
btnEquipAll.Position = UDim2.new(0,10,0,450)
btnEquipAll.Text = "Equip All Gears"
btnEquipAll.BackgroundColor3 = Color3.fromRGB(0,200,0)
btnEquipAll.TextColor3 = Color3.fromRGB(255,255,255)
btnEquipAll.TextScaled = true
btnEquipAll.MouseButton1Click:Connect(function()
    task.spawn(function()
        task.wait(0.05) -- allow character/backpack to exist
        equipAllGears(gearTable, true) -- true = debug logs
    end)
end)

-- Gear Detect Toggle
local btnGearDetect = Instance.new("TextButton", Frame)
btnGearDetect.Size = UDim2.new(0,400,0,30)
btnGearDetect.Position = UDim2.new(0,10,0,490)
btnGearDetect.Text = AutoGearKill and "Gear Detect: ON (Selective)" or "Toggle Gear Detect"
btnGearDetect.BackgroundColor3 = AutoGearKill and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
btnGearDetect.MouseButton1Click:Connect(function()
    AutoGearKill = not AutoGearKill
    btnGearDetect.BackgroundColor3 = AutoGearKill and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
    btnGearDetect.Text = AutoGearKill and "Gear Detect: ON (Selective)" or "Toggle Gear Detect"
end)
-- 1️⃣ Create button
local btnKorblox = Instance.new("TextButton", Frame)
btnKorblox.Size = UDim2.new(0, 400, 0, 30)
btnKorblox.Position = UDim2.new(0, 10, 0, 530)
btnKorblox.Text = "Toggle Korblox Bring"
btnKorblox.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
btnKorblox.TextColor3 = Color3.fromRGB(255, 255, 255)
btnKorblox.TextScaled = true

local KorbloxToggle = false
local running = false
local originalCFrames = {}
local swungTargets = {}

local function findKorbloxTool()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    return (char and char:FindFirstChild("KorbloxSwordAndShield")) 
        or (backpack and backpack:FindFirstChild("KorbloxSwordAndShield"))
end

local function restorePlayers()
    for part, cframe in pairs(originalCFrames) do
        if part.Parent then
            part.CFrame = cframe
            part.Anchored = false
        end
    end
    originalCFrames = {}
    swungTargets = {}
end

local function KorbloxLoopFast()
    if running then return end
    running = true

    task.spawn(function()
        while KorbloxToggle do
            local char = LocalPlayer.Character
            local torso = char and (char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart"))
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local sword = findKorbloxTool()

            if not (char and torso and humanoid and sword) then
                task.wait(0.1)
                continue
            end

            if sword.Parent ~= char then
                humanoid:EquipTool(sword)
                task.wait()
            end

            for _, target in ipairs(getSelectedPlayers()) do
                local tChar = target.Character
                if not tChar then continue end

                for _, part in ipairs(tChar:GetChildren()) do
                    if part:IsA("BasePart") then
                        if not originalCFrames[part] then
                            originalCFrames[part] = part.CFrame
                        end
                        part.Anchored = true
                        part.CFrame = torso.CFrame * CFrame.new(1.5, 3.5, -1.8) * CFrame.Angles(math.rad(90),0,0)
                    end
                end

                if not swungTargets[target] then
                    pcall(function() sword:Activate() end)
                    swungTargets[target] = true
                end
            end

            task.wait(0.01)
        end

        restorePlayers()
        running = false
    end)
end
btnKorblox.MouseButton1Click:Connect(function()
    KorbloxToggle = not KorbloxToggle
    btnKorblox.BackgroundColor3 = KorbloxToggle and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)

    if KorbloxToggle then
        KorbloxLoopFast()
    else
        restorePlayers()
    end
end)
LocalPlayer.CharacterAdded:Connect(function()
    if KorbloxToggle then
        task.wait(0.5)
        KorbloxLoopFast()
    end
end)

-- ForceField Removal Loop Toggle (FFRemoveToggle) (STABLE VERSION)
local function forceFieldRemovalLoop()
    while FFRemoveToggle do
        task.wait(0.1) 

        for _, obj in ipairs(workspace:GetChildren()) do
            
            -- Check if the object's name ends with "'s Cloud" or "'s cloud"
            if string.find(obj.Name, "'s Cloud", nil, true) or string.find(obj.Name, "'s cloud", nil, true) then 
                
                -- Search by NAME for the object named "ForceField"
                local ff = obj:FindFirstChild("ForceField") 
                
                if ff then
                    pcall(function() ff:Destroy() end)
                end
            end
        end
    end
end

local btnRemoveFF = Instance.new("TextButton", Frame)
btnRemoveFF.Size = UDim2.new(0, 400, 0, 30) 
btnRemoveFF.Position = UDim2.new(0, 10, 0, 570)
btnRemoveFF.Text = "Toggle FF Removal ('s cloud) - VISUAL"
btnRemoveFF.BackgroundColor3 = Color3.fromRGB(200, 100, 0) 
btnRemoveFF.TextColor3 = Color3.fromRGB(255, 255, 255)
btnRemoveFF.TextScaled = true
btnRemoveFF.MouseButton1Click:Connect(function()
    FFRemoveToggle = not FFRemoveToggle
    btnRemoveFF.BackgroundColor3 = FFRemoveToggle and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(200, 100, 0)
    
    if FFRemoveToggle then
        task.spawn(forceFieldRemovalLoop)
    end
end)

-- Anti-BB8 Toggle Button
local btnAntiBB8 = Instance.new("TextButton", Frame)
btnAntiBB8.Size = UDim2.new(0,400,0,30)
btnAntiBB8.Position = UDim2.new(0,10,0,610)
btnAntiBB8.Text = "Toggle Anti-BB8"
btnAntiBB8.BackgroundColor3 = Color3.fromRGB(255,0,0)
btnAntiBB8.TextColor3 = Color3.fromRGB(255,255,255)
btnAntiBB8.TextScaled = true
btnAntiBB8.MouseButton1Click:Connect(function()
    AntiBB8Toggle = not AntiBB8Toggle
    btnAntiBB8.BackgroundColor3 = AntiBB8Toggle and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
    if AntiBB8Toggle then safeEquipGear(gearTable.NeonNinjaSword) end
end)

-- Crash Button (Uses Balligator and SpaceSword)
local btnCrash = Instance.new("TextButton", Frame)
btnCrash.Size = UDim2.new(0,400,0,30)
btnCrash.Position = UDim2.new(0,10,0,650)
btnCrash.Text = "CRASH!"
btnCrash.BackgroundColor3 = Color3.fromRGB(255,0,0)
btnCrash.TextColor3 = Color3.fromRGB(255,255,255)
btnCrash.TextScaled = true
btnCrash.MouseButton1Click:Connect(function()
    local char,bp = getCharBP()
    if not (char and bp) then return end
    local aligator = bp:FindFirstChild(gearTable.Balligator.name) or char:FindFirstChild(gearTable.Balligator.name)
    local space = bp:FindFirstChild(gearTable.SpaceSword.name) or char:FindFirstChild(gearTable.SpaceSword.name)
    if not (aligator and space) then return end
    if aligator.Parent == bp then aligator.Parent = char end
    if space.Parent == bp then space.Parent = char end
    local rmt = aligator:WaitForChild("Remote",5):WaitForChild("Spawn",5)
    if rmt then pcall(function() rmt:InvokeServer() end) end
    local model = char:FindFirstChildOfClass("Model")
    if model then
        model:PivotTo(CFrame.new(Vector3.new(1e28,1e28,1e28)))
    end
    local ctrl = space:WaitForChild("ControlFunction",5)
    if ctrl then pcall(function() ctrl:InvokeServer("KeyDown","q") end) end
end)
--========================================================--
--                    SERVICES                          --
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local ToggleAssetRemote = ReplicatedStorage:FindFirstChild("ToggleAsset", true)

--========================================================--
--                    CONSTANTS                         --
--========================================================--

local ARCHOUR_ID = 49491808
local TOOL_NAME = "StaffOfPitFire"

local active = false
local running = false

--========================================================--
--              ANCHORED CHECK (TORSO ONLY)              --
--========================================================--

local function isAnchored()
    local char = LocalPlayer.Character
    local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
    return torso and torso.Anchored or false
end

--========================================================--
--                TOOL FINDER                           --
--========================================================--

local function findTool()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    return (char and char:FindFirstChild(TOOL_NAME))
        or (backpack and backpack:FindFirstChild(TOOL_NAME))
end

--========================================================--
--                CORE ANCHOR FUNCTION                   --
--========================================================--

local function AnchorPlayer()
    if not ToggleAsset or isAnchored() then return end

    local tool = findTool()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not (humanoid and character) then return end

    -- Spawn tool if we don't already have it
    if not tool then
        ToggleAssetRemote:InvokeServer(ARCHOUR_ID)
        local backpack = LocalPlayer:WaitForChild("Backpack", 2)
        tool = backpack:WaitForChild(TOOL_NAME, 2)
    end

    if not tool then return end

    -- Equip and activate first
    humanoid:EquipTool(tool)
    task.wait() -- allow equip to complete
    if tool.Parent == character then
        tool:Activate()
    end

    -- THEN toggle asset for anchoring
    ToggleAssetRemote:InvokeServer(ARCHOUR_ID)
end
--========================================================--
--                LOOP (SINGLE INSTANCE)                 --
--========================================================--

local function startLoop()
    if running then return end
    running = true

    task.spawn(function()
        while active do
            AnchorPlayer()
            task.wait(0.4)
        end
        running = false
    end)
end

--========================================================--
--                GUI BUTTON                            --
--========================================================--

local btnArch = Instance.new("TextButton", Frame)
btnArch.Size = UDim2.new(0, 400, 0, 30)
btnArch.Position = UDim2.new(0, 10, 0, 690)
btnArch.Text = "Archour: OFF"
btnArch.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
btnArch.TextColor3 = Color3.fromRGB(255, 255, 255)
btnArch.TextScaled = true
btnArch.Font = Enum.Font.SourceSansBold

btnArch.MouseButton1Click:Connect(function()
    active = not active

    btnArch.Text = active and "Archour: ON" or "Archour: OFF"
    btnArch.BackgroundColor3 = active and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)

    if active then
        startLoop()
    end
end)

-- [[ VARIABLES ]] --
local LocalPlayer = game:GetService("Players").LocalPlayer
local active = true -- Set to true for auto-start
local running = false

-- [[ GUI ELEMENT ]] --
local btn = Instance.new("TextButton", Frame)
btn.Size = UDim2.new(0, 400, 0, 30)
btn.Position = UDim2.new(0, 10, 0, 410)
btn.Text = active and "God Mode: ACTIVE" or "God Mode: OFF"
btn.BackgroundColor3 = active and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(170, 0, 0)
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.TextScaled = true

-- [[ CORE LOGIC ]] --
local function startLoop()
    -- Only one loop should run at a time
    if running then return end
    running = true

    task.spawn(function()
        while active do
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            
            -- Reliability Check: Make sure humanoid exists and isn't already dead
            if hum and hum.Health > 0 then
                local h = hum.Health
                
                -- Only fire if health isn't already infinite
                if (h == h) and (h ~= math.huge) then
                    -- Search Backpack and Character for the sword
                    local sword = LocalPlayer:FindFirstChild("Backpack") and LocalPlayer.Backpack:FindFirstChild("Diamond Blade Sword") 
                                  or (char and char:FindFirstChild("Diamond Blade Sword"))
                    
                    if sword then
                        local sObj = sword:FindFirstChildOfClass("Script")
                        local remote = sObj and sObj:FindFirstChildOfClass("RemoteFunction")
                        
                        if remote then
                            -- Use pcall and task.spawn to prevent the loop from ever "freezing"
                            task.spawn(function()
                                pcall(function()
                                    remote:InvokeServer(7, hum, -math.huge)
                                end)
                            end)
                        end
                    end
                end
            end
            task.wait(0.1) -- Slightly slower wait to prevent Remote spam kicks
        end
        running = false
    end)
end

-- [[ BUTTON TOGGLE ]] --
btn.MouseButton1Click:Connect(function()
    active = not active
    if active then
        btn.Text = "God Mode: ACTIVE"
        btn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        startLoop()
    else
        btn.Text = "God Mode: OFF"
        btn.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
    end
end)

-- [[ AUTO-RESTART ON RESPAWN ]] --
LocalPlayer.CharacterAdded:Connect(function()
    -- Reset the latch so the loop can start fresh for the new character
    running = false 
    task.wait(1) -- Wait for character to fully initialize
    if active then
        startLoop()
    end
end)

-- [[ INITIAL START ]] --
if active then
    startLoop()
end
-- ANTI-FLING (Auto, always on)
task.spawn(function()
    while true do
        task.wait(0.1)  -- fast loop
        local char = LocalPlayer.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0,0,0)
            root.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end)
    end
end)

-- GUI Button
local btnGearDetect = Instance.new("TextButton", Frame)
btnGearDetect.Size = UDim2.new(0, 400, 0, 30)
btnGearDetect.Position = UDim2.new(0, 10, 0, 330)
btnGearDetect.Text = "Toggle AnyGear Bring"
btnGearDetect.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
btnGearDetect.TextColor3 = Color3.fromRGB(255, 255, 255)
btnGearDetect.TextScaled = true

local GearToggle = false
local running = false

-- Track original part positions
local originalCFrames = {}
local swungTargets = {}

--========================================================--
--              Find any Tool in Backpack/Character       --
--========================================================--
local function findAnyTool()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    for _, tool in ipairs((char and char:GetChildren() or {}) ) do
        if tool:IsA("Tool") then return tool end
    end
    for _, tool in ipairs((backpack and backpack:GetChildren() or {}) ) do
        if tool:IsA("Tool") then return tool end
    end
    return nil
end

--========================================================--
--                 Bring Player Parts                     --
--========================================================--
local function bringPlayerAnyGear(target)
    local tChar = target.Character
    if not tChar then return end
    local char = LocalPlayer.Character
    local torso = char and char:FindFirstChild("Torso")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local tool = findAnyTool()
    if not (char and torso and humanoid and tool) then return end

    -- Equip tool once
    if tool.Parent ~= char then
        humanoid:EquipTool(tool)
        task.wait()
    end

    -- Move all BaseParts of target
    for _, part in ipairs(tChar:GetChildren()) do
        if part:IsA("BasePart") then
            if not originalCFrames[part] then
                originalCFrames[part] = part.CFrame
            end
            part.Anchored = true
            part.CFrame = torso.CFrame * CFrame.new(1.5, 3.5, -1.8) * CFrame.Angles(math.rad(90),0,0)
        end
    end

    -- Activate tool once per target
    if not swungTargets[target] and tool.Parent == char then
        tool:Activate()
        swungTargets[target] = true
    end
end

--========================================================--
--                 Restore Player Parts                  --
--========================================================--
local function restorePlayersAnyGear()
    for part, cframe in pairs(originalCFrames) do
        if part.Parent then
            part.CFrame = cframe
            part.Anchored = false
        end
    end
    originalCFrames = {}
    swungTargets = {}
end

--========================================================--
--                 Any Gear Loop                          --
--========================================================--
local function startAnyGearLoop()
    if running then return end
    running = true

    task.spawn(function()
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local torso = char and char:FindFirstChild("Torso")
        if not (char and humanoid and torso) then
            running = false
            return
        end

        local tool = findAnyTool()
        if not tool then
            running = false
            return
        end

        -- Equip tool once
        if tool.Parent ~= char then
            humanoid:EquipTool(tool)
            task.wait()
        end

        while GearToggle do
            local targets = getSelectedPlayers()
            for _, target in ipairs(targets) do
                pcall(bringPlayerAnyGear, target)
            end
            task.wait(0.01) -- ultra-fast
        end

        restorePlayersAnyGear()
        running = false
    end)
end

--========================================================--
--                 Button Click Handler                  --
--========================================================--
btnGearDetect.MouseButton1Click:Connect(function()
    GearToggle = not GearToggle
    btnGearDetect.BackgroundColor3 = GearToggle and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)
    startAnyGearLoop()
end)

--========================================================--
--                 Auto Restart on Respawn               --
--========================================================--
LocalPlayer.CharacterAdded:Connect(function()
    if GearToggle then
        startAnyGearLoop()
    end
end)
-- Ultra-light Auto Black Screen Remover
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BlindGuisTable = {
    ScreenFog = true,
    DarknessGui = true,
    VolleyballScreenGui = true,
    FlashBangEffect = true
}

-- Keep track of GUIs we've already checked
local checkedGuis = {}

-- Listen for new GUI children being added
PlayerGui.ChildAdded:Connect(function(gui)
    if BlindGuisTable[gui.Name] then
        pcall(function()
            gui:Destroy()
        end)
    end
    checkedGuis[gui] = true
end)

-- Clean any existing GUIs on script start
for _, gui in ipairs(PlayerGui:GetChildren()) do
    if BlindGuisTable[gui.Name] then
        pcall(function()
            gui:Destroy()
        end)
    end
    checkedGuis[gui] = true
end
-- [[ SETTINGS ]] --
local PlatformToggle = false
local LocalPlayer = Players.LocalPlayer
local FireRate = 0.1 -- Adjust this (0.1 = 10 times per second)

-- [[ COLLISION LOGIC ]] --
local function setNoCollision(targetChar)
    for _, part in ipairs(targetChar:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end

-- [[ HELPERS ]] --
local function getCharBP()
    return LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")
end

local function getPlatformShooter()
    local char, bp = getCharBP()
    if not (char or bp) then return end
    local gun = (bp and bp:FindFirstChild("StepGun")) or (char and char:FindFirstChild("StepGun"))
    if not gun then return end
    return gun, gun:FindFirstChildOfClass("RemoteEvent")
end

-- Using your provided targeting function
local function getSelectedPlayers()
    local result = {}
    for _, p in ipairs(Players:GetPlayers()) do
        -- Ensure isPlayerTargetable is defined in your main script
        if isPlayerTargetable(p) then
            table.insert(result, p)
        end
    end
    return result
end

-- [[ PERSISTENT LOOP ]] --
task.spawn(function()
    while true do
        -- Using task.wait() to prevent crashing/remote-spam kicks
        task.wait(FireRate)

        if not PlatformToggle then continue end

        local myChar, myBp = getCharBP()
        local PlatformGun, ShootEvent = getPlatformShooter()

        if not (myChar and PlatformGun and ShootEvent) then continue end

        local myTorso = myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso") or myChar:FindFirstChild("UpperTorso")
        if not myTorso then continue end

        for _, player in ipairs(getSelectedPlayers()) do
            local targetChar = player.Character
            if not targetChar then continue end

            local targetTorso = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Torso") or targetChar:FindFirstChild("UpperTorso")
            local targetHead = targetChar:FindFirstChild("Head")
            
            if targetTorso and targetHead then
                -- 1. Collision
                setNoCollision(targetChar)

                -- 2. Positions
                local targetPosition = myTorso.Position + Vector3.new(0, 8, 0)
                local firePosition = targetTorso.Position - Vector3.new(0, 2, 0)

                -- 3. Visuals (Local Only)
                targetHead.Anchored = true
                targetHead.CanCollide = false
                targetHead.Size = Vector3.new(2048, 2048, 2048)
                
                targetTorso.CFrame = CFrame.new(targetPosition)
                targetHead.CFrame = CFrame.new(targetPosition)

                -- 4. Auto-Equip
                if PlatformGun.Parent ~= myChar then
                    PlatformGun.Parent = myChar
                end

                -- 5. Firing Logic
                pcall(function()
                    ShootEvent:FireServer(firePosition)
                end)

                -- 6. "Sticky" Report Logic
                local ReportRemote = game.ReplicatedStorage:FindFirstChild("Report")
                if ReportRemote then
                    pcall(function()
                        ReportRemote:FireServer(CFrame.new(-math.huge, -math.huge, -math.huge))
                    end)
                end
            end
        end
    end
end)

-- [[ GUI BUTTON ]] --
-- Assuming 'Frame' is already defined in your UI setup
local btnPlatform = Instance.new("TextButton")
btnPlatform.Name = "PlatformToggleButton"
btnPlatform.Parent = Frame -- Change 'Frame' to your GUI frame name
btnPlatform.Size = UDim2.new(0, 400, 0, 30)
btnPlatform.Position = UDim2.new(0, 10, 0, 370)
btnPlatform.Text = "PLATFORM: OFF"
btnPlatform.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
btnPlatform.TextColor3 = Color3.fromRGB(255, 255, 255)
btnPlatform.TextScaled = true

btnPlatform.MouseButton1Click:Connect(function()
    PlatformToggle = not PlatformToggle
    btnPlatform.Text = PlatformToggle and "PLATFORM: ACTIVE" or "PLATFORM: OFF"
    btnPlatform.BackgroundColor3 = PlatformToggle and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(200, 0, 0)
    
    if not PlatformToggle then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then
                local head = player.Character:FindFirstChild("Head")
                if head then
                    head.Anchored = false
                    head.Size = Vector3.new(1, 1, 1) -- Standard Head Size
                    head.CanCollide = true
                end
            end
        end
    end
end)

local success, err = pcall(function()
    local shothook; shothook = hookmetamethod(game, "__namecall", function(self, ...)
        local args = { ... }
        local method = getnamecallmethod()
        if tostring(self) == "Report" and method == "FireServer" then
            args[1] = CFrame.new(NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN)
        end
        return shothook(self, unpack(args))
    end)
end)
