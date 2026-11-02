-- ============================================================
-- Blox Fruits Hub — Delta X Edition (main.lua)
-- Host: https://raw.githubusercontent.com/{USER}/{REPO}/refs/heads/main/main.lua
-- Loader: loadstring(game:HttpGet("URL_ABOVE"))()
--
-- Target: Roblox Blox Fruits
--   PlaceId 2753915549 = Sea 1
--   PlaceId 4442272183 = Sea 2
--   PlaceId 7449423635 = Sea 3
-- Executor: Delta X (Android / PC)
--
-- Delta X compatibility layer:
--   - gethui() cho UI parent (fallback game.CoreGui)
--   - request() cho HTTP (fallback game:HttpGet)
--   - pcall wrap setfpscap, setclipboard, isnetworkowner
--   - Orion Library (mobile-friendly)
--
-- Cach dung (Delta X):
--   1. Mo Delta X app
--   2. Vao game Blox Fruits
--   3. Paste script vao Delta X editor
--   4. Tap Execute
-- ============================================================

-- ============ DELTA X COMPAT LAYER ============
-- HTTP request: uu tien request() (Delta X native), fallback HttpGet
local function httpGet(url)
    if type(request) == "function" then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok and res and res.Body then
            return res.Body
        end
    end
    return game:HttpGet(url)
end

-- UI parent: uu tien gethui(), fallback CoreGui
local function getUIParent()
    if type(gethui) == "function" then
        local ok, parent = pcall(gethui)
        if ok and parent then return parent end
    end
    return game:GetService("CoreGui")
end

-- setclipboard safe
local function setClip(text)
    pcall(function()
        if type(setclipboard) == "function" then
            setclipboard(text)
        end
    end)
end

-- setfpscap safe
local function setFps(val)
    pcall(function()
        if type(setfpscap) == "function" then
            setfpscap(val)
        end
    end)
end

-- isnetworkowner safe (Delta X co the khong co)
local function isOwner(part)
    if type(isnetworkowner) == "function" then
        local ok, res = pcall(isnetworkowner, part)
        if ok then return res end
    end
    local hrp = getHRP and getHRP() or nil
    if hrp then
        return (part.Position - hrp.Position).Magnitude <= 200
    end
    return false
end

-- ============ CONFIG ============
getgenv().Config = {
    TweenSpeed     = 350,
    SelectedWeapon = "Melee",
    SelectIsland   = "",
    Team           = "Pirates",
    WalkSpeedVal   = 200,
    JumpPowerVal   = 200,
}

-- ============ SERVICES ============
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local CoreGui           = game:GetService("CoreGui")

-- ============ WORLD DETECT ============
local PlaceId = game.PlaceId
local World1, World2, World3 = false, false, false
if PlaceId == 2753915549 then
    World1 = true
elseif PlaceId == 4442272183 then
    World2 = true
elseif PlaceId == 7449423635 then
    World3 = true
end

-- ============ WAIT LOAD + TEAM ============
if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait() until LocalPlayer:FindFirstChild("DataLoaded")
getgenv().Team = getgenv().Team or "Pirates"

if LocalPlayer.PlayerGui:FindFirstChild("Main (minimal)") then
    repeat
        task.wait()
        ReplicatedStorage:WaitForChild("Remotes").CommF_:InvokeServer("SetTeam", getgenv().Team)
        task.wait(3)
    until not LocalPlayer.PlayerGui:FindFirstChild("Main (minimal)")
end

-- ============ HRP HELPER (forward declare cho isOwner) ============
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ============ CORE UTILS ============
local function getRoot(character)
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
end

