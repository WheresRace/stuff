--!nocheck

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

--// Requires
local Maid = require(ReplicatedStorage.Packages.Maid)
local HitboxClass = require(ReplicatedStorage.Shared.Classes.HitboxClass.HitboxClass)

local GloveTypes = {} -- This is a table that stores all of the different glove types so I don't have to go ahead and require all of them

local function LoadGloveTypes() -- This function basically just requires the glove types all at once so i can easily acess them in the glove types table
	for _, module in ipairs(script.GloveTypes:GetChildren()) do
		if module:IsA("ModuleScript") then
			local LoadedModule = require(module)
			GloveTypes[module.Name] = LoadedModule
		end
	end
end

-- Get Object function which  looks for a specific string and if it cant find it then it clones the template, Really useful
local function GetObject(Object, name: string, template: Instance)
	local existing = Object:FindFirstChild(name, true)
	if existing then
		return existing
	end
	if not template then
		return nil
	end
	local clone = template:Clone()
	if Object:IsA("Model") and Object.PrimaryPart then
		clone.Parent = Object.PrimaryPart
	else
		clone.Parent = Object
	end
	return clone
end

LoadGloveTypes()

--// Class
local Glove = {}

Glove.__index = Glove

--// Constructor
function Glove.new(player: Player, GloveType: string)
	local self = setmetatable({}, Glove)
	-- Cleanup
	self.Maid = Maid.new()
	-- Vars
	self.Player = player
	self.GloveType = GloveType -- Save the glove Type
	--// Stats (guarded)
	local typeData = GloveTypes[GloveType] -- Quickly get the GloveTypeData Which includes the following
	self.StorageAmount = typeData.StorageAmount or 10 -- Storage amount also doesnt do anything ( working on )
	self.Strength = typeData.Strength or 1 -- Strength doesn't do anything for now ( this is a game that i'm currently working on)
	self.Speed = typeData.Speed or 10 -- Speed changes how fast the alignposition moves
	--// Data
	self.GloveInventory = {} -- This stores all of the gloves data when you use it to collect things
	self.HeldObjects = {} -- Stores what objects are currently being held by the glove
	self.EquippedObject = "" -- The equipped object so you can release it if needed
	self.GloveMode = "Hold" -- The current Mode that the glove is in

	self:SetupPlayer() -- look below

	return self
end

-- This function sets up the players Grab Attachment, I use this as the attachment 1 for all the constraint movers or whatever they're called that the glove uses to move the object to the player.
function Glove:SetupPlayer()
	-- Quickly get or wait for the character
	local character = self.Player.Character
	if not character then
		character = self.Player.Character or self.Player.CharacterAdded:Wait()
	end

	-- Find the right arm
	local rightArm = character:FindFirstChild("Right Arm")
	if not rightArm then
		return
	end

	-- Get or create the grab attachment, I use recursive findfirstchild just incase its somewhere else, I only create it in this script though so it will only be in the right arm
	local GrabAttachment = character:FindFirstChild("GrabAttachment", true)
	if not GrabAttachment then
		GrabAttachment = Instance.new("Attachment")
		GrabAttachment.Name = "GrabAttachment"
		GrabAttachment.Parent = rightArm
		self:ChangeRange(15) -- Change the range so i just make the number negative so it goes farther you can see that in the change range function
	end
end

-- This function sets the object up to be grabbed
function Glove:SetupObject(Object: Instance)
	-- We validate the object here to make sure it's valid
	if not Object then
		return nil
	end

	-- Character check
	local character = self.Player.Character
	if not character then
		return nil
	end

	-- get all the templates
	local assets = ReplicatedStorage.Assets
	local grabPositionTemplate = assets.Physics:FindFirstChild("GrabPosition")
	local grabOrientationTemplate = assets.Physics:FindFirstChild("GrabOrientation")

	-- Get the grabposition and orientation objects, if not found the helper function i made will help me
	local GrabPosition = GetObject(Object, "GrabPosition", grabPositionTemplate)
	local GrabOrientation = GetObject(Object, "GrabOrientation", grabOrientationTemplate)

	-- make sure the attachment 0 of the object exists if not we just quickly create it
	local baseAttachment = Object:FindFirstChild("GrabBaseAttachment", true)
	if not baseAttachment then
		baseAttachment = Instance.new("Attachment")
		baseAttachment.Name = "GrabBaseAttachment"
		if Object:IsA("Model") and Object.PrimaryPart then -- I also do checks to see if the object is a model or a basepart so i can easily have flexibility.
			baseAttachment.Parent = Object.PrimaryPart
		else
			baseAttachment.Parent = Object
		end
	end

	-- Look for the right arm and find grabattachment which will be my attachment1
	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not rightArm then
		return nil
	end

	local GrabAttachment = rightArm:FindFirstChild("GrabAttachment")

	-- Connect everything and set the speed via responsiveness and boom the object is setup
	if GrabPosition then
		GrabPosition.Attachment0 = baseAttachment
		GrabPosition.Attachment1 = GrabAttachment
		GrabPosition.Responsiveness = self.Speed or 10
	end

	if GrabOrientation then
		GrabOrientation.Attachment0 = baseAttachment
		GrabOrientation.Attachment1 = GrabAttachment
	end

	-- Return for easy use
	return GrabPosition, GrabOrientation
