# CP77-RenderPlaneFix

## About

There's an issue with Cyberpunk 2077 which plagues a bunch of modded
clothing items and some vanilla ones:

![](before.png)

As you can see, Sleeves mods (like [BetterSleeves](https://github.com/Marco4413/CP77-BetterSleeves))
don't work well with all items. Usually these items are manually
fixed through Archive edits. However, it's not perfect and mods
that either add clothing items or modify vanilla items are prone
to break the item again.

This mod fixes everything at runtime using CET and Codeware:

![](after.png)

Which means that this mod should work with any clothing item, while
also keeping compatibility with refits!

### Requirements

- [CET 1.32.2+](https://github.com/yamashi/CyberEngineTweaks)
- [Codeware 1.9.3+](https://github.com/psiberx/cp2077-codeware)
- [RED4ext 1.25.0+](https://github.com/WopsS/RED4ext)

### Credits

Thanks to all contributors to CyberEngineTweaks, Codeware and RED4ext
for developing those projects and to the Cyberpunk 2077 Modding Community
Discord server for guiding me to the *dynamic* path!


### API

```lua
local RenderPlaneFix = GetMod("RenderPlaneFix")

RenderPlaneFix:IsPatchRegistered()

RenderPlaneFix:AreRequirementsMet()

RenderPlaneFix:RunPatchOnEntity(entity)

-- Any pattern within this table will be matched against
--  component names. If the pattern does not match then
--  the component can be patched.
RenderPlaneFix.componentNamePatternsBlacklist

-- This table contains string to boolean pairs.
-- Each entry represents the full name
--  of a component to not be patched.
RenderPlaneFix.componentNameBlacklist

-- Checks if the given component name should be patched.
RenderPlaneFix:ShouldPatchComponentByName(componentName)
```
