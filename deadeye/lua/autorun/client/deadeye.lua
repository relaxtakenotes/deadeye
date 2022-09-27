local deadeye_marks = {} -- used to update the cache
local deadeye_cached_positions = {} -- actual positions of the marks in real time
local current_target = {} -- just the first mark

local ang

local shooting_quota = 0
local total_mark_count = 0
local added_a_mark = false
local in_deadeye = false
local release_attack = false

local pp_lerp = 0
local pp_fraction = 0.3

local deadeye_timer = 10
local max_deadeye_timer = 10
local deadeye_timer_fraction = 1

local background_sfx_id = 0

local draw_deadeye_bar = CreateConVar("cl_deadeye_bar", "0", {FCVAR_ARCHIVE}, "Draw the deadeye charge bar", 0, 1)
local draw_deadeye_bar_style = CreateConVar("cl_deadeye_bar_mode", "0", {FCVAR_ARCHIVE}, "0 - seconds, 1 - percentage, 2 - just the bar", 0, 2)
local deadeye_bar_offset_x = CreateConVar("cl_deadeye_bar_offset_x", "0", {FCVAR_ARCHIVE}, "X axis offset", -9999, 9999)
local deadeye_bar_offset_y = CreateConVar("cl_deadeye_bar_offset_y", "0", {FCVAR_ARCHIVE}, "Y axis offset", -9999, 9999)

local mouse_sens = GetConVar("sensitivity")
local actual_sens = CreateConVar("cl_deadeye_mouse_sensitivity", mouse_sens:GetFloat(), {FCVAR_ARCHIVE}, "Due to the silent aim method, there needs to be more mouse precision and so the sensitivity is overriden. Use this convar to change your mouse sens.", -9999, 9999)

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
	pitch = 100,
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
    in_deadeye = !in_deadeye

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
end

local function get_hitbox_info(ent, hitboxid)
	// hitboxid from the trace
	// ent is the entity related to it
	return ent:GetBonePosition(ent:GetHitBoxBone(hitboxid, 0))
end

local function create_deadeye_point()
	// deadeye_mark concommand
	if not in_deadeye then return end
	if total_mark_count >= LocalPlayer():GetActiveWeapon():Clip1() then return end

	local lp = LocalPlayer()
	local tr = lp:GetEyeTrace()
	if not IsValid(tr.Entity) or not tr.Entity:IsNPC() then print("invalid target") return end
	debugoverlay.Line(tr.HitPos, tr.StartPos, 5, Color(255, 0, 0), true)

	added_a_mark = true
	local pos, angle = get_hitbox_info(tr.Entity, tr.HitBox)

	data = {}
	data.hitbox_id = tr.HitBox
	data.relative_pos_to_hitbox = pos - tr.HitPos
	// get rid of the current rotation so that we can rotate the point ourselves later
	data.relative_pos_to_hitbox:Rotate(-tr.Entity:GetAngles())

	if not deadeye_marks[tr.Entity:EntIndex()] then deadeye_marks[tr.Entity:EntIndex()] = {} end
	table.insert(deadeye_marks[tr.Entity:EntIndex()], data)

	total_mark_count = total_mark_count + 1
	LocalPlayer():EmitSound("deadeye_mark")
end

local function get_correct_mark_pos(ent, data)
	// used to fill the mark cache

	local pos, angle = get_hitbox_info(ent, data.hitbox_id)
	debugoverlay.Cross(pos, 3, 0.1, Color(255, 0, 0), true)

	local corrected_relative_pos = Vector(data.relative_pos_to_hitbox.x, data.relative_pos_to_hitbox.y, data.relative_pos_to_hitbox.z)
	corrected_relative_pos:Rotate(ent:GetAngles())
	local corrected_pos = pos - corrected_relative_pos

	debugoverlay.Line(pos, corrected_pos, 0.1, Color(50, 100, 255), true)
	return corrected_pos
end

local function remove_mark(entindex, index)
	table.remove(deadeye_marks[entindex], index)
	table.remove(deadeye_cached_positions[entindex], index)
	total_mark_count = math.abs(total_mark_count - 1)
end

local function get_first_mark()
	for entindex, cache_table in pairs(deadeye_cached_positions) do
		for i, mark in ipairs(cache_table) do
			return mark
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

net.Receive("deadeye_firebullet", function(len)
	if not in_deadeye then return end

	print("received", CurTime())

	local ent = net.ReadEntity()
	local delay = net.ReadFloat()

	shooting_quota = shooting_quota - 1

	local mark = get_first_mark()
	if table.Count(mark) <= 0 then return end
	remove_mark(mark.entindex, mark.index)
	release_attack = true
	timer.Simple(delay, function() 
		release_attack = false
	end)
end)

