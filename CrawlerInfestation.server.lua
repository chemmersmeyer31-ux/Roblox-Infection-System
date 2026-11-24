-- CRAWLER INFESTATION - PHASE 1
-- Place this Script in ServerScriptService alongside InfectionSystem.lua.
-- Uses Workspace.InfectionSpawner and the InfectionStage workspace attribute.
-- Crawlers are legs-only: no head, abdomen, eyes, or body.
-- Phase 1 is visual/stalking only: no damage, infection, or transformation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local infectionSpawner = workspace:WaitForChild("InfectionSpawner")
local rng = Random.new()

local COLORS = {
    dark = Color3.fromRGB(70, 35, 29),
    seed = Color3.fromRGB(112, 57, 39),
    ridge = Color3.fromRGB(139, 75, 49),
}
local MAX_CRAWLERS = {[3] = 2, [4] = 5, [5] = 9}
local HATCH_INTERVAL = {[3] = 38, [4] = 24, [5] = 15}
local CRAWLER_LIFETIME = 150
local DETECT_DISTANCE = 48
local LEAP_DISTANCE = 8

local folder = workspace:FindFirstChild("CrawlerInfestation")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "CrawlerInfestation"
folder.Parent = workspace

local function stage()
    return workspace:GetAttribute("InfectionStage") or 1
end

local function makePart(parent, name, shape, size, color)
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = shape
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.CorrodedMetal
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function placeRod(part, a, b, thickness)
    local delta = b - a
    if delta.Magnitude < 0.025 then
        part.Transparency = 1
        return
    end
    local axis = delta.Unit
    local up = Vector3.yAxis - axis * axis.Y
    if up.Magnitude < 0.04 then
        up = Vector3.xAxis - axis * axis.X
    end
    up = up.Unit
    local side = axis:Cross(up).Unit
    part.Transparency = 0
    part.Size = Vector3.new(delta.Magnitude, thickness, thickness)
    part.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

local function nearestPlayer(position, maxDistance)
    local bestRoot, bestDistance
    bestDistance = maxDistance
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then
            local d = (root.Position - position).Magnitude
            if d < bestDistance then bestRoot, bestDistance = root, d end
        end
    end
    return bestRoot, bestDistance
end