-- Tween-based teleport (an toan cho Delta X, khong bi Hyperion flag)
local TP_ACTIVE = false
local function topos(targetCFrame)
    if typeof(targetCFrame) == "Vector3" then
        targetCFrame = CFrame.new(targetCFrame)
    end
    local hrp = getHRP()
    if not hrp then return end
    local char = LocalPlayer.Character
    if not char then return end

    local part = char:FindFirstChild("PartTele")
    if not part then
        part = Instance.new("Part")
        part.Size = Vector3.new(10, 1, 10)
        part.Name = "PartTele"
        part.Anchored = true
        part.Transparency = 1
        part.CanCollide = false
        part.Parent = char
    end
    part.CFrame = hrp.CFrame

    local dist  = (targetCFrame.Position - hrp.Position).Magnitude
    local speed = getgenv().Config.TweenSpeed
    if dist <= 300 then speed = speed * 4 end

    local tween = TweenService:Create(
        part,
        TweenInfo.new(dist / speed, Enum.EasingStyle.Linear),
        { CFrame = targetCFrame }
    )
    tween:Play()

    TP_ACTIVE = true
    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed then
            hrp.CFrame = CFrame.new(part.CFrame.Position.X, targetCFrame.Position.Y, part.CFrame.Position.Z)
            if part and part.Parent then part:Destroy() end
            TP_ACTIVE = false
        end
    end)
end

local function stopTeleport()
    TP_ACTIVE = false
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("PartTele") then
        char.PartTele:Destroy()
    end
end

local function EquipWeapon(name)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local char     = LocalPlayer.Character
    if not backpack or not char then return end
    local tool = backpack:FindFirstChild(name)
    if tool then
        char.Humanoid:EquipTool(tool)
    end
end

local function EquipByType(weaponType)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end
    for _, tool in pairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == weaponType then
            LocalPlayer.Character.Humanoid:EquipTool(tool)
            return tool.Name
        end
    end
end

-- Server hop — dung request() cho Delta X
local function Hop()
    local placeId = game.PlaceId
    local cursor  = ""
    local visited = {}

    local function tpReturner()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end

        local body
        if type(request) == "function" then
            local ok, res = pcall(request, { Url = url, Method = "GET" })
            if ok and res and res.Body then
                body = HttpService:JSONDecode(res.Body)
            end
        else
            local ok, raw = pcall(function() return game:HttpGet(url) end)
            if ok and raw then
                body = HttpService:JSONDecode(raw)
            end
        end
        if not body or not body.data then return end

        if body.nextPageCursor and body.nextPageCursor ~= "null" then
            cursor = body.nextPageCursor
        end

        for _, server in pairs(body.data) do
            if tonumber(server.maxPlayers) > tonumber(server.playing) then
                local id = tostring(server.id)
                local fresh = true
                for _, v in pairs(visited) do
                    if v == id then fresh = false break end
                end
                if fresh then
                    table.insert(visited, id)
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(placeId, id, LocalPlayer)
                    end)
                    task.wait(4)
                end
            end
        end
    end

    pcall(tpReturner)
end

-- ============ ESP ============
local ESP_ID = math.random(1, 1000000)

local function makeESP(parent, getTextFn, getColorFn)
    if not parent or parent.Parent == nil then return end
    local existing = parent:FindFirstChild("NameEsp" .. ESP_ID)
    if existing then
        existing.TextLabel.Text = getTextFn()
        return
    end
    local bb = Instance.new("BillboardGui")
    bb.Name              = "NameEsp" .. ESP_ID
    bb.Adornee           = parent
    bb.AlwaysOnTop       = true
    bb.Size              = UDim2.new(1, 200, 1, 30)
    bb.ExtentsOffset     = Vector3.new(0, 1, 0)
    bb.Parent            = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.Font                   = Enum.Font.GothamSemibold
    lbl.TextSize               = 14
    lbl.TextColor3             = getColorFn()
    lbl.TextStrokeTransparency = 0.5
    lbl.Text                   = getTextFn()
    lbl.Parent                 = bb
end

local function clearESP(parent)
    if not parent then return end
    local esp = parent:FindFirstChild("NameEsp" .. ESP_ID)
    if esp then esp:Destroy() end
end

-- ============ FLY ============
local FLYING  = false
local flyConn = nil

local function stopFly()
    FLYING = false
    local hrp = getHRP()
    if hrp then
        if hrp:FindFirstChild("FlyVel")   then hrp.FlyVel:Destroy() end
        if hrp:FindFirstChild("FlyGyro")  then hrp.FlyGyro:Destroy() end
        local hum = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        if hum then hum.PlatformStand = false end
    end
    if flyConn then flyConn:Disconnect() flyConn = nil end
