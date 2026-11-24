-- PARASITE ARM PROTOTYPE
-- Separate from InfectionSystem and CrawlerInfestation.
-- Place this Script in ServerScriptService.
-- Add an anchored Part named ParasiteArmSpawner to Workspace.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local rng = Random.new()

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local SPAWNER_NAME = "ParasiteArmSpawner"
local DETECTION_RANGE = 42
local CHECK_INTERVAL = 0.5

local ARM_SEGMENTS = 18
local ARM_GROW_TIME = 2.8
local ARM_BASE_RADIUS = 0.85
local ARM_TIP_RADIUS = 1.25

local LIFT_HEIGHT = 12
local LIFT_TIME = 2.8
local HOLD_TIME = 1.4
local LOWER_TIME = 1.6

local ARM_COLORS = {
  Color3.fromRGB(75, 39, 31),
  Color3.fromRGB(112, 58, 39),
  Color3.fromRGB(91, 45, 34),
  Color3.fromRGB(139, 75, 49)
}

--------------------------------------------------
-- SETUP
--------------------------------------------------

local spawner = workspace:WaitForChild(SPAWNER_NAME)

assert(spawner:IsA("BasePart"), SPAWNER_NAME .. " must be a Part or other BasePart")

spawner.Anchored = true
spawner.Transparency = 1
spawner.CanCollide = false
spawner.CanTouch = false
spawner.CanQuery = false

local oldFolder = workspace:FindFirstChild("ParasiteArmPrototype")
if oldFolder then
  oldFolder:Destroy()
end

local armFolder = Instance.new("Folder")
armFolder.Name = "ParasiteArmPrototype"
armFolder.Parent = workspace

local armBusy = false

--------------------------------------------------
-- ARM GEOMETRY
--------------------------------------------------