local function surfaceRay(position, direction, ignore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    return workspace:Raycast(position, direction, params)
end

local function findGround(position)
    local hit = surfaceRay(position + Vector3.new(0, 5, 0), Vector3.new(0, -18, 0), {folder})
    if hit then return hit.Position + hit.Normal * 0.35, hit.Normal end
    return position + Vector3.new(0, 0.4, 0), Vector3.yAxis
end

local function makeCrawler(startPosition, startNormal)
    local model = Instance.new("Model")
    model.Name = "LegsOnlyCrawler"
    model.Parent = folder

    local centerPart = makePart(model, "LegAttachmentPoint", Enum.PartType.Ball,
        Vector3.new(0.13, 0.13, 0.13), COLORS.dark)
    centerPart.Transparency = 0.12

    local legs = {}
    for i = 1, 8 do
        legs[i] = {
            a = makePart(model, "LegRoot" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.dark),
            b = makePart(model, "LegOuter" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.seed),
            joint = makePart(model, "LegJoint" .. i, Enum.PartType.Ball,
                Vector3.new(0.18, 0.18, 0.18), COLORS.ridge),
            claw = makePart(model, "LegClaw" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.dark),
            angle = (i - 1) * math.pi / 4,
            length = rng:NextNumber(0.88, 1.18),
        }
    end

    local position = startPosition
    local normal = startNormal.Unit
    local forward = Vector3.new(1, 0, 0)
    forward = forward - normal * forward:Dot(normal)
    if forward.Magnitude < 0.05 then forward = Vector3.new(0, 0, 1) end
    forward = forward.Unit

    local born = os.clock()
    local nextLeap = born + rng:NextNumber(7, 18)
    local latchedUntil = 0
    local latchedRoot = nil
    local lastSeen = 0
    local wanderAngle = rng:NextNumber(0, math.pi * 2)
    local connection

    connection = RunService.Heartbeat:Connect(function(dt)
        if not model.Parent then
            connection:Disconnect()
            return
        end
        local now = os.clock()
        if now - born > CRAWLER_LIFETIME or stage() < 3 then
            model:Destroy()
            connection:Disconnect()
            return
        end

        if latchedRoot and latchedRoot.Parent and now < latchedUntil then
            local character = latchedRoot.Parent
            local offset = Vector3.new(0, 1.2 + math.sin(now * 7) * 0.12, 0)
            position = latchedRoot.Position + offset
            normal = Vector3.yAxis
            forward = latchedRoot.CFrame.LookVector
        else
            latchedRoot = nil
            local target, distance = nearestPlayer(position, DETECT_DISTANCE)
            local moveDirection

            if target then
                lastSeen = now
                local toTarget = target.Position - position
                moveDirection = toTarget - normal * toTarget:Dot(normal)
                if moveDirection.Magnitude > 0.05 then moveDirection = moveDirection.Unit end

                if distance <= LEAP_DISTANCE and now >= nextLeap then
                    latchedRoot = target
                    latchedUntil = now + rng:NextNumber(3.5, 6)
                    nextLeap = now + rng:NextNumber(22, 36)
                    position = target.Position + Vector3.new(0, 1.2, 0)
                    normal = Vector3.yAxis
                    forward = target.CFrame.LookVector
                end
            else
                if now - lastSeen > 5 then
                    wanderAngle += rng:NextNumber(-0.9, 0.9) * dt
                end
                local tangent = normal:Cross(Vector3.yAxis)
                if tangent.Magnitude < 0.05 then tangent = Vector3.xAxis end
                tangent = tangent.Unit
                moveDirection = (tangent * math.cos(wanderAngle) + normal:Cross(tangent) * math.sin(wanderAngle)).Unit
            end

            if not latchedRoot and moveDirection and moveDirection.Magnitude > 0.05 then
                forward = moveDirection
                local speed = target and 3.1 or 1.45
                local proposed = position + moveDirection * speed * math.min(dt, 0.08)

                -- Follow the current surface. Probe for a nearby wall/ceiling
                -- in the direction of travel so the crawler can turn onto it.
                local hit = surfaceRay(proposed + normal * 1.5, -normal * 4.2, {folder, target and target.Parent})
                if hit then
                    position = hit.Position + hit.Normal * 0.28
                    normal = hit.Normal.Unit
                else
                    local wall = surfaceRay(position + normal * 0.8, moveDirection * 2.2, {folder, target and target.Parent})
                    if wall then
                        local wallHit = surfaceRay(wall.Position + wall.Normal * 1.0, -wall.Normal * 2.2, {folder, target and target.Parent})
                        if wallHit then
                            position = wallHit.Position + wallHit.Normal * 0.28
                            normal = wallHit.Normal.Unit
                        else
                            position = proposed
                        end
                    else
                        position = proposed
                    end
                end
            end
        end

        centerPart.Position = position
        local up = normal
        local right = forward:Cross(up)
        if right.Magnitude < 0.05 then right = Vector3.xAxis end
        right = right.Unit
        forward = up:Cross(right).Unit

        for i, leg in ipairs(legs) do
            local angle = leg.angle
            local radial = right * math.cos(angle) + forward * math.sin(angle)
            local phase = now * 8 + ((i % 2 == 0) and math.pi or 0)
            local stride = math.sin(phase) * 0.18
            local lift = math.max(0, math.cos(phase)) * 0.13
            local root = position + radial * 0.06
            local knee = position + radial * (0.85 * leg.length + stride * 0.2) + up * (0.12 + lift)
            local foot = position + radial * (1.65 * leg.length + stride) - up * (0.22 - lift)
            local clawEnd = foot + radial * 0.18 - up * 0.06
            placeRod(leg.a, root, knee, 0.21)
            placeRod(leg.b, knee, foot, 0.15)
            placeRod(leg.claw, foot, clawEnd, 0.085)
            leg.joint.Position = knee
        end
    end)
    return model
end

local function hatchBulb(position)
    local bulb = makePart(folder, "CrawlerHatchingBulb", Enum.PartType.Ball,
        Vector3.new(0.42, 0.36, 0.42), COLORS.seed)
    bulb.Position = position
    bulb.Material = Enum.Material.CorrodedMetal
    local start = os.clock()
    while bulb.Parent and os.clock() - start < 2.2 do
        local pulse = 1 + math.sin((os.clock() - start) * 8) * 0.12
        bulb.Size = Vector3.new(0.42, 0.36, 0.42) * pulse
        task.wait(0.08)
    end
    if bulb.Parent then
        local spawnPosition = bulb.Position + Vector3.new(0, 0.35, 0)
        bulb:Destroy()
        makeCrawler(spawnPosition, Vector3.yAxis)
    end
end

local lastHatch = 0
while script.Parent do
    local currentStage = stage()
    local cap = MAX_CRAWLERS[currentStage]
    if cap and #folder:GetChildren() < cap and os.clock() - lastHatch >= HATCH_INTERVAL[currentStage] then
        lastHatch = os.clock()
        local angle = rng:NextNumber(0, math.pi * 2)
        local radius = rng:NextNumber(3, 9)
        local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
        local hatchPosition, _ = findGround(infectionSpawner.Position + offset)
        task.spawn(hatchBulb, hatchPosition)
    end
    task.wait(2)
end