end

local function startFly()
    stopFly()
    FLYING = true
    local hrp = getHRP()
    if not hrp then return end

    local vel = Instance.new("BodyVelocity")
    vel.Name     = "FlyVel"
    vel.MaxForce = Vector3.new(0, 0, 0)
    vel.Velocity = Vector3.new(0, 0, 0)
    vel.Parent   = hrp

    local gyro = Instance.new("BodyGyro")
    gyro.Name     = "FlyGyro"
    gyro.MaxTorque = Vector3.new(8999999488, 8999999488, 8999999488)
    gyro.P         = 1000
    gyro.D         = 50
    gyro.Parent    = hrp

    local cam  = Workspace.CurrentCamera
    local ctrl = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

    flyConn = RunService.RenderStepped:Connect(function()
        local h = getHRP()
        if not h or not FLYING then return end
        local hum = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        if hum then hum.PlatformStand = true end

        gyro.CFrame = cam.CFrame
        local mv   = ctrl:GetMoveVector()
        local speed = 50
        local v     = Vector3.new()
        if mv.X > 0 then v = v + cam.CFrame.RightVector * mv.X * speed * 50 end
        if mv.X < 0 then v = v + cam.CFrame.RightVector * mv.X * speed * 50 end
        if mv.Z > 0 then v = v - cam.CFrame.LookVector * mv.Z * speed * 50 end
        if mv.Z < 0 then v = v - cam.CFrame.LookVector * mv.Z * speed * 50 end
        if v.Magnitude > 350 then v = v.Unit * 350 end

        vel.MaxForce = Vector3.new(8999999488, 8999999488, 8999999488)
        vel.Velocity = v
    end)
end

-- ============ ORION LIBRARY (mobile-friendly cho Delta X) ============
local OrionLib = loadstring(httpGet("https://raw.githubusercontent.com/shlexware/Orion/main/source"))()

local Window = OrionLib:MakeWindow({
    Name         = "Blox Fruits Hub | Delta X",
    HidePremium  = true,
    SaveConfig   = true,
    ConfigFolder = "BloxHubDeltaX"
})

-- ============ TAB: FARM ============
local TabFarm  = Window:MakeTab({ Name = "Farm",   Icon = "rbxassetid://4370305131", PremiumOnly = false })
local SectionF = TabFarm:AddSection({ Name = "Auto Farm" })

SectionF:AddToggle({
    Name     = "Auto Farm Level (nearest mob)",
    Default  = false,
    Callback = function(state) getgenv().AutoFarmLevel = state end
})

task.spawn(function()
    while task.wait() do
        pcall(function()
            if not getgenv().AutoFarmLevel then return end
            local hrp = getHRP()
            if not hrp then return end

            local closest, minDist = nil, 2500
            for _, enemy in pairs(Workspace.Enemies:GetChildren()) do
                if enemy:FindFirstChild("HumanoidRootPart")
                   and enemy:FindFirstChild("Humanoid")
                   and enemy.Humanoid.Health > 0 then
                    local d = (enemy.HumanoidRootPart.Position - hrp.Position).Magnitude
                    if d < minDist then
                        closest, minDist = enemy, d
                    end
                end
            end

            if closest then
                EquipByType(getgenv().Config.SelectedWeapon)
                closest.HumanoidRootPart.CanCollide = false
                closest.Humanoid.WalkSpeed           = 0
                if closest:FindFirstChild("Head") then
                    closest.Head.CanCollide = false
                end
                topos(closest.HumanoidRootPart.CFrame * CFrame.new(0, 25, 0))
                if sethiddenproperty then
                    sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
                end
            end
        end)
    end
end)

SectionF:AddToggle({
    Name     = "Auto Haki (Buso)",
    Default  = false,
    Callback = function(state) getgenv().AutoHaki = state end
})

