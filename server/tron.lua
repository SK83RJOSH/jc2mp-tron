class "Tron"

function Tron:__init()
	self.lobbies = {}
	self.admins = {"76561198015337595", "76561198018954954"}

	Chat:Broadcast("Tron v0.5.3 loaded.", Color.Green)

	Events:Subscribe("ModuleUnload", self, self.ModuleUnload)
	Events:Subscribe("PreTick", self, self.PreTick)
	Events:Subscribe("PlayerChat", self, self.PlayerChat)
end

function Tron.SendMessage(player, message, color)
	Chat:Send(player, "[Tron] " .. message, color)
end

function Tron.Broadcast(message, color)
	for player in Server:GetPlayers() do
		Tron.SendMessage(player, message, color)
	end
end

function Tron:ModuleUnload()
	for k, lobby in ipairs(self.lobbies) do
		lobby:Disband()
	end
end

function Tron:PreTick()
	for k, lobby in ipairs(self.lobbies) do
		if lobby:GetState() == GamemodeState.ENDED then
			table.remove(self.lobbies, k)
		end
	end

	if #self.lobbies == 0 then
		table.insert(self.lobbies, Lobby(TronConfig.Maps[math.random(1, #TronConfig.Maps)]))
	end
end

function Tron:PlayerChat(args)
	local player = args.player
	local message = args.text

	if message:sub(0, 1) == "/" then
		local invalidCommand = false
		local args = Utils.GetArgs(message:sub(2))

		if args[1] == "tron" then
			local targetLobby = false

			for k, lobby in ipairs(self.lobbies) do
				if lobby:GetState() == GamemodeState.WAITING and lobby:GetQueue():GetSize() < lobby.maxPlayers then
					if lobby:GetQueue():Contains(player) then
						lobby:RemoveFromQueue(player)
						Tron.SendMessage(player, "You were remove from the " .. lobby.name .. " queue.", Color.Yellow)

						if not args[2] or lobby.name:lower():match(args[2]:lower()) then
							return false
						end
					elseif not targetLobby then
						if not args[2] or lobby.name:lower():match(args[2]:lower()) then
							targetLobby = lobby
						end
					end
				elseif lobby:GetState() > GamemodeState.WAITING then
					for cPlayer in lobby.world:GetPlayers() do
						if player == cPlayer then
							targetLobby = lobby
							break
						end
					end
				end
			end

			if not targetLobby then
				local index = false

				if args[2] then
					for k, map in ipairs(TronConfig.Maps) do
						if map.name:lower():match(args[2]:lower()) then
							index = k
							break
						end
					end
				else
					index = math.random(1, #TronConfig.Maps)
				end

				if index then
					targetLobby = Lobby(TronConfig.Maps[index])
					table.insert(self.lobbies, targetLobby)
				else
					Tron.SendMessage(player, "No map found with the name " .. args[2] .. "!", Color.Red)
					return false
				end
			end

			if targetLobby:GetState() > GamemodeState.WAITING then
				player:SetWorld(DefaultWorld)
			else
				if player:GetWorld() == DefaultWorld then
					targetLobby:AddToQueue(player)
					Tron.SendMessage(player, "You were added to the " .. targetLobby.name .. " queue.", Color.Yellow)
				else
					Tron.SendMessage(player, "Please exit your current gamemode!", Color.Red)
				end
			end
		elseif args[1] == "forcetron" then
			if table.find(self.admins, player:GetSteamId().id) then
				for k, lobby in pairs(self.lobbies) do
					lobby:Disband()
				end

				local config = TronConfig.Maps[math.random(1, #TronConfig.Maps)]

				if not args[2] then
					config.maxPlayers = tonumber(Config:GetValue("Server", "MaxPlayers"))
				else
					local index = math.random(1, #TronConfig.Maps)

					for k, map in ipairs(TronConfig.Maps) do
						if map.name:lower():match(tostring(args[2]):lower()) then
							index = k
							break
						end
					end

					config = TronConfig.Maps[index]
				end

				local lobby = Lobby(config)

				for player in Server:GetPlayers() do
					if player:GetWorld() == DefaultWorld then
						lobby:GetQueue():Add(player)
						Network:Send(player, "EnterLobby")
					end
				end

				lobby.startingTime = lobby.timer:GetSeconds()

				table.insert(self.lobbies, lobby)
			else
				Tron.SendMessage(player, "You don't have permission to do that!", Color.Red)
			end
		elseif args[1] == "tronsave" then
			if not TronConfig.Dev then
				Tron.SendMessage(player, "Dev mode must be enabled perform this operation!", Color.Red)
			else
				local radius = not args[2] and 0 or tonumber(args[2])

				if table.find(self.admins, player:GetSteamId().id) then
					if radius and radius >= 0 then
						local filename = os.time() .. "_" .. player:GetSteamId().id .. "_" .. math.random(999)
						local world = player:GetWorld()
						local header = "position = Vector3(" .. tostring(player:GetPosition() + (Vector3.Up * 2)) .. "),\n"
						local output = "props = {"

						for object in Server:GetStaticObjects() do
							if object:GetWorld() == world and object:GetPosition():Distance(player:GetPosition()) <= radius then
								if #output > 9 then
									output = output .. ","
								end

								output = output .. "\n\t{\n"

								output = output .. "\t\tposition = Vector3(" .. tostring(object:GetPosition()) .. "),\n"
								output = output .. "\t\tangle = Angle(" .. tostring(object:GetAngle()) .. "),\n"
								output = output .. "\t\tmodel = \"" .. object:GetModel() .. "\",\n"
								output = output .. "\t\tcollision = \"" .. object:GetCollision() .. "\"\n"

								output = output .. "\t}"
							end
						end

						output = output .. "\n}"

						if not pcall(function()
							local file = io.open(filename .. ".txt", "w")

							file:write(header .. output)
							file:close()

							Tron.SendMessage(player, "Saved to " .. filename .. ".txt!", Color.Yellow)
						end) then
							Tron.SendMessage(player, "Could not save " .. filename .. ".txt!", Color.Red)
						end
					else
						Tron.SendMessage(player, "Please specify a valid radius!", Color.Red)
					end
				else
					Tron.SendMessage(player, "You don't have permission to do that!", Color.Red)
				end
			end
		elseif args[1] == "tronlobbies" then
			local lobbyCount = #self.lobbies
			local playerCount = 0

			for k, lobby in pairs(self.lobbies) do
				if lobby:GetState() == GamemodeState.WAITING then
					playerCount = playerCount + lobby:GetQueue():GetSize()
				else
					playerCount = playerCount + lobby:GetPlayerCount()
				end
			end

			function plural(count, plural, notPlural)
				if count ~= 1 then
					return plural
				else
					return notPlural
				end
			end

			Tron.SendMessage(player, "There " .. plural(lobbyCount, "are", "is") .. " " .. lobbyCount .. " lobb" .. plural(lobbyCount, "ies", "y") .. " in-progress with a total of " .. playerCount .. " active " .. plural(playerCount, "players", "player") .. ".", Color.Yellow)
		elseif args[1] == "tronlist" then
			local mapstrings = {""}

			for k, map in ipairs(TronConfig.Maps) do
				if #mapstrings[#mapstrings] > 0 then
					mapstrings[#mapstrings] = mapstrings[#mapstrings] .. ", "
				end

				if #mapstrings[#mapstrings] + #map.name < 100 then
					mapstrings[#mapstrings] = mapstrings[#mapstrings] .. map.name
				elseif k <= #TronConfig.Maps then
					mapstrings[#mapstrings + 1] = map.name
				end
			end

			Tron.SendMessage(player, "List:", Color.Yellow)

			for k, string in ipairs(mapstrings) do
				player:SendChatMessage(string, Color.Yellow)
			end
		elseif args[1] == "tronhelp" then
			Tron.SendMessage(player, "Command List:", Color.Yellow)

			player:SendChatMessage("/tron [mapname]", Color.Yellow)
			player:SendChatMessage("/tronlist", Color.Yellow)
			player:SendChatMessage("/tronlobbies", Color.Yellow)

			if table.find(self.admins, player:GetSteamId().id) then
				player:SendChatMessage("/tronforce [mapname]", Color.Orange)
				player:SendChatMessage("/tronsave [radius]", Color.Orange)
			end
		else
			invalidCommand = true
		end

		if not invalidCommand then
			return false
		end
	end
end

Tron()
