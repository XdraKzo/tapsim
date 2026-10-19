-- TAP SIMULATOR KAITUN (v2)
-- Follows the progression step by step (Config.Stages): hatch, rebirth, break the bridge,
-- buy double jumps, unlock the next island, ... up to Volcano. On restart it skips finished steps.
-- Always running: auto tap, equip best, skill tree, cleanup when storage is full, golden/diamond, rewards.
-- Double jump / island unlock requests are not 100% known yet: the script tries a few versions and
-- LEARNS the right one if you do it once by hand while the script runs (saved to TapSimLearned.json).
-- To stop: run the script again (the old copy stops) or in F9 console: getgenv().TapSimId = 0

local Config = {
    -- AUTO TAP
    AutoTap = true,
    TapsPerSecond = 20,

    -- HATCH
    HatchCount = 0,            -- eggs per hatch. 0 = auto: 8 if the account has the 8-hatch gamepass, else 3
    HatchCountTry = {8, 3},    -- auto: biggest first; the game's answer tells what the account can do
    HatchDelay = 0.2,          -- seconds between hatch requests (lower = faster; the server still has its own limit)
    -- hatch animation (game setting "HatchAnimation", values 1 / 2 / 3). 2 and 3 still show it, so 1 is used.
    -- If it is still there: turn it off ONCE in the game's settings while the script runs; it learns it.
    HatchAnimationOff = true,
    HatchAnimationValue = 1,
    -- if saving for the egg would take longer than this (seconds, at the current income), the script
    -- rebirths first (more income) and comes back to the egg. 0 = off (only wait / tap).
    EggMaxWait = 0,
    -- if saving for a 3-hatch takes longer than this (seconds), eggs are opened 1 by 1 instead. 0 = off.
    MultiHatchMaxWait = 120,
    -- a step can also say MinRebirths = 50000: rebirth until that total first, then save for the egg.

    -- EQUIP BEST
    EquipBestEvery = 20,       -- seconds

    -- REBIRTH: button 1 = +1, 2 = +5, 3 = +25, 4 = +125, 5 = +625, 6 = +3.12k, 7 = +15.62k, 8 = +78k, 9 = +390k ...
    RebirthMaxButton = 12,
    RebirthDelay = 1,          -- seconds between rebirths in rebirth steps
    -- smart rebirth: the script saves for the biggest unlocked button if its cost is reachable within
    -- this many seconds (it does not spend the coins on small buttons meanwhile). Higher = waits longer
    -- for big buttons. Big buttons
    -- also unlock the next ones (+625 unlocks +3.12k and +15.62k).
    RebirthSaveWindow = 120,

    -- SKILL TREE (gems): these first, then every other node the script finds, cheapest first.
    -- Paused while saving gems for a double jump.
    AutoSkillTree = true,
    SkillTree = {
        "Critical Clicks 1", "Auto Clicker", "Auto Clicker Speed", "Pets",
        "Egg Luck 1", "Pet XP 1", "Pet Power 1",
    },
    SkillTreeEvery = 15,

    -- STORAGE CLEANUP: when free slots drop below CleanupWhenFree, delete the weakest pets until
    -- CleanupKeepFree slots are free. Never deleted: equipped, golden/diamond/shiny, secrets, KeepPets,
    -- pets a step is collecting, pets used for golden.
    Cleanup = true,
    -- OLD ISLAND PETS: every pet hatched on an island BEFORE the newest island you have unlocked is
    -- deleted (always, not only when storage is full). Kept: equipped, locked, secrets, KeepPets,
    -- KeepRarities, shiny (unless CleanupShiny = true).
    DeleteOldIslandPets = true,
    CleanupWhenFree = 10,
    CleanupKeepFree = 40,
    KeepPets = {},
    KeepRarities = {"Secret", "Exclusive", "Godly"},
    CleanupTiers = {"Normal", "Golden", "Diamond", "Rainbow"}, -- tiers the cleanup may delete (junk only)
    CleanupShiny = false,      -- false = shiny pets are never deleted by the cleanup

    -- STRONG PETS: if equipped pet power (Pets.PowerMultiplier) is at least this, hatch steps are
    -- skipped and the script only rebirths / unlocks islands up to the last one.
    StrongPower = 1e6,

    -- DOUBLE JUMPS: island needs (IslandLandings Jumps - JumpOffset) bought double jumps.
    -- Override per island here if it is wrong, e.g. JumpsNeeded = {Autumn = 1, Mushroom = 2}
    JumpOffset = 1,
    JumpsNeeded = {},
    -- double jumps are bought at the shop's upgrade point; the script looks for it by itself.
    -- If it cannot find it: JumpPoint = Vector3.new(x, y, z)
    JumpPoint = nil,

    -- GOLDEN / DIAMOND / RAINBOW (always on). The script teleports onto the machine's pad, crafts,
    -- waits for the result, presses Continue and goes back to what it was doing (egg).
    -- Machines: Golden (normal -> golden), Diamond (golden -> diamond), Rainbow (diamond -> rainbow, 30 s).
    Golden = {"Volcanic Angel", "Volcanic Devil"},
    GoldenWhenCopies = 6,      -- craft when you own this many normal copies
    GoldenUse = 6,             -- copies put in the machine (6 normal -> 1 golden)
    Diamond = {"Volcanic Angel", "Volcanic Devil"},
    DiamondUse = 5,            -- golden copies -> 1 diamond
    Rainbow = {"Volcanic Angel", "Volcanic Devil"},
    RainbowUse = 5,            -- diamond copies -> 1 rainbow (Rainbow machine: takes 30 s, then claimed)
    -- SHINY pets come from eggs (like PS99). They are crafted separately from normal ones:
    -- shiny -> shiny golden -> shiny diamond -> shiny rainbow.

    -- ENDGAME
    FinalEgg = nil,            -- nil = the egg that has Phoenix (else Draconic)
    FinalDeleteUpTo = "Phoenix", -- auto delete this pet and everything more common in the final egg
    -- extra auto delete per egg (game's own auto delete): AutoDelete = {Spotted = {"Chick", "Lamb"}}
    -- auto delete is set for these tiers too (golden / diamond / rainbow hatches of the same junk pets)
    AutoDeleteTiers = {"Normal", "Golden", "Diamond", "Rainbow"},
    AutoDelete = {},

    -- STEPS (done in order; finished ones are skipped on restart)
    --   MinRebirths     : (egg / island steps) rebirth until you have this many in total, THEN go for the egg / island
    --   Egg + Eggs      : hatch that egg until this many were opened (Count = eggs per hatch)
    --   Egg + UntilPet  : hatch until you own Pets copies of that pet
    --   RebirthButton   : save coins for THAT rebirth button and press it Times times (default 1).
    --                     Lower buttons are not pressed, so the coins are not wasted.
    --                     1 = +1, 2 = +5, 3 = +25, 4 = +125, 5 = +625, 6 = +3.12k, 7 = +15.62k, 8 = +78.12k, 9 = +390.62k
    --   Rebirths        : rebirth (highest affordable button) until total rebirths >= this (no hatching)
    --   MoreRebirths    : rebirth this many more than when the step started
    --   Bridge          : break the spawn bridge (rebirths in between if tap power is too low)
    --   Unlock          : buy double jumps (rebirths for gems) and unlock that island
    --   GoldenQuest     : make one golden pet from any 5 copies (quest), skipped if you cannot
    --   Final           : hatch the final egg forever
    Stages = {
        {Name = "First Basic egg", Island = "Spawn", Egg = "Basic", Eggs = 1, Count = 1},
        {Name = "First rebirth", Island = "Spawn", Rebirths = 1},
        {Name = "3 more Basic eggs", Island = "Spawn", Egg = "Basic", Eggs = 4},
        {Name = "Golden pet quest", Island = "Spawn", GoldenQuest = true},
        {Name = "50 rebirths -> 4 Spotted eggs", Island = "Spawn", Egg = "Spotted", Eggs = 4, MinRebirths = 50},
        {Name = "Break the bridge", Island = "Spawn", Bridge = true},
        {Name = "150 rebirths -> first Spiked egg", Island = "Spawn", Egg = "Spiked", Eggs = 1, Count = 1, MinRebirths = 150},
        {Name = "3 more Spiked eggs", Island = "Spawn", Egg = "Spiked", Eggs = 4},
        {Name = "500 rebirths -> Sky Island", Unlock = "Sky Island", MinRebirths = 500},
        {Name = "4 Nimbus eggs", Island = "Sky Island", Egg = "Nimbus", Eggs = 4, MinRebirths = 500},
        {Name = "4 Sky eggs", Island = "Sky Island", Egg = "Sky", Eggs = 4},
        {Name = "3k rebirths -> Autumn", Unlock = "Autumn", MinRebirths = 3000},
        {Name = "20 Pumpkin eggs", Island = "Autumn", Egg = "Pumpkin", Eggs = 20},
        {Name = "15k rebirths -> Mushroom", Unlock = "Mushroom", MinRebirths = 15000},
        {Name = "4 Mushroom eggs", Island = "Mushroom", Egg = "Mushroom", Eggs = 4},
        {Name = "100k rebirths -> 4 Mycelium eggs", Island = "Mushroom", Egg = "Mycelium", Eggs = 4, MinRebirths = 100000},
        {Name = "150k rebirths -> Desert", Unlock = "Desert", MinRebirths = 150000},
        {Name = "10 Cactus eggs", Island = "Desert", Egg = "Cactus", Eggs = 10, MinRebirths = 150000},
        {Name = "300k rebirths -> Crystal Cave", Unlock = "Crystal Cave", MinRebirths = 300000},
        {Name = "5 Geode eggs", Island = "Crystal Cave", Egg = "Geode", Eggs = 5, MinRebirths = 300000},
        {Name = "450k rebirths -> 10 Crystal eggs", Island = "Crystal Cave", Egg = "Crystal", Eggs = 10, MinRebirths = 450000},
        {Name = "700k rebirths -> Shadow Realm", Unlock = "Shadow Realm", MinRebirths = 700000},
        {Name = "10 Void eggs", Island = "Shadow Realm", Egg = "Void", Eggs = 10, MinRebirths = 700000},
        {Name = "1M rebirths -> Volcano", Unlock = "Volcano", MinRebirths = 1000000},
        {Name = "10 Volcanic eggs", Island = "Volcano", Egg = "Volcanic", Eggs = 10, MinRebirths = 1000000},
        {Name = "Rebirth until 200Qd/s income", Island = "Volcano", Rebirths = math.huge, OrIncome = 2e17},
        {Name = "Endgame", Island = "Volcano", Final = true},
    },

    -- RESUME: the script saves the step it is on (TapSimProgress_<UserId>.json) and continues
    -- from there next time. Set a number to force a step (e.g. 11), nil = continue where you left off.
    StartStep = nil,

    -- OTHER
    ClaimIndexRewards = true,
    ClaimOfflineRewards = true,
    ClaimTapChests = true,
    RewardsEvery = 60,
    AntiAFK = true,

    -- PANEL: full screen status panel. It covers the game, so egg animations are not seen, and with
    -- HideWorld the 3D world is not drawn at all (no animations, more FPS). Button top right: show / hide.
    Panel = true,
    HideWorld = true,
    Debug = true,
}

local VERSION = "v2.26-19.10"

-- stop any older copy
getgenv().TapSimId = (rawget(getgenv(), "TapSimId") or 0) + 1
local RunId = getgenv().TapSimId
local function IsActive() return getgenv().TapSimId == RunId end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait() until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

local function Log(...)
    if Config.Debug then print(...) end
end

local function Short(N)
    N = tonumber(N) or 0
    local Suffixes = {"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De"}
    local I = 1
    while math.abs(N) >= 1000 and I < #Suffixes do N /= 1000; I += 1 end
    return (I == 1 and "%d%s" or "%.2f%s"):format(N, Suffixes[I])
end

local function Dump(V, Depth, Max)
    Depth, Max = Depth or 0, Max or 2
    if type(V) ~= "table" then return tostring(V) end
    if Depth >= Max then return "{...}" end
    local Parts, N = {}, 0
    for K, X in pairs(V) do
        N += 1
        if N > 14 then table.insert(Parts, "...") break end
        table.insert(Parts, tostring(K) .. "=" .. Dump(X, Depth + 1, Max))
    end
    return "{" .. table.concat(Parts, ", ") .. "}"
end

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local Services = ReplicatedStorage:WaitForChild("RemoteServices", 30)

local function Remote(Path)
    local Obj = Services
    for Part in Path:gmatch("[^%.]+") do
        Obj = Obj and Obj:WaitForChild(Part, 10)
    end
    if not Obj then warn("[TapSim] remote not found: " .. Path) end
    return Obj
end

local R = {
    Tap = Remote("TapService.RE.TapRequested"),
    Hatch = Remote("EggService.RE.EggHatchRequested"),
    HatchResult = Remote("EggService.RE.EggHatchResult"),
    AutoDelete = Remote("EggService.RE.AutoDeleteRequested"),
    PetAction = Remote("PetService.RE.PetActionRequested"),
    Rebirth = Remote("RebirthService.RE.RebirthRequested"),
    RebirthResult = Remote("RebirthService.RE.RebirthResult"),
    SkillUnlock = Remote("SkillTreeService.RF.Unlock"),
    Machine = Remote("MachineService.RE.MachineCraftRequested"),
    MachineResult = Remote("MachineService.RE.MachineCraftResult"),
    BridgeEngage = Remote("BridgeService.RE.EngageChanged"),
    CrankResult = Remote("BridgeService.RE.CrankResult"),
    JumpBuy = Remote("DoubleJumpService.RF.Purchase"),
    IslandUnlock = Remote("IslandService.RE.IslandUnlockRequested"),
    IslandUnlockResult = Remote("IslandService.RE.IslandUnlockResult"),
    IslandTravel = Remote("IslandService.RF.Travel"),
    IndexClaimAll = Remote("PetIndexService.RE.ClaimAllRequested"),
    OfflineClaim = Remote("OfflineRewardsService.RF.Claim"),
    ChestClaim = Remote("TapChestService.RF.Claim"),
    UpdateSetting = Remote("SettingsService.RF.UpdateSetting"),
}

local function Fire(Rem, ...)
    if not Rem then return false end
    local Args = table.pack(...)
    return pcall(function() Rem:FireServer(table.unpack(Args, 1, Args.n)) end)
end

local function Invoke(Rem, ...)
    if not Rem then return false end
    local Args = table.pack(...)
    return pcall(function() return Rem:InvokeServer(table.unpack(Args, 1, Args.n)) end)
end

----------------------------------------------------------------
-- LEARNED REQUESTS (double jump purchase / island unlock), saved between runs
----------------------------------------------------------------
local LearnFile = "TapSimLearned.json"
local Learned = rawget(getgenv(), "TapSimLearned") or {}

pcall(function()
    if isfile and isfile(LearnFile) then
        local Saved = HttpService:JSONDecode(readfile(LearnFile))
        if type(Saved) == "table" then
            for K, V in pairs(Saved) do Learned[K] = Learned[K] or V end
        end
    end
end)
getgenv().TapSimLearned = Learned

local function Learn(Key, Args)
    local Copy = {}
    for I = 1, Args.n do
        local V = Args[I]
        if type(V) == "table" then
            local T = {}
            for K, X in pairs(V) do T[K] = X end
            V = T
        end
        Copy[I] = V
    end
    Learned[Key] = Copy
    print(("[TapSim] learned %s request: %s"):format(Key, Dump(Copy, 0, 3)))
    pcall(function()
        if writefile then writefile(LearnFile, HttpService:JSONEncode(Learned)) end
    end)
end

----------------------------------------------------------------
-- HOOK: follow the game's own sequence numbers + learn requests done by hand
----------------------------------------------------------------
local TapSeq, HatchSeq, DeleteBatch = 0, 0, 0

local OldNamecall
OldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if not checkcaller() then
        local Method = getnamecallmethod()
        if Method == "FireServer" then
            local Data = ...
            if self == R.Tap and type(Data) == "table" then
                local N = tonumber(Data.ClientSequence)
                if N and N > TapSeq then TapSeq = N end
            elseif self == R.Hatch and type(Data) == "table" then
                local N = tonumber(Data.Seq)
                if N and N > HatchSeq then HatchSeq = N end
            elseif self == R.PetAction and type(Data) == "table" then
                local N = tonumber(Data.Batch)
                if N and N > DeleteBatch then DeleteBatch = N end
            elseif self == R.AutoDelete and type(Data) == "table" then
                print("[TapSim] game auto delete request: " .. Dump(Data, 0, 3))
                for K in pairs(Data) do
                    if K ~= "Egg" and K ~= "Entries" and type(K) == "string" then
                        Learned.AutoDeleteTierKey = K
                        pcall(function()
                            if writefile then writefile(LearnFile, HttpService:JSONEncode(Learned)) end
                        end)
                        print("[TapSim] learned auto delete tier field: " .. K)
                    end
                end
            elseif self == R.IslandUnlock then
                Learn("IslandUnlock", table.pack(...))
            end
        elseif Method == "InvokeServer" and self == R.JumpBuy then
            Learn("DoubleJump", table.pack(...))
        elseif Method == "InvokeServer" and self == R.UpdateSetting then
            -- you changed a setting by hand: remember how the hatch animation setting is sent
            local Args = table.pack(...)
            print("[TapSim] game setting request: " .. Dump(Args, 0, 3))
            local Text = Dump(Args, 0, 3)
            if Text:find("HatchAnimation") then Learn("HatchSetting", Args) end
        end
    end
    return OldNamecall(self, ...)
end)