task.spawn(function()
    while task.wait(0.1) do
        if getgenv().AutoHaki then
            pcall(function()
                if not LocalPlayer.Character:FindFirstChild("HasBuso") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
                end
            end)
        end
    end
end)

SectionF:AddToggle({
    Name     = "Auto Ken (Observation)",
    Default  = false,
    Callback = function(state) getgenv().AutoKen = state end
})

task.spawn(function()
    while task.wait(0.1) do
        if getgenv().AutoKen then
            pcall(function()
                ReplicatedStorage.Remotes.CommE:FireServer("Ken", true)
            end)
        end
    end
end)

SectionF:AddToggle({
    Name     = "Auto Click (attack spam)",
    Default  = false,
    Callback = function(state) getgenv().AutoClick = state end
})

task.spawn(function()
    while task.wait() do
        if getgenv().AutoClick then
            pcall(function()
                if type(game:GetService("VirtualInputManager").SendMouseButtonEvent) == "function" then
                    game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.wait()
                    game:GetService("VirtualInputManager"):SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end
            end)
        end
    end
end)

SectionF:AddDropdown({
    Name     = "Select Weapon Type",
    Default  = "Melee",
    Options  = { "Melee", "Sword", "Gun", "Fruit" },
    Callback = function(val) getgenv().Config.SelectedWeapon = val end
})

SectionF:AddDropdown({
    Name     = "Bring Mob Mode",
    Default  = "Normal",
    Options  = { "Low", "Normal", "Super Bring" },
    Callback = function(val)
        local map = { Low = 100, Normal = 200, ["Super Bring"] = 300 }
        getgenv().Config.BringMode = map[val] or 200
    end
})

-- ============ TAB: VISUAL ============
local TabVis = Window:MakeTab({ Name = "Visual", Icon = "rbxassetid://4370305131", PremiumOnly = false })

TabVis:AddToggle({
    Name     = "ESP Player",
    Default  = false,
    Callback = function(state) getgenv().ESPPlayer = state end
})

task.spawn(function()
    while task.wait(0.1) do
        pcall(function()
            if getgenv().ESPPlayer then
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Head") then
                        local hrp = getHRP()
                        if hrp then
                            makeESP(
                                p.Character.Head,
                                function()
                                    local d = math.floor((hrp.Position - p.Character.Head.Position).Magnitude / 3)
                                    local hp = math.floor(p.Character.Humanoid.Health * 100 / p.Character.Humanoid.MaxHealth)
                                    return p.Name .. " | " .. d .. "m | HP " .. hp .. "%"
                                end,
                                function()
                                    if p.Team ~= LocalPlayer.Team then
                                        return Color3.fromRGB(255, 80, 80)
                                    else
                                        return Color3.fromRGB(80, 255, 80)
                                    end
                                end
                            )
                        end
                    end
                end
            else
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character then
                        clearESP(p.Character:FindFirstChild("Head"))
                    end
                end
            end
        end)
    end
end)

TabVis:AddToggle({
    Name     = "ESP Island",
    Default  = false,
    Callback = function(state) getgenv().ESPIsland = state end
})

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            for _, loc in pairs(Workspace._WorldOrigin.Locations:GetChildren()) do
                local esp = loc:FindFirstChild("IslandEsp")
                if getgenv().ESPIsland then
                    if not esp then
                        local bb = Instance.new("BillboardGui")
                        bb.Name            = "IslandEsp"
                        bb.Adornee         = loc
                        bb.AlwaysOnTop     = true
                        bb.Size            = UDim2.new(0, 200, 0, 50)
                        bb.StudsOffset     = Vector3.new(0, 2.5, 0)
                        bb.Parent          = loc
                        local lbl = Instance.new("TextLabel")
                        lbl.BackgroundTransparency = 1
                        lbl.Size                   = UDim2.new(1, 0, 1, 0)
                        lbl.Font                   = Enum.Font.GothamBold
                        lbl.TextSize               = 14
                        lbl.TextColor3             = Color3.fromRGB(255, 255, 255)
                        lbl.TextStrokeTransparency = 0.5
                        lbl.Parent                 = bb
                    end
                    local hrp = getHRP()
                    if hrp then
                        local d = math.floor((hrp.Position - loc.Position).Magnitude / 10)
                        loc.IslandEsp.TextLabel.Text = loc.Name .. "\n[" .. d .. "]"
                    end
                else
                    if esp then esp:Destroy() end
                end
            end
        end)
    end
