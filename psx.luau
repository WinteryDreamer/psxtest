-- Rafa's PSX AutoFarm (No UI, Auto-Start)
local SCRIPT_NAME = "Rafa PSX AutoFarm"
local SCRIPT_VERSION = "v0.1"

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Configuration (Modify these as needed)
local FAST_MODE = false -- Set to true for faster, less legit farming
local FARM_SPEED = 0.3 -- Seconds between farming actions (0.05 to 2)
local FARM_MAX_DISTANCE = 300 -- Max distance to farm coins (10 to 300)
local FARM_PRIORITIES = {"Nearest", "Lowest Life", "Highest Multiplier", "Diamonds"} -- Coin farming priorities

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
    LocalPlayer:Kick("Network Bypass Error: " .. tostring(bypassError))
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
    
    for priority, priorityName in ipairs(FARM_PRIORITIES) do
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
    print(string.format("%s %s Started! AutoFarm is running.", SCRIPT_NAME, SCRIPT_VERSION))
    
    while true do
        local CoinsTable = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Coins).DestroyAllCoins, 1)
        local RenderedPets = debug.getupvalue(getsenv(LocalPlayer.PlayerScripts.Scripts.Game.Pets).NetworkUpdate, 1)
        
        if FAST_MODE then
            local foundCoins = {}
            for coinId, coin in pairs(CoinsTable) do
                coin.coinId = coinId
                local mag = (HumanoidRootPart.Position - coin.p).Magnitude
                if mag <= FARM_MAX_DISTANCE and Library.WorldCmds.HasArea(coin.a) then
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
                        task.wait(FARM_SPEED)
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
                    
                    if not containsMyPet and mag <= FARM_MAX_DISTANCE and Library.WorldCmds.HasArea(coin:GetAttribute("Area")) then
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
                        task.wait(FARM_SPEED)
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Anti-AFK
for _, v in pairs(getconnections(LocalPlayer.Idled)) do
    v:Disable()
end
