-- Tungsten Rain: runtime logic
-- The storage ring: rods are not accelerated by the shot — they live accelerated.
-- A per-planet, per-force ring pulls rods from orbiting platform hubs and spins them
-- up to 0.01c in the background. Firing only releases an already-charged rod.
-- Click with the targeter -> spend one charged rod from the ring -> short delay
-- (the rod has to come around to the extraction window) -> kinetic impact.
-- Damage type: explosion by default (a kinetic impact IS a blast wave; vanilla nukes
-- agree). Rampant "fixed" nests resist physical/fire at 99.99% but leak 8% explosion.

local EXPLOSION_CANDIDATES = { "nuke-explosion", "massive-explosion", "big-artillery-explosion", "big-explosion" }
local SCORCH_CANDIDATES = { "nuclear-huge-scorchmark", "huge-scorchmark", "medium-scorchmark" }
local WAVE_CANDIDATES = { "big-artillery-explosion", "big-explosion", "explosion" }
local SMALL_SCORCH_CANDIDATES = { "medium-scorchmark", "small-scorchmark" }
local SMOKE_CANDIDATES = { "nuclear-smouldering-smoke-source" }

-- The strike always deals relativistic damage (subtracted straight from health,
-- so no resistance, per-hit cap or overkill-protection applies). On targets it
-- does not kill outright it also lands these conventional types through the normal
-- damage system, so the impact reads as a kinetic blast to armour logic and other
-- mods' on-damage hooks. The relativistic chunk is what guarantees the kill.
local LOGICAL_DAMAGE_TYPES = { "impact", "physical", "explosion" }

-- Kill `e` outright, and with it the whole stack it may stand for. Squad
-- compression (Rampant) shows a squad as one biter and, when that one dies,
-- pops the next out on the same spot; so keep killing there until the stack
-- is spent. Plain entities cost one extra half-tile search. `on_next` (optional)
-- is called with each further biter of the stack just before it dies.
local STACK_LIMIT = 500

-- Hostile combat robots are Rampant's drones — and its eggs, which hatch
-- biters when they die. A kinetic hit vaporizes them instead: destroy() raises
-- no death, so there is nothing left to hatch.
local function vaporize(e)
  pcall(function() e.destroy() end)
end

local function kill_stack(surface, e, force, on_next)
  local name, pos, owner = e.name, e.position, e.force
  pcall(function() e.die(force) end)
  for _ = 1, STACK_LIMIT do
    local ok, found = pcall(function()
      return surface.find_entities_filtered{ position = pos, radius = 0.5, name = name,
                                             force = owner, limit = 1 }
    end)
    local nxt = ok and found and found[1]
    if not (nxt and nxt.valid) then break end
    if on_next then pcall(on_next, nxt) end
    pcall(function() nxt.die(force) end)
    if nxt.valid then break end -- could not be killed (immune): leave it
  end
end

local function cfg()
  local s = settings.global
  return {
    damage        = s["tungsten-rain-damage"].value,
    fire_damage   = s["tungsten-rain-fire-damage"].value,
    start_fires   = s["tungsten-rain-start-fires"].value,
    dmg_pulses    = s["tungsten-rain-damage-pulses"].value,
    dmg_interval  = math.max(1, math.floor(s["tungsten-rain-damage-interval"].value * 60)), -- s -> ticks

    radius        = s["tungsten-rain-radius"].value,
    cooldown      = s["tungsten-rain-cooldown"].value * 60, -- seconds -> ticks
    spinup        = s["tungsten-rain-spinup"].value * 60,   -- seconds -> ticks
    capacity      = s["tungsten-rain-ring-capacity"].value,
    stations_full = s["tungsten-rain-ring-stations"].value,
    delay         = s["tungsten-rain-delay"].value,         -- ticks
    fx            = s["tungsten-rain-fx"].value,
    require_rods  = s["tungsten-rain-require-rods"].value,
    friendly_fire = s["tungsten-rain-friendly-fire"].value,
    spare_trees   = not s["tungsten-rain-destroy-trees"].value,
    auto_fire     = s["tungsten-rain-auto-fire"].value,
    auto_interval = math.max(600, math.floor(s["tungsten-rain-auto-interval"].value * 60)), -- s -> ticks, min 10 s
    auto_range    = s["tungsten-rain-auto-range"].value,
    auto_worms    = s["tungsten-rain-auto-worms"].value,
    needle_capacity = s["tungsten-rain-needle-capacity"].value,
    needle_rate     = s["tungsten-rain-needle-rate"].value,      -- per station per second
    needle_radius   = s["tungsten-rain-needle-radius"].value,
    needle_targets  = s["tungsten-rain-needle-targets"].value     -- targets per cartridge
  }
end

local function init_storage()
  storage.strikes = storage.strikes or {}
  storage.fx = storage.fx or {}     -- scheduled secondary detonations
  storage.dmg = storage.dmg or {}   -- scheduled damage pulses (spread over time)
  storage.waves = storage.waves or {} -- live continuous blast waves (render objects)
  storage.trails = storage.trails or {} -- fading tracer afterglows post-impact
  storage.next_shot = storage.next_shot or {}
  storage.next_auto = storage.next_auto or 0 -- next tick the auto-fire sweep may run
  -- auto_sweep: the auto-fire pass in progress, worked off a little every tick
  -- (see auto_fire_step); nil when idle
  -- radars[surface_index][unit_number] = radar entity. Kept up to date from build
  -- events so auto-fire never has to search a whole planet for them; dead ones
  -- are pruned lazily. Filled once by a full scan when the registry is new.
  if not storage.radars then
    storage.radars = {}
    for _, surface in pairs(game.surfaces) do
      local ok, found = pcall(function() return surface.find_entities_filtered{ type = "radar" } end)
      if ok and found then
        local by_id = {}
        for _, r in pairs(found) do
          if r.valid and r.unit_number then by_id[r.unit_number] = r end
        end
        storage.radars[surface.index] = by_id
      end
    end
  end
  -- rings[force_name][planet_name] =
  --   { charged = N, loaded = N, charging_done = tick or nil, stations = N, enabled = bool }
  --   loaded   = rods pulled from the hub, buffered, waiting their turn to spin up
  --   charging_done = tick the one rod currently spinning up will be ready
  --   charged  = rods fully spun up and fireable
  --   needles  = needle cartridges ready to fire (forged by the stations
  --              themselves out of asteroid dust; see "Needle cartridges" below)
  --   needle_frac = fractional cartridge carried between seconds
  storage.rings = storage.rings or {}
  -- zones[force_name][surface_index] = { [id] = { id, area, render } }: the ground
  -- the ring guards with needle cartridges — at most one zone per planet, a new
  -- one replaces the old. zone_pieces is the flat scan list built from it,
  -- zone_cursor the round-robin position in that list
  storage.zones = storage.zones or {}
  storage.zone_next_id = storage.zone_next_id or 1
  storage.zone_cursor = storage.zone_cursor or 1
  -- needle_volleys: cartridges in flight; needle_claims[unit_number] = tick until
  -- which that enemy already has a needle coming and is not targeted again
  storage.needle_volleys = storage.needle_volleys or {}
  storage.needle_claims = storage.needle_claims or {}
  for _, by_planet in pairs(storage.rings) do
    for _, ring in pairs(by_planet) do
      ring.needles = ring.needles or 0
      ring.needle_frac = ring.needle_frac or 0
      ring.stations = ring.stations or 0
      -- migration: rings that were already being built stay active
      if ring.enabled == nil then ring.enabled = ring.stations > 0 end
    end
  end
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

-- ---------------------------------------------------------------------------
-- The storage ring: per-force, per-planet necklace of deflector stations plus
-- a magazine of pre-accelerated rods. Each station can only bend the rod's path
-- by a fixed angle, and a closed loop needs 360 degrees total — so the ring's
-- top speed grows linearly with station count: v = 0.01c * (stations / full).
-- Energy (damage) scales as v^2, blast radius as energy^(1/3), and spin-up time
-- as energy too: a half-built ring hits at 25% but charges 4x faster.
-- Stations and slugs are both delivered to orbiting platform hubs; the ring
-- assembles and charges itself. Holding charged rods costs nothing (magnetic
-- force is perpendicular to velocity — bending does no work), so the ring
-- keeps its charge even if the delivery platform leaves orbit.
-- ---------------------------------------------------------------------------
local function get_ring(force_name, planet_name)
  local by_force = storage.rings[force_name]
  if not by_force then
    by_force = {}
    storage.rings[force_name] = by_force
  end
  local ring = by_force[planet_name]
  if not ring then
    -- enabled = false: rings never pull from hubs until explicitly activated
    -- (alt-select with the targeter), so loading a freighter platform at one
    -- planet does not feed that planet's ring by accident.
    ring = { charged = 0, loaded = 0, stations = 0, enabled = false }
    by_force[planet_name] = ring
  end
  return ring
end

-- The ring does NOT accelerate the rod: the rod fires its own engine while
-- circulating inside the ring, and the deflector stations only HOLD it on a stable
-- orbit (containment) during and after the burn. The speed a ring can keep is
-- capped by how many deflectors it has, so the held speed fraction = stations/full.
local function ring_speed(ring, c)
  local n = math.min(ring.stations or 0, c.stations_full)
  if n <= 0 then return 0 end
  return n / c.stations_full
