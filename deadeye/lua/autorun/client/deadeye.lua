// im not proud of this

local deadeye_marks = {} -- used to update the cache
local deadeye_cached_positions = {} -- actual positions of the marks in real time
local current_target = {} -- just the first mark
local last_target = {}
local start_angle = Angle()
local aim_lerp_ratio = 0
local transferred_ragdolls = {}
local gAimangles = Angle()

local ang

local shooting_quota = 0
local total_mark_count = 0
local added_a_mark = false
local in_deadeye = false
local release_attack = false
local spamming = false
local wait_for_target_switch = false
local current_attack_delay = 0

local previous_ammo = 0
local previous_wep = NULL
local previous_ammo_count = 0

local pp_lerp = 0
local pp_no_deadeye_lerp = 0
local distort_lerp = 0
local pp_fraction = 0.3
local mark_brightness = {}

local max_deadeye_timer = CreateConVar("cl_deadeye_timer", "10", {FCVAR_ARCHIVE}, "Timer, for you know what.", 1, 10000)
local deadeye_timer = max_deadeye_timer:GetFloat()
local deadeye_timer_fraction = 1

local background_sfx_id = 0
local no_ammo_spent_timer = 0

local deadeye_slowdown = CreateConVar("cl_deadeye_slowdown", "1", {FCVAR_ARCHIVE}, "Slow down the time when using deadeye.", 0, 1)
local draw_deadeye_bar = CreateConVar("cl_deadeye_bar", "1", {FCVAR_ARCHIVE}, "Draw the deadeye charge bar", 0, 1)
local draw_deadeye_bar_style = CreateConVar("cl_deadeye_bar_mode", "1", {FCVAR_ARCHIVE}, "0 - bar, 1 - circular, like in the game", 0, 2)
local deadeye_bar_offset_x = CreateConVar("cl_deadeye_bar_offset_x", "0", {FCVAR_ARCHIVE}, "X axis offset", -9999, 9999)
local deadeye_bar_offset_y = CreateConVar("cl_deadeye_bar_offset_y", "0", {FCVAR_ARCHIVE}, "Y axis offset", -9999, 9999)
local deadeye_bar_size = CreateConVar("cl_deadeye_bar_size", "1", {FCVAR_ARCHIVE}, "Size multiplier", 0, 1000)
local deadeye_infinite = CreateConVar("cl_deadeye_infinite", "0", {FCVAR_ARCHIVE}, "Make the thang infinite.", 0, 1)
local deadeye_transfer_to_ragdolls = CreateConVar("cl_deadeye_transfer_to_ragdolls", "0", {FCVAR_ARCHIVE}, "Transfer the marks of an entity that just died to their ragdoll. Requires keep corpses enabled. Also might be a bit wonky at times...", 0, 1)
local deadeye_vischeck = CreateConVar("cl_deadeye_vischeck", "0", {FCVAR_ARCHIVE}, "Stop wasting your ammo. I know that's how it's done in the game but just stop, okay?", 0, 1)
local deadeye_smooth_aimbot = CreateConVar("cl_deadeye_smooth_aimbot", "1", {FCVAR_ARCHIVE}, "Instead of aiming silenty, aim smoothly and visibly. Turns off the dumb sensitivity gimmick.", 0, 1)
local deadeye_target_switch_delay = CreateConVar("cl_deadeye_target_delay", "0.05", {FCVAR_ARCHIVE}, "Wait for the given seconds before switching to a different aim point", 0, 2)
local deadeye_debug = CreateConVar("cl_deadeye_debug", "0", {FCVAR_ARCHIVE}, "Debug!!!", 0, 1)

local mouse_sens = GetConVar("sensitivity")
local actual_sens = CreateConVar("cl_deadeye_mouse_sensitivity", "1", {FCVAR_ARCHIVE}, "Due to the silent aim method, there needs to be more mouse precision and so the sensitivity is overriden. Use this convar to change your mouse sens.", -9999, 9999)

