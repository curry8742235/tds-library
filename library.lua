-- // ========================================================== //
-- //      TDS LIBRARY - ADAPTIVE CORE v8 (Ground Targeted)      //
-- // ========================================================== //

local TDS = {}
TDS.placed_towers = {}
TDS.Services = {
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService")
}
TDS.LocalPlayer = TDS.Services.Players.LocalPlayer
TDS.Remote = TDS.Services.ReplicatedStorage:WaitForChild("RemoteFunction")

-- // 1. MAP ENGINE
local MapEngine = {}
MapEngine.RecAnchor = Vector3.new(-48.8, 3.8, 14.5) -- Simplicity Spawn
MapEngine.CurrentAnchor = Vector3.zero
MapEngine.Offset = Vector3.zero

-- Get Position Helper
function MapEngine:GetPos(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") or obj:IsA("Folder") then
        local p = obj:FindFirstChild("0") or obj:FindFirstChild("1") or obj:FindFirstChildWhichIsA("BasePart")
        if p and p:IsA("BasePart") then return p.Position end
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("BasePart") then return c.Position end
        end
    end
    return nil
end

-- Find Map Anchor (Reference Point)
function MapEngine:FindAnchor()
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if not map then return Vector3.zero end

    -- 1. EnemySpawn (Best)
    if map:FindFirstChild("EnemySpawn") then return map.EnemySpawn.Position end

    -- 2. Paths Folder (Lowest Node)
    if map:FindFirstChild("Paths") then
        local p = map.Paths
        local startNode = p:FindFirstChild("0") or p:FindFirstChild("1") or p:FindFirstChild("Start")
        
        if not startNode then
            local lowest = 9999
            for _, c in ipairs(p:GetChildren()) do
                local n = tonumber(c.Name)
                if n and n < lowest then lowest = n startNode = c end
            end
        end
        local pos = self:GetPos(startNode)
        if pos then return pos end
    end
    
    return Vector3.zero
end

-- Raycast: "Sniper" Mode (Targets Ground Only)
function MapEngine:FindGroundY(x, z)
    local origin = Vector3.new(x, self.CurrentAnchor.Y + 300, z)
    local dir = Vector3.new(0, -600, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include -- ONLY HIT THESE
    
    local whitelist = {}
    
    -- Add Workspace.Ground (Your specific request)
    if TDS.Services.Workspace:FindFirstChild("Ground") then 
        table.insert(whitelist, TDS.Services.Workspace.Ground) 
    end
    
    -- Add Map.Ground / Environment
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if map then
        if map:FindFirstChild("Ground") then table.insert(whitelist, map.Ground) end
        if map:FindFirstChild("Environment") then table.insert(whitelist, map.Environment) end
    end
    
    -- Fallback: If no specific folders, exclude bad stuff
    if #whitelist == 0 then
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            TDS.LocalPlayer.Character,
            TDS.Services.Workspace.Towers,
            TDS.Services.Workspace.Camera,
            map and map:FindFirstChild("Road"),
            map and map:FindFirstChild("Cliff"),
            map and map:FindFirstChild("Boundaries")
        }
    else
        params.FilterDescendantsInstances = whitelist
    end

    local res = TDS.Services.Workspace:Raycast(origin, dir, params)
    
    if res and res.Instance then
        return res.Position.Y + 0.1 -- Lift slightly above floor
    end
    
    return nil
end

function MapEngine:Initialize()
    if not TDS.Services.Workspace:FindFirstChild("Map") then
        TDS.Services.Workspace.ChildAdded:Wait()
        task.wait(1)
    end
    self.CurrentAnchor = self:FindAnchor()
    if self.CurrentAnchor ~= Vector3.zero then
        self.Offset = self.CurrentAnchor - self.RecAnchor
        print("[Library] ✅ Map Adapted. Offset:", self.Offset)
    end
end

MapEngine:Initialize()

-- // 2. CORE FUNCTIONS

function TDS:Place(name, recX, recY, recZ)
    local baseX = recX + MapEngine.Offset.X
    local baseZ = recZ + MapEngine.Offset.Z
    
    -- Spiral Search: 0 to 45 studs
    local radius_limit = 45
    local step_size = 3
    
    for r = 0, radius_limit, step_size do
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / step_size)
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + (math.cos(angle) * r)
            local tryZ = baseZ + (math.sin(angle) * r)
            
            -- RAYCAST
            local groundY = MapEngine:FindGroundY(tryX, tryZ)
            
            if groundY then
                local target = Vector3.new(tryX, groundY, tryZ)
                local s, res = pcall(function()
                    return self.Remote:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = target
                    }, name)
                end)

                if s and (res == true or (type(res)=="table" and res.Success)) then
                    local tOut = tick() + 2
                    repeat task.wait() until tick() > tOut or #TDS.Services.Workspace.Towers:GetChildren() > #self.placed_towers
                    
                    for _, t in ipairs(TDS.Services.Workspace.Towers:GetChildren()) do
                        if t.Name == name and t.Owner.Value == TDS.LocalPlayer.UserId then
                            local known = false
                            for _, k in ipairs(self.placed_towers) do if k==t then known=true end end
                            if not known then
                                table.insert(self.placed_towers, t)
                                print("✅ PLACED:", name, "| R:", r)
                                return 
                            end
                        end
                    end
                end
            end
        end
    end
    print("❌ FAILED:", name)
end

function TDS:Upgrade(idx)
    local t = self.placed_towers[idx]
    if t then pcall(function() self.Remote:InvokeServer("Troops", "Upgrade", "Set", {Troop=t, Path=1}) end) end
end

function TDS:Skip()
    pcall(function() self.Remote:InvokeServer("Voting", "Skip") end)
end

-- // AUTO SKIP LOOP
task.spawn(function()
    while task.wait(1) do
        if getgenv().AutoSkip then
            local v = TDS.LocalPlayer.PlayerGui:FindFirstChild("ReactOverridesVote")
            if v and v.Frame.Visible then TDS:Skip() end
        end
    end
end)

return TDS