end)

TabVis:AddToggle({
    Name     = "Remove Fog",
    Default  = false,
    Callback = function(state) getgenv().RemoveFog = state end
})

task.spawn(function()
    while task.wait(1) do
        if getgenv().RemoveFog then
            pcall(function() Lighting.FogEnd = 8999999488 end)
        else
            pcall(function() Lighting.FogEnd = 2500 end)
        end
    end
end)

TabVis:AddToggle({
    Name     = "White Screen (FPS boost)",
    Default  = false,
    Callback = function(state)
        getgenv().WhiteScreen = state
        RunService:Set3dRenderingEnabled(not state)
    end
})

-- ============ TAB: LOCAL ============
local TabLocal = Window:MakeTab({ Name = "Local", Icon = "rbxassetid://4370305131", PremiumOnly = false })

TabLocal:AddToggle({
    Name     = "Fly",
    Default  = false,
    Callback = function(state)
        if state then startFly() else stopFly() end
    end
})

TabLocal:AddToggle({
    Name     = "NoClip",
    Default  = false,
    Callback = function(state) getgenv().NoClip = state end
})

RunService.Stepped:Connect(function()
    if getgenv().NoClip then
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
    end
end)

TabLocal:AddToggle({
    Name     = "Walk Speed",
    Default  = false,
    Callback = function(state) getgenv().WalkSpeedOn = state end
})

TabLocal:AddDropdown({
    Name     = "Speed Value",
    Default  = "200",
    Options  = { "50", "100", "200", "300", "400" },
    Callback = function(val) getgenv().Config.WalkSpeedVal = tonumber(val) end
})

RunService.RenderStepped:Connect(function()
    if getgenv().WalkSpeedOn and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = getgenv().Config.WalkSpeedVal or 200 end
    end
end)

TabLocal:AddToggle({
    Name     = "High Jump",
    Default  = false,
    Callback = function(state) getgenv().HighJump = state end
})

TabLocal:AddDropdown({
    Name     = "Jump Power",
    Default  = "200",
    Options  = { "100", "200", "300", "400" },
    Callback = function(val) getgenv().Config.JumpPowerVal = tonumber(val) end
})

RunService.RenderStepped:Connect(function()
    if getgenv().HighJump and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.JumpPower = getgenv().Config.JumpPowerVal or 200 end
    end
end)

TabLocal:AddToggle({
    Name     = "Infinite Energy",
    Default  = false,
    Callback = function(state) getgenv().InfEnergy = state end
})

local maxEnergy = 100
task.spawn(function()
    while task.wait(0.1) do
        if getgenv().InfEnergy and LocalPlayer.Character then
            local energy = LocalPlayer.Character:FindFirstChild("Energy")
            if energy then
                if energy.Value > maxEnergy then maxEnergy = energy.Value end
                energy.Value = maxEnergy
            end
        end
    end
end)

TabLocal:AddToggle({
    Name     = "Walk on Water",
    Default  = false,
    Callback = function(state) getgenv().WalkWater = state end
})

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            if getgenv().WalkWater then
                Workspace.Map["WaterBase-Plane"].Size = Vector3.new(1000, 112, 1000)
            else
                Workspace.Map["WaterBase-Plane"].Size = Vector3.new(1000, 80, 1000)
            end
        end)
    end
end)

TabLocal:AddSlider({
    Name     = "Tween Speed",
    Min      = 50,
    Max      = 500,
    Default  = 350,
    Callback = function(val) getgenv().Config.TweenSpeed = val end
})

TabLocal:AddButton({
    Name     = "Stop All Tween",
    Callback = function()
        local hrp = getHRP()
        if hrp then topos(hrp.CFrame) end
        stopTeleport()
    end
})