----------------------------------------------------------------
-- ANTI AFK
----------------------------------------------------------------
if Config.AntiAFK then
    pcall(function()
        for _, Conn in ipairs(getconnections(LocalPlayer.Idled)) do Conn:Disable() end
    end)
    LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

----------------------------------------------------------------
-- PLAYER DATA (DataController replica)
----------------------------------------------------------------
local DataController
pcall(function() DataController = require(ReplicatedStorage.Controllers.Core.DataController) end)

local function D()
    local Ok, Replica = pcall(function() return DataController:GetReplica() end)
    return Ok and Replica and Replica.Data or nil
end

do
    local Deadline = os.clock() + 30
    repeat task.wait(0.5) until D() or os.clock() > Deadline
    if not D() then
        warn("[TapSim] player data not found (DataController). Stopping.")
        return
    end
end

local function Coins() local Data = D() return Data and Data.Currencies and tonumber(Data.Currencies.Coins) or 0 end
local function Gems() local Data = D() return Data and Data.Currencies and tonumber(Data.Currencies.Gems) or 0 end
local function Power() local Data = D() return Data and Data.Pets and tonumber(Data.Pets.PowerMultiplier) or 0 end
local function World() local Data = D() return Data and Data.Progression and Data.Progression.World or "Main" end

local function Rebirths()
    local Data = D()
    local A = Data and Data.Statistics and tonumber(Data.Statistics.Rebirths) or 0
    local Stats = LocalPlayer:FindFirstChild("leaderstats")
    local Value = Stats and Stats:FindFirstChild("Rebirths")
    local B = Value and tonumber(Value.Value) or 0
    return math.max(A, B)
end

-- bought double jumps: Data.PhysicalUpgrades.DoubleJump (Data.DoubleJumps stays 0)
local function Jumps()
    local Data = D()
    local P = Data and Data.PhysicalUpgrades
    local N = P and tonumber(P.DoubleJump)
    if N then return N end
    local J = Data and Data.DoubleJumps
    return J and tonumber(J[World()]) or 0
end

local Income = 0   -- coins per second (updated every 10 s)

local function InSet(T, Name)
    if type(T) ~= "table" then return false end
    if T[Name] then return true end
    for _, V in pairs(T) do
        if V == Name then return true end
    end
    return false
end

----------------------------------------------------------------
-- SAVED PROGRESS (per account): last step, islands seen unlocked, step data
----------------------------------------------------------------
local SaveFile = ("TapSimProgress_%d.json"):format(LocalPlayer.UserId)
local Save = {Stage = 1, StageName = nil, Islands = {}, Starts = {}, Done = {}, Pressed = {}}

pcall(function()
    if isfile and isfile(SaveFile) then
        local Loaded = HttpService:JSONDecode(readfile(SaveFile))
        if type(Loaded) == "table" then
            for K, V in pairs(Loaded) do Save[K] = V end
        end
    end
end)

local function WriteSave()
    pcall(function()
        if writefile then writefile(SaveFile, HttpService:JSONEncode(Save)) end
    end)
end

-- island counts as unlocked if ANY of the game's lists has it, or the game told us so once
local function IslandUnlocked(Name)
    if Name == "Spawn" or Save.Islands[Name] then return true end
    local Data = D()
    local P = Data and Data.Progression
    if not P then return false end
    if InSet(P.UnlockedIslands, Name) or InSet(P.UnlockedZones, Name) or InSet(P.IslandFirstVisits, Name)
        or InSet(P.PortalFirstVisits, Name) or InSet(P.IslandRoutes, Name) or P.Island == Name then
        Save.Islands[Name] = true
        WriteSave()
        return true
    end
    return false
end

local function SkillOwned(Name)
    local Data = D()
    return Data and Data.SkillTree and InSet(Data.SkillTree.Unlocked, Name) or false
end

----------------------------------------------------------------
-- GAME CONFIG MODULES
----------------------------------------------------------------
local ModuleCache = {}
local function FindModule(Name)
    if ModuleCache[Name] ~= nil then return ModuleCache[Name] or nil end
    for _, M in ipairs(ReplicatedStorage:GetDescendants()) do
        if M:IsA("ModuleScript") and M.Name == Name then
            local Ok, V = pcall(require, M)
            if Ok and type(V) == "table" then
                ModuleCache[Name] = V
                return V
            end
        end
    end
    ModuleCache[Name] = false
end

local EggCfg = FindModule("LaunchEggConfig") or {}
if type(EggCfg.Eggs) == "table" and not EggCfg.Basic then EggCfg = EggCfg.Eggs end

local IslandCfg = FindModule("IslandConfig")
IslandCfg = IslandCfg and (IslandCfg.Islands or IslandCfg) or {}

local Landings = FindModule("IslandLandings")
Landings = Landings and (Landings.Landings or Landings) or {}

local IndexCatalog = FindModule("PetIndexCatalog")

local function EggInfo(Egg) return type(EggCfg[Egg]) == "table" and EggCfg[Egg] or nil end
local function EggPrice(Egg) local I = EggInfo(Egg) return I and tonumber(I.Price) end

local SecretSet = {}
for _, Info in pairs(EggCfg) do
    if type(Info) == "table" and type(Info.Secrets) == "table" then
        for Name in pairs(Info.Secrets) do SecretSet[Name] = true end
    end
end

local function IsSecret(Name)
    if not Name then return false end
    if SecretSet[Name] then return true end
    if IndexCatalog and type(IndexCatalog.IsSecret) == "function" then
        local Ok, V = pcall(IndexCatalog.IsSecret, Name)
        if Ok and V then return true end
    end
    return false
end

-- final egg: the one that has Phoenix
local FinalEgg = Config.FinalEgg
if not FinalEgg then
    for Name, Info in pairs(EggCfg) do
        if type(Info) == "table" and type(Info.Pets) == "table" and Info.Pets[Config.FinalDeleteUpTo] then
            FinalEgg = Name
            break
        end
    end
    FinalEgg = FinalEgg or "Draconic"
end

----------------------------------------------------------------
-- POSITIONS (scanned before; used when the egg / island is not streamed in)
----------------------------------------------------------------
local IslandOrder = {"Spawn", "Sky Island", "Autumn", "Mushroom", "Desert", "Crystal Cave", "Shadow Realm", "Volcano"}
local IslandIndex = {}
for I, Name in ipairs(IslandOrder) do IslandIndex[Name] = I end

local IslandPos = {
    ["Spawn"] = Vector3.new(-50, -511, -1860),
    ["Sky Island"] = Vector3.new(85.9, -33.8, -1868.2),
    ["Autumn"] = Vector3.new(15.7, 893.1, -1910.3),
    ["Mushroom"] = Vector3.new(-138.8, 2028.8, -1700.9),
    ["Desert"] = Vector3.new(37.2, 3632.0, -1879.8),
    ["Crystal Cave"] = Vector3.new(30.6, 5459.4, -1680.7),
    ["Shadow Realm"] = Vector3.new(-147.2, 7686.9, -1648.5),
    ["Volcano"] = Vector3.new(-164.0, 11054.0, -1840.0),
}

local EggPos = {
    Basic = Vector3.new(5.9, -511.3, -1832.7),
    Spotted = Vector3.new(-4.9, -511.2, -1821.8),
    Spiked = Vector3.new(-23.0, -512.9, -1707.2),
    Nimbus = Vector3.new(-96.6, -47.8, -1891.4),
    Sky = Vector3.new(-88.3, -47.5, -1904.1),
    Pumpkin = Vector3.new(-142.5, 880.6, -1832.6),
    Mushroom = Vector3.new(-5.9, 2031.9, -1924.8),
    Mycelium = Vector3.new(-21.2, 2031.8, -1932.0),
    Cactus = Vector3.new(-202.5, 3631.9, -1862.8),
    Geode = Vector3.new(-67.7, 5438.2, -1986.9),
    Crystal = Vector3.new(-52.9, 5438.2, -1991.6),
    Void = Vector3.new(-203.6, 7675.9, -1885.1),
    Volcanic = Vector3.new(-2.4, 11072.6, -1913.2),
    Draconic = Vector3.new(8.9, 11072.5, -1905.3),
}