if not game.SinglePlayer() then 
	hook.Add("InitPostEntity", "deadeye_warning", function() 
		Derma_Message("Deadeye doesn't formally support MultiPlayer, however if you are fine with a few bugs and play only with your friends you can enjoy this mod. If otherwise please play on SinglePlayer!", "Notice", "ok ty")
	end)
end

sound.Add({
	name = "deadeye_start",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = {95,105},
	sound = {"deadeye/start1.wav", "deadeye/start2.wav"} 
})

sound.Add({
	name = "deadeye_mark",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = {95,105},
	sound = "deadeye/mark.wav"
})

sound.Add({
	name = "deadeye_click",
	channel = CHAN_STATIC,
	volume = 0.5,
	level = 0,
	pitch = {98,102},
	sound = "deadeye/click.wav"
})


sound.Add({
	name = "deadeye_end",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = {95,105},
	sound = "deadeye/end.wav"
})

sound.Add({
	name = "deadeye_background",
	channel = CHAN_STATIC,
	volume = 1.0,
	level = 0,
	pitch = {95,105},
	sound = "deadeye/background.wav"
})

local background_sfx = NULL

local function toggle_deadeye()
	if spamming then return end
	spamming = true
	timer.Simple(0.1, function() spamming = false end)

	if not LocalPlayer():Alive() or not LocalPlayer():GetActiveWeapon().Clip1 or LocalPlayer():GetActiveWeapon():Clip1() == 0 or (deadeye_timer < 1 and not deadeye_infinite:GetBool()) then

	    net.Start("in_deadeye")
	    	net.WriteBool(false)
	    	net.WriteBool(deadeye_slowdown:GetBool())
	    net.SendToServer()

	    if not in_deadeye then
	    	LocalPlayer():EmitSound("deadeye_click")
			pp_no_deadeye_lerp = 1
		else
			LocalPlayer():EmitSound("deadeye_end")
	    end
		in_deadeye = false
		if background_sfx != NULL then background_sfx:Stop() end
		return
	end

	in_deadeye = !in_deadeye

    net.Start("in_deadeye")
    	net.WriteBool(in_deadeye)
    	net.WriteBool(deadeye_slowdown:GetBool())
    net.SendToServer()

    if not in_deadeye then
		LocalPlayer():EmitSound("deadeye_end")
		background_sfx:Stop()
		//LocalPlayer():StopLoopingSound(background_sfx_id)
    end

    if in_deadeye then 	
    	LocalPlayer():EmitSound("deadeye_start")

    	background_sfx = CreateSound(LocalPlayer(), "deadeye/background.wav")
    	background_sfx:SetSoundLevel(0)
    	background_sfx:Play()
    	//background_sfx_id = LocalPlayer():StartLoopingSound("deadeye_background")
    end

	deadeye_marks = {} 
	deadeye_cached_positions = {}
    shooting_quota = 0
    mark_brightness = {}
	added_a_mark = false
	no_ammo_spent_timer = 0
	release_attack = false
	pitch_changing = false
	aim_lerp_ratio = 0
	current_attack_delay = 0
	gAimangles = Angle()
end

