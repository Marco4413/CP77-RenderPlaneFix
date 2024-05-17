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

local RenderPlaneFix = {
    showUI = false,
    -- Anything that does not match "^[hlstg][012]_%d%d%d_"
    --  should not be patched. However, most modded items would
    --  not match against that pattern.
    componentNameBlacklist = { },
    patchedComponents = { }
}

function RenderPlaneFix.Log(...)
    print(table.concat{"[ ", os.date("%x %X"), " ][ RenderPlaneFix ]: ", ...})
end

function RenderPlaneFix:ShouldPatchComponentByName(componentName)
    for _, pattern in next, self.componentNameBlacklist do
        if component.name.value:find(pattern) then
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
    local entGarmentSkinnedMeshComponentCName = CName.new("entGarmentSkinnedMeshComponent")
    local renderPlaneCName = CName.new("renderPlane")

    self.patchedComponents = { }
    local entityComponents = entity:GetComponents()
    for _, garmentSkinnedMeshComponent in next, entityComponents do
        if (garmentSkinnedMeshComponent:GetClassName() == entGarmentSkinnedMeshComponentCName
            and garmentSkinnedMeshComponent.renderingPlaneAnimationParam ~= renderPlaneCName
            --and garmentSkinnedMeshComponent.name.value:find("^[hlstg][012]_%d%d%d_")
            and self:ShouldPatchComponentByName(garmentSkinnedMeshComponent.name.value)) then
            table.insert(self.patchedComponents, garmentSkinnedMeshComponent.name.value)
            garmentSkinnedMeshComponent.renderingPlaneAnimationParam = renderPlaneCName
            garmentSkinnedMeshComponent:RefreshAppearance()
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
                "All components that were recently patched are shown here.",
                " If an item is not in the list, either it was already patched or has no issues."
            })
            for i=1, #RenderPlaneFix.patchedComponents do
                ImGui.Bullet()
                ImGui.TextWrapped(RenderPlaneFix.patchedComponents[i])
            end
        end
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
