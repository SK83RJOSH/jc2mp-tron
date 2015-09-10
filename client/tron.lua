class "Tron"

function Tron:__init()
	self.state = GamemodeState.WAITING
	self.inLobby = false
	self.queue = {}
	self.queueMin = 0
	self.queueMax = 0
	self.spec = {
		listOffset = 1,
		player = false,
		angle = Angle(),
		zoom = 1
	}
	self.collisionFired = false
	self.timer = Timer()
	self.blockedActions = {Action.StuntJump, Action.StuntposEnterVehicle, Action.ParachuteOpenClose, Action.ExitVehicle, Action.EnterVehicle, Action.UseItem}
	self.segments = {}

	Network:Subscribe("EnterLobby", self, self.EnterLobby)
	Network:Subscribe("StateChange", self, self.StateChange)
	Network:Subscribe("UpdateQueue", self, self.UpdateQueue)
	Network:Subscribe("ExitLobby", self, self.ExitLobby)

	Events:Subscribe("CalcView", self, self.CalcView)
	Events:Subscribe("LocalPlayerExitVehicle", self, self.LocalPlayerExitVehicle)
	Events:Subscribe("InputPoll", self, self.InputPoll)
	Events:Subscribe("LocalPlayerInput", self, self.LocalPlayerInput)
	Events:Subscribe("LocalPlayerWorldChange", self, self.LocalPlayerWorldChange)
	Events:Subscribe("PlayerNetworkValueChange", self, self.PlayerNetworkValueChange)
	Events:Subscribe("EntityDespawn", self, self.EntityDespawn)
	Events:Subscribe("PreTick", self, self.PreTick)
	Events:Subscribe("Render", self, self.Render)
	Events:Subscribe("GameRender", self, self.GameRender)
end

function Tron:AddSegment(segments, segment)
	segment.time = self.timer:GetSeconds()

	table.insert(segments, segment)

	if #segments > 8 then
		table.remove(segments, 1)
	end
end

function DrawCenteredShadowedText(position, text, color, textsize)
	local textsize = textsize or TextSize.Default
	local bounds = Render:GetTextSize(text, textsize)

	if not IsNaN(position) then
		Render:DrawText(position - (bounds / 2) + (Vector2.One * math.max(textsize / 32, 1)), text, Color.Black, textsize)
		Render:DrawText(position - (bounds / 2), text, color, textsize)
	end
end

function Tron:EnterLobby(args)
	self.inLobby = true
	self.state = GamemodeState.WAITING
	self.queue = {}
	self.queueMin = 0
	self.queueMax = 0
	self.spec = {
		listOffset = 1,
		player = false,
		angle = Angle(),
		zoom = 1
	}
	self.collisionFired = false
end

function Tron:StateChange(args)
	self.state = args.state
	self.stateArgs = args.stateArgs

	if self.state > GamemodeState.PREPARING and self.state < GamemodeState.ENDING then
		self.timer:Restart()
	end
end

function Tron:UpdateQueue(args)
	self.position = args.position
	self.maxRadius = args.maxRadius
	self.queue = args.queue
	self.queueMin = args.min
	self.queueMax = args.max
end

function Tron:ExitLobby(args)
	Game:FireEvent("ply.vulnerable")
	self.inLobby = false
end

function Tron:CalcView(args)
	if not self.inLobby then return end

	if self.state == GamemodeState.INPROGRESS then
		if not LocalPlayer:InVehicle() then
			local players = {}

			for player in Client:GetPlayers() do
				if player:GetWorld() == LocalPlayer:GetWorld() and player:InVehicle() then
					table.insert(players, player)
				end
			end

			if #players > 0 then
				self.spec.listOffset = self.spec.listOffset >= 0 and self.spec.listOffset % #players or #players + self.spec.listOffset

				local player = players[self.spec.listOffset + 1]

				if self.spec.player and IsValid(self.spec.player) and player ~= self.spec.player then
					self.spec.listOffset = table.find(players, self.spec.player)

					if self.spec.listOffset then
						self.spec.listOffset = self.spec.listOffset - 1
					else
						self.spec.listOffset = 0
					end
				elseif not self.spec.player or not IsValid(self.spec.player) then
					self.spec.player = player
				end

				local position = player:GetPosition()
				local targetPosition = position - ((Angle(player:GetAngle().yaw, 0, 0) * self.spec.angle) * ((Vector3.Forward * 40) + (Vector3.Up * 15)))
				local direction = targetPosition - player:GetPosition()
				local length = direction:Length() * self.spec.zoom
				local raycast = Physics:Raycast(position, direction:Normalized(), 2, length)
				local distance = IsNaN(raycast.distance) or raycast.distance == length and length or raycast.distance - 0.1

				Camera:SetPosition(position + (direction:Normalized() * distance))

				local angle = Angle.FromVectors(Vector3.Forward, position - Camera:GetPosition())

				if not IsNaN(angle) then
					angle.roll = 0 -- Fucking I hate angles and Jman100 also TheStatPow
					Camera:SetAngle(angle)
				end
			end

			return false
		end
	end
