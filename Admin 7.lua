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
local AutoGearKill = true
local KorbloxToggle = false
local AntiBB8Toggle = false
local FFRemoveToggle = false
local KorbloxBringToggle = false
local DangerousPlayers = {}
local KillQueue = {}
local function GetStickeyStep()
    local existing = Workspace:FindFirstChild("StickyStep")
    if existing then return existing end

    local something
    local connection
    connection = Workspace.ChildAdded:Connect(function(thing)
        task.wait()
        if thing.Name == "StickyStep" then
            something = thing
            connection:Disconnect()
        end
    end)

    repeat task.wait() until something
    return something
end
local PlatformState = {}
local PlatformOriginal = {}

local function saveOriginal(char)
    if PlatformOriginal[char] then return end

    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    local head  = char:FindFirstChild("Head")
    if not (torso and head) then return end

    PlatformOriginal[char] = {
        torsoCF = torso.CFrame,
        headCF  = head.CFrame,
        headSize = head.Size
    }
end

local function restoreOriginal(char)
    local data = PlatformOriginal[char]
    if not data then return end

    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    local head  = char:FindFirstChild("Head")
    if not (torso and head) then return end

    pcall(function()
        head.Anchored = false
        head.CanCollide = true
        head.Size = data.headSize

        torso.CFrame = data.torsoCF
        head.CFrame  = data.headCF
    end)

    PlatformOriginal[char] = nil
end
-- Universal target parts (R6 + R15 + safety checks)
local ImportantPlayerParts = {
    Head = true,
    Torso = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    UpperTorso = true,
    LowerTorso = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
    HumanoidRootPart = true,
    Humanoid = true,
    Health = true,
    ForceField = true
}
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
    GreenHyperLaser = { name = "GreenHyperLaser", id = 1427401206 }
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
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    return char, bp
end

local function safeEquipGear(gear)
    local char, bp = getCharBP()
    if not (char and bp) then return end

    -- Check if already toggled
    local tool = bp:FindFirstChild(gear.name) or char:FindFirstChild(gear.name)
    if tool then return end

    -- Toggle asset ONLY (fast)
    local rem = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ToggleAsset")
    if rem then
        pcall(function()
            rem:InvokeServer(gear.id)
        end)
    end
end

local function equipAllGears()
    for _, gear in pairs(gearTable) do
        safeEquipGear(gear)
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

--------------------------------------------------
-- Cached Gear Remotes
--------------------------------------------------
local cachedDiamondRemote
local cachedDiamondTool

local cachedRocketRemote
local cachedRocketTool

-- Clear caches on respawn
LocalPlayer.CharacterAdded:Connect(function()
    cachedDiamondRemote = nil
    cachedDiamondTool = nil
    cachedRocketRemote = nil
    cachedRocketTool = nil
end)

--------------------------------------------------
-- Cached Diamond Remote
--------------------------------------------------
local function getDiamondRemote()
    -- Return cached if still valid
    if cachedDiamondRemote and cachedDiamondTool and cachedDiamondTool.Parent then
        return cachedDiamondRemote
    end

    local char, bp = getCharBP()
    if not (char and bp) then return nil end

    local sword = bp:FindFirstChild("Diamond Blade Sword") or char:FindFirstChild("Diamond Blade Sword")
    if not sword then return nil end

    local script = sword:FindFirstChildOfClass("Script")
    if not script then return nil end

    local remote = script:FindFirstChildOfClass("RemoteFunction")
    if not remote then return nil end

    -- Cache
    cachedDiamondTool = sword
    cachedDiamondRemote = remote

    return remote
end

