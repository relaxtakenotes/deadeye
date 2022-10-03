if not game.SinglePlayer() then 
	hook.Add("InitPostEntity", "deadeye_warning", function() 
		Derma_Message("Why are you playing in multiplayer?\nThis mod doesn't work at all in multiplayer and opens up severe security vulnerabilities.\nThis mod was disabled for your safety.\nDon't forget to change your mouse sensitivity if you have modified it!", "Deadeye", "wow frick u") 
	end) 
	return 
end

local deadeye_marks = {} -- used to update the cache
local deadeye_cached_positions = {} -- actual positions of the marks in real time
local current_target = {} -- just the first mark

local ang

local shooting_quota = 0
local total_mark_count = 0
local added_a_mark = false
local in_deadeye = false
local release_attack = false
local spamming = false

local previous_ammo = 0
local previous_wep = NULL

local pp_lerp = 0
local pp_fraction = 0.3
local mark_brightness = {}

local max_deadeye_timer = CreateConVar("cl_deadeye_timer", "10", {FCVAR_ARCHIVE}, "Timer, for you know what.", 1, 10000)
local deadeye_timer = max_deadeye_timer:GetFloat()
local deadeye_timer_fraction = 1

local background_sfx_id = 0
local no_ammo_spent_timer = 0
local previous_ammo_count = 0

local draw_deadeye_bar = CreateConVar("cl_deadeye_bar", "0", {FCVAR_ARCHIVE}, "Draw the deadeye charge bar", 0, 1)
local draw_deadeye_bar_style = CreateConVar("cl_deadeye_bar_mode", "1", {FCVAR_ARCHIVE}, "0 - bar, 1 - circular, like in the game", 0, 2)
local deadeye_bar_offset_x = CreateConVar("cl_deadeye_bar_offset_x", "0", {FCVAR_ARCHIVE}, "X axis offset", -9999, 9999)
local deadeye_bar_offset_y = CreateConVar("cl_deadeye_bar_offset_y", "0", {FCVAR_ARCHIVE}, "Y axis offset", -9999, 9999)
local deadeye_bar_size = CreateConVar("cl_deadeye_bar_size", "1", {FCVAR_ARCHIVE}, "Size multiplier", 0, 1000)
local deadeye_accurate = CreateConVar("cl_deadeye_accurate", "0", {FCVAR_ARCHIVE}, "Instead of aiming at the [hitbox position + offset], aim just at the hitbox position.", 0, 1)
local deadeye_infinite = CreateConVar("cl_deadeye_infinite", "0", {FCVAR_ARCHIVE}, "Make the thang infinite.", 0, 1)
local deadeye_transfer_to_ragdolls = CreateConVar("cl_deadeye_transfer_to_ragdolls", "0", {FCVAR_ARCHIVE}, "Transfer the marks of an entity that just died to their ragdoll. Requires keep corpses enabled. Also might be a bit wonky at times...", 0, 1)
local deadeye_vischeck = CreateConVar("cl_deadeye_vischeck", "0", {FCVAR_ARCHIVE}, "Stop wasting your ammo. I know that's how it's done in the game but just stop, okay?", 0, 1)

local mouse_sens = GetConVar("sensitivity")
local actual_sens = CreateConVar("cl_deadeye_mouse_sensitivity", "1", {FCVAR_ARCHIVE}, "Due to the silent aim method, there needs to be more mouse precision and so the sensitivity is overriden. Use this convar to change your mouse sens.", -9999, 9999)

sound.Add( {
	name = "deadeye_start",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = 100,
	sound = {"deadeye/start1.wav", "deadeye/start2.wav"} 
})

sound.Add( {
	name = "deadeye_mark",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = {95,105},
	sound = "deadeye/mark.wav"
})

sound.Add( {
	name = "deadeye_end",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = 100,
	sound = "deadeye/end.wav"
})

sound.Add( {
	name = "deadeye_background",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = 100,
	sound = "deadeye/background.wav"
})


