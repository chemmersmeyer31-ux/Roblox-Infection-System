-- INFECTION SYSTEM - PROTOTYPE 22
-- CLOSED COCOON / CEILING HOIST / NO CAPTURE BUBBLE
-- LIVING ENVIRONMENTAL INFECTION

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

local rng = Random.new()

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local MAX_SEGMENTS = 6000

local MIN_LENGTH = 1.2
local MAX_LENGTH = 2.2

local GROWTH_DELAY = 1.1
local GROWTH_TIME = 2.0

local BRANCH_CHANCE = 0.42
local MAX_BRANCH_DEPTH = 5

local MIN_BRANCH_STEPS = 24
local MAX_BRANCH_STEPS = 48

local SURFACE_OFFSET = 0.06
local MIN_SPACING = 0.72

local PULSE_MIN_TIME = 1.5
local PULSE_MAX_TIME = 2.8
local PULSE_AMOUNT = 0.16

local HANGING_CHANCE = 0.80
local HANGING_MIN_LENGTH = 18
local HANGING_MAX_LENGTH = 32

local MAX_GROUND_STALKS = 3
local MAX_GROUND_ANCHORS = 60
local GROUND_STALK_TRIGGER_DISTANCE = 14
local GROUND_STALK_MIN_SPACING = 12
local GROUND_STALK_HEIGHT = 4.4
local GROUND_STALK_MAX_LEAN = 1.8
local GROUND_STALK_SEGMENTS = 5
local GROUND_STALK_SCAN_INTERVAL = 0.35
local GROUND_STALK_SPAWN_COOLDOWN = 6.5
local GROUND_STALK_GRAB_COOLDOWN = 12.0

local MAIN_COLOR = Color3.fromRGB(75, 39, 31)
local LIGHT_COLOR = Color3.fromRGB(112, 58, 39)
local DARK_COLOR = Color3.fromRGB(51, 29, 25)

local generatedCount = 0
local occupiedPositions = {}
local growthSegments = {}
local growthStage = 1
local relocationStarted = false
local infectionBulb = nil
local OCCUPANCY_CELL_SIZE = 1.5

local groundAnchors = {}
local ceilingAnchors = {}
local ceilingVines = {}
local groundStalks = {}

local activeGrabCount = 0
local infectionGrowthBoosts = 0
local lastGroundStalkSpawn = 0
local infectedPlayers = {}

--------------------------------------------------
-- SPAWNER
--------------------------------------------------

local spawner = workspace:WaitForChild("InfectionSpawner")

local oldFolder = workspace:FindFirstChild("GeneratedInfection")
if oldFolder then
	oldFolder:Destroy()
end

local infectionFolder = Instance.new("Folder")
infectionFolder.Name = "GeneratedInfection"
infectionFolder.Parent = workspace

--------------------------------------------------
-- RAYCAST SETTINGS
--------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {spawner, infectionFolder}
rayParams.IgnoreWater = true

local directions = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1)
}

--------------------------------------------------
-- OVERLAP PREVENTION
--------------------------------------------------

local function getCellKey(position)
	local x = math.floor(position.X / OCCUPANCY_CELL_SIZE)
	local y = math.floor(position.Y / OCCUPANCY_CELL_SIZE)
	local z = math.floor(position.Z / OCCUPANCY_CELL_SIZE)
	return x .. ":" .. y .. ":" .. z, x, y, z
end

local function canPlaceSegment(startPosition, endPosition, thickness)
	local difference = endPosition - startPosition
	local length = difference.Magnitude

	if length < 0.05 then
		return false
	end

	local spacing = math.max(MIN_SPACING, thickness * 1.35)
	local connectionLength = 0.38
	local sampleCount = math.max(4, math.ceil(length / 0.28))

	for sampleIndex = 2, sampleCount do
		local alpha = sampleIndex / sampleCount
		local sample = startPosition + difference * alpha
		local distanceFromStart = length * alpha

		if distanceFromStart > connectionLength then
			local _, cx, cy, cz = getCellKey(sample)
			local cellRadius = math.ceil(spacing / OCCUPANCY_CELL_SIZE) + 1

			for x = cx - cellRadius, cx + cellRadius do
				for y = cy - cellRadius, cy + cellRadius do
					for z = cz - cellRadius, cz + cellRadius do
						local bucket = occupiedPositions[
						x .. ":" .. y .. ":" .. z
						]

						if bucket then
							for _, occupied in ipairs(bucket) do
								local isParentConnection =
									(occupied - startPosition).Magnitude
									<= connectionLength

								if not isParentConnection
									and (sample - occupied).Magnitude < spacing then
									return false
								end
							end
						end
					end
				end
			end
		end
	end

	return true
end

local function registerSegment(startPosition, endPosition)
	local difference = endPosition - startPosition
	local length = difference.Magnitude
	local sampleCount = math.max(2, math.ceil(length / 0.28))

	for sampleIndex = 0, sampleCount do
		local alpha = sampleIndex / sampleCount
		local sample = startPosition + difference * alpha
		local key = getCellKey(sample)

		if not occupiedPositions[key] then
			occupiedPositions[key] = {}
		end

		table.insert(occupiedPositions[key], sample)
	end
end

local function registerGroundAnchor(position, normal)
	if normal.Y < 0.82 then return end
	if position.Y > spawner.Position.Y + 6 then return end
	if #groundAnchors >= MAX_GROUND_ANCHORS then return end

	for _, anchor in ipairs(groundAnchors) do
		if (anchor.position - position).Magnitude < 3.5 then
			return
		end
	end

	table.insert(groundAnchors, {
		position = position,
		used = false
	})
end

local MAX_CEILING_ANCHORS = 40
local CEILING_ANCHOR_SPACING = 4.5

local function registerCeilingAnchor(position, normal)
	if normal.Y > -0.72 then return end
	if #ceilingAnchors >= MAX_CEILING_ANCHORS then return end

	for _, anchor in ipairs(ceilingAnchors) do
		if (anchor.position - position).Magnitude < CEILING_ANCHOR_SPACING then
			return
		end
	end

	table.insert(ceilingAnchors, {
		position = position,
		used = false
	})
end

--------------------------------------------------
-- FIND STARTING SURFACE
--------------------------------------------------

local function findStartingSurface()
	local bestHit = nil
	local bestDistance = math.huge

	for _, direction in ipairs(directions) do
		local origin = spawner.Position + direction * 0.5
		local result = workspace:Raycast(
			origin,
			-direction * 12,
			rayParams
		)

		if result then
			local distance = (result.Position - spawner.Position).Magnitude

			if distance < bestDistance then
				bestDistance = distance
				bestHit = result
			end
		end
	end

	return bestHit
end

--------------------------------------------------
-- COLORS AND THICKNESS
--------------------------------------------------

local function getRandomColor()
	local color = MAIN_COLOR:Lerp(LIGHT_COLOR, rng:NextNumber())

	if rng:NextNumber() < 0.3 then
		color = color:Lerp(DARK_COLOR, rng:NextNumber(0.2, 0.6))
	end

	return color
end

local function getThickness(depth)
	if depth == 0 then
		return rng:NextNumber(0.28, 0.43)
	elseif depth == 1 then
		return rng:NextNumber(0.17, 0.29)
	elseif depth == 2 then
		return rng:NextNumber(0.11, 0.20)
	else
		return rng:NextNumber(0.08, 0.15)
	end
end

--------------------------------------------------
-- CREATE ENVIRONMENTAL SEGMENT
--------------------------------------------------

local function createSegment(startPosition, endPosition, faceNormal, thickness)
	local difference = endPosition - startPosition
	local length = difference.Magnitude

	if length < 0.05 then return nil end

	local direction = difference.Unit
	local up = faceNormal - direction * faceNormal:Dot(direction)

	if up.Magnitude < 0.01 then return nil end
	up = up.Unit

	local side = direction:Cross(up)
	if side.Magnitude < 0.01 then return nil end
	side = side.Unit

	local depth = rng:NextNumber(0.10, 0.19)

	local baseSize = Vector3.new(
		length + math.max(depth, thickness) * 1.15,
		depth * 1.25,
		thickness * 1.25
	)

	local middlePosition =
		(startPosition + endPosition) / 2 + up * (depth / 2)

	local finalCFrame = CFrame.fromMatrix(
		middlePosition,
		direction,
		up,
		side
	)

	local startCFrame = CFrame.fromMatrix(
		startPosition + up * (depth / 2),
		direction,
		up,
		side
	)

	local baseColor = getRandomColor()

	local segment = Instance.new("Part")
	segment.Name = "LivingTendril"
	segment.Shape = Enum.PartType.Cylinder
	segment.Material = Enum.Material.CorrodedMetal
	segment.Color = baseColor
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false
	segment.CanQuery = false
	segment.Size = Vector3.new(0.05, depth, thickness)
	segment.CFrame = startCFrame
	segment.Parent = infectionFolder
	table.insert(growthSegments, segment)

	local growthTween = TweenService:Create(
		segment,
		TweenInfo.new(
			GROWTH_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{
			Size = baseSize,
			CFrame = finalCFrame
		}
	)

	growthTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and segment.Parent then
			local pulseSize = Vector3.new(
				baseSize.X,
				baseSize.Y * (1 + PULSE_AMOUNT),
				baseSize.Z * (1 + PULSE_AMOUNT)
			)

			local pulseTween = TweenService:Create(
				segment,
				TweenInfo.new(
					rng:NextNumber(PULSE_MIN_TIME, PULSE_MAX_TIME),
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true,
					rng:NextNumber(0, 1.5)
				),
				{
					Size = pulseSize,
					Color = baseColor:Lerp(LIGHT_COLOR, 0.16)
				}
			)

			pulseTween:Play()
		end
	end)

	growthTween:Play()
	return segment
end

--------------------------------------------------
-- PLAYER-FACING DIRECTION
--------------------------------------------------

local function getPlayerFacingDirection(position)
	local nearestRoot = nil
	local nearestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root then
			local distance = (root.Position - position).Magnitude

			if distance < nearestDistance then
				nearestDistance = distance
				nearestRoot = root
			end
		end
	end

	if nearestRoot then
		local difference = nearestRoot.Position - position
		local horizontal = Vector3.new(difference.X, 0, difference.Z)

		if horizontal.Magnitude > 0.05 then
			return horizontal.Unit
		end
	end

	return Vector3.new(0, 0, 1)
end

--------------------------------------------------
-- PLAYER SEARCH
--------------------------------------------------

local function findNearestPlayer(position, maxDistance)
	local nearestRoot = nil
	local nearestDistance = maxDistance

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root then
			local offset = root.Position - position
			local horizontalDistance =
				Vector3.new(offset.X, 0, offset.Z).Magnitude

			if math.abs(offset.Y) <= 12
				and horizontalDistance < nearestDistance then

				nearestRoot = root
				nearestDistance = horizontalDistance
			end
		end
	end

	return nearestRoot, nearestDistance
end

--------------------------------------------------
-- PLAYER-REACTIVE GROUND VINES
--------------------------------------------------

