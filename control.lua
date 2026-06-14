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

local function cfg()
  local s = settings.global
  return {
    damage        = s["tungsten-rain-damage"].value,
    damage_type   = s["tungsten-rain-damage-type"].value,
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
    spare_trees   = not s["tungsten-rain-destroy-trees"].value
  }
end

local function init_storage()
  storage.strikes = storage.strikes or {}
  storage.fx = storage.fx or {}     -- scheduled secondary detonations
  storage.dmg = storage.dmg or {}   -- scheduled damage pulses (spread over time)
  storage.waves = storage.waves or {} -- live continuous blast waves (render objects)
  storage.trails = storage.trails or {} -- fading tracer afterglows post-impact
  storage.next_shot = storage.next_shot or {}
  -- rings[force_name][planet_name] =
  --   { charged = N, loaded = N, charging_done = tick or nil, stations = N, enabled = bool }
  --   loaded   = rods pulled from the hub, buffered, waiting their turn to spin up
  --   charging_done = tick the one rod currently spinning up will be ready
  --   charged  = rods fully spun up and fireable
  storage.rings = storage.rings or {}
  for _, by_planet in pairs(storage.rings) do
    for _, ring in pairs(by_planet) do
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

            -- spin up one buffered rod at a time; weaker rings charge faster
            if not ring.charging_done and (ring.loaded or 0) > 0 then
              ring.loaded = ring.loaded - 1
              ring.charging_done = event.tick + spinup_ticks(ring, c)
            end
          end
        end
      end
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

  local tbl = content.add{ type = "table", column_count = 6 }
  for _, key in ipairs({ "gui-col-planet", "gui-col-stations", "gui-col-power",
                         "gui-col-rods", "gui-col-spinup" }) do
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
        if dist > d.r_inner and dist <= d.r_outer then
          local falloff = math.max(0.3, 1 - dist / d.radius)
          local dmg = d.damage * falloff
          local dtype = d.damage_type or "tungsten-kinetic"
          if dtype == "tungsten-kinetic" then
            -- Relativistic: bypass ALL resistance. Some modpacks (e.g. Rampant
            -- fixed) blanket-resist every registered damage type at
            -- data-final-fixes, custom ones included, so a novel type is not
            -- enough. At 0.01c armour is a rounding error, so we subtract straight
            -- from health (no percentage/flat resist applies) and delete outright
            -- when the hit would kill.
            if dmg >= e.health then
              pcall(function() e.die(d.force or "neutral") end)
            else
              pcall(function() e.health = e.health - dmg end)
            end
          else
            -- any other configured type plays by vanilla resistance rules
            pcall(e.damage, dmg, d.force or "neutral", dtype)
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
      damage_type = s.damage_type,
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

  local remaining = "∞"
  local power = 1 -- energy fraction of a full-power shot
  if c.require_rods then
    local planet = surface.planet
    if not planet then
      player.print({ "tungsten-rain.no-planet" })
      return
    end
    local ring = get_ring(force.name, planet.name)
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
    ring.charged = ring.charged - 1
    remaining = ring.charged
    power = ring_power(ring, c)
  end

  -- scale with ring power: damage ~ energy, radius ~ energy^(1/3)
  local radius = math.max(5, c.radius * power ^ (1 / 3))

  local area = event.area
  local pos = {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2
  }

  storage.next_shot[force.name] = now + c.cooldown
  table.insert(storage.strikes, {
    tick = now + c.delay,
    pos = pos,
    surface = surface,
    force = force,
    radius = radius,
    damage = c.damage * power,
    damage_type = c.damage_type,
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

  player.print({ "tungsten-rain.incoming", remaining, math.floor(power * 100 + 0.5) })
  pcall(function() surface.play_sound{ path = "utility/new_objective", position = pos } end)
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

script.on_event(defines.events.on_player_selected_area, on_selected)
script.on_event(defines.events.on_player_alt_selected_area, on_alt_selected)

-- ---------------------------------------------------------------------------
-- Scheduler
-- ---------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
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
      damage_type = c.damage_type,
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
      enabled = ring.enabled or false
    }
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
