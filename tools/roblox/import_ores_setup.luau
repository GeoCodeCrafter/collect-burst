-- run in the command bar after File > Import 3D of assets/ores.fbx. sorts the clusters into
-- ReplicatedStorage.CollectBurstAssets.Ores.<Coal|Iron|Gold|Diamond>, three shapes each
local rs = game:GetService("ReplicatedStorage")

local imported
for _, m in workspace:GetDescendants() do
	if m:IsA("Model") and m:FindFirstChild("Coal1", true) and m:FindFirstChild("Diamond1", true) then
		imported = m
		break
	end
end
if not imported then
	return "no imported ores found (looking for a model with Coal1 and Diamond1 in it)"
end

local assets = rs:FindFirstChild("CollectBurstAssets") or Instance.new("Folder")
assets.Name = "CollectBurstAssets"
assets.Parent = rs
local ores = assets:FindFirstChild("Ores")
if ores then
	ores:Destroy()
end
ores = Instance.new("Folder")
ores.Name = "Ores"
ores.Parent = assets

local out = {}
for _, kind in { "Coal", "Iron", "Gold", "Diamond" } do
	local folder = Instance.new("Folder")
	folder.Name = kind
	folder.Parent = ores
	local n, pbr = 0, 0
	for i = 1, 3 do
		local p = imported:FindFirstChild(kind .. i, true)
		p = p and (if p:IsA("BasePart") then p else p:FindFirstChildWhichIsA("BasePart", true))
		if p then
			p.Anchored = true
			p.CanCollide = false
			-- the importer leaves the pivot turned for blender's Z-up
			p.PivotOffset = CFrame.new()
			pcall(function()
				p.RenderFidelity = Enum.RenderFidelity.Precise
			end)
			if kind == "Diamond" then
				-- a baked texture can only make a clear stone flat white, so diamonds are roblox glass instead
				local sa = p:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then
					sa:Destroy()
				end
				p.Material = Enum.Material.Glass
				p.Color = Color3.fromRGB(214, 238, 255)
				p.Transparency = 0.25
				p.Reflectance = 0.5
			end
			p.Parent = folder
			n += 1
			if p:FindFirstChildWhichIsA("SurfaceAppearance") then
				pbr += 1
			end
		end
	end
	table.insert(out, string.format("%s %d (%d with PBR)", kind, n, pbr))
end
imported:Destroy()
return table.concat(out, " | ")