local function setRoundedStalkSegment(
	part,
	startPosition,
	endPosition,
	facingDirection,
	radius
)
	local difference = endPosition - startPosition
	local length = difference.Magnitude

	if length < 0.025 then
		part.Transparency = 1
		return
	end

	local axis = difference.Unit
	local up = facingDirection - axis * facingDirection:Dot(axis)

	if up.Magnitude < 0.05 then
		up = Vector3.new(1, 0, 0) - axis * axis.X
	end

	if up.Magnitude < 0.05 then
		up = Vector3.new(0, 0, 1) - axis * axis.Z
	end

	up = up.Unit
	local side = axis:Cross(up)

	if side.Magnitude < 0.05 then
		part.Transparency = 1
		return
	end

	side = side.Unit
	part.Transparency = 0
	part.Size = Vector3.new(length + radius * 0.9, radius * 2, radius * 2)
	part.CFrame = CFrame.fromMatrix(
		(startPosition + endPosition) / 2,
		axis,
		up,
		side
	)
end

local function createGroundStalk(anchor)
	if #groundStalks >= MAX_GROUND_STALKS
		or generatedCount + GROUND_STALK_SEGMENTS > MAX_SEGMENTS then
		return false
	end

	for _, existing in ipairs(groundStalks) do
		if (existing.anchor - anchor.position).Magnitude
			< GROUND_STALK_MIN_SPACING then
			anchor.used = true
			return false
		end
	end

	local model = Instance.new("Model")
	model.Name = "PlayerFacingGroundVine"
	model.Parent = infectionFolder

	local parts = {}

	for index = 1, GROUND_STALK_SEGMENTS do
		local part = Instance.new("Part")
		part.Name = "VineStem"
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.CorrodedMetal
		part.Color = getRandomColor()
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(0.05, 0.28, 0.28)
		part.Parent = model
		table.insert(parts, part)
	end

	generatedCount += GROUND_STALK_SEGMENTS
	anchor.used = true

	table.insert(groundStalks, {
		anchor = anchor.position,
		model = model,
		parts = parts,
		age = 0,
		direction = Vector3.new(0, 0, 1),
		lastTargetDirection = Vector3.new(0, 0, 1)
	})

	return true
end

local function updateGroundStalk(stalk, deltaTime)
	if not stalk.model.Parent then return end

	stalk.age += deltaTime

	local targetRoot, distance = findNearestPlayer(
		stalk.anchor,
		GROUND_STALK_TRIGGER_DISTANCE + 8
	)

	local targetDirection = stalk.lastTargetDirection
	local leanAmount = 0.15

	if targetRoot then
		local offset = targetRoot.Position - stalk.anchor
		local horizontal = Vector3.new(offset.X, 0, offset.Z)

		if horizontal.Magnitude > 0.05 then
			targetDirection = horizontal.Unit
			stalk.lastTargetDirection = targetDirection

			local proximity = 1 - math.clamp(
				distance / (GROUND_STALK_TRIGGER_DISTANCE + 8),
				0,
				1
			)

			leanAmount = 0.35 + GROUND_STALK_MAX_LEAN * proximity
		end
	end

	stalk.direction = stalk.direction:Lerp(
		targetDirection,
		math.clamp(deltaTime * 3.5, 0, 1)
	)

	if stalk.direction.Magnitude > 0.05 then
		stalk.direction = stalk.direction.Unit
	end

	local growDuration = GROWTH_DELAY * GROUND_STALK_SEGMENTS
	local growthAlpha = math.clamp(stalk.age / growDuration, 0, 1)
	local visibleHeight = GROUND_STALK_HEIGHT * growthAlpha
	local visibleLean = leanAmount * growthAlpha

	for index, part in ipairs(stalk.parts) do
		local t0 = (index - 1) / GROUND_STALK_SEGMENTS
		local t1 = math.min(index / GROUND_STALK_SEGMENTS, growthAlpha)

		if t1 <= t0 then
			part.Transparency = 1
		else
			local function pathPoint(t)
				local bend = t * t

				return stalk.anchor + Vector3.new(
					stalk.direction.X * visibleLean * bend,
					visibleHeight * t,
					stalk.direction.Z * visibleLean * bend
				)
			end

			local radius = 0.20
			- (index / GROUND_STALK_SEGMENTS) * 0.035

			setRoundedStalkSegment(
				part,
				pathPoint(t0),
				pathPoint(t1),
				stalk.direction,
				radius
			)
		end
	end
end

local attemptPlayerGrab

local function runGroundStalkSystem()
	local scanClock = 0
	local previousTime = os.clock()

	while infectionFolder.Parent do
		local now = os.clock()
		local deltaTime = math.min(now - previousTime, 0.25)
		previousTime = now
		scanClock += deltaTime

		for _, stalk in ipairs(groundStalks) do
			updateGroundStalk(stalk, deltaTime)

			local stalkReady =
				stalk.age >= GROWTH_DELAY * GROUND_STALK_SEGMENTS

			if stalkReady and not stalk.grabbed and activeGrabCount < 2 then
				local targetRoot = findNearestPlayer(stalk.anchor, 5.2)

				if targetRoot then
					local character = targetRoot.Parent
					local humanoid =
						character and character:FindFirstChildOfClass("Humanoid")

					local player =
						humanoid and Players:GetPlayerFromCharacter(character)

					if player and humanoid and humanoid.Health > 0
						and not infectedPlayers[player]
						and attemptPlayerGrab then

						stalk.grabbed = true

						task.spawn(function()
							local ok, err = pcall(
								attemptPlayerGrab,
								{
									position = stalk.anchor,
									normal = Vector3.new(0, 1, 0),
									used = false
								},
								player,
								character,
								humanoid,
								targetRoot
							)

							if not ok then
								warn(
									"[INFECTION] Ground stalk capture error: "
										.. tostring(err)
								)
							end

							task.wait(GROUND_STALK_GRAB_COOLDOWN)

							if stalk.model and stalk.model.Parent then
								stalk.grabbed = false
							end
						end)
					end
				end
			end
		end

		if scanClock >= GROUND_STALK_SCAN_INTERVAL then
			scanClock = 0

			-- Player-reactive ground vines are a mature-infection feature.
			-- Keep the seed and developing bulb phases visually quiet.
			if growthStage >= 3
				and now - lastGroundStalkSpawn >= GROUND_STALK_SPAWN_COOLDOWN
				and #groundStalks < MAX_GROUND_STALKS then

				for _, anchor in ipairs(groundAnchors) do
					if not anchor.used then
						local root = findNearestPlayer(
							anchor.position,
							GROUND_STALK_TRIGGER_DISTANCE
						)

						if root then
							if createGroundStalk(anchor) then
								lastGroundStalkSpawn = now
							end
							break
						end
					end
				end
			end
		end

		task.wait(0.1)
	end
end

--------------------------------------------------
-- DECORATIVE CEILING VINES
--------------------------------------------------

local MAX_DECORATIVE_CEILING_VINES = 5
local CEILING_VINE_SEGMENT_LENGTH = 0.72
local CEILING_VINE_MAX_SEGMENTS = 36
local CEILING_VINE_MAX_DROP = 26
local CEILING_VINE_THICKNESS = 0.16
local CEILING_VINE_SCAN_INTERVAL = 1.0

local function makeCeilingVineSegment(parent, startPoint, endPoint, thickness)
	local delta = endPoint - startPoint
	local length = math.max(delta.Magnitude, 0.1)
	local axis = delta.Unit

	local up = Vector3.new(0, 0, -1)
	up = up - axis * up:Dot(axis)

	if up.Magnitude < 0.05 then
		up = Vector3.new(1, 0, 0) - axis * axis.X
	end

	up = up.Unit
	local side = axis:Cross(up).Unit

	local part = Instance.new("Part")
	part.Name = "PushableCeilingVineSegment"
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.CorrodedMetal
	part.Color = getRandomColor()
	part.Size = Vector3.new(length, thickness, thickness)
	part.CFrame = CFrame.fromMatrix(
		(startPoint + endPoint) * 0.5,
		axis,
		up,
		side
	)
	part.Anchored = false
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = false
	part.CustomPhysicalProperties =
		PhysicalProperties.new(0.35, 0.75, 0.05, 1, 1)
	part.Parent = parent

	return part
end

