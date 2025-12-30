-- // ========================================================== //
-- //      TDS LIBRARY - DEEPSEEK CORE v6 (Direct Ground Fix)    //
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
MapEngine.RecAnchor = Vector3.new(-48.8, 3.8, 14.5)
MapEngine.CurrentAnchor = Vector3.zero
MapEngine.Offset = Vector3.zero

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

-- // PHYSICAL PART CHECK (Backup if Raycast fails)
function MapEngine:GetGroundPartHeight(x, z)
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if not map then return nil end
    
    local groundFolder = map:FindFirstChild("Ground") or TDS.Services.Workspace:FindFirstChild("Ground")
    if not groundFolder then return nil end
    
    -- Loop through all parts in Ground folder
    for _, part in ipairs(groundFolder:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Check if X,Z is inside the part
            local halfSize = part.Size / 2
            local pos = part.Position
            
            if x >= (pos.X - halfSize.X) and x <= (pos.X + halfSize.X) and
               z >= (pos.Z - halfSize.Z) and z <= (pos.Z + halfSize.Z) then
               
               -- Return Top Surface Y
               return pos.Y + halfSize.Y + 0.2
            end
        end
    end
    return nil
end

-- // RAYCAST: EXCLUDE MODE (Hits everything EXCEPT Roads)
function MapEngine:FindValidGround(x, z)
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    local origin = Vector3.new(x, self.CurrentAnchor.Y + 300, z) -- Start High
    local dir = Vector3.new(0, -600, 0) -- Shoot Down
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude -- HIT EVERYTHING EXCEPT...
    
    local blacklist = {
        TDS.LocalPlayer.Character,
        TDS.Services.Workspace:FindFirstChild("Towers"),
        TDS.Services.Workspace:FindFirstChild("Pickups"),
        TDS.Services.Workspace:FindFirstChild("Camera")
    }
    
    if map then
        if map:FindFirstChild("Road") then table.insert(blacklist, map.Road) end
        if map:FindFirstChild("Paths") then table.insert(blacklist, map.Paths) end
        if map:FindFirstChild("Cliff") then table.insert(blacklist, map.Cliff) end
        if map:FindFirstChild("Boundaries") then table.insert(blacklist, map.Boundaries) end
    end
    
    params.FilterDescendantsInstances = blacklist

    local res = TDS.Services.Workspace:Raycast(origin, dir, params)
    
    if res and res.Instance then
        -- FOUND SOLID OBJECT
        return res.Position.Y + 0.5
    end
    
    -- RAYCAST MISSED? TRY PHYSICAL CHECK
    return self:GetGroundPartHeight(x, z)
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
    local STEP_SIZE = 3
    
    for r = 0, RADIUS_LIMIT, STEP_SIZE do
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / STEP_SIZE)
        
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + (math.cos(angle) * r)
            local tryZ = baseZ + (math.sin(angle) * r)
            
            -- SCAN
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
    
    warn("❌ FAILED:", name, "| Could not find Ground.")
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
