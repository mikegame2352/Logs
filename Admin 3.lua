-- FINAL ADMIN GUI LOCAL SCRIPT (FIXED GEAR DETECT, PART GRAB KILL, LISTS, BB8 STABILITY)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService") -- Used for saving/loading
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
-- State Variables
local SelectedPlayers = {}
local PlayerAutoTargetList = {} -- NEW: Players to ALWAYS target (Black/Grey)
local PlayerIgnoreList = {}   -- NEW: Players to NEVER target (Blue)
local Toggles = {}
local KillAuraEnabled = false
local KillAuraRadius = 20
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

local function getCharBP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local bp = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack")
    return char,bp
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

local function safeEquipGear(gear)
    local char,bp = getCharBP()
    local tool = bp:FindFirstChild(gear.name) or char:FindFirstChild(gear.name)
    
    if not tool then
        local rem = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ToggleAsset")
        if rem then pcall(function() rem:InvokeServer(gear.id) end) end
        task.wait(0.1)
        tool = bp:FindFirstChild(gear.name) or char:FindFirstChild(gear.name)
    end
    
    if tool and bp then
        pcall(function() char:FindFirstChildOfClass("Humanoid"):EquipTool(tool) end)
    end
end

local function equipAllGears()
    for _,gear in pairs(gearTable) do safeEquipGear(gear) end
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
    if not script then return nil end
    return script:FindFirstChildOfClass("RemoteFunction")
end

local function getRocketRemote(char, bp)
    local rocket = bp:FindFirstChild("RocketJumper") or char:FindFirstChild("RocketJumper")
    return rocket and rocket:FindFirstChildOfClass("RemoteEvent")
end

-- Client-Side Simulated Touch (UPDATED with CanCollide fix)
local function TouchAndUnTouch(PartToTouch, MyTouchTransmitter)
    task.spawn(function()
        pcall(function()
            if not (PartToTouch and MyTouchTransmitter) then return end
            
            -- **NEW: Temporarily disable collision to prevent self-knockback**
            local originalCanCollide = PartToTouch.CanCollide
            PartToTouch.CanCollide = false 
            
            firetouchinterest(PartToTouch, MyTouchTransmitter, 0) -- Touch
            task.wait()
            firetouchinterest(PartToTouch, MyTouchTransmitter, 1) -- Untouch
            
            -- Restore collision state immediately after the touch sequence
            PartToTouch.CanCollide = originalCanCollide
        end)
    end)
end

-- AUTO-EQUIP AND AUTO-GET GEARS ON START
task.spawn(function()
    loadLists() -- Load saved lists on startup
    getCharBP()
    equipAllGears()
    fireEquipTool()
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
        local char = p.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function()
                    diamondRemote:InvokeServer(7, hum, math.huge)
                end)
            end
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
                    fireEvent:FireServer(pos + Vector3.new(0,2,0), pos)
                    fireEvent:FireServer(pos - Vector3.new(0,2,0), pos)
                end)
            end
        end
    end
end
-- Kill Aura Loop (UPDATED with List support)
task.spawn(function()
    while true do
        task.wait()
        if KillAuraEnabled then
            local myChar = LocalPlayer.Character
            if not myChar then continue end
            local myPos = myChar:FindFirstChild("HumanoidRootPart") and myChar.HumanoidRootPart.Position
            if not myPos then continue end
            local nearbyPlayers = {}
            for _,p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and not PlayerIgnoreList[p.Name] then -- Check Ignore List
                    local c = p.Character
                    if c and c:FindFirstChild("HumanoidRootPart") then
                        local dist = (c.HumanoidRootPart.Position - myPos).Magnitude
                        if dist <= KillAuraRadius then table.insert(nearbyPlayers,p) end
                    end
                end
            end
            if #nearbyPlayers>0 then applyDamage(nearbyPlayers,math.huge) end
        end
    end
end)