local function createPushableCeilingVine(anchor)
	if #ceilingVines >= MAX_DECORATIVE_CEILING_VINES then
		return false
	end

	local floorResult = workspace:Raycast(
		anchor.position - Vector3.new(0, 0.12, 0),
		Vector3.new(0, -CEILING_VINE_MAX_DROP, 0),
		rayParams
	)

	if not floorResult then return false end

	local availableDrop = math.max(1.5, floorResult.Distance - 0.12)

	local segmentCount = math.clamp(
		math.ceil(availableDrop / CEILING_VINE_SEGMENT_LENGTH),
		2,
		CEILING_VINE_MAX_SEGMENTS
	)

	local segmentLength = availableDrop / segmentCount

	local model = Instance.new("Model")
	model.Name = "DecorativePushableCeilingVine"
	model.Parent = infectionFolder

	local anchorPart = Instance.new("Part")
	anchorPart.Name = "CeilingVineAnchor"
	anchorPart.Size = Vector3.new(0.18, 0.18, 0.18)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.CFrame = CFrame.new(anchor.position)
	anchorPart.Parent = model

	local previousAttachment = Instance.new("Attachment")
	previousAttachment.Name = "VineRootAttachment"
	previousAttachment.Parent = anchorPart

	local nearbyRoot = findNearestPlayer(anchor.position, 30)
	local leanDirection = Vector3.zero

	if nearbyRoot then
		local offset = nearbyRoot.Position - anchor.position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)

		if horizontal.Magnitude > 0.05 then
			leanDirection = horizontal.Unit * 0.28
		end
	end

	local segmentParts = {}

	for index = 1, segmentCount do
		local t0 = (index - 1) / segmentCount
		local t1 = index / segmentCount

		local startPoint = anchor.position
			+ Vector3.new(0, -segmentLength * (index - 1), 0)
			+ leanDirection * t0

		local endPoint = anchor.position
			+ Vector3.new(0, -segmentLength * index, 0)
			+ leanDirection * t1

		local part = makeCeilingVineSegment(
			model,
			startPoint,
			endPoint,
			CEILING_VINE_THICKNESS * (1 - (index - 1) * 0.10)
		)

		table.insert(segmentParts, part)

		local topAttachment = Instance.new("Attachment")
		topAttachment.Position = Vector3.new(-part.Size.X * 0.5, 0, 0)
		topAttachment.Parent = part

		local bottomAttachment = Instance.new("Attachment")
		bottomAttachment.Position = Vector3.new(part.Size.X * 0.5, 0, 0)
		bottomAttachment.Parent = part

		local joint = Instance.new("BallSocketConstraint")
		joint.Attachment0 = previousAttachment
		joint.Attachment1 = topAttachment
		joint.LimitsEnabled = true
		joint.UpperAngle = 28
		joint.Parent = model

		previousAttachment = bottomAttachment
	end

	local bottomPart = segmentParts[#segmentParts]

	local swayAttachment = Instance.new("Attachment")
	swayAttachment.Parent = bottomPart

	local swayForce = Instance.new("VectorForce")
	swayForce.Attachment0 = swayAttachment
	swayForce.RelativeTo = Enum.ActuatorRelativeTo.World
	swayForce.ApplyAtCenterOfMass = true
	swayForce.Force = Vector3.zero
	swayForce.Parent = bottomPart

	anchor.used = true

	table.insert(ceilingVines, {
		model = model,
		parts = segmentParts,
		anchor = anchor.position,
		swayForce = swayForce,
		bottomPart = bottomPart
	})

	return true
end

local function runCeilingVineSystem()
	local scanClock = 0

	while infectionFolder.Parent do
		scanClock += 0.2

		for _, vine in ipairs(ceilingVines) do
			if vine.model and vine.model.Parent
				and vine.bottomPart and vine.bottomPart.Parent
				and vine.swayForce and vine.swayForce.Parent then

				local targetRoot = findNearestPlayer(vine.anchor, 24)

				if targetRoot then
					local offset = targetRoot.Position - vine.bottomPart.Position
					local horizontal = Vector3.new(offset.X, 0, offset.Z)

					if horizontal.Magnitude > 0.05 then
						vine.swayForce.Force =
							horizontal.Unit * vine.bottomPart.AssemblyMass * 1.6
					end
				else
					vine.swayForce.Force = Vector3.zero
				end
			end
		end

		if scanClock >= CEILING_VINE_SCAN_INTERVAL then
			scanClock = 0

			if #ceilingVines < MAX_DECORATIVE_CEILING_VINES then
				for _, anchor in ipairs(ceilingAnchors) do
					if not anchor.used then
						createPushableCeilingVine(anchor)
						break
					end
				end
			end
		end

		task.wait(0.2)
	end
end

--------------------------------------------------
-- INFECTION SPAWNER BULB
--------------------------------------------------

local BULB_GROWTH_TIME = 55
local BULB_PULSE_MIN_TIME = 2.2
local BULB_PULSE_MAX_TIME = 3.4

local function createSpawnerBulb(surfacePosition, surfaceNormal)
	local bulb = Instance.new("Part")
	bulb.Name = "InfectionSpawnerBulb"
	bulb.Shape = Enum.PartType.Ball
	bulb.Material = Enum.Material.CorrodedMetal
	bulb.Color = Color3.fromRGB(112, 57, 39)
	bulb.Anchored = true
	bulb.CanCollide = false
	bulb.CanTouch = false
	bulb.CanQuery = false
	bulb.CastShadow = true
	bulb.Size = Vector3.new(0.15, 0.15, 0.15)
	bulb.CFrame = CFrame.new(
		surfacePosition + surfaceNormal.Unit * 0.12
	)
	bulb.Parent = infectionFolder

	local targetSize = Vector3.new(1.25, 1.25, 1.25)
	-- Keep the bulb resting against the surface as it grows instead of
	-- lifting its center far away and making it look like it is floating.
	local targetCFrame = CFrame.new(
		surfacePosition + surfaceNormal.Unit * (targetSize.Y * 0.48)
	)

	TweenService:Create(
		spawner,
		TweenInfo.new(
			BULB_GROWTH_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{Transparency = 1}
	):Play()

	local growTween = TweenService:Create(
		bulb,
		TweenInfo.new(
			BULB_GROWTH_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{
			Size = targetSize,
			CFrame = targetCFrame
		}
	)

	growTween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed or not bulb.Parent then
			return
		end

		TweenService:Create(
			bulb,
			TweenInfo.new(
				rng:NextNumber(BULB_PULSE_MIN_TIME, BULB_PULSE_MAX_TIME),
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{Size = targetSize * 1.045}
		):Play()
	end)

	growTween:Play()
	print("[INFECTION] Stage 1 seed bulb is growing.")
	return bulb
end

--------------------------------------------------
-- HANGING FLESH RIBBONS
--------------------------------------------------

local function growDangling(position, depth)
	if generatedCount >= MAX_SEGMENTS then return end

	local steps = rng:NextInteger(HANGING_MIN_LENGTH, HANGING_MAX_LENGTH)
	local faceNormal = getPlayerFacingDirection(position)
	local drift = Vector3.zero

	for i = 1, steps do
		if generatedCount >= MAX_SEGMENTS then return end

		local length = rng:NextNumber(0.9, 1.7)

		local candidateOffsets = {
			Vector3.zero,
			Vector3.new(0.35, 0, 0),
			Vector3.new(-0.35, 0, 0),
			Vector3.new(0, 0, 0.35),
			Vector3.new(0, 0, -0.35),
			Vector3.new(0.55, 0, 0.25),
			Vector3.new(-0.55, 0, -0.25)
		}

		local nextPosition = nil
		local thickness = getThickness(depth)

		for _, offset in ipairs(candidateOffsets) do
			local candidate = position
				+ Vector3.new(0, -length, 0)
				+ drift
				+ offset

			if canPlaceSegment(position, candidate, thickness) then
				nextPosition = candidate
				break
			end
		end

		if not nextPosition then return end

		generatedCount += 1

		local segment = createSegment(
			position,
			nextPosition,
			faceNormal,
			thickness
		)

		if not segment then
			generatedCount -= 1
			return
		end

		registerSegment(position, nextPosition)
		position = nextPosition

		task.wait(GROWTH_DELAY * rng:NextNumber(0.8, 1.3))
	end
end

--------------------------------------------------
-- SURFACE FOLLOWING
--------------------------------------------------

local function getNextStep(position, normal, direction, stepLength)
	local forwardOrigin = position + normal * SURFACE_OFFSET

	local forwardHit = workspace:Raycast(
		forwardOrigin,
		direction * (stepLength + 0.35),
		rayParams
	)

	if forwardHit then
		local newNormal = forwardHit.Normal

		if newNormal:Dot(normal) < 0.92 then
			local newPosition =
				forwardHit.Position + newNormal * SURFACE_OFFSET

			local newDirection =
				normal - newNormal * normal:Dot(newNormal)

			if newDirection.Magnitude > 0.05 then
				return newPosition, newNormal, newDirection.Unit
			end
		end
	end

	local targetPosition = position + direction * stepLength
	local probeOffsets = {1.0, 2.0, 3.5, 5.0}

	for _, height in ipairs(probeOffsets) do
		local sampleOrigin = targetPosition + normal * height

		local surfaceHit = workspace:Raycast(
			sampleOrigin,
			-normal * (height + 2.5),
			rayParams
		)

		if surfaceHit then
			local newNormal = surfaceHit.Normal
			local newPosition =
				surfaceHit.Position + newNormal * SURFACE_OFFSET

			local newDirection =
				direction - newNormal * direction:Dot(newNormal)

			if newDirection.Magnitude > 0.05 then
				return newPosition, newNormal, newDirection.Unit
			end
		end
	end

	return nil
end

local function findAlternativeStep(
	position,
	normal,
	direction,
	stepLength,
	thickness
)
	local angleChoices = {
		0, 15, -15, 28, -28, 42, -42, 60,
		-60, 85, -85, 120, -120, 160, -160, 180
	}

	local startIndex = rng:NextInteger(1, #angleChoices)

	for attempt = 1, #angleChoices do
		local index =
			((startIndex + attempt - 2) % #angleChoices) + 1

		local angle = math.rad(angleChoices[index])

		local candidateDirection =
			CFrame.fromAxisAngle(normal, angle)
			:VectorToWorldSpace(direction)

		candidateDirection =
			candidateDirection
		- normal * candidateDirection:Dot(normal)

		if candidateDirection.Magnitude > 0.05 then
			candidateDirection = candidateDirection.Unit

			local nextPosition, nextNormal, nextDirection = getNextStep(
				position,
				normal,
				candidateDirection,
				stepLength
			)

			if nextPosition then
				local distance = (nextPosition - position).Magnitude

				if distance >= 0.1
					and distance <= stepLength + 1.5
					and canPlaceSegment(
						position,
						nextPosition,
						thickness
					) then

					return nextPosition, nextNormal, nextDirection
				end
			end
		end
	end

	return nil
end

--------------------------------------------------
-- GROW BRANCH
--------------------------------------------------

local growBranch

growBranch = function(position, normal, direction, steps, depth)
	for i = 1, steps do
		if generatedCount >= MAX_SEGMENTS or relocationStarted then return end

		direction = direction - normal * direction:Dot(normal)

		if direction.Magnitude < 0.05 then return end
		direction = direction.Unit

		local angle = math.rad(rng:NextNumber(-28, 28))

		local curvedDirection =
			CFrame.fromAxisAngle(normal, angle)
			:VectorToWorldSpace(direction)

		direction = direction:Lerp(curvedDirection, 0.62).Unit

		local settings = ({[1]={0.65,1.05,4.6,0.035,1},[2]={0.9,1.45,3.0,0.16,2},[3]={MIN_LENGTH,MAX_LENGTH,GROWTH_DELAY,BRANCH_CHANCE,MAX_BRANCH_DEPTH},[5]={MIN_LENGTH,MAX_LENGTH,1.35,0.48,6}})[growthStage]
		if not settings then return end

		-- Each successful infection feeds the colony. Early stages become
		-- noticeably more active without skipping the timed stage progression.
		if infectionGrowthBoosts > 0 and growthStage == 1 then
			settings = {0.8, 1.2, 2.9, 0.12, 2}
		elseif infectionGrowthBoosts > 0 and growthStage == 2 then
			settings = {1.0, 1.55, 2.4, 0.22, 3}
		end
		local stepLength = rng:NextNumber(settings[1], settings[2])
		local thickness = getThickness(depth)

		local nextPosition, nextNormal, nextDirection =
			findAlternativeStep(
				position,
				normal,
				direction,
				stepLength,
				thickness
			)

		if not nextPosition then
			local isCeilingUnderside = normal.Y < -0.45
			local isRoofSurface = normal.Y > 0.35
				and position.Y > spawner.Position.Y + 4

			if (isCeilingUnderside or isRoofSurface)
				and rng:NextNumber() < HANGING_CHANCE then

				task.spawn(function()
					growDangling(position, depth + 1)
				end)
			end

			return
		end

		local segmentNormal = normal + nextNormal

		if segmentNormal.Magnitude < 0.05 then
			segmentNormal = normal
		else
			segmentNormal = segmentNormal.Unit
		end

		generatedCount += 1

		local segment = createSegment(
			position,
			nextPosition,
			segmentNormal,
			thickness
		)

		if not segment then
			generatedCount -= 1
			return
		end

		registerSegment(position, nextPosition)
		registerGroundAnchor(nextPosition, nextNormal)
		registerCeilingAnchor(nextPosition, nextNormal)

		position = nextPosition
		normal = nextNormal
		direction = nextDirection

		if depth < settings[5]
			and rng:NextNumber() < settings[4]
			and generatedCount < MAX_SEGMENTS then

			local branchAngle = math.rad(rng:NextNumber(40, 110))
			local sign = rng:NextInteger(0, 1) == 0 and -1 or 1

			local branchDirection =
				CFrame.fromAxisAngle(normal, branchAngle * sign)
				:VectorToWorldSpace(direction)

			task.spawn(function()
				growBranch(
					position,
					normal,
					branchDirection,
					rng:NextInteger(
						MIN_BRANCH_STEPS,
						MAX_BRANCH_STEPS
					),
					depth + 1
				)
			end)
		end

		task.wait(settings[3] * rng:NextNumber(0.8, 1.3))
	end
end

--------------------------------------------------
-- PLAYER GRAB AND CONTAINMENT
--------------------------------------------------

local GRAB_TRIGGER_DISTANCE = 5.2
local MAX_ACTIVE_GRABS = 2
local JUMPS_TO_ESCAPE = 4
local ENTANGLE_TIME = 5
local ARM_REACH_TIME = 0.85
local COCOON_START_DELAY = 4
local OUTER_LAYER_FORM_TIME = 1.6
local GRAB_ARM_THICKNESS = 0.30

-- Hoisting settings.
local ROOF_SEARCH_DISTANCE = 45
local ROOF_MIN_NORMAL_Y = -0.45
local HOIST_VINE_COUNT = 3
local HOIST_VINE_SEGMENTS = 10
local HOIST_VINE_FORM_TIME = 4.0
local HOIST_DURATION = 5.5
local HOIST_DISTANCE_BELOW_ROOF = 1.5
local HOIST_VINE_THICKNESS = 0.28

-- Transformation and descent settings.
local POST_HOIST_HANG_TIME = 3
local INFECTED_DESCENT_DISTANCE = 12
local INFECTED_DESCENT_TIME = 6
local DESCENT_VINE_COUNT = 3
local DESCENT_VINE_SEGMENTS = 9
local DESCENT_VINE_THICKNESS = 0.30
local COCOON_RETRACT_TIME = 1.5

--------------------------------------------------
-- CAPTURE VINE HELPERS
--------------------------------------------------

local function setCylinderBetween(part, pointA, pointB, thickness)
	local difference = pointB - pointA
	local length = math.max(difference.Magnitude, 0.05)
	local axis = difference.Unit

	local up = Vector3.new(0, 1, 0)
	up = up - axis * up:Dot(axis)

	if up.Magnitude < 0.05 then
		up = Vector3.new(1, 0, 0)
		up = up - axis * up:Dot(axis)
	end

	up = up.Unit
	local side = axis:Cross(up).Unit

	part.Size = Vector3.new(length, thickness, thickness)
	part.CFrame = CFrame.fromMatrix(
		(pointA + pointB) * 0.5,
		axis,
		up,
		side
	)
end

local function newCaptureVine(name, thickness)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.CorrodedMetal
	part.Color = Color3.fromRGB(76, 39, 30)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.Size = Vector3.new(0.05, thickness, thickness)
	part.Parent = infectionFolder

	return part
end

local function getBodyCenterPart(root)
	local character = root.Parent

	return character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("LowerTorso")
		or root
end

--------------------------------------------------
-- CONTACT ARMS
--------------------------------------------------

local function createContactArms(anchor, root)
	local arms = {}
	local targetCF = root.CFrame
	local _, bounds = root.Parent:GetBoundingBox()

	local sideOffset = math.max(bounds.X * 0.34, 0.65)
	local torsoY = math.clamp(bounds.Y * 0.08, -0.15, 0.35)

	for _, sign in ipairs({-1, 1}) do
		local arm = newCaptureVine(
			"PlayerGrabArm",
			GRAB_ARM_THICKNESS
		)

		local start = anchor.position + Vector3.new(0, 0.18, 0)

		local target = targetCF:PointToWorldSpace(
			Vector3.new(sign * sideOffset, torsoY, 0)
		)

		setCylinderBetween(
			arm,
			start,
			start:Lerp(target, 0.02),
			GRAB_ARM_THICKNESS
		)

		table.insert(arms, {
			part = arm,
			start = start,
			sign = sign,
			sideOffset = sideOffset,
			torsoY = torsoY
		})
	end

	return arms
end

local function updateContactArms(arms, root, alpha)
	if not root.Parent then return end

	for _, item in ipairs(arms) do
		local target = root.CFrame:PointToWorldSpace(
			Vector3.new(item.sign * item.sideOffset, item.torsoY, 0)
		)

		local eased = alpha * alpha * (3 - 2 * alpha)
		local endPoint = item.start:Lerp(target, eased)

		setCylinderBetween(
			item.part,
			item.start,
			endPoint,
			GRAB_ARM_THICKNESS
		)
	end
end

--------------------------------------------------
-- INITIAL BODY ENTANGLEMENT
--------------------------------------------------

local function createBodyEntanglement(root)
	local strands = {}
	local bodyCenter = getBodyCenterPart(root)

	local contactClearance = 0.20
	local radiusX = math.max(
		bodyCenter.Size.X * 0.5 + 0.085 + contactClearance,
		0.78
	)
	local radiusZ = math.max(
		bodyCenter.Size.Z * 0.5 + 0.085 + contactClearance,
		0.64
	)

	local head = root.Parent:FindFirstChild("Head")
	local topY

	if head and head:IsA("BasePart") then
		local headCenterY =
			bodyCenter.CFrame:PointToObjectSpace(head.Position).Y

		topY = headCenterY + head.Size.Y * 0.12 - 0.30
	else
		topY = bodyCenter.Size.Y * 0.48
	end

	local bottomY = -bodyCenter.Size.Y * 0.58
	local halfHeight = math.max((topY - bottomY) * 0.5, 0.9)
	local centerY = (topY + bottomY) * 0.5

	local strandCount = 4
	local segmentCount = 34

	for strandIndex = 1, strandCount do
		local parts = {}

		for segmentIndex = 1, segmentCount do
			local part = newCaptureVine(
				"WrappingEntanglementVine",
				0.17
			)
			part.Transparency = 1
			table.insert(parts, part)
		end

		table.insert(strands, {
			parts = parts,
			phase = (strandIndex - 1) * (math.pi * 2 / strandCount),
			turns = strandIndex % 2 == 0 and -1.75 or 1.75
		})
	end

	return {
		strands = strands,
		radiusX = radiusX,
		radiusZ = radiusZ,
		halfHeight = halfHeight,
		centerY = centerY,
		segmentCount = segmentCount
	}
end

local function updateBodyEntanglement(entanglement, root, alpha)
	if not root.Parent then return end

	local segmentCount = entanglement.segmentCount

	for _, strand in ipairs(entanglement.strands) do
		for index, part in ipairs(strand.parts) do
			local t0 = (index - 1) / segmentCount
			local t1 = index / segmentCount

			if t0 <= alpha then
				local function pointAt(t)
					local angle =
						strand.phase + t * math.pi * 2 * strand.turns

					local y =
						(t - 0.5) * 2 * entanglement.halfHeight

					local localPoint = Vector3.new(
						math.cos(angle) * entanglement.radiusX,
						entanglement.centerY + y,
						math.sin(angle) * entanglement.radiusZ
					)

					return getBodyCenterPart(root).CFrame
						:PointToWorldSpace(localPoint)
				end

				part.Transparency = 0

				setCylinderBetween(
					part,
					pointAt(t0),
					pointAt(math.min(t1, alpha)),
					0.17
				)
			else
				part.Transparency = 1
			end
		end
	end
end

--------------------------------------------------
-- CHARACTER AND COCOON POSITIONING
--------------------------------------------------

local function getCharacterBoundsFrame(root)
	return root.Parent:GetBoundingBox()
end

local function getCocoonFrame(root)
	return getCharacterBoundsFrame(root)
end

local function getCharacterCocoonBounds(root)
	local _, boxSize = root.Parent:GetBoundingBox()

	return Vector3.new(
		boxSize.X + 0.16,
		boxSize.Y + 0.18,
		boxSize.Z + 0.16
	)
end

--------------------------------------------------
-- CLOSED 3D COCOON
--------------------------------------------------

local function createCocoonEntanglement(root, cocoonData)
	local cocoonSize = cocoonData and cocoonData.targetSize
		or getCharacterCocoonBounds(root)

	local radiusX = cocoonSize.X * 0.5 + 0.02
	local radiusY = cocoonSize.Y * 0.5 + 0.02
	local radiusZ = cocoonSize.Z * 0.5 + 0.02

	local strands = {}
	local segmentCount = 48
	local meridianCount = 12

	for strandIndex = 1, meridianCount do
		local parts = {}

		for segmentIndex = 1, segmentCount do
			local part = newCaptureVine("CocoonVerticalLoop", 0.23)
			part.Transparency = 1
			table.insert(parts, part)
		end

		table.insert(strands, {
			parts = parts,
			angle = (strandIndex - 1)
				* (math.pi * 2 / meridianCount),
			kind = "meridian"
		})
	end

	local ringCount = 9

	for ringIndex = 1, ringCount do
		local parts = {}

		for segmentIndex = 1, segmentCount do
			local part = newCaptureVine("CocoonHorizontalRing", 0.21)
			part.Transparency = 1
			table.insert(parts, part)
		end

		local verticalLevel =
			-0.88 + ((ringIndex - 1) / (ringCount - 1)) * 1.76

		table.insert(strands, {
			parts = parts,
			level = verticalLevel,
			kind = "latitude"
		})
	end

	local diagonalCount = 4

	for strandIndex = 1, diagonalCount do
		local parts = {}

		for segmentIndex = 1, segmentCount do
			local part = newCaptureVine("CocoonDiagonalLoop", 0.19)
			part.Transparency = 1
			table.insert(parts, part)
		end

		table.insert(strands, {
			parts = parts,
			phase = (strandIndex - 1)
				* (math.pi * 2 / diagonalCount),
			direction = strandIndex % 2 == 0 and -1 or 1,
			kind = "diagonal"
		})
	end

	return {
		strands = strands,
		radiusX = radiusX,
		radiusY = radiusY,
		radiusZ = radiusZ,
		segmentCount = segmentCount
	}
end

local function updateCocoonEntanglement(layer, root, alpha)
	if not layer or not root.Parent then return end

	local centerFrame = getCocoonFrame(root)
	local count = layer.segmentCount

	for _, strand in ipairs(layer.strands) do
		for index, part in ipairs(strand.parts) do
			local t0 = (index - 1) / count
			local t1 = index / count

			if t0 <= alpha then
				local function pointAt(t)
					local angle = t * math.pi * 2

					if strand.kind == "meridian" then
						local ringRadius = math.sin(angle)

						return centerFrame:PointToWorldSpace(Vector3.new(
							math.cos(strand.angle)
								* ringRadius * layer.radiusX,
							math.cos(angle) * layer.radiusY,
							math.sin(strand.angle)
								* ringRadius * layer.radiusZ
							))

					elseif strand.kind == "latitude" then
						local horizontalRadius =
							math.sqrt(
								math.max(0, 1 - strand.level * strand.level)
							)

						return centerFrame:PointToWorldSpace(Vector3.new(
							math.cos(angle)
								* layer.radiusX * horizontalRadius,
							strand.level * layer.radiusY,
							math.sin(angle)
								* layer.radiusZ * horizontalRadius
							))

					else
						local verticalLevel =
							math.sin(angle + strand.phase)
							* 0.62
							* strand.direction

						local horizontalRadius =
							math.sqrt(
								math.max(
									0,
									1 - verticalLevel * verticalLevel
								)
							)

						return centerFrame:PointToWorldSpace(Vector3.new(
							math.cos(angle)
								* layer.radiusX * horizontalRadius,
							verticalLevel * layer.radiusY,
							math.sin(angle)
								* layer.radiusZ * horizontalRadius
							))
					end
				end

				part.Transparency = 0

				local thickness =
					strand.kind == "meridian" and 0.23
					or strand.kind == "latitude" and 0.21
					or 0.19

				setCylinderBetween(
					part,
					pointAt(t0),
					pointAt(math.min(t1, alpha)),
					thickness
				)
			else
				part.Transparency = 1
			end
		end
	end
end

local function destroyVineLayer(layer)
	if not layer then return end

	for _, strand in ipairs(layer.strands) do
		for _, part in ipairs(strand.parts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end
end

--------------------------------------------------
-- OUTER VINE LAYER
--------------------------------------------------

local function createOuterVineLayer(root)
	local cocoonSize = getCharacterCocoonBounds(root)

	local radiusX = cocoonSize.X * 0.5 + 0.04
	local radiusY = cocoonSize.Y * 0.5 + 0.04
	local radiusZ = cocoonSize.Z * 0.5 + 0.04

	local strands = {}
	local strandCount = 5
	local segmentCount = 28

	for strandIndex = 1, strandCount do
		local parts = {}

		for segmentIndex = 1, segmentCount do
			local part = newCaptureVine("OuterContainmentVine", 0.20)
			part.Transparency = 1
			table.insert(parts, part)
		end

		table.insert(strands, {
			parts = parts,
			phase = (strandIndex - 1) * (math.pi * 2 / strandCount),
			tilt = (strandIndex - 1) * 0.24
		})
	end

	return {
		strands = strands,
		radiusX = radiusX,
		radiusY = radiusY,
		radiusZ = radiusZ,
		segmentCount = segmentCount
	}
end

local function updateOuterVineLayer(layer, root, alpha)
	if not layer or not root.Parent then return end

	local count = layer.segmentCount
	local centerFrame = getCocoonFrame(root)

	for _, strand in ipairs(layer.strands) do
		for index, part in ipairs(strand.parts) do
			local t0 = (index - 1) / count
			local t1 = index / count

			if t0 <= alpha then
				local function pointAt(t)
					local angle = strand.phase + t * math.pi * 2
					local vertical = (t - 0.5) * 2

					local x = math.cos(angle) * layer.radiusX
					local z = math.sin(angle) * layer.radiusZ
					local y = vertical * layer.radiusY

					local rotatedX =
						x * math.cos(strand.tilt)
					- y * math.sin(strand.tilt)

					local rotatedY =
						x * math.sin(strand.tilt)
						+ y * math.cos(strand.tilt)

					return centerFrame:PointToWorldSpace(
						Vector3.new(rotatedX, rotatedY, z)
					)
				end

				part.Transparency = 0

				setCylinderBetween(
					part,
					pointAt(t0),
					pointAt(math.min(t1, alpha)),
					0.20
				)
			else
				part.Transparency = 1
			end
		end
	end
end

--------------------------------------------------
-- ROOF DETECTION FOR HOISTING
--------------------------------------------------

local function findHoistRoof(root, cocoonData)
	local centerFrame = getCocoonFrame(root)
	local cocoonSize = cocoonData.targetSize

	local origin = centerFrame.Position
		+ Vector3.new(0, cocoonSize.Y * 0.5 + 0.5, 0)

	local result = workspace:Raycast(
		origin,
		Vector3.new(0, ROOF_SEARCH_DISTANCE, 0),
		rayParams
	)

	if not result then
		return nil
	end

	if result.Normal.Y > ROOF_MIN_NORMAL_Y then
		return nil
	end

	if not result.Instance:IsA("BasePart")
		or not result.Instance.CanCollide then
		return nil
	end

	return result
end

--------------------------------------------------
-- CEILING HOIST VINES
--------------------------------------------------

local function createHoistVines(root, cocoonData, roofResult)
	local vines = {}
	local roofPoint = roofResult.Position

	local attachmentOffsets = {
		Vector3.new(-1.15, 0, -0.8),
		Vector3.new(1.15, 0, -0.8),
		Vector3.new(0, 0, 1.2)
	}

	for vineIndex = 1, HOIST_VINE_COUNT do
		local offset = attachmentOffsets[vineIndex]

		local roofStart = Vector3.new(
			roofPoint.X + offset.X,
			roofPoint.Y - 0.12,
			roofPoint.Z + offset.Z
		)

		local targetLocal = Vector3.new(
			offset.X,
			cocoonData.targetSize.Y * 0.34,
			offset.Z
		)

		local parts = {}

		for segmentIndex = 1, HOIST_VINE_SEGMENTS do
			local part = newCaptureVine(
				"CeilingHoistingVine",
				HOIST_VINE_THICKNESS
			)

			part.Transparency = 1
			table.insert(parts, part)
		end

		table.insert(vines, {
			parts = parts,
			roofStart = roofStart,
			targetLocal = targetLocal
		})
	end

	return vines
end

local function updateHoistVines(vines, root, alpha)
	if not root.Parent then return end

	local centerFrame = getCocoonFrame(root)

	for _, vine in ipairs(vines) do
		local startPoint = vine.roofStart
		local endPoint = centerFrame:PointToWorldSpace(vine.targetLocal)

		for index, part in ipairs(vine.parts) do
			local t0 = (index - 1) / HOIST_VINE_SEGMENTS
			local t1 = index / HOIST_VINE_SEGMENTS

			if t0 < alpha then
				local visibleEnd = math.min(t1, alpha)

				local pointA = startPoint:Lerp(endPoint, t0)
				local pointB = startPoint:Lerp(endPoint, visibleEnd)

				part.Transparency = 0

				setCylinderBetween(
					part,
					pointA,
					pointB,
					HOIST_VINE_THICKNESS
				)
			else
				part.Transparency = 1
			end
		end
	end
end

local function destroyHoistVines(vines)
	if not vines then return end

	for _, vine in ipairs(vines) do
		for _, part in ipairs(vine.parts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end
end

--------------------------------------------------
-- COCOON RETRACTION
--------------------------------------------------

local function retractCocoonLayer(layer)
	if not layer then return end

	local parts = {}

	for _, strand in ipairs(layer.strands) do
		for _, part in ipairs(strand.parts) do
			if part and part.Parent then
				table.insert(parts, part)
			end
		end
	end

	local startTime = os.clock()

	while os.clock() - startTime < COCOON_RETRACT_TIME do
		local alpha = math.clamp(
			(os.clock() - startTime) / COCOON_RETRACT_TIME,
			0,
			1
		)

		local eased = alpha * alpha * (3 - 2 * alpha)

		for _, part in ipairs(parts) do
			if part.Parent then
				part.Transparency = eased
				part.Size = Vector3.new(
					math.max(part.Size.X * (1 - eased), 0.02),
					math.max(0.02, 0.21 * (1 - eased)),
					math.max(0.02, 0.21 * (1 - eased))
				)
			end
		end

		task.wait(0.035)
	end

	destroyVineLayer(layer)
end

--------------------------------------------------
-- CEILING HOIST SEQUENCE
--------------------------------------------------

local function performCeilingHoist(
	root,
	cocoonData,
	roofResult,
	finalEntanglement,
	outerLayer
)
	if not root.Parent then return false end

	print("[INFECTION] Suitable roof found. Growing ceiling hoisting vines.")

	local vines = createHoistVines(root, cocoonData, roofResult)

	local formationStart = os.clock()

	while os.clock() - formationStart < HOIST_VINE_FORM_TIME do
		if not root.Parent then
			destroyHoistVines(vines)
			return false
		end

		local alpha = math.clamp(
			(os.clock() - formationStart) / HOIST_VINE_FORM_TIME,
			0,
			1
		)

		updateCocoonEntanglement(finalEntanglement, root, 1)
		updateOuterVineLayer(outerLayer, root, 1)
		updateHoistVines(vines, root, alpha)

		task.wait(0.035)
	end

	updateCocoonEntanglement(finalEntanglement, root, 1)
	updateOuterVineLayer(outerLayer, root, 1)
	updateHoistVines(vines, root, 1)

	print("[INFECTION] Ceiling vines attached. Beginning cocoon hoist.")

	local hoistStartCFrame = root.CFrame
	-- The root is near the cocoon's center, so leave room for the cocoon's
	-- entire upper half plus a small visible gap beneath the ceiling.
	local cocoonTopClearance =
		(cocoonData.targetSize.Y * 0.5) + HOIST_DISTANCE_BELOW_ROOF
	local availableHeight =
		roofResult.Position.Y - root.Position.Y
	- cocoonTopClearance

	local liftDistance = math.max(0, availableHeight)

	if liftDistance < 1 then
		print("[INFECTION] Roof is too close for a safe hoist.")
		destroyHoistVines(vines)
		return false
	end

	local liftStart = os.clock()

	while os.clock() - liftStart < HOIST_DURATION do
		if not root.Parent then
			destroyHoistVines(vines)
			return false
		end

		local alpha = math.clamp(
			(os.clock() - liftStart) / HOIST_DURATION,
			0,
			1
		)

		local easedAlpha = alpha * alpha * (3 - 2 * alpha)
		local rise = liftDistance * easedAlpha

		root.CFrame =
			hoistStartCFrame + Vector3.new(0, rise, 0)

		updateCocoonEntanglement(finalEntanglement, root, 1)
		updateOuterVineLayer(outerLayer, root, 1)
		updateHoistVines(vines, root, 1)

		task.wait(0.035)
	end

	root.CFrame =
		hoistStartCFrame + Vector3.new(0, liftDistance, 0)

	updateCocoonEntanglement(finalEntanglement, root, 1)
	updateOuterVineLayer(outerLayer, root, 1)
	updateHoistVines(vines, root, 1)

	print("[INFECTION] Cocoon hoist complete.")

	return true, vines
end

--------------------------------------------------
-- HIDE ORIGINAL CHARACTER
--------------------------------------------------

local function hideOriginalCharacter(character)
	local savedVisuals = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			savedVisuals[descendant] = {
				Transparency = descendant.Transparency,
				CastShadow = descendant.CastShadow
			}
			descendant.Transparency = 1
			descendant.CastShadow = false

		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			savedVisuals[descendant] = {
				Transparency = descendant.Transparency
			}
			descendant.Transparency = 1

		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui") then
			savedVisuals[descendant] = {
				Enabled = descendant.Enabled
			}
			descendant.Enabled = false
		end
	end

	return savedVisuals
end

local function restoreOriginalCharacter(character, humanoid, root, savedVisuals, restoreState)
	if savedVisuals then
		for instance, properties in pairs(savedVisuals) do
			if instance and instance.Parent then
				for property, value in pairs(properties) do
					pcall(function()
						instance[property] = value
					end)
				end
			end
		end
	end

	if humanoid and humanoid.Parent and restoreState then
		humanoid.WalkSpeed = restoreState.WalkSpeed
		humanoid.AutoRotate = restoreState.AutoRotate
		humanoid.UseJumpPower = restoreState.UseJumpPower
		humanoid.JumpPower = restoreState.JumpPower
		humanoid.JumpHeight = restoreState.JumpHeight
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Jumping,
			restoreState.JumpingEnabled
		)
	end

	if root and root.Parent and restoreState then
		root.Anchored = restoreState.RootAnchored
	end

	local animateScript = character and character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = false
	end
end

local function prepareInfectedCharacter()
	local template = ServerStorage:FindFirstChild("InfectedCharacter")
	if not template or not template:IsA("Model") then
		warn("[INFECTION] Transformation cancelled: ServerStorage.InfectedCharacter model was not found.")
		return nil
	end

	local clone = template:Clone()
	local infectedHumanoid = clone:FindFirstChildOfClass("Humanoid")
	local infectedRoot = clone:FindFirstChild("HumanoidRootPart")

	if not infectedHumanoid or not infectedRoot or not infectedRoot:IsA("BasePart") then
		warn("[INFECTION] Transformation cancelled: InfectedCharacter needs a Humanoid and a BasePart named HumanoidRootPart.")
		clone:Destroy()
		return nil
	end

	clone.PrimaryPart = infectedRoot
	return clone
end

local function replacePlayerCharacter(player, oldCharacter, infectedCharacter, targetCFrame, keepAnchored)
	if not player or not player.Parent then
		return false
	end

	local infectedRoot = infectedCharacter:FindFirstChild("HumanoidRootPart")
	local infectedHumanoid = infectedCharacter:FindFirstChildOfClass("Humanoid")

	if not infectedRoot or not infectedHumanoid then
		return false
	end

	infectedCharacter.Name = player.Name
	infectedCharacter:PivotTo(targetCFrame)
	infectedCharacter.Parent = workspace

	-- Keep the replacement physically fixed inside the cocoon until its release.
	for _, descendant in ipairs(infectedCharacter:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = keepAnchored == true
		end
	end

	local assigned, assignmentError = pcall(function()
		player.Character = infectedCharacter
	end)

	if not assigned or player.Character ~= infectedCharacter then
		warn("[INFECTION] Character assignment failed: " .. tostring(assignmentError))
		infectedCharacter:Destroy()
		return false
	end

	if not keepAnchored then
		pcall(function()
			infectedRoot:SetNetworkOwner(player)
		end)
	end

	if oldCharacter and oldCharacter.Parent then
		oldCharacter:Destroy()
	end

	return true
end

--------------------------------------------------
-- INVISIBLE INFECTED PLACEHOLDER
--------------------------------------------------

local function createInvisiblePlaceholder(root)
	local placeholder = Instance.new("Part")
	placeholder.Name = "InvisibleInfectedPlaceholder"
	placeholder.Size = Vector3.new(2, 4, 2)
	placeholder.Transparency = 1
	placeholder.Anchored = true
	placeholder.CanCollide = false
	placeholder.CanTouch = false
	placeholder.CanQuery = false
	placeholder.CastShadow = false
	placeholder.CFrame = root.CFrame
	placeholder.Parent = infectionFolder

	return placeholder
end

--------------------------------------------------
-- DESCENDING VINES
--------------------------------------------------

local function createDescentVines()
	local vines = {}

	-- These points attach around the upper body of the visible infected rig.
	local offsets = {
		Vector3.new(-1.1, 1.25, -0.8),
		Vector3.new(1.1, 1.25, -0.8),
		Vector3.new(0, 1.15, 1.2)
	}

	for vineIndex = 1, DESCENT_VINE_COUNT do
		local parts = {}

		for segmentIndex = 1, DESCENT_VINE_SEGMENTS do
			local part = newCaptureVine(
				"InfectedDescentVine",
				DESCENT_VINE_THICKNESS
			)

			part.Transparency = 0
			table.insert(parts, part)
		end

		table.insert(vines, {
			parts = parts,
			offset = offsets[vineIndex]
		})
	end

	return vines
end

local function updateDescentVines(vines, infectedRoot, anchorPosition)
	if not infectedRoot or not infectedRoot.Parent then return end

	for _, vine in ipairs(vines) do
		-- Start at the ceiling and finish directly on the moving parasite.
		local startPoint = anchorPosition + Vector3.new(
			vine.offset.X,
			-0.12,
			vine.offset.Z
		)
		local endPoint = infectedRoot.CFrame:PointToWorldSpace(vine.offset)

		for index, part in ipairs(vine.parts) do
			local t0 = (index - 1) / DESCENT_VINE_SEGMENTS
			local t1 = index / DESCENT_VINE_SEGMENTS
			local pointA = startPoint:Lerp(endPoint, t0)
			local pointB = startPoint:Lerp(endPoint, t1)

			part.Transparency = 0
			setCylinderBetween(
				part,
				pointA,
				pointB,
				DESCENT_VINE_THICKNESS
			)
		end
	end
end

local function destroyDescentVines(vines)
	if not vines then return end

	for _, vine in ipairs(vines) do
		for _, part in ipairs(vine.parts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end
end

--------------------------------------------------
-- INFECTED DESCENT SEQUENCE
--------------------------------------------------

local function performInfectedDescent(
	player,
	character,
	root,
	humanoid,
	finalEntanglement,
	outerLayer,
	hoistVines,
	roofResult,
	restoreState
)
	print("[INFECTION] Cocoon holding captured player.")

	-- Prepare the replacement before changing anything about the original avatar.
	local infectedCharacter = prepareInfectedCharacter()
	if not infectedCharacter then
		restoreOriginalCharacter(character, humanoid, root, nil, restoreState)
		return false
	end

	local savedVisuals = hideOriginalCharacter(character)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Swap characters WHILE the cocoon is still closed and suspended.
	-- The infected rig remains anchored at the roof position during the reveal.
	local transformed = replacePlayerCharacter(
		player,
		character,
		infectedCharacter,
		root.CFrame,
		true
	)

	if not transformed then
		restoreOriginalCharacter(character, humanoid, root, savedVisuals, restoreState)
		return false
	end

	-- Ground stalks must never capture this player again after transformation.
	infectedPlayers[player] = true

	local infectedRoot = infectedCharacter:FindFirstChild("HumanoidRootPart")
	local infectedHumanoid = infectedCharacter:FindFirstChildOfClass("Humanoid")
	if not infectedRoot or not infectedHumanoid then
		warn("[INFECTION] Replacement rig lost its root or Humanoid after assignment.")
		return false
	end

	infectedHumanoid.WalkSpeed = 0
	infectedHumanoid.JumpPower = 0
	infectedHumanoid.JumpHeight = 0
	infectedHumanoid.AutoRotate = false

	print("[INFECTION] Player transformed inside the suspended cocoon.")

	-- Keep the ceiling/grabbing vines attached while the new parasite is revealed.
	local hangStart = os.clock()
	while os.clock() - hangStart < POST_HOIST_HANG_TIME do
		if not infectedCharacter.Parent or not infectedRoot.Parent then
			return false
		end

		updateCocoonEntanglement(finalEntanglement, infectedRoot, 1)
		updateOuterVineLayer(outerLayer, infectedRoot, 1)
		if hoistVines then
			updateHoistVines(hoistVines, infectedRoot, 1)
		end
		task.wait(0.05)
	end

	if not infectedCharacter.Parent or not infectedRoot.Parent then
		return false
	end

	print("[INFECTION] Cocoon opening around the infected character.")

	-- Retract the cocoon while the support vines are STILL holding it at the roof.
	retractCocoonLayer(outerLayer)
	retractCocoonLayer(finalEntanglement)

	-- One final update keeps the support vines aligned with the new character.
	if hoistVines and infectedRoot.Parent then
		updateHoistVines(hoistVines, infectedRoot, 1)
	end

	-- Only release the ceiling support once the cocoon has opened.
	destroyHoistVines(hoistVines)
	print("[INFECTION] Ceiling vines released. Lowering the visible infected character.")

	-- Only perform the hanging descent when a real ceiling was found and
	-- the cocoon was actually hoisted. Ground-mounted outdoor cocoons must
	-- release the infected character where it was captured, not lower it
	-- through the floor.
	if roofResult then
		local descentVines = createDescentVines()
		local descentAnchor = roofResult.Position

		local startPivot = infectedCharacter:GetPivot()
		local descentStart = os.clock()

		while os.clock() - descentStart < INFECTED_DESCENT_TIME do
			if not infectedCharacter.Parent or not infectedRoot.Parent then
				destroyDescentVines(descentVines)
				return false
			end

			local alpha = math.clamp(
				(os.clock() - descentStart) / INFECTED_DESCENT_TIME,
				0,
				1
			)
			local easedAlpha = alpha * alpha * (3 - 2 * alpha)
			local offset = Vector3.new(
				0,
				-INFECTED_DESCENT_DISTANCE * easedAlpha,
				0
			)

			infectedCharacter:PivotTo(startPivot + offset)
			updateDescentVines(descentVines, infectedRoot, descentAnchor)
			task.wait(0.035)
		end

		infectedCharacter:PivotTo(
			startPivot - Vector3.new(0, INFECTED_DESCENT_DISTANCE, 0)
		)
		updateDescentVines(descentVines, infectedRoot, descentAnchor)
		destroyDescentVines(descentVines)
	else
		print("[INFECTION] No ceiling hoist was used. Releasing infected character at ground level.")
	end

	-- The parasite is now released and can move normally.
	for _, descendant in ipairs(infectedCharacter:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	infectedHumanoid.WalkSpeed = restoreState.WalkSpeed
	infectedHumanoid.AutoRotate = restoreState.AutoRotate
	infectedHumanoid.UseJumpPower = restoreState.UseJumpPower
	infectedHumanoid.JumpPower = restoreState.JumpPower
	infectedHumanoid.JumpHeight = restoreState.JumpHeight
	infectedHumanoid:SetStateEnabled(
		Enum.HumanoidStateType.Jumping,
		restoreState.JumpingEnabled
	)

	pcall(function()
		infectedRoot:SetNetworkOwner(player)
	end)

	print("[INFECTION] Infected character released successfully.")
	return true
end

--------------------------------------------------
-- PLAYER CAPTURE SEQUENCE
--------------------------------------------------

local function rewardSuccessfulInfection(anchor)
	if growthStage < 1 or growthStage > 3 then return end

	infectionGrowthBoosts += 1
	print("[INFECTION] Successful infection! The colony is feeding and expanding.")

	-- A small growth burst spreads outward from the capture site. The normal
	-- stage timer still controls when the parasite evolves to its next stage.
	local origin = anchor.position
	local normal = anchor.normal or Vector3.new(0, 1, 0)
	local branchCount = math.min(3 + infectionGrowthBoosts, 6)

	for index = 1, branchCount do
		local angle = (index - 1) * (math.pi * 2 / branchCount)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		direction = direction - normal * direction:Dot(normal)
		if direction.Magnitude > 0.05 then
			task.spawn(growBranch, origin, normal, direction.Unit, rng:NextInteger(9, 15), 0)
		end
	end

	-- The central bulb also swells slightly with each successful feeding.
	if infectionBulb and infectionBulb.Parent then
		local stageBaseSize = ({[1]=1.25, [2]=2.2, [3]=3.8})[growthStage] or infectionBulb.Size.X
		local addedSize = math.min(infectionGrowthBoosts * 0.18, 0.9)
		local targetSize = stageBaseSize + addedSize
		TweenService:Create(
			infectionBulb,
			TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Size = Vector3.new(targetSize, targetSize, targetSize)}
		):Play()
	end
end

attemptPlayerGrab = function(anchor, player, character, humanoid, root)
	if infectedPlayers[player] then return end
	if activeGrabCount >= MAX_ACTIVE_GRABS or anchor.used then return end
	if not character.Parent or humanoid.Health <= 0 then return end

	anchor.used = true
	activeGrabCount += 1

	local oldWalkSpeed = humanoid.WalkSpeed
	local oldAutoRotate = humanoid.AutoRotate
	local oldJumpPower = humanoid.JumpPower
	local oldJumpHeight = humanoid.JumpHeight
	local oldUseJumpPower = humanoid.UseJumpPower
	local oldRootAnchored = root.Anchored

	local wasJumpingEnabled =
		humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)

	local capturePosition = root.Position
	local arms = createContactArms(anchor, root)
	local entanglement = createBodyEntanglement(root)

	local jumpCount = 0
	local escaped = false

	local jumpConnection = humanoid.StateChanged:Connect(
		function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping then
				jumpCount += 1

				if jumpCount >= JUMPS_TO_ESCAPE then
					escaped = true
				end
			end
		end
	)

	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	local function holdPlayer(allowJump)
		if not root.Parent then return end

		local offset = capturePosition - root.Position
		local verticalVelocity = root.AssemblyLinearVelocity.Y

		if allowJump then
			verticalVelocity = math.min(verticalVelocity, 0)
		else
			verticalVelocity = 0
		end

		root.AssemblyLinearVelocity = Vector3.new(
			math.clamp(offset.X * 10, -20, 20),
			verticalVelocity,
			math.clamp(offset.Z * 10, -20, 20)
		)

		root.AssemblyAngularVelocity = Vector3.zero
	end

	local startTime = os.clock()
	local released = false

	while not released
		and os.clock() - startTime < ENTANGLE_TIME
		and humanoid.Health > 0
		and character.Parent do

		local elapsed = os.clock() - startTime
		local reachAlpha = math.clamp(elapsed / ARM_REACH_TIME, 0, 1)

		updateContactArms(arms, root, reachAlpha)

		updateBodyEntanglement(
			entanglement,
			root,
			math.clamp(elapsed / ENTANGLE_TIME, 0, 1)
		)

		holdPlayer(true)

		if escaped then
			released = true
		end

		task.wait(0.035)
	end

	local outerLayer = nil
	local finalEntanglement = nil
	local hoistVines = nil
	local sealed = false
	local roofResult = nil

	if not escaped and humanoid.Health > 0 and character.Parent then
		if jumpConnection then
			jumpConnection:Disconnect()
			jumpConnection = nil
		end

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Jumping,
			false
		)

		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.Jump = false

		-- Freeze the player after the escape phase.
		-- This prevents falling and unwanted movement animations.
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end

		local animateScript = character:FindFirstChild("Animate")

		if animateScript then
			animateScript.Disabled = true
		end

		print("[INFECTION] Player frozen. Preparing direct cocoon formation.")

		local cocoonStart = os.clock()

		while os.clock() - cocoonStart < COCOON_START_DELAY
			and humanoid.Health > 0
			and character.Parent do

			holdPlayer(false)
			task.wait(0.035)
		end

		if humanoid.Health > 0 and character.Parent then
			local cocoonData = {
				targetSize = getCharacterCocoonBounds(root)
			}

			finalEntanglement =
				createCocoonEntanglement(root, cocoonData)

			outerLayer = createOuterVineLayer(root)

			sealed = true

			print("[INFECTION] Complete closed cocoon forming.")

			local layerStart = os.clock()

			while os.clock() - layerStart < OUTER_LAYER_FORM_TIME
				and humanoid.Health > 0
				and character.Parent do

				local alpha = math.clamp(
					(os.clock() - layerStart) / OUTER_LAYER_FORM_TIME,
					0,
					1
				)

				updateCocoonEntanglement(
					finalEntanglement,
					root,
					alpha
				)

				updateOuterVineLayer(outerLayer, root, alpha)

				task.wait(0.035)
			end

			updateCocoonEntanglement(finalEntanglement, root, 1)
			updateOuterVineLayer(outerLayer, root, 1)

			-- Remove the temporary body-wrapping vines.
			for _, strand in ipairs(entanglement.strands) do
				for _, part in ipairs(strand.parts) do
					if part and part.Parent then
						part:Destroy()
					end
				end
			end

			table.clear(entanglement.strands)

			-- Remove the original ground contact arms.
			for _, arm in ipairs(arms) do
				if arm.part and arm.part.Parent then
					arm.part:Destroy()
				end
			end

			table.clear(arms)

			print("[INFECTION] Ground vines released the sealed cocoon.")

			-- Search for a suitable roof.
			roofResult = findHoistRoof(root, cocoonData)

			if roofResult then
				local hoisted, formedVines =
					performCeilingHoist(
						root,
						cocoonData,
						roofResult,
						finalEntanglement,
						outerLayer
					)

				if hoisted then
					hoistVines = formedVines
				end
			else
				print("[INFECTION] No suitable roof found. Cocoon remains ground-mounted.")
			end

			-- Hold, retract, hide, and lower the placeholder.
			local restoreState = {
				WalkSpeed = oldWalkSpeed,
				AutoRotate = oldAutoRotate,
				JumpPower = oldJumpPower,
				JumpHeight = oldJumpHeight,
				UseJumpPower = oldUseJumpPower,
				RootAnchored = oldRootAnchored,
				JumpingEnabled = wasJumpingEnabled
			}

			local infectionSucceeded = performInfectedDescent(
				player,
				character,
				root,
				humanoid,
				finalEntanglement,
				outerLayer,
				hoistVines,
				roofResult,
				restoreState
			)

			if infectionSucceeded then
				rewardSuccessfulInfection(anchor)
			end
		end
	end

	if jumpConnection then
		jumpConnection:Disconnect()
	end

	-- Only restore movement if the player escaped or capture
	-- was interrupted BEFORE the cocoon was sealed.
	if humanoid.Parent and not sealed then
		humanoid.WalkSpeed = oldWalkSpeed
		humanoid.AutoRotate = oldAutoRotate
		humanoid.UseJumpPower = oldUseJumpPower
		humanoid.JumpPower = oldJumpPower
		humanoid.JumpHeight = oldJumpHeight

		root.Anchored = oldRootAnchored

		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Jumping,
			wasJumpingEnabled
		)

		local animateScript = character:FindFirstChild("Animate")

		if animateScript then
			animateScript.Disabled = false
		end
	end

	for _, arm in ipairs(arms) do
		if arm.part and arm.part.Parent then
			arm.part:Destroy()
		end
	end

	for _, strand in ipairs(entanglement.strands) do
		for _, part in ipairs(strand.parts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end

	-- These layers may already have been destroyed during retraction.
	if outerLayer then
		destroyVineLayer(outerLayer)
	end

	if finalEntanglement then
		destroyVineLayer(finalEntanglement)
	end

	if hoistVines then
		destroyHoistVines(hoistVines)
	end

	activeGrabCount = math.max(0, activeGrabCount - 1)

	if escaped then
		print("[INFECTION] Player escaped during the entanglement phase.")
	elseif sealed then
		print("[INFECTION] Capture sequence complete.")
	else
		print("[INFECTION] Capture sequence ended or was interrupted.")
	end
end

--------------------------------------------------
-- INFECTION STAGES AND RELOCATION
--------------------------------------------------

local function setBulbSize(size, duration)
	if infectionBulb and infectionBulb.Parent then
		TweenService:Create(infectionBulb, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = Vector3.new(size, size, size)}):Play()
	end
end

local function retractStageThreeTendrils()
	print("[INFECTION] Stage 4: retracting the old tendril network.")
	local old = growthSegments
	growthSegments = {}
	for _, part in ipairs(old) do
		if part and part.Parent then
			local duration = rng:NextNumber(1.5, 2.8)
			TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = Vector3.new(0.03, 0.02, 0.02), Transparency = 1}):Play()
			task.delay(duration + 0.1, function()
				if part and part.Parent then part:Destroy() end
			end)
		end
	end
	generatedCount = math.max(0, generatedCount - #old)
	table.clear(occupiedPositions)
	table.clear(groundAnchors)
	table.clear(ceilingAnchors)
	for _, stalk in ipairs(groundStalks) do
		if stalk.model and stalk.model.Parent then stalk.model:Destroy() end
	end
	table.clear(groundStalks)
	for _, vine in ipairs(ceilingVines) do
		if vine.model and vine.model.Parent then vine.model:Destroy() end
	end
	table.clear(ceilingVines)
end

local function makeWalkerLeg()
	local part = Instance.new("Part")
	part.Name = "Stage4WalkingTentacle"
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.CorrodedMetal
	part.Color = Color3.fromRGB(72, 37, 29)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = infectionFolder
	return part
end

local function crawlToNestTarget()
	local target = workspace:FindFirstChild("InfectionNestTarget", true)
	local houseZone = workspace:FindFirstChild("InfectionHouseZone", true)

	if not target or not target:IsA("BasePart") then
		warn("[INFECTION] Missing BasePart named InfectionNestTarget.")
		return false
	end
	if not houseZone or not houseZone:IsA("BasePart") then
		warn("[INFECTION] Missing BasePart named InfectionHouseZone. Add an invisible zone covering the house interior.")
		return false
	end

	-- The nest marker must be inside the volume that identifies the house.
	local markerLocal = houseZone.CFrame:PointToObjectSpace(target.Position)
	local halfSize = houseZone.Size * 0.5
	if math.abs(markerLocal.X) > halfSize.X
		or math.abs(markerLocal.Y) > halfSize.Y
		or math.abs(markerLocal.Z) > halfSize.Z then
		warn("[INFECTION] InfectionNestTarget is outside InfectionHouseZone. Move the marker inside the zone.")
		return false
	end

	-- Ignore the two invisible helper parts when finding the actual floor.
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude
	floorParams.FilterDescendantsInstances = {spawner, infectionFolder, target, houseZone}
	floorParams.IgnoreWater = true

	local function findFloor(position)
		return workspace:Raycast(
			position + Vector3.new(0, 8, 0),
			Vector3.new(0, -60, 0),
			floorParams
		)
	end

	local startFloor = findFloor(infectionBulb.Position)
	local targetFloor = findFloor(target.Position)
	if not startFloor or not targetFloor then
		warn("[INFECTION] Could not find the floor beneath the bulb or nest marker.")
		return false
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 4,
		AgentCanJump = true,
		WaypointSpacing = 3
	})
	local pathStart = startFloor.Position + Vector3.new(0, 2, 0)
	local pathFinish = targetFloor.Position + Vector3.new(0, 2, 0)
	local ok = pcall(function()
		path:ComputeAsync(pathStart, pathFinish)
	end)
	local routePoints = {}
	local useWindowClimb = false
	if ok and path.Status == Enum.PathStatus.Success then
		for _, waypoint in ipairs(path:GetWaypoints()) do
			local waypointFloor = findFloor(waypoint.Position)
			local floorPosition = waypointFloor and waypointFloor.Position or waypoint.Position
			table.insert(routePoints, {
				position = floorPosition + Vector3.new(0, 2, 0),
				mode = "ground"
			})
		end
	else
		-- If the navmesh cannot find a doorway route, look for a clear
		-- horizontal band above the solid wall: this is the window opening.
		local horizontal = Vector3.new(
			targetFloor.Position.X - startFloor.Position.X,
			0,
			targetFloor.Position.Z - startFloor.Position.Z
		)
		if horizontal.Magnitude < 0.1 then
			warn("[INFECTION] No floor route or usable window direction was found.")
			return false
		end
		local direction = horizontal.Unit
		local wallOrigin = startFloor.Position + Vector3.new(0, 2, 0)
		local wallHit = workspace:Raycast(wallOrigin, direction * horizontal.Magnitude, floorParams)
		local clearHeight = nil
		if wallHit then
			for height = 2.5, 8.5, 0.5 do
				local rayOrigin = startFloor.Position + Vector3.new(0, height, 0)
				local rayTarget = targetFloor.Position + Vector3.new(0, height, 0)
				local obstruction = workspace:Raycast(rayOrigin, rayTarget - rayOrigin, floorParams)
				if not obstruction then
					clearHeight = height
					break
				end
			end
		end
		if not wallHit or not clearHeight then
			warn("[INFECTION] No doorway path or clear window-height opening found. Check the window is open and unobstructed.")
			return false
		end

		local outsideWall = wallHit.Position - direction * 1.4
		local insideWall = wallHit.Position + direction * 1.4
		local climbY = startFloor.Position.Y + clearHeight
		table.insert(routePoints, {position = Vector3.new(outsideWall.X, climbY, outsideWall.Z), mode = "climb"})
		table.insert(routePoints, {position = Vector3.new(insideWall.X, climbY, insideWall.Z), mode = "window"})
		table.insert(routePoints, {position = targetFloor.Position + Vector3.new(0, 2, 0), mode = "descend"})
		useWindowClimb = true
		print("[INFECTION] Stage 4: navmesh route unavailable; climbing the wall and passing through a clear window-height opening.")
	end

	-- Eight separate walking/climbing tentacles surround the bulb.
	local legs = {}
	for i = 1, 8 do
		legs[i] = makeWalkerLeg()
	end

	local bulbRadius = math.max(infectionBulb.Size.Y * 0.5, 0.65)
	local current = startFloor.Position + Vector3.new(0, bulbRadius + 0.12, 0)
	infectionBulb.Position = current
	if not useWindowClimb then
		print("[INFECTION] Stage 4: following the floor path into InfectionHouseZone with eight walking tentacles.")
	end

	for _, routePoint in ipairs(routePoints) do
		local destination = routePoint.position
		local mode = routePoint.mode
		local segmentStart = current
		local distance = (destination - segmentStart).Magnitude
		local steps = math.max(1, math.ceil(distance / 0.22))

		for step = 1, steps do
			if not infectionBulb or not infectionBulb.Parent then
				for _, leg in ipairs(legs) do if leg and leg.Parent then leg:Destroy() end end
				return false
			end

			local alpha = step / steps
			local nextPosition = segmentStart:Lerp(destination, alpha)
			local facing = destination - segmentStart
			if facing.Magnitude < 0.05 then facing = Vector3.new(0, 0, 1) end
			local bob = math.sin(os.clock() * 7) * 0.07
			infectionBulb.CFrame = CFrame.lookAt(
				nextPosition + Vector3.new(0, bob, 0),
				nextPosition + facing.Unit
			)

			for legIndex, leg in ipairs(legs) do
				local angle = (legIndex - 1) * math.pi * 0.25
				local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local hip = infectionBulb.Position + radial * 1.0 + Vector3.new(0, -0.2, 0)
				local stride = math.sin(os.clock() * 8 + legIndex * math.pi * 0.5) * 0.42
				local foot
				if mode == "climb" or mode == "window" then
					-- During the wall section, the limbs reach around the bulb
					-- and brace against the vertical surface instead of the floor.
					local verticalReach = ((legIndex % 2 == 0) and 1 or -1) * 0.65
					foot = hip + Vector3.new(
						-radial.X * (1.0 + stride),
						verticalReach + stride * 0.25,
						-radial.Z * (1.0 + stride)
					)
				else
					foot = hip + Vector3.new(
						radial.X * (1.15 + stride),
						-bulbRadius + 0.05 + math.max(0, stride) * 0.3,
						radial.Z * (1.15 + stride)
					)
				end
				setCylinderBetween(leg, hip, foot, 0.38)
			end
			task.wait(0.06)
		end
		current = destination
	end

	for _, leg in ipairs(legs) do
		if leg and leg.Parent then leg:Destroy() end
	end

	local finalFloor = findFloor(target.Position)
	if finalFloor then
		local settledPosition = finalFloor.Position + Vector3.new(0, bulbRadius + 0.12, 0)
		infectionBulb.Position = settledPosition
	end
	return (infectionBulb.Position - (targetFloor.Position + Vector3.new(0, bulbRadius + 0.12, 0))).Magnitude < 10
end

local function formStageFiveNest()
	if not infectionBulb or not infectionBulb.Parent then return end
	print("[INFECTION] Stage 5: forming the suspended nest.")

	-- Find the floor beneath the bulb before moving it. Ground growth must
	-- remain attached to the floor, not follow the elevated bulb.
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude
	floorParams.FilterDescendantsInstances = {spawner, infectionFolder}
	floorParams.IgnoreWater = true

	local groundHit = workspace:Raycast(
		infectionBulb.Position + Vector3.new(0, 4, 0),
		Vector3.new(0, -40, 0),
		floorParams
	)
	local groundPosition = groundHit
		and groundHit.Position + Vector3.new(0, 0.06, 0)
		or infectionBulb.Position - Vector3.new(0, infectionBulb.Size.Y * 0.5, 0)

	local houseZone = workspace:FindFirstChild("InfectionHouseZone", true)
	local isIndoors = false
	if houseZone and houseZone:IsA("BasePart") then
		local localPosition = houseZone.CFrame:PointToObjectSpace(infectionBulb.Position)
		local halfSize = houseZone.Size * 0.5
		isIndoors = math.abs(localPosition.X) <= halfSize.X
			and math.abs(localPosition.Y) <= halfSize.Y
			and math.abs(localPosition.Z) <= halfSize.Z
	end

	local directions = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 1).Unit, Vector3.new(-1, 0, 1).Unit,
		Vector3.new(1, 0, -1).Unit, Vector3.new(-1, 0, -1).Unit
	}
	local wallHits = {}
	for _, direction in ipairs(directions) do
		local hit = workspace:Raycast(
			infectionBulb.Position,
			direction * 14,
			floorParams
		)
		if hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
			table.insert(wallHits, hit)
		end
	end
	local ceilingHit = workspace:Raycast(
		infectionBulb.Position,
		Vector3.new(0, 20, 0),
		floorParams
	)

	local bulbRadius = math.max(infectionBulb.Size.Y * 0.5, 1)
	local raisedPosition = groundPosition + Vector3.new(0, bulbRadius + 3.2, 0)

	if isIndoors then
		-- In the house, the single central bulb is lifted above the floor.
		-- Use nearby walls/ceiling when available, with floor-reaching braces
		-- as a reliable fallback so it never simply floats unsupported.
		local attachmentCount = 0
		for _, hit in ipairs(wallHits) do
			local attachment = newCaptureVine("Stage5NestAttachmentTendril", 0.48)
			setCylinderBetween(attachment, raisedPosition, hit.Position, 0.48)
			attachmentCount += 1
			if attachmentCount >= 5 then break end
		end
		if ceilingHit then
			local attachment = newCaptureVine("Stage5NestCeilingTendril", 0.52)
			setCylinderBetween(attachment, raisedPosition, ceilingHit.Position, 0.52)
			attachmentCount += 1
		end
		if attachmentCount == 0 then
			for index = 1, 4 do
				local angle = (index - 1) * math.pi * 0.5
				local foot = groundPosition + Vector3.new(
					math.cos(angle) * 2.2, 0, math.sin(angle) * 2.2
				)
				local brace = newCaptureVine("Stage5NestSupportTendril", 0.5)
				setCylinderBetween(brace, raisedPosition, foot, 0.5)
			end
		end
		TweenService:Create(
			infectionBulb,
			TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{Position = raisedPosition, Size = Vector3.new(5.2, 5.2, 5.2)}
		):Play()
	else
		-- Outdoors, keep the central bulb close to the ground.
		for index = 1, 4 do
			local angle = (index - 1) * math.pi * 0.5
			local hip = groundPosition + Vector3.new(
				math.cos(angle) * 0.85, 0.35, math.sin(angle) * 0.85
			)
			local foot = groundPosition + Vector3.new(
				math.cos(angle) * 2.0, 0.05, math.sin(angle) * 2.0
			)
			local support = newCaptureVine("Stage5GroundSupportTentacle", 0.42)
			setCylinderBetween(support, hip, foot, 0.42)
		end
		TweenService:Create(
			infectionBulb,
			TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = groundPosition + Vector3.new(0, 0.55, 0), Size = Vector3.new(4.8, 4.8, 4.8)}
		):Play()
	end

	-- One main bulb only. Grow a broad network of tendrils outward from
	-- eight separate points around its grounded base.
	registerGroundAnchor(groundPosition, Vector3.new(0, 1, 0))
	for index = 1, 12 do
		local angle = (index - 1) * (math.pi * 2 / 12)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local startPoint = groundPosition + direction * 0.8
		task.spawn(growBranch, startPoint, Vector3.new(0, 1, 0), direction, 42, 1)
	end
