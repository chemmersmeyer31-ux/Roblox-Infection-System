-- CRAWLER INFESTATION - PHASE 2
-- Place this Script in ServerScriptService alongside InfectionSystem.lua.
-- Requires Workspace.InfectionSpawner and the Workspace.InfectionStage attribute.
-- Crawlers remain legs-only. Phase 2 is still visual/stalking only:
-- no damage, infection, transformation, or character control.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local infectionSpawner = workspace:WaitForChild("InfectionSpawner")
local rng = Random.new()

local COLORS = {
    dark = Color3.fromRGB(70, 35, 29),
    seed = Color3.fromRGB(112, 57, 39),
    ridge = Color3.fromRGB(139, 75, 49),
}

local MAX_CRAWLERS = {[3] = 2, [4] = 5, [5] = 9}
local HATCH_INTERVAL = {[3] = 38, [4] = 24, [5] = 15}
local CRAWLER_LIFETIME = 150

-- AI tuning
local DETECT_DISTANCE = 48
local FORGET_AFTER = 7
local STALK_DISTANCE = 13
local APPROACH_DISTANCE = 7
local LEAP_DISTANCE = 6
local WALK_SPEED = 2.0
local STALK_SPEED = 2.5
local APPROACH_SPEED = 3.0
local RETREAT_SPEED = 3.4

local folder = workspace:FindFirstChild("CrawlerInfestation")
if folder then
    folder:Destroy()
end
folder = Instance.new("Folder")
folder.Name = "CrawlerInfestation"
folder.Parent = workspace

local function currentStage()
    return workspace:GetAttribute("InfectionStage") or 1
end

local function makePart(parent, name, shape, size, color)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = shape
    part.Size = size
    part.Color = color
    part.Material = Enum.Material.CorrodedMetal
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function placeRod(part, a, b, thickness)
    local delta = b - a
    if delta.Magnitude < 0.025 then
        part.Transparency = 1
        return
    end

    local axis = delta.Unit
    local up = Vector3.yAxis - axis * axis.Y
    if up.Magnitude < 0.04 then
        up = Vector3.xAxis - axis * axis.X
    end
    up = up.Unit
    local side = axis:Cross(up).Unit

    part.Transparency = 0
    part.Size = Vector3.new(delta.Magnitude, thickness, thickness)
    part.CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, up, side)
end

local function makeIgnoreList(extra)
    local ignore = {folder}
    if extra then
        table.insert(ignore, extra)
    end
    return ignore
end

local function raycast(origin, direction, extraIgnore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = makeIgnoreList(extraIgnore)
    params.IgnoreWater = true
    return workspace:Raycast(origin, direction, params)
end

local function getCharacterParts(player)
    local character = player.Character
    if not character then
        return nil, nil, nil
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local torso = character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or root

    if root and humanoid and humanoid.Health > 0 then
        return character, root, torso
    end
    return nil, nil, nil
end

local function canSeeTarget(origin, character, torso)
    if not character or not torso then
        return false
    end

    local direction = torso.Position - origin
    if direction.Magnitude < 0.1 then
        return true
    end

    -- Ignore the target character so a clear ray means there is no wall
    -- or solid obstacle between the crawler and the player.
    local hit = raycast(origin, direction, character)
    return hit == nil
end

local function findGround(position)
    local hit = raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0))
    if hit then
        return hit.Position + hit.Normal * 0.32, hit.Normal
    end
    return position + Vector3.new(0, 0.4, 0), Vector3.yAxis
end

local function nearestVisiblePlayer(position)
    local best
    local bestDistance = DETECT_DISTANCE

    for _, player in ipairs(Players:GetPlayers()) do
        local character, root, torso = getCharacterParts(player)
        if root and torso then
            local distance = (root.Position - position).Magnitude
            if distance < bestDistance and canSeeTarget(position, character, torso) then
                best = {
                    player = player,
                    character = character,
                    root = root,
                    torso = torso,
                    distance = distance,
                }
                bestDistance = distance
            end
        end
    end

    return best
end

local function tangentDirection(direction, normal)
    local tangent = direction - normal * direction:Dot(normal)
    if tangent.Magnitude < 0.05 then
        tangent = normal:Cross(Vector3.xAxis)
        if tangent.Magnitude < 0.05 then
            tangent = normal:Cross(Vector3.zAxis)
        end
    end
    return tangent.Unit
