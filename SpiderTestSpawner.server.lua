-- SPIDER CREATURE TEST SPAWNER
-- Place this Script in ServerScriptService.
-- Create an anchored Part in Workspace named SpiderTestSpawner.
-- Visual prototype only; this remains separate from InfectionSystem.lua.

local RunService = game:GetService("RunService")
local spawner = workspace:WaitForChild("SpiderTestSpawner")
assert(spawner:IsA("BasePart"), "SpiderTestSpawner must be a BasePart.")

local old = workspace:FindFirstChild("SpiderCreatureTest")
if old then old:Destroy() end

local model = Instance.new("Model")
model.Name = "SpiderCreatureTest"
model.Parent = workspace

local ROOT = spawner.Position + Vector3.new(0, 2.0, 0)
local LEG_COUNT = 8

-- Same rusty seed-bulb palette as InfectionSystem.lua.
local SEED = Color3.fromRGB(112, 57, 39)
local DARK = Color3.fromRGB(70, 35, 29)
local MID = Color3.fromRGB(91, 44, 33)
local RIDGE = Color3.fromRGB(139, 75, 49)
local AMBER = Color3.fromRGB(224, 157, 66)

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
	local d = b - a
	local length = math.max(d.Magnitude, 0.04)
	local axis = d.Unit
	local up = Vector3.new(0, 1, 0) - axis * axis.Y
	if up.Magnitude < 0.04 then
		up = Vector3.new(1, 0, 0) - axis * axis.X
	end
	up = up.Unit
	local side = axis:Cross(up).Unit
	p.Size = Vector3.new(length, thickness, thickness)
	p.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

-- The body is low and elongated: a seed-like abdomen, compact thorax and
-- wedge-shaped head. The pieces overlap so they read as one creature.
local abdomen = part("OrganicAbdomen", Enum.PartType.Ball, Vector3.new(2.25, 1.42, 1.62), SEED)
local thorax = part("Thorax", Enum.PartType.Ball, Vector3.new(1.05, 0.83, 1.02), DARK)
local head = part("LowHead", Enum.PartType.Ball, Vector3.new(0.78, 0.61, 0.78), MID)

-- Layered carapace plates follow the back instead of looking like extra balls.
local shell = part("DorsalCarapace", Enum.PartType.Ball, Vector3.new(1.72, 0.34, 1.28), RIDGE)
local sidePlates = {}
for i = 1, 4 do
	sidePlates[i] = part("CarapacePlate" .. i, Enum.PartType.Wedge,
		Vector3.new(0.72, 0.34, 0.78), (i % 2 == 0) and MID or DARK)
end

-- Uneven thorn-like infection growths along the back.
local spines = {}
for i = 1, 3 do
	spines[i] = part("SeedSpine" .. i, Enum.PartType.Cylinder,
		Vector3.new(0.48, 0.15, 0.15), RIDGE)
end
local tendrilNubs = {}
for i = 1, 2 do
	tendrilNubs[i] = part("TendrilBud" .. i, Enum.PartType.Ball,
		Vector3.new(0.32, 0.28, 0.30), DARK)
end

-- Small amber sensory points, tucked close to the head.
local eyes = {
	part("EyeLeft", Enum.PartType.Ball, Vector3.new(0.12, 0.12, 0.10), AMBER, Enum.Material.Neon),
	part("EyeRight", Enum.PartType.Ball, Vector3.new(0.12, 0.12, 0.10), AMBER, Enum.Material.Neon),
}

-- Eight legs: short heavy upper segments, longer angled lower segments,
-- and little hooked tips. Individual lengths vary for an irregular silhouette.
local legs = {}
for i = 1, LEG_COUNT do
	local upper = part("LegCoxa" .. i, Enum.PartType.Cylinder, Vector3.new(1, 0.31, 0.31), DARK)
	local lower = part("LegTibia" .. i, Enum.PartType.Cylinder, Vector3.new(1, 0.20, 0.20), RIDGE)
	local joint = part("LegKnee" .. i, Enum.PartType.Ball, Vector3.new(0.25, 0.25, 0.25), MID)
	local claw = part("LegClaw" .. i, Enum.PartType.Cylinder, Vector3.new(1, 0.12, 0.12), DARK)
	local pair = (i - 1) % 4
	local side = (i <= 4) and -1 or 1
	legs[i] = {
		upper = upper, lower = lower, joint = joint, claw = claw,
		pair = pair, side = side,
		lengthScale = ({1.08, 0.94, 1.12, 0.88})[pair + 1] * ((i == 2 or i == 7) and 0.92 or 1),
	}
