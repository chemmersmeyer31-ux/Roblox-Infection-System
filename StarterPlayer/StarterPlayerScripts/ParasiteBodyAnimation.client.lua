-- R15 PARASITE BODY ANIMATION
-- Install this as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- Every client runs this controller, so infected characters animate for everyone.
-- Roblox's normal Animator remains enabled; this script applies the parasite pose
-- after the Animator has evaluated its tracks.

local RunService = game:GetService("RunService")

local activeCharacters = {}

local function findMotor(character, name)
	local item = character:FindFirstChild(name, true)
	if item and item:IsA("Motor6D") then
		return item
	end
	return nil
end

local function setupCharacter(character)
	if not character:IsA("Model") then
		return
	end

	local function tryStart()
		if activeCharacters[character] then
			return
		end
		if character:GetAttribute("IsInfected") ~= true then
			return
		end

		-- Character parts can replicate after the Model and infection attribute.
		-- DescendantAdded below retries setup as the R15 rig arrives.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not rootPart then
			return
		end

		-- Take over the infected character's animation locally, after this
		-- client has detected the infection. Do not disable Animate on the
		-- server: each client must disable its own copy so this LocalScript
		-- can immediately provide the replacement pose below.
		local animateScript = character:FindFirstChild("Animate")
		if animateScript and animateScript:IsA("LocalScript") then
			animateScript.Disabled = true
		end

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0.1)
			end
		end

		local joints = {
			Root = findMotor(character, "Root"),
			Waist = findMotor(character, "Waist"),
			Neck = findMotor(character, "Neck"),

			RightShoulder = findMotor(character, "RightShoulder"),
			LeftShoulder = findMotor(character, "LeftShoulder"),
			RightElbow = findMotor(character, "RightElbow"),
			LeftElbow = findMotor(character, "LeftElbow"),
			RightWrist = findMotor(character, "RightWrist"),
			LeftWrist = findMotor(character, "LeftWrist"),

			RightHip = findMotor(character, "RightHip"),
			LeftHip = findMotor(character, "LeftHip"),
			RightKnee = findMotor(character, "RightKnee"),
			LeftKnee = findMotor(character, "LeftKnee"),
			RightAnkle = findMotor(character, "RightAnkle"),
			LeftAnkle = findMotor(character, "LeftAnkle"),
		}

		if not joints.Root or not joints.Waist then
			warn("[PARASITE] R15 Root/Waist joints not found on " .. character:GetFullName())
			return
		end

		activeCharacters[character] = {
			humanoid = humanoid,
			rootPart = rootPart,
			joints = joints,
			startTime = os.clock(),
			gaitPhase = 0,
			movementBlend = 0,
		}

		print("[PARASITE] R15 body animation active: " .. character.Name)
	end

	-- Listen before the first attempt so we don't miss parts that replicate later.
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Humanoid") or descendant:IsA("BasePart")
			or descendant:IsA("Motor6D") or descendant.Name == "Animate" then
			tryStart()
		end
	end)

	character:GetAttributeChangedSignal("IsInfected"):Connect(tryStart)
	tryStart()
end

for _, character in ipairs(workspace:GetChildren()) do
	setupCharacter(character)
end

workspace.ChildAdded:Connect(setupCharacter)
workspace.ChildRemoved:Connect(function(character)
	activeCharacters[character] = nil
end)

local function pose(motor, transform)
	if motor and motor.Parent then
		motor.Transform = transform
	end
end

