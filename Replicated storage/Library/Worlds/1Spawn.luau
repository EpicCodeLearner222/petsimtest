local module = {}

module.WorldData = {
  Name = "Spawn",
  Number = 1,
  Teleport = workspace:WaitForChild("Maps"):WaitForChild(module.WorldData.Name).Spawn.CFrame +Vector3.new(0,5,0), -- Set y to 5 so people don't spawn inside ground incase the spawn isn't already listed.
  Interactive = workspace:WaitForChild("Maps"):WaitForChild(module.WorldData.Name).Interactive:GetChildren(),
  Breakables = Interactive.Breakables,
  Cost = 0, -- Cost for worlds, by default if it's 0 then its' automatically unlocked.
}

return module