end

-- Energy fraction of a full-power shot: (v/v_max)^2 = (stations/full)^2. A ring
-- with too few deflectors can't contain a full-speed rod; it bleeds off the excess
-- and settles the rod at the fastest orbit it can hold, hence less energy on impact.
local function ring_power(ring, c)
  local f = ring_speed(ring, c)
  return f * f
end

-- "Spin-up" is the rod accelerating itself, inside the ring, up to the speed the
-- ring can hold, then stabilizing on orbit. F = ma with a fixed little engine makes
-- the burn time linear in the final speed: a full ring takes the whole configured
-- time to reach 0.01c, a half-built ring needs only 50% speed so it burns half as
-- long. Floored at 60 ticks so even a near-empty ring takes a beat to settle.
local function spinup_ticks(ring, c)
  return math.max(60, math.floor(c.spinup * ring_speed(ring, c)))
end

-- Take one item out of the hub of any of this force's platforms parked at the planet.
local function try_consume_from_hub(force, planet_name, item_name)
  local ok_pl, platforms = pcall(function() return force.platforms end)
  if not (ok_pl and platforms) then return false end
  for _, platform in pairs(platforms) do
    local ok_loc, loc = pcall(function() return platform.space_location end)
    if ok_loc and loc and loc.name == planet_name then
      local ok_hub, hub = pcall(function() return platform.hub end)
      if ok_hub and hub and hub.valid then
        local ok_inv, inv = pcall(function()
          return hub.get_inventory(defines.inventory.hub_main)
        end)
        if ok_inv and inv and inv.get_item_count(item_name) > 0 then
          inv.remove({ name = item_name, count = 1 })
          return true
        end
      end
    end
  end
  return false
end

-- Rods the ring is holding: waiting in the buffer (loaded), being spun up
-- right now (charging), and already charged and fireable. Capacity caps the sum.
local function ring_total(ring)
  return (ring.loaded or 0) + (ring.charged or 0) + (ring.charging_done and 1 or 0)
end

local function finish_charging(ring, tick)
  if ring.charging_done and tick >= ring.charging_done then
    ring.charged = ring.charged + 1
    ring.charging_done = nil
  end
end

local GUI_FRAME = "tungsten-rain-status"
local rebuild_status -- defined in the GUI section below
local auto_fire      -- defined after the targeting helpers

-- Background assembly and spin-up, runs once a second.
script.on_nth_tick(60, function(event)
  local c = cfg()

  -- 1) finish any spin-ups that are due (even if the platform has since left)
  for _, by_planet in pairs(storage.rings) do
    for _, ring in pairs(by_planet) do
      finish_charging(ring, event.tick)
    end
  end

  -- 2) install stations and start new spin-ups where a platform is parked
  for _, force in pairs(game.forces) do
    local ok_pl, platforms = pcall(function() return force.platforms end)
    if ok_pl and platforms then
      local parked_at = {}
      for _, platform in pairs(platforms) do
        local ok_loc, loc = pcall(function() return platform.space_location end)
        if ok_loc and loc then parked_at[loc.name] = true end
      end
      for planet_name in pairs(parked_at) do
        local ring = get_ring(force.name, planet_name)

        -- a paused/unactivated ring never pulls anything from hubs:
        -- freighters can load up at this planet without feeding its ring
        if ring.enabled then
          -- ring assembly: one deflector station deployed per second
          if ring.stations < c.stations_full
              and try_consume_from_hub(force, planet_name, "ring-deflector-station") then
            ring.stations = ring.stations + 1
            local key = ring.stations >= c.stations_full
              and "tungsten-rain.ring-complete" or "tungsten-rain.ring-station-installed"
            pcall(function()
              force.print({ key, ring.stations, c.stations_full, planet_name })
            end)
          end

          if ring.stations > 0 then
            -- rod intake: empty the hub straight into the ring buffer, up to
            -- capacity, in one pass. A freighter can drop its whole load and
            -- leave; the rods then spin up one at a time without it being parked.
            while ring_total(ring) < c.capacity
                and try_consume_from_hub(force, planet_name, "tungsten-rod") do
              ring.loaded = (ring.loaded or 0) + 1
            end
          end
        end
      end
    end
  end

  -- 3) spin up the next buffered rod in EVERY ring, one at a time — independent of
  --    any platform being parked. Once rods are pulled into the buffer the freighter
  --    can leave; the ring keeps charging them on its own (a weaker ring charges
  --    faster). Runs after intake so a rod pulled this tick starts spinning at once.
  for _, by_planet in pairs(storage.rings) do
    for _, ring in pairs(by_planet) do
      if (ring.stations or 0) > 0 and not ring.charging_done and (ring.loaded or 0) > 0 then
        ring.loaded = ring.loaded - 1
        ring.charging_done = event.tick + spinup_ticks(ring, c)
      end
      -- needle cartridges: every active station forges needle_rate per second
      -- from the asteroid dust the ring sweeps up; no hub, no platform needed
      if ring.enabled and (ring.stations or 0) > 0 then
        local room = c.needle_capacity - (ring.needles or 0)
        if room > 0 then
          local made = ring.stations * c.needle_rate + (ring.needle_frac or 0)
          local whole = math.floor(made)
          ring.needle_frac = made - whole
          ring.needles = (ring.needles or 0) + math.min(whole, room)
        else
          ring.needle_frac = 0
        end
      end
    end
  end

  -- 4) automatic bombardment of enemy nests/worms within radar range
  if c.auto_fire and auto_fire then
    storage.next_auto = storage.next_auto or 0
    if event.tick >= storage.next_auto and not storage.auto_sweep then
      pcall(function() auto_fire(c, event.tick) end)
      storage.next_auto = event.tick + c.auto_interval
    end
  end

  -- refresh open status windows
  if rebuild_status then
    pcall(function()
      for _, player in pairs(game.connected_players) do
        if player.gui.screen[GUI_FRAME] then rebuild_status(player) end
      end
    end)
  end
end)

-- ---------------------------------------------------------------------------
-- Status window: per-planet ring overview with pause/resume buttons.
-- Toggled by the second shortcut-bar button; refreshes once a second while open.
-- ---------------------------------------------------------------------------
function rebuild_status(player)
  local frame = player.gui.screen[GUI_FRAME]
  if not frame then return end
  local old = frame["tungsten-rain-content"]
  if old then old.destroy() end
  local content = frame.add{ type = "flow", name = "tungsten-rain-content", direction = "vertical" }

  local c = cfg()
  local force = player.force

  -- planets worth showing: existing rings + wherever a platform is parked
  local planets = {}
  local by_force = storage.rings[force.name]
  if by_force then
    for name in pairs(by_force) do planets[name] = true end
  end
  local ok_pl, platforms = pcall(function() return force.platforms end)
  if ok_pl and platforms then
    for _, platform in pairs(platforms) do
      local ok_loc, loc = pcall(function() return platform.space_location end)
      if ok_loc and loc then planets[loc.name] = true end
    end
  end
  local names = {}
  for n in pairs(planets) do names[#names + 1] = n end
  table.sort(names)

  if #names == 0 then
    content.add{ type = "label", caption = { "tungsten-rain.gui-no-rings" } }
    return
  end

  local tbl = content.add{ type = "table", column_count = 7 }
  for _, key in ipairs({ "gui-col-planet", "gui-col-stations", "gui-col-power",
                         "gui-col-rods", "gui-col-spinup", "gui-col-needles" }) do
    local l = tbl.add{ type = "label", caption = { "tungsten-rain." .. key } }
    l.style.font = "default-bold"
  end
  tbl.add{ type = "empty-widget" }

  for _, name in ipairs(names) do
    local ring = get_ring(force.name, name)
    finish_charging(ring, game.tick)
    tbl.add{ type = "label",
      caption = { "?", { "space-location-name." .. name }, { "planet-name." .. name }, name } }
    tbl.add{ type = "label", caption = ring.stations .. "/" .. c.stations_full }
    tbl.add{ type = "label", caption = math.floor(ring_power(ring, c) * 100 + 0.5) .. "%" }
    local queued = (ring.loaded or 0) + (ring.charging_done and 1 or 0)
    local rods = ring.charged .. "/" .. c.capacity
    if queued > 0 then rods = rods .. " (+" .. queued .. ")" end
    tbl.add{ type = "label", caption = rods }
    local spin = "—"
    if ring.charging_done then
      spin = { "tungsten-rain.gui-spinup-remaining",
               math.max(0, math.ceil((ring.charging_done - game.tick) / 60)) }
    end
    tbl.add{ type = "label", caption = spin }
    tbl.add{ type = "label", caption = (ring.needles or 0) .. "/" .. c.needle_capacity }
    tbl.add{ type = "button", name = "tungsten-rain-toggle/" .. name,
      caption = ring.enabled and { "tungsten-rain.gui-btn-pause" }
                             or { "tungsten-rain.gui-btn-resume" } }
  end
end

local function toggle_status(player)
  local existing = player.gui.screen[GUI_FRAME]
  if existing then
    existing.destroy()
    return
  end
  local frame = player.gui.screen.add{ type = "frame", name = GUI_FRAME, direction = "vertical" }
  local bar = frame.add{ type = "flow", direction = "horizontal" }
  local title = bar.add{ type = "label", caption = { "tungsten-rain.gui-title" }, style = "frame_title" }
  title.drag_target = frame
  local spacer = bar.add{ type = "empty-widget", style = "draggable_space_header" }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  spacer.drag_target = frame
  bar.add{ type = "sprite-button", name = "tungsten-rain-close",
    sprite = "utility/close", style = "frame_action_button" }
  frame.auto_center = true
  rebuild_status(player)
end

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "tungsten-rain-status" then return end
  local player = game.get_player(event.player_index)
  if player then toggle_status(player) end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end

  if element.name == "tungsten-rain-close" then
    local frame = player.gui.screen[GUI_FRAME]
    if frame then frame.destroy() end
    return
  end

  local planet_name = element.name:match("^tungsten%-rain%-toggle/(.+)$")
  if planet_name then
    local ring = get_ring(player.force.name, planet_name)
    ring.enabled = not ring.enabled
    rebuild_status(player)
  end
end)