local function toggle_deadeye()
	if spamming then return end
	spamming = true
	timer.Simple(0.1, function() spamming = false end)
	local has_no_ammo = (LocalPlayer():GetActiveWeapon().Clip1 and LocalPlayer():GetActiveWeapon():Clip1() == 0)
	if not LocalPlayer():Alive() or has_no_ammo then
		in_deadeye = false
	else
		in_deadeye = !in_deadeye
	end

    net.Start("in_deadeye")
    	net.WriteBool(in_deadeye)
    net.SendToServer()

    if not in_deadeye then
		LocalPlayer():EmitSound("deadeye_end")
		LocalPlayer():StopLoopingSound(background_sfx_id)
    end

    if in_deadeye then 	
    	LocalPlayer():EmitSound("deadeye_start") 
    	background_sfx_id = LocalPlayer():StartLoopingSound("deadeye_background")
    end

	deadeye_marks = {} 
	deadeye_cached_positions = {}
    shooting_quota = 0
    total_mark_count = 0
    mark_brightness = {}
end

local function get_hitbox_info(ent, hitboxid)
	// hitboxid from the trace
	// ent is the entity related to it
	local set_number, set_string = ent:GetHitboxSet()
	return ent:GetBonePosition(ent:GetHitBoxBone(hitboxid, set_number))
end

local function get_hitbox_matrix(ent, hitboxid)
	// hitboxid from the trace
	// ent is the entity related to it
	local set_number, set_string = ent:GetHitboxSet()
	return ent:GetBoneMatrix(ent:GetHitBoxBone(hitboxid, set_number))
end

local function create_deadeye_point()
	// deadeye_mark concommand
	if not in_deadeye then return end
	if total_mark_count >= LocalPlayer():GetActiveWeapon():Clip1() then return end

	local lp = LocalPlayer()

	local tr = util.TraceLine( {
		start = LocalPlayer():EyePos(),
		endpos = LocalPlayer():EyePos() + LocalPlayer():EyeAngles():Forward() * 10000,
		filter = LocalPlayer(),
		mask = MASK_SHOT_PORTAL
	})

	if not IsValid(tr.Entity) or not tr.Entity:IsNPC() then return end

	//debugoverlay.Line(tr.HitPos, tr.StartPos, 5, Color(255, 0, 0), true)

	added_a_mark = true

	local matrix = get_hitbox_matrix(tr.Entity, tr.HitBox)
	tr.HitPos = tr.HitPos + (matrix:GetTranslation() - tr.HitPos):GetNormalized() + (tr.HitPos - tr.StartPos):GetNormalized() * 2

	matrix:SetTranslation(matrix:GetTranslation() - tr.HitPos)

	data = {}
	data.hitbox_id = tr.HitBox
	data.relative_pos_to_hitbox = matrix:GetTranslation()
	data.initial_rotation = tr.Entity:GetAngles()
	data.relative_pos_to_hitbox:Rotate(-data.initial_rotation)
	data.order = total_mark_count

	if not deadeye_marks[tr.Entity:EntIndex()] then deadeye_marks[tr.Entity:EntIndex()] = {} end
	table.insert(deadeye_marks[tr.Entity:EntIndex()], data)

	total_mark_count = total_mark_count + 1
	LocalPlayer():EmitSound("deadeye_mark")
end

local function get_correct_mark_pos(ent, data)
	// used to fill the mark cache
	// with proper rotations... more or less?
	local matrix = get_hitbox_matrix(ent, data.hitbox_id)
	local relative_pos = Vector(data.relative_pos_to_hitbox:Unpack())

	relative_pos:Rotate(ent:GetAngles())
	matrix:SetTranslation(matrix:GetTranslation() - relative_pos)

	return matrix:GetTranslation()
end

local function remove_mark(entindex, index)
	if deadeye_marks[entindex] then table.remove(deadeye_marks[entindex], index) end
	if deadeye_cached_positions[entindex] then table.remove(deadeye_cached_positions[entindex], index) end
	total_mark_count = math.abs(total_mark_count - 1)
end

