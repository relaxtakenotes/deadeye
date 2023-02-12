util.AddNetworkString("deadeye_firebullet")
util.AddNetworkString("in_deadeye")
util.AddNetworkString("deadeye_primaryfire_time")
util.AddNetworkString("deadeye_ragdoll_created")
util.AddNetworkString("deadeye_destroy_grenade")
util.AddNetworkString("deadeye_shot")

local in_deadeye = {}
local in_deadeye_prev = {}
local slowdown = false

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

net.Receive("deadeye_destroy_grenade", function() 
	local grenade = net.ReadEntity()
	if grenade:GetClass() != "npc_grenade_frag" then return end
	grenade:SetSaveValue("m_flDetonateTime", 0)
end)

hook.Add("CreateEntityRagdoll", "deadeye_ragdoll_notify", function(owner, entity) 
	net.Start("deadeye_ragdoll_created", true)
	net.WriteEntity(owner)
	net.WriteEntity(entity)
	net.Broadcast()
end)

hook.Add("EntityTakeDamage", "deadeye_randommiss", function(ent, dmg)
	if in_deadeye[ent] and ent:IsPlayer() and dmg:GetAttacker():IsNPC() then
		if math.random(0,1) == 1 then return true end
	end
end)

hook.Add("PlayerTick", "deadeye_norecoil", function(ply, cmd)
	if in_deadeye[ply] then
		local weapon = ply:GetActiveWeapon()
		ply:SetViewPunchAngles(Angle(0, 0, 0))
		ply:SetViewPunchVelocity(Angle(0, 0, 0))

		// mw2019 stuff
		if weapon.Trigger and weapon:GetTriggerDelta() < 1 then
			weapon:SetTriggerDelta(1)
		end

        if string.StartWith(weapon:GetClass() , "arc9_") then
            weapon:SetReady(true)
        end

		//local delay = math.abs((weapon:GetNextPrimaryFire() - CurTime()) * 0.2)
		//weapon:SetNextPrimaryFire(CurTime() + delay)
        //print(delay)

        if slowdown then game.SetTimeScale(0.2) end
	end

    if game.SinglePlayer() then
    	if in_deadeye[ply] != in_deadeye_prev[ply] and in_deadeye[ply] then
            ply:GetActiveWeapon():SetNextPrimaryFire(CurTime())
    		zero_out_vars()
    	elseif in_deadeye[ply] != in_deadeye_prev[ply] and not in_deadeye[ply] then
    		restore_vars()
    	end
    end

	in_deadeye_prev[ply] = in_deadeye[ply]
end)

net.Receive("in_deadeye", function(len,ply) 
	in_deadeye[ply] = net.ReadBool()

    if game.SinglePlayer() then
        slowdown = net.ReadBool()
    else
        slowdown = false
    end

	if in_deadeye[ply] then
		local weapon = ply:GetActiveWeapon()

		pcall(function() 
			local current_amount = weapon:Clip1()
			local max_amount = weapon:GetMaxClip1()
			local total_amount = ply:GetAmmoCount(weapon:GetPrimaryAmmoType())
			local required = max_amount - current_amount

			if required <= total_amount then
				ply:RemoveAmmo(required, weapon:GetPrimaryAmmoType())
				weapon:SetClip1(max_amount)
			end
		end)
		
		if slowdown then game.SetTimeScale(0.2) end
	else
		if slowdown then game.SetTimeScale(1) end
	end
end)

local function networkGunshotEvent(data)
	if not in_deadeye[data.Entity] then return end
    if data.Entity:IsPlayer() then
        local delay = 0
        if slowdown then
    		delay = math.abs((data.Weapon:GetNextPrimaryFire() - CurTime()) * 0.2)
    		data.Weapon:SetNextPrimaryFire(CurTime() + delay)
        else
            delay = data.Weapon:GetNextPrimaryFire() - CurTime()
        end

    	net.Start("deadeye_shot")
    	net.WriteFloat(delay)
    	net.Send(data.Entity)
    end
end

function arc9_deadeye_detour(args)
    local bullet = args[2]
    local attacker = bullet.Attacker

    if attacker.deadeye_shotThisTick == nil then attacker.deadeye_shotThisTick = false end
    if attacker.deadeye_shotThisTick then return end
    if table.Count(bullet.Damaged) != 0 or bullet.deadeye_detected then return end

    local weapon = bullet.Weapon
    local weaponClass = weapon:GetClass()
    local pos = attacker:GetShootPos()
    local ammotype = bullet.Weapon.Primary.Ammo
    local dir = bullet.Vel:Angle():Forward()
    local vel = bullet.Vel

    timer.Simple(0, function()
        local data = {}
        data.Entity = attacker
        data.Weapon = attacker:GetActiveWeapon()
        networkGunshotEvent(data)
    end)
    bullet.deadeye_detected = true
    attacker.deadeye_shotThisTick = true

    timer.Simple(engine.TickInterval()*2, function() attacker.deadeye_shotThisTick = false end)
end