-- Ultra Fast, Safe Gear Detect Loop
task.spawn(function()
    -- Pre-made vectors for explosion (faster than creating new ones every loop)
    local OFFSET_UP   = Vector3.new(0,  0, 0)
    local OFFSET_DOWN = Vector3.new(0, -1, 0)

    while true do
        task.wait() -- faster but still safe
        
        if not AutoGearKill then continue end

        local myChar = LocalPlayer.Character
        local myBp = LocalPlayer:FindFirstChild("Backpack")
        if not (myChar and myBp) then continue end
        
        local diamondRemote = getDiamondRemote()
        local fireEvent = getRocketRemote(myChar, myBp)

        if not (diamondRemote or fireEvent) then continue end

        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            if PlayerIgnoreList[player.Name] then continue end
            
            local pChar = player.Character
            if not pChar then continue end

            local pBP = player:FindFirstChild("Backpack")

            -- ⚡ FAST LOCAL LOOKUPS
            local bpFind = pBP and pBP.FindFirstChild
            local charFind = pChar.FindFirstChild

            -- ⚔️ GEAR DETECTION (now includes Behemoth + Wormhole)
            local hasGear =
                (bpFind and bpFind(pBP, gearTable.Balligator.name))
                or charFind(pChar, gearTable.Balligator.name)
                or (bpFind and bpFind(pBP, gearTable.KorbloxSwordAndShield.name))
                or charFind(pChar, gearTable.KorbloxSwordAndShield.name)
                or (bpFind and bpFind(pBP, gearTable.RocketJumper.name))
                or charFind(pChar, gearTable.RocketJumper.name)
                or (bpFind and bpFind(pBP, gearTable.DiamondBlade.name))
                or charFind(pChar, gearTable.DiamondBlade.name)
                or (bpFind and bpFind(pBP, gearTable.SwordOfTheBehemoth.name))
                or charFind(pChar, gearTable.SwordOfTheBehemoth.name)
                or (bpFind and bpFind(pBP, gearTable.WormholeTunneler.name))
                or charFind(pChar, gearTable.WormholeTunneler.name)

            -- Skip if no gear detected
            if not hasGear then continue end

            -- Check humanoid health
            local hum = pChar:FindFirstChildOfClass("Humanoid")
            if not hum then continue end
            if hum.Health <= 0 then continue end

            -- HEAD for rocket
            local head = charFind(pChar, "Head")

            -- 💥 APPLY DAMAGE SAFELY
            if diamondRemote then
                pcall(function()
                    diamondRemote:InvokeServer(7, hum, math.huge)
                end)
            end

            -- 💣 EXPLOSIONS
            if fireEvent and head then
                pcall(function() fireEvent:FireServer(head.Position - OFFSET_DOWN, head.Position) end)
                pcall(function() fireEvent:FireServer(head.Position - OFFSET_UP,   head.Position) end)
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
Frame.Size = UDim2.new(0,420,0,780) -- Height is the same as your last script
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
    -- Update cache when character spawns
    p.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        humanoidCache[p] = hum
    end)
    -- If they already have a character
    if p.Character then
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if hum then humanoidCache[p] = hum end
    end
end

-- Track all current + future players
for _, p in ipairs(Players:GetPlayers()) do
    trackPlayer(p)
end
Players.PlayerAdded:Connect(trackPlayer)

-- Loop button factory
local function createLoopButton(name, action, yPos)
    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(0, 400, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.Text = name
    btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true

    Toggles[name] = false
    local heartbeatConnection

    btn.MouseButton1Click:Connect(function()
        Toggles[name] = not Toggles[name]
        btn.BackgroundColor3 = Toggles[name] and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)

        if heartbeatConnection then
            heartbeatConnection:Disconnect()
            heartbeatConnection = nil
        end

        if Toggles[name] then
            local loopAction = action
            heartbeatConnection = RunService.RenderStepped:Connect(function()
                if not Toggles[name] then return end

                local targets, count = {}, 0
                for _, p in ipairs(getSelectedPlayers()) do
                    local hum = humanoidCache[p]
                    -- Keep NaN and positive health
                    if hum and (hum.Health > 0 or hum.Health ~= hum.Health) then
                        count += 1
                        targets[count] = p
                    end
                end

                if count > 0 and loopAction then
                    loopAction(targets)
                end
            end)
        end
    end)