-- ---------------------------------------------------------------------------
-- The impact itself
-- ---------------------------------------------------------------------------
local function spawn_first_valid(surface, names, position)
  for _, name in ipairs(names) do
    local ok = pcall(surface.create_entity, { name = name, position = position })
    if ok then return true end
  end
  return false
end

-- One ring of the expanding shockwave: explosions spread evenly around a circle.
local function do_fx(f)
  local surface = f.surface
  if not (surface and surface.valid) then return end
  local a0 = math.random() * 2 * math.pi
  local step = 2 * math.pi / f.count
  for j = 1, f.count do
    local a = a0 + j * step
    spawn_first_valid(surface, f.names, {
      x = f.pos.x + math.cos(a) * f.r,
      y = f.pos.y + math.sin(a) * f.r
    })
  end
end

-- Incoming tracer: a white-hot streak diving into the target point during the
-- last ~0.17 s before impact — a blink, as orbital velocity deserves.
-- Entry comes from the top of the screen at a random per-strike angle.
local TRACER_TICKS = 10
local TRACER_DIST = 140 -- tiles from spawn point to target
local TRACER_TRAIL = 60 -- visible streak length, tiles

local function random_tracer_dir()
  local dx = (math.random() - 0.5) * 1.1 -- lean up to ~33 degrees off vertical
  return { x = dx, y = -math.sqrt(1 - dx * dx) }
end

local function destroy_tracer(s)
  for _, key in ipairs({ "tracer", "tracer_light" }) do
    local obj = s[key]
    if obj then
      pcall(function() if obj.valid then obj.destroy() end end)
      s[key] = nil
    end
  end
end

local function update_tracer(s, tick)
  local surface = s.surface
  if not (surface and surface.valid) then return end
  local q = 1 - (s.tick - tick) / TRACER_TICKS -- 0 at start, 1 at impact
  if q < 0 then return end
  s.tracer_dir = s.tracer_dir or random_tracer_dir()
  local dir = s.tracer_dir
  local remaining = TRACER_DIST * (1 - q)
  local tip = {
    x = s.pos.x + dir.x * remaining,
    y = s.pos.y + dir.y * remaining
  }
  local mid = {
    x = tip.x + dir.x * TRACER_TRAIL / 2,
    y = tip.y + dir.y * TRACER_TRAIL / 2
  }
  pcall(function()
    if not s.tracer then
      -- streak texture points north (tail up); rotate its head along the dive
      local atan2 = math.atan2 or math.atan
      local orientation = (atan2(dir.x, -dir.y) / (2 * math.pi)) % 1
      s.tracer = rendering.draw_sprite{
        sprite = "tungsten-rain-tracer",
        target = mid,
        surface = surface,
        orientation = orientation,
        x_scale = 1.1,
        y_scale = TRACER_TRAIL / 16, -- 512 px = 16 tiles at scale 1
        tint = { r = 1, g = 0.93, b = 0.8, a = 0.95 },
        render_layer = "air-object"
      }
      s.tracer_light = rendering.draw_light{
        sprite = "utility/light_medium",
        scale = 5,
        intensity = 0.9,
        color = { r = 1, g = 0.9, b = 0.7 },
        target = tip,
        surface = surface
      }
    else
      if s.tracer.valid then s.tracer.target = mid end
      if s.tracer_light and s.tracer_light.valid then
        s.tracer_light.target = tip
      end
    end
  end)
end

-- One ring of the expanding blast: damages only the annulus (r_inner, r_outer]
-- that the shockwave front has swept since the previous pulse, so damage rolls
-- outward from the impact point in step with the visual front. Linear falloff
-- from 100% at the center to 30% at the rim; each entity is caught exactly once,
-- when the front reaches it — the core takes the penetrator hit first and hardest,
-- the rim takes the spent wave last and weakest.
local function damage_area(d)
  local surface = d.surface
  if not (surface and surface.valid) then return end
  local ok_find, entities = pcall(function()
    return surface.find_entities_filtered{ position = d.pos, radius = d.r_outer }
  end)
  if not (ok_find and entities) then return end
  for _, e in pairs(entities) do
    if e.valid and e.health and e.health > 0 then
      local skip = false
      if not d.friendly_fire and d.force and e.force == d.force then skip = true end
      if d.spare_trees and e.type == "tree" then skip = true end
      if not skip then
        local dx = e.position.x - d.pos.x
        local dy = e.position.y - d.pos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        -- Damage the whole GROWING disc the front has swept, on every pulse: a
        -- target under the blast takes a hit on each pass (the center gets hammered
        -- pulse after pulse, the rim once the front reaches it). No "hit once" cap
        -- and no band gaps to slip through — the point is that it dies, even if it
        -- takes ten hits to get there.
        if dist <= d.r_outer then
          local falloff = math.max(0.3, 1 - dist / d.radius)
          local dmg = d.damage * falloff
          -- Relativistic core: the kill always goes straight through health,
          -- bypassing every resistance, per-hit cap and overkill-protection some
          -- modpacks (Rampant fixed) bolt onto the damage system at
          -- data-final-fixes. At 0.01c armour is a rounding error. A lethal hit
          -- deletes the target outright; a survivor loses the rest from health.
          if dmg >= e.health then
            if e.type == "combat-robot" then
              vaporize(e)
            elseif e.type == "unit" then
              kill_stack(surface, e, d.force or "neutral")
            else
              pcall(function() e.die(d.force or "neutral") end)
            end
          else
            pcall(function() e.health = e.health - dmg end)
            -- the same impact also strikes with every logical conventional type
            -- (these obey vanilla resistances) so armour and other mods' on-damage
            -- hooks still see a kinetic blast; the health chunk above is the kill.
            for _, dt in ipairs(LOGICAL_DAMAGE_TYPES) do
              if e.valid then pcall(e.damage, dmg, d.force or "neutral", dt) end
            end
          end
          if e.valid and d.fire_damage and d.fire_damage > 0 then
            pcall(e.damage, d.fire_damage * falloff, d.force or "neutral", "fire")
          end
        end
      end
    end
  end
  -- a couple of detonations on the advancing ring, so the wavefront is visible
  if d.fx then
    local band = math.max(0.1, d.r_outer - d.r_inner)
    for _ = 1, 2 do
      local a = math.random() * 2 * math.pi
      local rr = d.r_inner + math.random() * band
      spawn_first_valid(surface, WAVE_CANDIDATES,
        { x = d.pos.x + math.cos(a) * rr, y = d.pos.y + math.sin(a) * rr })
    end
  end
end