local function get_first_mark()
	// bandaid fix for misordered shots
	// could, in theory, fix it by changing the fundementals of how i store marks but who cares lol

	local smallest_order
	for entindex, cache_table in pairs(deadeye_cached_positions) do
		for i, mark in ipairs(cache_table) do
			if not smallest_order then smallest_order = mark.data.order end
			smallest_order = math.min(smallest_order, mark.data.order)
		end
	end

	for entindex, cache_table in pairs(deadeye_cached_positions) do
		for i, mark in ipairs(cache_table) do
			if mark.data.order == smallest_order then
				return mark
			end
		end
	end

	return {}
end

local function fix_movement(cmd, fa)
	local vec = Vector(cmd:GetForwardMove(), cmd:GetSideMove(), 0)
	local vel = math.sqrt(vec.x * vec.x + vec.y * vec.y)
	local mang = vec:Angle()
	local yaw = cmd:GetViewAngles().y - fa.y + mang.y
 
	if ( ( cmd:GetViewAngles().p + 90 ) % 360 ) > 180 then
		yaw = 180 - yaw
	end
 
	yaw = ( ( yaw + 180 ) % 360 ) - 180

	cmd:SetForwardMove( math.cos( math.rad( yaw ) ) * vel )
	cmd:SetSideMove( math.sin( math.rad( yaw ) ) * vel )
end


local function on_primary_attack(ent)
	if not in_deadeye then return end

	local weapon = ent:GetActiveWeapon()
	net.Start("deadeye_primaryfire_time")
	net.WriteBool(true)
	net.SendToServer()
	local delay = math.abs(weapon:GetNextPrimaryFire() - CurTime()) * 0.3

	shooting_quota = shooting_quota - 1

	local mark = get_first_mark()
	if table.Count(mark) <= 0 then return end
	remove_mark(mark.entindex, mark.index)
	release_attack = true
	timer.Simple(delay, function()
		release_attack = false
	end)
end

hook.Add("CreateMove", "deadeye_detect_primaryfire", function(cmd) 
	local ply = LocalPlayer()
	if not ply:Alive() then return end
	local wep = ply:GetActiveWeapon()
	if not wep then return end
	if not wep.Clip1 then return end
	local current_ammo = wep:Clip1()
	if current_ammo < previous_ammo and not (wep != previous_wep) then
		on_primary_attack(ply, wep)
	end
	
	previous_ammo = current_ammo
	previous_wep = wep
end)

