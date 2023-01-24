local function options(panel)
    panel:CheckBox("Slowdown time", "cl_deadeye_slowdown")
    panel:CheckBox("Draw deadeye indicator", "cl_deadeye_bar")
    panel:CheckBox("Original deadeye indicator", "cl_deadeye_bar_mode")
    panel:CheckBox("Infinite mode", "cl_deadeye_infinite")
    panel:CheckBox("Transfer marks to dead bodies", "cl_deadeye_transfer_to_ragdolls")
    panel:CheckBox("Mark visibility check", "cl_deadeye_vischeck")
    panel:ControlHelp("Stops shooting if there's an obstacle between the target and you.")
    panel:CheckBox("Smooth mode", "cl_deadeye_smooth_aimbot")
    panel:ControlHelp("Instead of silently aiming at targets, aim at them smoothly.")

    panel:NumSlider("Mouse Sensitivity", "cl_deadeye_mouse_sensitivity", 0, 100, 1)
    panel:ControlHelp("Only needed if smooth mode is off.")

    panel:NumSlider("Deadeye Time", "cl_deadeye_timer", 0, 100, 1)

    panel:NumSlider("Deadeye indicator X offset", "cl_deadeye_bar_offset_x", -9999, 9999, 1)
    panel:NumSlider("Deadeye indicator Y offset", "cl_deadeye_bar_offset_y", -9999, 9999, 1)
    panel:NumSlider("Deadeye indicator size", "cl_deadeye_bar_size", 0, 50, 1)

end

hook.Add("PopulateToolMenu", "deadeye_options_populate", function() 
    spawnmenu.AddToolMenuOption("Options", "Deadeye", "DeadeyeLol", "Settings", nil, nil, function(panel)
        panel:ClearControls()
        options(panel)
    end)
end)

hook.Add("AddToolMenuCategories", "deadeye_options_add", function() 
    spawnmenu.AddToolCategory("Options", "Deadeye", "Deadeye")
end)

