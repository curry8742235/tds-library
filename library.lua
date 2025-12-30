-- // ========================================================== //
-- //      TDS LIBRARY - DEEPSEEK CORE v5 (Ground Fix)           //
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

-- Get absolute position of any object/model/folder
function MapEngine:GetPos(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") or obj:IsA("Folder") then
        local p = obj:FindFirstChild("0") or obj:FindFirstChild("1") or obj:FindFirstChild("Start") or obj:FindFirstChildWhichIsA("BasePart")
        if p and p:IsA("BasePart") then return p.Position end
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("BasePart") then return c.Position end
        end
    end
    return nil
end

function MapEngine:FindAnchor()
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if not map then return Vector3.zero end

    -- Priority 1: Paths Folder (Lowest Node)
    if map:FindFirstChild("Paths") then
        local p = map.Paths
        local startNode = p:FindFirstChild("0") or p:FindFirstChild("1") or p:FindFirstChild("Start")
        
        -- Check nested paths
        if not startNode and p:FindFirstChild("Path") then
            startNode = p.Path:FindFirstChild("0")
        end
        
        -- Check numeric children
        if not startNode then
            local lowest = 9999
            for _, c in ipairs(p:GetChildren()) do
                local n = tonumber(c.Name)
                if n and n < lowest then
                    lowest = n
                    startNode = c
                end
            end
        end

        local pos = self:GetPos(startNode)
        if pos then return pos end
    end

    -- Priority 2: EnemySpawn
    if map:FindFirstChild("EnemySpawn") then return map.EnemySpawn.Position end
    
    return Vector3.zero
end

-- // RAYCAST: TARGET SPECIFIC GROUND FOLDERS
function MapEngine:FindValidGround(x, z)
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    local origin = Vector3.new(x, self.CurrentAnchor.Y + 200, z)
    local dir = Vector3.new(0, -500, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include -- STRICT MODE
    
    local whitelist = {}
    
    -- 1. Add Workspace.Ground (The one you showed in Dex)
    if TDS.Services.Workspace:FindFirstChild("Ground") then
        table.insert(whitelist, TDS.Services.Workspace.Ground)
    end
    
    -- 2. Add Map.Ground / Map.Environment
    if map then
        if map:FindFirstChild("Ground") then table.insert(whitelist, map.Ground) end
        if map:FindFirstChild("Environment") then table.insert(whitelist, map.Environment) end
    end
    
    -- If we found specific ground folders, use them.
    if #whitelist > 0 then
        params.FilterDescendantsInstances = whitelist
    else
        -- Fallback: Use Exclude mode if no "Ground" folder exists
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            TDS.LocalPlayer.Character,
            TDS.Services.Workspace.Towers,
            TDS.Services.Workspace.Pickups,
            TDS.Services.Workspace.Camera,
            map and map:FindFirstChild("Road"),
            map and map:FindFirstChild("Cliff"),
            map and map:FindFirstChild("Boundaries"),
            map and map:FindFirstChild("Paths")
        }
    end

    local res = TDS.Services.Workspace:Raycast(origin, dir, params)
    
    if res and res.Instance then
        -- Lift 0.5 studs to avoid clipping
        return res.Position.Y + 0.5 
    end
    return nil
end

function MapEngine:Initialize()
    if not TDS.Services.Workspace:FindFirstChild("Map") then
        TDS.Services.Workspace.ChildAdded:Wait()
        task.wait(1)
    end
    
    self.CurrentAnchor = self:FindAnchor()
    if self.CurrentAnchor == Vector3.zero then
        warn("[Library] ⚠️ ANCHOR NOT FOUND.")
    else
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
    local RADIUS_LIMIT = 45
    local STEP_SIZE = 4
    
    for r = 0, RADIUS_LIMIT, STEP_SIZE do
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / STEP_SIZE)
        
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + (math.cos(angle) * r)
            local tryZ = baseZ + (math.sin(angle) * r)
            
            -- RAYCAST
            local groundY = MapEngine:FindValidGround(tryX, tryZ)
            
            if groundY then
                local target = Vector3.new(tryX, groundY, tryZ)
                
                local s, res = pcall(function()
                    return self.Remote:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = target
                    }, name)
                end)

                if s and (res == true or (type(res)=="table" and res.Success)) then
                    -- Verify
                    local tOut = tick() + 2
                    repeat task.wait() until tick() > tOut or #TDS.Services.Workspace.Towers:GetChildren() > #self.placed_towers
                    
                    for _, t in ipairs(TDS.Services.Workspace.Towers:GetChildren()) do
                        if t.Name == name and t.Owner.Value == TDS.LocalPlayer.UserId then
                            local known = false
                            for _, k in ipairs(self.placed_towers) do if k==t then known=true end end
                            
                            if not known then
                                table.insert(self.placed_towers, t)
                                print("✅ PLACED:", name, "| R:", r)
                                return -- SUCCESS
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- FALLBACK: BLIND PLACEMENT (If Raycast failed)
    print("⚠️ Raycast failed. Attempting blind placement at estimated height...")
    local estimatedY = MapEngine.CurrentAnchor.Y + (recY - MapEngine.RecAnchor.Y) + 1
    local blindTarget = Vector3.new(baseX, estimatedY, baseZ)
    
    local s, res = pcall(function()
        return self.Remote:InvokeServer("Troops", "Place", {
            Rotation = CFrame.new(),
            Position = blindTarget
        }, name)
    end)
    
    if s and (res == true or (type(res)=="table" and res.Success)) then
        print("✅ BLIND PLACEMENT SUCCESS")
        return
    end

    warn("❌ FAILED:", name, "| No ground found in", RADIUS_LIMIT, "studs")
end

function TDS:Upgrade(idx)
    local t = self.placed_towers[idx]
    if t then pcall(function() self.Remote:InvokeServer("Troops", "Upgrade", "Set", {Troop=t, Path=1}) end) end
end

function TDS:Skip()
    pcall(function() self.Remote:InvokeServer("Voting", "Skip") end)
end

task.spawn(function()
    while task.wait(1) do
        if getgenv().AutoSkip then
            local v = TDS.LocalPlayer.PlayerGui:FindFirstChild("ReactOverridesVote")
            if v and v.Frame.Visible then TDS:Skip() end
        end
    end
end)

return TDS
