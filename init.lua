--[[
Copyright (c) 2026 [Marco4413](https://github.com/Marco4413/CP77-RenderPlaneFix)

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
local Enum     = require "Enum"

---@enum CustomPatchType
local CustomPatchType = Enum.New{ Empty = 0, RenderPlane = 1 }

---@enum PatchType
local PatchType = Enum.New{
    Auto   = 1, -- 0b0001
    Custom = 8, -- 0b1000

    AutoAndCustom = 9, -- 0b1001
}

local RenderPlaneFix = {
    CustomPatchType = CustomPatchType,
    PatchType = PatchType,

    showUI = false,
    patchType = PatchType.Auto,

    ---@type table<string, CustomPatchType>
    customPatchComponents = { },
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

    _nEmpty = nil,
    _nRenderPlane = nil,

    _configInitialized = false,
    _classesToPatch = { },

    ---Deprecated: see patchType
    ---@deprecated
    customPatch = false,
}

function RenderPlaneFix.Log(...)
    print(table.concat{"[ ", os.date("%x %X"), " ][ RenderPlaneFix ]: ", ...})
end

function RenderPlaneFix:ResetConfig()
    self.patchType = PatchType.Auto
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
        version = 2,
        patchType = PatchType[self.patchType],
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

    if version <= 1 then
        version = 2
        self.patchType = self.customPatch and PatchType.Custom or PatchType.Auto
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

        if type(config.patchType) == "string" and PatchType[config.patchType] then
            self.patchType = PatchType[config.patchType]
        end

        if type(config.customPatchComponents) == "table" then
            self.customPatchComponents = { }
            for name, patch in next, config.customPatchComponents do
                if patch == CustomPatchType.Empty or patch == CustomPatchType.RenderPlane then
                    self.customPatchComponents[name] = patch
                end
            end
        end

        -- DEPRECATED FIELDS

        if type(config.customPatch) == "boolean" then
            self.customPatch = config.customPatch
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

function RenderPlaneFix:_GetEmptyCName()
    if self._nEmpty then return self._nEmpty; end
    self._nEmpty = CName.new()
    return self._nEmpty
end

function RenderPlaneFix:_GetRenderPlaneCName()
    if self._nRenderPlane then return self._nRenderPlane; end
    self._nRenderPlane = CName.new("renderPlane")
    return self._nRenderPlane
end

function RenderPlaneFix:RunAutoPatchOnEntity(entity)
    if not self:AreRequirementsMet() then return false; end

    local nEmpty       = self:_GetEmptyCName()
    local nRenderPlane = self:_GetRenderPlaneCName()

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        if self:IsPatchableClass(component) then
            if (self:ShouldPatchComponentByName(component.name.value)
                and component.renderingPlaneAnimationParam == nEmpty) then
                component.renderingPlaneAnimationParam = nRenderPlane
            end
        end
    end
    return true
end

function RenderPlaneFix:RunCustomPatchOnEntity(entity)
    if not self:AreRequirementsMet() then return false; end

    local nEmpty       = self:_GetEmptyCName()
    local nRenderPlane = self:_GetRenderPlaneCName()

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        if self:IsPatchableClass(component) then
            local patch = self.customPatchComponents[component.name.value]
            if patch then
                component.renderingPlaneAnimationParam = (patch == CustomPatchType.RenderPlane and nRenderPlane or nEmpty)
            end
        end
    end
    return true
end

function RenderPlaneFix:RunPatchOnEntity(entity)
    if self.patchType == PatchType.Auto then
        return self:RunAutoPatchOnEntity(entity)
    elseif self.patchType == PatchType.Custom then
        return self:RunCustomPatchOnEntity(entity)
    elseif self.patchType == PatchType.AutoAndCustom then
        local applied = false
        if self:RunAutoPatchOnEntity(entity)   then applied = true; end
        if self:RunCustomPatchOnEntity(entity) then applied = true; end
        return applied
    end

    assert(false, "unhandled PatchType")
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
    local mod = RenderPlaneFix
    if not mod.showUI then return; end
    if ImGui.Begin("Render Plane Fix") then
        ImGui.TextWrapped(table.concat{
            "Mod Requirements Met: ", mod:AreRequirementsMet() and "Yes" or "No"
        })

        if not mod:AreRequirementsMet() then
            return
        end

        ImGui.TextWrapped(table.concat{
            "Patch Registered: ", mod:IsPatchRegistered() and "Yes" or "No"
        })
        ImGui.Separator()

        local player              = nil
        local patchableComponents = nil
        local nEmpty              = mod:_GetEmptyCName()
        local nRenderPlane        = mod:_GetRenderPlaneCName()

        if ImGui.CollapsingHeader("Patched Components") then
            ImGui.TextWrapped(table.concat{
                "ALL player components that have 'renderPlane' set are shown here.",
                " Which does not strictly mean that they were patched by this mod."
            })

            player = player or Game.GetPlayer()
            if player then
                patchableComponents = patchableComponents or mod:GetPatchableComponentsOfEntity(player)
                for _, component in next, patchableComponents do
                    if mod:IsPatchableClass(component) and component.renderingPlaneAnimationParam == nRenderPlane then
                        ImGui.Bullet()
                        ImGui.TextWrapped(component.name.value)
                    end
                end
            end
        end
        ImGui.Separator()

        if ImGui.CollapsingHeader("Unpatched Components") then
            ImGui.TextWrapped(table.concat{
                "All player components that can be patched are shown here.",
                " This section is mainly used to see what components were filtered out."
            })

            player = player or Game.GetPlayer()
            if player then
                patchableComponents = patchableComponents or mod:GetPatchableComponentsOfEntity(player)
                for _, component in next, patchableComponents do
                    if mod:IsPatchableClass(component) and component.renderingPlaneAnimationParam ~= nRenderPlane then
                        ImGui.Bullet()
                        ImGui.TextWrapped(component.name.value)
                    end
                end
            end
        end
        ImGui.Separator()

        mod.patchType = Enum.ImCombo(PatchType, mod.patchType, "Patch Type")
        ImGui.Separator()

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

            ImGui.PushStyleColor(ImGuiCol.Text, .9, .1, 0, 1)
            ImGui.TextWrapped(table.concat{
                "<!> You can share your custom patch by giving this mod's config file to others.",
                " The config file is found within this mod's CET folder ('Cyberpunk2077/bin/x64/plugins/cyber_engine_tweaks/mods/RenderPlaneFix/data/config.json').",
            })
            ImGui.PopStyleColor()

            ImGui.Separator()
            if ImGui.CollapsingHeader("Component Selector") then
                ImGui.TextWrapped("This menu shows all components (equipped by the player) which can be patched.")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped("Pressing the + or - buttons will add or remove the item from the patch list.")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(
                    "If the item is on the patch list, pressing the R or E buttons will set the component to either 'renderPlane' or '<empty>'.")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(table.concat{
                    "If the item is on the patch list, pressing the A button will simulate the patch being applied.",
                    " Once pressed, you should swap weapons or aim to see the changes."
                })
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(
                    "If the auto-patch would apply on the item, its name will be shown in green.")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(
                    "If the auto-patch would apply on the item but the item is already set to 'renderPlane', its name will be shown in yellow.")
                ImGui.Separator()

                player = player or Game.GetPlayer()
                if not player then
                    ImGui.TextWrapped("No player found, please load a game.")
                else
                    patchableComponents = patchableComponents or mod:GetPatchableComponentsOfEntity(player)
                    ImGui.PushID("custom-components")
                    for _, component in next, patchableComponents do
                        ImGui.PushID(component.name.value)
                        local patch = mod.customPatchComponents[component.name.value]
                        if patch then
                            if BetterUI.ButtonRemove() then
                                mod.customPatchComponents[component.name.value] = nil
                            end
                            if patch == CustomPatchType.Empty then
                                ImGui.SameLine()
                                if BetterUI.SquareButton("R") then
                                    mod.customPatchComponents[component.name.value] = CustomPatchType.RenderPlane
                                end
                                ImGui.SameLine()
                                if BetterUI.SquareButton("A") then
                                    component.renderingPlaneAnimationParam = nEmpty
                                end
                            elseif patch == CustomPatchType.RenderPlane then
                                ImGui.SameLine()
                                if BetterUI.SquareButton("E") then
                                    mod.customPatchComponents[component.name.value] = CustomPatchType.Empty
                                end
                                ImGui.SameLine()
                                if BetterUI.SquareButton("A") then
                                    component.renderingPlaneAnimationParam = nRenderPlane
                                end
                            end
                        elseif BetterUI.ButtonAdd() then
                            mod.customPatchComponents[component.name.value] = CustomPatchType.RenderPlane
                        end
                        ImGui.SameLine()

                        local shouldBePatched = mod:ShouldPatchComponentByName(component.name.value)
                        if shouldBePatched then
                            if component.renderingPlaneAnimationParam == nEmpty then
                                ImGui.PushStyleColor(ImGuiCol.Text, .1, .9, 0, 1)
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, .9, .9, 0, 1)
                            end
                        end

                        ImGui.Text(component.name.value)

                        if shouldBePatched then ImGui.PopStyleColor(); end

                        ImGui.PopID()
                    end
                    ImGui.PopID()
                end
            end

            ImGui.Separator()
            if ImGui.CollapsingHeader("Patch Manager") then
                ImGui.TextWrapped("This menu shows all components which will be patched (if found).")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped("Pressing the - button will remove the item from the patch list.")
                ImGui.Bullet(); ImGui.SameLine(); ImGui.TextWrapped(
                    "If the item is on the patch list, pressing the R or E buttons will set the component to either 'renderPlane' or '<empty>'.")
                ImGui.Separator()

                ImGui.PushID("custom-patch")
                for name, patch in next, mod.customPatchComponents do
                    ImGui.PushID(name)
                    if BetterUI.ButtonRemove() then
                        mod.customPatchComponents[name] = nil
                    end
                    if patch == CustomPatchType.Empty then
                        ImGui.SameLine()
                        if BetterUI.SquareButton("R") then
                            mod.customPatchComponents[name] = CustomPatchType.RenderPlane
                        end
                    elseif patch == CustomPatchType.RenderPlane then
                        ImGui.SameLine()
                        if BetterUI.SquareButton("E") then
                            mod.customPatchComponents[name] = CustomPatchType.Empty
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

        if BetterUI.FitButtonN(3, "Register") then mod:RegisterPatch(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(2, "Unregister") then mod:UnregisterPatch(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(1, "Run") then
            local player = Game.GetPlayer()
            if player then
                mod:RunPatchOnEntity(player)
            end
        end
        ImGui.Separator()

        ImGui.Text("Config |")
        ImGui.SameLine()

        if BetterUI.FitButtonN(3, "Load") then mod:LoadConfig(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(2, "Save") then mod:SaveConfig(); end
        ImGui.SameLine()

        if BetterUI.FitButtonN(1, "Reset") then mod:ResetConfig(); end
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