local function do_strike(s)
  local surface = s.surface
  if not (surface and surface.valid) then
    destroy_tracer(s)
    return
  end
  -- the tracer lingers as an ionized afterglow in the rarefied trail,
  -- fading from white-hot to pale blue as the plasma recombines
  if s.tracer then
    table.insert(storage.trails, {
      line = s.tracer,
      light = s.tracer_light,
      start = game.tick,
      duration = 55
    })
    s.tracer, s.tracer_light = nil, nil
  end
  local pos = s.pos

  -- visuals: the central fireball is a staggered cluster of nuke-class
  -- explosions, not a single one — vanilla nuke art is drawn for a 35-tile
  -- blast and looks undersized alone at our radii
  spawn_first_valid(surface, EXPLOSION_CANDIDATES, pos)
  if s.fx then
    for i = 1, 5 do
      local a = math.random() * 2 * math.pi
      local d = (0.04 + math.random() * 0.10) * s.radius
      table.insert(storage.fx, {
        tick = game.tick + i * 6,
        surface = surface,
        pos = pos,
        r = d,
        count = 1,
        names = EXPLOSION_CANDIDATES
      })
    end
  end
  spawn_first_valid(surface, SCORCH_CANDIDATES, pos)
  pcall(function() surface.play_sound{ path = "utility/alert_destroyed", position = pos } end)

  if s.fx then
    -- continuous blast wave: a glowing front (stroked circle) and a dust torus
    -- (procedural sprite) expand together from the center to the rim, animated
    -- per tick in the on_tick handler below
    local wave = {
      pos = pos,
      surface = surface,
      radius = s.radius,
      start = game.tick,
      -- rim-to-rim time = the damage bombardment window, so the visual front and
      -- the damage ring expand together (min 48 ticks so a 1-pulse strike still
      -- gets a visible sweep)
      duration = math.max(48, math.max(1, math.floor(s.pulses or 1))
                              * math.max(1, math.floor(s.interval or 30)))
    }
    pcall(function()
      wave.flash = rendering.draw_circle{
        color = { r = 1, g = 0.95, b = 0.85, a = 0.9 },
        radius = 2, filled = true,
        target = pos, surface = surface, draw_on_ground = true
      }
      -- soft gaussian glow sprite instead of a stroked circle: no razor edge
      wave.front = rendering.draw_sprite{
        sprite = "tungsten-rain-glow-ring",
        target = pos, surface = surface,
        x_scale = 0.05, y_scale = 0.05,
        tint = { r = 1, g = 0.6, b = 0.25, a = 0 },
        render_layer = "air-object"
      }
      -- two dust layers, second rotated a quarter turn and trailing slightly:
      -- doubles perceived density and breaks up the texture repetition
      wave.dust = rendering.draw_sprite{
        sprite = "tungsten-rain-dust-ring",
        target = pos, surface = surface,
        x_scale = 0.1, y_scale = 0.1,
        tint = { r = 1, g = 1, b = 1, a = 0 },
        render_layer = "air-object"
      }
      wave.dust2 = rendering.draw_sprite{
        sprite = "tungsten-rain-dust-ring",
        target = pos, surface = surface,
        x_scale = 0.1, y_scale = 0.1,
        orientation = 0.25,
        tint = { r = 1, g = 1, b = 1, a = 0 },
        render_layer = "air-object"
      }
    end)
    table.insert(storage.waves, wave)

    -- secondary detonations: sparse random pops while the wave passes through
    -- (do_fx picks a random angle; sqrt gives an even spread over the area)
    for _ = 1, 14 do
      local d = math.sqrt(math.random()) * s.radius
      table.insert(storage.fx, {
        tick = game.tick + 4 + math.random(0, 66),
        surface = surface,
        pos = pos,
        r = d,
        count = 1,
        names = WAVE_CANDIDATES
      })
    end

    -- footprint: scattered scorchmarks + smouldering smoke in the crater zone
    for _ = 1, 8 do
      local a = math.random() * 2 * math.pi
      local d = (0.2 + math.random() * 0.6) * s.radius
      spawn_first_valid(surface, SMALL_SCORCH_CANDIDATES,
        { x = pos.x + math.cos(a) * d, y = pos.y + math.sin(a) * d })
    end
    for _ = 1, 3 do
      local a = math.random() * 2 * math.pi
      local d = math.random() * s.radius * 0.25
      spawn_first_valid(surface, SMOKE_CANDIDATES,
        { x = pos.x + math.cos(a) * d, y = pos.y + math.sin(a) * d })
    end
  end

  -- fireball: the vaporized rod and ground plasma ignite the inner blast zone.
  -- No radiation — but fire does not need a warhead either.
  if s.start_fires then
    for _ = 1, 24 do
      local a = math.random() * 2 * math.pi
      local d = math.random() * s.radius * 0.6
      pcall(surface.create_entity, {
        name = "fire-flame",
        position = { x = pos.x + math.cos(a) * d, y = pos.y + math.sin(a) * d }
      })
    end
  end

  -- damage: physical (shockwave) + fire (fireball) dealt as an expanding ring,
  -- not one instant hit. The front rolls outward from the impact point over the
  -- bombardment window (default 6 pulses x 0.5 s = 3 s), decelerating on the same
  -- curve as the visual wave, R*(1-(1-p)^2), so damage and graphics stay locked
  -- together. Pulse k damages the annulus the front swept since the last pulse:
  -- the core eats the penetrator hit at t=0, the rim is reached last and weakest.
  local pulses = math.max(1, math.floor(s.pulses or 1))
  local interval = math.max(1, math.floor(s.interval or 30))
  local prev_r = 0
  for k = 1, pulses do
    local p = k / pulses
    local front_r = s.radius * (1 - (1 - p) * (1 - p))
    table.insert(storage.dmg, {
      tick = game.tick + (k - 1) * interval,
      pos = pos,
      surface = surface,
      r_inner = prev_r,
      r_outer = front_r,
      radius = s.radius,
      damage = s.damage,
      fire_damage = s.fire_damage,
      force = s.force,
      friendly_fire = s.friendly_fire,
      spare_trees = s.spare_trees,
      -- only later rings spawn extra pops; the impact frame is busy enough
      fx = s.fx and k > 1
    })
    prev_r = front_r
  end

  if s.force then
    -- chart the blast area so the result is visible through the fog of war
    pcall(function()
      local r = s.radius * 1.5
      s.force.chart(surface, {
        { pos.x - r, pos.y - r },
        { pos.x + r, pos.y + r }
      })
    end)
    pcall(function()
      s.force.print({ "tungsten-rain.impact", math.floor(pos.x), math.floor(pos.y), surface.name })
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Blast wave animation: one glowing front + one dust torus per strike,
-- updated every tick until the wave reaches the rim
-- ---------------------------------------------------------------------------
local function destroy_wave(w)
  for _, key in ipairs({ "flash", "front", "dust", "dust2" }) do
    local obj = w[key]
    if obj then
      pcall(function() if obj.valid then obj.destroy() end end)
      w[key] = nil
    end
  end
end

local function update_wave(w, tick)
  local p = (tick - w.start) / w.duration
  if p >= 1 then
    destroy_wave(w)
    return false
  end
  -- decelerating front, like a real blast: fast at first, stalling at the rim
  local front_r = w.radius * (1 - (1 - p) * (1 - p))
  pcall(function()
    if w.front and w.front.valid then
      -- glow texture has its ring at ~0.60 of half-size: ~4.8 tiles at scale 1
      local fscale = math.max(0.05, front_r / 4.8)
      w.front.x_scale = fscale
      w.front.y_scale = fscale
      w.front.color = {
        r = 1, g = 0.6 - 0.3 * p, b = 0.25 - 0.18 * p, a = 0.9 * (1 - p)
      }
    end
    if w.flash then
      -- white core flash, gone in the first ~0.25 s
      if p < 0.25 and w.flash.valid then
        w.flash.radius = math.max(2, front_r * 0.85)
        w.flash.color = { r = 1, g = 0.95, b = 0.85, a = 0.9 * (1 - p / 0.25) }
      else
        if w.flash.valid then w.flash.destroy() end
        w.flash = nil
      end
    end
    -- dust wall trails just behind the front; the torus texture has its ring
    -- at ~0.60 of half-size, i.e. visual ring radius ~5 tiles at scale 1
    local dust_a = math.sin(math.pi * math.min(1, p * 1.05)) * 0.95
    if w.dust and w.dust.valid then
      local scale = math.max(0.05, front_r / 5.6)
      w.dust.x_scale = scale
      w.dust.y_scale = scale
      w.dust.color = { r = 1, g = 1, b = 1, a = dust_a }
    end
    if w.dust2 and w.dust2.valid then
      local scale = math.max(0.05, front_r / 6.2) -- trails the first layer
      w.dust2.x_scale = scale
      w.dust2.y_scale = scale
      w.dust2.color = { r = 1, g = 1, b = 1, a = dust_a * 0.8 }
    end
  end)
  return true
end

-- ---------------------------------------------------------------------------
-- Targeting
-- ---------------------------------------------------------------------------

-- Greedily cover a set of nest positions with as few strikes as possible: each
-- strike's blast (radius) wipes everything within it, so we cluster nests that
-- fall inside one radius into a single rod. Returns strike points sorted by how
-- many nests each covers (densest first), so a rod-limited carpet hits the worst
-- clusters before running dry. This is what makes a carpet economize rods.
-- Points are bucketed into a grid of radius-sized cells, so each seed only looks
-- at its neighbourhood instead of every remaining nest: linear in the number of
-- nests rather than quadratic. The work is resumable — cluster_run does a
-- bounded number of seeds per call — so auto-fire can spread it over many
-- ticks; the state is plain tables and lives in storage between ticks.
local function cluster_new(targets, radius)
  local cell = math.max(1, radius)
  local grid = {}
  for i, t in ipairs(targets) do
    local gx, gy = math.floor(t.x / cell), math.floor(t.y / cell)
    local col = grid[gx]
    if not col then col = {}; grid[gx] = col end
    local bucket = col[gy]
    if not bucket then bucket = {}; col[gy] = bucket end
    bucket[#bucket + 1] = i
  end
  local alive = {}
  for i = 1, #targets do alive[i] = true end
  return { targets = targets, cell = cell, r2 = radius * radius, grid = grid,
           alive = alive, next_seed = 1, pts = {} }
end

-- calls fn(i, t) for every live point within one cell of (x, y)
local function cluster_each_near(st, x, y, fn)
  local cell, grid, alive, targets = st.cell, st.grid, st.alive, st.targets
  local gx, gy = math.floor(x / cell), math.floor(y / cell)
  for ix = gx - 1, gx + 1 do
    local col = grid[ix]
    if col then
      for iy = gy - 1, gy + 1 do
        local bucket = col[iy]
        if bucket then
          for _, i in ipairs(bucket) do
            if alive[i] then fn(i, targets[i]) end
          end
        end
      end
    end
  end
end

-- Process up to `budget` seeds; returns true once every point is clustered.
local function cluster_run(st, budget)
  local targets, alive, r2, pts = st.targets, st.alive, st.r2, st.pts
  local n_targets = #targets
  local seed_i = st.next_seed
  while budget > 0 and seed_i <= n_targets do
    if alive[seed_i] then
      budget = budget - 1
      local seed = targets[seed_i]
      -- centroid of every nest within one radius of the seed
      local cx, cy, n = 0, 0, 0
      cluster_each_near(st, seed.x, seed.y, function(_, t)
        local dx, dy = t.x - seed.x, t.y - seed.y
        if dx * dx + dy * dy <= r2 then
          cx = cx + t.x; cy = cy + t.y; n = n + 1
        end
      end)
      local sx, sy = cx / n, cy / n
      -- drop everything the strike at the centroid actually covers
      local covered = 0
      cluster_each_near(st, sx, sy, function(i, t)
        local dx, dy = t.x - sx, t.y - sy
        if dx * dx + dy * dy <= r2 then
          alive[i] = false; covered = covered + 1
        end
      end)
      alive[seed_i] = false -- safety: seed gone even if the centroid drifted off it
      pts[#pts + 1] = { x = sx, y = sy, count = math.max(1, covered) }
    end
    seed_i = seed_i + 1
  end
  st.next_seed = seed_i
  return seed_i > n_targets
end

local function cluster_finish(st)
  local pts = st.pts
  table.sort(pts, function(a, b) return a.count > b.count end)
  return pts
end

local function cluster_strikes(targets, radius)
  local st = cluster_new(targets, radius)
  cluster_run(st, math.huge)
  return cluster_finish(st)
end

-- Queue one incoming rod at pos plus its target marker.
local function schedule_strike(surface, force, pos, radius, power, c, now)
  table.insert(storage.strikes, {
    tick = now + c.delay,
    pos = pos,
    surface = surface,
    force = force,
    radius = radius,
    damage = c.damage * power,
    fire_damage = c.fire_damage * power,
    start_fires = c.start_fires,
    fx = c.fx,
    friendly_fire = c.friendly_fire,
    spare_trees = c.spare_trees,
    pulses = c.dmg_pulses,
    interval = c.dmg_interval
  })
  pcall(function()
    rendering.draw_circle{
      color = { r = 1, g = 0.1, b = 0.1, a = 0.6 },
      radius = radius,
      width = 4,
      target = pos,
      surface = surface,
      time_to_live = math.max(c.delay, 1),
      draw_on_ground = true
    }
  end)
end

-- Radar coverage as a handful of non-overlapping rectangles. Each radar covers a
-- square of +-range tiles, rounded out to whole chunks (the radar's own scan is
-- chunk-based too). Overlapping squares are merged per chunk row, and identical
-- row spans stacked into rectangles, so every tile in range is searched exactly
-- once — a base with dozens of radars used to be searched once per radar.
local function radar_coverage(radars, range)
  local rows = {}
  for _, radar in pairs(radars) do
    if radar.valid then
      local p = radar.position
      local x0, x1 = math.floor((p.x - range) / 32), math.floor((p.x + range) / 32)
      for cy = math.floor((p.y - range) / 32), math.floor((p.y + range) / 32) do
        local row = rows[cy]
        if not row then row = {}; rows[cy] = row end
        row[#row + 1] = { x0, x1 }
      end
    end
  end
  local ys = {}
  for cy in pairs(rows) do ys[#ys + 1] = cy end
  table.sort(ys)

  local rects, open = {}, {}
  for _, cy in ipairs(ys) do
    local spans = rows[cy]
    table.sort(spans, function(u, v) return u[1] < v[1] end)
    local next_open = {}
    local cur
    local function close_span()
      local key = cur[1] .. ":" .. cur[2]
      local r = open[key]
      if r and r.y1 == cy - 1 then
        r.y1 = cy
      else
        r = { x0 = cur[1], x1 = cur[2], y0 = cy, y1 = cy }
        rects[#rects + 1] = r
      end
      next_open[key] = r
    end
    for _, span in ipairs(spans) do
      if cur and span[1] <= cur[2] + 1 then
        if span[2] > cur[2] then cur[2] = span[2] end
      else
        if cur then close_span() end
        cur = { span[1], span[2] }
      end
    end
    close_span()
    open = next_open
  end

  -- cut into pieces of at most PIECE x PIECE chunks, so one search is small
  -- enough to do a few per tick without a hitch
  local PIECE = 4
  local areas = {}
  for _, r in ipairs(rects) do
    for py = r.y0, r.y1, PIECE do
      for px = r.x0, r.x1, PIECE do
        local qx, qy = math.min(px + PIECE - 1, r.x1), math.min(py + PIECE - 1, r.y1)
        areas[#areas + 1] = { { px * 32, py * 32 }, { (qx + 1) * 32, (qy + 1) * 32 } }
      end
    end
  end
  return areas
end

-- Squared distance from p to the nearest radar. Radars are pre-bucketed in cells
-- of `cell` tiles; every target sits in some radar's (chunk-rounded) square, so
-- the nearest radar is at most cell*sqrt(2) away and two cells of reach find it.
local function nearest_radar_d2(radar_grid, cell, p)
  local gx, gy = math.floor(p.x / cell), math.floor(p.y / cell)
  local best = math.huge
  for ix = gx - 2, gx + 2 do
    local col = radar_grid[ix]
    if col then
      for iy = gy - 2, gy + 2 do
        local bucket = col[iy]
        if bucket then
          for _, rp in ipairs(bucket) do
            local dx, dy = p.x - rp.x, p.y - rp.y
            local d = dx * dx + dy * dy
            if d < best then best = d end
          end
        end
      end
    end
  end
  return best
end

-- Auto-fire is a sweep spread over the whole interval instead of one burst:
--   scan    — a few radar-coverage pieces searched per tick, done by SCAN_SHARE
--             of the interval;
--   cluster — a batch of nests grouped per tick, done by CLUSTER_SHARE;
--   fire    — nearest-first sort and launch, one cheap step per ring.
-- The per-tick budget is whatever is left divided by the ticks left, so a small
-- sweep finishes in a few ticks and a huge one is smeared evenly. All state
-- lives in storage (multiplayer- and save-safe). Rods fire when a ring's sweep
-- finishes, at most CLUSTER_SHARE of the interval after it started.
local SCAN_SHARE, CLUSTER_SHARE = 0.5, 0.9
local MIN_SEEDS_PER_TICK = 50

-- live radars of `force` on `surface`, pruning dead registry entries
local function registered_radars(surface, force)
  local by_id = storage.radars and storage.radars[surface.index]
  local out = {}
  if not by_id then return out end
  for id, r in pairs(by_id) do
    if not r.valid then
      by_id[id] = nil
    elseif r.force == force then
      out[#out + 1] = r
    end
  end
  return out
end

local function register_radar(event)
  local e = event.entity or event.destination
  if not (e and e.valid and e.type == "radar" and e.unit_number) then return end
  storage.radars = storage.radars or {}
  local by_id = storage.radars[e.surface.index]
  if not by_id then by_id = {}; storage.radars[e.surface.index] = by_id end
  by_id[e.unit_number] = e
end

local RADAR_FILTER = { { filter = "type", type = "radar" } }
for _, ev in ipairs({ "on_built_entity", "on_robot_built_entity", "script_raised_built",
                      "script_raised_revive", "on_entity_cloned" }) do
  if defines.events[ev] then
    script.on_event(defines.events[ev], register_radar, RADAR_FILTER)
  end
end

-- Queue one ring's sweep job (nothing is searched yet)
local function auto_fire_job(c, force, surface, ring)
  local radars = registered_radars(surface, force)
  if #radars == 0 then return nil end
  local enemies = {}
  for _, f in pairs(game.forces) do
    if f ~= force and force.is_enemy(f) then enemies[#enemies + 1] = f end
  end
  if #enemies == 0 then return nil end
  local radar_pos = {}
  for i, r in ipairs(radars) do radar_pos[i] = { x = r.position.x, y = r.position.y } end
  return {
    force = force, surface = surface, ring = ring, enemies = enemies,
    radar_pos = radar_pos,
    pieces = radar_coverage(radars, c.auto_range), next_piece = 1,
    targets = {}
  }
end

-- Automatic bombardment: every force's rings hit the nearest enemy nests (and,
-- optionally, worms) sitting inside radar coverage, clustered by blast radius so
-- rods are not wasted, nearest threats first, capped by charged rods. Assigned to
-- the forward-declared `auto_fire` so on_nth_tick (defined earlier) can call it;
-- it only STARTS a sweep, auto_fire_step does the work tick by tick.
-- Only rings that can actually fire are swept: an empty, paused or unbuilt ring
-- costs nothing, and forces without rings (enemy, neutral, modded) are skipped.
auto_fire = function(c, tick)
  local jobs = {}
  if c.require_rods then
    for force_name, by_planet in pairs(storage.rings) do
      local force = game.forces[force_name]
      if force and force.valid then
        for planet_name, ring in pairs(by_planet) do
          if ring.enabled and (ring.stations or 0) > 0 then
            finish_charging(ring, tick)
            local planet = game.planets[planet_name]
            local surface = planet and planet.surface
            if (ring.charged or 0) > 0 and surface and surface.valid then
              jobs[#jobs + 1] = auto_fire_job(c, force, surface, ring)
            end
          end
        end
      end
    end
  else
    -- free strikes (testing): no rings needed, any force with players fires
    for _, force in pairs(game.forces) do
      if #force.players > 0 then
        for _, surface in pairs(game.surfaces) do
          if surface.valid and surface.planet then
            jobs[#jobs + 1] = auto_fire_job(c, force, surface, nil)
          end
        end
      end
    end
  end
  if #jobs == 0 then return end
  storage.auto_sweep = {
    c = c, jobs = jobs, phase = "scan", job_i = 1,
    scan_end = tick + math.max(1, math.floor(c.auto_interval * SCAN_SHARE)),
    cluster_end = tick + math.max(2, math.floor(c.auto_interval * CLUSTER_SHARE))
  }
end

local function remaining_share(total_left, deadline, tick, min_per_tick)
  local ticks_left = math.max(1, deadline - tick)
  return math.max(min_per_tick, math.ceil(total_left / ticks_left))
end

-- Launch one finished job's clusters, nearest radar first
local function auto_fire_launch(sw, job, tick)
  local c, force, surface, ring = sw.c, job.force, job.surface, job.ring
  if not (surface.valid and force.valid) then return end
  local free = not c.require_rods
  if not free then
    -- the ring may have been paused or spent by hand while we were sweeping
    finish_charging(ring, tick)
    if not ring.enabled or (ring.charged or 0) < 1 then return end
  end
  local pts = cluster_finish(job.cl)
  if #pts == 0 then return end

  local cell = c.auto_range + 32
  local radar_grid = {}
  for _, rp in ipairs(job.radar_pos) do
    local gx, gy = math.floor(rp.x / cell), math.floor(rp.y / cell)
    local col = radar_grid[gx]
    if not col then col = {}; radar_grid[gx] = col end
    local bucket = col[gy]
    if not bucket then bucket = {}; col[gy] = bucket end
    bucket[#bucket + 1] = rp
  end
  for _, p in ipairs(pts) do p.d = nearest_radar_d2(radar_grid, cell, p) end
  table.sort(pts, function(a, b) return a.d < b.d end)

  local power = free and 1 or ring_power(ring, c)
  local radius = job.radius
  local avail = free and math.huge or ring.charged
  local fired = 0
  for _, p in ipairs(pts) do
    if fired >= avail then break end
    schedule_strike(surface, force, { x = p.x, y = p.y }, radius, power, c, tick)
    fired = fired + 1
  end
  if not free then ring.charged = ring.charged - fired end
  if fired > 0 then
    pcall(function()
      force.print({ "tungsten-rain.auto", fired, surface.planet.name })
    end)
  end
end

-- One tick of the sweep in progress. Called from on_tick; a no-op when idle.
local function auto_fire_step(tick)
  local sw = storage.auto_sweep
  if not sw then return end
  if not settings.global["tungsten-rain-auto-fire"].value then
    storage.auto_sweep = nil
    return
  end
  local jobs = sw.jobs

  if sw.phase == "scan" then
    local left = 0
    for i = sw.job_i, #jobs do left = left + (#jobs[i].pieces - jobs[i].next_piece + 1) end
    local budget = remaining_share(left, sw.scan_end, tick, 1)
    while budget > 0 and sw.job_i <= #jobs do
      local job = jobs[sw.job_i]
      if job.next_piece > #job.pieces or not job.surface.valid then
        sw.job_i = sw.job_i + 1
      else
        local area = job.pieces[job.next_piece]
        job.next_piece = job.next_piece + 1
        budget = budget - 1
        local types = sw.c.auto_worms and { "unit-spawner", "turret" } or { "unit-spawner" }
        local ok_e, ents = pcall(function()
          return job.surface.find_entities_filtered{ area = area, type = types, force = job.enemies }
        end)
        if ok_e and ents then
          local targets = job.targets
          for _, e in pairs(ents) do
            if e.valid then targets[#targets + 1] = e.position end
          end
        end
      end
    end
    if sw.job_i > #jobs then
      -- scan done: set up clustering for every job at the power its ring has now
      for _, job in ipairs(jobs) do
        local power = (not sw.c.require_rods) and 1 or ring_power(job.ring, sw.c)
        job.radius = math.max(5, sw.c.radius * power ^ (1 / 3))
        job.cl = cluster_new(job.targets, job.radius)
        job.targets = nil
      end
      sw.phase, sw.job_i = "cluster", 1
    end
    return
  end

  if sw.phase == "cluster" then
    local left = 0
    for i = sw.job_i, #jobs do left = left + (#jobs[i].cl.targets - jobs[i].cl.next_seed + 1) end
    local budget = remaining_share(left, sw.cluster_end, tick, MIN_SEEDS_PER_TICK)
    while budget > 0 and sw.job_i <= #jobs do
      local job = jobs[sw.job_i]
      local before = job.cl.next_seed
      if cluster_run(job.cl, budget) then
        auto_fire_launch(sw, job, tick)
        job.cl = nil
        sw.job_i = sw.job_i + 1
      end
      budget = budget - (job.cl and (job.cl.next_seed - before) or 1)
    end
    if sw.job_i > #jobs then storage.auto_sweep = nil end
  end
end

local function on_selected(event)
  if event.item ~= "tungsten-rain-targeter" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end

  -- no shooting at your own platform deck
  if surface.platform then
    player.print({ "tungsten-rain.no-platform-strikes" })
    return
  end

  local c = cfg()
  local now = game.tick
  local force = player.force

  local ready_at = storage.next_shot[force.name] or 0
  if ready_at > now then
    player.print({ "tungsten-rain.cooldown", math.ceil((ready_at - now) / 60) })
    return
  end

  local ring -- set when rods are required
  local power = 1       -- energy fraction of a full-power shot
  local available = math.huge -- charged rods we may fire this select
  if c.require_rods then
    local planet = surface.planet
    if not planet then
      player.print({ "tungsten-rain.no-planet" })
      return
    end
    ring = get_ring(force.name, planet.name)
    finish_charging(ring, now)
    if ring.stations < 1 then
      if ring.enabled then
        player.print({ "tungsten-rain.ring-not-built", c.stations_full })
      else
        player.print({ "tungsten-rain.ring-disabled" })
      end
      return
    end
    if ring.charged < 1 then
      if ring.charging_done then
        player.print({ "tungsten-rain.ring-charging", math.ceil((ring.charging_done - now) / 60) })
      else
        player.print({ "tungsten-rain.no-rods" })
      end
      return
    end
    power = ring_power(ring, c)
    available = ring.charged
  end

  -- scale with ring power: damage ~ energy, radius ~ energy^(1/3)
  local radius = math.max(5, c.radius * power ^ (1 / 3))
  local area = event.area

  -- carpet mode: rain a rod on every enemy nest in the selection, but cluster
  -- them by blast radius so one rod covers a whole clump — no wasted slugs.
  local nests = {}
  pcall(function()
    for _, e in pairs(surface.find_entities_filtered{ area = area, type = "unit-spawner" }) do
      if e.valid and e.force ~= force then nests[#nests + 1] = e.position end
    end
  end)

  local points
  if #nests > 0 then
    points = cluster_strikes(nests, radius)
  else
    -- nothing to carpet: a single strike at the center, as before
    points = { {
      x = (area.left_top.x + area.right_bottom.x) / 2,
      y = (area.left_top.y + area.right_bottom.y) / 2
    } }
  end

  local fired = 0
  for _, p in ipairs(points) do
    if fired >= available then break end
    schedule_strike(surface, force, p, radius, power, c, now)
    fired = fired + 1
  end
  if fired == 0 then return end

  if c.require_rods then
    ring.charged = ring.charged - fired
  end
  storage.next_shot[force.name] = now + c.cooldown

  local left = c.require_rods and ring.charged or "∞"
  if #nests > 0 then
    local uncovered = #points - fired
    if uncovered > 0 then
      player.print({ "tungsten-rain.carpet-short", fired, uncovered, left })
    else
      player.print({ "tungsten-rain.carpet", fired, left, math.floor(power * 100 + 0.5) })
    end
  else
    player.print({ "tungsten-rain.incoming", left, math.floor(power * 100 + 0.5) })
  end
  pcall(function()
    surface.play_sound{ path = "utility/new_objective", position = points[1] }
  end)
end

-- Alt-select with the targeter: toggle ring assembly above the current planet.
-- Pausing only stops pulling stations/rods from hubs; charged rods stay charged
-- and remain fireable, and an in-progress spin-up still completes.
local function on_alt_selected(event)
  if event.item ~= "tungsten-rain-targeter" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end
  local planet = surface.planet
  if not planet then
    player.print({ "tungsten-rain.no-planet" })
    return
  end

  local c = cfg()
  local ring = get_ring(player.force.name, planet.name)
  finish_charging(ring, game.tick)
  ring.enabled = not ring.enabled
  local key = ring.enabled and "tungsten-rain.ring-enabled" or "tungsten-rain.ring-paused"
  player.print({ key, planet.name, ring.stations, c.stations_full, ring.charged })
end

-- ---------------------------------------------------------------------------
-- Needle cartridges and protected zones
-- A needle cartridge is a 10 kg bundle of 100 steel needles held at 15 km/s —
-- slow enough that a ring holds it on a far weaker pulse than a rod, and every
-- station forges its own out of the asteroid dust the ring sweeps up. It enters
-- the atmosphere whole under its plasma cocoon; the spiral's induced current
-- decays on a timer set by the firing pulse, and at ~1 km the binding lets go
-- and the cocoon itself blows the bundle open into a spray — one needle per
-- target, no blast, no crater. Zones are marked with the targeter's
-- reverse-select; every enemy that walks into one gets a needle.
-- ---------------------------------------------------------------------------
-- combat-robot: Rampant drones and eggs (vaporized, so eggs never hatch)
local NEEDLE_TYPES = { "unit", "unit-spawner", "turret", "spider-unit", "combat-robot" }
local NEEDLE_DELAY = 90   -- ticks from release to impact
local ZONE_SCAN_PERIOD = 60 -- every zone piece is searched once per second
local ZONE_PIECE = 128    -- tiles per side of one search piece
-- needle visuals, in ticks before impact: the cartridge streaks down from the
-- sky, opens over the group, then each needle flies to its own target
local NEEDLE_SKY_TICKS = 36
local NEEDLE_SPLIT_TICKS = 16
local NEEDLE_BURST_HEIGHT = 16 -- tiles screen-up of the group's middle
-- the sky streak's trail fades this many ticks after impact: top piece first,
-- the piece nearest the burst last (the needle fan itself is gone at impact)
local NEEDLE_TRAIL_MIN = 4
local NEEDLE_TRAIL_MAX = 14
-- each needle line lingers up to this many extra ticks, at random, so the fan
-- goes out ragged instead of all at once (still mostly before the trail)
local NEEDLE_FAN_JITTER = 6
-- and appears up to this many ticks late (must stay below half the split time)
local NEEDLE_APPEAR_JITTER = 6
local NEEDLE_COLOR = { r = 1, g = 0.78, b = 0.45, a = 0.95 }

local function enemy_forces(force)
  local out = {}
  for _, f in pairs(game.forces) do
    if f ~= force and force.is_enemy(f) then out[#out + 1] = f end
  end
  return out
end

-- Flat list of search pieces across every zone, so the per-tick scanner can
-- walk them round-robin: each zone is cut into ZONE_PIECE-sized squares.
local function rebuild_zone_pieces()
  local pieces = {}
  for force_name, by_surface in pairs(storage.zones) do
    for surface_index, zones in pairs(by_surface) do
      for id, z in pairs(zones) do
        local a = z.area
        for y = a.left_top.y, a.right_bottom.y - 1e-6, ZONE_PIECE do
          for x = a.left_top.x, a.right_bottom.x - 1e-6, ZONE_PIECE do
            pieces[#pieces + 1] = {
              force_name = force_name, surface_index = surface_index, zone_id = id,
              area = { { x, y }, { math.min(x + ZONE_PIECE, a.right_bottom.x),
                                   math.min(y + ZONE_PIECE, a.right_bottom.y) } }
            }
          end
        end
      end
    end
  end
  storage.zone_pieces = pieces
  storage.zone_cursor = 1
end

local function draw_zone(surface, force, area)
  local ok, obj = pcall(function()
    return rendering.draw_rectangle{
      color = { r = 0.2, g = 0.6, b = 1, a = 0.5 },
      width = 3,
      filled = false,
      left_top = area.left_top,
      right_bottom = area.right_bottom,
      surface = surface,
      forces = { force },
      draw_on_ground = true
    }
  end)
  return ok and obj or nil
end

-- drop this force's zone on this surface, if any; returns whether there was one
local function clear_zone(force, surface)
  local by_surface = storage.zones[force.name]
  local zones = by_surface and by_surface[surface.index]
  if not zones then return false end
  local had = false
  for _, z in pairs(zones) do
    pcall(function() if z.render and z.render.valid then z.render.destroy() end end)
    had = true
  end
  by_surface[surface.index] = nil
  rebuild_zone_pieces()
  return had
end

-- one zone per planet: marking a new one replaces the old
local function add_zone(force, surface, area)
  clear_zone(force, surface)
  local by_surface = storage.zones[force.name]
  if not by_surface then by_surface = {}; storage.zones[force.name] = by_surface end
  local zones = {}
  by_surface[surface.index] = zones
  local id = storage.zone_next_id
  storage.zone_next_id = id + 1
  local a = {
    left_top = { x = math.floor(area.left_top.x), y = math.floor(area.left_top.y) },
    right_bottom = { x = math.ceil(area.right_bottom.x), y = math.ceil(area.right_bottom.y) }
  }
  zones[id] = { id = id, area = a, render = draw_zone(surface, force, a) }
  rebuild_zone_pieces()
end

-- Split fresh targets into cartridges: each takes up to needle_targets enemies
-- within needle_radius of its first one. Returns lists of entities.
local function group_for_cartridges(targets, radius, per_cartridge)
  local r2 = radius * radius
  local taken, groups = {}, {}
  for i, seed in ipairs(targets) do
    if not taken[i] then
      local sp = seed.position
      local group = {}
      for j = i, #targets do
        if not taken[j] then
          local p = targets[j].position
          local dx, dy = p.x - sp.x, p.y - sp.y
          if dx * dx + dy * dy <= r2 then
            taken[j] = true
            group[#group + 1] = targets[j]
            if #group >= per_cartridge then break end
          end
        end
      end
      groups[#groups + 1] = group
    end
  end
  return groups
end

-- One piece of one zone: find unclaimed enemies, spend cartridges on them.
local function scan_zone_piece(piece, c, tick)
  local force = game.forces[piece.force_name]
  local surface = game.get_surface(piece.surface_index)
  if not (force and force.valid and surface and surface.valid and surface.planet) then return end
  local free = not c.require_rods
  local ring
  if not free then
    local by_force = storage.rings[force.name]
    ring = by_force and by_force[surface.planet.name]
    if not (ring and ring.enabled and (ring.needles or 0) > 0) then return end
  end
  local enemies = enemy_forces(force)
  if #enemies == 0 then return end
  local ok, ents = pcall(function()
    return surface.find_entities_filtered{ area = piece.area, type = NEEDLE_TYPES, force = enemies }
  end)
  if not (ok and ents and #ents > 0) then return end

  local claims = storage.needle_claims
  local fresh = {}
  for _, e in pairs(ents) do
    if e.valid then
      local id = e.unit_number
      if not (id and claims[id] and claims[id] > tick) then fresh[#fresh + 1] = e end
    end
  end
  if #fresh == 0 then return end

  for _, group in ipairs(group_for_cartridges(fresh, c.needle_radius, c.needle_targets)) do
    if not free then
      if ring.needles < 1 then break end
      ring.needles = ring.needles - 1
    end
    local cx, cy = 0, 0
    for _, e in ipairs(group) do
      if e.unit_number then claims[e.unit_number] = tick + NEEDLE_DELAY + 30 end
      local p = e.position
      cx, cy = cx + p.x, cy + p.y
    end
    table.insert(storage.needle_volleys, {
      tick = tick + NEEDLE_DELAY, surface = surface, force = force, targets = group, fx = c.fx,
      -- the cartridge opens a little "above" (screen-up of) the middle of its group
      burst = { x = cx / #group, y = cy / #group - NEEDLE_BURST_HEIGHT },
      slant = (math.random() - 0.5) * 2
    })
  end
end

-- Called every tick: search the next slice of zone pieces so that every piece
-- is covered once per ZONE_SCAN_PERIOD, spread evenly instead of in a burst.
local function zone_defense_step(tick)
  local pieces = storage.zone_pieces
  if not pieces or #pieces == 0 then return end
  local c
  -- fractional pacing: #pieces per period, so 2 pieces = one search every 30 ticks
  local budget = (storage.zone_budget or 0) + #pieces / ZONE_SCAN_PERIOD
  local per_tick = math.floor(budget)
  storage.zone_budget = budget - per_tick
  for _ = 1, per_tick do
    local i = storage.zone_cursor
    if i > #pieces then i = 1 end
    storage.zone_cursor = i + 1
    c = c or cfg()
    scan_zone_piece(pieces[i], c, tick)
  end
end

-- A cartridge arrives: one needle per target, each tracked to where it is now.
local function land_volley(v)
  local surface, force = v.surface, v.force
  if not (surface and surface.valid) then return end
  for _, e in ipairs(v.targets) do
    -- normally the fan already killed it the moment its needle landed
    -- (needle_fx); this catches targets when the visuals are off
    if e.valid then needle_hit(v, e) end
  end
end

local function lerp(a, b, t) return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t } end

-- A needle strikes e: it dies, and with it its compressed stack — every biter
-- of the stack still gets its own streak from the burst
local function needle_hit(v, e)
  local surface = v.surface
  if e.type == "combat-robot" then return vaporize(e) end
  kill_stack(surface, e, v.force, v.fx and v.burst and function(n)
    rendering.draw_line{ color = NEEDLE_COLOR, width = 1.5, from = v.burst, to = n.position,
      surface = surface, time_to_live = NEEDLE_SPLIT_TICKS / 2 + math.random(0, NEEDLE_FAN_JITTER) }
  end or nil)
end

-- Per-tick visuals of a cartridge in flight: one hot streak falling from the sky
-- to the burst point, a flash, then a fan of needles — one line to every target,
-- drawn in two halves so the spray visibly spreads out. Needle tips track the
-- targets, so a running biter is still hit where it is.
local function needle_fx(v, tick)
  local surface = v.surface
  if not (surface and surface.valid) then return end
  local left = v.tick - tick
  local burst = v.burst
  if left <= NEEDLE_SKY_TICKS and left > NEEDLE_SPLIT_TICKS then
    local sky = { x = burst.x + v.slant * 30, y = burst.y - 60 }
    local t0 = (NEEDLE_SKY_TICKS - left) / (NEEDLE_SKY_TICKS - NEEDLE_SPLIT_TICKS)
    local t1 = math.min(1, t0 + 0.25)
    pcall(function()
      -- each piece lingers past the impact, so the streak's trail outlives the
      -- needle fan by a moment and fades from the top down
      local expires = NEEDLE_TRAIL_MIN + math.floor(t0 * (NEEDLE_TRAIL_MAX - NEEDLE_TRAIL_MIN))
      rendering.draw_line{ color = NEEDLE_COLOR, width = 5, from = lerp(sky, burst, t0),
        to = lerp(sky, burst, t1), surface = surface, time_to_live = left + expires }
    end)
  elseif left <= NEEDLE_SPLIT_TICKS and left > 0 then
    if left == NEEDLE_SPLIT_TICKS then
      pcall(function()
        rendering.draw_light{ sprite = "utility/light_small", scale = 3, intensity = 1,
          color = NEEDLE_COLOR, target = burst, surface = surface, time_to_live = 8 }
      end)
      -- every needle leaves the burst a little late, at random, so the fan
      -- opens ragged; each still reaches its target by the impact tick
      v.jitter = {}
      for i = 1, #v.targets do v.jitter[i] = math.random(0, NEEDLE_APPEAR_JITTER) end
    end
    local half = NEEDLE_SPLIT_TICKS / 2
    for i, e in ipairs(v.targets) do
      local j = v.jitter and v.jitter[i] or 0
      if e.valid and left == NEEDLE_SPLIT_TICKS - j then
        pcall(function()
          rendering.draw_line{ color = NEEDLE_COLOR, width = 1.5, from = burst,
            to = lerp(burst, e.position, 0.5), surface = surface,
            time_to_live = half + math.random(0, NEEDLE_FAN_JITTER) }
        end)
      elseif e.valid and left == half - j then
        -- the needle reaches its biter now: draw it to where the biter stands
        -- (a line tied to the entity would vanish with it) and kill it on the spot
        pcall(function()
          rendering.draw_line{ color = NEEDLE_COLOR, width = 1.5,
            from = lerp(burst, e.position, 0.5), to = e.position, surface = surface,
            time_to_live = half + math.random(0, NEEDLE_FAN_JITTER) }
        end)
        needle_hit(v, e)
      end
    end
  end
end

local function on_reverse_selected(event)
  if event.item ~= "tungsten-rain-targeter" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local surface = event.surface
  if not (surface and surface.valid and surface.planet) then
    if player then player.print({ "tungsten-rain.no-planet" }) end
    return
  end
  add_zone(player.force, surface, event.area)
  player.print({ "tungsten-rain.zone-added", surface.planet.name })
end

local function on_alt_reverse_selected(event)
  if event.item ~= "tungsten-rain-targeter" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end
  player.print(clear_zone(player.force, surface) and { "tungsten-rain.zone-removed" }
                                                    or { "tungsten-rain.zone-none" })
end

script.on_event(defines.events.on_player_selected_area, on_selected)
script.on_event(defines.events.on_player_reverse_selected_area, on_reverse_selected)
script.on_event(defines.events.on_player_alt_reverse_selected_area, on_alt_reverse_selected)
script.on_event(defines.events.on_player_alt_selected_area, on_alt_selected)

-- ---------------------------------------------------------------------------
-- Scheduler
-- ---------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
  if storage.auto_sweep then
    local ok = pcall(auto_fire_step, event.tick)
    if not ok then storage.auto_sweep = nil end -- never wedge on a bad sweep
  end

  pcall(zone_defense_step, event.tick)
  local volleys = storage.needle_volleys
  if volleys and #volleys > 0 then
    for i = #volleys, 1, -1 do
      local v = volleys[i]
      if event.tick >= v.tick then
        land_volley(table.remove(volleys, i))
      elseif v.fx and v.burst and event.tick >= v.tick - NEEDLE_SKY_TICKS then
        needle_fx(v, event.tick)
      end
    end
  end
  -- forget stale claims now and then (entities that died some other way)
  if event.tick % 3600 == 0 and storage.needle_claims then
    for id, t in pairs(storage.needle_claims) do
      if t <= event.tick then storage.needle_claims[id] = nil end
    end
  end

  local strikes = storage.strikes
  if strikes and #strikes > 0 then
    for i = #strikes, 1, -1 do
      local s = strikes[i]
      if event.tick >= s.tick then
        table.remove(strikes, i)
        do_strike(s)
      elseif s.fx and event.tick >= s.tick - TRACER_TICKS then
        update_tracer(s, event.tick)
      end
    end
  end

  local fx = storage.fx
  if fx and #fx > 0 then
    for i = #fx, 1, -1 do
      if event.tick >= fx[i].tick then
        do_fx(table.remove(fx, i))
      end
    end
  end

  local dmg = storage.dmg
  if dmg and #dmg > 0 then
    for i = #dmg, 1, -1 do
      if event.tick >= dmg[i].tick then
        damage_area(table.remove(dmg, i))
      end
    end
  end

  local waves = storage.waves
  if waves and #waves > 0 then
    for i = #waves, 1, -1 do
      if not update_wave(waves[i], event.tick) then
        table.remove(waves, i)
      end
    end
  end

  local trails = storage.trails
  if trails and #trails > 0 then
    for i = #trails, 1, -1 do
      local t = trails[i]
      local p = (event.tick - t.start) / t.duration
      if p >= 1 then
        for _, obj in pairs({ t.line, t.light }) do
          pcall(function() if obj.valid then obj.destroy() end end)
        end
        table.remove(trails, i)
      else
        pcall(function()
          -- ease-out fade: (1-p)^2 approaches zero asymptotically, so the
          -- final destroy is invisible instead of a hard pop
          local fade = (1 - p) * (1 - p)
          if t.line and t.line.valid then
            -- white-hot -> pale blue: the plasma in the wake recombining
            t.line.color = {
              r = 1 - 0.35 * p, g = 0.92 - 0.1 * p, b = 0.75 + 0.25 * p,
              a = 0.95 * fade
            }
          end
          if t.light and t.light.valid then
            t.light.intensity = 0.9 * fade
          end
        end)
      end
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Remote interface: for testing and for future auto-targeting integrations
-- /c remote.call("tungsten_rain", "strike", game.player.position, game.player.surface, game.player.force)
-- ---------------------------------------------------------------------------
remote.add_interface("tungsten_rain", {
  strike = function(position, surface, force)
    init_storage()
    local c = cfg()
    table.insert(storage.strikes, {
      tick = game.tick,
      pos = { x = position.x or position[1], y = position.y or position[2] },
      surface = surface,
      force = force,
      radius = c.radius,
      damage = c.damage,
      fire_damage = c.fire_damage,
      start_fires = c.start_fires,
      fx = c.fx,
      friendly_fire = c.friendly_fire,
      spare_trees = c.spare_trees
    })
  end,

  -- /c game.print(serpent.line(remote.call("tungsten_rain", "ring_status", "player", "nauvis")))
  ring_status = function(force_name, planet_name)
    init_storage()
    local by_force = storage.rings[force_name]
    local ring = by_force and by_force[planet_name]
    if not ring then return { charged = 0, loaded = 0, stations = 0, power = 0, enabled = false } end
    return {
      charged = ring.charged,
      loaded = ring.loaded or 0,
      charging_done = ring.charging_done,
      stations = ring.stations or 0,
      power = ring_power(ring, cfg()),
      enabled = ring.enabled or false,
      needles = ring.needles or 0
    }
  end,

  -- cheat/testing: instantly add needle cartridges to a ring
  -- /c remote.call("tungsten_rain", "charge_needles", "player", "nauvis", 100)
  charge_needles = function(force_name, planet_name, count)
    init_storage()
    local ring = get_ring(force_name, planet_name)
    ring.needles = (ring.needles or 0) + (count or 1)
  end,

  -- mark / clear a protected zone from script
  -- /c remote.call("tungsten_rain", "add_zone", game.player.force, game.player.surface, {left_top={x=-50,y=-50}, right_bottom={x=50,y=50}})
  add_zone = function(force, surface, area)
    init_storage()
    add_zone(force, surface, area)
  end,
  clear_zone = function(force, surface)
    init_storage()
    return clear_zone(force, surface)
  end,

  -- cheat/testing: instantly add charged rods to a ring
  -- /c remote.call("tungsten_rain", "charge_ring", "player", "nauvis", 5)
  charge_ring = function(force_name, planet_name, count)
    init_storage()
    local ring = get_ring(force_name, planet_name)
    ring.charged = ring.charged + (count or 1)
  end,

  -- cheat/testing: instantly deploy deflector stations (default: a full ring)
  -- /c remote.call("tungsten_rain", "build_ring", "player", "nauvis")
  build_ring = function(force_name, planet_name, count)
    init_storage()
    local ring = get_ring(force_name, planet_name)
    ring.stations = count or cfg().stations_full
    ring.enabled = true
  end
})
