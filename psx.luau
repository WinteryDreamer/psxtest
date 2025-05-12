-- Rafa's PSX AutoFarm with UI
local SCRIPT_NAME = "Wintery PSX AutoFarm"
local SCRIPT_VERSION = "v0.1"

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- Configuration (Controlled by UI)
local Config = {
    FAST_MODE = false,
    FARM_SPEED = 0.1,
    FARM_MAX_DISTANCE = 300,
    FARM_PRIORITIES = {"Nearest", "Lowest Life", "Highest Multiplier", "Diamonds"}
}

-- AutoFarm State
local isAutoFarmRunning = false
local autoFarmThread = nil

-- Wait for game to load
if not game:IsLoaded() then game.Loaded:Wait() end

-- Check if in Pet Simulator X
if game.PlaceId ~= 6284583030 and game.PlaceId ~= 10321372166 and game.PlaceId ~= 7722306047 and game.PlaceId ~= 12610002282 then
    warn("Not in Pet Simulator X!")
    return
end

-- Library Setup
local Library = require(ReplicatedStorage.Library)
while not Library.Loaded do task.wait() end

-- Character Setup
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Anti-Cheat Bypass
local banSuccess, banError = pcall(function()
    local Blunder = require(ReplicatedStorage:WaitForChild("X"):WaitForChild("Blunder"):WaitForChild("BlunderList"))
    if not Blunder or not Blunder.getAndClear then
        LocalPlayer:Kick("Error: Blunder not found!")
        return
    end
    
    local OldGet = Blunder.getAndClear
    setreadonly(Blunder, false)
    
    Blunder.getAndClear = function(Packet)
        for i, v in ipairs(Packet.list) do
            if v.message ~= "PING" then
                table.remove(Packet.list, i)
            end
        end
        return OldGet(Packet)
    end
    
    setreadonly(Blunder, true)
end)

if not banSuccess then
    LocalPlayer:Kick("Anti-Cheat Bypass Error: " .. tostring(banError))
    return
end

-- Network Bypass
local bypassSuccess, bypassError = pcall(function()
    if not Library.Network or not Library.Network.Invoke then
        LocalPlayer:Kick("Network Error!")
        return
    end
    hookfunction(debug.getupvalue(Library.Network.Invoke, 1), function(...) return true end)
end)

if not bypassSuccess then
    LocalPlayer:Kick("Network Bypass Error: " .. tostring(banError))
    return
end

-- Coin Sorting Logic
local function GetCoinLowestPriority(mainCoin, coinToCompare, coinMesh)
    local coin = Library.Directory.Coins[mainCoin.n]
    local coinCompare = Library.Directory.Coins[coinToCompare.n]
    
    local aMagnitude = coinMesh and (HumanoidRootPart.Position - mainCoin.p).Magnitude or math.huge
    local bMagnitude = coinMesh and (HumanoidRootPart.Position - coinToCompare.p).Magnitude or math.huge
    
    local coinIsDiamond = coin.currencyType == "Diamonds"
    local coinHighestMultiplier = (mainCoin.b and mainCoin.b.l and #mainCoin.b.l or 0) > (coinToCompare.b and coinToCompare.b.l and #coinToCompare.b.l or 0)
    
    for priority, priorityName in ipairs(Config.FARM_PRIORITIES) do
        if priorityName == "Diamonds" and coinIsDiamond then
            return priority
        elseif priorityName == "Highest Multiplier" and coinHighestMultiplier then
            return priority
        elseif priorityName == "Lowest Life" and coin.health < coinCompare.health then
            return priority
        elseif priorityName == "Nearest" and aMagnitude < bMagnitude then
            return priority
        end
    end
    return 9999999
end

-- AutoFarm Logic
local function RunAutoFarm()
    while isAutoFarmRunning do
        local CoinsTable = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Coins).DestroyAllCoins, 1)
        local RenderedPets = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Pets).NetworkUpdate, 1)
        
        if Config.FAST_MODE then
            local foundCoins = {}
            for coinId, coin in pairs(CoinsTable) do
                coin.coinId = coinId
                local mag = (HumanoidRootPart.Position - coin.p).Magnitude
                if mag <= Config.FARM_MAX_DISTANCE and Library.WorldCmds.HasArea(coin.a) then
                    table.insert(foundCoins, coin)
                end
            end
            
            table.sort(foundCoins, function(a, b)
                return GetCoinLowestPriority(a, b) < GetCoinLowestPriority(b, a)
            end)
            
            local equippedPets = Library.PetCmds.GetEquipped()
            if equippedPets and #equippedPets > 0 and #foundCoins > 0 then
                for _, pet in pairs(equippedPets) do
                    local selectedCoin = foundCoins[1]
                    if selectedCoin then
                        Library.Network.Invoke("Join Coin", selectedCoin.coinId, {pet.uid})
                        Library.Network.Fire("Farm Coin", selectedCoin.coinId, pet.uid)
                        table.remove(foundCoins, 1)
                        task.wait(Config.FARM_SPEED)
                    end
                end
            end
        else
            local WorldCoins = Library.Things:WaitForChild("Coins")
            local foundCoins = {}
            
            for _, coin in ipairs(WorldCoins:GetChildren()) do
                local coinMesh = coin:FindFirstChild("Coin")
                if coinMesh then
                    local coinData = CoinsTable[coin.Name]
                    local mag = (HumanoidRootPart.Position - coinMesh.Position).Magnitude
                    local containsMyPet = false
                    
                    for _, pet in pairs(Library.PetCmds.GetEquipped()) do
                        if coinData and coinData.pets and table.find(coinData.pets, pet.uid) then
                            containsMyPet = true
                            break
                        end
                    end
                    
                    if not containsMyPet and mag <= Config.FARM_MAX_DISTANCE and Library.WorldCmds.HasArea(coin:GetAttribute("Area")) then
                        table.insert(foundCoins, coin)
                    end
                end
            end
            
            table.sort(foundCoins, function(coinA, coinB)
                local a = CoinsTable[coinA.Name]
                local b = CoinsTable[coinB.Name]
                return GetCoinLowestPriority(a, b, coinA:FindFirstChild("Coin")) < GetCoinLowestPriority(b, a, coinB:FindFirstChild("Coin"))
            end)
            
            for _, pet in pairs(RenderedPets) do
                if pet.spawned.owner == LocalPlayer and not pet.farming then
                    local coin = foundCoins[1]
                    if coin then
                        Library.Signal.Fire("Select Coin", coin, pet)
                        table.remove(foundCoins, 1)
                        task.wait(Config.FARM_SPEED)
                    end
                end
            end
        end
        task.wait(0.1)
    end