end

local function runInfectionStageController()
	local stageClock = os.clock()
	while infectionFolder.Parent and growthStage < 4 do
		task.wait(2)
		local elapsed = os.clock() - stageClock
		local count = #growthSegments
		if growthStage == 1 and elapsed >= 75 and count >= 5 then
			growthStage = 2
			stageClock = os.clock()
			setBulbSize(2.2, 12)
			print("[INFECTION] Stage 2: the bulb is developing.")
			local origin = infectionBulb.Position - Vector3.new(0, 1.5, 0)
			for index = 1, 4 do
				local angle = (index - 1) * math.pi * 0.5
				task.spawn(growBranch, origin, Vector3.new(0, 1, 0), Vector3.new(math.cos(angle), 0, math.sin(angle)), 18, 0)
			end
		elseif growthStage == 2 and elapsed >= 115 and count >= 35 then
			growthStage = 3
			stageClock = os.clock()
			setBulbSize(3.8, 18)
			print("[INFECTION] Stage 3: mature parasite growth. Original growth settings restored.")
			local origin = infectionBulb.Position - Vector3.new(0, 1.5, 0)
			for index = 1, 8 do
				local angle = (index - 1) * math.pi * 0.25
				task.spawn(growBranch, origin, Vector3.new(0, 1, 0), Vector3.new(math.cos(angle), 0, math.sin(angle)), 32, 0)
			end
		elseif growthStage == 3 and elapsed >= 180 and count >= 120 then
			growthStage = 4
			relocationStarted = true
			setBulbSize(4.3, 7)
			retractStageThreeTendrils()
			task.wait(3.2)
			if crawlToNestTarget() then
				growthStage = 5
				relocationStarted = false
				formStageFiveNest()
				print("[INFECTION] Stage 5 nest established.")
			else
				warn("[INFECTION] Relocation stopped: check InfectionNestTarget and pathfinding.")
			end
		end
	end