--------------------------------------------------
-- Cached Rocket Remote
--------------------------------------------------
local function getRocketRemote(char, bp)
    -- Return cached if still valid
    if cachedRocketRemote and cachedRocketTool and cachedRocketTool.Parent then
        return cachedRocketRemote
    end

    if not (char and bp) then return nil end

    local rocket = bp:FindFirstChild("RocketJumper") or char:FindFirstChild("RocketJumper")
    if not rocket then return nil end

    local remote = rocket:FindFirstChildOfClass("RemoteEvent")
    if not remote then return nil end

    -- Cache
    cachedRocketTool = rocket
    cachedRocketRemote = remote

    return remote
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
            task.wait(0.1)
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
end)
local function combinedAttack(players)
    -- Always re-fetch inside the loop so respawn works
    local char, bp = getCharBP()
    local diamondRemote = getDiamondRemote()
    local rocketRemote = getRocketRemote(char, bp)

    -- If you’re dead, char/bp may be nil, but that’s fine — just skip this tick
    if not char or not bp then return end

    for _, p in ipairs(players) do
        local pChar = p.Character
        if not pChar then continue end

        local hum = pChar:FindFirstChildOfClass("Humanoid")
        local h = hum and hum.Health
        if h == 0 then continue end

        -- Diamond attack
        if diamondRemote and hum then
            pcall(function()
                diamondRemote:InvokeServer(7, hum, math.huge)
            end)
        end

        -- Rocket attack
        if rocketRemote then
            local target =
                pChar:FindFirstChild("HumanoidRootPart")
                or pChar:FindFirstChild("Torso")
                or pChar:FindFirstChild("UpperTorso")
                or pChar:FindFirstChild("Head")
                or pChar:FindFirstChildWhichIsA("BasePart")

            if target then
                local pos = target.Position
                pcall(function()
                    rocketRemote:FireServer(pos, pos)
                    rocketRemote:FireServer(pos + Vector3.new(2, 1, 2), pos)
                    rocketRemote:FireServer(pos + Vector3.new(-2, -1, 2), pos)
                    rocketRemote:FireServer(pos + Vector3.new(2, -1, -2), pos)
                    rocketRemote:FireServer(pos + Vector3.new(-2, 1, -2), pos)
                end)
            end
        end

        -- Spawn rockets
        local spawn = workspace:FindFirstChild(p.Name .. "'s Cloud")
        if spawn and rocketRemote then
            local spawnLoc = spawn:FindFirstChild("SpawnLocation") or spawn:FindFirstChildWhichIsA("BasePart")
            if spawnLoc then
                local sPos = spawnLoc.Position
                pcall(function()
                    rocketRemote:FireServer(sPos + Vector3.new(0,6,0), sPos)
                    rocketRemote:FireServer(sPos + Vector3.new(0,-3,0), sPos)
                    rocketRemote:FireServer(sPos + Vector3.new(2,5,2), sPos)
                    rocketRemote:FireServer(sPos + Vector3.new(-2,5,-2), sPos)
                end)
            end
        end
    end
