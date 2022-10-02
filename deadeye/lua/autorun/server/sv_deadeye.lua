if not game.SinglePlayer() then 
	return 
end
util.AddNetworkString("deadeye_firebullet")
util.AddNetworkString("in_deadeye")
util.AddNetworkString("deadeye_primaryfire_time")

local in_deadeye = false
local in_deadeye_prev = false

local accuracy_vars = {}
local accuracy_vars_original = {}

local function add_accuracy_var(cvar_string)
	accuracy_vars[cvar_string] = GetConVar(cvar_string)
end

add_accuracy_var("arccw_mult_recoil")
add_accuracy_var("arccw_mult_movedisp")
add_accuracy_var("arccw_mult_hipfire")
add_accuracy_var("mgbase_sv_accuracy")
add_accuracy_var("mgbase_sv_recoil")
add_accuracy_var("sv_tfa_spread_multiplier")
add_accuracy_var("sv_tfa_soundscale") // not actually an accuracy var but i just dont want weird audio shit happening

local function zero_out_vars()
	for key, convar in pairs(accuracy_vars) do
		accuracy_vars_original[key] = convar:GetFloat()
		if key == "mgbase_sv_accuracy" then
			convar:SetFloat(5)
		else
			convar:SetFloat(0)
		end
	end
end

local function restore_vars()
	for key, convar in pairs(accuracy_vars) do
		convar:SetFloat(accuracy_vars_original[key])
	end
end

hook.Add("EntityTakeDamage", "deadeye_randommiss", function(ent, dmg)
	if in_deadeye and ent:IsPlayer() and dmg:GetAttacker():IsNPC() then
		if math.random(0,1) == 1 then return true end
	end
end)

hook.Add("PlayerTick", "deadeye_norecoil", function(ply, cmd)
	if in_deadeye then
		ply:SetViewPunchAngles(Angle(0, 0, 0))
		ply:SetViewPunchVelocity(Angle(0, 0, 0))
	end

	if in_deadeye != in_deadeye_prev and in_deadeye then
		zero_out_vars()
	elseif in_deadeye != in_deadeye_prev and not in_deadeye then
		restore_vars()
	end

	in_deadeye_prev = in_deadeye
end)

hook.Add("EntityFireBullets", "deadeye_spread", function(attacker, data)
	if not in_deadeye then return end

    local entity = NULL
    local weapon = NULL
    local weaponIsWeird = false

    if attacker:IsPlayer() or attacker:IsNPC() then
        entity = attacker
        weapon = entity:GetActiveWeapon()
    else
        weapon = attacker
        entity = weapon:GetOwner()
        if entity == NULL then 
            entity = attacker
            weaponIsWeird = true
        end
    end

    if weaponIsWeird then return end

    if entity:IsPlayer() then
    	data.Spread = Vector(0,0,0)
    	return true
    end
end)

net.Receive("deadeye_primaryfire_time", function(len, ply) 
	local weapon = ply:GetActiveWeapon()
	local nextprimaryfire = weapon:GetNextPrimaryFire()
	local newnextfire = CurTime() + math.abs(nextprimaryfire - CurTime()) * 0.3
	weapon:SetNextPrimaryFire(newnextfire)
end)

net.Receive("in_deadeye", function(len,ply) 
	in_deadeye = net.ReadBool()

	if in_deadeye then
		ply:GetActiveWeapon():SetClip1(ply:GetActiveWeapon():GetMaxClip1())
		game.SetTimeScale(0.2)
	else
		game.SetTimeScale(1)
	end
end)