-- CraftPath :: Minimap
-- A minimap button that opens the planner. Uses LibDBIcon when another addon has loaded it (so minimap
-- addons can collect it with the other buttons); otherwise draws a plain button that can be dragged round
-- the minimap. "/craftpath minimap" hides or shows it.

local _, CPath = ...
local MinimapButton = {}
CPath.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local NAME = "CraftPath"
local lib, own

local function Store()
	local db = CPath.db
	if type(db.minimap) ~= "table" then db.minimap = {} end
	return db.minimap
end

local function Tooltip(tt)
	tt:AddLine("CraftPath")
	tt:AddLine("Click to open the profession planner.", 1, 1, 1)
	tt:AddLine("Drag to move this button.", 0.6, 0.55, 0.45)
end

local function Click()
	if CPath.UI then CPath.UI:Toggle() end
end

-- Plain button, placed by angle round the minimap.
local function Place()
	local angle = math.rad(Store().minimapPos or 215)
	local r = (Minimap:GetWidth() or 140) / 2 + 8
	own:ClearAllPoints()
	own:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function BuildOwn()
	if own or not Minimap then return end
	own = CreateFrame("Button", "CraftPathMinimapButton", Minimap)
	own:SetSize(31, 31)
	own:SetFrameStrata("MEDIUM")
	own:SetFrameLevel(8)
	own:RegisterForClicks("AnyUp")
	own:RegisterForDrag("LeftButton")
	own:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = own:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(ICON)
	icon:SetSize(19, 19)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local border = own:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(52, 52)
	border:SetPoint("TOPLEFT")
	own:SetScript("OnClick", Click)
	own:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		Tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	own:SetScript("OnLeave", function() GameTooltip:Hide() end)
	own:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			Store().minimapPos = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			Place()
		end)
	end)
	own:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function MinimapButton:Apply()
	local store = Store()
	if lib then
		lib:Refresh(NAME, store)
		if store.hide then lib:Hide(NAME) else lib:Show(NAME) end
	elseif own then
		Place()
		if store.hide then own:Hide() else own:Show() end
	end
end

function MinimapButton:Toggle()
	local store = Store()
	store.hide = not store.hide
	self:Apply()
	CPath:Print(store.hide and "Minimap button hidden. Type /craftpath minimap to bring it back." or "Minimap button shown.")
end

local function Setup()
	if lib or own then return end
	local stub = _G.LibStub
	local ldb = stub and stub("LibDataBroker-1.1", true)
	local icon = stub and stub("LibDBIcon-1.0", true)
	if ldb and icon then
		local ok, object = pcall(ldb.NewDataObject, ldb, NAME, {
			type = "launcher", text = NAME, icon = ICON,
			OnClick = Click, OnTooltipShow = Tooltip,
		})
		if ok and object and pcall(icon.Register, icon, NAME, object, Store()) then lib = icon end
	end
	if not lib then BuildOwn() end
	MinimapButton:Apply()
end

CPath:On("LOGIN", Setup)
-- saved data can arrive late and replace the table the button's position lives in
CPath:On("DB_CHANGED", function() if lib or own then MinimapButton:Apply() end end)

-- The addon list button on the minimap (where the client has one).
function _G.CraftPath_OnCompartmentClick() Click() end