end

local function steerOnSurface(position, normal, desiredDirection, distance, ignoreCharacter)
    -- On vertical surfaces, bias movement upward so the crawler actually climbs
    -- instead of endlessly walking sideways or losing its tangent direction.
    local desired = desiredDirection
    if math.abs(normal.Y) < 0.65 then
        desired = desired + Vector3.yAxis * 0.8
    end
    local direction = tangentDirection(desired, normal)
    local probeOrigin = position + normal * 0.42
    local obstacle = raycast(probeOrigin, direction * 1.65, ignoreCharacter)

    if obstacle then
        local wallNormal = obstacle.Normal.Unit
        -- A near-vertical obstacle is a climbable face. Attach to it, then
        -- continue upward along its surface rather than steering away.
        if math.abs(wallNormal.Y) < 0.65 and wallNormal:Dot(normal) < 0.82 then
            local attached = obstacle.Position + wallNormal * 0.3
            return attached, wallNormal, Vector3.yAxis
        end

        -- Otherwise slide around the obstruction.
        local slideA = tangentDirection(obstacle.Normal, normal)
        local slideB = -slideA
        local hitA = raycast(probeOrigin, slideA * 1.25, ignoreCharacter)
        local hitB = raycast(probeOrigin, slideB * 1.25, ignoreCharacter)
        if not hitA then
            direction = slideA
        elseif not hitB then
            direction = slideB
        else
            direction = -direction
        end
    end

    local proposed = position + direction * distance
    local surface = raycast(proposed + normal * 1.3, -normal * 3.8, ignoreCharacter)
    if surface then
        return surface.Position + surface.Normal * 0.3, surface.Normal.Unit, direction
    end

    -- At the top of a wall, look down for the ledge's upper surface and step onto it.
    if math.abs(normal.Y) < 0.65 then
        local topSurface = raycast(proposed + Vector3.yAxis * 1.25,
            -Vector3.yAxis * 3.2, ignoreCharacter)
        if topSurface and topSurface.Normal.Y > 0.55 then
            return topSurface.Position + topSurface.Normal * 0.3,
                topSurface.Normal.Unit, tangentDirection(direction, topSurface.Normal)
        end
    end

    -- At a floor edge, check for a nearby vertical face to climb.
    local forwardFace = raycast(position + normal * 0.35, direction * 1.8, ignoreCharacter)
    if forwardFace and math.abs(forwardFace.Normal.Y) < 0.65 then
        return forwardFace.Position + forwardFace.Normal * 0.3,
            forwardFace.Normal.Unit, Vector3.yAxis
    end

    local turn = tangentDirection(normal:Cross(direction), normal)
    local alternate = position + turn * distance
    local alternateSurface = raycast(alternate + normal * 1.3, -normal * 3.8, ignoreCharacter)
    if alternateSurface then
        return alternateSurface.Position + alternateSurface.Normal * 0.3,
            alternateSurface.Normal.Unit, turn
    end

    return position, normal, direction
end

