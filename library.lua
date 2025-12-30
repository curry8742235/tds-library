-- // ========================================================== //
-- //      TDS OPTIMIZED LIBRARY - DEEPSEEK EDITION v3           //
-- //      (Auto-Anchor, Terrain Snap, Anti-Road, Spiral Search) //
-- // ========================================================== //

if not game:IsLoaded() then game.Loaded:Wait() end

-- // Core Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local RemoteFunction = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- // Game State Detection
local function identify_game_state()
    local gui = LocalPlayer:WaitForChild("PlayerGui")
    while true do
        if gui:FindFirstChild("LobbyGui") then return "LOBBY"
        elseif gui:FindFirstChild("GameGui") then return "GAME" end
        task.wait(1)
    end
end
local game_state = identify_game_state()

-- // 1. ADVANCED MAP ANALYSIS ENGINE
local MapEngine = {}
MapEngine.RecAnchor = Vector3.new(-48.8, 3.8, 14.5) -- Simplicity Spawn
MapEngine.CurrentAnchor = Vector3.zero
MapEngine.Offset = Vector3.zero

-- Helper to recursively find a valid part
function MapEngine:FindFirstPart(parent, searchNames)
    if not parent then return nil end
    
    -- Check direct children
    for _, name in ipairs(searchNames) do
        local child = parent:FindFirstChild(name)
        if child and child:IsA("BasePart") then return child end
        if child and (child:IsA("Model") or child:IsA("Folder")) then
            local deep = self:FindFirstPart(child, searchNames) or child:FindFirstChildWhichIsA("BasePart")
            if deep then return deep end
        end
    end
    
    -- Deep search all descendants if needed (Expensive, use sparingly)
    return nil
end

function MapEngine:FindAnchor()
    local map = Workspace:FindFirstChild("Map")
    if not map then return Vector3.zero end

    -- Priority 1: EnemySpawn (Recursive)
    local spawnPart = self:FindFirstPart(map, {"EnemySpawn", "Spawn"})
    if spawnPart then return spawnPart.Position end

    -- Priority 2: Paths (0, 1, Start)
    local paths = map:FindFirstChild("Paths")
    if paths then
        local node = self:FindFirstPart(paths, {"0", "1", "Start", "Path", "Main"})
        if node then return node.Position end
        
        -- Fallback: Lowest numbered folder
        local lowest = 9999
        local best = nil
        for _, c in ipairs(paths:GetChildren()) do
            local n = tonumber(c.Name)
            if n and n < lowest then
                lowest = n
                best = c
            end
        end
        if best then
            if best:IsA("BasePart") then return best.Position end
            local p = best:FindFirstChildWhichIsA("BasePart")
            if p then return p.Position end
        end
    end
    
    -- Priority 3: Desperation (First Part in Map)
    local anyPart = map:FindFirstChildWhichIsA("BasePart", true)
    if anyPart then return anyPart.Position end

    return Vector3.zero
end

-- Raycast that filters out Roads/Paths/Cliffs
function MapEngine:ScanTerrain(x, z)
    local origin = Vector3.new(x, self.CurrentAnchor.Y + 100, z)
    local dir = Vector3.new(0, -500, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        LocalPlayer.Character,
        Workspace:FindFirstChild("Towers"),
        Workspace:FindFirstChild("Pickups"),
        Workspace:FindFirstChild("Camera")
    }

    local result = Workspace:Raycast(origin, dir, params)
    if result and result.Instance then
        local hit = result.Instance
        local n = hit.Name
        local p = hit.Parent.Name
        local gp = hit.Parent.Parent and hit.Parent.Parent.Name or ""
        
        -- STRICT SURFACE FILTER
        if n == "Road" or p == "Road" or gp == "Road" then return nil end
        if n == "Path" or p == "Paths" or gp == "Paths" then return nil end
        if n == "Bridge" or n == "Cliff" or p == "Cliff" then return nil end
        if n == "Boundaries" or p == "Boundaries" then return nil end
        
        -- Return valid ground height + lift
        return result.Position.Y + 0.5
    end
    return nil
end