hook.Add("CreateMove", "deadeye_aimbot", function(cmd)
	// update real view angle for silent aimbot
	if (!ang) then ang = cmd:GetViewAngles() end
	ang = ang + Angle(cmd:GetMouseY() * .023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), cmd:GetMouseX() * -.023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), 0)
	if cmd:KeyDown(IN_ATTACK) and cmd:KeyDown(IN_USE) and LocalPlayer():GetActiveWeapon():GetClass() == "weapon_physgun" then
		ang = cmd:GetViewAngles() -- physgun prop rotating causes desync with the actual view angle
	end
	ang.x = math.NormalizeAngle(ang.x)
	ang.p = math.Clamp(ang.p, -89, 89)
	cmd:SetViewAngles(ang)

	if max_deadeye_timer:GetFloat() <= 0 then
		max_deadeye_timer:SetFloat(1)
	end

	if not in_deadeye then 
		added_a_mark = false
		if not deadeye_infinite:GetBool() then deadeye_timer = math.Clamp(deadeye_timer + deadeye_timer_fraction * FrameTime(), 0, max_deadeye_timer:GetFloat()) end
		return 
	end

	if not deadeye_infinite:GetBool() then deadeye_timer = math.Clamp(deadeye_timer - deadeye_timer_fraction * FrameTime() / 0.3, 0, max_deadeye_timer:GetFloat()) end

	if not LocalPlayer():Alive() then
		toggle_deadeye()
	    return
	end

	// causes toggle_deadeye() to activate below
	if deadeye_timer <= 0 and shooting_quota <= 0 and total_mark_count > 0 and not cmd:KeyDown(IN_ATTACK) then
		cmd:AddKey(IN_ATTACK)
	end

	// filling the mark cache
	for entindex, data_table in pairs(deadeye_marks) do
		for i, data in ipairs(data_table) do
			local mark_cache = {}
			mark_cache.pos = get_correct_mark_pos(Entity(entindex), data)
			mark_cache.entindex = entindex
			mark_cache.data = data
			mark_cache.index = i

			if not deadeye_cached_positions[entindex] then deadeye_cached_positions[entindex] = {} end
			deadeye_cached_positions[entindex][i] = mark_cache
		end
	end

	current_target = get_first_mark()

	// no more marks, reset the quota and turn off deadeye after we're done shooting
	if total_mark_count <= 0 then
		shooting_quota = 0
		if added_a_mark or deadeye_timer <= 0 then
			toggle_deadeye()
		end
	end

	if not LocalPlayer():GetActiveWeapon().Clip1 or LocalPlayer():GetActiveWeapon():Clip1() == 0 then
		toggle_deadeye()
	    return
	end

	// check if there are more marks than bullets and fill the quota if that's the case... or if we're attacking
	if total_mark_count >= LocalPlayer():GetActiveWeapon():Clip1() or cmd:KeyDown(IN_ATTACK) then
		shooting_quota = total_mark_count
	end

	// we have a quota to work for and we have available marks, shoot!!!
	if shooting_quota > 0 and not cmd:KeyDown(IN_ATTACK) and total_mark_count > 0 then
		cmd:AddKey(IN_ATTACK)
	end

	// this weird no ammo spent timer thing is to ensure we shoot at all, cuz some weapons just dont give us the proper delay
	if release_attack or (no_ammo_spent_timer >= 1 and shooting_quota > 0 and total_mark_count > 0) then
		if cmd:KeyDown(IN_ATTACK) then cmd:RemoveKey(IN_ATTACK) end
		no_ammo_spent_timer = 0
	elseif shooting_quota > 0 and total_mark_count > 0 then
		no_ammo_spent_timer = math.Clamp(no_ammo_spent_timer + 20 * FrameTime(), 0, 1)
	end

	//print(total_mark_count, shooting_quota)

	// do the silent aimbot shit
	if cmd:CommandNumber() == 0 then
		cmd:SetViewAngles(ang)
		return
	end

	// deadeye aka aimbot
	if current_target.entindex and cmd:KeyDown(IN_ATTACK) then
		local tr = util.TraceLine( {
			start = LocalPlayer():GetShootPos(),
			endpos = current_target.pos,
			filter = LocalPlayer(),
			mask = MASK_SHOT_PORTAL
		})

		if deadeye_vischeck:GetBool() and Entity(current_target.entindex):GetClass() != "prop_ragdoll" and tr.HitPos != current_target.pos and tr.Entity:EntIndex() != current_target.entindex then
			if cmd:KeyDown(IN_ATTACK) then cmd:RemoveKey(IN_ATTACK) end
		end

		local aimangles = (current_target.pos - LocalPlayer():GetShootPos() - LocalPlayer():GetVelocity() * engine.TickInterval()):Angle()
		cmd:SetViewAngles(aimangles)
		fix_movement(cmd, ang)
	end
end)

hook.Add("EntityRemoved", "deadeye_cleanup_transfer", function(ent)
	if not ent:IsNPC() or not deadeye_transfer_to_ragdolls:GetBool() then return end
	local found_ragdoll = false
	local entidx = ent:EntIndex()
	local model_name = ent:GetModel()
	local bonepos = ent:GetBonePosition(0)
	
	local tr = util.TraceHull( {
		start = bonepos,
		endpos = bonepos,
		mins = Vector(-10, -10, -10),
		maxs = Vector(10, 10, 10),
		mask = MASK_SHOT_PORTAL,
		filter = function(entity) if entity:GetClass() == "prop_ragdoll" and entity:GetModel() == model_name then return true end end
	})

	if IsValid(tr.Entity) then
		deadeye_marks[tr.Entity:EntIndex()] = deadeye_marks[entidx]
		deadeye_cached_positions[tr.Entity:EntIndex()] = deadeye_cached_positions[entidx]
		found_ragdoll = true
	end

	if total_mark_count > 0 and not found_ragdoll then
		if not deadeye_marks[entidx] then return end
		total_mark_count = total_mark_count - table.Count(deadeye_marks[entidx])
	end

	deadeye_marks[entidx] = nil
	deadeye_cached_positions[entidx] = nil
end)