local function makeCrawler(startPosition, startNormal)
    local model = Instance.new("Model")
    model.Name = "LegsOnlyCrawler"
    model.Parent = folder

    local centerPart = makePart(model, "LegAttachmentPoint", Enum.PartType.Ball,
        Vector3.new(0.13, 0.13, 0.13), COLORS.dark)
    centerPart.Transparency = 0.12

    local legs = {}
    for i = 1, 8 do
        legs[i] = {
            a = makePart(model, "LegRoot" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.dark),
            b = makePart(model, "LegOuter" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.seed),
            joint = makePart(model, "LegJoint" .. i, Enum.PartType.Ball,
                Vector3.new(0.18, 0.18, 0.18), COLORS.ridge),
            claw = makePart(model, "LegClaw" .. i, Enum.PartType.Cylinder, Vector3.one, COLORS.dark),
            angle = (i - 1) * math.pi / 4,
            length = rng:NextNumber(0.88, 1.18),
        }
    end

    local position = startPosition
    local normal = startNormal.Unit
    local forward = tangentDirection(Vector3.xAxis, normal)

    local born = os.clock()
    local state = "roam"
    local stateUntil = 0
    local nextDecision = born + rng:NextNumber(1.5, 3.5)
    local nextLeap = born + rng:NextNumber(12, 22)
    local nextStalkShift = born + rng:NextNumber(3, 6)
    local stalkSide = rng:NextNumber() < 0.5 and -1 or 1
    local wanderDirection = forward
    local targetInfo = nil
    local lastKnownPosition = nil
    local lastSeenAt = 0
    local leapStart = nil
    local leapGoal = nil
    local leapStarted = 0
    local leapDuration = 0.48
    local clingStarted = 0
    local clingDuration = 4.2
    local clingSide = 1
    local retreatDirection = forward
    local connection

    local function setState(newState, duration)
        state = newState
        stateUntil = os.clock() + (duration or 0)
    end

    local function updateTarget()
        local visible = nearestVisiblePlayer(position)
        if visible then
            targetInfo = visible
            lastKnownPosition = visible.root.Position
            lastSeenAt = os.clock()
            return visible
        end

        if targetInfo then
            local character, root, torso = getCharacterParts(targetInfo.player)
            if root and torso then
                targetInfo.character = character
                targetInfo.root = root
                targetInfo.torso = torso
                targetInfo.distance = (root.Position - position).Magnitude
            else
                targetInfo = nil
            end
        end

        if os.clock() - lastSeenAt > FORGET_AFTER then
            targetInfo = nil
        end
        return nil
    end

    connection = RunService.Heartbeat:Connect(function(dt)
        if not model.Parent then
            connection:Disconnect()
            return
        end

        local now = os.clock()
        if now - born > CRAWLER_LIFETIME or currentStage() < 3 then
            model:Destroy()
            connection:Disconnect()
            return
        end

        local visibleTarget = updateTarget()
        local activeTarget = targetInfo
        local targetRoot = activeTarget and activeTarget.root
        local targetTorso = activeTarget and activeTarget.torso
        local targetDistance = targetRoot and (targetRoot.Position - position).Magnitude or math.huge
        local ignoreCharacter = activeTarget and activeTarget.character
        local escortReference = workspace:FindFirstChild("InfectionBulbReference")
        local escortBulb = escortReference and escortReference:IsA("ObjectValue") and escortReference.Value
        local escortActive = currentStage() == 4
            and workspace:GetAttribute("StageFourRelocating") == true
            and escortBulb and escortBulb:IsA("BasePart")
        local escortSlot = model:GetAttribute("EscortSlot")
        if state == "escort" and not escortActive then
            setState("roam", rng:NextNumber(2, 4))
        end

        -- Escorts resume formation whenever they are not responding to a visible player.
        if escortActive and not visibleTarget and state ~= "leap"
            and state ~= "cling" and state ~= "retreat" then
            state = "escort"
            targetInfo = nil
            lastKnownPosition = nil
        elseif visibleTarget and state == "escort" then
            setState("stalk", rng:NextNumber(2.5, 4.5))
        end

        -- Recover cleanly if the player resets or disappears during a leap/cling.
        if state == "leap" and (not targetRoot or not targetTorso) then
            setState("investigate", 1.5)
        elseif state == "cling" and (not targetRoot or not targetTorso) then
            stateUntil = now
        end

        if state == "cling" and targetRoot and targetTorso and now < stateUntil then
            local progress = math.clamp((now - clingStarted) / clingDuration, 0, 1)
            local orbit = math.sin(progress * math.pi * 2) * 0.18
            local localOffset = Vector3.new(
                clingSide * (0.55 + orbit),
                0.15 + progress * 0.58,
                -0.28 + math.cos(progress * math.pi * 2) * 0.12
            )
            position = targetTorso.CFrame:PointToWorldSpace(localOffset)
            normal = targetTorso.CFrame.RightVector * clingSide
            forward = targetTorso.CFrame.LookVector
        elseif state == "leap" and targetRoot and targetTorso then
            local alpha = math.clamp((now - leapStarted) / leapDuration, 0, 1)
            local eased = alpha * alpha * (3 - 2 * alpha)
            position = leapStart:Lerp(leapGoal, eased)
            normal = (targetTorso.Position - position).Magnitude > 0.05
                and (position - targetTorso.Position).Unit or Vector3.yAxis
            forward = targetTorso.CFrame.LookVector

            if alpha >= 1 then
                clingStarted = now
                clingDuration = rng:NextNumber(1.6, 2.4)
                stateUntil = now + clingDuration
                clingSide = rng:NextNumber() < 0.5 and -1 or 1
                state = "cling"
            end
        elseif state == "retreat" then
            -- The crawler must detach from the avatar before surface steering:
            -- otherwise its raycasts can leave it stranded at the face/torso.
            local groundHit = raycast(position + Vector3.yAxis * 1.5,
                -Vector3.yAxis * 80, ignoreCharacter)
            if groundHit then
                local groundPosition = groundHit.Position + groundHit.Normal * 0.3
                local delta = groundPosition - position
                local step = math.min(delta.Magnitude, RETREAT_SPEED * 2.2 * math.min(dt, 0.08))
                if delta.Magnitude > 0.05 then
                    position = position + delta.Unit * step
                end
                if delta.Magnitude < 0.8 then
                    normal = groundHit.Normal.Unit
                end
            else
                position = position - Vector3.yAxis * (RETREAT_SPEED * math.min(dt, 0.08))
            end
            if now >= stateUntil then
                targetInfo = nil
                targetRoot = nil
                targetTorso = nil
                normal = Vector3.yAxis
                setState("roam", rng:NextNumber(2, 4))
            end
        else
            -- A visible player refreshes memory. A hidden player is investigated
            -- at their last known position for a short time.
            if visibleTarget then
                if state == "roam" or state == "investigate" then
                    setState("stalk", rng:NextNumber(2.5, 4.5))
                end
            elseif targetInfo and lastKnownPosition then
                if state ~= "investigate" and state ~= "approach" then
                    setState("investigate", FORGET_AFTER)
                end
            end

            if state == "escort" and escortActive then
                -- Slot 1 scouts ahead; slot 2 protects the bulb's rear flank.
                local bulbFrame = escortBulb.CFrame
                local slot = escortSlot or 2
                local offset = slot == 1
                    and (bulbFrame.LookVector * 4.2 + bulbFrame.RightVector * 2.0)
                    or (-bulbFrame.LookVector * 3.6 - bulbFrame.RightVector * 2.2)
                local desired = escortBulb.Position + offset
                local verticalGap = math.abs(desired.Y - position.Y)

                -- Stay on the current traversable surface if the bulb is
                -- climbing a wall; regroup when it reaches a nearby floor.
                if verticalGap < 6 then
                    local direction = desired - position
                    if direction.Magnitude > 1.8 then
                        position, normal, forward = steerOnSurface(
                            position, normal, direction, 3.2 * math.min(dt, 0.08), nil
                        )
                    else
                        local orbit = bulbFrame.RightVector * (slot == 1 and 1 or -1)
                        position, normal, forward = steerOnSurface(
                            position, normal, orbit, 0.65 * math.min(dt, 0.08), nil
                        )
                    end
                end

            elseif state == "roam" then
                if now >= nextDecision then
                    local angle = rng:NextNumber(-math.pi, math.pi)
                    local base = tangentDirection(forward, normal)
                    wanderDirection = CFrame.fromAxisAngle(normal, angle):VectorToWorldSpace(base)
                    nextDecision = now + rng:NextNumber(2, 4.5)
                end
                position, normal, forward = steerOnSurface(
                    position, normal, wanderDirection, WALK_SPEED * math.min(dt, 0.08), nil
                )

            elseif state == "investigate" then
                if not lastKnownPosition or now - lastSeenAt > FORGET_AFTER then
                    targetInfo = nil
                    setState("roam", rng:NextNumber(2, 4))
                else
                    local direction = lastKnownPosition - position
                    if direction.Magnitude > 2.5 then
                        position, normal, forward = steerOnSurface(
                            position, normal, direction, STALK_SPEED * math.min(dt, 0.08), ignoreCharacter
                        )
                    elseif visibleTarget then
                        setState("stalk", rng:NextNumber(2, 4))
                    else
                        setState("roam", rng:NextNumber(2, 4))
                    end
                end

            elseif state == "stalk" or state == "approach" then
                if not targetRoot then
                    setState("investigate", FORGET_AFTER)
                elseif not visibleTarget and now - lastSeenAt > 1.5 then
                    setState("investigate", FORGET_AFTER)
                else
                    if now >= nextStalkShift then
                        stalkSide = -stalkSide
                        nextStalkShift = now + rng:NextNumber(3, 6)
                    end

                    if state == "stalk" then
                        local side = targetRoot.CFrame.RightVector * stalkSide
                        local behind = -targetRoot.CFrame.LookVector * 3
                        local desired = targetRoot.Position + side * 7 + behind
                        local direction = desired - position

                        if targetDistance < 8.5 then
                            -- Hold nearby and circle rather than immediately leaping.
                            direction = side
                        end

                        position, normal, forward = steerOnSurface(
                            position, normal, direction, STALK_SPEED * math.min(dt, 0.08), ignoreCharacter
                        )

                        if targetDistance > 22 and visibleTarget then
                            setState("approach", rng:NextNumber(1.5, 3))
                        elseif targetDistance <= APPROACH_DISTANCE and now >= nextLeap then
                            state = "approach"
                        elseif now >= stateUntil then
                            -- Pause and observe before choosing another movement.
                            setState("stalk", rng:NextNumber(1.5, 3.5))
                            nextStalkShift = now + rng:NextNumber(2, 5)
                        end
                    else
                        if targetDistance > 10 then
                            position, normal, forward = steerOnSurface(
                                position, normal, targetRoot.Position - position,
                                APPROACH_SPEED * math.min(dt, 0.08), ignoreCharacter
                            )
                        elseif targetDistance <= LEAP_DISTANCE and now >= nextLeap and visibleTarget then
                            local torsoCFrame = targetTorso.CFrame
                            local side = rng:NextNumber() < 0.5 and -1 or 1
                            leapStart = position
                            -- Aim for the upper chest/shoulder area, not the face.
                            leapGoal = torsoCFrame:PointToWorldSpace(Vector3.new(side * 0.72, -0.32, -0.38))
                            leapStarted = now
                            leapDuration = rng:NextNumber(0.38, 0.58)
                            nextLeap = now + rng:NextNumber(28, 42)
                            state = "leap"
                        else
                            -- Do not force a leap. Circle and wait for a better opening.
                            local orbitDirection = targetRoot.CFrame.RightVector * stalkSide
                            position, normal, forward = steerOnSurface(
                                position, normal, orbitDirection,
                                1.1 * math.min(dt, 0.08), ignoreCharacter
                            )
                        end
                    end
                end
            end
        end

        -- Occasionally disengage after clinging; this keeps leaps from becoming constant.
        if state == "cling" and now >= stateUntil then
            local away = targetRoot and (position - targetRoot.Position) or -forward
            if away.Magnitude < 0.05 then
                away = -forward
            end
            retreatDirection = tangentDirection(away, normal)
            setState("retreat", rng:NextNumber(1.4, 2.4))
        end

        centerPart.Position = position

        local up = normal.Unit
        local right = forward:Cross(up)
        if right.Magnitude < 0.05 then
            right = up:Cross(Vector3.xAxis)
        end
        if right.Magnitude < 0.05 then
            right = Vector3.xAxis
        end
        right = right.Unit
        forward = up:Cross(right).Unit

        local moving = state == "roam" or state == "investigate"
            or state == "stalk" or state == "approach" or state == "retreat"
        local gaitSpeed = moving and 9 or 5
        for i, leg in ipairs(legs) do
            local angle = leg.angle
            local radial = right * math.cos(angle) + forward * math.sin(angle)
            local phase = now * gaitSpeed + ((i % 2 == 0) and math.pi or 0)
            local stride = moving and math.sin(phase) * 0.19 or math.sin(phase) * 0.045
            local lift = math.max(0, math.cos(phase)) * (moving and 0.14 or 0.055)
            local root = position + radial * 0.06
            local knee = position + radial * (0.85 * leg.length + stride * 0.2) + up * (0.12 + lift)
            local foot = position + radial * (1.65 * leg.length + stride) - up * (0.22 - lift)
            local clawEnd = foot + radial * 0.18 - up * 0.06

            placeRod(leg.a, root, knee, 0.21)
            placeRod(leg.b, knee, foot, 0.15)
            placeRod(leg.claw, foot, clawEnd, 0.085)
            leg.joint.Position = knee
        end
    end)

    return model
