--[[
Copyright (c) 2024 [Marco4413](https://github.com/Marco4413/CP77-RenderPlaneFix)

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
]]

local BetterUI = require "BetterUI"

---@enum CustomPatchType
local CustomPatchType = { Empty = 0, RenderPlane = 1 }
local RenderPlaneFix = {
    showUI = false,
    customPatch = false,
    ---@type table<string, CustomPatchType>
    customPatchComponents = { },
    CustomPatchType = CustomPatchType,
    -- The whitelist is matched first, so it overrides any blacklist setting
    componentNameWhitelist = {
        ["t0_000_pma_base__full_seamfix"] = true,
        ["t0_000_pwa_base__full_seamfix"] = true,
        ["t0_000_pma_base__full"] = true,
        ["t0_000_pwa_base__full"] = true,
        ["t0_000_pma_fpp__torso"] = true,
        ["t0_000_pwa_fpp__torso"] = true,
    },
    -- Anything that does not match "^[hlstg][012]_%d%d%d_"
    --  should not be patched. However, most modded items would
    --  not match against that pattern.
    componentNamePatternsBlacklist = {
        "_shadow$", "_shadowmesh$", "^beard_shadow",
        "^[hn][ehtx01]b?_%d%d%d_p?[wm][abcf]a?_",
        "^Morph",
    },
    componentNameBlacklist = {
        ["shoe_lights"] = true,
        ["shoes"]  = true,
        ["feet"]   = true,
        ["calves"] = true,
        ["thighs"] = true,
        ["legs"]   = true,
        ["torso"]  = true,
        ["body"]   = true,
        ["beard"]  = true,
    },
    patchedComponents = { },
    unpatchedComponents = { },
    _configInitialized = false,
    _classesToPatch = { },
}

function RenderPlaneFix.Log(...)
    print(table.concat{"[ ", os.date("%x %X"), " ][ RenderPlaneFix ]: ", ...})
end

function RenderPlaneFix:ResetConfig()
    self.customPatch = false
    self.customPatchComponents = {
        ["t0_005_pwa_body__t_bug7718"] = CustomPatchType.RenderPlane,
        ["t0_005_pwa_body__t_bug_shirt"] = CustomPatchType.RenderPlane,
        ["g1_014_pwa_gloves__ninja_gloves"] = CustomPatchType.RenderPlane,
        ["t2_084_pwa_jacket__short_sleeves_dec_nusa"] = CustomPatchType.RenderPlane,
    }
    self:MigrateConfigFromVersion(nil)
end

function RenderPlaneFix:SaveConfig()
    local file = io.open("data/config.json", "w")
    file:write(json.encode({
        version = 1,
        customPatch = self.customPatch,
        customPatchComponents = self.customPatchComponents,
    }))
    io.close(file)
end

function RenderPlaneFix:MigrateConfigFromVersion(version)
    if not version or type(version) ~= "number" then
        -- Migrate from version 0 to 1
        version = 1
        self.customPatchComponents["t0_005_pma_body__t_bug5280"] = CustomPatchType.RenderPlane
        self.customPatchComponents["t0_005_pma_body__t_bug_shirt2655"] = CustomPatchType.RenderPlane
        self.customPatchComponents["g1_014_pma_gloves__ninja_gloves"] = CustomPatchType.RenderPlane
        self.customPatchComponents["t2_084_pma__short_sleeves_dec_nusa"] = CustomPatchType.RenderPlane
    end

    -- Migrate from version x to latest
end

function RenderPlaneFix:LoadConfig()
    local ok = pcall(function ()
        local file = io.open("data/config.json", "r")
        local configText = file:read("*a")
        io.close(file)

        local config = json.decode(configText)
        if not config then return; end

        if type(config.customPatch) == "boolean" then
            self.customPatch = config.customPatch
        end

        if type(config.customPatchComponents) == "table" then
            self.customPatchComponents = { }
            for name, patch in next, config.customPatchComponents do
                if patch == CustomPatchType.Empty or patch == CustomPatchType.RenderPlane then
                    self.customPatchComponents[name] = patch
                end
            end
        end

        self:MigrateConfigFromVersion(config.version)
    end)
    if not ok then self:SaveConfig(); end
end

function RenderPlaneFix:ShouldPatchComponentByName(componentName)
    if self.componentNameWhitelist[componentName] then return true;  end
    if self.componentNameBlacklist[componentName] then return false; end
    for _, pattern in next, self.componentNamePatternsBlacklist do
        if componentName:find(pattern) then
            return false
        end
    end
    return true
end

function RenderPlaneFix:IsPatchableClass(classInstance)
    local className = classInstance:GetClassName()
    for _, toMatch in next, self._classesToPatch do
        if className == toMatch then return true; end
    end
    return false
end

function RenderPlaneFix:RegisterPatch()
    if not self:AreRequirementsMet() or self:IsPatchRegistered() then return false; end

    RenderPlaneFix.Log("Creating EntityLifecycleEvent listener")
    self._entityListener = NewProxy({
        OnPlayerReassemble = {
            args = { "handle:EntityLifecycleEvent" },
            callback = function(event)
                local player = event:GetEntity()
                RenderPlaneFix:RunPatchOnEntity(player)
            end
        }
    })

    RenderPlaneFix.Log("Adding 'Entity/Reassemble' listener for PlayerPuppet")
    Game.GetCallbackSystem()
        :RegisterCallback(
            "Entity/Reassemble",
            self._entityListener:Target(),
            self._entityListener:Function("OnPlayerReassemble"))
        :AddTarget(EntityTarget.Type("PlayerPuppet"))
        :SetLifetime(CallbackLifetime.Forever)

    return true
end

function RenderPlaneFix:UnregisterPatch()
    if not self:AreRequirementsMet() or not self:IsPatchRegistered() then return false; end

    RenderPlaneFix.Log("Removing 'Entity/Reassemble' listener")
    Game.GetCallbackSystem()
        :UnregisterCallback(
            "Entity/Reassemble",
            self._entityListener:Target())
    self._entityListener = nil

    return true
end

function RenderPlaneFix:IsPatchRegistered()
    return self._entityListener ~= nil
end

function RenderPlaneFix:AreRequirementsMet()
    return Codeware ~= nil
end

function RenderPlaneFix:RunAutoPatchOnEntity(entity)
    if not self:AreRequirementsMet() then return false; end

    local emptyCName = CName.new()
    local renderPlaneCName = CName.new("renderPlane")

    self.patchedComponents = { }
    self.unpatchedComponents = { }

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        if self:IsPatchableClass(component) then
            if (self:ShouldPatchComponentByName(component.name.value)
                and component.renderingPlaneAnimationParam == emptyCName) then
                component.renderingPlaneAnimationParam = renderPlaneCName
                component:RefreshAppearance()
            end

            if component.renderingPlaneAnimationParam == renderPlaneCName then
                table.insert(self.patchedComponents, component.name.value)
            elseif component.renderingPlaneAnimationParam == emptyCName then
                table.insert(self.unpatchedComponents, component.name.value)
            end
        end
    end
    return true
end

function RenderPlaneFix:RunCustomPatchOnEntity(entity)
    if not self:AreRequirementsMet() then return false; end

    local emptyCName = CName.new()
    local renderPlaneCName = CName.new("renderPlane")

    self.patchedComponents = { }
    self.unpatchedComponents = { }

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        if self:IsPatchableClass(component) then
            local patch = self.customPatchComponents[component.name.value]
            if patch then
                component.renderingPlaneAnimationParam = (patch == CustomPatchType.RenderPlane and renderPlaneCName or emptyCName)
                component:RefreshAppearance()
            end

            if component.renderingPlaneAnimationParam == renderPlaneCName then
                table.insert(self.patchedComponents, component.name.value)
            elseif component.renderingPlaneAnimationParam == emptyCName then
                table.insert(self.unpatchedComponents, component.name.value)
            end
        end
    end
    return true
end

function RenderPlaneFix:RunPatchOnEntity(entity)
    if RenderPlaneFix.customPatch then
        return RenderPlaneFix:RunCustomPatchOnEntity(entity)
    end
    return RenderPlaneFix:RunAutoPatchOnEntity(entity)
end

function RenderPlaneFix:GetPatchableComponentsOfEntity(entity)
    if not self:AreRequirementsMet() then return { }; end

    local patchables = { }

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        if self:IsPatchableClass(component) then
            table.insert(patchables, component)
        end
    end

    return patchables
end

local function Event_OnInit()
    if not RenderPlaneFix:AreRequirementsMet() then
        RenderPlaneFix.Log("Mod Requirements not met, please install Codeware")
        return
    end

    RenderPlaneFix._classesToPatch = {
        CName.new("entMeshComponent"),
        CName.new("entSkinnedMeshComponent"),
        CName.new("entGarmentSkinnedMeshComponent"),
        CName.new("entMorphTargetSkinnedMeshComponent"),
    }

    RenderPlaneFix:ResetConfig()
    RenderPlaneFix:LoadConfig()
    RenderPlaneFix._configInitialized = true
    RenderPlaneFix:RegisterPatch()
end

local function Event_OnShutdown()
    if RenderPlaneFix._configInitialized then
        RenderPlaneFix:SaveConfig()
    end
    RenderPlaneFix:UnregisterPatch()
end

local function Event_OnDraw()
    if not RenderPlaneFix.showUI then return; end
    if ImGui.Begin("Render Plane Fix") then
        ImGui.TextWrapped(table.concat{
            "Mod Requirements Met: ", RenderPlaneFix:AreRequirementsMet() and "Yes" or "No"
        })

        if not RenderPlaneFix:AreRequirementsMet() then
            return
        end

        ImGui.TextWrapped(table.concat{
            "Patch Registered: ", RenderPlaneFix:IsPatchRegistered() and "Yes" or "No"
        })
        ImGui.Separator()
        
        if ImGui.CollapsingHeader("Patched Components") then
            ImGui.TextWrapped(table.concat{
                "ALL components that have 'renderPlane' set are shown here.",
                " Which does not strictly mean that they were patched by this mod."
            })
            for i=1, #RenderPlaneFix.patchedComponents do
                ImGui.Bullet()
                ImGui.TextWrapped(RenderPlaneFix.patchedComponents[i])
            end
        end
        ImGui.Separator()
        
        if ImGui.CollapsingHeader("Unpatched Components") then
            ImGui.TextWrapped(table.concat{
                "All components that can be patched are shown here.",
                " This section is mainly used to see what components were filtered out."
            })
            for i=1, #RenderPlaneFix.unpatchedComponents do
                ImGui.Bullet()
                ImGui.TextWrapped(RenderPlaneFix.unpatchedComponents[i])
            end
        end
        ImGui.Separator()

        RenderPlaneFix.customPatch = ImGui.Checkbox("Use Custom Patch", RenderPlaneFix.customPatch)
        ImGui.TextWrapped(table.concat{
            "Press the arrow if the menu does not open.",
            " Nested sub-menus are a bit broken but I need them here."
        })

        if ImGui.CollapsingHeader("Custom Patch") then
            ImGui.TextWrapped(table.concat{
                "If something does not work try reloading the save file first (some changes are not real-time).",
                " Especially if you loaded a save with Custom Patch disabled."
            })

            ImGui.TextWrapped(table.concat{
                "You can manage and build your custom patch here.",
                " The automatic patch has some issues which cannot easily be fixed.",
                " You can try to work around those by manually defining what to patch."
            })

            ImGui.TextWrapped("The Component Selector menu shows all components (equipped by the player) which can be patched.")
            ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped("Pressing the + or - buttons will add or remove the item from the patch list.")
            ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(
                "If the item is on the patch list, pressing the R or E buttons will set the component to either 'renderPlane' or 'None'.")
            ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(table.concat{
                "If the item is on the patch list, pressing the A button will simulate the patch being applied.",
                " Once pressed, you should swap weapons or aim to see the changes."
            })

            ImGui.TextWrapped("The Patch Manager menu shows all components which will be patched (if found) and allows you to remove them or change their type.")

            ImGui.Separator()
            if ImGui.CollapsingHeader("Component Selector") then
                local player = Game.GetPlayer()
                if not player then
                    ImGui.TextWrapped("No player found, please load a game.")
                else
                    local emptyCName = CName.new()
                    local renderPlaneCName = CName.new("renderPlane")

                    local patchables = RenderPlaneFix:GetPatchableComponentsOfEntity(player)
                    ImGui.PushID("custom-components")
                    for _, component in next, patchables do
                        ImGui.PushID(component.name.value)
                        local patch = RenderPlaneFix.customPatchComponents[component.name.value]
                        if patch then
                            if BetterUI.ButtonRemove() then
                                RenderPlaneFix.customPatchComponents[component.name.value] = nil
                            end
                            if patch == CustomPatchType.Empty then
                                ImGui.SameLine()
                                if BetterUI.SquareButton("R") then
                                    RenderPlaneFix.customPatchComponents[component.name.value] = CustomPatchType.RenderPlane
                                end
                                ImGui.SameLine()
                                if BetterUI.SquareButton("A") then
                                    component.renderingPlaneAnimationParam = emptyCName
                                    component:RefreshAppearance()
                                end
                            elseif patch == CustomPatchType.RenderPlane then
                                ImGui.SameLine()
                                if BetterUI.SquareButton("E") then
                                    RenderPlaneFix.customPatchComponents[component.name.value] = CustomPatchType.Empty
                                end
                                ImGui.SameLine()
                                if BetterUI.SquareButton("A") then
                                    component.renderingPlaneAnimationParam = renderPlaneCName
                                    component:RefreshAppearance()
                                end
                            end
                        elseif BetterUI.ButtonAdd() then
                            RenderPlaneFix.customPatchComponents[component.name.value] = CustomPatchType.RenderPlane
                        end
                        ImGui.SameLine()
                        ImGui.Text(component.name.value)
                        ImGui.PopID()
                    end
                    ImGui.PopID()
                end
            end

            ImGui.Separator()
            if ImGui.CollapsingHeader("Patch Manager") then
                ImGui.PushID("custom-patch")
                for name, patch in next, RenderPlaneFix.customPatchComponents do
                    ImGui.PushID(name)
                    if BetterUI.ButtonRemove() then
                        RenderPlaneFix.customPatchComponents[name] = nil
                    end
                    if patch == CustomPatchType.Empty then
                        ImGui.SameLine()
                        if BetterUI.SquareButton("R") then
                            RenderPlaneFix.customPatchComponents[name] = CustomPatchType.RenderPlane
                        end
                    elseif patch == CustomPatchType.RenderPlane then
                        ImGui.SameLine()
                        if BetterUI.SquareButton("E") then
                            RenderPlaneFix.customPatchComponents[name] = CustomPatchType.Empty
                        end
                    end
                    ImGui.SameLine()
                    ImGui.Text(name)
                    ImGui.PopID()
                end
                ImGui.PopID()
            end
        end
        ImGui.Separator()

        ImGui.Text("Patch |")
        ImGui.SameLine()

        if BetterUI.FitButtonN(3, "Register") then RenderPlaneFix:RegisterPatch(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(2, "Unregister") then RenderPlaneFix:UnregisterPatch(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(1, "Run") then
            local player = Game.GetPlayer()
            if player then
                RenderPlaneFix:RunPatchOnEntity(player)
            end
        end
        ImGui.Separator()

        ImGui.Text("Config |")
        ImGui.SameLine()

        if BetterUI.FitButtonN(3, "Load") then RenderPlaneFix:LoadConfig(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(2, "Save") then RenderPlaneFix:SaveConfig(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(1, "Reset") then RenderPlaneFix:ResetConfig(); end
        ImGui.Separator()
    end
end

local function Event_OnOverlayOpen()
    RenderPlaneFix.showUI = true
end

local function Event_OnOverlayClose()
    RenderPlaneFix.showUI = false
end

function RenderPlaneFix:Init()
    registerForEvent("onInit", Event_OnInit)
    registerForEvent("onShutdown", Event_OnShutdown)
    registerForEvent("onDraw", Event_OnDraw)
    registerForEvent("onOverlayOpen", Event_OnOverlayOpen)
    registerForEvent("onOverlayClose", Event_OnOverlayClose)
    return self
end

return RenderPlaneFix:Init()