local function is_usable_for_deadeye(ent)
	if not IsValid(ent) or not ent.GetModel or not ent.GetClass then return false end
	if not ent:GetModel() or not ent:GetClass() then return false end 
	local is_explosive = string.find(ent:GetModel(), "explosive") or string.find(ent:GetModel(), "gascan") or string.find(ent:GetModel(), "propane_tank") or string.find(ent:GetClass(), "npc_grenade_frag")

	if not ent:IsNPC() and not is_explosive and not ent:IsPlayer() then return false end

	return true
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

	local tr = util.TraceLine({
		start = LocalPlayer():EyePos(),
		endpos = LocalPlayer():EyePos() + LocalPlayer():EyeAngles():Forward() * 10000,
		filter = LocalPlayer(),
		mask = MASK_SHOT_PORTAL
	})

	if (tr.Entity == NULL or not IsValid(tr.Entity)) or not is_usable_for_deadeye(tr.Entity) then

		local tr_h = util.TraceHull({
			start = LocalPlayer():EyePos(),
			endpos = LocalPlayer():EyePos() + LocalPlayer():EyeAngles():Forward() * 10000,
			filter = LocalPlayer(),
			mins = Vector(-10, -10, -10),
			maxs = Vector(10, 10, 10),
			mask = MASK_SHOT_PORTAL
		})

		if (tr_h.Entity == NULL or not IsValid(tr_h.Entity)) or not is_usable_for_deadeye(tr_h.Entity) or not string.find(tr_h.Entity:GetClass(), "npc_grenade_frag") then return end

		tr = tr_h
	end

	added_a_mark = true

	local matrix = get_hitbox_matrix(tr.Entity, tr.HitBox)

	local precision_multiplier = math.Remap(tr.Fraction, 0, 1, 1, 10)
	tr.HitPos = tr.HitPos + (matrix:GetTranslation() - tr.HitPos):GetNormalized() * precision_multiplier + tr.Normal * 2

	data = {}
	data.hitbox_id = tr.HitBox
	data.initial_rotation = tr.Entity:GetAngles()
	if not string.find(tr.Entity:GetClass(), "npc_grenade_frag") then
		data.offset = matrix:GetTranslation() - tr.HitPos
		data.offset:Rotate(-data.initial_rotation)
	else
		data.offset = Vector()
	end
	data.order = total_mark_count

	if not deadeye_marks[tr.Entity:EntIndex()] then deadeye_marks[tr.Entity:EntIndex()] = {} end
	table.insert(deadeye_marks[tr.Entity:EntIndex()], data)

	LocalPlayer():EmitSound("deadeye_mark")
end

local function get_correct_mark_pos(ent, data)	
	local matrix = get_hitbox_matrix(ent, data.hitbox_id)
	local offset = Vector(data.offset:Unpack())

	if not matrix then // invalid cuz not rendered
		local pos, ang = get_hitbox_info(ent, data.hitbox_id)
		return pos - offset 
	end

	local pos = matrix:GetTranslation()
	offset:Rotate(ent:GetAngles())

	return pos - offset
end

local function remove_mark(entindex, index)
	print("removed", Entity(entindex), index)
	if deadeye_marks[entindex] then table.remove(deadeye_marks[entindex], index) end
	if deadeye_cached_positions[entindex] then table.remove(deadeye_cached_positions[entindex], index) end
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
 
	if ((cmd:GetViewAngles().p + 90) % 360) > 180 then
		yaw = 180 - yaw
	end
 
	yaw = ((yaw + 180) % 360) - 180

	cmd:SetForwardMove(math.cos(math.rad(yaw)) * vel)
	cmd:SetSideMove(math.sin(math.rad(yaw)) * vel)
end

net.Receive("deadeye_shot", function()
	if not in_deadeye then return end

	local weapon = LocalPlayer():GetActiveWeapon()
	local delay = net.ReadFloat()

	current_attack_delay = delay
	if shooting_quota > 0 then
		shooting_quota = total_mark_count
	end

	if game.SinglePlayer() then
		local tr = util.TraceHull({
			start = LocalPlayer():EyePos(),
			endpos = LocalPlayer():EyePos() + LocalPlayer():EyeAngles():Forward() * 10000,
			filter = LocalPlayer(),
			mins = Vector(-10, -10, -10),
			maxs = Vector(10, 10, 10),
			mask = MASK_SHOT_PORTAL
		})

		if tr.Entity and tr.Entity:GetClass() == "npc_grenade_frag" then
			net.Start("deadeye_destroy_grenade")
			net.WriteEntity(tr.Entity)
			net.SendToServer()
		end
	end

	if weapon:GetNextPrimaryFire() > 0 and delay < 2 and delay > 0 then
		release_attack = true
		timer.Simple(delay, function()
			release_attack = false
		end)
	end

	wait_for_target_switch = true
	if deadeye_slowdown:GetBool() then
		timer.Simple(deadeye_target_switch_delay:GetFloat() * 0.2, function() wait_for_target_switch = false end)
	else
	    timer.Simple(deadeye_target_switch_delay:GetFloat(), function() wait_for_target_switch = false end)
	end

	local mark = get_first_mark()
	if table.Count(mark) <= 0 then return end
	remove_mark(mark.entindex, mark.index)
end)