end

local function createEgg(position, surfaceNormal)
    local normal = surfaceNormal and surfaceNormal.Unit or Vector3.yAxis
    local egg = makePart(folder, "CrawlerEgg", Enum.PartType.Ball,
        Vector3.new(0.3, 0.43, 0.3), Color3.fromRGB(248, 207, 64))
    egg.Material = Enum.Material.SmoothPlastic
    egg.Position = position - normal * 0.1
    egg.CFrame = CFrame.lookAt(egg.Position, egg.Position + normal)
    egg:SetAttribute("EggReadyToHatch", false)
    return egg
end

local function hatchEgg(egg)
    if not egg or not egg.Parent then return end
    local normal = egg.CFrame.UpVector
    local baseSize = egg.Size
    local start = os.clock()
    local hatchDuration = 3.6
    while egg.Parent and os.clock() - start < hatchDuration do
        local elapsed = os.clock() - start
        local pulse = 1 + math.sin(elapsed * 6.5) * 0.09
        egg.Size = baseSize * pulse
        task.wait(0.08)
    end

    if egg.Parent then
        local spawnPosition = egg.Position + normal * 0.3
        for step = 1, 8 do
            if not egg.Parent then break end
            egg.Size = baseSize * (1 - step / 9)
            egg.Transparency = step / 10
            task.wait(0.045)
        end
        if egg.Parent then egg:Destroy() end
        makeCrawler(spawnPosition, normal)
    end