hook.Add("EntityRemoved", "deadeye_cleanup_classic", function(ent)
	if not ent:IsNPC() or deadeye_transfer_to_ragdolls:GetBool() then return end
	local entidx = ent:EntIndex()

	if total_mark_count > 0 then
		if not deadeye_marks[entidx] then return end
		total_mark_count = total_mark_count - table.Count(deadeye_marks[entidx])
	end

	deadeye_marks[entidx] = nil
	deadeye_cached_positions[entidx] = nil
end)

hook.Add("ChatText", "deadeye_hide_cvar_changes", function(index, name, text, type)
	if type != "servermsg" then return end
	if string.find(text, "sv_tfa_spread_multiplier") then return true end
	if string.find(text, "sv_tfa_soundscale") then return true end
end)

hook.Add("InitPostEntity", "deadeye_stuff", function() 
	LocalPlayer():ChatPrint("[IMPORTANT INFO FOR DEADEYE MOD] During deadeye, the mouse accuracy is reduced due to the method used to aim. To increase said accuracy, please change the sensitivity convar to higher values. If you need to actually change your mouse speed, please change the cl_deadeye_mouse_sensitivity convar")
end)

local pp_in_deadeye = {
	["$pp_colour_addr"] = 0.60,
	["$pp_colour_addg"] = 0.35,
	["$pp_colour_addb"] = 0.13,
	["$pp_colour_brightness"] = -0.4,
	["$pp_colour_contrast"] = 0.7,
	["$pp_colour_colour"] = 0.8,
}