hook.Add("Think", "debug_deadyee", function() 
	if engine.TickCount() % 20 and deadeye_debug:GetBool() then
		print("----------------------------------")
		print("shooting_quota: ", shooting_quota)
		print("total_mark_count: ", total_mark_count)
		print("added_a_mark: ", added_a_mark)
		print("in_deadeye: ", in_deadeye)
		print("release_attack: ", release_attack)
		print("spamming: ", spamming)
		print("wait_for_target_switch: ", wait_for_target_switch)
		print("previous_ammo: ", previous_ammo)
		print("previous_wep: ", previous_wep)
		print("previous_ammo_count: ", previous_ammo_count)
		print("no_ammo_spent_timer: ", no_ammo_spent_timer)
		print("----------------------------------")
	end
end)

local already_aiming = false
local pitch_changing = false

hook.Add("CreateMove", "deadeye_aimbot", function(cmd)
	// update real view angle for silent aimbot
	if not deadeye_smooth_aimbot:GetBool() then
		if (!ang) then ang = cmd:GetViewAngles() end
		ang = ang + Angle(cmd:GetMouseY() * .023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), cmd:GetMouseX() * -.023 / mouse_sens:GetFloat() * actual_sens:GetFloat(), 0)
		if cmd:KeyDown(IN_ATTACK) and cmd:KeyDown(IN_USE) and LocalPlayer():GetActiveWeapon():GetClass() == "weapon_physgun" then
			ang = cmd:GetViewAngles() -- physgun prop rotating causes desync with the actual view angle
		end
		ang.x = math.NormalizeAngle(ang.x)
		ang.p = math.Clamp(ang.p, -89, 89)
		cmd:SetViewAngles(ang)
	end

	if max_deadeye_timer:GetFloat() <= 0 then
		max_deadeye_timer:SetFloat(1)
	end

	if not in_deadeye then
		start_angle = LocalPlayer():EyeAngles()
		if game.SinglePlayer() then 
			if not deadeye_infinite:GetBool() then deadeye_timer = math.Clamp(deadeye_timer + deadeye_timer_fraction * RealFrameTime() / 5, 0, max_deadeye_timer:GetFloat()) end
		else
			deadeye_timer = math.Clamp(deadeye_timer + deadeye_timer_fraction * RealFrameTime() / 2, 0, math.Clamp(max_deadeye_timer:GetFloat(), 0, 10))
		end
		return 
	end

	total_mark_count = 0
	for _, tbl in pairs(deadeye_marks) do
		total_mark_count = total_mark_count + table.Count(tbl)
	end

	if SetViewPunchAngles then
		SetViewPunchAngles(Angle(0,0,0))
	end

	if game.SinglePlayer() then 
		if not deadeye_infinite:GetBool() then deadeye_timer = math.Clamp(deadeye_timer - deadeye_timer_fraction * RealFrameTime() / 2, 0, max_deadeye_timer:GetFloat()) end
	else
		deadeye_timer = math.Clamp(deadeye_timer - deadeye_timer_fraction * RealFrameTime() / 2, 0, math.Clamp(max_deadeye_timer:GetFloat(), 0, 10))
	end

	if max_deadeye_timer:GetFloat() - deadeye_timer > max_deadeye_timer:GetFloat() * 0.8 and not pitch_changing then
		background_sfx:ChangePitch(255, deadeye_timer)
		pitch_changing = true
	end

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

	if current_target.data then
		last_target_index = current_target.data.order
	end
	current_target = get_first_mark()

	if (last_target and current_target and current_target.data) and last_target_index != current_target.data.order then
		start_angle = LocalPlayer():EyeAngles()
		aim_lerp_ratio = 0
	end

	// no more marks, reset the quota and turn off deadeye after we're done shooting
	if total_mark_count <= 0 then
		shooting_quota = 0
		if added_a_mark or deadeye_timer <= 0 then
			toggle_deadeye()
		end
	end

	//if cmd:KeyDown(IN_ATTACK) and not added_a_mark then
	//	toggle_deadeye()
	//end

	if not LocalPlayer():GetActiveWeapon().Clip1 or LocalPlayer():GetActiveWeapon():Clip1() == 0 then
		toggle_deadeye()
	    return
	end

	// check if there are more marks than bullets and fill the quota if that's the case... or if we're attacking
	if total_mark_count >= LocalPlayer():GetActiveWeapon():Clip1() or cmd:KeyDown(IN_ATTACK) then
		shooting_quota = total_mark_count
	end

	// we have a quota to work for and we have available marks, shoot!!!
	if shooting_quota > 0 and total_mark_count > 0 then
		cmd:AddKey(IN_ATTACK)
	end
	//print(total_mark_count, shooting_quota)

	// do the silent aimbot shit
	if not deadeye_smooth_aimbot:GetBool() then
		if cmd:CommandNumber() == 0 then
			cmd:SetViewAngles(ang)
			return
		end
	end

	//print(LocalPlayer():GetActiveWeapon():GetTriggerDelta())
	local currently_waiting = false
	// this weird no ammo spent timer thing is to ensure we shoot at all, cuz some weapons just dont give us the proper delay
	if current_target.entindex and (release_attack or (no_ammo_spent_timer >= 1 and shooting_quota > 0 and total_mark_count > 0)) then
		if cmd:KeyDown(IN_ATTACK) then cmd:RemoveKey(IN_ATTACK) end
		timer.Simple(engine.TickInterval()*2, function() no_ammo_spent_timer = 0 end)
		currently_waiting = true
	elseif shooting_quota > 0 and total_mark_count > 0 then
		no_ammo_spent_timer = math.Clamp(no_ammo_spent_timer + RealFrameTime() * 10, 0, 1)
		currently_waiting = false
	end
	
	if wait_for_target_switch then cmd:RemoveKey(IN_ATTACK) return end

	// deadeye aka aimbot
	if current_target.entindex and (cmd:KeyDown(IN_ATTACK) or already_aiming) then

		local actual_shoot_position = LocalPlayer():GetShootPos() + LocalPlayer():GetVelocity() * engine.TickInterval() - Entity(current_target.entindex):GetVelocity() * engine.TickInterval()

		local tr = util.TraceLine({
			start = LocalPlayer():GetShootPos(),
			endpos = current_target.pos,
			filter = LocalPlayer(),
			mask = MASK_SHOT_PORTAL
		})

		if deadeye_vischeck:GetBool() and Entity(current_target.entindex):GetClass() != "prop_ragdoll" and not tr.HitPos:IsEqualTol(current_target.pos, 10) and tr.Entity:EntIndex() != current_target.entindex then
			cmd:RemoveKey(IN_ATTACK)
		end

		if not deadeye_smooth_aimbot:GetBool() then
			local aimangles = (current_target.pos - actual_shoot_position):Angle()
			cmd:SetViewAngles(aimangles)
			fix_movement(cmd, ang)
			already_aiming = true
		else
			local aimangles = (current_target.pos - actual_shoot_position):Angle()

			if current_attack_delay == 0 then
				aim_lerp_ratio = math.Clamp(aim_lerp_ratio + RealFrameTime() * 3 + 0.01, 0, 1)
			else
				aim_lerp_ratio = math.Clamp(aim_lerp_ratio + RealFrameTime() * (3 + current_attack_delay*10) + 0.01, 0, 1)
			end

			local lerped_angles = LerpAngle(math.ease.InOutCubic(aim_lerp_ratio), start_angle, aimangles)
			cmd:SetViewAngles(lerped_angles)
			gAimangles = lerped_angles

			if aim_lerp_ratio < 1 then
				cmd:RemoveKey(IN_ATTACK)
			elseif not currently_waiting then
				cmd:AddKey(IN_ATTACK)
			end

			already_aiming = true
		end
	else
		start_angle = LocalPlayer():EyeAngles()
		aim_lerp_ratio = 0
		already_aiming = false
	end
