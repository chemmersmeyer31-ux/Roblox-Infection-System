-- PLAYER PARASITE TRANSFORMATION
-- Separate prototype: recolors infected characters, adds growths, animates a back tendril.
-- Place this Script in ServerScriptService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EVENT_NAME = "ParasiteInfectionEvent"
local rng = Random.new()

local COLORS = {
  Color3.fromRGB(75, 39, 31),
  Color3.fromRGB(112, 58, 39),
  Color3.fromRGB(91, 45, 34),
  Color3.fromRGB(139, 75, 49),
  Color3.fromRGB(51, 29, 25)
}

local GROWTH_MIN = 0.22
local GROWTH_MAX = 0.58
local TENDRIL_LENGTH = 8.5
local TENDRIL_SEGMENTS = 11

local event = game:GetService("ServerScriptService"):FindFirstChild(EVENT_NAME)
if not event then
  event = Instance.new("BindableEvent")
  event.Name = EVENT_NAME
  event.Parent = game:GetService("ServerScriptService")
end

local active = {}

local function randomColor()
  return COLORS[rng:NextInteger(1, #COLORS)]
end

local function transformBodyAppearance(character)
  -- Remove visual items that would cover the parasite body.
  for _, item in ipairs(character:GetChildren()) do
    if item:IsA("Accessory")
      or item:IsA("Shirt")
      or item:IsA("Pants")
      or item:IsA("ShirtGraphic")
      or item:IsA("CharacterMesh")
      or item:IsA("BodyColors") then
      item:Destroy()
    end
  end

  for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("Decal") or item:IsA("Texture") or item:IsA("SurfaceAppearance") then
      item:Destroy()
    elseif item:IsA("SpecialMesh") then
      item.TextureId = ""
    end
  end

  local parasiteColor = Color3.fromRGB(76, 39, 30)
  local headRustColor = Color3.fromRGB(119, 61, 39)
  for _, item in ipairs(character:GetChildren()) do
    if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" then
      item.Material = Enum.Material.CorrodedMetal
      item.Color = item.Name == "Head" and headRustColor or parasiteColor
      if item:IsA("MeshPart") then
        item.TextureID = ""
      end
    end
  end
end

local function findNearestUninfected(character, origin)
  local nearest = nil
  local nearestDistance = math.huge

  for _, model in ipairs(workspace:GetDescendants()) do
    if model:IsA("Model") and model ~= character
      and not model:GetAttribute("IsInfected")
      and not model:GetAttribute("ParasiteArmGrabbed") then
      local humanoid = model:FindFirstChildOfClass("Humanoid")
      local root = model:FindFirstChild("HumanoidRootPart")
      if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
        local distance = (root.Position - origin).Magnitude
        if distance < nearestDistance then
          nearest = root
          nearestDistance = distance
        end
      end
    end
  end

  return nearest
end

local function setGroundVineSegment(motor, torso, startPosition, endPosition, facingDirection, radius)
  local difference = endPosition - startPosition
  local length = difference.Magnitude
  if length < 0.025 then
    motor.Enabled = false
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
    motor.Enabled = false
    return
  end
  side = side.Unit

  local targetCFrame = CFrame.fromMatrix((startPosition + endPosition) * 0.5, axis, up, side)
  local part = motor.Part1
  part.Size = Vector3.new(length + radius * 0.9, radius * 2, radius * 2)
  motor.C0 = torso.CFrame:ToObjectSpace(targetCFrame)
  motor.Enabled = true
end

local function makeBackTendril(character, root)
  local folder = Instance.new("Folder")
  folder.Name = "ParasiteBackTendril"
  folder.Parent = character

  local torso = character:FindFirstChild("UpperTorso")
    or character:FindFirstChild("Torso")
    or character:FindFirstChild("LowerTorso")
    or root

  local function newVinePart(name, color, size)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Cylinder
    part.Material = Enum.Material.CorrodedMetal
    part.Color = color or Color3.fromRGB(76, 39, 30)
    part.Size = size or Vector3.new(0.5, 0.5, 0.5)
    part.Anchored = false
    part.Massless = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = true
    part.Parent = folder

    local motor = Instance.new("Motor6D")
    motor.Name = "BackVineAttachment"
    motor.Part0 = torso
    motor.Part1 = part
    motor.C0 = torso.CFrame:ToObjectSpace(part.CFrame)
    motor.C1 = CFrame.identity
    motor.Parent = torso
    return {part = part, motor = motor}
  end

  local roots = {}
  for index = 1, 4 do
    roots[index] = newVinePart("BackVineRootRunner", COLORS[(index % #COLORS) + 1])
  end

  local stalkParts = {}
  for index = 1, 13 do
    stalkParts[index] = newVinePart("BackGroundVineStem", COLORS[(index % #COLORS) + 1])
  end

  local rootBulb = Instance.new("Part")
  rootBulb.Name = "BackVineBulb"
  rootBulb.Shape = Enum.PartType.Ball
  rootBulb.Size = Vector3.new(0.95, 1.05, 0.95)
  rootBulb.Material = Enum.Material.CorrodedMetal
  rootBulb.Color = Color3.fromRGB(76, 39, 30)
  rootBulb.Anchored = false
  rootBulb.Massless = true
  rootBulb.CanCollide = false
  rootBulb.CanTouch = false
  rootBulb.CanQuery = false
  rootBulb.Parent = folder

  local bulbMotor = Instance.new("Motor6D")
  bulbMotor.Name = "BackVineBaseAttachment"
  bulbMotor.Part0 = torso
  bulbMotor.Part1 = rootBulb
  bulbMotor.C0 = CFrame.new(0, 0, torso.Size.Z * 0.5 + 0.45)
  bulbMotor.C1 = CFrame.identity
  bulbMotor.Parent = torso

  local direction = root.CFrame.LookVector
  -- Keep the tendril on one consistent anatomical side. Re-selecting this
  -- every frame makes it jump across the character when the target moves.
  local sideSign = 1
  local phase = rng:NextNumber(0, math.pi * 2)
  local currentExtension = 1.0
  local targetRoot = nil
  local nextTargetScan = 0
  local connection

  connection = RunService.Heartbeat:Connect(function(dt)
    if not character.Parent or not root.Parent or not folder.Parent or not torso.Parent then
      connection:Disconnect()
      folder:Destroy()
      return
    end

    local origin = torso.CFrame:PointToWorldSpace(Vector3.new(0, 0.12, torso.Size.Z * 0.5 + 0.45))
    if os.clock() >= nextTargetScan then
      targetRoot = findNearestUninfected(character, origin)
      nextTargetScan = os.clock() + 0.3
    end

    local desiredDirection = root.CFrame.LookVector
    local desiredExtension = 2.2
    if targetRoot and targetRoot.Parent then
      -- Aim from a point above the infected player's head so the raised tip
      -- points toward the enemy instead of simply facing horizontally.
      local elevatedAimOrigin = origin + Vector3.new(0, 4.65, 0)
      local enemyAimPoint = targetRoot.Position + Vector3.new(0, 1.5, 0)
      local aimOffset = enemyAimPoint - elevatedAimOrigin
      if aimOffset.Magnitude > 0.05 then
        desiredDirection = aimOffset.Unit
      end

      local distance = (targetRoot.Position - origin).Magnitude
      local proximity = 1 - math.clamp(distance / 35, 0, 1)
      -- Give the tendril a longer reach, especially as the enemy gets close.
      desiredExtension = 2.2 + proximity * 4.0
    end

    direction = direction:Lerp(desiredDirection, math.clamp(dt * 4.5, 0, 1))
    if direction.Magnitude > 0.05 then direction = direction.Unit end
    currentExtension += (desiredExtension - currentExtension) * math.clamp(dt * 2.6, 0, 1)
    phase += dt * 2.0
    local hasTarget = targetRoot ~= nil and targetRoot.Parent ~= nil
    -- Gently search when no enemy is being tracked; fade this motion out
    -- when a target appears so the tendril can aim cleanly.
    local idleAmount = hasTarget and 0 or 1
    local sway = math.sin(phase * 0.75) * (0.08 + idleAmount * 0.16)

    local right = torso.CFrame.RightVector
    for index, item in ipairs(roots) do
      local sideSign = index % 2 == 0 and 1 or -1
      local verticalSign = index <= 2 and 1 or -1
      local startPoint = origin + right * sideSign * 0.18 + Vector3.new(0, verticalSign * 0.18, 0)
      local endPoint = origin + right * sideSign * (0.72 + (index % 2) * 0.12)
        + Vector3.new(0, verticalSign * 0.38, 0)
      setGroundVineSegment(item.motor, torso, startPoint, endPoint, direction, 0.105)
    end

    -- The tendril rises above the head, sweeps farther around the shoulder/side,
    -- then angles its tip toward the enemy from that elevated position.
    local stemHeight = 4.65
    local visibleExtension = currentExtension + sway
    local sideDirection = torso.CFrame.RightVector * sideSign
    local function pathPoint(t)
      local bend = t * t
      local sideSweep = math.sin(t * math.pi) * 1.5
      local forwardReach = visibleExtension * bend
      local shoulderLift = math.sin(t * math.pi) * 0.28
      -- With no target, the raised tip slowly sways and reaches slightly
      -- forward/back, like the parasite is quietly searching for movement.
      local idleSideSearch = math.sin(phase * 0.75) * 0.42 * idleAmount * bend
      local idleForwardSearch = math.sin(phase * 0.55 + 0.8) * 0.28 * idleAmount * bend
      return origin
        + sideDirection * (sideSweep + idleSideSearch)
        + direction * (forwardReach + idleForwardSearch)
        + Vector3.new(0, stemHeight * t + shoulderLift, 0)
    end

    for index, item in ipairs(stalkParts) do
      local t0 = (index - 1) / #stalkParts
      local t1 = index / #stalkParts
      local taper = index / #stalkParts
      local radius = 0.285 - taper * 0.105
      setGroundVineSegment(item.motor, torso, pathPoint(t0), pathPoint(t1), direction, radius)
    end
  end)

  return folder
end

local function disableDefaultAnimations(character, humanoid)
  -- The default Animate LocalScript keeps starting Roblox's normal idle/walk
  -- tracks. Disable it before taking control of the infected body's joints.
  local animateScript = character:FindFirstChild("Animate")
  if animateScript and animateScript:IsA("LocalScript") then
    animateScript.Disabled = true
  end

  local animator = humanoid:FindFirstChildOfClass("Animator")
  if animator then
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
      track:Stop(0.12)
    end
  end
end

local function addProceduralAnimation(character, humanoid, root)
  disableDefaultAnimations(character, humanoid)
  local joints = {}

  -- Normalize names so this works with both R6 names ("Right Shoulder")
  -- and R15 names ("RightShoulder").
  for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("Motor6D") then
      local key = string.lower(item.Name):gsub("[%s_]", "")
      joints[key] = {motor = item, base = item.C0}
    end
  end

  local function getJoint(...)
    for _, name in ipairs({...}) do
      if joints[name] then return joints[name] end
    end
    return nil
  end

  local rootJoint = getJoint("rootjoint", "root")
  local waist = getJoint("waist")
  local neck = getJoint("neck")

  local rightShoulder = getJoint("rightshoulder")
  local leftShoulder = getJoint("leftshoulder")
  local rightElbow = getJoint("rightelbow")
  local leftElbow = getJoint("leftelbow")
  local rightWrist = getJoint("rightwrist")
  local leftWrist = getJoint("leftwrist")

  local rightHip = getJoint("righthip")
  local leftHip = getJoint("lefthip")
  local rightKnee = getJoint("rightknee")
  local leftKnee = getJoint("leftknee")
  local rightAnkle = getJoint("rightankle")
  local leftAnkle = getJoint("leftankle")

  -- R6 has no separate elbows, knees, wrists, or ankles. Those joints are
  -- simply skipped; the matching R15 joints are animated when they exist.
  if not rootJoint and not waist then
    warn("[PARASITE] No supported body root joints found on " .. character.Name)
    return
  end

  local startTime = os.clock()
  local targetRoot = nil
  local nextTargetScan = 0
  local smoothedHeadYaw = 0
  local smoothedHeadPitch = 0
  local movementBlend = 0
  local gaitPhase = 0
  local connection

  local function apply(joint, offset)
    if joint and joint.motor and joint.motor.Parent then
      joint.motor.C0 = joint.base * offset
    end
  end

  connection = RunService.Heartbeat:Connect(function(dt)
    if not character.Parent or humanoid.Health <= 0 then
      connection:Disconnect()
      return
    end

    local elapsed = os.clock() - startTime
    local moveAmount = humanoid.MoveDirection.Magnitude
    local velocity = root.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local moving = moveAmount > 0.08 and horizontalSpeed > 0.5

    -- Smoothly blend between the idle pose and the coordinated walking pose.
    local targetMovementBlend = moving and 1 or 0
    movementBlend += (targetMovementBlend - movementBlend) * math.clamp(dt * 5, 0, 1)

    local gaitRate = math.clamp(horizontalSpeed * 0.85, 4.5, 9.5)
    if moving then
      gaitPhase += dt * gaitRate
    end

    local stride = math.sin(gaitPhase)
    local oppositeStride = math.sin(gaitPhase + math.pi)
    local kneeRight = math.max(0, -stride) * 0.72 * movementBlend
    local kneeLeft = math.max(0, -oppositeStride) * 0.72 * movementBlend

    local idleBreath = math.sin(elapsed * 1.35)
    local idleSway = math.sin(elapsed * 0.8 + 0.5)
    local walkBob = math.abs(math.sin(gaitPhase * 2)) * 0.075 * movementBlend
    local idleBob = idleBreath * 0.025 * (1 - movementBlend)
    local bodyBob = walkBob + idleBob

    local bodyLean = 0.13 * movementBlend + 0.035 * (1 - movementBlend)
    local bodyRoll = math.sin(gaitPhase) * 0.035 * movementBlend
      + idleSway * 0.045 * (1 - movementBlend)
    local bodyTwist = math.sin(gaitPhase) * 0.045 * movementBlend
      + math.sin(elapsed * 0.55) * 0.025 * (1 - movementBlend)

    -- Root and waist work together, instead of the torso staying rigid.
    apply(rootJoint, CFrame.new(0, bodyBob, 0)
      * CFrame.Angles(bodyLean, bodyTwist, bodyRoll))
    apply(waist, CFrame.Angles(
      -0.045 * movementBlend + idleBreath * 0.018 * (1 - movementBlend),
      -bodyTwist * 0.65,
      -bodyRoll * 0.55
    ))

    -- Both arms swing opposite the legs. The elbows flex as each arm swings
    -- back, while wrists add a small follow-through so the whole arm connects.
    local armIdle = math.sin(elapsed * 1.1) * 0.055
    local rightArmSwing = stride * 0.48 * movementBlend + armIdle * (1 - movementBlend)
    local leftArmSwing = oppositeStride * 0.48 * movementBlend - armIdle * (1 - movementBlend)
    local shoulderHunch = -0.17 + 0.035 * math.sin(elapsed * 1.7)

    apply(rightShoulder, CFrame.Angles(shoulderHunch + rightArmSwing, 0, -0.13))
    apply(leftShoulder, CFrame.Angles(shoulderHunch + leftArmSwing, 0, 0.13))

    apply(rightElbow, CFrame.Angles(
      0.12 + math.max(0, -stride) * 0.62 * movementBlend
        + (1 - movementBlend) * (0.12 + math.sin(elapsed * 1.4) * 0.035),
      0, 0
    ))
    apply(leftElbow, CFrame.Angles(
      0.12 + math.max(0, -oppositeStride) * 0.62 * movementBlend
        + (1 - movementBlend) * (0.12 + math.sin(elapsed * 1.4 + 1) * 0.035),
      0, 0
    ))

    apply(rightWrist, CFrame.Angles(0, 0, math.sin(gaitPhase + 0.5) * 0.08 * movementBlend))
    apply(leftWrist, CFrame.Angles(0, 0, math.sin(gaitPhase + math.pi + 0.5) * 0.08 * movementBlend))

    -- Hips drive the stride; knees and ankles follow the same gait phase.
    local legIdle = math.sin(elapsed * 0.75) * 0.025
    apply(rightHip, CFrame.Angles(
      oppositeStride * 0.42 * movementBlend + legIdle * (1 - movementBlend), 0, 0
    ))
    apply(leftHip, CFrame.Angles(
      stride * 0.42 * movementBlend - legIdle * (1 - movementBlend), 0, 0
    ))
    apply(rightKnee, CFrame.Angles(kneeRight + (1 - movementBlend) * 0.025, 0, 0))
    apply(leftKnee, CFrame.Angles(kneeLeft + (1 - movementBlend) * 0.025, 0, 0))
    apply(rightAnkle, CFrame.Angles(-kneeRight * 0.35, 0, 0))
    apply(leftAnkle, CFrame.Angles(-kneeLeft * 0.35, 0, 0))

    -- The head tracks the nearest uninfected character, then returns to a
    -- subtle searching motion when no target is nearby.
    if neck then
      if os.clock() >= nextTargetScan then
        targetRoot = findNearestUninfected(character, root.Position)
        nextTargetScan = os.clock() + 0.4
      end

      local desiredYaw = 0
      local desiredPitch = 0
      if targetRoot and targetRoot.Parent then
        local offset = root.CFrame:PointToObjectSpace(
          targetRoot.Position + Vector3.new(0, 1.2, 0)
        )
        desiredYaw = math.clamp(math.atan2(-offset.X, -offset.Z), -0.65, 0.65)
        local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
        desiredPitch = math.clamp(
          math.atan2(offset.Y - 1.2, math.max(horizontalDistance, 0.1)),
          -0.3, 0.3
        )
      else
        desiredYaw = math.sin(elapsed * 0.7) * 0.12
        desiredPitch = math.sin(elapsed * 0.9 + 1) * 0.07
      end

      local headBlend = math.clamp(dt * 3.5, 0, 1)
      smoothedHeadYaw += (desiredYaw - smoothedHeadYaw) * headBlend
      smoothedHeadPitch += (desiredPitch - smoothedHeadPitch) * headBlend
      local idleTilt = targetRoot and 0 or math.sin(elapsed * 0.65) * 0.045
      apply(neck, CFrame.Angles(smoothedHeadPitch, smoothedHeadYaw, idleTilt))
    end
  end)
end
local function transformCharacter(character, player)
  if not character or not character.Parent or character:GetAttribute("IsInfected") then
    return
  end

  local humanoid = character:FindFirstChildOfClass("Humanoid")
  local root = character:FindFirstChild("HumanoidRootPart")
  if not humanoid or not root then return end

  character:SetAttribute("IsInfected", true)
  if player then
    player:SetAttribute("IsInfected", true)
  end

  print("[PARASITE] Transforming " .. character.Name)
  transformBodyAppearance(character)
  makeBackTendril(character, root)
  addProceduralAnimation(character, humanoid, root)
end

event.Event:Connect(function(character, player)
  transformCharacter(character, player)
end)

print("[PARASITE] Transformation system ready.")
