-- Rafa's PSX AutoFarm (Minimal Version)
local SCRIPT_NAME = "Rafa PSX AutoFarm"
local SCRIPT_VERSION = "v0.1"

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- Wait for game to load
if not game:IsLoaded() then game.Loaded:Wait() end

-- Check if in Pet Simulator X
if game.PlaceId ~= 6284583030 and game.PlaceId ~= 10321372166 and game.PlaceId ~= 7722306047 and game.PlaceId ~= 12610002282 then
    return
end

-- Library Setup
local Library = require(ReplicatedStorage.Library)
while not Library.Loaded do task.wait() end

-- Character Setup
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua'))()
local Window = Rayfield:CreateWindow({
    Name = "PSX AutoFarm | by Rafa",
    LoadingTitle = SCRIPT_NAME .. " " .. SCRIPT_VERSION,
    LoadingSubtitle = "by Rafa",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "Rafa",
        FileName = "PSX_AutoFarm"
    }
})

-- AutoFarm Variables
local enableAutoFarm = false
local AutoFarm_FastMode = false
local AutoFarm_FarmSpeed = 0.3
local farmMaxDistance = 150
local FarmFocusList = {"Nearest", "Lowest Life", "Highest Multiplier", "Diamonds"}

-- AutoFarm Tab
local autoFarmTab = Window:CreateTab("Auto Farm", "13075651575")
local autoFarmSection = autoFarmTab:CreateSection("Auto Farm")

autoFarmTab:CreateToggle({
    Name = "Enable Auto-Farm",
    Flag = "AutoFarm_Enabled",
    SectionParent = autoFarmSection,
    CurrentValue = false,
    Callback = function(Value)
        enableAutoFarm = Value
    end
})

autoFarmTab:CreateToggle({
    Name = "Fast Mode",
    Flag = "AutoFarm_FastMode",
    SectionParent = autoFarmSection,
    CurrentValue = false,
    Callback = function(Value)
        AutoFarm_FastMode = Value
    end
})

autoFarmTab:CreateSlider({
    Name = "Farm Speed",
    Flag = "AutoFarm_FarmSpeed",
    SectionParent = autoFarmSection,
    Range = {0.05, 2},
    Increment = 0.05,
    Suffix = "Second(s)",
    CurrentValue = 0.3,
    Callback = function(Value)
        AutoFarm_FarmSpeed = Value
    end
})

autoFarmTab:CreateSlider({
    Name = "Farm Max Distance",
    Flag = "AutoFarm_MaxDistance",
    SectionParent = autoFarmSection,
    Range = {10, 300},
    Increment = 1,
    Suffix = "Studs",
    CurrentValue = 150,
    Callback = function(Value)
        farmMaxDistance = Value
    end
})

-- Coin Sorting Logic
local function GetCoinLowestPriority(mainCoin, coinToCompare, coinMesh)
    local coin = Library.Directory.Coins[mainCoin.n]
    local coinCompare = Library.Directory.Coins[coinToCompare.n]
    
    local aMagnitude = (HumanoidRootPart.Position - mainCoin.p).Magnitude
    local bMagnitude = (HumanoidRootPart.Position - coinToCompare.p).Magnitude
    
    local coinIsDiamond = coin.currencyType == "Diamonds"
    local coinHighestMultiplier = (mainCoin.b and mainCoin.b.l and #mainCoin.b.l or 0) > (coinToCompare.b and coinToCompare.b.l and #coinToCompare.b.l or 0)
    
    for priority, priorityName in ipairs(FarmFocusList) do
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
task.spawn(function()
    while true do
        if enableAutoFarm then
            local CoinsTable = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Coins).DestroyAllCoins, 1)
            local RenderedPets = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Pets).NetworkUpdate, 1)
            
            if AutoFarm_FastMode then
                local foundCoins = {}
                for coinId, coin in pairs(CoinsTable) do
                    coin.coinId = coinId
                    local mag = (HumanoidRootPart.Position - coin.p).Magnitude
                    if mag <= farmMaxDistance and Library.WorldCmds.HasArea(coin.a) then
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
                            task.wait(AutoFarm_FarmSpeed)
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
                        
                        if not containsMyPet and mag <= farmMaxDistance and Library.WorldCmds.HasArea(coin:GetAttribute("Area")) then
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
                    if enableAutoFarm and pet.spawned.owner == LocalPlayer and not pet.farming then
                        local coin = foundCoins[1]
                        if coin then
                            Library.Signal.Fire("Select Coin", coin, pet)
                            table.remove(foundCoins, 1)
                            task.wait(AutoFarm_FarmSpeed)
                        end
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Anti-AFK
for _, v in pairs(getconnections(LocalPlayer.Idled))ешь do
    v:Disable()
end

Library.ChatMsg.New(string.format("Hello, %s! AutoFarm %s Loaded!", LocalPlayer.DisplayName, SCRIPT_VERSION), Color3.fromRGB(175, 70, 245))
Rayfield.LoadConfiguration()