end

-- Anti-AFK
for _, v in pairs(getconnections(LocalPlayer.Idled)) do
    v:Disable()
end

-- Create UI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = LocalPlayer.PlayerGui
ScreenGui.Name = "AutoFarmUI"
ScreenGui.ResetOnSpawn = false

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 300, 0, 400)
Frame.Position = UDim2.new(0.5, -150, 0.5, -200)
Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Rafa's PSX AutoFarm v0.1"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 20
Title.Font = Enum.Font.SourceSansBold
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 30)
StatusLabel.Position = UDim2.new(0, 0, 0, 40)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Stopped"
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.TextSize = 16
StatusLabel.Font = Enum.Font.SourceSans
StatusLabel.Parent = Frame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0.9, 0, 0, 40)
ToggleButton.Position = UDim2.new(0.05, 0, 0, 80)
ToggleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
ToggleButton.Text = "Start AutoFarm"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 16
ToggleButton.Font = Enum.Font.SourceSans
ToggleButton.Parent = Frame

local FastModeToggle = Instance.new("TextButton")
FastModeToggle.Size = UDim2.new(0.9, 0, 0, 40)
FastModeToggle.Position = UDim2.new(0.05, 0, 0, 130)
FastModeToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
FastModeToggle.Text = "Fast Mode: OFF"
FastModeToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
FastModeToggle.TextSize = 16
FastModeToggle.Font = Enum.Font.SourceSans
FastModeToggle.Parent = Frame

local FarmSpeedLabel = Instance.new("TextLabel")
FarmSpeedLabel.Size = UDim2.new(0.9, 0, 0, 20)
FarmSpeedLabel.Position = UDim2.new(0.05, 0, 0, 180)
FarmSpeedLabel.BackgroundTransparency = 1
FarmSpeedLabel.Text = "Farm Speed: 0.1s"
FarmSpeedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmSpeedLabel.TextSize = 14
FarmSpeedLabel.Font = Enum.Font.SourceSans
FarmSpeedLabel.Parent = Frame

local FarmSpeedSlider = Instance.new("TextBox")
FarmSpeedSlider.Size = UDim2.new(0.9, 0, 0, 30)
FarmSpeedSlider.Position = UDim2.new(0.05, 0, 0, 200)
FarmSpeedSlider.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
FarmSpeedSlider.Text = "0.1"
FarmSpeedSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmSpeedSlider.TextSize = 14
FarmSpeedSlider.Font = Enum.Font.SourceSans
FarmSpeedSlider.Parent = Frame

local MaxDistanceLabel = Instance.new("TextLabel")
MaxDistanceLabel.Size = UDim2.new(0.9, 0, 0, 20)
MaxDistanceLabel.Position = UDim2.new(0.05, 0, 0, 240)
MaxDistanceLabel.BackgroundTransparency = 1
MaxDistanceLabel.Text = "Max Distance: 300"
MaxDistanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
MaxDistanceLabel.TextSize = 14
MaxDistanceLabel.Font = Enum.Font.SourceSans
MaxDistanceLabel.Parent = Frame

