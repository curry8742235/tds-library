-- // ========================================================== //
-- //      TDS LIBRARY - DEEPSEEK ADAPTIVE CORE v4               //
-- //      (Ground-Only Targeting system)                        //
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

    -- Priority: Paths > 0 (Start of path)
    if map:FindFirstChild("Paths") then
        local p = map.Paths
        -- Look for node 0, 1, or Start
        local startNode = p:FindFirstChild("0") or p:FindFirstChild("1") or p:FindFirstChild("Start")
        -- Handle nested paths (e.g. Paths > Path > 0)
        if not startNode and p:FindFirstChild("Path") then
            startNode = p.Path:FindFirstChild("0")
        end
        
        local pos = self:GetPos(startNode)
        if pos then return pos end
    end

    -- Fallback: EnemySpawn
    if map:FindFirstChild("EnemySpawn") then return map.EnemySpawn.Position end
    
    return Vector3.zero
end

-- // RAYCAST: The "Sniper"
function MapEngine:FindValidGround(x, z)
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if not map then return nil end

    local origin = Vector3.new(x, self.CurrentAnchor.Y + 200, z)
    local dir = Vector3.new(0, -500, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include -- WHITELIST MODE
    
    -- ONLY LOOK AT THE GROUND FOLDER
    local whitelist = {}
    if map:FindFirstChild("Ground") then table.insert(whitelist, map.Ground) end
    if map:FindFirstChild("Environment") then table.insert(whitelist, map.Environment) end
    
    -- If no Ground folder, fallback to Map but exclude Road/Cliff
    if #whitelist == 0 then
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            TDS.LocalPlayer.Character,
            TDS.Services.Workspace.Towers,
            TDS.Services.Workspace.Pickups,
            TDS.Services.Workspace.Camera,
            map:FindFirstChild("Road"),
            map:FindFirstChild("Cliff"),
            map:FindFirstChild("Boundaries"),
            map:FindFirstChild("Paths")
        }
    else
        params.FilterDescendantsInstances = whitelist
    end

    local res = TDS.Services.Workspace:Raycast(origin, dir, params)
    
    if res and res.Instance then
        -- Double check we didn't hit a Cliff/Road (Extra Safety)
        local n = res.Instance.Name
        local p = res.Instance.Parent.Name
        if n == "Road" or p == "Road" then return nil end
        if n == "Cliff" or p == "Cliff" then return nil end
        
        return res.Position.Y + 0.5 -- Valid Ground Height
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
        warn("[Library] ⚠️ ANCHOR NOT FOUND. PLACEMENT MAY FAIL.")
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
    
    -- SPIRAL SEARCH (Expand outwards to find Grass)
    local RADIUS_LIMIT = 45
    local STEP_SIZE = 4
    
    for r = 0, RADIUS_LIMIT, STEP_SIZE do
        -- Calculate points in this ring
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / STEP_SIZE)
        
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + (math.cos(angle) * r)
            local tryZ = baseZ + (math.sin(angle) * r)
            
            -- SCAN FOR GROUND
            local groundY = MapEngine:FindValidGround(tryX, tryZ)
            
            if groundY then
                local target = Vector3.new(tryX, groundY, tryZ)
                
                -- ATTEMPT PLACE
                local s, res = pcall(function()
                    return self.Remote:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = target
                    }, name)
                end)

                -- CHECK SUCCESS
                if s and (res == true or (type(res)=="table" and res.Success)) then
                    -- REGISTER
                    local tOut = tick() + 2
                    repeat task.wait() until tick() > tOut or #TDS.Services.Workspace.Towers:GetChildren() > #self.placed_towers
                    
                    for _, t in ipairs(TDS.Services.Workspace.Towers:GetChildren()) do
                        if t.Name == name and t.Owner.Value == TDS.LocalPlayer.UserId then
                            local known = false
                            for _, k in ipairs(self.placed_towers) do if k==t then known=true end end
                            
                            if not known then
                                table.insert(self.placed_towers, t)
                                print("✅ PLACED:", name, "| R:", r)
                                return -- DONE
                            end
                        end
                    end
                end
            end
        end
    end
    print("❌ FAILED:", name, "| No ground found in", RADIUS_LIMIT, "studs")
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