hook.Add("InitPostEntity", "deadeye_create_physbul_hooks", function()
    if ARC9 then
        function deadeye_wrapfunction(a)    -- a = old function
          return function(...)
            local args = { ... }
            arc9_deadeye_detour(args)
            return a(...)
          end
        end
        ARC9.SendBullet = deadeye_wrapfunction(ARC9.SendBullet)
    end

    if TFA then
        hook.Add("Think", "deadeye_detecttfaphys", function()
            local latestPhysBullet = TFA.Ballistics.Bullets["bullet_registry"][table.Count(TFA.Ballistics.Bullets["bullet_registry"])]
            if latestPhysBullet == nil then return end
            if latestPhysBullet["deadeye_detected"] then return end

            local weapon = latestPhysBullet["inflictor"]
            local weaponClass = weapon:GetClass()

            local pos = latestPhysBullet["bul"]["Src"]
            local ammotype = weapon.Primary.Ammo
            local dir = latestPhysBullet["velocity"]:Angle():Forward()
            local vel = latestPhysBullet["velocity"]
            local entity = latestPhysBullet["inflictor"]:GetOwner()

            if entity.deadeye_shotThisTick == nil then entity.deadeye_shotThisTick = false end
            if entity.deadeye_shotThisTick then return end
            entity.deadeye_shotThisTick = true
            timer.Simple(engine.TickInterval()*2, function() entity.deadeye_shotThisTick = false end)

            local data = {}
            data.Entity = latestPhysBullet["inflictor"]:GetOwner()
            data.Weapon = latestPhysBullet["inflictor"]
            networkGunshotEvent(data)

            latestPhysBullet["deadeye_detected"] = true
        end)
    end

    if ArcCW then
        hook.Add("Think", "deadeye_detectarccwphys", function()
            if ArcCW.PhysBullets[table.Count(ArcCW.PhysBullets)] == nil then return end
            local latestPhysBullet = ArcCW.PhysBullets[table.Count(ArcCW.PhysBullets)]
            if latestPhysBullet["deadeye_detected"] then return end
            if latestPhysBullet["Attacker"] == Entity(0) then return end
            local entity = latestPhysBullet["Attacker"]

            if entity.deadeye_shotThisTick == nil then entity.deadeye_shotThisTick = false end
            if entity.deadeye_shotThisTick then return end
            entity.deadeye_shotThisTick = true
            timer.Simple(engine.TickInterval()*2, function() entity.deadeye_shotThisTick = false end)

            local weapon = latestPhysBullet["Weapon"]
            local weaponClass = weapon:GetClass()

            local pos = latestPhysBullet["Pos"]
            local ammotype = weapon.Primary.Ammo
            local dir = latestPhysBullet["Vel"]:Angle():Forward()
            local vel = latestPhysBullet["Vel"]

            local data = {}
            data.Entity = latestPhysBullet["Attacker"]
            data.Weapon = latestPhysBullet["Attacker"]:GetActiveWeapon()
            networkGunshotEvent(data)
            
            latestPhysBullet["deadeye_detected"] = true
        end)
    end

    if MW_ATTS then -- global var from mw2019 sweps
        hook.Add("OnEntityCreated", "deadeye_detectmw2019phys", function(ent)
            if ent:GetClass() != "mg_sniper_bullet" and ent:GetClass() != "mg_slug" then return end
            timer.Simple(0, function()
                local attacker = ent:GetOwner()
                local entity = attacker
                local weapon = attacker:GetActiveWeapon()
                local pos = ent.LastPos
                local dir = (ent:GetPos() - ent.LastPos):GetNormalized()
                local vel = ent:GetAngles():Forward() * ent.Projectile.Speed
                local ammotype = "none"
                if weapon.Primary and weapon.Primary.Ammo then ammotype = weapon.Primary.Ammo end

                if entity.deadeye_shotThisTick == nil then entity.deadeye_shotThisTick = false end
                if entity.deadeye_shotThisTick then return end
                entity.deadeye_shotThisTick = true
                timer.Simple(engine.TickInterval()*2, function() entity.deadeye_shotThisTick = false end)

                local data = {}
                data.Entity = attacker
                data.Weapon = attacker:GetActiveWeapon()

                networkGunshotEvent(data)
            end)
        end)
    end

    hook.Remove("InitPostEntity", "deadeye_create_physbul_hooks")
end)

hook.Add("EntityFireBullets", "deadeye_EntityFireBullets", function(attacker, data)
    if data.Spread.z == 0.125 then return end -- for my blood decal workaround for mw sweps

    local entity = NULL
    local weapon = NULL
    local weaponIsWeird = false
    local isSuppressed = false
    local ammotype = "none"

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

    if not weaponIsWeird and weapon != NULL and entity.GetShootPos != nil then -- should solve all of the issues caused by external bullet sources (such as the turret mod)
        local weaponClass = weapon:GetClass()
        local entityShootPos = entity:GetShootPos()

        if weaponClass == "mg_arrow" then return end -- mw2019 sweps crossbow
        if weaponClass == "mg_sniper_bullet" and data.Spread == Vector(0,0,0) then return end -- physical bullets in mw2019
        if weaponClass == "mg_slug" and data.Spread == Vector(0,0,0) then return end -- physical bullets in mw2019

        if data.Distance < 200 then return end -- melee

        if string.StartWith(weaponClass, "arccw_") then
            if data.Distance == 20000 then -- grenade launchers in arccw
                return
            end
            if GetConVar("arccw_bullet_enable"):GetInt() == 1 and data.Spread == Vector(0, 0, 0) then -- bullet physics in arcw
                return
            end
        end

        if string.StartWith(weaponClass, "arc9_") then
            if GetConVar("arc9_bullet_physics"):GetInt() == 1 and data.Spread == Vector(0, 0, 0) then -- bullet physics in arc9
                return
            end
        end

        if entity.deadeye_shotThisTick == nil then entity.deadeye_shotThisTick = false end
        if entity.deadeye_shotThisTick then return end
        entity.deadeye_shotThisTick = true
        timer.Simple(engine.TickInterval()*2, function() entity.deadeye_shotThisTick = false end)
                                                                                             
        if #data.AmmoType > 2 then ammotype = data.AmmoType elseif weapon.Primary then ammotype = weapon.Primary.Ammo end
    end

    local deadeye_data = {}
    deadeye_data.Entity = entity
    deadeye_data.Weapon = weapon
    networkGunshotEvent(deadeye_data)

    data.Spread = Vector(0,0,0)

    return true
end)