end
-- Kill Aura Loop (UPDATED with List support)
task.spawn(function()
    while true do
        task.wait(0.1)
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
local GearKeywords = {
    "KorbloxSword",
    "Diamond Blade",
    "Balligator",
    "SpaceSword",
    "RocketJumper",
    "Behemoth",
    "Wormhole",
    "PitFire",
}

local function detectGear(pChar, pBP)
    for _, tool in ipairs(pChar:GetChildren()) do
        if tool:IsA("Tool") then
            for _, keyword in ipairs(GearKeywords) do
                if string.find(tool.Name, keyword) then
                    return true
                end
            end
        end
    end

    if pBP then
        for _, tool in ipairs(pBP:GetChildren()) do
            if tool:IsA("Tool") then
                for _, keyword in ipairs(GearKeywords) do
                    if string.find(tool.Name, keyword) then
                        return true
                    end
                end
            end
        end
    end

    return false
end
-- Tighter rocket slice offsets
local OFFSET_CENTER = Vector3.new(0, 0, 0)
local OFFSET_UP     = Vector3.new(0, 0.1, 0)
local OFFSET_DOWN   = Vector3.new(0, -0.1, 0)

local function fireVerticalSlice(fireEvent, pos)
    pcall(function() fireEvent:FireServer(pos + OFFSET_CENTER, pos) end)
    pcall(function() fireEvent:FireServer(pos + OFFSET_UP, pos) end)
    pcall(function() fireEvent:FireServer(pos + OFFSET_DOWN, pos) end)
end
task.spawn(function()
    while task.wait(0.05) do
        if not AutoGearKill then continue end

        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            if PlayerIgnoreList[player.Name] then continue end

            local pChar = player.Character
            if not pChar then
                DangerousPlayers[player] = nil
                continue
            end

            local pBP = player:FindFirstChild("Backpack")

            if detectGear(pChar, pBP) then
                DangerousPlayers[player] = true
            else
                DangerousPlayers[player] = nil
            end
        end
    end
end)
task.spawn(function()
    while RunService.RenderStepped:Wait() do
        if not AutoGearKill then continue end

        local myChar = LocalPlayer.Character
        local myBp   = LocalPlayer:FindFirstChild("Backpack")
        if not (myChar and myBp) then continue end

        local diamondRemote = getDiamondRemote()
        local fireEvent     = getRocketRemote(myChar, myBp)
        if not (diamondRemote or fireEvent) then continue end

        for player in pairs(DangerousPlayers) do
            local pChar = player.Character
            if not pChar then continue end
        if h == 0 then
            continue
        end
            local head = pChar:FindFirstChild("Head")

            -- Diamond kill
            if diamondRemote then
                pcall(function()
                    diamondRemote:InvokeServer(7, hum, math.huge)
                end)
            end

            -- Rocket slice
            if fireEvent and head then
                fireVerticalSlice(fireEvent, head.Position)
            end
        end
    end
end)
-- Anti-BB8 Crasher Loop (STABLE - No Anchor, Teleport in Front)
task.spawn(function()
    while true do
        task.wait(0.1)
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
local function getPlatformShooter()
    local Character, Backpack = getCharBP()
    if not (Character and Backpack) then return end

    local gun = Backpack:FindFirstChild("StepGun") or Character:FindFirstChild("StepGun")
    if not gun then return end

    local shoot = gun:FindFirstChild("Shoot") or gun:FindFirstChildOfClass("RemoteEvent")
    if not shoot then return end

    return gun, shoot
end
local function IfNotTagAddTag(thing, Tag)
    if not CollectionService:HasTag(thing, Tag) then
        CollectionService:AddTag(thing, Tag)
    end
end
function Platform(TargetCharacter)
    if not TargetCharacter then return end

    local Character, Backpack = getCharBP()
    if not (Character and Backpack) then return end

    local PlatformGun, ShootEvent = getPlatformShooter()
    if not (PlatformGun and ShootEvent) then return end

    local myTorso = Character:FindFirstChild("Torso") or Character:FindFirstChild("UpperTorso")
    if not myTorso then return end

    local targetTorso =
        TargetCharacter:FindFirstChild("Torso")
        or TargetCharacter:FindFirstChild("UpperTorso")

    local targetHead = TargetCharacter:FindFirstChild("Head")
    if not (targetTorso and targetHead) then return end

    local targetPosition = myTorso.Position + Vector3.new(0, 8, 0)
    local originalSize = targetHead.Size

    -- ===============================
    -- APPLY PLATFORM (only once)
    -- ===============================
    if not PlatformState[TargetCharacter] then

        PlatformState[TargetCharacter] = true
        saveOriginal(TargetCharacter)

        task.spawn(function()
            IfNotTagAddTag(TargetCharacter, "Platform")

            targetHead.Anchored = true
            targetHead.CanCollide = false

            if originalSize ~= Vector3.new(2048,2048,2048) then
                targetHead.Size = Vector3.new(2048,2048,2048)
            end

            targetTorso.CFrame = CFrame.new(targetPosition)
            targetHead.CFrame  = CFrame.new(targetPosition)
        end)

        if PlatformGun.Parent ~= Character then
            PlatformGun.Parent = Character
            task.wait()
        end

        pcall(function()
            ShootEvent:FireServer(targetTorso.Position)
        end)
local sticky = GetStickeyStep()
if sticky and sticky:FindFirstChild("BodyForce") then
    sticky.BodyForce.Force = Vector3.new(-math.huge, -math.huge, -math.huge)
end
local ReportRemote = game.ReplicatedStorage:FindFirstChild("Report") 
if ReportRemote then pcall(function() ReportRemote:FireServer(CFrame.new(0/0, 0/0, 0/0)) end) end
    -- ===============================
    -- REMOVE PLATFORM (toggle OFF)
    -- ===============================
    else
        PlatformState[TargetCharacter] = false
        restoreOriginal(TargetCharacter)
    end
end

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
local function createLoopButton(text, callback, yPos, autoStart)
    local active = autoStart or false

    if not Frame then return end
    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(0, 400, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.Text = text .. (active and " [ON]" or " [OFF]")
    btn.BackgroundColor3 = active and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.TextScaled = true

    -- Ultra-fast loop: no health checks, no humanoid lookups
    task.spawn(function()
        while btn.Parent do
            RunService.RenderStepped:Wait()

            if active then
                local filtered = table.create(8)
                for _, p in ipairs(getSelectedPlayers()) do
                    local char = p.Character
                    if char then
                        filtered[#filtered+1] = p
                    end
                end

                if callback and #filtered > 0 then
                    callback(filtered)
                end
            end
        end
    end)

    btn.MouseButton1Click:Connect(function()
        active = not active
        btn.Text = text .. (active and " [ON]" or " [OFF]")
        btn.BackgroundColor3 = active and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)
    end)

    return btn
end
-- Example usage
createLoopButton("Loop Kill+Explode", combinedAttack, 250, true)
-- Platform loop toggle (targets selected players)
createLoopButton("Loop Platform", function(players)
    for _, p in ipairs(players) do
        local char = p.Character
        if char then
            Platform(char) -- call your Platform function on each selected player's character
        end
    end
end, 290, false) -- autoStart = false (set true if you want it auto-on)
-- 🔘 GUI toggle button (same style as your example)
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
                RunService.RenderStepped:Wait() -- faster: every frame

                local myChar, _ = getCharBP()
                if not myChar then continue end

                local equippedTool = myChar:FindFirstChildOfClass("Tool")
                local toolHandle = equippedTool and equippedTool:FindFirstChild("Handle")
                if not toolHandle then continue end

                local TargetCFrame = toolHandle.CFrame * CFrame.new(0, 0, 1)
                local targets = getSelectedPlayers()

                for _, p in ipairs(targets) do
                    local pChar = p.Character
                    if not pChar then continue end

                    local hum = pChar:FindFirstChildOfClass("Humanoid")
                    if not hum or hum.Health <= 0 then continue end

                    -- Grab key parts (excluding HRP for stability)
                    local partsToBring = {
                        pChar:FindFirstChild("Torso"),
                        pChar:FindFirstChild("UpperTorso"),
                        pChar:FindFirstChild("Head")
                    }

                    for _, part in ipairs(partsToBring) do
                        if part and part.Parent then
                            pcall(function()
                                -- slam part directly to tool handle position
                                part.CFrame = TargetCFrame
                            end)
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
        task.wait(0.5) 

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
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local ARCHOUR_ID = 49491808 -- asset ID for StaffOfPitFire

-- Anchored check
local function isCharacterAnchored()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, partName in ipairs({"Torso","HumanoidRootPart"}) do
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

-- Get Archour tool (StaffOfPitFire)
local function getArchourTool()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    if not bp or not char then return nil end
    return bp:FindFirstChild("StaffOfPitFire") or char:FindFirstChild("StaffOfPitFire")
end

-- Equip, fire, then unequip quickly
local function useArchourOnce()
    if isCharacterAnchored() then return end

    local toggle = getToggleAsset()
    if not toggle then return end

    local char, bp = LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")
    if not (char and bp) then return end

    -- Spawn if missing
    local tool = getArchourTool()
    if not tool then
        pcall(function() toggle:InvokeServer(ARCHOUR_ID) end)
        local timeout = 0.2
        while not tool and timeout > 0 do
            task.wait(0.05)
            tool = getArchourTool()
            timeout -= 0.05
        end
    end
    if not tool then return end

    -- Equip
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum:EquipTool(tool) else tool.Parent = char end

    -- Fire immediately
    pcall(function() tool:Activate() end)

    -- Quick unequip
    task.wait(0.1)
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

-- Loop runner (aggressive timing)
local function startLoop()
    task.spawn(function()
        while active do
            if isCharacterAnchored() then
                task.wait(0.2)
            else
                useArchourOnce()
                task.wait(0.15) -- rapid fire
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
-- Self-Healing God Self Loop (never needs re-enable)
do
    local active = true
    local loopConnection

    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(0, 400, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, 410)
    btn.Text = "Toggle God Self"
    btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true

    -- Cached references
    local cachedRemote = nil
    local cachedHum = nil

    -- Rebuild cache every time something changes
    local function rebuildCache()
        local char = LocalPlayer.Character
        if not char then
            cachedRemote = nil
            cachedHum = nil
            return
        end

        cachedHum = char:FindFirstChildOfClass("Humanoid")

        local sword =
            LocalPlayer.Backpack:FindFirstChild("Diamond Blade Sword")
            or char:FindFirstChild("Diamond Blade Sword")

        if sword then
            local script = sword:FindFirstChildOfClass("Script")
            if script then
                cachedRemote = script:FindFirstChildOfClass("RemoteFunction")
            end
        end
    end

    -- Fire once using cached references
    local function fireOnce()
        if cachedRemote and cachedHum then
            pcall(function()
                cachedRemote:InvokeServer(7, cachedHum, -math.huge)
            end)
        end
    end

    -- Loop that auto-repairs itself
    local function startLoop()
        if loopConnection then loopConnection:Disconnect() end

        loopConnection = RunService.RenderStepped:Connect(function()
            if not active then return end

            -- Auto-repair cache if anything is missing
            if not cachedRemote or not cachedHum then
                rebuildCache()
            end

            fireOnce()
        end)
    end

    local function stopLoop()
        if loopConnection then
            loopConnection:Disconnect()
            loopConnection = nil
        end
        active = false
        btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    end

    btn.MouseButton1Click:Connect(function()
        if active then
            stopLoop()
        else
            active = true
            btn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            rebuildCache()
            startLoop()
        end
    end)

    -- Auto-repair on respawn
    LocalPlayer.CharacterAdded:Connect(function()
        if active then
            rebuildCache()
            fireOnce()
            startLoop()
        end
    end)

    -- Auto-repair when character is removed
    LocalPlayer.CharacterRemoving:Connect(function()
        cachedRemote = nil
        cachedHum = nil
    end)

    -- Start immediately
    if active then
        rebuildCache()
        fireOnce()
        startLoop()
    end
end
-- ANTI-FLING (Auto, always on, no HumanoidRootPart dependency)
task.spawn(function()
    while true do
        task.wait() -- fast loop
        local char = LocalPlayer.Character
        if not char then continue end

        -- Scan all parts in character
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                pcall(function()
                    part.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    part.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end)
            end
        end
    end
end)
-- Helper: get bringable parts
local function getBringableParts(pChar)
    local parts = {}
    for _, child in ipairs(pChar:GetChildren()) do
        if child:IsA("BasePart") then
            -- Skip accessories/hats
            if child.Name ~= "Accessory" and child.Name ~= "Hat" then
                table.insert(parts, child)
            end
        end
    end
    -- Fallback: if only HRP/Head exist, ensure they’re included
    if #parts == 0 then
        local head = pChar:FindFirstChild("Head")
        local hrp  = pChar:FindFirstChild("HumanoidRootPart")
        if head then table.insert(parts, head) end
        if hrp then table.insert(parts, hrp) end
    end
    return parts
end

-- Korblox Bring Button
local KorbloxBringToggle = false
local btnKorbloxBring = Instance.new("TextButton", Frame)
btnKorbloxBring.Size = UDim2.new(0,400,0,30)
btnKorbloxBring.Position = UDim2.new(0,10,0,730)
btnKorbloxBring.Text = "Toggle Korblox Bring"
btnKorbloxBring.BackgroundColor3 = Color3.fromRGB(255,0,0)
btnKorbloxBring.TextColor3 = Color3.fromRGB(255,255,255)
btnKorbloxBring.TextScaled = true

btnKorbloxBring.MouseButton1Click:Connect(function()
    KorbloxBringToggle = not KorbloxBringToggle
    btnKorbloxBring.BackgroundColor3 = KorbloxBringToggle and Color3.fromRGB(0,200,0) or Color3.fromRGB(255,0,0)

    if KorbloxBringToggle then
        task.spawn(function()
            while KorbloxBringToggle do
                RunService.RenderStepped:Wait()

                local myChar, bp = getCharBP()
                if not myChar then continue end

                -- Auto-equip KorbloxSwordAndShield
                local sword = myChar:FindFirstChild("KorbloxSwordAndShield")
                if not sword and bp then
                    local swordInBP = bp:FindFirstChild("KorbloxSwordAndShield")
                    if swordInBP then
                        myChar:FindFirstChildOfClass("Humanoid"):EquipTool(swordInBP)
                    end
                end
                sword = myChar:FindFirstChild("KorbloxSwordAndShield")
                local handle = sword and sword:FindFirstChild("Handle")
                if not (sword and handle) then continue end

                -- Bring parts for each target
                for _, p in ipairs(getSelectedPlayers()) do
                    local pChar = p.Character
                    if not pChar then continue end
                    local hum = pChar:FindFirstChildOfClass("Humanoid")
                    if not hum or hum.Health <= 0 then continue end

                    local partsToBring = getBringableParts(pChar)
                    for _, part in ipairs(partsToBring) do
                        pcall(function()
                            part.CFrame = handle.CFrame
                        end)
                    end
                end

                -- Auto swing
                pcall(function() sword:Activate() end)
            end
        end)
    end
end)
-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

-- Globals
local activeClone = nil
local BaseProtectToggle = false
local hitboxSize = Vector3.new(60, 60, 60) -- detection box size

-- Helper: Use Diamond Blade Sword Remote
local function useDiamondSwordOnPlayer(targetChar)
    local Character = LocalPlayer.Character
    local Backpack = LocalPlayer:FindFirstChild("Backpack")
    if not (Character and Backpack) then return end

    -- Find sword
    local sword = Backpack:FindFirstChild("DiamondBladeSword") or Character:FindFirstChild("DiamondBladeSword")
    if not sword then return end

    -- Equip if needed
    if sword.Parent == Backpack then
        sword.Parent = Character
        task.wait()
    end

    -- Find remote
    local diamondRemote = sword:FindFirstChild("Remote") or sword:FindFirstChildOfClass("RemoteFunction")
    if not diamondRemote then return end

    -- Get target humanoid
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- Fire remote
    pcall(function()
        diamondRemote:InvokeServer(7, hum, math.huge)
    end)
end

-- Helper: Use KorbloxSwordAndShield by hovering parts
local function useKorbloxOnPlayer(targetChar)
    local Character = LocalPlayer.Character
    local Backpack = LocalPlayer:FindFirstChild("Backpack")
    if not (Character and Backpack) then return end

    local tool = Backpack:FindFirstChild("KorbloxSwordAndShield") or Character:FindFirstChild("KorbloxSwordAndShield")
    if not tool then return end

    if tool.Parent == Backpack then
        tool.Parent = Character
        task.wait()
    end

    local handle = tool:FindFirstChild("Handle") or tool:FindFirstChild("Stick")
    if not handle then return end

    for _, partName in ipairs({"Torso","UpperTorso","Head"}) do
        local targetPart = targetChar:FindFirstChild(partName)
        if targetPart then
            targetPart.CFrame = handle.CFrame + Vector3.new(0, 2, 0)
        end
    end
end

-- Base Protection function
local function baseprotection(myPlayer)
    -- Spawn clone if not exists
    if not activeClone then
        local cloudName = myPlayer.Name .. "'s Cloud"
        local Cloud = Workspace:FindFirstChild(cloudName)
        if not Cloud then return end
        local union = Cloud:FindFirstChild("Union")
        if not union then return end

        activeClone = union:Clone()
        activeClone.Parent = Workspace
        activeClone.Name = myPlayer.Name .. "'s CloneUnion"
        activeClone.CanCollide = false
        activeClone.CanQuery = false
        activeClone.Transparency = 1
        activeClone.Size = Vector3.new(60, 60, 60)
        activeClone.CFrame = union.CFrame
    end

    -- Scan players inside hitbox
    local param = OverlapParams.new()
    param.FilterDescendantsInstances = { activeClone }
    param.FilterType = Enum.RaycastFilterType.Exclude

    local parts = Workspace:GetPartBoundsInBox(activeClone.CFrame, hitboxSize, param)
    local seenPlayers = {}

    for _, part in ipairs(parts) do
        local char = part:FindFirstAncestorOfClass("Model")
        local player = char and Players:GetPlayerFromCharacter(char)

        if player and player ~= LocalPlayer and not seenPlayers[player] then
            seenPlayers[player] = true
            task.spawn(function()
                if char then
                    useDiamondSwordOnPlayer(char)
                    useKorbloxOnPlayer(char)
                end
            end)
        end
    end
end

local btnBaseProtect = Instance.new("TextButton", Frame)
btnBaseProtect.Size = UDim2.new(0, 400, 0, 30)
btnBaseProtect.Position = UDim2.new(0, 10, 0, 770)
btnBaseProtect.Text = "Toggle Base Protection"
btnBaseProtect.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
btnBaseProtect.TextColor3 = Color3.fromRGB(255, 255, 255)
btnBaseProtect.TextScaled = true

btnBaseProtect.MouseButton1Click:Connect(function()
    BaseProtectToggle = not BaseProtectToggle
    btnBaseProtect.BackgroundColor3 = BaseProtectToggle and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)

    if not BaseProtectToggle and activeClone then
        activeClone:Destroy()
        activeClone = nil
    end
end)

-- Base Protection Loop
task.spawn(function()
    while true do
        task.wait(0.1)
        if BaseProtectToggle then
            baseprotection(LocalPlayer)
        end
    end
end)