end

local start = os.clock()
local connection
connection = RunService.Heartbeat:Connect(function()
	if not model.Parent or not spawner.Parent then
		if connection then connection:Disconnect() end
		return
	end

	local t = os.clock() - start
	local bob = math.sin(t * 4.1) * 0.035
	local center = ROOT + Vector3.new(0, bob, 0)
	-- Face toward local -Z. This keeps the creature's head clearly in front.
	local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(180), 0)
	local forward, right = frame.LookVector, frame.RightVector

	local abdomenPos = center + forward * 0.70 + Vector3.new(0, 0.02, 0)
	local thoraxPos = center - forward * 0.48 + Vector3.new(0, -0.03, 0)
	local headPos = center - forward * 1.12 + Vector3.new(0, -0.16, 0)

	abdomen.CFrame = CFrame.lookAt(abdomenPos, abdomenPos + forward)
	thorax.CFrame = CFrame.lookAt(thoraxPos, thoraxPos + forward)
	head.CFrame = CFrame.lookAt(headPos, headPos + forward)
	shell.CFrame = CFrame.new(abdomenPos + Vector3.new(0, 0.58, 0)) * frame.Rotation

	for i, plate in ipairs(sidePlates) do
		local side = (i <= 2) and -1 or 1
		local row = (i - 1) % 2
		local pos = abdomenPos + forward * ((row == 0) and -0.18 or 0.55)
			+ right * (side * 0.64) + Vector3.new(0, 0.18, 0)
		plate.CFrame = CFrame.lookAt(pos, pos + forward) * CFrame.Angles(0, side * math.rad(90), 0)
	end

	for i, spine in ipairs(spines) do
		local zOffset = (i - 2) * 0.52
		local base = abdomenPos - forward * zOffset + Vector3.new(0, 0.64, 0)
		local tip = base + Vector3.new((i == 2) and 0 or (i == 1 and -0.17 or 0.20), 0.30 + (i == 2 and 0.12 or 0), 0)
		between(spine, base, tip, 0.15)
	end
	for i, bud in ipairs(tendrilNubs) do
		local side = (i == 1) and -1 or 1
		bud.CFrame = CFrame.new(abdomenPos + right * (side * 0.82) + Vector3.new(0, 0.16, 0))
	end

	for i, eye in ipairs(eyes) do
		local side = (i == 1) and -1 or 1
		eye.Position = headPos - forward * 0.32 + right * (side * 0.23) + Vector3.new(0, 0.06, 0)
	end

	for _, leg in ipairs(legs) do
		local pair, side = leg.pair, leg.side
		local longitudinal = (pair - 1.5) * 0.48
		local phase = t * 6.0 + ((pair % 2 == 0) and math.pi or 0)
			+ ((side == 1) and math.pi or 0)
		local swing = math.sin(phase)
		local lift = math.max(0, math.cos(phase)) * 0.20
		local scale = leg.lengthScale

		local hip = thoraxPos + forward * longitudinal + right * (side * 0.42)
			+ Vector3.new(0, -0.17, 0)
		local knee = hip + right * (side * 0.82 * scale)
			- forward * (0.20 + longitudinal * 0.34)
			+ Vector3.new(0, 0.10 + lift * 0.25, 0)
		local foot = hip + right * (side * 1.92 * scale)
			- forward * (0.48 + longitudinal * 0.55 - swing * 0.22)
			+ Vector3.new(0, -1.55 + lift, 0)
		local clawEnd = foot + right * (side * 0.16) - forward * 0.20
			+ Vector3.new(0, -0.04, 0)

		between(leg.upper, hip, knee, 0.31)
		between(leg.lower, knee, foot, 0.20)
		between(leg.claw, foot, clawEnd, 0.12)
		leg.joint.Position = knee
	end
end)

print("[SPIDER TEST] Spawned the organic seed-spider visual prototype.")
