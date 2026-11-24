-- SPIDER CREATURE TEST SPAWNER
-- Place this Script in ServerScriptService.
-- Create an anchored Part in Workspace named SpiderTestSpawner.
-- The creature is generated separately from the main InfectionSystem.

local RunService = game:GetService("RunService")

local spawner = workspace:WaitForChild("SpiderTestSpawner")
assert(spawner:IsA("BasePart"), "SpiderTestSpawner must be a BasePart.")

local old = workspace:FindFirstChild("SpiderCreatureTest")
if old then
	old:Destroy()
end

local model = Instance.new("Model")
model.Name = "SpiderCreatureTest"
model.Parent = workspace

local ROOT = spawner.Position + Vector3.new(0, 2.2, 0)
local BODY_LENGTH = 3.2
local BODY_WIDTH = 1.35
local BODY_HEIGHT = 1.05
local LEG_COUNT = 8
local LEG_LENGTH = 2.15

local DARK = Color3.fromRGB(53, 31, 28)
local MID = Color3.fromRGB(82, 43, 34)
local HIGHLIGHT = Color3.fromRGB(111, 61, 43)

local function makePart(name, shape, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Slate
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function setBetween(part, a, b, thickness)
	local delta = b - a
	local length = math.max(delta.Magnitude, 0.05)
	local axis = delta.Unit
	local up = Vector3.new(0, 1, 0) - axis * axis.Y
	if up.Magnitude < 0.05 then
		up = Vector3.new(1, 0, 0) - axis * axis.X
	end
	up = up.Unit
	local side = axis:Cross(up).Unit
	part.Size = Vector3.new(length, thickness, thickness)
	part.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

-- Long, narrow abdomen with a smaller thorax and head.
local abdomen = makePart(
	"SpiderAbdomen",
	Enum.PartType.Ball,
	Vector3.new(BODY_LENGTH * 0.58, BODY_HEIGHT, BODY_WIDTH),
	MID
)
local thorax = makePart(
	"SpiderThorax",
	Enum.PartType.Ball,
	Vector3.new(1.35, 0.9, 1.0),
	DARK
)
local head = makePart(
	"SpiderHead",
	Enum.PartType.Ball,
	Vector3.new(0.72, 0.68, 0.72),
	HIGHLIGHT
)

-- Small raised plates give the silhouette a little more character.
local backPlate = makePart(
	"SpiderBackPlate",
	Enum.PartType.Ball,
	Vector3.new(1.45, 0.24, 0.9),
	HIGHLIGHT
)

local legs = {}
for index = 1, LEG_COUNT do
	local side = (index <= 4) and -1 or 1
	local pairIndex = (index - 1) % 4
	local upper = makePart(
		"SpiderLegUpper" .. index,
		Enum.PartType.Cylinder,
		Vector3.new(1, 0.28, 0.28),
		MID,
		Enum.Material.CorrodedMetal
	)
	local lower = makePart(
		"SpiderLegLower" .. index,
		Enum.PartType.Cylinder,
		Vector3.new(1, 0.21, 0.21),
		DARK,
		Enum.Material.CorrodedMetal
	)
	local joint = makePart(
		"SpiderLegJoint" .. index,
		Enum.PartType.Ball,
		Vector3.new(0.34, 0.34, 0.34),
		HIGHLIGHT
	)
	table.insert(legs, {
		upper = upper,
		lower = lower,
		joint = joint,
		side = side,
		pair = pairIndex
	})
end

local startedAt = os.clock()
local connection
connection = RunService.Heartbeat:Connect(function()
	if not model.Parent or not spawner.Parent then
		if connection then connection:Disconnect() end
		return
	end

	local t = os.clock() - startedAt
	local bodyBob = math.sin(t * 5) * 0.07
	local center = ROOT + Vector3.new(0, bodyBob, 0)

	-- The long axis points along local Z, giving the creature a narrow profile.
	local facing = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0)
	local abdomenPosition = center + facing.LookVector * 0.48
	local thoraxPosition = center - facing.LookVector * 0.62
	local headPosition = center - facing.LookVector * 1.28

	abdomen.CFrame = CFrame.new(abdomenPosition) * facing.Rotation
	thorax.CFrame = CFrame.new(thoraxPosition) * facing.Rotation
	head.CFrame = CFrame.new(headPosition) * facing.Rotation
	backPlate.CFrame = CFrame.new(abdomenPosition + Vector3.new(0, 0.43, 0)) * facing.Rotation

	for index, leg in ipairs(legs) do
		local pair = leg.pair
		local side = leg.side
		local longitudinal = (pair - 1.5) * 0.55
		local phase = t * 7 + ((pair % 2 == 0) and math.pi or 0) + (side == 1 and math.pi or 0)
		local swing = math.sin(phase)
		local lift = math.max(0, math.cos(phase)) * 0.38

		local hip = thoraxPosition
			+ facing.LookVector * longitudinal
			+ Vector3.new(side * 0.34, -0.18, 0)
		local outward = facing.RightVector * side
		local forward = facing.LookVector

		local knee = hip
			+ outward * (0.95 + swing * 0.16)
			+ forward * (0.55 + longitudinal * 0.42 + swing * 0.22)
			+ Vector3.new(0, 0.12 + lift * 0.25, 0)

		local foot = hip
			+ outward * (LEG_LENGTH * 0.88)
			+ forward * (longitudinal * 0.75 + swing * 0.42)
			+ Vector3.new(0, -1.65 + lift, 0)

		setBetween(leg.upper, hip, knee, 0.28)
		setBetween(leg.lower, knee, foot, 0.21)
		leg.joint.Position = knee
	end
end)

print("[SPIDER TEST] Spawned SpiderCreatureTest. Remove the model or stop the server to end the test.")