local function makeArmPart(name, shape)
  local part = Instance.new("Part")
  part.Name = name
  part.Shape = shape or Enum.PartType.Cylinder
  part.Material = Enum.Material.CorrodedMetal
  part.Color = ARM_COLORS[rng:NextInteger(1, #ARM_COLORS)]
  part.Anchored = true
  part.CanCollide = false
  part.CanTouch = false
  part.CanQuery = false
  part.CastShadow = true
  part.Parent = armFolder
  return part
end

local function placeCylinder(part, startPosition, endPosition, thickness)
  local difference = endPosition - startPosition
  local length = difference.Magnitude

  if length < 0.04 then
    part.Transparency = 1
    return
  end

  local axis = difference.Unit
  local up = Vector3.yAxis - axis * axis.Y

  if up.Magnitude < 0.05 then
    up = Vector3.zAxis - axis * axis.Z
  end

  up = up.Unit
  local side = axis:Cross(up).Unit
  up = side:Cross(axis).Unit

  part.Transparency = 0
  part.Size = Vector3.new(length + thickness * 0.12, thickness, thickness)
  part.CFrame = CFrame.fromMatrix(
    (startPosition + endPosition) / 2,
    axis,
    up,
    side
  )
end

local function curvePoint(startPosition, controlPosition, endPosition, alpha)
  local inverse = 1 - alpha
  return startPosition * (inverse * inverse)
    + controlPosition * (2 * inverse * alpha)
    + endPosition * (alpha * alpha)
end

local function createArm()
  local parts = {}

  for index = 1, ARM_SEGMENTS do
    local part = makeArmPart("ArmGrowthChunk")
    part.Size = Vector3.new(0.05, 0.1, 0.1)
    part.Transparency = 1
    table.insert(parts, part)
  end

  local tip = makeArmPart("ArmTip", Enum.PartType.Ball)
  tip.Size = Vector3.new(2.5, 2.5, 2.5)
  tip.Transparency = 1

  return parts, tip
end

local function updateArm(parts, tip, targetPosition, growthProgress)
  local startPosition = spawner.Position
    + Vector3.new(0, spawner.Size.Y * 0.5, 0)

  local controlPosition = startPosition:Lerp(targetPosition, 0.5)
    + Vector3.new(0, 2.1, 0)

  for index, part in ipairs(parts) do
    local segmentStart = (index - 1) / ARM_SEGMENTS
    local segmentEnd = index / ARM_SEGMENTS
    local localProgress = math.clamp(
      growthProgress * ARM_SEGMENTS - (index - 1),
      0,
      1
    )

    if localProgress <= 0 then
      part.Transparency = 1
    else
      local visibleEnd = segmentStart
        + (segmentEnd - segmentStart) * localProgress

      local a = curvePoint(
        startPosition,
        controlPosition,
        targetPosition,
        segmentStart
      )
      local b = curvePoint(
        startPosition,
        controlPosition,
        targetPosition,
        visibleEnd
      )

      local radiusAlpha = index / ARM_SEGMENTS
      local radius = ARM_BASE_RADIUS
        + (ARM_TIP_RADIUS - ARM_BASE_RADIUS) * radiusAlpha

      placeCylinder(part, a, b, radius * 2)
    end
  end

  tip.Position = targetPosition
  tip.Transparency = growthProgress >= 1 and 0 or 1
end

--------------------------------------------------
-- PLAYER TARGETING
--------------------------------------------------

local function findTarget()
  local nearestPlayer = nil
  local nearestRoot = nil
  local nearestHumanoid = nil
  local nearestDistance = DETECTION_RANGE

  for _, player in ipairs(Players:GetPlayers()) do
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    local alreadyGrabbed = character
      and character:GetAttribute("ParasiteArmGrabbed") == true
    local alreadyInfected = player:GetAttribute("IsInfected") == true
      or (character and character:GetAttribute("IsInfected") == true)

    if root and humanoid and humanoid.Health > 0
      and not alreadyGrabbed and not alreadyInfected then

      local offset = root.Position - spawner.Position
      local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude

      if math.abs(offset.Y) <= 14 and horizontalDistance < nearestDistance then
        nearestPlayer = player
        nearestRoot = root
        nearestHumanoid = humanoid
        nearestDistance = horizontalDistance
      end
    end
  end

  return nearestPlayer, nearestRoot, nearestHumanoid
end

--------------------------------------------------
-- GRAB AND LIFT SEQUENCE
--------------------------------------------------

local function animateArm(parts, tip, root, startCFrame, endCFrame, duration, growthStart, growthEnd)
  local elapsed = 0

  while elapsed < duration and root.Parent do
    local deltaTime = RunService.Heartbeat:Wait()
    elapsed += deltaTime

    local alpha = math.clamp(elapsed / duration, 0, 1)
    local eased = alpha * alpha * (3 - 2 * alpha)
    local currentCFrame = startCFrame:Lerp(endCFrame, eased)

    root.CFrame = currentCFrame

    local growth = growthStart + (growthEnd - growthStart) * alpha
    updateArm(parts, tip, root.Position, growth)
  end

  if root.Parent then
    root.CFrame = endCFrame
    updateArm(parts, tip, root.Position, growthEnd)
  end
end

local function runGrab(player, root, humanoid)
  if armBusy or not root.Parent or not humanoid.Parent then return end

  armBusy = true

  local character = player.Character
  if not character then
    armBusy = false
    return
  end

  character:SetAttribute("ParasiteArmGrabbed", true)

  local wasAnchored = root.Anchored
  local oldAutoRotate = humanoid.AutoRotate
  local oldPlatformStand = humanoid.PlatformStand
  local originalCFrame = root.CFrame

  local parts, tip = createArm()

  print("[PARASITE ARM] Growing toward " .. player.Name)

  local growStart = os.clock()
  while os.clock() - growStart < ARM_GROW_TIME and root.Parent do
    local alpha = math.clamp(
      (os.clock() - growStart) / ARM_GROW_TIME,
      0,
      1
    )
    updateArm(parts, tip, root.Position, alpha)
    RunService.Heartbeat:Wait()
  end

  if not root.Parent or humanoid.Health <= 0 then
    armFolder:ClearAllChildren()
    armBusy = false
    return
  end

  updateArm(parts, tip, root.Position, 1)

  -- The arm's thick tip closes around the avatar before lifting.
  tip.Size = Vector3.new(3.2, 3.2, 3.2)
  tip.Position = root.Position

  root.Anchored = true
  humanoid.AutoRotate = false
  humanoid.PlatformStand = true

  local raisedCFrame = originalCFrame + Vector3.new(0, LIFT_HEIGHT, 0)
  animateArm(parts, tip, root, originalCFrame, raisedCFrame, LIFT_TIME, 1, 1)

  task.wait(HOLD_TIME)

  if root.Parent then
    animateArm(parts, tip, root, raisedCFrame, originalCFrame, LOWER_TIME, 1, 1)
  end

  if root.Parent then
    root.Anchored = wasAnchored
    humanoid.PlatformStand = oldPlatformStand
    humanoid.AutoRotate = oldAutoRotate
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
  end

  -- Leave the arm visible briefly, then retract by cleaning up the prototype.
  task.wait(0.8)
  if armFolder.Parent then
    armFolder:ClearAllChildren()
  end

  print("[PARASITE ARM] Finished prototype grab for " .. player.Name)
  armBusy = false
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

print("[PARASITE ARM] Prototype ready. Waiting for " .. SPAWNER_NAME)

while script.Parent do
  if not armBusy then
    local player, root, humanoid = findTarget()

    if player and root and humanoid then
      task.spawn(runGrab, player, root, humanoid)
    end
  end

  task.wait(CHECK_INTERVAL)
end