local BridgeStand = Vector3.new(-49.9, -515, -1806)

local function ToVector(V)
    if typeof(V) == "Vector3" then return V end
    if typeof(V) == "CFrame" then return V.Position end
    if type(V) == "table" then
        local X, Y, Z = tonumber(V.X or V.x or V[1]), tonumber(V.Y or V.y or V[2]), tonumber(V.Z or V.z or V[3])
        if X and Y and Z then return Vector3.new(X, Y, Z) end
    end
end

----------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------
local function Root()
    local Char = LocalPlayer.Character
    return Char and Char:FindFirstChild("HumanoidRootPart")
end

local function Humanoid()
    local Char = LocalPlayer.Character
    return Char and Char:FindFirstChildOfClass("Humanoid")
end

local function GetPosition(Obj)
    if Obj:IsA("Model") then
        local Ok, CF = pcall(Obj.GetPivot, Obj)
        if Ok then return CF.Position end
    end
    local Part = Obj:IsA("BasePart") and Obj or Obj:FindFirstChildWhichIsA("BasePart", true)
    return Part and Part.Position
end

local function Teleport(Pos)
    local HRP = Root()
    if not HRP or not Pos then return end
    pcall(function() LocalPlayer:RequestStreamAroundAsync(Pos, 5) end)
    HRP.CFrame = CFrame.new(Pos)
    HRP.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.4)
end

local function Near(Pos, Range)
    local HRP = Root()
    return HRP and Pos and (HRP.Position - Pos).Magnitude <= (Range or 15)
end

local function GoToEgg(Egg)
    local Folder = workspace:FindFirstChild("Eggs")
    local Model = Folder and Folder:FindFirstChild(Egg)
    local Pos = (Model and GetPosition(Model)) or EggPos[Egg]
    if Pos and not Near(Pos, 14) then Teleport(Pos + Vector3.new(0, 3, 7)) end
end

local function GoToIsland(Island)
    local Pos = IslandPos[Island]
    if Pos and not Near(Pos, 250) and IslandUnlocked(Island) then
        Teleport(Pos + Vector3.new(0, 4, 0))
    end
end

----------------------------------------------------------------
-- PETS
----------------------------------------------------------------
local function TierOf(E)
    local T = E.Tier or E.Variant
    if E.Diamond then T = "Diamond" elseif E.Golden then T = "Golden" end
    T = tostring(T or "Normal")
    -- the game may write it differently ("Gold", "Rainbow" ...): use one name per tier
    local L = T:lower()
    if L:find("gold") then return "Golden" end
    if L:find("diamond") then return "Diamond" end
    -- the game calls the rainbow tier "Shiny" inside (its rainbow machine is Machine = "Shiny")
    if L:find("rainbow") or L:find("shiny") then return "Rainbow" end
    return "Normal"
end

-- shiny (from eggs) is a separate mark, not the tier: a shiny pet can be normal / golden / diamond / rainbow
local function ShinyOf(E)
    if E.Shiny == true or E.IsShiny == true or E.Shiny == 1 then return true end
    for _, K in ipairs({"Variant", "Mutation", "Shine", "Effect"}) do
        local V = E[K]
        if type(V) == "string" and V:lower():find("shiny") then return true end
    end
    return false
end

local function OwnedPets()
    local Data = D()
    local Owned = Data and Data.Pets and Data.Pets.Owned
    local List = {}
    for K, E in pairs(type(Owned) == "table" and Owned or {}) do
        if type(E) == "table" then
            local Id = E.Id or E.UUID or E.Uid or (type(K) == "string" and K or nil)
            local Name = E.Name or E.Pet or E.PetName
            if Id and Name then
                table.insert(List, {
                    Id = Id, Name = Name, Tier = TierOf(E), Shiny = ShinyOf(E), Power = tonumber(E.Power) or 0,
                    Rarity = E.Rarity, Locked = E.Locked or E.Favorite or E.Favorited, SourceEgg = E.SourceEgg,
                })
            end
        end
    end
    return List
end

local function EquippedSet()
    local Data = D()
    local Eq = Data and Data.Pets and Data.Pets.Equipped
    local Set, N = {}, 0
    for K, V in pairs(type(Eq) == "table" and Eq or {}) do
        local Id
        if type(V) == "string" then Id = V
        elseif V == true then Id = K
        elseif type(V) == "table" then Id = V.Id or V.UUID or (type(K) == "string" and K)
        end
        if Id and not Set[Id] then Set[Id] = true; N += 1 end
    end
    return Set, N
end

-- Shiny: nil = any, true = only shiny, false = only not shiny
local function CountPet(Name, Tier, Shiny)
    local N = 0
    for _, P in ipairs(OwnedPets()) do
        if P.Name == Name and (not Tier or P.Tier == Tier) and (Shiny == nil or P.Shiny == Shiny) then N += 1 end
    end
    return N
end

local function StorageLimit()
    local Data = D()
    return Data and Data.Pets and tonumber(Data.Pets.StorageLimit) or 150
end

local function EquipBest()
    Fire(R.PetAction, {Action = "EquipBest", Mode = "Clicks"})
end