RunService.PreSimulation:Connect(function(dt)
	for character, data in pairs(activeCharacters) do
		local humanoid = data.humanoid
		local rootPart = data.rootPart
		local joints = data.joints

		if not character.Parent or not humanoid.Parent or humanoid.Health <= 0
			or not rootPart.Parent then
			activeCharacters[character] = nil
			continue
		end

		local elapsed = os.clock() - data.startTime
		local velocity = rootPart.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local moving = humanoid.MoveDirection.Magnitude > 0.08 and horizontalSpeed > 0.5

		local targetBlend = moving and 1 or 0
		data.movementBlend += (targetBlend - data.movementBlend)
			* math.clamp(dt * 5, 0, 1)

		local blend = data.movementBlend
		local gaitRate = math.clamp(horizontalSpeed * 0.85, 4.5, 9.5)
		if moving then
			data.gaitPhase += dt * gaitRate
		end

		local phase = data.gaitPhase
		local stride = math.sin(phase)
		local oppositeStride = math.sin(phase + math.pi)

		-- Legs: hips lead the stride; knees and ankles follow the same phase.
		local rightKnee = math.max(0, -stride) * 0.72 * blend
		local leftKnee = math.max(0, -oppositeStride) * 0.72 * blend
		local legIdle = math.sin(elapsed * 0.75) * 0.025

		pose(joints.RightHip, CFrame.Angles(
			oppositeStride * 0.42 * blend + legIdle * (1 - blend), 0, 0))
		pose(joints.LeftHip, CFrame.Angles(
			stride * 0.42 * blend - legIdle * (1 - blend), 0, 0))
		pose(joints.RightKnee, CFrame.Angles(rightKnee + 0.025 * (1 - blend), 0, 0))
		pose(joints.LeftKnee, CFrame.Angles(leftKnee + 0.025 * (1 - blend), 0, 0))
		pose(joints.RightAnkle, CFrame.Angles(-rightKnee * 0.35, 0, 0))
		pose(joints.LeftAnkle, CFrame.Angles(-leftKnee * 0.35, 0, 0))

		-- Arms counter-swing with the legs; elbows and wrists follow through.
		local armIdle = math.sin(elapsed * 1.1) * 0.055
		local rightArm = stride * 0.48 * blend + armIdle * (1 - blend)
		local leftArm = oppositeStride * 0.48 * blend - armIdle * (1 - blend)

		pose(joints.RightShoulder, CFrame.Angles(-0.17 + rightArm, 0, -0.13))
		pose(joints.LeftShoulder, CFrame.Angles(-0.17 + leftArm, 0, 0.13))
		pose(joints.RightElbow, CFrame.Angles(
			0.12 + math.max(0, -stride) * 0.62 * blend, 0, 0))
		pose(joints.LeftElbow, CFrame.Angles(
			0.12 + math.max(0, -oppositeStride) * 0.62 * blend, 0, 0))
		pose(joints.RightWrist, CFrame.Angles(0, 0, stride * 0.08 * blend))
		pose(joints.LeftWrist, CFrame.Angles(0, 0, oppositeStride * 0.08 * blend))

		-- Torso: breathing while idle, coordinated bob/lean while walking.
		local breath = math.sin(elapsed * 1.35)
		local idleSway = math.sin(elapsed * 0.8 + 0.5)
		local bob = math.abs(math.sin(phase * 2)) * 0.075 * blend
			+ breath * 0.025 * (1 - blend)
		local lean = 0.13 * blend + 0.035 * (1 - blend)
		local roll = math.sin(phase) * 0.035 * blend
			+ idleSway * 0.045 * (1 - blend)
		local twist = math.sin(phase) * 0.045 * blend
			+ math.sin(elapsed * 0.55) * 0.025 * (1 - blend)

		pose(joints.Root, CFrame.new(0, bob, 0) * CFrame.Angles(lean, twist, roll))
		pose(joints.Waist, CFrame.Angles(
			-0.045 * blend + breath * 0.018 * (1 - blend),
			-twist * 0.65,
			-roll * 0.55
		))

		-- Subtle searching head motion while idle.
		pose(joints.Neck, CFrame.Angles(
			math.sin(elapsed * 0.9) * 0.035,
			math.sin(elapsed * 0.7) * 0.09,
			math.sin(elapsed * 0.65) * 0.035
		))
	end
end)