end

-- Changes the range of the attachment1 the attachment in the players right arm
function Glove:ChangeRange(range: number): boolean
	range = math.abs(range) * -1 -- Make the number negative so that it goes infront of the player
	local Character = self.Player.Character

	-- Character stuff get grab attachment
	if not Character then
		return false
	end

	local GrabAttachment = Character:FindFirstChild("GrabAttachment", true)

	if not GrabAttachment then
		return false
	end

	-- Set the cframe of the grabattachment so when your holding things you can change the range

	GrabAttachment.CFrame = CFrame.new(0, range, 0)

	return true
end

-- my helper function to quickly get equipped data
function Glove:_getEquippedData()
	local key = self.EquippedObject

	if key ~= "" and self.GloveInventory[key] then -- Blank means "" the player hasnt selected a item so we check to amke sure itrs not blank and the item eactually exists
		return key, self.GloveInventory[key] -- Return the key and the inventory data which includes a multitude of things
	end

	return nil
end

-- Another helper function
function Glove:_getOrAssignUUID(Object: Instance): string
	local uuid = Object:GetAttribute("UUID") -- Looks for the UUID
	if not uuid then -- If the uuid doesnt exist then go ahead and create a UUID for the object
		uuid = HttpService:GenerateGUID(false)
		Object:SetAttribute("UUID", uuid)
	end
	return uuid -- RETURN THE uuid
end

-- So I can easily stop the glitching that happens when your carrying too many things at once. Now the objects will only collide with eachother and not the player when i disable the collisions using this function
function Glove:_disableCollisions(Object: Instance)
	for _, part in pairs(Object:GetDescendants()) do -- Loop through descendants which is all parts within the part basically
		if part:IsA("BasePart") then -- Check if its a base part
			part.CollisionGroup = "VomGrabbed" -- And set the collision group to the one i made in studio
		end
	end
end