local pp_out_deadeye = {
	["$pp_colour_addr"] = 0,
	["$pp_colour_addg"] = 0,
	["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0,
	["$pp_colour_contrast"] = 1,
	["$pp_colour_colour"] = 1,
}

local vignettemat = Material("overlays/vignette01")
hook.Add("RenderScreenspaceEffects", "deadeye_overlay", function()
	local tab = {
		["$pp_colour_addr"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addr"], pp_in_deadeye["$pp_colour_addr"]),
		["$pp_colour_addg"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addg"], pp_in_deadeye["$pp_colour_addg"]),
		["$pp_colour_addb"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addb"], pp_in_deadeye["$pp_colour_addb"]),
		["$pp_colour_brightness"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_brightness"], pp_in_deadeye["$pp_colour_brightness"]),
		["$pp_colour_contrast"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_contrast"], pp_in_deadeye["$pp_colour_contrast"]),
		["$pp_colour_colour"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_colour"], pp_in_deadeye["$pp_colour_colour"]),
	}

	if in_deadeye then
		pp_lerp = math.Clamp(pp_lerp + pp_fraction * 50 * FrameTime(), 0, 1)
		tab["$pp_colour_brightness"] = Lerp(pp_lerp, 0.8, pp_in_deadeye["$pp_colour_brightness"])
	else
		pp_lerp = math.Clamp(pp_lerp - pp_fraction * 20 * FrameTime(), 0, 1)
	end

	if pp_lerp > 0 then
		DrawColorModify(tab)
		render.UpdateScreenEffectTexture()
		vignettemat:SetFloat("$alpha", pp_lerp)
		render.SetMaterial(vignettemat)
		render.DrawScreenQuad()
	end
end)

local deadeye_cross = Material("deadeye/deadeye_cross")
local deadeye_core = Material("deadeye/deadeye_core")
local blank_material = Material("color")
local deadeye_core_circle = Material("deadeye/rpg_meter_track_9")

local function draw_circ_bar(x, y, w, h, progress, color)
	// https://gist.github.com/Joseph10112/6e6e896b5feee50f7aa2145aabaf6e8c
	// i love pasting xD

	if deadeye_infinite:GetBool() then
		// just a lil optimization i thought would be nice
		surface.SetDrawColor(color)
		surface.SetMaterial(deadeye_core_circle)
		surface.DrawTexturedRect(x, y, w, h)		
	end

	local dummy = {}
	table.insert(dummy, {x = x + (w / 2), y = y + (h / 2)})
	for i = 180, -180 + progress * 360, -1 do
		table.insert(dummy, {x = x + (w / 2) + math.sin(math.rad(i)) * w, y = y + (h / 2) + math.cos(math.rad(i)) * h})
	end
	table.insert(dummy, {x = x + (w / 2), y = y + (h / 2)})
	
	render.SetStencilWriteMask(-1)
	render.SetStencilTestMask(-1)
	render.SetStencilReferenceValue(0)
	
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	render.SetStencilPassOperation(STENCILOPERATION_KEEP)
	render.SetStencilFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.ClearStencil()

	render.SetStencilEnable(true)
		render.SetStencilReferenceValue(1)
		render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
		
		surface.SetDrawColor(Color(255, 255, 255))
		surface.DrawPoly(dummy)
		render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)

		surface.SetDrawColor(color)
		surface.SetMaterial(deadeye_core_circle)
		surface.DrawTexturedRect(x, y, w, h)
		
	render.SetStencilEnable(false)
end

hook.Add("HUDPaint", "deadeye_mark_render", function()
	if in_deadeye then
		surface.SetMaterial(deadeye_cross)
		for entindex, cache_table in pairs(deadeye_cached_positions) do
			for i, mark in ipairs(cache_table) do
				local pos2d = mark.pos:ToScreen()
				// bruh
				local color_blink
				if Entity(entindex):GetClass() != "prop_ragdoll" then
					if not mark_brightness[entindex] then mark_brightness[entindex] = {} end
					if not mark_brightness[entindex][mark.index] then mark_brightness[entindex][mark.index] = 1 end
					mark_brightness[entindex][mark.index] = math.Clamp(mark_brightness[entindex][mark.index] - 30 * FrameTime(), 0, 1)
					color_blink = math.Remap(mark_brightness[entindex][mark.index], 0, 1, 0, 255)
				else
					color_blink = 0
				end

				surface.SetDrawColor(255, color_blink, color_blink, 255)
				surface.DrawTexturedRect(pos2d.x-8, pos2d.y-8, 16, 16)
			end
		end
	end

	// i'll improve the position calculations later :unaware:
	if draw_deadeye_bar:GetBool() then
		if draw_deadeye_bar_style:GetInt() == 0 then
			surface.SetDrawColor(0, 0, 0, 128)
			surface.DrawRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), 150*deadeye_bar_size:GetFloat(), 12*deadeye_bar_size:GetFloat())

			if deadeye_infinite:GetBool() then 
				surface.SetDrawColor(255, 190, 48, 128)
			else
				surface.SetDrawColor(255, 255, 255, 128)
			end

			surface.DrawRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), math.Remap(deadeye_timer, 0, max_deadeye_timer:GetFloat(), 0, 150)*deadeye_bar_size:GetFloat(), 12*deadeye_bar_size:GetFloat())
		else
			surface.SetMaterial(deadeye_core)
			if deadeye_infinite:GetBool() then 
				surface.SetDrawColor(255, 190, 48, 255)
			else
				surface.SetDrawColor(255, 255, 255, 255)
			end
			surface.DrawTexturedRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), 42*deadeye_bar_size:GetFloat(), 42*deadeye_bar_size:GetFloat())
			
			local progress = math.Remap(deadeye_timer, 0, max_deadeye_timer:GetFloat(), 1, 0)

			if progress != 1 then
				local color
				if deadeye_infinite:GetBool() then 
					color = Color(255, 190, 48, 255)
				else
					color = Color(255, 255, 255, 255)
				end

				draw_circ_bar(34-(5.5*deadeye_bar_size:GetFloat())+deadeye_bar_offset_x:GetFloat(), ScrH()-250-(5.5*deadeye_bar_size:GetFloat())-deadeye_bar_offset_y:GetFloat(), 53*deadeye_bar_size:GetFloat(), 53*deadeye_bar_size:GetFloat(), progress, color)
			end
		end
	end
end)

concommand.Add("cl_deadeye_mark", create_deadeye_point)
concommand.Add("cl_deadeye_clear", function() deadeye_marks = {} end)
concommand.Add("cl_deadeye_toggle", toggle_deadeye)