end
-- Loop Buttons
createLoopButton("Loop Kill", killPlayers, 250)
createLoopButton("Loop Explode", explodePlayers, 290)
createLoopButton("Loop NaN (Self)", function(_) applyDamage({LocalPlayer}, 0/0) end, 370)

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
btnEquipAll.MouseButton1Click:Connect(equipAllGears)

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

-- Flexible Part Grab Kill Button (STABLE)
local btnKorblox = Instance.new("TextButton", Frame)
btnKorblox.Size = UDim2.new(0,400,0,30)
btnKorblox.Position = UDim2.new(0,10,0,530)
btnKorblox.Text = "Toggle Part Grab Kill (Equipped Tool)"
btnKorblox.BackgroundColor3 = Color3.fromRGB(255,0,0)
btnKorblox.TextColor3 = Color3.fromRGB(255,255,255)
btnKorblox.TextScaled = true
btnKorblox.MouseButton1Click:Connect(function()
    KorbloxToggle = not KorbloxToggle
    btnKorblox.BackgroundColor3 = KorbloxToggle and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
    
    if KorbloxToggle then
        task.spawn(function()
            while KorbloxToggle do
                task.wait() 

                local myChar, _ = getCharBP()
                if not myChar then continue end

                local equippedTool = myChar:FindFirstChildOfClass("Tool")
                local toolHandle = equippedTool and equippedTool:FindFirstChild("Handle")
                
                if not toolHandle then continue end

                local TargetCFrame = toolHandle.CFrame * CFrame.new(0, 0, 1) 
                local targets = getSelectedPlayers() -- Uses new function

                for _, p in ipairs(targets) do
                    local pChar = p.Character
                    if not pChar then continue end
                    
                    -- Exclude HumanoidRootPart to maintain stability and prevent server corrections
                    local partsToBring = {
                        pChar:FindFirstChild("Torso"),
                        pChar:FindFirstChild("UpperTorso"), 
                        pChar:FindFirstChild("Head")
                    }

                    for _, part in ipairs(partsToBring) do
                        if part and part.Parent then
                            pcall(function()
                                part.CFrame = TargetCFrame
                            end)
                            
                            TouchAndUnTouch(part, toolHandle)
                        end
                    end
                end
            end
        end)
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
        model:PivotTo(CFrame.new(Vector3.new(1e30,1e30,1e30)))
    end
    local ctrl = space:WaitForChild("ControlFunction",5)
    if ctrl then pcall(function() ctrl:InvokeServer("KeyDown","q") end) end
end)
-- ARCHOUR STAFF TOGGLE BUTTON GUI (StaffOfPitFire)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local ARCHOUR_ID = 49491808 -- asset ID for StaffOfPitFire

-- Anchored check
local function isCharacterAnchored()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, partName in ipairs({"HumanoidRootPart","Torso","UpperTorso","LowerTorso"}) do
        local part = char:FindFirstChild(partName)
        if part and part.Anchored then return true end
    end
    return false
end

-- Find ToggleAsset remote
local function getToggleAsset()
    local function scan(parent)
        for _, obj in ipairs(parent:GetChildren()) do
            if obj.Name == "ToggleAsset" then return obj end
            local r = scan(obj)
            if r then return r end
        end
        return nil
    end
    return scan(ReplicatedStorage)
end

-- Get Archour tool (actually StaffOfPitFire)
local function getArchourTool()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    if not bp or not char then return nil end
    return bp:FindFirstChild("StaffOfPitFire") or char:FindFirstChild("StaffOfPitFire")
end