end

function Tron:InputPoll(args)
	if not self.inLobby then return end

	if self.state == GamemodeState.INPROGRESS then
		if LocalPlayer:InVehicle() and LocalPlayer:GetVehicle():GetHealth() == 0 then
			-- Force the player out
			Input:SetValue(Action.UseItem, 1)
			Input:SetValue(Action.ExitVehicle, 1)
		elseif LocalPlayer:InVehicle() then
			-- Tweak controls
			Input:SetValue(Action.Accelerate, math.max(0.65, Input:GetValue(Action.Accelerate)))

			if LocalPlayer:GetVehicle():GetLinearVelocity():Length() < 10 then
				Input:SetValue(Action.Reverse, 0)
			end

			Input:SetValue(Action.Handbrake, 0)
		end
	elseif self.state == GamemodeState.PREPARING or self.state == GamemodeState.COUNTDOWN then
		Input:SetValue(Action.Handbrake, 1)
	end
end

function Tron:LocalPlayerInput(args)
	if not self.inLobby then return end

	local gamepad = Game:GetSetting(GameSetting.GamepadInUse) == 1

	if self.state == GamemodeState.PREPARING or self.state == GamemodeState.COUNTDOWN then
		return false
	elseif self.state == GamemodeState.INPROGRESS then
		if table.find(self.blockedActions, args.input) then
			return false
		elseif LocalPlayer:InVehicle() then
			local toggleAction = gamepad and Action.ZoomIn or Action.FireLeft

			if args.input == toggleAction and Input:GetValue(toggleAction) == 0 then
				Network:Send("Firing", {TronFiring = not LocalPlayer:GetValue("TronFiring")})
			end
		else
			if Input:GetValue(args.input) == 0 then
				if args.input == Action.FireLeft then
					self.spec.listOffset = self.spec.listOffset - 1
					self.spec.player = false
				elseif args.input == Action.FireRight then
					self.spec.listOffset = self.spec.listOffset + 1
					self.spec.player = false
				end
			end

			local sensitivity = {
				x = (Game:GetSetting(gamepad and GameSetting.GamepadSensitivityX or GameSetting.MouseSensitivityX) * (Game:GetSetting(gamepad and GameSetting.GamepadInvertX or GameSetting.MouseInvertX) and -1 or 1)) / 100 / (math.pi * 2),
				y = (Game:GetSetting(gamepad and GameSetting.GamepadSensitivityY or GameSetting.MouseSensitivityY) * (Game:GetSetting(gamepad and GameSetting.GamepadInvertY or GameSetting.MouseInvertY) and -1 or 1)) / 100 / (math.pi * 2)
			}

			if args.input == Action.LookLeft then
				self.spec.angle.yaw = self.spec.angle.yaw - (args.state * sensitivity.x)
			elseif args.input == Action.LookRight then
				self.spec.angle.yaw = self.spec.angle.yaw + (args.state * sensitivity.x)
			elseif args.input == Action.LookDown then
				self.spec.angle.pitch = self.spec.angle.pitch - (args.state * sensitivity.y)
			elseif args.input == Action.LookUp then
				self.spec.angle.pitch = self.spec.angle.pitch + (args.state * sensitivity.y)
			end

			if gamepad then
				if args.input == Action.MoveForward then
					self.spec.zoom = self.spec.zoom + (args.state * sensitivity.y)
				elseif args.input == Action.MoveBackward then
					self.spec.zoom = self.spec.zoom - (args.state * sensitivity.y)
				end
			else
				if args.input == Action.NextWeapon then
					self.spec.zoom = self.spec.zoom + 0.1
				elseif args.input == Action.PrevWeapon then
					self.spec.zoom = self.spec.zoom - 0.1
				end
			end

			self.spec.zoom = math.clamp(self.spec.zoom, 0.15, 1.5)
			self.spec.angle.pitch = math.clamp(self.spec.angle.pitch, -1.5, -0.4)
		end
	end
end