-- Basically same thing as above but I reset it back to the default collision group
function Glove:_enableCollisions(Object: Instance)
	for _, part in pairs(Object:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Default"
		end
	end
end

-- The function that makes the glove work
function Glove:Use(SpecificRequest: "Launch" | "Drop") -- Specific requests are basically player inputs like letting go of the mouse, launch isnt implemented yet. Drop for example just drops the object
	local mode = SpecificRequest or self.GloveMode -- Get the mode or glovemode
	local method = self[mode] -- Find the corresponding function
	if type(method) == "function" then -- Make sure its a function using type
		return method(self) -- run the function  and return whatever value it may have
	end

	return false -- return false if it doesnt work
end

-- Make sure the object the player is trying to interact with is valid
function Glove:VerifyObject(Object: Instance)
	if not Object or typeof(Object) ~= "Instance" then
		return false
	end -- If the object isnt a instance then quicky return end

	local modelAncestor = Object:FindFirstAncestorOfClass("Model") --check if the object has a model ancestor
	local target = modelAncestor or Object -- this is to account for if its a model or a basepart
	local uuid = target:GetAttribute("UUID") -- get the objects uuid

	if not uuid then -- Look for uuid or assign a uuid
		uuid = self:_getOrAssignUUID(target) -- Now that i look at this again, it may be a bad idea as it could possibly assign uuids to random parts :/
	end

	-- Make sure the object isnt already being held  so there isnt any overlap
	if self.HeldObjects[uuid] then -- UUID is the key
		-- Return false is the object cant be verified
		return false
	end

	-- Then I check if the object is a valid target via a tag i assign to all objects that i want to be interactable
	if target:HasTag("GloveInteractable") then
		return true
	end

	-- Return false is the object cant be verified
	return false
end

-- Check how many items i have in my glove storage
function Glove:CheckAmountInStorage(): number
	local count = 0 -- start the count at 0
	for _, _ in pairs(self.GloveInventory) do -- Loop through the inventory
		count = count + 1 -- Add 1 for each entry
	end
	return count -- Return the count
end

-- Add the object to the gloves data
function Glove:AddObject(Object: Instance): boolean
	if not Object then
		return false
	end -- Make sure it exists
	if self:CheckAmountInStorage() >= self.StorageAmount then
		return false
	end -- Make sure they already didn't hit the max storageamount

	-- UUID Data
	local uuid = self:_getOrAssignUUID(Object)
	local objName = Object.Name

	-- What this does is check to see if the same type of object already exists in the database, If so we then get the key (UUID)
	local existingKey
	for key, data in pairs(self.GloveInventory) do
		if data.Name == objName then
			existingKey = key
			break
		end
	end

	-- If we got the key we can go ahead and add 1 to the amount. I haven't added any limitations to this yet like a if statement to amke sure they don't go over a certain amount
	if existingKey then
		self.GloveInventory[existingKey].Amount += 1
	else -- If we don't have the key then we will just create a new entry in the data
		-- Tool for testing purposes ( another script )
		local Tool = Instance.new("Tool")
		Tool.Name = objName
		Tool.RequiresHandle = false
		Tool:SetAttribute("IsGloveItem", true)
		Tool:SetAttribute("UUID", uuid)

		-- Add the object to the inventory
		self.GloveInventory[uuid] = {
			Name = objName,
			OriginalID = uuid,
			Tool = Tool,
			Amount = 1,
		}

		Tool.Parent = self.Player.Backpack
	end

	-- Return true if the object was added to the data
	return true
end

-- Remove the object from the data
function Glove:RemoveObject(
	ObjectID: string,
	RemoveType: "Destroy" | "Release" | "Launch"
): boolean -- ObjectID another name for the UUID, RemoveType is the type of removal (destroy, release, launch)
	-- RemoveType Destroy just gets rid of it in the data without any visuals while release shows visuals, launch hasnt been implemented
	-- It doesn't really do anything as of now since im still implementing it( game still in development)
	if not ObjectID then
		return false
	end -- Make sure we have the UUID

	-- Again the same as the add function, we check to see if the object exists now that i think about it
	-- i could of just did something like self.GloveInventory[ObjectId] with a if statement
	local foundKey, ObjectData
	for key, data in pairs(self.GloveInventory) do
		if data.OriginalID == ObjectID then
			foundKey, ObjectData = key, data
			break
		end
	end

	if not ObjectData then
		return false
	end

	-- handle removal logicm if the type is destroy then we simply just run the gloves destroy function
	if RemoveType ~= "Destroy" and type(self[RemoveType]) == "function" then
		self[RemoveType](self, ObjectData)
	end

	-- Minus the objects data by 1
	ObjectData.Amount -= 1

	-- Check to see if theres no more left in amount
	if ObjectData.Amount <= 0 then -- If so we can get rid of the object for good
		if ObjectData.Tool then
			ObjectData.Tool:Destroy()
		end

		if self.EquippedObject == ObjectData.OriginalID then -- If the object was the one equipped then reset equipped object and glovemode Back to their defaults
			self.EquippedObject = ""
			self.GloveMode = "Hold"
		end

		self.GloveInventory[foundKey] = nil -- Remove the entry from the data
	end

	return true
end

-- Visualizes the release of the object
function Glove:Release(object): boolean
	-- Get equipped data
	local key, ObjectData = self:_getEquippedData()
	if not ObjectData then
		return false
	end

	-- Bunch of security checks for the objectTemplate character right arm, same stuff
	local template = ReplicatedStorage:FindFirstChild(ObjectData.Name, true)
	if not template then
		return false
	end

	local character = self.Player.Character
	if not character then
		return false
	end

	local rightArm = character:FindFirstChild("Right Arm")
	if not rightArm then
		return false
	end

	-- This codes purpose is to visualize the release when you remove a object so it just clones the object
	local clone = template:Clone()
	clone.Parent = workspace

	-- Then depending on the type and whether it has a primary part or not it teleports the part to the right arm cframe
	if clone:IsA("Model") and clone.PrimaryPart then
		clone:PivotTo(rightArm.CFrame)
	elseif clone:IsA("BasePart") then
		clone.CFrame = rightArm.CFrame
	elseif clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			primary.CFrame = rightArm.CFrame
		end
	end

	self:RemoveObject(ObjectData.OriginalID, "Destroy") -- Then it runs the destroy function to release the object. I should probably just keep the Destroy function and remove the other 2 removetypes
	return true
end

-- Holds the object in the players right arm
function Glove:Hold()
	-- Again some security checks looking for the hrp
	local primary = self.Player.Character.PrimaryPart
	if not primary then
		return
	end

	-- Change the range so the grabattachment is 15 studs away from the player
	self:ChangeRange(15)

	-- Use maid to create a hitbox task with my hitbox class that uses a runservice task via maid to clean it up
	-- GetPartBoundsInRadius to get the part bounds in a radius of 25 studs around the hrp
	self.Maid.HitboxTask = HitboxClass.new(primary, 25, Vector3.new(0, 0, -5))

	-- Start the hitbox and the hitbox class has a completed function that runs when the hitbox is completed so whenever it finds a object it runs
	self.Maid.HitboxTask:Start(function(Object: Instance)
		-- safety/security checks make sure the object is allowed to be interacted with
		if not self:VerifyObject(Object) then
			return
		end
		-- Get the objects true name and data aka make sure its a model or basepart
		if Object:FindFirstAncestorOfClass("Model") then
			Object = Object:FindFirstAncestorOfClass("Model")
		end

		-- Setup the object getting the grab position orientation
		local GrabPosition, GrabOrientation = self:SetupObject(Object)
		if not (GrabPosition and GrabOrientation) then
			return
		end

		-- Enabling them
		GrabPosition.Enabled = true
		GrabOrientation.Enabled = true

		-- Checking for ballsocket constraint so its jiggly and then enabling that
		local BallSocket = Object:FindFirstChild("BallSocketConstraint", true)
		if BallSocket then
			BallSocket.Enabled = true
		end
		self:_disableCollisions(Object) -- Disabling collisions so they dont run into the player and make them fly across the map

		-- And add the entry to held objects setting the grabbed attribute to true
		self.HeldObjects[self:_getOrAssignUUID(Object)] = Object
		Object:SetAttribute("Grabbed", true)
	end)
end

-- Drops the object
function Glove:Drop()
	if self.Maid.HitboxTask then -- Cancels the hitbox task
		self.Maid.HitboxTask = nil
	end

	-- Loop through all the held objecto drop them
	for uuid, object in pairs(self.HeldObjects) do
		if not object or not object.Parent then -- If the object doesn't exist anymore then just remove it from the entry and continue
			self.HeldObjects[uuid] = nil
			continue -- We continue so it doesn't just error as the object doesn't exist anymore if it went on it would of errored on the grabposition line
		end

		-- Get all of the constaints and disable them
		local GrabPosition = object:FindFirstChild("GrabPosition", true)
		local GrabOrientation = object:FindFirstChild("GrabOrientation", true)
		local BallSocketConstraint = object:FindFirstChild("BallSocketConstraint", true)

		if GrabPosition then
			GrabPosition.Enabled = false
		end
		if GrabOrientation then
			GrabOrientation.Enabled = false
		end
		if BallSocketConstraint then
			BallSocketConstraint.Enabled = false
		end

		-- renable collisions set grabbed to false
		self:_enableCollisions(object)
		object:SetAttribute("Grabbed", false)

		-- remove the data from the entry
		self.HeldObjects[uuid] = nil
	end
end

--// Switching mode
function Glove:SwitchMode(Mode: "Hold")
	if not Mode or Mode == self.GloveMode then -- Make sure the mode isnt the current mode thats set
		return
	end
	self.GloveMode = Mode -- Set the mode to the var
end

--// destroy the glove
function Glove:Destroy(): boolean
	if self.Maid then -- Get rid of the maid and clean all connections associated with it
		self.Maid:Destroy()
	end

	-- Set maid to nil just inclase and clear the table and remove the metatable
	self.Maid = nil
	table.clear(self)
	setmetatable(self, nil)

	return true
end

return Glove