-- Equip, auto‑fire, then unequip
local function useArchourOnce()
    if isCharacterAnchored() then return end

    local toggle = getToggleAsset()
    if not toggle then return end

    local tool = getArchourTool()

    -- Spawn if missing (poll quickly, timeout 0.5s)
    if not tool then
        pcall(function() toggle:InvokeServer(ARCHOUR_ID) end)
        local timeout = 0.5
        while not tool and timeout > 0 do
            task.wait(0.05)
            tool = getArchourTool()
            timeout -= 0.05
        end
    end

    if not tool then return end

    -- Equip
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:EquipTool(tool) else tool.Parent = LocalPlayer.Character end
    task.wait(0.15)

    -- Fire
    pcall(function() tool:Activate() end)
    task.wait(0.3)

    -- Unequip/remove via ToggleAsset
    pcall(function() toggle:InvokeServer(ARCHOUR_ID) end)
end

-- GUI Button (directly under your existing Frame)
local btnArch = Instance.new("TextButton", Frame)
btnArch.Size = UDim2.new(0,400,0,30)
btnArch.Position = UDim2.new(0,10,0,690)
btnArch.Text = "Archour: OFF"
btnArch.BackgroundColor3 = Color3.fromRGB(255,0,0) -- red when OFF
btnArch.TextColor3 = Color3.fromRGB(255,255,255)
btnArch.TextScaled = true
btnArch.Font = Enum.Font.SourceSansBold

local active = false
local persistActive = false

-- Loop runner
local function startLoop()
    task.spawn(function()
        while active do
            if isCharacterAnchored() then
                task.wait(0.4)
            else
                useArchourOnce()
                task.wait(0.5)
            end
        end
    end)
end

-- Toggle button
btnArch.MouseButton1Click:Connect(function()
    active = not active
    persistActive = active
    btnArch.Text = active and "Archour: ON" or "Archour: OFF"
    btnArch.BackgroundColor3 = active and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)

    if active then
        startLoop()
    else
        local toggle = getToggleAsset()
        if toggle then pcall(function() toggle:InvokeServer(ARCHOUR_ID) end) end
    end
end)

-- Resume after respawn
LocalPlayer.CharacterAdded:Connect(function(char)
    if persistActive then
        char:WaitForChild("Humanoid")
        LocalPlayer:WaitForChild("Backpack")
        task.wait(0.5)
        active = true
        btnArch.Text = "Archour: ON"
        btnArch.BackgroundColor3 = Color3.fromRGB(0,200,0)
        startLoop()
    end
end)
-- Toggleable God Self Loop Button (pause on NaN/Inf, resume when normal)
do
    local active = false
    local loopConnection

    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(0, 400, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, 410) -- adjust Y if needed
    btn.Text = "Toggle God Self"
    btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- red = off
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true

    local function startLoop()
        if loopConnection then loopConnection:Disconnect() end

        loopConnection = RunService.RenderStepped:Connect(function()
            if not active then return end
            local char = LocalPlayer.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end

            local h = hum.Health
            -- If health is NaN or Inf, pause (do nothing this frame)
            if h == math.huge or h ~= h then
                return
            end

            -- Otherwise keep firing
            local sword = LocalPlayer.Backpack:FindFirstChild("Diamond Blade Sword") or char:FindFirstChild("Diamond Blade Sword")
            if not sword then return end
            local script = sword:FindFirstChildOfClass("Script")
            if not script then return end
            local remote = script:FindFirstChildOfClass("RemoteFunction")
            if not remote then return end

            pcall(function()
                remote:InvokeServer(7, hum, -math.huge)
            end)
        end)
    end

    local function stopLoop()
        if loopConnection then
            loopConnection:Disconnect()
            loopConnection = nil
        end
        active = false
        btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- red when off
    end

    btn.MouseButton1Click:Connect(function()
        if active then
            stopLoop()
        else
            active = true
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0) -- green when on
            startLoop()
        end
    end)

    -- Reset button state on respawn (but keep toggle if still active)
    LocalPlayer.CharacterAdded:Connect(function()
        if active then
            task.wait(0) -- give character a moment to load
            startLoop()
        else
            stopLoop()
        end
    end)
end
-- ANTI-FLING (Auto, always on)
task.spawn(function()
    while true do
        task.wait(0)  -- fast loop
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
