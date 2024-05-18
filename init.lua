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

-- BetterUI is MIT licensed https://github.com/Marco4413/CP77-BetterSleeves

---@param n number
---@return number
---@return number
local function BetterUI_FitNButtonsInContentRegionAvail(n)
    local widthAvail, _ = ImGui.GetContentRegionAvail()
    local lineHeight = ImGui.GetTextLineHeightWithSpacing()
    local buttonWidth = widthAvail/n - 2.5 * (n-1)
    return buttonWidth, lineHeight
end

---@param n number
---@param label string
---@return boolean
local function BetterUI_FitButtonN(n, label)
    return ImGui.Button(label, BetterUI_FitNButtonsInContentRegionAvail(n))
end

local RenderPlaneFix = {
    showUI = false,
    -- The whitelist is matched first, so it overrides any blacklist setting
    componentNameWhitelist = {
    },
    -- Anything that does not match "^[hlstg][012]_%d%d%d_"
    --  should not be patched. However, most modded items would
    --  not match against that pattern.
    componentNamePatternsBlacklist = {
        "_shadow$", "_shadowmesh$",
        "^hh_%d%d%d_p?[wm][abcf]a?__",
        "^MorphTargetSkinnedMesh",
        "^[ntw][0x]_000_p?[mw]a_base__",
        "^[ant][0x]_00[08]_p?[mw]a__?fpp_",
    },
    componentNameBlacklist = {
        ["shoe_lights"] = true,
        ["shoes"]  = true,
        ["feet"]   = true,
        ["calves"] = true,
        ["legs"]   = true,
        ["thighs"] = true,
        ["torso"]  = true,
        ["body"]   = true,
    },
    patchedComponents = { },
    unpatchedComponents = { },
}

function RenderPlaneFix.Log(...)
    print(table.concat{"[ ", os.date("%x %X"), " ][ RenderPlaneFix ]: ", ...})
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

function RenderPlaneFix:RunPatchOnEntity(entity)
    if not self:AreRequirementsMet() then return false; end

    local entSkinnedMeshComponentCName = CName.new("entSkinnedMeshComponent")
    local entGarmentSkinnedMeshComponentCName = CName.new("entGarmentSkinnedMeshComponent")

    local emptyCName = CName.new()
    local renderPlaneCName = CName.new("renderPlane")

    self.patchedComponents = { }
    self.unpatchedComponents = { }

    local entityComponents = entity:GetComponents()
    for _, component in next, entityComponents do
        local componentClassName = component:GetClassName()
        if (componentClassName == entSkinnedMeshComponentCName
            or componentClassName == entGarmentSkinnedMeshComponentCName) then
            if (component.renderingPlaneAnimationParam == emptyCName
                --and garmentSkinnedMeshComponent.name.value:find("^[hlstg][012]_%d%d%d_")
                and self:ShouldPatchComponentByName(component.name.value)) then
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

local function Event_OnInit()
    if RenderPlaneFix:AreRequirementsMet() then
        RenderPlaneFix:RegisterPatch()
    else
        RenderPlaneFix.Log("Mod Requirements not met, please install Codeware")
    end
end

local function Event_OnShutdown()
    RenderPlaneFix:UnregisterPatch()
end

local function Event_OnDraw()
    if not RenderPlaneFix.showUI then return; end
    if ImGui.Begin("Render Plane Fix") then
        ImGui.TextWrapped(table.concat{
            "Mod Requirements Met: ", RenderPlaneFix:AreRequirementsMet() and "Yes" or "No"
        })
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

        ImGui.Text("Patch |")
        ImGui.SameLine()

        if BetterUI_FitButtonN(3, "Register") then RenderPlaneFix:RegisterPatch(); end
        ImGui.SameLine()

        if BetterUI_FitButtonN(2, "Unregister") then RenderPlaneFix:UnregisterPatch(); end
        ImGui.SameLine()

        if BetterUI_FitButtonN(1, "Run") then
            local player = Game.GetPlayer()
            if player then
                RenderPlaneFix:RunPatchOnEntity(player)
            end
        end
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
