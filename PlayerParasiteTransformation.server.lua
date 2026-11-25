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
    local desiredExtension = 1.0
    if targetRoot and targetRoot.Parent then
      local offset = targetRoot.Position - origin
      local horizontal = Vector3.new(offset.X, 0, offset.Z)
      if horizontal.Magnitude > 0.05 then
        -- The tendril turns around its back attachment to face the target.
        desiredDirection = horizontal.Unit
        local proximity = 1 - math.clamp(offset.Magnitude / 35, 0, 1)
        -- It stays compact at range, then reaches farther as the target approaches.
        desiredExtension = 1.0 + proximity * 2.5
      end
    end

    direction = direction:Lerp(desiredDirection, math.clamp(dt * 4.5, 0, 1))
    if direction.Magnitude > 0.05 then direction = direction.Unit end
    currentExtension += (desiredExtension - currentExtension) * math.clamp(dt * 2.6, 0, 1)
    phase += dt * 2.0
    local sway = math.sin(phase) * 0.09

    local right = torso.CFrame.RightVector
    for index, item in ipairs(roots) do
      local sideSign = index % 2 == 0 and 1 or -1
      local verticalSign = index <= 2 and 1 or -1
      local startPoint = origin + right * sideSign * 0.18 + Vector3.new(0, verticalSign * 0.18, 0)
      local endPoint = origin + right * sideSign * (0.72 + (index % 2) * 0.12)
        + Vector3.new(0, verticalSign * 0.38, 0)
      setGroundVineSegment(item.motor, torso, startPoint, endPoint, direction, 0.105)
    end

    -- A fuller, taller reach: the tendril rises to shoulder height,
    -- sweeps around the nearest side of the infected character, then reaches
    -- toward the target. Extension increases as the target gets close.
    local stemHeight = 4.65
    local visibleExtension = currentExtension + sway
    local sideSign = direction:Dot(torso.CFrame.RightVector) >= 0 and 1 or -1
    local sideDirection = torso.CFrame.RightVector * sideSign
    local function pathPoint(t)
      local bend = t * t
      local sideSweep = math.sin(t * math.pi) * 1.05
      local forwardReach = visibleExtension * bend
      local shoulderLift = math.sin(t * math.pi) * 0.28
      return origin
        + sideDirection * sideSweep
        + direction * forwardReach
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

local function addProceduralAnimation(character, humanoid, root)
  local joints = {}
  for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("Motor6D") then
      local key = string.lower(item.Name):gsub("[%s_]", "")
      if key == "root" or key == "rootjoint"
        or key == "rightshoulder" or key == "leftshoulder"
        or key == "rightarm" or key == "leftarm"
        or key == "righthip" or key == "lefthip"
        or key == "rightleg" or key == "leftleg"
        or key == "waist" then
        joints[key] = {motor = item, base = item.C0}
      end
    end
  end

  local rootJoint = joints.rootjoint or joints.root or joints.waist
  if not rootJoint then return end

  local startTime = os.clock()
  local connection
  connection = RunService.Heartbeat:Connect(function()
    if not character.Parent or humanoid.Health <= 0 or not rootJoint.motor.Parent then
      connection:Disconnect()
      return
    end

    local elapsed = os.clock() - startTime
    local moving = humanoid.MoveDirection.Magnitude > 0.08
    local speed = moving and 8.5 or 2.1
    local wave = math.sin(elapsed * speed)
    local bob = wave * (moving and 0.07 or 0.025)
    local lean = moving and 0.13 or 0.035
    local roll = math.sin(elapsed * (moving and 4.25 or 1.05)) * 0.04

    rootJoint.motor.C0 = rootJoint.base
      * CFrame.new(0, bob, 0)
      * CFrame.Angles(lean, 0, roll)

    local rightShoulder = joints.rightshoulder or joints.rightarm
    local leftShoulder = joints.leftshoulder or joints.leftarm
    local rightHip = joints.righthip or joints.rightleg
    local leftHip = joints.lefthip or joints.leftleg

    local armSwing = moving and wave * 0.42 or math.sin(elapsed * 1.2) * 0.045
    local legSwing = moving and -wave * 0.34 or 0.015

    if rightShoulder then
      rightShoulder.motor.C0 = rightShoulder.base * CFrame.Angles(armSwing - 0.16, 0, -0.12)
    end
    if leftShoulder then
      leftShoulder.motor.C0 = leftShoulder.base * CFrame.Angles(-armSwing - 0.16, 0, 0.12)
    end
    if rightHip then
      rightHip.motor.C0 = rightHip.base * CFrame.Angles(legSwing, 0, 0)
    end
    if leftHip then
      leftHip.motor.C0 = leftHip.base * CFrame.Angles(-legSwing, 0, 0)
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