function Tron:LocalPlayerExitVehicle(args)
	if not self.inLobby then return end

	if self.state == GamemodeState.INPROGRESS and not self.collisionFired then
		Network:Send("Collision", {
			vehicle = args.vehicle,
			fell = true
		})
		self.collisionFired = true
	end
end

function Tron:LocalPlayerWorldChange(args)
	if args.new_world == DefaultWorld and self.inLobby then
		self:ExitLobby()
	end
end

function Tron:PlayerNetworkValueChange(args)
	if args.value == true and args.key == "TronFiring" and args.player:InVehicle() and self.segments[args.player:GetVehicle():GetId()] then
		local point = Point(args.player:GetVehicle():GetPosition() - args.player:GetVehicle():GetAngle() * Vector3.Forward * 1.5, args.player:GetVehicle():GetAngle())
		local segment = self.segments[args.player:GetVehicle():GetId()][#self.segments[args.player:GetVehicle():GetId()]]

		if segment then
			self:AddSegment(self.segments[args.player:GetVehicle():GetId()], LineSegment(point, point, segment.height, segment.color))
		end
	end
end

function Tron:EntityDespawn(args)
	if args.entity.__type == "Vehicle" then
		self.segments[args.entity:GetId()] = nil
	end
end

function Tron:PreTick(args)
	if not self.inLobby then return end

	if self.state == GamemodeState.INPROGRESS then
		Game:FireEvent("ply.invulnerable")

		local players = {LocalPlayer}

		for player in Client:GetPlayers() do
			table.insert(players, player)
		end

		for k, player in ipairs(players) do
			if IsValid(player) and player:InVehicle() and IsValid(player:GetVehicle()) and player == player:GetVehicle():GetDriver() then
				local vehicle = player:GetVehicle()

				if not self.segments[vehicle:GetId()] then
					self.segments[vehicle:GetId()] = {}
				end
			end
		end

		for k, segments in pairs(self.segments) do
			local vehicle = Vehicle.GetById(k)

			if IsValid(vehicle) then
				local point = Point(vehicle:GetPosition() - vehicle:GetAngle() * Vector3.Forward * 1.5, vehicle:GetAngle())
				local height = 1
				local color = Color(vehicle:GetColors().r, vehicle:GetColors().g, vehicle:GetColors().b, 100)

				if (#segments == 0 or segments[#segments]:Length() > 10) and vehicle:GetDriver() and vehicle:GetDriver():GetValue("TronFiring") then
					self:AddSegment(segments, LineSegment(segments[#segments] and segments[#segments].endPoint or point, point, height, color))
				end

				for k, segment in ipairs(segments) do
					if k == #segments and vehicle:GetDriver() and vehicle:GetDriver():GetValue("TronFiring") then
						segment.endPoint = point
					end

					if LocalPlayer:InVehicle() and IsValid(LocalPlayer:GetVehicle()) and LocalPlayer:GetVehicle():GetDriver() == LocalPlayer then
						if LocalPlayer:GetVehicle() ~= vehicle or k < #segments then
							local pVehicle = LocalPlayer:GetVehicle()
							local startPoint = Point(pVehicle:GetPosition() - pVehicle:GetAngle() * Vector3.Forward * 1.5, pVehicle:GetAngle())
							local endPoint = Point(pVehicle:GetPosition() + pVehicle:GetAngle() * Vector3.Forward * 1.5, pVehicle:GetAngle())

							if segment:Intersects(LineSegment(startPoint, endPoint, height, color)) then
								if not self.collisionFired then
									Network:Send("Collision", {
										vehicle = pVehicle,
										killer = vehicle:GetDriver()
									})

									self.collisionFired = true
									self.spec.player = vehicle:GetDriver()
								end
							end
						end
					end

					if self.timer:GetSeconds() - segment.time > 30 then
						table.remove(segments, k)
					end
				end
			end
		end

		if LocalPlayer:InVehicle() then
			local vehicle = LocalPlayer:GetVehicle()
			local distance = LocalPlayer:GetPosition():Distance(self.stateArgs.position)

			if vehicle:GetLinearVelocity():Length() > 8 and distance <= self.stateArgs.maxRadius then
				self.timer:Restart()
			end

			if self.timer:GetSeconds() > 5 and not self.collisionFired then
				Network:Send("Collision", {
					vehicle = vehicle
				})
				self.collisionFired = true
			end
		end
	end
end

function Tron:Render(args)
	if not self.inLobby or Game:GetState() ~= GUIState.Game then return end

	local gamepad = Game:GetSetting(GameSetting.GamepadInUse) == 1

	if self.state == GamemodeState.WAITING then
		local playersNeeded = math.max(self.queueMin - #self.queue, 0)

		DrawCenteredShadowedText(Vector2(Render.Width / 2, 70), #self.queue .. ' / ' .. self.queueMax, Color.Yellow, TextSize.Large)

		if playersNeeded > 0 then
			DrawCenteredShadowedText(Vector2(Render.Width / 2, 70 + TextSize.Large), '(' .. playersNeeded .. ' more player' .. (playersNeeded ~= 1 and 's needed)' or ' needed)'), Color.Yellow, TextSize.Large)
		end

		if self.queue then
			for k, player in ipairs(self.queue) do
				DrawCenteredShadowedText(Vector2(Render.Width - 75, Render.Height - 75 - (k * 20)), player:GetName(), player:GetColor())
			end

			DrawCenteredShadowedText(Vector2(Render.Width - 75, Render.Height - 75 - ((#self.queue + 1) * 20)), "Current Queue", Color.White, 20)
		end
	elseif self.state == GamemodeState.PREPARING then
		DrawCenteredShadowedText(Vector2(Render.Width / 2, 70), "Waiting for other players...", Color.Yellow, TextSize.Huge)
	elseif self.state == GamemodeState.COUNTDOWN then
		DrawCenteredShadowedText(Vector2(Render.Width / 2, 70), math.max(math.ceil(3 - self.timer:GetSeconds()), 1) .. "...", Color.Yellow, TextSize.Huge)
	elseif self.state == GamemodeState.INPROGRESS then

		if LocalPlayer:InVehicle() then
			if gamepad then
				DrawCenteredShadowedText(Vector2(Render.Width / 2, Render.Height - 35), "Press RB to toggle your trail! Last player alive wins!", Color.Yellow)
			else
				DrawCenteredShadowedText(Vector2(Render.Width / 2, Render.Height - 35), "Right-click to toggle your trail! Last player alive wins!", Color.Yellow)
			end
		else
			if gamepad then
				DrawCenteredShadowedText(Vector2(Render.Width / 2, Render.Height - 35), "You died. Press left and right triggers to change who you're spectating!", Color.Yellow)
			else
				DrawCenteredShadowedText(Vector2(Render.Width / 2, Render.Height - 35), "You died. Press left and right click to change who you're spectating!", Color.Yellow)
			end
		end

		if LocalPlayer:InVehicle() then
			local distance = LocalPlayer:GetPosition():Distance(self.stateArgs.position)

			if self.timer:GetSeconds() > 2 and distance < self.stateArgs.maxRadius then
				DrawCenteredShadowedText(Render.Size / 2, "Self-destruct in " .. math.max(math.ceil(5 - self.timer:GetSeconds()), 1) .. "...", Color.Red, TextSize.Huge)
			elseif self.timer:GetSeconds() > 0 and distance >= self.stateArgs.maxRadius then
				DrawCenteredShadowedText(Render.Size / 2, "Out of bounds " .. math.max(math.ceil(5 - self.timer:GetSeconds()), 1) .. "...", Color.Red, TextSize.Huge)
			end
		end

		if not LocalPlayer:InVehicle() then
			for player in Client:GetPlayers() do
				if player:InVehicle() then
					local position, visible = Render:WorldToScreen(player:GetPosition())
					local vehicle = player:GetVehicle()

					if visible then
						local color1, color2 = vehicle:GetColors()
						DrawCenteredShadowedText(position, player:GetName(), color1)
					end
				end
			end
		end
	end

	if self.state >= GamemodeState.PREPARING and self.state <= GamemodeState.ENDING then
		local players = {LocalPlayer}

		for player in Client:GetPlayers() do
			if player:GetWorld() == LocalPlayer:GetWorld() then
				table.insert(players, player)
			end
		end

		for k, player in ipairs(players) do
			local color = self.state ~= GamemodeState.PREPARING and Color.Black or Color.Gray

			if player:InVehicle() then
				color = player:GetVehicle():GetColors()
			end

			DrawCenteredShadowedText(Vector2(Render.Width - 75, Render.Height - 75 - (k * 20)), player:GetName(), color)
		end

		DrawCenteredShadowedText(Vector2(Render.Width - 75, Render.Height - 75 - ((#players + 1) * 20)), "Players", Color.White, 20)
	end
end

function Tron:GameRender()
	if self.state == GamemodeState.INPROGRESS then
		for k, segments in pairs(self.segments) do
			for k, segment in ipairs(segments) do
				segment:Render()
			end
		end
	end
end

Tron()
