-- FIRE PIT STAFF TOGGLE BUTTON GUI
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PITFIRE_ID = 49491808

-- Check if character is anchored
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

-- Get PitFire tool
local function getPitFireTool()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    if not bp or not char then return nil end
    return bp:FindFirstChild("StaffOfPitFire") or char:FindFirstChild("StaffOfPitFire")
end

-- Equip, auto‑fire, then unequip
local function usePitFireOnce()
    if isCharacterAnchored() then return end

    local toggle = getToggleAsset()
    if not toggle then return end

    local tool = getPitFireTool()

    -- Spawn if missing (poll quickly, timeout 0.5s)
    if not tool then
        pcall(function() toggle:InvokeServer(PITFIRE_ID) end)
        local timeout = 0.5
        while not tool and timeout > 0 do
            task.wait(0.05)
            tool = getPitFireTool()
            timeout -= 0.05
        end
    end

    if not tool then return end

    -- Equip
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:EquipTool(tool) else tool.Parent = LocalPlayer.Character end
    task.wait(0.15) -- equip delay

    -- Auto‑fire
    pcall(function() tool:Activate() end)
    task.wait(0.3) -- fire window

    -- Unequip/remove via ToggleAsset
    pcall(function() toggle:InvokeServer(PITFIRE_ID) end)
end

-- GUI Creation
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ScreenGui = Instance.new("ScreenGui", PlayerGui)
ScreenGui.Name = "FirePitToggleGui"
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 180, 0, 60)
MainFrame.Position = UDim2.new(0, 50, 0, 50)
MainFrame.BackgroundColor3 = Color3.fromRGB(50,50,50)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true

local Button = Instance.new("TextButton", MainFrame)
Button.Size = UDim2.new(1, -10, 1, -10)
Button.Position = UDim2.new(0, 5, 0, 5)
Button.Text = "Fire Pit Staff: OFF"
Button.BackgroundColor3 = Color3.fromRGB(133,80,255)
Button.TextColor3 = Color3.fromRGB(255,255,255)
Button.Font = Enum.Font.SourceSansBold
Button.TextScaled = true

local active = false
local persistActive = false

-- Loop runner
local function startLoop()
    task.spawn(function()
        while active do
            if isCharacterAnchored() then
                task.wait(0.4) -- pause while anchored
            else
                usePitFireOnce()
                task.wait(0.5) -- cycle delay
            end
        end
    end)
end

-- Toggle button
Button.MouseButton1Click:Connect(function()
    active = not active
    persistActive = active
    Button.Text = active and "Fire Pit Staff: ON" or "Fire Pit Staff: OFF"

    if active then
        startLoop()
    else
        -- Unequip/remove staff only when turning OFF
        local toggle = getToggleAsset()
        if toggle then pcall(function() toggle:InvokeServer(PITFIRE_ID) end) end
    end
end)

-- Resume after respawn (wait for Humanoid + Backpack)
LocalPlayer.CharacterAdded:Connect(function(char)
    if persistActive then
        char:WaitForChild("Humanoid")
        LocalPlayer:WaitForChild("Backpack")
        task.wait(0.5) -- short delay to avoid "two tries"
        active = true
        Button.Text = "Fire Pit Staff: ON"
        startLoop()
    end
end)