local MaxDistanceSlider = Instance.new("TextBox")
MaxDistanceSlider.Size = UDim2.new(0.9, 0, 0, 30)
MaxDistanceSlider.Position = UDim2.new(0.05, 0, 0, 260)
MaxDistanceSlider.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
MaxDistanceSlider.Text = "300"
MaxDistanceSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
MaxDistanceSlider.TextSize = 14
MaxDistanceSlider.Font = Enum.Font.SourceSans
MaxDistanceSlider.Parent = Frame

local PriorityLabel = Instance.new("TextLabel")
PriorityLabel.Size = UDim2.new(0.9, 0, 0, 20)
PriorityLabel.Position = UDim2.new(0.05, 0, 0, 300)
PriorityLabel.BackgroundTransparency = 1
PriorityLabel.Text = "Priority: Nearest"
PriorityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
PriorityLabel.TextSize = 14
PriorityLabel.Font = Enum.Font.SourceSans
PriorityLabel.Parent = Frame

local PriorityDropdown = Instance.new("TextButton")
PriorityDropdown.Size = UDim2.new(0.9, 0, 0, 30)
PriorityDropdown.Position = UDim2.new(0.05, 0, 0, 320)
PriorityDropdown.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
PriorityDropdown.Text = "Select Priority"
PriorityDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
PriorityDropdown.TextSize = 14
PriorityDropdown.Font = Enum.Font.SourceSans
PriorityDropdown.Parent = Frame

local DropdownList = Instance.new("Frame")
DropdownList.Size = UDim2.new(0.9, 0, 0, 100)
DropdownList.Position = UDim2.new(0.05, 0, 0, 350)
DropdownList.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
DropdownList.Visible = false
DropdownList.Parent = Frame

local priorities = {"Nearest", "Lowest Life", "Highest Multiplier", "Diamonds"}
for i, priority in ipairs(priorities) do
    local PriorityOption = Instance.new("TextButton")
    PriorityOption.Size = UDim2.new(1, 0, 0, 25)
    PriorityOption.Position = UDim2.new(0, 0, 0, (i-1)*25)
    PriorityOption.BackgroundTransparency = 1
    PriorityOption.Text = priority
    PriorityOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    PriorityOption.TextSize = 14
    PriorityOption.Font = Enum.Font.SourceSans
    PriorityOption.Parent = DropdownList
    PriorityOption.MouseButton1Click:Connect(function()
        Config.FARM_PRIORITIES = {priority}
        PriorityLabel.Text = "Priority: " .. priority
        PriorityDropdown.Text = priority
        DropdownList.Visible = false
    end)
end

-- UI Interactivity
ToggleButton.MouseButton1Click:Connect(function()
    isAutoFarmRunning = not isAutoFarmRunning
    if isAutoFarmRunning then
        ToggleButton.Text = "Stop AutoFarm"
        StatusLabel.Text = "Status: Running"
        autoFarmThread = task.spawn(RunAutoFarm)
    else
        ToggleButton.Text = "Start AutoFarm"
        StatusLabel.Text = "Status: Stopped"
        if autoFarmThread then
            task.cancel(autoFarmThread)
        end
    end
end)

FastModeToggle.MouseButton1Click:Connect(function()
    Config.FAST_MODE = not Config.FAST_MODE
    FastModeToggle.Text = "Fast Mode: " .. (Config.FAST_MODE and "ON" or "OFF")
end)

FarmSpeedSlider.FocusLost:Connect(function()
    local value = tonumber(FarmSpeedSlider.Text)
    if value and value >= 0.05 and value <= 2 then
        Config.FARM_SPEED = value
        FarmSpeedLabel.Text = "Farm Speed: " .. value .. "s"
    else
        FarmSpeedSlider.Text = tostring(Config.FARM_SPEED)
    end
end)

MaxDistanceSlider.FocusLost:Connect(function()
    local value = tonumber(MaxDistanceSlider.Text)
    if value and value >= 10 and value <= 300 then
        Config.FARM_MAX_DISTANCE = value
        MaxDistanceLabel.Text = "Max Distance: " .. value
    else
        MaxDistanceSlider.Text = tostring(Config.FARM_MAX_DISTANCE)
    end
end)

PriorityDropdown.MouseButton1Click:Connect(function()
    DropdownList.Visible = not DropdownList.Visible
end)

-- Draggable UI
local dragging, dragInput, dragStart, startPos
Frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Close UI with Keybind (e.g., 'E')
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.E then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Notify Player
StarterGui:SetCore("SendNotification", {
    Title = "Wintery's PSX AutoFarm",
    Text = "UI Loaded! Press 'E' to toggle UI.",
    Duration = 5
})