end)

hook.Add("InputMouseApply", "deadeye_freeze_mouse", function(cmd)
	if in_deadeye and current_target.entindex and (cmd:KeyDown(IN_ATTACK) or already_aiming) and deadeye_smooth_aimbot:GetBool() then
		cmd:SetMouseX(0)
		cmd:SetMouseY(0)

		if not gAimangles:IsZero() then cmd:SetViewAngles(gAimangles) end

		return true
	end
end)

local on_removal = {}

net.Receive("deadeye_ragdoll_created", function()
	if not deadeye_transfer_to_ragdolls:GetBool() then return end
	local owner = net.ReadEntity()
	local ragdoll = net.ReadEntity()
	if not is_usable_for_deadeye(owner) then return end
	owner.deadeye_on_removal = true
	
	timer.Simple(0, function()
		owner.deadeye_is_dead = true
		if IsValid(ragdoll) then
			deadeye_marks[ragdoll:EntIndex()] = deadeye_marks[owner:EntIndex()]
			deadeye_cached_positions[ragdoll:EntIndex()] = deadeye_cached_positions[owner:EntIndex()]
			if deadeye_cached_positions[ragdoll:EntIndex()] then deadeye_cached_positions[ragdoll:EntIndex()].entidx = ragdoll:EntIndex() end
			transferred_ragdolls[ragdoll:EntIndex()] = true
		end
		deadeye_marks[owner:EntIndex()] = nil
		deadeye_cached_positions[owner:EntIndex()] = nil
	end)
end)