-- Initialize Map Data
if game_state == "GAME" then
    task.spawn(function()
        if not Workspace:FindFirstChild("Map") then Workspace.ChildAdded:Wait() task.wait(1) end
        MapEngine.CurrentAnchor = MapEngine:FindAnchor()
        
        if MapEngine.CurrentAnchor ~= Vector3.zero then
            MapEngine.Offset = MapEngine.CurrentAnchor - MapEngine.RecAnchor
            print("[DeepSeek] Map Adapted. Offset:", MapEngine.Offset)
        else
            warn("[DeepSeek] CRITICAL: Map Anchor not found. Script may fail.")
        end
    end)
end

-- // TDS Controller
local TDS = {
    placed_towers = {},
    DebugMode = true
}

-- // Utilities
local function check_success(res)
    if res == true then return true end
    if type(res) == "table" and res.Success then return true end
    return false
end

-- // API Implementation

function TDS:Place(name, recX, recY, recZ)
    if game_state ~= "GAME" then return end
    
    local baseX = recX + MapEngine.Offset.X
    local baseZ = recZ + MapEngine.Offset.Z
    
    -- SPIRAL SEARCH: 0 to 35 Studs Radius
    local radius = 35
    local step = 3.5
    
    for r = 0, radius, step do
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / step)
        
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + math.cos(angle) * r
            local tryZ = baseZ + math.sin(angle) * r
            
            -- RAYCAST CHECK
            local groundY = MapEngine:ScanTerrain(tryX, tryZ)
            
            if groundY then
                local targetPos = Vector3.new(tryX, groundY, tryZ)
                
                -- ATTEMPT PLACEMENT
                local success, res = pcall(function()
                    return RemoteFunction:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = targetPos
                    }, name)
                end)

                if success and check_success(res) then
                    -- Verify & Register
                    local start = tick()
                    repeat task.wait() until tick() - start > 1 or #Workspace.Towers:GetChildren() > #self.placed_towers
                    
                    for _, t in ipairs(Workspace.Towers:GetChildren()) do
                        if t.Name == name and t.Owner.Value == LocalPlayer.UserId then
                            local known = false
                            for _, k in ipairs(self.placed_towers) do if k == t then known = true end end
                            
                            if not known then
                                table.insert(self.placed_towers, t)
                                if self.DebugMode then
                                    print(string.format("✅ Placed %s (Radius: %.1f)", name, r))
                                end
                                return -- SUCCESS
                            end
                        end
                    end
                end
            end
        end
    end
    warn("❌ Failed to place " .. name .. " (No valid ground found)")
end

function TDS:Upgrade(idx, path)
    local t = self.placed_towers[idx]
    if t then
        pcall(function() 
            RemoteFunction:InvokeServer("Troops", "Upgrade", "Set", { Troop = t, Path = path or 1 }) 
        end)
    end
end

function TDS:Sell(idx)
    local t = self.placed_towers[idx]
    if t then
        pcall(function() RemoteFunction:InvokeServer("Troops", "Sell", { Troop = t }) end)
        table.remove(self.placed_towers, idx)
    end
end

function TDS:Ability(idx, name, data)
    local t = self.placed_towers[idx]
    if t then
        pcall(function()
            RemoteFunction:InvokeServer("Troops", "Abilities", "Activate", {
                Troop = t, Name = name, Data = data
            })
        end)
    end
end

function TDS:SetTarget(idx, mode)
    local t = self.placed_towers[idx]
    if t then
        pcall(function() RemoteFunction:InvokeServer("Troops", "Target", "Set", { Troop = t, Target = mode }) end)
    end
end

function TDS:Skip()
    pcall(function() RemoteFunction:InvokeServer("Voting", "Skip") end)
end

-- // Automation Hooks
task.spawn(function()
    while task.wait(1) do
        if getgenv().AutoSkip then
            local vote = PlayerGui:FindFirstChild("ReactOverridesVote")
            if vote and vote:FindFirstChild("Frame") and vote.Frame.Visible then
                TDS:Skip()
            end
        end
    end
end)

return TDS