-- ============ TAB: TELEPORT ============
local TabTP = Window:MakeTab({ Name = "Teleport", Icon = "rbxassetid://4370305131", PremiumOnly = false })

local islands = {}
if World1 then
    islands = { "WindMill", "Marine", "Middle Town", "Jungle", "Pirate Village", "Desert",
                "Snow Island", "MarineFord", "Colosseum", "Sky Island 1", "Sky Island 2",
                "Sky Island 3", "Prison", "Magma Village", "Under Water Island", "Fountain City" }
elseif World2 then
    islands = { "The Cafe", "Frist Spot", "Dark Area", "Flamingo Mansion", "Flamingo Room",
                "Green Zone", "Zombie Island", "Two Snow Mountain", "Punk Hazard",
                "Cursed Ship", "Ice Castle", "Forgotten Island", "Ussop Island" }
elseif World3 then
    islands = { "Mansion", "Port Town", "Great Tree", "Castle On The Sea", "Hydra Island",
                "Floating Turtle", "Haunted Castle", "Ice Cream Island", "Peanut Island",
                "Cake Island", "Candy Cane Island", "Tiki Outpost" }
end

local islandCFrame = {
    ["WindMill"]           = CFrame.new(889, 17, 1434),
    ["Marine"]             = CFrame.new(-2728, 25, 2056),
    ["Middle Town"]        = CFrame.new(-688, 15, 1585),
    ["Jungle"]             = CFrame.new(-1614, 37, 146),
    ["Pirate Village"]     = CFrame.new(-1173, 45, 3837),
    ["Desert"]             = CFrame.new(945, 21, 4375),
    ["Snow Island"]        = CFrame.new(1298, 87, -1344),
    ["MarineFord"]         = CFrame.new(-4810, 21, 4359),
    ["Colosseum"]          = CFrame.new(-1535, 7, -3014),
    ["Sky Island 1"]       = CFrame.new(-4814, 718, -2551),
    ["Sky Island 2"]       = CFrame.new(-4652, 873, -1754),
    ["Sky Island 3"]       = CFrame.new(-7895, 5547, -380),
    ["Prison"]             = CFrame.new(4870, 6, 736),
    ["Magma Village"]      = CFrame.new(-5290, 9, 8349),
    ["Under Water Island"] = CFrame.new(61164, 5, 1820),
    ["Fountain City"]      = CFrame.new(5128, 60, 4106),
    ["The Cafe"]           = CFrame.new(-382, 73, 290),
    ["Frist Spot"]         = CFrame.new(-11, 29, 2771),
    ["Dark Area"]          = CFrame.new(3494, 13, -3259),
    ["Flamingo Mansion"]   = CFrame.new(-317, 331, 597),
    ["Flamingo Room"]      = CFrame.new(2285, 15, 905),
    ["Green Zone"]         = CFrame.new(-2258, 73, -2696),
    ["Zombie Island"]      = CFrame.new(-5552, 194, -776),
    ["Two Snow Mountain"]  = CFrame.new(752, 408, -5277),
    ["Punk Hazard"]        = CFrame.new(-5897, 18, -5096),
    ["Cursed Ship"]        = CFrame.new(919, 125, 32869),
    ["Ice Castle"]         = CFrame.new(5505, 40, -6178),
    ["Forgotten Island"]   = CFrame.new(-3050, 240, -10178),
    ["Ussop Island"]       = CFrame.new(4816, 8, 2863),
    ["Mansion"]            = CFrame.new(-12471, 374, -7551),
    ["Port Town"]          = CFrame.new(-339, 21, 5555),
    ["Great Tree"]         = CFrame.new(2681, 1682, -7190),
    ["Castle On The Sea"]  = CFrame.new(-5073, 315, -3153),
    ["Hydra Island"]       = CFrame.new(5290, 1005, 392),
    ["Floating Turtle"]    = CFrame.new(-12528, 332, -8658),
    ["Haunted Castle"]     = CFrame.new(-9517, 142, 5528),
    ["Ice Cream Island"]   = CFrame.new(-902, 79, -10988),
    ["Peanut Island"]      = CFrame.new(-2062, 50, -10232),
    ["Cake Island"]        = CFrame.new(-1897, 14, -11576),
    ["Candy Cane Island"]  = CFrame.new(-1038, 10, -14076),
    ["Tiki Outpost"]       = CFrame.new(-16224, 9, 439),
}