end

local function countCrawlers()
    local count = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and child.Name == "LegsOnlyCrawler" then
            count += 1
        end
    end
    return count
end

local function ensureStageTwoEggs()
    local eggs = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") and child.Name == "CrawlerEgg" then
            table.insert(eggs, child)
        end
    end
    local desiredEggs = 4
    for index = #eggs + 1, desiredEggs do
        local angle = (index - 1) * (math.pi * 2 / desiredEggs)
        local radius = 2.7 + (index % 2) * 0.8
        local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
        local position, normal = findGround(infectionSpawner.Position + offset)
        createEgg(position, normal)
    end
end

local lastHatch = 0
while script.Parent do
    local current = currentStage()
    local cap = MAX_CRAWLERS[current]

    if current == 2 then
        -- Stage 2 is the egg incubation stage: show the eggs, but do not hatch.
        ensureStageTwoEggs()
    end

    if current == 4 and workspace:GetAttribute("StageFourRelocating") == true then
        local reference = workspace:FindFirstChild("InfectionBulbReference")
        local bulb = reference and reference:IsA("ObjectValue") and reference.Value
        local escorts = {}

        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and child.Name == "LegsOnlyCrawler" then
                table.insert(escorts, child)
            end
        end

        while #escorts < 2 and bulb and bulb:IsA("BasePart") do
            local side = #escorts == 0 and -1 or 1
            local spawnAt = bulb.Position + Vector3.new(side * 4, 0, 2)
            local groundPosition, groundNormal = findGround(spawnAt)
            local escort = makeCrawler(groundPosition, groundNormal)
            table.insert(escorts, escort)
        end

        for index = 1, math.min(#escorts, 2) do
            escorts[index]:SetAttribute("EscortSlot", index)
        end
    end

    if cap and countCrawlers() < cap
        and os.clock() - lastHatch >= HATCH_INTERVAL[current] then

        lastHatch = os.clock()
        local egg
        if current == 3 then
            -- Use the eggs that were already visible throughout Stage 2 first.
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("BasePart") and child.Name == "CrawlerEgg" then
                    egg = child
                    break
                end
            end
        end

        if not egg then
            local angle = rng:NextNumber(0, math.pi * 2)
            local radius = rng:NextNumber(2, 4.5)
            local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            local spawnOrigin = infectionSpawner.Position
            if current == 5 then
                local pointsFolder = workspace:FindFirstChild("StageFiveEggSpawnPoints")
                local points = pointsFolder and pointsFolder:GetChildren() or {}
                local point = #points > 0 and points[rng:NextInteger(1, #points)] or nil
                if point and point:IsA("BasePart") then
                    spawnOrigin = point.Position
                end
            end
            local hatchPosition, hatchNormal = findGround(spawnOrigin + offset)
            egg = createEgg(hatchPosition, hatchNormal)
        end

        task.spawn(hatchEgg, egg)
    end

    task.wait(2)
end
