-- SPIDER CREATURE TEST SPAWNER
-- Place this Script in ServerScriptService.
-- Create an anchored Part in Workspace named SpiderTestSpawner.
-- Visual prototype only: separate from the main InfectionSystem.

local RunService = game:GetService("RunService")

local spawner = workspace:WaitForChild("SpiderTestSpawner")
assert(spawner:IsA("BasePart"), "SpiderTestSpawner must be a BasePart.")

local old = workspace:FindFirstChild("SpiderCreatureTest")
if old then old:Destroy() end

local model = Instance.new("Model")
model.Name = "SpiderCreatureTest"
model.Parent = workspace

local ROOT = spawner.Position + Vector3.new(0, 2.15, 0)
local LEG_COUNT = 8
local LEG_SPREAD = 2.25

-- Match the Stage 1 infection seed: rusty, dark reddish-brown and organic.
local SEED = Color3.fromRGB(112, 57, 39)
local SEED_DARK = Color3.fromRGB(77, 39, 31)
local RIDGE = Color3.fromRGB(139, 75, 49)
local EYE = Color3.fromRGB(224, 157, 66)

local function makePart(name, shape, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.CorrodedMetal
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
	part.Parent = model
	return part
end

local function setBetween(part, a, b, thicknessX, thicknessY)
	local delta = b - a
	local length = math.max(delta.Magnitude, 0.05)
	local axis = delta.Unit
	local up = Vector3.new(0, 1, 0) - axis * axis.Y
	if up.Magnitude < 0.05 then
		up = Vector3.new(1, 0, 0) - axis * axis.X
	end
	up = up.Unit
	local side = axis:Cross(up).Unit
	part.Size = Vector3.new(length, thicknessX or part.Size.Y, thicknessY or part.Size.Z)
	part.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

-- One substantial seed-like core is the visual focus, not a stack of balls.
local core = makePart("SeedCore", Enum.PartType.Ball, Vector3.new(1.75, 1.48, 1.55), SEED)
local abdomen = makePart("RearSeedLobe", Enum.PartType.Ball, Vector3.new(1.25, 1.05, 1.18), SEED_DARK)
local frontShell = makePart("FrontShell", Enum.PartType.Ball, Vector3.new(0.88, 0.72, 0.82), SEED)
local dorsalRidge = makePart("DorsalGrowth", Enum.PartType.Ball, Vector3.new(1.0, 0.22, 0.88), RIDGE)

-- Small uneven growth ridges break up the smooth toy-like silhouette.
local ridges = {}
for i = 1, 3 do
	local ridge = makePart("SeedRidge" .. i, Enum.PartType.Ball,
		Vector3.new(0.42, 0.13, 0.62), RIDGE)
	ridges[i] = ridge
end

-- Two tiny amber eye points sit low on the front shell.
local eyes = {}
for i = 1, 2 do
	eyes[i] = makePart("Eye" .. i, Enum.PartType.Ball, Vector3.new(0.13, 0.13, 0.10), EYE, Enum.Material.Neon)
end

-- Each leg has a thick root, a long angular shin and a small hooked foot.
local legs = {}
for i = 1, LEG_COUNT do
	local upper = makePart("LegRoot" .. i, Enum.PartType.Cylinder,
		Vector3.new(1, 0.30, 0.30), SEED_DARK)
	local lower = makePart("LegShin" .. i, Enum.PartType.Cylinder,
		Vector3.new(1, 0.21, 0.21), RIDGE)
	local joint = makePart("LegJoint" .. i, Enum.PartType.Ball,
		Vector3.new(0.29, 0.29, 0.29), SEED)
	local foot = makePart("FootHook" .. i, Enum.PartType.Cylinder,
		Vector3.new(1, 0.13, 0.13), SEED_DARK)
	legs[i] = {
		upper = upper, lower = lower, joint = joint, foot = foot,
		side = (i <= 4) and -1 or 1,
		pair = (i - 1) % 4,
	}
end

local startedAt = os.clock()
local connection
connection = RunService.Heartbeat:Connect(function()
	if not model.Parent or not spawner.Parent then
		if connection then connection:Disconnect() end
		return
	end

	local t = os.clock() - startedAt
	local bob = math.sin(t * 4.2) * 0.045
	local center = ROOT + Vector3.new(0, bob, 0)

	-- Head faces forward; the larger seed-like abdomen trails behind it.
	local facing = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0)
	local forward = facing.LookVector
	local right = facing.RightVector

	core.CFrame = CFrame.lookAt(center, center + forward)
	abdomen.CFrame = CFrame.lookAt(center + forward * 0.92 + Vector3.new(0, 0.02, 0), center + forward * 1.92)
	frontShell.CFrame = CFrame.lookAt(center - forward * 0.78 + Vector3.new(0, -0.08, 0), center - forward * 1.6)
	dorsalRidge.CFrame = CFrame.new(center + Vector3.new(0, 0.67, 0)) * facing.Rotation

	for i, ridge in ipairs(ridges) do
		local offset = (i - 2) * 0.38
		ridge.CFrame = CFrame.new(center + Vector3.new(0, 0.69, 0) + forward * offset) * facing.Rotation
	end

	for i, eye in ipairs(eyes) do
		local side = (i == 1) and -1 or 1
		eye.Position = center - forward * 1.12 + right * (side * 0.20) + Vector3.new(0, 0.02, 0)
	end

	for _, leg in ipairs(legs) do
		local pair = leg.pair
		local side = leg.side
		local longitudinal = (pair - 1.5) * 0.48
		local phase = t * 6.2 + ((pair % 2 == 0) and math.pi or 0) + (side == 1 and math.pi or 0)
		local swing = math.sin(phase)
		local lift = math.max(0, math.cos(phase)) * 0.24

		local hip = center + forward * longitudinal + right * (side * 0.58) + Vector3.new(0, -0.20, 0)
		local knee = hip
			+ right * (side * 0.95)
			- forward * (0.25 + longitudinal * 0.30)
			+ Vector3.new(0, 0.18 + lift * 0.3, 0)
		local footPoint = hip
			+ right * (side * LEG_SPREAD)
			- forward * (0.55 + longitudinal * 0.48 - swing * 0.24)
			+ Vector3.new(0, -1.72 + lift, 0)
		local toe = footPoint + right * (side * 0.22) - forward * 0.18 + Vector3.new(0, -0.05, 0)

		setBetween(leg.upper, hip, knee, 0.30, 0.30)
		setBetween(leg.lower, knee, footPoint, 0.21, 0.21)
		setBetween(leg.foot, footPoint, toe, 0.13, 0.13)
		leg.joint.Position = knee
	end
end)

print("[SPIDER TEST] Spawned the remodeled seed-creature spider. Visual prototype only.")