TabTP:AddDropdown({
    Name     = "Select Island",
    Default  = "",
    Options  = islands,
    Callback = function(val) getgenv().Config.SelectIsland = val end
})

TabTP:AddButton({
    Name     = "Teleport To Island",
    Callback = function()
        local sel = getgenv().Config.SelectIsland
        if sel and islandCFrame[sel] then
            topos(islandCFrame[sel])
        end
    end
})

TabTP:AddButton({
    Name     = "Server Hop",
    Callback = function() Hop() end
})

TabTP:AddButton({
    Name     = "Rejoin Server",
    Callback = function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
})

-- ============ TAB: MISC ============
local TabMisc = Window:MakeTab({ Name = "Misc", Icon = "rbxassetid://4370305131", PremiumOnly = false })

TabMisc:AddButton({
    Name     = "Unlock FPS",
    Callback = function() setFps(9999999) end
})

TabMisc:AddButton({
    Name     = "Max Zoom",
    Callback = function()
        LocalPlayer.CameraMaxZoomDistance = 9223372036854718
    end
})

TabMisc:AddButton({
    Name     = "Anti-AFK Re-enable",
    Callback = function()
        for _, conn in pairs(getconnections(LocalPlayer.Idled)) do
            conn:Disable()
        end
    end
})

TabMisc:AddButton({
    Name     = "Copy Discord",
    Callback = function()
        setClip("https://discord.gg/yourlink")
    end
})

TabMisc:AddButton({
    Name     = "Destroy UI",
    Callback = function()
        stopFly()
        getgenv().AutoFarmLevel = false
        getgenv().AutoHaki      = false
        getgenv().AutoKen       = false
        getgenv().AutoClick     = false
        getgenv().ESPPlayer     = false
        getgenv().ESPIsland     = false
        getgenv().RemoveFog     = false
        getgenv().WhiteScreen   = false
        getgenv().NoClip        = false
        getgenv().WalkSpeedOn   = false
        getgenv().HighJump      = false
        getgenv().InfEnergy     = false
        getgenv().WalkWater     = false
        OrionLib:Destroy()
    end
})

-- ============ ANTI-IDLE + SIM RADIUS ============
pcall(function()
    for _, conn in pairs(getconnections(LocalPlayer.Idled)) do
        conn:Disable()
    end
end)

task.spawn(function()
    while task.wait() do
        pcall(function()
            if setscriptable then setscriptable(LocalPlayer, "SimulationRadius", true) end
            if sethiddenproperty then sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end
        end)
    end
end)

-- ============ INIT ============
OrionLib:Init()

-- ============ DELTA X NOTES ============
-- 1. Script nay TOI UU cho Delta X:
--    - httpGet() dung request() (native Delta X) voi fallback game:HttpGet
--    - pcall wrap moi optional API (setfpscap, setclipboard, isnetworkowner)
--    - Orion Library mobile-friendly
--
-- 2. Neu Orion khong load (URL chet):
--    - Thu doi sang Rayfield: loadstring(httpGet("https://raw.githubusercontent.com/Rayfield/rayfield/main/source"))()
--    - Hoac Fluent: loadstring(httpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/main/source"))()
--
-- 3. Delta X mobile:
--    - Tap toggle de bat/tat feature
--    - Giu de scroll trong dropdown
--    - Slider keo ngang
--
-- 4. Anti-cheat Roblox (Hyperion):
--    - Tween teleport (topos) an toan hon CFrame thang
--    - ESP BillboardGui an toan hon drawing library
--    - sethiddenproperty SimulationRadius can setscriptable truoc
--
-- 5. Them feature moi theo pattern:
--    Tab:AddToggle({Name=..., Callback=function(s) getgenv().Flag = s end})
--    task.spawn(function() while task.wait() do if getgenv().Flag then ... end end end)