end

--------------------------------------------------
-- START INFECTION
--------------------------------------------------

print("[INFECTION] Starting infection system...")

local startingSurface = findStartingSurface()

if not startingSurface then
	warn("[INFECTION] ERROR: No starting surface found near InfectionSpawner.")
	return
end

local startPosition =
	startingSurface.Position
	+ startingSurface.Normal * SURFACE_OFFSET

local startNormal = startingSurface.Normal

-- Register the initial starting point.
registerGroundAnchor(startPosition, startNormal)
registerCeilingAnchor(startPosition, startNormal)

-- Create the infection's starting bulb.
infectionBulb = createSpawnerBulb(
	startingSurface.Position,
	startingSurface.Normal
)

-- Choose an initial growth direction.
local startDirection = getPlayerFacingDirection(startPosition)

startDirection =
	startDirection
- startNormal * startDirection:Dot(startNormal)

if startDirection.Magnitude < 0.05 then
	local fallbackAxis

	if math.abs(startNormal.Z) < 0.9 then
		fallbackAxis = Vector3.new(0, 0, 1)
	else
		fallbackAxis = Vector3.new(1, 0, 0)
	end

	startDirection =
		fallbackAxis
	- startNormal * fallbackAxis:Dot(startNormal)
end

startDirection = startDirection.Unit

-- Start the main infection growth.
task.spawn(function()
	growBranch(
		startPosition,
		startNormal,
		startDirection,
		rng:NextInteger(5, 7),
		0
	)
end)

-- Start progression and the player-reactive systems.
task.spawn(runInfectionStageController)
task.spawn(runGroundStalkSystem)
task.spawn(runCeilingVineSystem)

print("[INFECTION] Infection system successfully started.")
