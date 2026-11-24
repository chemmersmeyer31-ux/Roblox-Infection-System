-- SPIDER CREATURE TEST SPAWNER
-- Place this Script in ServerScriptService.
-- Create an anchored Part in Workspace named SpiderTestSpawner.
-- Visual prototype only; this remains separate from InfectionSystem.lua.
--
-- Design: eight legs and NOTHING ELSE. All eight legs attach directly
-- to one tiny central pivot. There is no head, abdomen, thorax, or shell.

local RunService = game:GetService("RunService")
local spawner = workspace:WaitForChild("SpiderTestSpawner")
assert(spawner:IsA("BasePart"), "SpiderTestSpawner must be a BasePart.")

local old = workspace:FindFirstChild("SpiderCreatureTest")
if old then old:Destroy() end

local model = Instance.new("Model")
model.Name = "SpiderCreatureTest"
model.Parent = workspace

local ROOT = spawner.Position + Vector3.new(0, 1.7, 0)
local LEG_COUNT = 8

local SEED = Color3.fromRGB(112, 57, 39)
local DARK = Color3.fromRGB(70, 35, 29)
local RIDGE = Color3.fromRGB(139, 75, 49)

local function part(name, shape, size, color, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = shape
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.CorrodedMetal
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = model
    return p
end

local function between(p, a, b, thickness)
    local delta = b - a
    local length = math.max(delta.Magnitude, 0.04)
    local axis = delta.Unit
    local up = Vector3.new(0, 1, 0) - axis * axis.Y
    if up.Magnitude < 0.04 then
        up = Vector3.new(1, 0, 0) - axis * axis.X
    end
    up = up.Unit
    local side = axis:Cross(up).Unit
    p.Size = Vector3.new(length, thickness, thickness)
    p.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

-- The central pivot is deliberately almost invisible: it is only the
-- attachment point for the legs, not a creature body.
local pivot = part("LegAttachmentPoint", Enum.PartType.Ball,
    Vector3.new(0.16, 0.16, 0.16), DARK)
pivot.Transparency = 0.15

local legs = {}
for i = 1, LEG_COUNT do
    local upper = part("LegRoot" .. i, Enum.PartType.Cylinder,
        Vector3.new(1, 0.24, 0.24), DARK)
    local lower = part("LegOuter" .. i, Enum.PartType.Cylinder,
        Vector3.new(1, 0.17, 0.17), SEED)
    local knee = part("LegJoint" .. i, Enum.PartType.Ball,
        Vector3.new(0.21, 0.21, 0.21), RIDGE)
    local tip = part("LegTip" .. i, Enum.PartType.Cylinder,
        Vector3.new(1, 0.10, 0.10), DARK)

    legs[i] = {
        upper = upper,
        lower = lower,
        knee = knee,
        tip = tip,
        angle = ((i - 1) / LEG_COUNT) * math.pi * 2,
        length = ({1.00, 1.08, 0.94, 1.12, 1.04, 0.96, 1.10, 0.98})[i],
    }
end

local started = os.clock()
local connection
connection = RunService.Heartbeat:Connect(function()
    if not model.Parent or not spawner.Parent then
        if connection then connection:Disconnect() end
        return
    end

    local t = os.clock() - started
    local center = ROOT + Vector3.new(0, math.sin(t * 3.5) * 0.025, 0)
    pivot.Position = center

    for i, leg in ipairs(legs) do
        local angle = leg.angle
        local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
        local phase = t * 5.5 + ((i % 2 == 0) and math.pi or 0)
        local stride = math.sin(phase) * 0.22
        local lift = math.max(0, math.cos(phase)) * 0.17
        local length = leg.length

        -- Every leg begins at the exact same central attachment point.
        local root = center + radial * 0.07
        local knee = center
            + radial * (1.05 * length + stride * 0.25)
            + Vector3.new(0, -0.05 + lift * 0.3, 0)
            + tangent * (math.sin(phase) * 0.08)
        local foot = center
            + radial * (2.05 * length + stride)
            + Vector3.new(0, -1.25 + lift, 0)
        local clawEnd = foot + radial * 0.20 + Vector3.new(0, -0.10, 0)

        between(leg.upper, root, knee, 0.24)
        between(leg.lower, knee, foot, 0.17)
        between(leg.tip, foot, clawEnd, 0.10)
        leg.knee.Position = knee
    end
end)

print("[SPIDER TEST] Spawned the eight-legs-only radial spider prototype.")