local function DeletePets(Ids)
    for I = 1, #Ids, 50 do
        local Part = {}
        for J = I, math.min(I + 49, #Ids) do table.insert(Part, Ids[J]) end
        DeleteBatch += 1
        Fire(R.PetAction, {PetIds = Part, Action = "Delete", Batch = DeleteBatch})
        task.wait(0.5)
    end
end

----------------------------------------------------------------
-- HATCH COUNTS
----------------------------------------------------------------
local LocalHatched = {}
local HatchStats = {Hatches = 0, Taps = 0, Rebirths = 0, Skills = 0}
local Session = {Start = os.clock(), Hatched = 0, Rebirths = 0}

local LastHatchAnswer
if R.HatchResult then
    R.HatchResult.OnClientEvent:Connect(function(Data)
        LastHatchAnswer = Data
        if type(Data) == "table" and Data.Success and Data.Egg then
            local N = tonumber(Data.Rolls) or tonumber(Data.Count) or 1
            LocalHatched[Data.Egg] = (LocalHatched[Data.Egg] or 0) + N
            HatchStats.Hatches += N
            Session.Hatched += N
        end
    end)
end

local StartHatched = {}
local function OpenedFrom(Egg)
    local Data = D()
    local H = Data and Data.Statistics and Data.Statistics.EggHatches
    local V = type(H) == "table" and H[Egg]
    if type(V) == "table" then V = V.Count or V.Total or V.Opened end
    V = tonumber(V)
    if V then return V end
    return LocalHatched[Egg] or 0
end

----------------------------------------------------------------
-- REBIRTH: highest button that works
----------------------------------------------------------------
local RebirthAnswer
local RebirthRest = {}

if R.RebirthResult then
    R.RebirthResult.OnClientEvent:Connect(function(Data)
        if type(Data) ~= "table" then return end
        RebirthAnswer = Data
        if Data.Success then
            HatchStats.Rebirths += tonumber(Data.Amount) or 1
        end
    end)
end

-- cost of a button ~= K * rebirths * 5^(button - 1); K is measured from every successful rebirth
local RebirthK
local MaxButton = tonumber(Save.MaxButton)
if not MaxButton then
    -- guess from your total: pressing +25 / +625 / +15.62k ... unlocks the next two buttons
    MaxButton = 3
    for K = 3, Config.RebirthMaxButton, 2 do
        if Rebirths() >= 5 ^ (K - 1) then MaxButton = K + 2 end
    end
end
MaxButton = math.min(MaxButton, Config.RebirthMaxButton)

local function ButtonCost(Index)
    if not RebirthK then return nil end
    return RebirthK * math.max(Rebirths(), 1) * 5 ^ (Index - 1)
end

local function PressRebirth(Index, Quick)
    RebirthAnswer = nil
    Fire(R.Rebirth, {Index = Index})
    local Deadline = os.clock() + 1
    repeat task.wait(0.05) until RebirthAnswer or os.clock() > Deadline

    local A = RebirthAnswer
    if A and A.Success then
        local Amount, Price, After = tonumber(A.Amount), tonumber(A.Price), tonumber(A.Rebirths)
        if Amount and Price and After then
            RebirthK = Price / (Amount * math.max(After - Amount, 1))
        end
        -- odd buttons (+25, +625, +15.62k ...) unlock the next two
        if Index >= 3 and Index % 2 == 1 and Index + 2 > MaxButton then
            MaxButton = math.min(Index + 2, Config.RebirthMaxButton)
            Save.MaxButton = MaxButton
            WriteSave()
            Log(("[TapSim] rebirth buttons up to %d unlocked"):format(MaxButton))
        end
        return true
    end
    -- Quick: the cost was only a guess, try again soon
    RebirthRest[Index] = os.clock() + ((Quick or Index == 1) and 3 or 15)
    return false
end

-- the game's own rebirth menu knows which button you can afford (RebirthController.GetBestAffordableOption)
local RebirthCtl
pcall(function() RebirthCtl = require(ReplicatedStorage.Controllers.Game.RebirthController) end)
local BestShown = false

local function GameBestAffordable()
    if type(RebirthCtl) ~= "table" or type(RebirthCtl.GetBestAffordableOption) ~= "function" then return nil end
    local Ok, V = pcall(RebirthCtl.GetBestAffordableOption, RebirthCtl)
    if not Ok or V == nil then Ok, V = pcall(RebirthCtl.GetBestAffordableOption) end
    if not BestShown then
        BestShown = true
        Log("[TapSim] game's best affordable rebirth: " .. Dump(V, 0, 2))
    end
    if type(V) == "number" then return V end
    if type(V) == "table" then return tonumber(V.Index or V.Button or V.Slot or V.Option or V[1]) end
    return nil
end

local function DoRebirth()
    local Best = GameBestAffordable()
    if Best and (Best < 1 or Best > Config.RebirthMaxButton) then Best = nil end

    -- a bigger button than the affordable one is close: wait for it (or try it if the guess is near)
    for Index = MaxButton, (Best or 0) + 1, -1 do
        if os.clock() >= (RebirthRest[Index] or 0) then
            local Cost = ButtonCost(Index)
            if not Cost then
                if not Best and PressRebirth(Index) then return true end
            elseif Coins() >= Cost * 0.85 then
                -- cost is only estimated: just try it
                if PressRebirth(Index, true) then return true end
            elseif Coins() + Income * Config.RebirthSaveWindow >= Cost then
                return false
            end
        end
    end

    -- the best button the game says you can afford
    if Best and PressRebirth(Best, true) then return true end
    return false
end

----------------------------------------------------------------
-- DOUBLE JUMP + ISLAND UNLOCK
----------------------------------------------------------------
local SavingGems = false
local LastJumpTry = 0

local function JumpsNeeded(Island)
    if Config.JumpsNeeded[Island] then return Config.JumpsNeeded[Island] end
    local L = Landings[Island]
    local J = type(L) == "table" and tonumber(L.Jumps)
    if J then return math.max(J - Config.JumpOffset, 0) end
    local Index = IslandIndex[Island]
    return Index and math.max(Index - 2, 0) or 0
end

-- game's own double jump code (client module), if it has a buy function we can call
local JumpModule, JumpModuleFns = nil, {}
for _, M in ipairs(ReplicatedStorage:GetDescendants()) do
    if M:IsA("ModuleScript") and M.Name:lower():find("doublejump") then
        local Ok, V = pcall(require, M)
        if Ok and type(V) == "table" then
            for K, F in pairs(V) do
                if type(F) == "function" then
                    local L = tostring(K):lower()
                    local Robux = L:find("robux") or L:find("product") or L:find("prompt") or L:find("gamepass") or L:find("token")
                    if (L:find("purchase") or L:find("buy")) and not Robux then
                        JumpModule = JumpModule or V
                        table.insert(JumpModuleFns, {Module = V, Name = K, Path = M:GetFullName()})
                    end
                end
            end
        end
    end
end

local JumpFullPass = false

local function JumpCandidates()
    local W, J = World(), Jumps()
    local List = {}

    -- learned from the game: same request, numbers moved to the next level
    if Learned.DoubleJump then
        table.insert(List, Learned.DoubleJump)
        local First = Learned.DoubleJump[1]
        if type(First) == "table" then
            for K, V in pairs(First) do
                if type(V) == "number" then
                    for _, N in ipairs({J + 1, J + 2}) do
                        local T = {}
                        for K2, V2 in pairs(First) do T[K2] = V2 end
                        T[K] = N
                        table.insert(List, {T})
                    end
                end
            end
        end
    end

    -- guesses: {World = "Main"} is understood by the server, it just wants one more field
    for _, Key in ipairs({"Level", "Tier", "Index", "Jumps", "Target", "Amount", "Count", "Id"}) do
        for _, N in ipairs((Key == "Amount" or Key == "Count") and {1} or {J + 1, J + 2}) do
            table.insert(List, {{World = W, [Key] = N}})
        end
    end
    for _, N in ipairs({J + 1, J + 2}) do
        table.insert(List, {W, N})
        table.insert(List, {N})
    end
    return List
end

-- the double jump shop only sells while you stand at its upgrade point: find it in workspace
local JumpPointShown = false
local JumpPadShown = false
local function FindJumpPoint()
    if Config.JumpPoint then return Config.JumpPoint end
    local Found = {}
    local function Add(Obj, Why)
        local Pos = GetPosition(Obj)
        if Pos then table.insert(Found, {Pos = Pos, Name = Obj:GetFullName(), Why = Why, Obj = Obj}) end
    end
    for _, Obj in ipairs(workspace:GetDescendants()) do
        local L = Obj.Name:lower()
        if (Obj:IsA("BasePart") or Obj:IsA("Model")) and (L:find("doublejump") or L:find("double jump") or L:find("jumpshop")
            or L:find("jumpupgrade") or L:find("upgradepoint")) then
            Add(Obj, "name")
        elseif Obj:IsA("ProximityPrompt") and (Obj.ActionText .. Obj.ObjectText):lower():find("jump") then
            if Obj.Parent then Add(Obj.Parent, "prompt") end
        elseif Obj:IsA("TextLabel") and Obj.Text:lower():find("double jump") then
            local Part = Obj:FindFirstAncestorWhichIsA("BasePart") or Obj:FindFirstAncestorWhichIsA("Model")
            if Part then Add(Part, "sign") end
        end
    end
    if #Found == 0 then return nil end

    local HRP = Root()
    table.sort(Found, function(A, B)
        if not HRP then return false end
        return (A.Pos - HRP.Position).Magnitude < (B.Pos - HRP.Position).Magnitude
    end)
    if not JumpPointShown then
        JumpPointShown = true
        for I = 1, math.min(6, #Found) do
            local F = Found[I]
            print(("[TapSim] double jump point? %s (%s) @ %.1f, %.1f, %.1f"):format(F.Name, F.Why, F.Pos.X, F.Pos.Y, F.Pos.Z))
        end
    end
    return Found[1].Pos, Found[1].Obj
end

local function GoToJumpPoint(Island)
    local Pos, Obj = FindJumpPoint()
    if not Pos then
        -- not streamed in: look around the current island and the jump start of the next one
        local Current = IslandOrder[(IslandIndex[Island] or 2) - 1]
        local L = type(Landings[Island]) == "table" and Landings[Island] or {}
        for _, Spot in ipairs({IslandPos[Current], ToVector(L.From)}) do
            Teleport(Spot + Vector3.new(0, 4, 0))
            task.wait(1.5)
            Pos, Obj = FindJumpPoint()
            if Pos then break end
        end
    end
    if not Pos then
        warn("[TapSim] double jump upgrade point not found. Stand on it and run in F9: print(game.Players.LocalPlayer.Character.HumanoidRootPart.Position) -> put it in Config.JumpPoint")
        return false
    end
    -- the machine model ("double jump machine") has a pad: "Step on the pad!"
    local HRP = Root()
    local Machine
    for _, M in ipairs(workspace:GetDescendants()) do
        if M:IsA("Model") and M.Name:lower():gsub("[%s_]", ""):find("doublejumpmachine") then
            local P = GetPosition(M)
            if P and (not Machine or (HRP and (P - HRP.Position).Magnitude < (GetPosition(Machine) - HRP.Position).Magnitude)) then
                Machine = M
            end
        end
    end

    local Pads = {}
    if Machine then
        for _, Part in ipairs(Machine:GetDescendants()) do
            if Part:IsA("BasePart") then
                local L = Part.Name:lower()
                if Part:FindFirstChildWhichIsA("TouchTransmitter") or L:find("pad") or L:find("touch")
                    or L:find("hitbox") or L:find("trigger") or L:find("zone") then
                    table.insert(Pads, Part)
                end
            end
        end
        if not JumpPadShown then
            JumpPadShown = true
            local Names = {}
            for _, Part in ipairs(Machine:GetDescendants()) do
                if Part:IsA("BasePart") and #Names < 25 then
                    table.insert(Names, Part.Name .. (Part:FindFirstChildWhichIsA("TouchTransmitter") and "*" or ""))
                end
            end
            print(("[TapSim] jump machine %s | pads: %d | parts (* = touch): %s"):format(Machine:GetFullName(), #Pads, table.concat(Names, ", ")))
        end
    end

    local Pad = Pads[1]
    if Pad then
        -- stand inside the pad area (the server checks it), then on top, touch it and step around
        Teleport(Pad.Position)
        task.wait(0.8)
        Teleport(Pad.Position + Vector3.new(0, math.min(Pad.Size.Y / 2, 2) + 2.5, 0))
        HRP = Root()
        for _, P in ipairs(Pads) do
            pcall(function()
                firetouchinterest(HRP, P, 0)
                task.wait(0.1)
                firetouchinterest(HRP, P, 1)
                task.wait(0.05)
                firetouchinterest(HRP, P, 0)
            end)
        end
        local Hum = Humanoid()
        if Hum then
            Hum:MoveTo(Pad.Position + Vector3.new(1, 0, 0))
            task.wait(0.6)
            Hum:MoveTo(Pad.Position)
        end
        task.wait(1.5)
    else
        local Spot = Machine and GetPosition(Machine) or Pos
        if not Near(Spot, 6) then Teleport(Spot + Vector3.new(0, 3, 0)) end
        task.wait(1.5)
    end

    -- if it opens with a prompt, trigger it like a player would
    pcall(function()
        local Prompt = (Machine or Obj) and (Machine or Obj):FindFirstChildWhichIsA("ProximityPrompt", true)
        if Prompt and fireproximityprompt then fireproximityprompt(Prompt) end
    end)
    task.wait(0.5)
    return true, Pads[1]
end

local function InsideUpgradePoint()
    local Ok, C = pcall(require, ReplicatedStorage.Controllers.Game.DoubleJumpShopController)
    if not Ok or type(C) ~= "table" or type(C.IsInsideUpgradePoint) ~= "function" then return nil end
    local Ok2, V = pcall(C.IsInsideUpgradePoint, C)
    if not Ok2 then Ok2, V = pcall(C.IsInsideUpgradePoint) end
    return Ok2 and V or false
end

local function TryBuyJump(Island)
    if not R.JumpBuy then return false end
    -- after one full pass without luck, only retry every 60 s (do it once by hand -> learned)
    if os.clock() - LastJumpTry < (JumpFullPass and 20 or 8) then return false end
    LastJumpTry = os.clock()

    local Before = Jumps()
    local _, Pad = GoToJumpPoint(Island)

    -- move around on the pad until the game itself says we are inside the upgrade point
    local Inside = InsideUpgradePoint()
    if Inside == false and Pad then
        local Half = Pad.Size / 2
        local Spots = {Vector3.new(0, 0, 0)}
        for _, X in ipairs({-0.5, 0, 0.5}) do
            for _, Z in ipairs({-0.5, 0, 0.5}) do
                table.insert(Spots, Vector3.new(Half.X * X, Half.Y + 2.5, Half.Z * Z))
            end
        end
        for _, Off in ipairs(Spots) do
            local HRP = Root()
            if HRP then
                HRP.CFrame = Pad.CFrame * CFrame.new(Off)
                HRP.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait(0.6)
            Inside = InsideUpgradePoint()
            if Inside then break end
        end
    end
    Log("[TapSim] inside double jump upgrade point: " .. tostring(Inside))

    -- 1) the game's own buy function
    for _, F in ipairs(JumpModuleFns) do
        for _, Args in ipairs({{}, {Before + 1}, {Before + 2}}) do
            local Ok, Result = pcall(F.Module[F.Name], table.unpack(Args))
            if not Ok then Ok, Result = pcall(F.Module[F.Name], F.Module, table.unpack(Args)) end
            task.wait(0.6)
            if Jumps() > Before then
                print(("[TapSim] double jump bought with %s.%s -> %d"):format(F.Path, tostring(F.Name), Jumps()))
                return true
            end
            Log(("[TapSim] double jump %s.%s(%s) -> %s %s"):format(F.Path, tostring(F.Name), Dump(Args, 0, 1), tostring(Ok), Dump(Result, 0, 2)))
        end
    end

    -- 2) the remote with learned / guessed arguments
    -- (guesses only on the first pass or when something was learned; the game's own function is retried every time)
    local Shown = {}
    for _, Args in ipairs((JumpFullPass and not Learned.DoubleJump) and {} or JumpCandidates()) do
        if not IsActive() then return false end
        local Ok, Result = Invoke(R.JumpBuy, table.unpack(Args))
        task.wait(0.3)
        if Jumps() > Before or (type(Result) == "table" and Result.Success) then
            task.wait(0.5)
            print(("[TapSim] double jump bought -> %d (args %s)"):format(Jumps(), Dump(Args, 0, 2)))
            Learn("DoubleJump", table.pack(table.unpack(Args)))
            return true
        end
        local Reason = type(Result) == "table" and tostring(Result.Reason) or tostring(Result)
        if not Shown[Reason] or not JumpFullPass then
            Shown[Reason] = true
            Log(("[TapSim] double jump try %s -> %s"):format(Dump(Args, 0, 2), Dump(Result, 0, 2)))
        end
    end

    if not JumpFullPass then
        JumpFullPass = true
        warn("[TapSim] could not buy the double jump by itself. Press BUY in the Double Jumps menu ONCE by hand while the script runs: it learns the request and does the rest alone.")
    end
    return false
end

local LastIslandResult
if R.IslandUnlockResult then
    R.IslandUnlockResult.OnClientEvent:Connect(function(Data)
        LastIslandResult = Data
        Log("[TapSim] island result: " .. Dump(Data, 0, 2))
        -- any successful answer (unlock or travel) means the island is open
        if type(Data) == "table" and Data.Success and type(Data.Island) == "string" then
            Save.Islands[Data.Island] = true
            WriteSave()
        end
    end)
end

local function IslandArgs(Island)
    local Base = Learned.IslandUnlock
    if not Base then return {{Island = Island, Action = "Unlock"}} end
    local Args = {}
    for I, V in ipairs(Base) do
        if type(V) == "table" then
            local T = {}
            for K, X in pairs(V) do T[K] = X end
            if T.Island then T.Island = Island end
            V = T
        elseif type(V) == "string" and IslandIndex[V] then
            V = Island
        end
        Args[I] = V
    end
    return Args
end

local function TryUnlockIsland(Island)
    local L = type(Landings[Island]) == "table" and Landings[Island] or {}
    local From, Landing = ToVector(L.From), ToVector(L.Position) or IslandPos[Island]

    -- go the way a player would: start point, then "jump" up to the landing in small steps, then walk around
    if From then
        Teleport(From + Vector3.new(0, 4, 0))
        task.wait(0.8)
    end
    if Landing then
        local HRP = Root()
        if From and HRP then
            pcall(function() LocalPlayer:RequestStreamAroundAsync(Landing, 5) end)
            local Start, Goal = From + Vector3.new(0, 4, 0), Landing + Vector3.new(0, 4, 0)
            local Steps = 40
            for I = 1, Steps do
                local T = I / Steps
                local Pos = Start:Lerp(Goal, T) + Vector3.new(0, math.sin(T * math.pi) * 12, 0)
                HRP = Root()
                if not HRP then break end
                HRP.CFrame = CFrame.new(Pos)
                HRP.AssemblyLinearVelocity = Vector3.new(0, 30 * (1 - 2 * T), 0)
                task.wait(0.05)
            end
        end
        Teleport(Landing + Vector3.new(0, 4, 0))
        task.wait(1)
        local Hum = Humanoid()
        if Hum then
            for _, Off in ipairs({Vector3.new(10, 0, 0), Vector3.new(0, 0, 10), Vector3.new(-10, 0, 0), Vector3.new(0, 0, -10)}) do
                Hum:MoveTo(Landing + Off)
                task.wait(1.2)
            end
        end
    end
    if IslandUnlocked(Island) then return true end

    LastIslandResult = nil
    Fire(R.IslandUnlock, table.unpack(IslandArgs(Island)))
    task.wait(1.5)
    if not IslandUnlocked(Island) and not Learned.IslandUnlock then
        Fire(R.IslandUnlock, {Island = Island})
        task.wait(1.5)
    end
    if not IslandUnlocked(Island) then
        Invoke(R.IslandTravel, {Source = "Menu", Island = Island})
        task.wait(1.5)
    end
    return IslandUnlocked(Island)
end

----------------------------------------------------------------
-- GOLDEN / DIAMOND / RAINBOW: go onto the machine pad, craft, come back
----------------------------------------------------------------
local MoveLock = false   -- while true the egg loop does not teleport (crafting trip in progress)
local CurrentStage       -- set by the main loop; no machine trips during island / bridge steps
local MachineShown = {}

local function FindMachine(Kind)
    local Keys = Kind == "Rainbow" and {"rainbowmachine", "shinymachine"} or {Kind:lower() .. "machine"}
    local HRP = Root()
    local Best, BestDist
    for _, M in ipairs(workspace:GetDescendants()) do
        if M:IsA("Model") then
            local L = M.Name:lower():gsub("[%s_]", "")
            for _, K in ipairs(Keys) do
                if L == K or L:find("^" .. K) then
                    local P = GetPosition(M)
                    local Dist = (P and HRP) and (P - HRP.Position).Magnitude or 0
                    if P and (not Best or Dist < BestDist) then Best, BestDist = M, Dist end
                end
            end
        end
    end
    return Best
end

local function StandOnPad(Model)
    local Pad
    for _, Part in ipairs(Model:GetDescendants()) do
        if Part:IsA("BasePart") then
            local L = Part.Name:lower()
            if Part:FindFirstChildWhichIsA("TouchTransmitter") or L == "touch" or L:find("pad") or L:find("hitbox") or L:find("trigger") then
                Pad = Pad or Part
            end
        end
    end
    if not MachineShown[Model] then
        MachineShown[Model] = true
        print(("[TapSim] machine %s, pad: %s"):format(Model:GetFullName(), Pad and Pad.Name or "none"))
    end

    local Pos = Pad and Pad.Position or GetPosition(Model)
    Teleport(Pos)
    task.wait(0.5)
    Teleport(Pos + Vector3.new(0, (Pad and math.min(Pad.Size.Y / 2, 2) or 0) + 2.5, 0))
    pcall(function()
        if Pad then
            local HRP = Root()
            firetouchinterest(HRP, Pad, 0)
            task.wait(0.1)
            firetouchinterest(HRP, Pad, 1)
            task.wait(0.05)
            firetouchinterest(HRP, Pad, 0)
        end
    end)
    local Hum = Humanoid()
    if Hum then Hum:MoveTo(Pos + Vector3.new(1, 0, 0)) end
    task.wait(1.2)
end

-- where each machine is (golden: spawn, diamond: Crystal Cave, rainbow: Volcano / Shadow Realm)
local MachineIslands = {
    Golden = {"Spawn"},
    Diamond = {"Crystal Cave"},
    Rainbow = {"Volcano", "Shadow Realm"},
}

-- go to the machine, run Work(), come back to where you were
local function AtMachine(Kind, Work)
    local Machine = FindMachine(Kind)
    local HRP = Root()
    local Back = HRP and HRP.CFrame

    if not Machine then
        -- not streamed in: go to the island(s) the machine is on and look again
        MoveLock = true
        for _, Island in ipairs(MachineIslands[Kind] or {"Spawn"}) do
            local Pos = IslandPos[Island]
            if Pos and IslandUnlocked(Island) then
                Teleport(Pos + Vector3.new(0, 4, 0))
                task.wait(2)
                Machine = FindMachine(Kind)
                if Machine then break end
            end
        end
        if not Machine then
            MoveLock = false
            if Back then Teleport(Back.Position) end
            local Names = {}
            for _, M in ipairs(workspace:GetDescendants()) do
                if M:IsA("Model") and M.Name:lower():find("machine") and #Names < 15 then table.insert(Names, M:GetFullName()) end
            end
            warn(("[TapSim] %s machine not found. Machines in the map: %s"):format(Kind, table.concat(Names, " | ")))
            return false
        end
    end

    MoveLock = true
    local Ok, Err = pcall(function()
        StandOnPad(Machine)
        Work()
    end)
    if not Ok then warn("[TapSim] machine error: " .. tostring(Err)) end
    if Back then Teleport(Back.Position) end
    MoveLock = false
    return Ok
end

-- result screens ("Crafted! ... Continue"): press the button like a click
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local function IsShown(G)
    local PG = LocalPlayer:FindFirstChild("PlayerGui")
    local O = G
    while O and O ~= PG do
        if O:IsA("GuiObject") and not O.Visible then return false end
        if O:IsA("ScreenGui") and not O.Enabled then return false end
        O = O.Parent
    end
    return O == PG
end

local function FindButton(Word)
    local PG = LocalPlayer:FindFirstChild("PlayerGui")
    if not PG then return end
    for _, G in ipairs(PG:GetDescendants()) do
        if (G:IsA("TextLabel") or G:IsA("TextButton")) and G.Text:lower():gsub("%s", "") == Word then
            local Btn = G:IsA("GuiButton") and G or G:FindFirstAncestorWhichIsA("GuiButton")
            if Btn and IsShown(Btn) and IsShown(G) then return Btn end
        end
    end
end

local function PressButton(Btn)
    local Fired = false
    pcall(function()
        for _, Ev in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up"}) do
            for _, C in ipairs(getconnections(Btn[Ev])) do
                pcall(function() C:Fire() end)
                Fired = true
            end
        end
    end)
    if not Fired then
        pcall(function()
            local Inset = GuiService:GetGuiInset()
            local P = Btn.AbsolutePosition + Btn.AbsoluteSize / 2 + Inset
            VirtualInputManager:SendMouseButtonEvent(P.X, P.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(P.X, P.Y, 0, false, game, 0)
        end)
    end
end

local function PressContinue()
    local Btn = FindButton("continue")
    if Btn then
        PressButton(Btn)
        return true
    end
    return false
end

-- always: close result screens that wait for "Continue"
task.spawn(function()
    while IsActive() do
        task.wait(1)
        pcall(PressContinue)
    end
end)

-- wait for the machine's answer, then for the result screen to be closed
local LastMachineAnswer
local function WaitMachine(Machine, Action, Timeout)
    local Deadline = os.clock() + (Timeout or 20)
    repeat task.wait(0.2) until (LastMachineAnswer and LastMachineAnswer.Machine == Machine
        and (not Action or LastMachineAnswer.Action == Action)) or os.clock() > Deadline
    local Answer = LastMachineAnswer

    -- animation + "Continue": keep pressing until the screen is gone (max 12 s)
    local Until = os.clock() + 12
    task.wait(1)
    while os.clock() < Until do
        if not PressContinue() then
            task.wait(0.8)
            if not FindButton("continue") then break end
        end
        task.wait(0.4)
    end
    return Answer
end

local function PickIds(Name, Tier, Shiny, Use)
    local Equipped = EquippedSet()
    local Ids = {}
    local List = OwnedPets()
    table.sort(List, function(A, B) return (Equipped[A.Id] and 1 or 0) < (Equipped[B.Id] and 1 or 0) end)
    for _, P in ipairs(List) do
        if P.Name == Name and P.Tier == Tier and P.Shiny == Shiny and not P.Locked and #Ids < Use then
            table.insert(Ids, P.Id)
        end
    end
    return Ids
end

local function Label(Name, Tier, Shiny)
    return (Shiny and "shiny " or "") .. (Tier ~= "Normal" and (Tier:lower() .. " ") or "") .. Name
end

-- Golden / Diamond / Rainbow machine: PetIds + Craft, answer comes at once
local function Craft(Machine, Name, Tier, Shiny, Use)
    if #PickIds(Name, Tier, Shiny, Use) < Use then return false end
    return AtMachine(Machine, function()
        local Ids = PickIds(Name, Tier, Shiny, Use)
        if #Ids < Use then return end
        LastMachineAnswer = nil
        Fire(R.Machine, {PetIds = Ids, Machine = Machine, Action = "Craft"})
        print(("[TapSim] %s machine: %d x %s ... waiting for the result"):format(Machine, #Ids, Label(Name, Tier, Shiny)))
        local Answer = WaitMachine(Machine, nil, 20)
        local Result = not Answer and "no answer"
            or (Answer.Success == false and ("refused: " .. tostring(Answer.Reason)))
            or (Answer.Crafted == false and "FAILED (bad luck)") or "success"
        print(("[TapSim] %s machine done: %s"):format(Machine, Result))
    end)
end

-- Rainbow machine (the game sends Machine = "Shiny"): Start with diamonds -> wait 30 s -> Claim
-- (CraftId saved, also survives a restart)
local function RainbowStart(Name, Shiny)
    if #PickIds(Name, "Diamond", Shiny, Config.RainbowUse) < Config.RainbowUse then return false end
    return AtMachine("Rainbow", function()
        local Ids = PickIds(Name, "Diamond", Shiny, Config.RainbowUse)
        if #Ids < Config.RainbowUse then return end
        LastMachineAnswer = nil
        Fire(R.Machine, {PetIds = Ids, Machine = "Shiny", Action = "Start"})
        print(("[TapSim] rainbow started: %d x %s (ready in 30 s)"):format(#Ids, Label(Name, "Diamond", Shiny)))
        local Answer = WaitMachine("Shiny", "Start", 15)
        if Answer and Answer.Success == false then print("[TapSim] rainbow refused: " .. tostring(Answer.Reason)) end
    end)
end

if R.MachineResult then
    R.MachineResult.OnClientEvent:Connect(function(Data)
        if type(Data) ~= "table" then return end
        LastMachineAnswer = Data
        Log("[TapSim] machine result: " .. Dump(Data, 0, 1))
        if Data.Machine == "Shiny" and Data.Success and Data.CraftId then
            Save.Rainbow = Save.Rainbow or {}
            if Data.Action == "Start" then
                Save.Rainbow[Data.CraftId] = tonumber(Data.EndTime) or (os.time() + (tonumber(Data.Duration) or 30))
            elseif Data.Action == "Claim" then
                Save.Rainbow[Data.CraftId] = nil
            end
            WriteSave()
        end
    end)
end

local function RainbowClaims()
    local Ready = {}
    for Id, EndTime in pairs(Save.Rainbow or {}) do
        if os.time() >= (tonumber(EndTime) or 0) + 1 then table.insert(Ready, Id) end
    end
    if #Ready == 0 then return end
    AtMachine("Rainbow", function()
        for _, Id in ipairs(Ready) do
            LastMachineAnswer = nil
            Fire(R.Machine, {Machine = "Shiny", Action = "Claim", CraftId = Id})
            print("[TapSim] rainbow claim: " .. Id)
            WaitMachine("Shiny", "Claim", 15)
        end
    end)
    -- if the game never answers, do not try the same id forever
    task.delay(10, function()
        for _, Id in ipairs(Ready) do
            if Save.Rainbow and Save.Rainbow[Id] then Save.Rainbow[Id] = nil end
        end
        WriteSave()
    end)
end

local function AutoCraft()
    if CurrentStage and (CurrentStage.Unlock or CurrentStage.Bridge) then return end

    -- finished rainbows first
    RainbowClaims()

    -- tiers, separately for shiny (from eggs) and normal copies
    for _, Shiny in ipairs({true, false}) do
        for _, Name in ipairs(Config.Golden) do
            if CountPet(Name, "Normal", Shiny) >= Config.GoldenWhenCopies then
                Craft("Golden", Name, "Normal", Shiny, Config.GoldenUse)
            end
        end
        for _, Name in ipairs(Config.Diamond) do
            if CountPet(Name, "Golden", Shiny) >= Config.DiamondUse then
                Craft("Diamond", Name, "Golden", Shiny, Config.DiamondUse)
            end
        end
        for _, Name in ipairs(Config.Rainbow) do
            if CountPet(Name, "Diamond", Shiny) >= Config.RainbowUse then
                RainbowStart(Name, Shiny)
            end
        end
    end
end

----------------------------------------------------------------
-- STORAGE CLEANUP
----------------------------------------------------------------
local Protected = {}
for _, Name in ipairs(Config.KeepPets) do Protected[Name] = true end
for _, Name in ipairs(Config.Golden) do Protected[Name] = true end
for _, Name in ipairs(Config.Diamond) do Protected[Name] = true end
for _, Name in ipairs(Config.Rainbow) do Protected[Name] = true end

local CleanTier = {}
for _, T in ipairs(Config.CleanupTiers) do CleanTier[T] = true end
for _, S in ipairs(Config.Stages) do
    if S.UntilPet then Protected[S.UntilPet] = true end
end

local KeepRarity = {}
for _, Name in ipairs(Config.KeepRarities) do KeepRarity[Name] = true end

local function Cleanup()
    local List = OwnedPets()
    local Limit = StorageLimit()
    if Limit - #List >= Config.CleanupWhenFree then return end

    local Equipped, EquippedCount = EquippedSet()
    if EquippedCount == 0 then
        Log("[TapSim] storage full but equipped pets could not be read; cleanup skipped for safety")
        return
    end

    local Junk = {}
    for _, P in ipairs(List) do
        if not Equipped[P.Id] and not P.Locked and CleanTier[P.Tier] and (Config.CleanupShiny or not P.Shiny) and not Protected[P.Name]
            and not IsSecret(P.Name) and not KeepRarity[tostring(P.Rarity)] then
            table.insert(Junk, P)
        end
    end
    table.sort(Junk, function(A, B) return A.Power < B.Power end)

    local ToDelete = {}
    local Need = Config.CleanupKeepFree - (Limit - #List)
    for I = 1, math.min(Need, #Junk) do table.insert(ToDelete, Junk[I].Id) end

    if #ToDelete > 0 then
        print(("[TapSim] storage %d/%d -> deleting %d weakest pets"):format(#List, Limit, #ToDelete))
        DeletePets(ToDelete)
    end
end

----------------------------------------------------------------
-- AUTO DELETE (game's own, per egg)
----------------------------------------------------------------
local AutoDeleteSent = {}
local function SetAutoDelete(Egg, Pets)
    if not R.AutoDelete or #Pets == 0 or AutoDeleteSent[Egg] then return end
    AutoDeleteSent[Egg] = true

    -- the field the game uses for the tier is learned when you change the tier in the egg menu by hand
    -- (Learned.AutoDeleteTierKey); until then "Tier" is used
    local TierKey = Learned.AutoDeleteTierKey or "Tier"
    for _, T in ipairs(Config.AutoDeleteTiers) do
        if T == "Normal" then
            Fire(R.AutoDelete, {Egg = Egg, Entries = Pets})
        else
            Fire(R.AutoDelete, {Egg = Egg, Entries = Pets, [TierKey] = T})
        end
        task.wait(0.2)
    end
    print(("[TapSim] auto delete %s (%s): %s"):format(Egg, table.concat(Config.AutoDeleteTiers, "/"), table.concat(Pets, ", ")))
    task.delay(2, function()
        local Data = D()
        local A = Data and Data.Eggs and Data.Eggs.AutoDelete
        Log(("[TapSim] game's auto delete for %s now: %s"):format(Egg, Dump(type(A) == "table" and A[Egg] or A, 0, 3)))
    end)
end

local function FinalDeleteList()
    local Info = EggInfo(FinalEgg)
    local Pets = Info and Info.Pets
    local Limit = type(Pets) == "table" and tonumber(Pets[Config.FinalDeleteUpTo])
    local List = {}
    if not Limit then return List end
    for Name, Chance in pairs(Pets) do
        if tonumber(Chance) and tonumber(Chance) >= Limit and not Protected[Name] and not IsSecret(Name) then
            table.insert(List, Name)
        end
    end
    return List
end

for Egg, Pets in pairs(Config.AutoDelete) do SetAutoDelete(Egg, Pets) end

----------------------------------------------------------------
-- STATUS
----------------------------------------------------------------
local Status = "starting"
local StageName = "-"

local StatusLogged = {}
local function SetStatus(Text)
    Status = Text
    -- the same line at most every 20 s
    local Key = Text:gsub("[%d%.]+%a*", "#")
    if os.clock() - (StatusLogged[Key] or -100) > 20 then
        StatusLogged[Key] = os.clock()
        Log("[TapSim] " .. Text)
    end
end

-- income from lifetime coins (does not drop on rebirth)
task.spawn(function()
    local function Lifetime()
        local Data = D()
        return Data and Data.Statistics and tonumber(Data.Statistics.LifetimeCoins) or 0
    end
    local Last, LastT = Lifetime(), os.clock()
    while IsActive() do
        task.wait(10)
        local Now, T = Lifetime(), os.clock()
        Income = math.max((Now - Last) / (T - LastT), 0)
        Last, LastT = Now, T
    end
end)

----------------------------------------------------------------
-- STAGES
----------------------------------------------------------------
local function HighestIsland()
    local Best = 1
    for I, Name in ipairs(IslandOrder) do
        if IslandUnlocked(Name) then Best = I end
    end
    return Best
end

local function StageDone(S)
    if S.Final then return false end
    if S.Unlock then return IslandUnlocked(S.Unlock) end
    if S.Bridge then
        local Data = D()
        return S._Done or (Data and Data.Progression and Data.Progression.BridgeLowered) or HighestIsland() >= 2
    end
    if S.RebirthButton then
        return (tonumber(Save.Pressed[tostring(S._Index)]) or 0) >= (S.Times or 1)
    end
    if S.Rebirths then
        return Rebirths() >= S.Rebirths or (S.OrIncome and Income >= S.OrIncome) or false
    end
    if S.MoreRebirths then
        return S._Start ~= nil and Rebirths() >= S._Start + S.MoreRebirths
    end
    if S.UntilPet then return CountPet(S.UntilPet) >= (S.Pets or 1) end
    if S.Egg then return OpenedFrom(S.Egg) >= (S.Eggs or 1) end
    return S._Done == true
end

local function ShouldSkip(S)
    -- steps of islands you already passed
    local Island = S.Unlock or S.Island
    local Index = IslandIndex[Island or ""]
    local Highest = HighestIsland()
    if Index and Index < Highest then return true end
    if S.Unlock and Index and Index <= Highest then return true end
    -- strong pets: no hatching except endgame
    if S.Egg and not S.Final and Power() >= Config.StrongPower then return true end
    return StageDone(S)
end

-- how many eggs per hatch this account can open (8 with the gamepass, else 3)
local MaxHatch = tonumber(Config.HatchCount) ~= 0 and tonumber(Config.HatchCount) or tonumber(Save.MaxHatch)
local HatchTryIndex = 1

local function SetMaxHatch(N, Why)
    MaxHatch = N
    Save.MaxHatch = N
    WriteSave()
    print(("[TapSim] eggs per hatch: %d (%s)"):format(N, Why))
end

local function HatchCount()
    return MaxHatch or 3
end

local function NextHatchTry()
    return Config.HatchCountTry[HatchTryIndex] or 3
end

-- the gamepass list may already tell it
if not MaxHatch then
    pcall(function()
        local Data = D()
        local Found = {}
        local function Scan(T, Depth)
            if type(T) ~= "table" or Depth > 3 then return end
            for K, V in pairs(T) do
                local Text = (tostring(K) .. " " .. (type(V) ~= "table" and tostring(V) or "")):lower()
                if Text:find("hatch") then table.insert(Found, tostring(K) .. "=" .. tostring(V)) end
                -- only the NAME counts (a value like HatchSpeed = 8 is not the gamepass)
                local Key = tostring(K):lower()
                if type(K) == "number" and type(V) == "string" then Key = V:lower() end   -- list of gamepass names
                if type(V) ~= "table" and (((Key:find("8") or Key:find("eight")) and Key:find("hatch")) or Key:find("octo")) then
                    if V ~= false and V ~= 0 and V ~= nil then MaxHatch = 8 end
                end
                Scan(V, Depth + 1)
            end
        end
        Scan(Data and Data.Monetization, 0)
        Log("[TapSim] hatch gamepass data: " .. (#Found > 0 and table.concat(Found, ", ") or "none"))
        if MaxHatch then SetMaxHatch(MaxHatch, "8-hatch gamepass found") end
    end)
end

local function RunHatch(S)
    local Egg = S.Final and FinalEgg or S.Egg
    if S.Final then SetAutoDelete(FinalEgg, FinalDeleteList()) end

    local LastEquip = 0
    while IsActive() and (S.Final or not StageDone(S)) do
        if not S.Final and Power() >= Config.StrongPower then return end

        while MoveLock and IsActive() do task.wait(0.2) end
        GoToEgg(Egg)
        local Count = S.Count or HatchCount()
        local Testing = false
        -- auto hatch count not known yet: try the next bigger count once (if the coins are there)
        if not S.Count and not MaxHatch and Price and Coins() >= Price * NextHatchTry() then
            Count = NextHatchTry()
            Testing = true
        end
        local Price = EggPrice(Egg)

        -- step wants a minimum total of rebirths before this egg
        if S.MinRebirths and Rebirths() < S.MinRebirths then
            SetStatus(("rebirthing to %s before %s egg (%s)"):format(Short(S.MinRebirths), Egg, Short(Rebirths())))
            DoRebirth()
            task.wait(Config.RebirthDelay)
            continue
        end

        -- saving for the 3-hatch would take too long: open them one by one
        if Price and Count > 1 and Coins() < Price * Count and Config.MultiHatchMaxWait > 0 then
            -- income is measured every 10 s; until then (Income = 0) keep the 3-hatch and just save
            if Income > 0 then
                local Wait = (Price * Count - Coins()) / Income
                if Wait > Config.MultiHatchMaxWait then
                    SetStatus(("%s x%d needs %s more, about %d min at %s/s -> opening 1 by 1"):format(
                        Egg, Count, Short(Price * Count - Coins()), math.ceil(Wait / 60), Short(Income)))
                    Count = 1
                end
            end
        end

        if Price and Coins() < Price * Count then
            if Coins() >= Price then
                Count = 1
            else
                local Wait = Income > 0 and (Price * Count - Coins()) / Income or math.huge
                if Config.EggMaxWait > 0 and Wait > Config.EggMaxWait and DoRebirth() then
                    SetStatus(("%s egg is %s away (%.0f s) -> rebirth first"):format(Egg, Short(Price * Count - Coins()), math.min(Wait, 1e9)))
                    task.wait(Config.RebirthDelay)
                    continue
                end
                SetStatus(("saving coins for %s egg (%s / %s)"):format(Egg, Short(Coins()), Short(Price * Count)))
                task.wait(1)
                continue
            end
        end

        SetStatus("hatching " .. Egg)
        HatchSeq += 1
        LastHatchAnswer = nil
        Fire(R.Hatch, {Egg = Egg, Count = Count, Seq = HatchSeq, Auto = false})

        if Testing then
            local Deadline = os.clock() + 4
            repeat task.wait(0.1) until LastHatchAnswer or os.clock() > Deadline
            local A = LastHatchAnswer
            local Got = A and A.Success and (tonumber(A.Rolls) or tonumber(A.Count)) or nil
            if Got and Got >= Count then
                SetMaxHatch(Count, "the game hatched " .. Got)
            elseif Got then
                SetMaxHatch(Got, "the game hatched only " .. Got)
            else
                HatchTryIndex += 1
                Log(("[TapSim] %d-hatch refused (%s), trying smaller"):format(Count, A and tostring(A.Reason or A.Error) or "no answer"))
                if HatchTryIndex > #Config.HatchCountTry then SetMaxHatch(3, "fallback") end
            end
        end

        if os.clock() - LastEquip > 10 then
            LastEquip = os.clock()
            EquipBest()
        end
        task.wait(Config.HatchDelay)
    end
    EquipBest()
end

local function RunRebirth(S)
    if S.MoreRebirths and not S._Start then
        S._Start = Rebirths()
        Save.Starts[tostring(S._Index)] = S._Start
        WriteSave()
    end
    while IsActive() and not StageDone(S) do
        local Target = S.Rebirths or (S._Start + S.MoreRebirths)
        if S.OrIncome and Target == math.huge then
            SetStatus(("rebirthing until %s/s income (now %s/s, rebirths %s)"):format(Short(S.OrIncome), Short(Income), Short(Rebirths())))
        else
            SetStatus(("rebirthing: %s / %s"):format(Short(Rebirths()), Short(Target)))
        end
        DoRebirth()
        task.wait(Config.RebirthDelay)
    end
end

local function RunRebirthButton(S)
    local Key = tostring(S._Index)
    local Amount = 5 ^ (S.RebirthButton - 1)
    while IsActive() and not StageDone(S) do
        RebirthAnswer = nil
        Fire(R.Rebirth, {Index = S.RebirthButton})

        local Deadline = os.clock() + 0.8
        repeat task.wait(0.05) until RebirthAnswer or os.clock() > Deadline

        if RebirthAnswer and RebirthAnswer.Success and tonumber(RebirthAnswer.Index) == S.RebirthButton then
            Save.Pressed[Key] = (tonumber(Save.Pressed[Key]) or 0) + 1
            WriteSave()
            print(("[TapSim] rebirth +%s done (%d / %d) -> total %s"):format(Short(Amount), Save.Pressed[Key], S.Times or 1, Short(Rebirths())))
        else
            local Price = RebirthAnswer and tonumber(RebirthAnswer.Price)
            SetStatus(("saving coins for the +%s rebirth button (%s%s)"):format(Short(Amount), Short(Coins()),
                Price and (" / " .. Short(Price)) or ""))
            task.wait(1)
        end
    end
end

local function RunBridge(S)
    local Progress, Power_, Lowered, LastChange = 0, 0, false, os.clock()
    local Conn = R.CrankResult and R.CrankResult.OnClientEvent:Connect(function(Data)
        if type(Data) ~= "table" then return end
        if Data.Lowered then Lowered = true end
        local P = tonumber(Data.Progress)
        if P and P > Progress then Progress = P; LastChange = os.clock() end
        Power_ = tonumber(Data.Power) or Power_
    end)

    while IsActive() and not StageDone(S) and not Lowered do
        Teleport(BridgeStand)
        Fire(R.BridgeEngage, {Engaged = true})
        LastChange = os.clock()
        SetStatus("breaking the bridge (tapping)")

        while IsActive() and not Lowered and not StageDone(S) and os.clock() - LastChange < 12 do
            if not Near(BridgeStand, 20) then Teleport(BridgeStand) end
            task.wait(0.5)
        end

        Fire(R.BridgeEngage, {Engaged = false})
        if Lowered or StageDone(S) then break end

        -- no progress: tap power too low (needs about 700). Rebirth for a minute and try again.
        SetStatus(("bridge not moving (power %s, progress %s) -> rebirthing 60 s"):format(Short(Power_), Short(Progress)))
        local Until = os.clock() + 60
        while IsActive() and os.clock() < Until do
            DoRebirth()
            task.wait(Config.RebirthDelay)
        end
    end

    if Conn then Conn:Disconnect() end
    if Lowered or StageDone(S) then
        S._Done = true
        Save.Done[tostring(S._Index)] = true
        WriteSave()
        print("[TapSim] bridge is down")
    end
end

local function RunUnlock(S)
    local Island = S.Unlock
    local Tries, LastRoute, LastBuy = 0, 0, 0

    -- the game's DoubleJumps number does not show bought jumps, so the script does not wait for it:
    -- it tries the jump route, then the shop (fails harmlessly if already owned), then rebirths for gems
    while IsActive() and not IslandUnlocked(Island) do
        local Price = type(IslandCfg[Island]) == "table" and tonumber(IslandCfg[Island].Price)

        if S.MinRebirths and Rebirths() < S.MinRebirths then
            SetStatus(("rebirthing to %s before %s (%s)"):format(Short(S.MinRebirths), Island, Short(Rebirths())))
            DoRebirth()
            task.wait(Config.RebirthDelay)
            continue
        end

        -- 1) jump route / unlock (every 30 s, or right away when the coins for the gate are there)
        if os.clock() - LastRoute > 30 or (Price and Coins() >= Price and os.clock() - LastRoute > 8) then
            LastRoute = os.clock()
            SetStatus("unlocking " .. Island .. ((Price and Coins() >= Price) and " (enough coins)" or " (jump route)"))
            if TryUnlockIsland(Island) then break end
            Tries += 1
            if Tries == 4 then
                warn(("[TapSim] could not unlock %s by itself yet. If you can, unlock it ONCE by hand while the script runs; it learns the request."):format(Island))
            end
        end

        -- 2) next double jump at the shop pad (every 40 s)
        if Jumps() < JumpsNeeded(Island) and os.clock() - LastBuy > 40 then
            LastBuy = os.clock()
            SavingGems = true
            SetStatus(("buying a double jump for %s (have %d, need %d, gems %s)"):format(Island, Jumps(), JumpsNeeded(Island), Short(Gems())))
            TryBuyJump(Island)
        end

        -- 3) meanwhile: rebirth for gems
        SetStatus(("%s locked -> rebirthing for gems (%s), next try soon"):format(Island, Short(Gems())))
        DoRebirth()
        task.wait(Config.RebirthDelay)
    end

    SavingGems = false
    if IslandUnlocked(Island) then
        print("[TapSim] island unlocked: " .. Island)
        GoToIsland(Island)
    end
end

local function RunGoldenQuest(S)
    local Counts = {}
    for _, P in ipairs(OwnedPets()) do
        if P.Tier == "Normal" and not P.Shiny then Counts[P.Name] = (Counts[P.Name] or 0) + 1 end
    end
    local Best, BestN = nil, 0
    for Name, N in pairs(Counts) do
        if N > BestN then Best, BestN = Name, N end
    end
    if Best and BestN >= 5 then
        Craft("Golden", Best, "Normal", false, 5)
        EquipBest()
    else
        Log("[TapSim] golden quest skipped (no 5 copies of one pet)")
    end
    S._Done = true
    Save.Done[tostring(S._Index)] = true
    WriteSave()
end

local function RunStage(S)
    if S.Island and S.Island ~= "Spawn" then GoToIsland(S.Island) end
    if S.Island == "Spawn" and not Near(IslandPos.Spawn, 300) then Teleport(IslandPos.Spawn + Vector3.new(0, 4, 0)) end

    if S.Unlock then RunUnlock(S)
    elseif S.Bridge then RunBridge(S)
    elseif S.RebirthButton then RunRebirthButton(S)
    elseif S.Rebirths or S.MoreRebirths then RunRebirth(S)
    elseif S.GoldenQuest then RunGoldenQuest(S)
    elseif S.Egg or S.Final then RunHatch(S)
    end
end

----------------------------------------------------------------
-- START INFO
----------------------------------------------------------------
do
    local Data = D()
    local Sample
    for _, E in pairs(Data.Pets and Data.Pets.Owned or {}) do Sample = E break end
    local _, EqN = EquippedSet()
    local EggN = 0
    for _, V in pairs(EggCfg) do if type(V) == "table" then EggN += 1 end end
    local LandN = 0
    for _ in pairs(Landings) do LandN += 1 end

    print(("[TapSim] %s | coins %s, gems %s, rebirths %s, pet power %s, pets %d/%d (equipped %d), double jumps %d"):format(
        VERSION, Short(Coins()), Short(Gems()), Short(Rebirths()), Short(Power()), #OwnedPets(), StorageLimit(), EqN, Jumps()))
    print("[TapSim] pet sample: " .. Dump(Sample, 0, 2))
    local Tiers = {}
    for _, E in pairs(Data.Pets and Data.Pets.Owned or {}) do
        if type(E) == "table" then
            local Raw = tostring(E.Tier)
            Tiers[Raw] = (Tiers[Raw] or 0) + 1
        end
    end
    print("[TapSim] pet tiers in the game data: " .. Dump(Tiers, 0, 1))
    -- every field any pet has (to see how the game marks shiny pets)
    local Keys, KeyList = {}, {}
    for _, E in pairs(Data.Pets and Data.Pets.Owned or {}) do
        if type(E) == "table" then
            for K, V in pairs(E) do
                local Key = tostring(K)
                if not Keys[Key] then
                    Keys[Key] = true
                    table.insert(KeyList, Key .. (type(V) ~= "table" and ("=" .. tostring(V)) or ""))
                end
            end
        end
    end
    print("[TapSim] pet fields: " .. table.concat(KeyList, ", "))
    print("[TapSim] equipped raw: " .. Dump(Data.Pets and Data.Pets.Equipped, 0, 2))
    local P = Data.Progression or {}
    print("[TapSim] islands: " .. Dump(P.UnlockedIslands, 0, 2) .. " | zones: " .. Dump(P.UnlockedZones, 0, 2)
        .. " | first visits: " .. Dump(P.IslandFirstVisits, 0, 2) .. " | portals: " .. Dump(P.PortalFirstVisits, 0, 2)
        .. " | routes: " .. Dump(P.IslandRoutes, 0, 2) .. " | now on: " .. tostring(P.Island))
    print(("[TapSim] saved progress: step %s, islands %s"):format(tostring(Save.Stage), Dump(Save.Islands, 0, 1)))

    -- every value with "jump" in its name (player data, player / character attributes)
    local Hits = {}
    local function Scan(T, Path, Depth)
        if Depth > 4 or #Hits > 20 then return end
        for K, V in pairs(T) do
            local KP = Path .. "." .. tostring(K)
            if tostring(K):lower():find("jump") then table.insert(Hits, KP .. "=" .. Dump(V, 0, 2)) end
            if type(V) == "table" and tostring(K) ~= "_uq" and tostring(K) ~= "Owned" then Scan(V, KP, Depth + 1) end
        end
    end
    Scan(Data, "Data", 0)
    for _, Obj in ipairs({LocalPlayer, LocalPlayer.Character}) do
        for K, V in pairs(Obj and Obj:GetAttributes() or {}) do
            if K:lower():find("jump") then table.insert(Hits, Obj.Name .. "@" .. K .. "=" .. tostring(V)) end
        end
    end
    print("[TapSim] jump data: " .. (#Hits > 0 and table.concat(Hits, " | ") or "none"))
    local Fns = {}
    for _, F in ipairs(JumpModuleFns) do table.insert(Fns, F.Path .. "." .. tostring(F.Name)) end
    pcall(function()
        local C = require(ReplicatedStorage.Controllers.Game.DoubleJumpShopController)
        local Names = {}
        for K, V in pairs(C) do table.insert(Names, tostring(K) .. (type(V) == "function" and "()" or "")) end
        table.insert(Fns, "DoubleJumpShopController: " .. table.concat(Names, ", "))
    end)
    print("[TapSim] jump functions: " .. table.concat(Fns, " | "))
    print(("[TapSim] config: %d eggs, %d landings, final egg %s, learned: %s"):format(EggN, LandN, FinalEgg, Dump(Learned, 0, 3)))
end

----------------------------------------------------------------
-- BACKGROUND: tap, equip best, skill tree, cleanup + crafting, rewards
----------------------------------------------------------------
if Config.AutoTap and R.Tap then
    task.spawn(function()
        local Owed, Last = 0, os.clock()
        while IsActive() do
            local Now = os.clock()
            Owed = math.min(Owed + (Now - Last) * Config.TapsPerSecond, Config.TapsPerSecond)
            Last = Now
            while Owed >= 1 do
                Owed -= 1
                TapSeq += 1
                Fire(R.Tap, {ClientSequence = TapSeq, Auto = false, Source = "screen"})
                HatchStats.Taps += 1
            end
            task.wait()
        end
    end)
end

task.spawn(function()
    while IsActive() do
        EquipBest()
        task.wait(Config.EquipBestEvery)
    end
end)

-- skill tree: config list first, then every node found in a SkillTree config module (cheapest first)
local SkillNames = {}
do
    local Seen, Found = {}, {}
    for _, Name in ipairs(Config.SkillTree) do
        if not Seen[Name] then Seen[Name] = true; table.insert(SkillNames, Name) end
    end
    for _, M in ipairs(ReplicatedStorage:GetDescendants()) do
        if M:IsA("ModuleScript") and M.Name:lower():find("skilltree") then
            local Ok, V = pcall(require, M)
            if Ok and type(V) == "table" then
                local Nodes = type(V.Nodes) == "table" and V.Nodes or type(V.Skills) == "table" and V.Skills or V
                for K, Node in pairs(Nodes) do
                    if type(Node) == "table" then
                        local Name = type(K) == "string" and K or Node.Name
                        local Price = tonumber(Node.Price or Node.Cost)
                        if type(Name) == "string" and Price and not Seen[Name] then
                            Seen[Name] = true
                            table.insert(Found, {Name = Name, Price = Price})
                        end
                    end
                end
            end
        end
    end
    table.sort(Found, function(A, B) return A.Price < B.Price end)
    for _, F in ipairs(Found) do table.insert(SkillNames, F.Name) end
    Log(("[TapSim] skill tree: %d nodes known"):format(#SkillNames))
end

if Config.AutoSkillTree and R.SkillUnlock then
    task.spawn(function()
        local Failed = {}
        while IsActive() do
            if not SavingGems then
                for _, Name in ipairs(SkillNames) do
                    if not IsActive() or SavingGems then break end
                    if not SkillOwned(Name) and os.clock() >= (Failed[Name] or 0) then
                        local Ok, Result = Invoke(R.SkillUnlock, {Name = Name})
                        if Ok and type(Result) == "table" and Result.Success then
                            HatchStats.Skills += 1
                            Log(("[TapSim] skill unlocked: %s (%s gems)"):format(Name, Short(Result.Price)))
                        else
                            Failed[Name] = os.clock() + 60
                        end
                        task.wait(0.15)
                    end
                end
            end
            task.wait(Config.SkillTreeEvery)
        end
    end)
end

-- egg -> island (from the game's egg config, the scanned egg list as fallback)
local EggIsland = {
    Basic = "Spawn", Spotted = "Spawn", Spiked = "Spawn", Nimbus = "Sky Island", Sky = "Sky Island",
    Pumpkin = "Autumn", Mushroom = "Mushroom", Mycelium = "Mushroom", Cactus = "Desert",
    Geode = "Crystal Cave", Crystal = "Crystal Cave", Void = "Shadow Realm", Volcanic = "Volcano", Draconic = "Volcano",
}
for Name, Info in pairs(EggCfg) do
    if type(Info) == "table" and type(Info.Island) == "string" and IslandIndex[Info.Island] then
        EggIsland[Name] = Info.Island
    end
end

local KeepPet = {}
for _, Name in ipairs(Config.KeepPets) do KeepPet[Name] = true end

local function DeleteOldIslandPets()
    local Highest = HighestIsland()
    if Highest <= 1 then return end

    local Equipped, EquippedCount = EquippedSet()
    if EquippedCount == 0 then return end   -- safety: equipped pets not readable

    local Ids = {}
    for _, P in ipairs(OwnedPets()) do
        local Island = P.SourceEgg and EggIsland[P.SourceEgg]
        local Index = Island and IslandIndex[Island]
        if Index and Index < Highest and not Equipped[P.Id] and not P.Locked and not IsSecret(P.Name)
            and not KeepPet[P.Name] and not KeepRarity[tostring(P.Rarity)] and (Config.CleanupShiny or not P.Shiny) then
            table.insert(Ids, P.Id)
        end
    end

    if #Ids > 0 then
        print(("[TapSim] deleting %d pets from islands before %s"):format(#Ids, IslandOrder[Highest]))
        DeletePets(Ids)
    end
end

task.spawn(function()
    while IsActive() do
        task.wait(15)
        pcall(AutoCraft)
        if Config.DeleteOldIslandPets then pcall(DeleteOldIslandPets) end
        if Config.Cleanup then pcall(Cleanup) end
    end
end)

task.spawn(function()
    while IsActive() do
        if Config.ClaimIndexRewards then Fire(R.IndexClaimAll) end
        if Config.ClaimOfflineRewards then Invoke(R.OfflineClaim) end
        if Config.ClaimTapChests then Invoke(R.ChestClaim) end
        task.wait(Config.RewardsEvery)
    end
end)

task.spawn(function()
    while IsActive() do
        task.wait(30)
        print(("[TapSim] step: %s | %s | coins %s (%s/s), gems %s, rebirths %s, power %s, pets %d/%d, jumps %d | 30 s: %d taps, %d pets, +%s rebirths, %d skills"):format(
            StageName, Status, Short(Coins()), Short(Income), Short(Gems()), Short(Rebirths()), Short(Power()),
            #OwnedPets(), StorageLimit(), Jumps(), HatchStats.Taps, HatchStats.Hatches, Short(HatchStats.Rebirths), HatchStats.Skills))
        HatchStats.Taps, HatchStats.Hatches, HatchStats.Rebirths, HatchStats.Skills = 0, 0, 0, 0

        -- crafting progress: normal / golden / diamond / rainbow copies of each craft pet
        local Parts = {}
        for _, Name in ipairs(Config.Golden) do
            for _, Shiny in ipairs({false, true}) do
                local N, G, Dm, Rb = CountPet(Name, "Normal", Shiny), CountPet(Name, "Golden", Shiny),
                    CountPet(Name, "Diamond", Shiny), CountPet(Name, "Rainbow", Shiny)
                if N + G + Dm + Rb > 0 then
                    table.insert(Parts, ("%s%s: %d normal, %d golden, %d diamond, %d rainbow"):format(
                        Shiny and "shiny " or "", Name, N, G, Dm, Rb))
                end
            end
        end
        if #Parts > 0 then
            print(("[TapSim] craft (need %d normal -> golden, %d golden -> diamond, %d diamond -> rainbow): %s"):format(
                Config.GoldenUse, Config.DiamondUse, Config.RainbowUse, table.concat(Parts, " | ")))
        end
    end
end)

----------------------------------------------------------------
-- MAIN: run the steps in order
----------------------------------------------------------------
----------------------------------------------------------------
-- HATCH ANIMATION OFF (game setting)
----------------------------------------------------------------
local function HatchAnimValue()
    local Data = D()
    return Data and Data.Settings and Data.Settings.HatchAnimation
end

if Config.HatchAnimationOff and R.UpdateSetting then
    task.spawn(function()
        local Start = HatchAnimValue()
        -- learned from you (setting changed by hand), else the known format {Name, Value}
        local Args = Learned.HatchSetting or {{Name = "HatchAnimation", Value = Config.HatchAnimationValue}}
        if not Learned.HatchSetting and Start == Config.HatchAnimationValue then
            print(("[TapSim] hatch animation setting already %s"):format(tostring(Start)))
            return
        end
        local Ok, Result = Invoke(R.UpdateSetting, table.unpack(Args))
        task.wait(0.5)
        print(("[TapSim] hatch animation setting %s -> %s (request %s, answer %s)"):format(
            tostring(Start), tostring(HatchAnimValue()), Dump(Args, 0, 2), Dump(Result, 0, 2)))
    end)
end

print("[TapSim] kaitun started.")

----------------------------------------------------------------
-- PANEL
----------------------------------------------------------------
if Config.Panel then
    local RunService = game:GetService("RunService")
    local StartRebirths = Rebirths()

    local function CountSecrets()
        local N = 0
        for _, P in ipairs(OwnedPets()) do
            if IsSecret(P.Name) then N += 1 end
        end
        return N
    end
    local StartSecrets = CountSecrets()

    local Parent
    pcall(function() Parent = gethui() end)
    if not Parent then pcall(function() Parent = game:GetService("CoreGui") end) end
    if not Parent then Parent = LocalPlayer:WaitForChild("PlayerGui") end
    pcall(function()
        local Old = Parent:FindFirstChild("TapSimPanel")
        if Old then Old:Destroy() end
    end)

    local Gui = Instance.new("ScreenGui")
    Gui.Name = "TapSimPanel"
    Gui.IgnoreGuiInset = true
    Gui.ResetOnSpawn = false
    Gui.DisplayOrder = 999999
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.Parent = Parent

    local Green = Color3.fromRGB(26, 188, 156)

    local Back = Instance.new("Frame")
    Back.Size = UDim2.fromScale(1, 1)
    Back.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
    Back.BorderSizePixel = 0
    Back.Active = true   -- blocks clicks to the game below
    Back.Parent = Gui

    local Box = Instance.new("Frame")
    Box.AnchorPoint = Vector2.new(0.5, 0.5)
    Box.Position = UDim2.fromScale(0.5, 0.5)
    Box.Size = UDim2.fromOffset(720, 640)
    Box.BackgroundTransparency = 1
    Box.Parent = Back
    -- fit small (phone) screens
    local Scale = Instance.new("UIScale")
    Scale.Parent = Box
    local function Fit()
        local V = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        Scale.Scale = math.clamp(math.min(V.X / 760, V.Y / 680), 0.4, 1.2)
    end
    Fit()
    pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Fit) end)

    local Layout = Instance.new("UIListLayout")
    Layout.Padding = UDim.new(0, 8)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Parent = Box

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 60)
    Title.BackgroundTransparency = 1
    Title.Font = Enum.Font.GothamBlack
    Title.Text = "Tap Simulator Kaitun"
    Title.TextColor3 = Green
    Title.TextScaled = true
    Title.LayoutOrder = 0
    Title.Parent = Box

    local Rows = {}
    local Order = 0
    local function Row(Name, Gap)
        Order += 1
        if Gap then
            local Line = Instance.new("Frame")
            Line.Size = UDim2.new(1, 0, 0, 2)
            Line.BackgroundColor3 = Green
            Line.BackgroundTransparency = 0.6
            Line.BorderSizePixel = 0
            Line.LayoutOrder = Order
            Line.Parent = Box
            Order += 1
        end
        local F = Instance.new("Frame")
        F.Size = UDim2.new(1, 0, 0, 34)
        F.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
        F.BorderSizePixel = 0
        F.LayoutOrder = Order
        F.Parent = Box
        Instance.new("UICorner", F).CornerRadius = UDim.new(0, 6)

        local L = Instance.new("TextLabel")
        L.Size = UDim2.new(0.45, -12, 1, 0)
        L.Position = UDim2.new(0, 12, 0, 0)
        L.BackgroundTransparency = 1
        L.Font = Enum.Font.GothamBold
        L.Text = Name
        L.TextColor3 = Color3.fromRGB(205, 210, 220)
        L.TextSize = 20
        L.TextXAlignment = Enum.TextXAlignment.Left
        L.Parent = F

        local V = Instance.new("TextLabel")
        V.Size = UDim2.new(0.55, -12, 1, 0)
        V.Position = UDim2.new(0.45, 0, 0, 0)
        V.BackgroundTransparency = 1
        V.Font = Enum.Font.GothamBold
        V.Text = "-"
        V.TextColor3 = Green
        V.TextSize = 20
        V.TextScaled = false
        V.TextTruncate = Enum.TextTruncate.AtEnd
        V.TextXAlignment = Enum.TextXAlignment.Right
        V.Parent = F
        Rows[Name] = V
    end

    Row("Status")
    Row("Step")
    Row("Island")
    Row("Eggs Hatched (session)", true)
    Row("Secrets (session)")
    Row("Time Farmed")
    Row("Coins", true)
    Row("Income")
    Row("Gems")
    Row("Rebirths")
    Row("Pet Power", true)
    Row("Pets")

    -- show / hide button (always on top, top right)
    local Toggle = Instance.new("TextButton")
    Toggle.AnchorPoint = Vector2.new(1, 0)
    Toggle.Position = UDim2.new(1, -12, 0, 12)
    Toggle.Size = UDim2.fromOffset(150, 36)
    Toggle.BackgroundColor3 = Green
    Toggle.Font = Enum.Font.GothamBold
    Toggle.TextColor3 = Color3.fromRGB(13, 17, 23)
    Toggle.TextSize = 16
    Toggle.ZIndex = 10
    Toggle.Parent = Gui
    Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 8)

    local Shown = true
    local function Apply()
        Back.Visible = Shown
        Toggle.Text = Shown and "Show game" or "Show panel"
        if Config.HideWorld then
            pcall(function() RunService:Set3dRenderingEnabled(not Shown) end)
        end
    end
    Toggle.MouseButton1Click:Connect(function()
        Shown = not Shown
        Apply()
    end)
    Apply()

    local function Clock(Seconds)
        Seconds = math.floor(Seconds)
        return ("%02d:%02d:%02d"):format(math.floor(Seconds / 3600), math.floor(Seconds % 3600 / 60), Seconds % 60)
    end

    task.spawn(function()
        local LastSecrets, SecretsCheck = 0, 0
        while IsActive() and Gui.Parent do
            pcall(function()
                local Data = D()
                Rows["Status"].Text = tostring(Status)
                Rows["Step"].Text = tostring(StageName)
                Rows["Island"].Text = tostring(Data and Data.Progression and Data.Progression.Island or "-")
                Rows["Eggs Hatched (session)"].Text = Short(Session.Hatched)
                if os.clock() - SecretsCheck > 5 then
                    SecretsCheck = os.clock()
                    LastSecrets = math.max(CountSecrets() - StartSecrets, 0)
                end
                Rows["Secrets (session)"].Text = tostring(LastSecrets)
                Rows["Time Farmed"].Text = Clock(os.clock() - Session.Start)
                Rows["Coins"].Text = Short(Coins())
                Rows["Income"].Text = Short(Income) .. "/s"
                Rows["Gems"].Text = Short(Gems())
                Rows["Rebirths"].Text = ("%s (+%s)"):format(Short(Rebirths()), Short(Rebirths() - StartRebirths))
                Rows["Pet Power"].Text = Short(Power())
                Rows["Pets"].Text = ("%d / %d"):format(#OwnedPets(), StorageLimit())
            end)
            task.wait(0.5)
        end
        -- script stopped: give the game back (unless a newer copy has its own panel up)
        local Newer = Parent:FindFirstChild("TapSimPanel")
        if not Newer or Newer == Gui then
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
        end
        pcall(function() Gui:Destroy() end)
    end)
end

-- restore saved step data
for I, S in ipairs(Config.Stages) do
    S._Index = I
    if Save.Done[tostring(I)] then S._Done = true end
    if Save.Starts[tostring(I)] then S._Start = tonumber(Save.Starts[tostring(I)]) end
end

-- continue from the step you were on last time (Config.StartStep forces a step)
local First = tonumber(Config.StartStep)
if not First and Save.StageName then
    for I, S in ipairs(Config.Stages) do
        if S.Name == Save.StageName then First = I break end
    end
    -- step list changed: start from the top, finished steps / passed islands are skipped
    if not First then First = 1 end
end
First = math.clamp(First or tonumber(Save.Stage) or 1, 1, #Config.Stages)
if First > 1 then print(("[TapSim] continuing from step %d (%s)"):format(First, Config.Stages[First].Name)) end

for I = First, #Config.Stages do
    local S = Config.Stages[I]
    if not IsActive() then break end
    if not ShouldSkip(S) then
        StageName = ("%d/%d %s"):format(I, #Config.Stages, S.Name)
        CurrentStage = S
        print("[TapSim] >>> step " .. StageName)
        Save.Stage = I
        Save.StageName = S.Name
        WriteSave()
        -- repeat the step until it is really done (an error only restarts it)
        while IsActive() and not ShouldSkip(S) do
            local Ok, Err = pcall(RunStage, S)
            if not Ok then
                warn("[TapSim] step error: " .. tostring(Err))
                task.wait(3)
            end
        end
    end
    if IsActive() then
        local Next = math.min(I + 1, #Config.Stages)
        if Next > (tonumber(Save.Stage) or 1) then
            Save.Stage = Next
            Save.StageName = Config.Stages[Next].Name
            WriteSave()
        end
    end
end

print("[TapSim] stopped.")