hook.Add("CreateMove", "deadeye_aimbot", function(cmd)
	// update real view angle for silent aimbot
	if (!ang) then ang = cmd:GetViewAngles() end
	ang = ang + Angle(cmd:GetMouseY() * .023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), cmd:GetMouseX() * -.023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), 0)
	ang.x = math.NormalizeAngle(ang.x)
	ang.p = math.Clamp(ang.p, -89, 89)
	cmd:SetViewAngles(ang)

	if not in_deadeye then 
		added_a_mark = false
		deadeye_timer = math.Clamp(deadeye_timer + deadeye_timer_fraction * FrameTime(), 0, max_deadeye_timer)
		return 
	end


	deadeye_timer = math.Clamp(deadeye_timer - deadeye_timer_fraction * FrameTime() / 0.3, 0, max_deadeye_timer)

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

			debugoverlay.Cross(mark_cache.pos, 3, 0.1, Color(255, 255, 255), true)
		end
	end

	current_target = get_first_mark()

	// no more marks, reset the quota and turn off deadeye after we're done shooting
	if total_mark_count <= 0 then
		shooting_quota = 0
		if added_a_mark then
			toggle_deadeye()
		end
	end

	// check if there are more marks than bullets and fill the quota if that's the case... or if we're attacking
	if total_mark_count >= LocalPlayer():GetActiveWeapon():Clip1() or cmd:KeyDown(IN_ATTACK) then
		shooting_quota = total_mark_count
	end

	// we have a quota to work for and we have available marks, shoot!!!
	if shooting_quota > 0 and not cmd:KeyDown(IN_ATTACK) and total_mark_count > 0 then
		cmd:AddKey(IN_ATTACK)
	end

	if release_attack then
		if cmd:KeyDown(IN_ATTACK) then cmd:RemoveKey(IN_ATTACK) end
	end

	//print(total_mark_count, shooting_quota)

	// do the silent aimbot shit
	if (cmd:CommandNumber() == 0) then
		cmd:SetViewAngles(ang)
		return
	end

	// deadeye aka aimbot
	if current_target.entindex and cmd:KeyDown(IN_ATTACK) then
		local aimangles = (current_target.pos - LocalPlayer():GetShootPos() - LocalPlayer():GetVelocity() * engine.TickInterval()):Angle()
		cmd:SetViewAngles(aimangles)
		fix_movement(cmd, ang)
	end
end)

hook.Add("EntityRemoved", "deadeye_cleanup", function(ent)
	if total_mark_count > 0 then
		if not deadeye_marks[ent:EntIndex()] then return end
		total_mark_count = total_mark_count - table.Count(deadeye_marks[ent:EntIndex()])
	end
	deadeye_marks[ent:EntIndex()] = nil
	deadeye_cached_positions[ent:EntIndex()] = nil
end)

hook.Add("ChatText", "deadeye_hide_cvar_changes", function(index, name, text, type)
	if type != "servermsg" then return end
	if string.find(text, "sv_tfa_spread_multiplier") then return true end
end)

hook.Add("InitPostEntity", "deadeye_chat_info", function() 
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

	DrawColorModify(tab)
	render.UpdateScreenEffectTexture()
	vignettemat:SetFloat("$alpha", pp_lerp)
	render.SetMaterial(vignettemat)
	render.DrawScreenQuad()
end)

local material = Material("deadeye/deadeye_cross")
hook.Add("HUDPaint", "deadeye_mark_render", function()
	surface.SetDrawColor(255, 0, 0, 255)
	surface.SetMaterial(material)

	for entindex, cache_table in pairs(deadeye_cached_positions) do
		for i, mark in ipairs(cache_table) do
			local pos2d = mark.pos:ToScreen()
			surface.DrawTexturedRect(pos2d.x-8, pos2d.y-8, 16, 16)
		end
	end

	if draw_deadeye_bar:GetBool() then
		surface.SetDrawColor(0, 0, 0, 128)
		surface.DrawRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), 150, 12)

		surface.SetDrawColor(255, 255, 255, 128)
		surface.DrawRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), math.Remap(deadeye_timer, 0, max_deadeye_timer, 0, 150), 12)

		if draw_deadeye_bar_style:GetInt() == 0 then
			surface.SetFont("DermaDefault")
			surface.SetTextColor(0, 0, 0)
			surface.SetTextPos(36+deadeye_bar_offset_x:GetFloat(), ScrH()-251-deadeye_bar_offset_y:GetFloat())
			surface.DrawText(string.format("%.2f",deadeye_timer))
		elseif draw_deadeye_bar_style:GetInt() == 1 then
			surface.SetFont("DermaDefault")
			surface.SetTextColor(0, 0, 0)
			surface.SetTextPos(36+deadeye_bar_offset_x:GetFloat(), ScrH()-251-deadeye_bar_offset_y:GetFloat())
			surface.DrawText(string.format("%.2f",deadeye_timer/max_deadeye_timer*100).."%")
		end
	end
end)

concommand.Add("cl_deadeye_mark", create_deadeye_point)
concommand.Add("cl_deadeye_clear", function() deadeye_marks = {} end)
concommand.Add("cl_deadeye_toggle", toggle_deadeye)
concommand.Add("cl_deadeye_timer", function(ply,cmd,args)
	if not args[1] then print("This command changes the deadeye timer. Default value is 10 seconds. Enter any value to change it.") return end
	deadeye_timer = args[1]
	max_deadeye_timer = args[1]
	print("Changed deadeye timer to ", args[1])
end)