hook.Add("EntityRemoved", "deadeye_cleanup_transfer", function(ent)
	if not is_usable_for_deadeye(ent) then return end
	if ent.deadeye_on_removal then return end // we already dealt with it
	if not deadeye_marks[ent:EntIndex()] then return end

	ent.deadeye_is_dead = true

	deadeye_marks[ent:EntIndex()] = nil
	deadeye_cached_positions[ent:EntIndex()] = nil
end)

hook.Add("ChatText", "deadeye_hide_cvar_changes", function(index, name, text, type)
	if type != "servermsg" then return end
	if string.find(text, "sv_tfa_spread_multiplier") then return true end
	if string.find(text, "sv_tfa_soundscale") then return true end
end)

local pp_in_deadeye = {
	["$pp_colour_addr"] = 0.8,
	["$pp_colour_addg"] = 0.4,
	["$pp_colour_addb"] = 0.0,
	["$pp_colour_brightness"] = -0.45,
	["$pp_colour_contrast"] = 0.6,
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

local vignettemat = Material("deadeye/vignette01")
local distortmat = Material("deadeye/distort")
local ca_r = Material("deadeye/ca_r")
local ca_g = Material("deadeye/ca_g")
local ca_b = Material("deadeye/ca_b")
local black = Material("vgui/black")
local highlight = Material("deadeye/highlight")

hook.Add("RenderScreenspaceEffects", "zzzxczxc_deadeye_overlay", function()
	render.UpdateScreenEffectTexture()

	if pp_lerp > 0 then
		highlight:SetVector("$selfillumtint", Vector(pp_lerp/50, pp_lerp/50, pp_lerp/50))
		highlight:SetVector("$envmaptint", Vector(pp_lerp, pp_lerp, pp_lerp))
		
		cam.Start3D()
			for _, ent in ipairs(ents.GetAll()) do
				if ent.deadeye_is_dead then continue end
				if not ent:GetModel() then continue end
				//local is_explosive = string.find(ent:GetModel(), "explosive") or string.find(ent:GetModel(), "gascan") or string.find(ent:GetModel(), "propane_tank") or string.find(ent:GetModel(), "npc_grenade_frag")
				//if not transferred_ragdolls[ent:EntIndex()] and (not IsValid(ent) or (not ent:IsNPC() and not is_explosive and not (ent:IsPlayer() and ent != LocalPlayer()))) then continue end
				if not transferred_ragdolls[ent:EntIndex()] and not is_usable_for_deadeye(ent) then continue end
				if ent == LocalPlayer() or ent == LocalPlayer():GetActiveWeapon() then continue end
				render.MaterialOverride(highlight)
				render.SuppressEngineLighting(true)
				ent:DrawModel()
				render.SuppressEngineLighting(false)
				render.MaterialOverride(nil)
			end
		cam.End3D()
	end

	local tab = {
		["$pp_colour_addr"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addr"], pp_in_deadeye["$pp_colour_addr"]),
		["$pp_colour_addg"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addg"], pp_in_deadeye["$pp_colour_addg"]),
		["$pp_colour_addb"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_addb"], pp_in_deadeye["$pp_colour_addb"]),
		["$pp_colour_brightness"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_brightness"], pp_in_deadeye["$pp_colour_brightness"]),
		["$pp_colour_contrast"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_contrast"], pp_in_deadeye["$pp_colour_contrast"]),
		["$pp_colour_colour"] = Lerp(pp_lerp, pp_out_deadeye["$pp_colour_colour"], pp_in_deadeye["$pp_colour_colour"]),
	}

	if in_deadeye then
		pp_lerp = math.Clamp(pp_lerp + pp_fraction * RealFrameTime() * 7, 0, 1)
		tab["$pp_colour_brightness"] = Lerp(pp_lerp, 0.8, pp_in_deadeye["$pp_colour_brightness"])
		distort_lerp = math.Remap(deadeye_timer, 0, max_deadeye_timer:GetFloat(), 1, 0)
	else
		pp_lerp = math.Clamp(pp_lerp - pp_fraction * RealFrameTime() * 7, 0, 1)
		distort_lerp = math.Clamp(distort_lerp - RealFrameTime() * 2, 0, 1)
	end

	if pp_lerp > 0 then
		DrawColorModify(tab)
		render.UpdateScreenEffectTexture()
		vignettemat:SetFloat("$alpha", pp_lerp)
		render.SetMaterial(vignettemat)
		render.DrawScreenQuad()
	elseif not table.Empty(transferred_ragdolls) then
		transferred_ragdolls = {}
	end

	if distort_lerp > 0 and not deadeye_infinite:GetBool() then
		distortmat:SetFloat("$refractamount", math.Remap(math.ease.InQuart(distort_lerp), 0, 1, 0, 0.15))
		render.UpdateScreenEffectTexture()
		render.SetMaterial(distortmat)
		render.DrawScreenQuad()
		render.UpdateScreenEffectTexture()
		local mult = math.ease.InQuart(distort_lerp) * 2
		render.UpdateScreenEffectTexture()
		render.SetMaterial(black)
		render.DrawScreenQuad()
		render.SetMaterial(ca_r)
		render.DrawScreenQuadEx(-8 * mult, -4 * mult, ScrW() + 16 * mult, ScrH() + 8 * mult)
		render.SetMaterial(ca_g)
		render.DrawScreenQuadEx(-4 * mult, -2 * mult, ScrW() + 8 * mult, ScrH() + 4 * mult)
		render.SetMaterial(ca_b)
		render.DrawScreenQuad()
	end
end)

local pp_no_deadeye_lerp_second = 0
hook.Add("RenderScreenspaceEffects", "deadeye_no_time_overlay", function() 
	local tab = {
		["$pp_colour_addr"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_addr"], pp_in_deadeye["$pp_colour_addr"] * 0.5),
		["$pp_colour_addg"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_addg"], pp_in_deadeye["$pp_colour_addg"] * 0.5),
		["$pp_colour_addb"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_addb"], pp_in_deadeye["$pp_colour_addb"] * 0.5),
		["$pp_colour_brightness"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_brightness"], pp_in_deadeye["$pp_colour_brightness"] * 0.5),
		["$pp_colour_contrast"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_contrast"], pp_in_deadeye["$pp_colour_contrast"] * 1),
		["$pp_colour_colour"] = Lerp(pp_no_deadeye_lerp_second, pp_out_deadeye["$pp_colour_colour"], pp_in_deadeye["$pp_colour_colour"]),
	}

	pp_no_deadeye_lerp = math.Clamp(pp_no_deadeye_lerp - pp_fraction * RealFrameTime() * 15, 0, 1)

	if pp_no_deadeye_lerp < 0.3 then
		pp_no_deadeye_lerp_second = math.Clamp(pp_no_deadeye_lerp_second - pp_fraction * RealFrameTime() * 15, 0, 1)
	else
		pp_no_deadeye_lerp_second = math.Clamp(pp_no_deadeye_lerp_second + pp_fraction * RealFrameTime() * 25, 0, 1)
	end	

	if pp_no_deadeye_lerp > 0 then
		distort_lerp = pp_no_deadeye_lerp_second * 0.8
		DrawColorModify(tab)
		render.UpdateScreenEffectTexture()
	end
end)

local deadeye_cross = Material("deadeye/deadeye_cross")
local deadeye_core = Material("deadeye/deadeye_core")
local blank_material = Material("color")
local deadeye_core_circle = Material("deadeye/rpg_meter_track_9")

local function draw_circ_bar(x, y, w, h, progress, color)
	// https://gist.github.com/Joseph10112/6e6e896b5feee50f7aa2145aabaf6e8c
	// i love pasting xD

	if game.SinglePlayer() and deadeye_infinite:GetBool() then
		surface.SetDrawColor(color)
		surface.SetMaterial(deadeye_core_circle)
		surface.DrawTexturedRect(x, y, w, h)
		return	
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
					mark_brightness[entindex][mark.index] = math.Clamp(mark_brightness[entindex][mark.index] - 4*RealFrameTime(), 0, 1)
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

			if game.SinglePlayer() and deadeye_infinite:GetBool() then 
				surface.SetDrawColor(255, 190, 48, 128)
			else
				surface.SetDrawColor(255, 255, 255, 128)
			end

			surface.DrawRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), math.Remap(deadeye_timer, 0, max_deadeye_timer:GetFloat(), 0, 150)*deadeye_bar_size:GetFloat(), 12*deadeye_bar_size:GetFloat())
		else
			surface.SetMaterial(deadeye_core)
			if game.SinglePlayer() and deadeye_infinite:GetBool() then 
				surface.SetDrawColor(255, 190, 48, 255)
			else
				surface.SetDrawColor(255, 255, 255, 255)
			end
			surface.DrawTexturedRect(34+deadeye_bar_offset_x:GetFloat(), ScrH()-250-deadeye_bar_offset_y:GetFloat(), 42*deadeye_bar_size:GetFloat(), 42*deadeye_bar_size:GetFloat())
			
			local progress = math.Remap(deadeye_timer, 0, max_deadeye_timer:GetFloat(), 1, 0)

			if progress != 1 then
				local color
				if game.SinglePlayer() and deadeye_infinite:GetBool() then 
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
concommand.Add("cl_deadeye_toggle", toggle_deadeye)