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

local function makeGrowth(parent, bodyPart, size, localPosition)
  local bulb = Instance.new("Part")
  bulb.Name = "ParasiteBulb"
  bulb.Shape = Enum.PartType.Ball
  bulb.Size = size
  bulb.Material = Enum.Material.SmoothPlastic
  bulb.Color = randomColor()
  bulb.Anchored = false
  bulb.Massless = true
  bulb.CanCollide = false
  bulb.CanTouch = false
  bulb.CanQuery = false
  bulb.CFrame = bodyPart.CFrame * CFrame.new(localPosition)
  bulb.Parent = parent

  local weld = Instance.new("WeldConstraint")
  weld.Part0 = bodyPart
  weld.Part1 = bulb
  weld.Parent = bulb
  return bulb
end

local function addBodyGrowths(character)
  local bodyParts = {}
  for _, item in ipairs(character:GetChildren()) do
    if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart"
      and item.Name ~= "ParasiteBackTendril" then
      table.insert(bodyParts, item)
      item.Material = Enum.Material.SmoothPlastic
      item.Color = randomColor()
    end
  end

  for _, bodyPart in ipairs(bodyParts) do
    local name = bodyPart.Name
    local count = 1
    if string.find(name, "Torso") or name == "UpperTorso" then
      count = 5
    elseif string.find(name, "Arm") or string.find(name, "Leg") then
      count = 2
    end

    for index = 1, count do
      local x = rng:NextNumber(-0.32, 0.32) * bodyPart.Size.X
      local y = rng:NextNumber(-0.34, 0.34) * bodyPart.Size.Y
      local z = (rng:NextNumber() < 0.5 and -1 or 1) * bodyPart.Size.Z * 0.48
      local radius = rng:NextNumber(GROWTH_MIN, GROWTH_MAX)
      local scale = Vector3.new(radius, radius * rng:NextNumber(0.8, 1.25), radius)
      makeGrowth(character, bodyPart, scale, Vector3.new(x, y, z))
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

local function makeBackTendril(character, root)
  local folder = Instance.new("Folder")
  folder.Name = "ParasiteBackTendril"
  folder.Parent = character

  local segments = {}
  for index = 1, TENDRIL_SEGMENTS do
    local part = Instance.new("Part")
    part.Name = "BackVineSegment"
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.SmoothPlastic
    part.Color = COLORS[(index % #COLORS) + 1]
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = true
    part.Parent = folder
    table.insert(segments, part)
  end

  local baseBulb = Instance.new("Part")
  baseBulb.Name = "BackVineRoot"
  baseBulb.Shape = Enum.PartType.Ball
  baseBulb.Size = Vector3.new(1.7, 1.8, 1.7)
  baseBulb.Material = Enum.Material.SmoothPlastic
  baseBulb.Color = COLORS[2]
  baseBulb.Anchored = true
  baseBulb.CanCollide = false
  baseBulb.CanTouch = false
  baseBulb.CanQuery = false
  baseBulb.Parent = folder

  local phase = rng:NextNumber(0, math.pi * 2)
  local connection
  connection = RunService.Heartbeat:Connect(function(dt)
    if not character.Parent or not root.Parent or not folder.Parent then
      connection:Disconnect()
      folder:Destroy()
      return
    end

    local origin = root.CFrame:PointToWorldSpace(Vector3.new(0, 1.15, 0.9))
    local target = findNearestUninfected(character, origin)
    local direction

    if target then
      direction = target.Position - origin
    else
      direction = root.CFrame.LookVector
    end

    if direction.Magnitude < 0.05 then
      direction = root.CFrame.LookVector
    end
    direction = direction.Unit

    phase += dt * 1.8
    local sway = math.sin(phase) * 0.35
    local side = direction:Cross(Vector3.yAxis)
    if side.Magnitude < 0.05 then
      side = root.CFrame.RightVector
    end
    side = side.Unit

    local endPosition = origin + direction * TENDRIL_LENGTH
      + Vector3.new(0, 1.0 + sway, 0)
    local control = origin + direction * (TENDRIL_LENGTH * 0.48)
      + Vector3.new(0, 2.1 + sway, 0) + side * sway

    baseBulb.Position = origin
    baseBulb.CFrame = CFrame.new(origin)

    for index, part in ipairs(segments) do
      local alpha = (index - 0.5) / TENDRIL_SEGMENTS
      local inverse = 1 - alpha
      local position = origin * (inverse * inverse)
        + control * (2 * inverse * alpha)
        + endPosition * (alpha * alpha)
      local tangent = (control - origin):Lerp(endPosition - control, alpha)
      if tangent.Magnitude < 0.05 then tangent = direction end
      local radius = 0.72 - alpha * 0.43
      local length = TENDRIL_LENGTH / TENDRIL_SEGMENTS * 1.55
      part.Size = Vector3.new(length, radius * 2, radius * 2)
      part.CFrame = CFrame.lookAt(position, position + tangent.Unit)
    end
  end)

  return folder
end

local function addProceduralAnimation(character, humanoid, root)
  local rootJoint = nil
  for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("Motor6D") and (item.Name == "RootJoint" or item.Name == "Root") then
      rootJoint = item
      break
    end
  end
  if not rootJoint then return end

  local baseC0 = rootJoint.C0
  local startTime = os.clock()
  local connection
  connection = RunService.Heartbeat:Connect(function()
    if not character.Parent or humanoid.Health <= 0 or not rootJoint.Parent then
      connection:Disconnect()
      return
    end

    local elapsed = os.clock() - startTime
    local moving = humanoid.MoveDirection.Magnitude > 0.08
    local speed = moving and 8.5 or 2.1
    local bob = math.sin(elapsed * speed) * (moving and 0.075 or 0.025)
    local lean = moving and 0.12 or 0.035
    local roll = math.sin(elapsed * (moving and 4.25 or 1.05)) * 0.035

    rootJoint.C0 = baseC0
      * CFrame.new(0, bob, 0)
      * CFrame.Angles(lean, 0, roll)
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
  addBodyGrowths(character)
  makeBackTendril(character, root)
  addProceduralAnimation(character, humanoid, root)
end

event.Event:Connect(function(character, player)
  transformCharacter(character, player)
end)

print("[PARASITE] Transformation system ready.")
