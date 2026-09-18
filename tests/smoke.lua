-- Smoke test: execute mod files under mocked Factorio environment.
-- Run from mod root: lua tests/smoke.lua
-- Validates top-level execution and basic prototype shape, not game behavior.

local failures = 0
local function check(cond, msg)
  if cond then
    print("  OK   " .. msg)
  else
    failures = failures + 1
    print("  FAIL " .. msg)
  end
end

-- -------------------------------------------------- data stage mocks
kg = 1000 -- core lualib global in Factorio 2.0 data stage

local extended = {}
data = {
  extend = function(_, protos)
    for _, p in ipairs(protos) do
      assert(type(p) == "table", "prototype is not a table")
      assert(p.type, "prototype missing type")
      assert(p.name, "prototype missing name")
      extended[#extended + 1] = p
    end
  end
}

print("settings.lua:")
local settings_protos = {}
do
  local saved = data
  data = { extend = function(_, protos)
    for _, p in ipairs(protos) do settings_protos[#settings_protos + 1] = p end
  end }
  dofile("settings.lua")
  data = saved
end
check(#settings_protos == 19, "19 settings defined (got " .. #settings_protos .. ")")
for _, p in ipairs(settings_protos) do
  check(p.setting_type == "runtime-global", p.name .. " is runtime-global")
  check(p.default_value ~= nil, p.name .. " has default")
end

print("data.lua:")
dofile("data.lua")
check(#extended == 12, "12 prototypes defined (got " .. #extended .. ")")
local by_key = {} -- items and recipes share names, so key by type/name
for _, p in ipairs(extended) do by_key[p.type .. "/" .. p.name] = p end

check(by_key["damage-type/tungsten-kinetic"] ~= nil, "own kinetic damage type defined")

local dust = by_key["sprite/tungsten-rain-dust-ring"]
check(dust ~= nil and dust.filename == "__tungsten-rain__/graphics/dust-ring.png",
  "dust ring sprite defined with mod-local path")
local dust_file = io.open("graphics/dust-ring.png", "rb")
check(dust_file ~= nil, "graphics/dust-ring.png exists on disk")
if dust_file then dust_file:close() end

local glow = by_key["sprite/tungsten-rain-glow-ring"]
check(glow ~= nil and glow.blend_mode == "additive", "glow ring sprite defined (additive)")
local glow_file = io.open("graphics/glow-ring.png", "rb")
check(glow_file ~= nil, "graphics/glow-ring.png exists on disk")
if glow_file then glow_file:close() end

local tracer_sprite = by_key["sprite/tungsten-rain-tracer"]
check(tracer_sprite ~= nil and tracer_sprite.blend_mode == "additive",
  "tracer streak sprite defined (additive)")
local tracer_file = io.open("graphics/tracer.png", "rb")
check(tracer_file ~= nil, "graphics/tracer.png exists on disk")
if tracer_file then tracer_file:close() end

local rod = by_key["item/tungsten-rod"]
check(rod ~= nil, "tungsten-rod item defined")
check(rod and rod.weight == 100000, "rod weight = 100 kg (100*kg = " .. tostring(rod and rod.weight) .. ")")

local station = by_key["item/ring-deflector-station"]
check(station ~= nil, "deflector station item defined")
check(station and station.weight == 1000000, "station weight = 1 t = one rocket (got " .. tostring(station and station.weight) .. ")")

local targeter = by_key["selection-tool/tungsten-rain-targeter"]
check(targeter ~= nil, "targeter selection-tool defined")
check(targeter and targeter.select and targeter.select.mode and targeter.alt_select and targeter.alt_select.mode,
  "targeter has 2.0-format select/alt_select with mode")
local tflags = {}
for _, f in ipairs(targeter and targeter.flags or {}) do tflags[f] = true end
check(tflags["only-in-cursor"] and tflags["spawnable"], "targeter is a cursor-only spawnable remote")

local shortcut = by_key["shortcut/tungsten-rain-targeter"]
check(shortcut ~= nil, "targeter shortcut defined")
check(shortcut and shortcut.action == "spawn-item"
  and shortcut.item_to_spawn == "tungsten-rain-targeter"
  and shortcut.technology_to_unlock == "tungsten-rain",
  "shortcut spawns the targeter, unlocked by the technology")

local status_sc = by_key["shortcut/tungsten-rain-status"]
check(status_sc ~= nil and status_sc.action == "lua"
  and status_sc.technology_to_unlock == "tungsten-rain",
  "status window shortcut defined (lua action, tech-locked)")

local tech = by_key["technology/tungsten-rain"]
check(tech ~= nil, "technology defined")
check(tech and #tech.effects == 2, "technology unlocks 2 recipes (targeter is a shortcut, not crafted)")

-- recipe ingredients reference only known-existing items (base/space-age)
local known = {
  ["tungsten-plate"] = true, ["carbon"] = true, ["copper-cable"] = true,
  ["low-density-structure"] = true, ["accumulator"] = true, ["processing-unit"] = true,
  ["advanced-circuit"] = true, ["radar"] = true, ["rocket-fuel"] = true
}
for _, p in ipairs(extended) do
  if p.type == "recipe" then
    for _, ing in ipairs(p.ingredients) do
      check(known[ing.name], "recipe " .. p.name .. " ingredient exists: " .. ing.name)
    end
  end
end

-- -------------------------------------------------- runtime stage mocks
print("control.lua:")
local handlers = { events = {}, nth = {} }
script = {
  on_init = function(f) handlers.on_init = f end,
  on_configuration_changed = function(f) handlers.on_config = f end,
  on_event = function(ev, f) handlers.events[ev] = f end,
  on_nth_tick = function(n, f) handlers.nth[n] = f end
}
defines = {
  events = {
    on_player_selected_area = "on_player_selected_area",
    on_player_alt_selected_area = "on_player_alt_selected_area",
    on_tick = "on_tick",
    on_lua_shortcut = "on_lua_shortcut",
    on_gui_click = "on_gui_click",
    on_built_entity = "on_built_entity",
    on_robot_built_entity = "on_robot_built_entity",
    script_raised_built = "script_raised_built",
    script_raised_revive = "script_raised_revive",
    on_entity_cloned = "on_entity_cloned"
  },
  inventory = { hub_main = 1, cargo_landing_pad_main = 2 }
}
local remote_ifaces = {}
remote = { add_interface = function(name, t) remote_ifaces[name] = t end }
rendering = { draw_circle = function() end }
-- settings mock: defaults must match settings.lua
local setting_defaults = {}
for _, p in ipairs(settings_protos) do setting_defaults[p.name] = p.default_value end
local setting_overrides = {}
settings = {
  global = setmetatable({}, { __index = function(_, k)
    assert(setting_defaults[k] ~= nil, "control.lua reads undefined setting: " .. tostring(k))
    if setting_overrides[k] ~= nil then return { value = setting_overrides[k] } end
    return { value = setting_defaults[k] }
  end })
}
storage = {}

-- a force with one platform parked at Vulcanus: 3 rods + 2 deflector stations in the hub
local hub = { ["tungsten-rod"] = 3, ["ring-deflector-station"] = 2 }
local hub_inv = {
  get_item_count = function(name) return hub[name] or 0 end,
  remove = function(spec) hub[spec.name] = (hub[spec.name] or 0) - spec.count end
}
local platform = {
  space_location = { name = "vulcanus" },
  hub = { valid = true, get_inventory = function() return hub_inv end }
}
local force = { name = "player", platforms = { platform }, print = function() end }
local fake_player = { print = function() end, force = force, gui = { screen = {} } }
game = { tick = 0, forces = { player = force }, connected_players = {}, surfaces = {},
         get_player = function() return fake_player end }

dofile("control.lua")

check(handlers.on_init ~= nil, "on_init registered")
check(handlers.on_config ~= nil, "on_configuration_changed registered")
check(handlers.events["on_player_selected_area"] ~= nil, "on_player_selected_area registered")
check(handlers.events["on_player_alt_selected_area"] ~= nil, "on_player_alt_selected_area registered")
check(handlers.events["on_tick"] ~= nil, "on_tick registered")
check(handlers.nth[60] ~= nil, "on_nth_tick(60) ring charger registered")
check(handlers.events["on_lua_shortcut"] ~= nil, "on_lua_shortcut registered (status window)")
check(handlers.events["on_gui_click"] ~= nil, "on_gui_click registered (status window)")
local iface = remote_ifaces["tungsten_rain"]
check(iface and iface.strike and iface.ring_status and iface.charge_ring and iface.build_ring,
  "remote interface: strike / ring_status / charge_ring / build_ring registered")

handlers.on_init()
check(type(storage.strikes) == "table" and type(storage.next_shot) == "table"
  and type(storage.rings) == "table" and type(storage.fx) == "table"
  and type(storage.waves) == "table" and type(storage.trails) == "table",
  "on_init creates storage tables (incl. rings, fx, waves, trails)")

-- on_tick with no strikes must be a cheap no-op
handlers.events["on_tick"]({ tick = 1 })
check(true, "on_tick no-op with empty strike queue")

-- remote strike queues an entry; reading all settings along the way
iface.strike({ x = 10, y = 20 }, { valid = true }, nil)
check(#storage.strikes == 1, "remote strike queues a strike")
local s = storage.strikes[1]
check(s.pos.x == 10 and s.pos.y == 20, "strike position recorded")
check(s.radius == 67 and s.damage == 500000, "strike picks up settings (radius/damage)")
check(s.fire_damage == 150000 and s.start_fires == true, "strike picks up fire settings")
check(s.fx == true, "strike carries the visual shockwave flag")

-- ring assembly + charge cycle. Settings: 20 stations full, spinup 60 s = 3600 ticks.
-- Spin-up is linear in held speed: ticks = max(60, floor(3600 * stations/20)).
-- 1 station -> 180 ticks, 2 -> 360, 20 (full) -> 3600.
print("ring:")
local nth = handlers.nth[60]

-- rings start inactive: a freighter can load up without feeding this planet's ring
nth({ tick = 0 })
local st = iface.ring_status("player", "vulcanus")
check(st.enabled == false, "ring starts disabled")
check(st.stations == 0 and hub["ring-deflector-station"] == 2 and hub["tungsten-rod"] == 3,
  "inactive ring pulls nothing from the hub")

-- alt-select with the targeter activates assembly
local vulcanus_surface = { valid = true, planet = { name = "vulcanus" } }
local function alt_toggle()
  handlers.events["on_player_alt_selected_area"]({
    item = "tungsten-rain-targeter", player_index = 1, surface = vulcanus_surface
  })
end
alt_toggle()
st = iface.ring_status("player", "vulcanus")
check(st.enabled == true, "alt-select enables ring assembly")

nth({ tick = 0 })
st = iface.ring_status("player", "vulcanus")
check(hub["ring-deflector-station"] == 1, "station #1 deployed from hub")
check(st.stations == 1, "ring reports 1 station")
check(math.abs(st.power - 0.0025) < 1e-9, "power = (1/20)^2 = 0.0025")
check(hub["tungsten-rod"] == 0, "all 3 rods pulled from the hub into the buffer at once")
check(st.charged == 0 and st.charging_done == 180, "1-station spin-up = floor(3600/20) = 180 ticks")
check(st.loaded == 2, "2 rods wait in the buffer while 1 spins up")

-- rod #1 done, station #2 deployed, rod #2 starts spinning up (2 stations = 360 ticks)
nth({ tick = 180 })
st = iface.ring_status("player", "vulcanus")
check(st.charged == 1, "first rod charged after its spin-up")
check(st.stations == 2 and hub["ring-deflector-station"] == 0, "station #2 deployed, hub out of stations")
check(st.loaded == 1, "rod #2 pulled from buffer into spin-up, 1 still waiting")
check(st.charging_done == 540, "2-station spin-up = 180 + 360")

-- drain rods completely (rod #2 done at 540, rod #3 at 540 + 360 = 900)
nth({ tick = 540 })
nth({ tick = 900 })
st = iface.ring_status("player", "vulcanus")
check(st.charged == 3 and hub["tungsten-rod"] == 0 and st.charging_done == nil,
  "all 3 rods charged, hub empty, ring idle")

-- empty hub: nth tick is a no-op
nth({ tick = 960 })
st = iface.ring_status("player", "vulcanus")
check(st.charged == 3 and st.stations == 2, "no phantom rods or stations from an empty hub")

-- pausing stops all pulling, charge is kept
alt_toggle()
st = iface.ring_status("player", "vulcanus")
check(st.enabled == false, "alt-select again pauses the ring")
hub["ring-deflector-station"] = 1
nth({ tick = 1020 })
st = iface.ring_status("player", "vulcanus")
check(st.stations == 2 and hub["ring-deflector-station"] == 1 and st.charged == 3,
  "paused ring pulls nothing, keeps its charge")

-- resume: assembly continues
alt_toggle()
nth({ tick = 1080 })
st = iface.ring_status("player", "vulcanus")
check(st.stations == 3 and hub["ring-deflector-station"] == 0, "resumed ring continues assembly")

-- cheat: complete the ring; full power, and spin-up takes the full configured time
iface.build_ring("player", "vulcanus")
st = iface.ring_status("player", "vulcanus")
check(st.stations == 20 and st.power == 1 and st.enabled == true,
  "build_ring completes and activates the ring (power 100%)")
hub["tungsten-rod"] = 1
nth({ tick = 1140 })
st = iface.ring_status("player", "vulcanus")
check(st.charging_done == 1140 + 3600, "full ring spin-up takes the full 3600 ticks")

-- cheat charge for testing
iface.charge_ring("player", "vulcanus", 5)
st = iface.ring_status("player", "vulcanus")
check(st.charged == 8, "charge_ring adds charged rods")

-- unknown ring reports empty
st = iface.ring_status("enemy", "nauvis")
check(st.charged == 0 and st.stations == 0 and st.power == 0, "unknown ring reports empty")

-- GUI: pause button click toggles the ring (frame closed -> rebuild is a safe no-op)
handlers.events["on_gui_click"]({
  player_index = 1,
  element = { valid = true, name = "tungsten-rain-toggle/vulcanus" }
})
st = iface.ring_status("player", "vulcanus")
check(st.enabled == false, "GUI pause button toggles the ring")
handlers.events["on_gui_click"]({
  player_index = 1,
  element = { valid = true, name = "tungsten-rain-toggle/vulcanus" }
})
st = iface.ring_status("player", "vulcanus")
check(st.enabled == true, "GUI resume button toggles it back")

-- auto-fire: a sweep spread over the interval. Radars come from the build-event
-- registry, coverage is searched once in small pieces a tick at a time, only
-- enemy forces are hit, nests are clustered by blast radius, nearest fires first.
print("auto-fire:")
setting_overrides["tungsten-rain-auto-fire"] = true
check(handlers.events["on_built_entity"] and handlers.events["on_robot_built_entity"]
  and handlers.events["script_raised_built"] and handlers.events["on_entity_cloned"],
  "radar registry listens to build / robot / script / clone events")
local enemy = { name = "enemy", valid = true }
force.valid = true
force.players = {}
force.is_enemy = function(f) return f == enemy end
game.forces.enemy = enemy
vulcanus_surface.index = 3
local function radar(id, x, y)
  return { valid = true, type = "radar", unit_number = id, surface = vulcanus_surface,
           force = force, position = { x = x, y = y } }
end
handlers.events["on_built_entity"]({ entity = radar(1, 0, 0) })
handlers.events["on_robot_built_entity"]({ entity = radar(2, 10, 0) })
handlers.events["script_raised_built"]({ entity = radar(3, 5, 5) })
local dead = radar(4, 9000, 9000)
handlers.events["on_built_entity"]({ entity = dead })
dead.valid = false -- destroyed since: must be pruned, not searched around

local nests = { { x = 100, y = 100 }, { x = 110, y = 100 }, { x = 300, y = -200 },
                { x = 5000, y = 5000 } } -- the last one is far outside radar range
local area_calls, area_tiles, seen_force, calls_this_tick, max_per_tick = 0, 0, nil, 0, 0
local found_order = {}
vulcanus_surface.find_entities_filtered = function(f)
  assert(f.type ~= "radar", "auto-fire must not search the planet for radars")
  area_calls = area_calls + 1
  calls_this_tick = calls_this_tick + 1
  area_tiles = area_tiles + (f.area[2][1] - f.area[1][1]) * (f.area[2][2] - f.area[1][2])
  seen_force = f.force
  local out = {}
  for _, n in ipairs(nests) do
    if n.x >= f.area[1][1] and n.x < f.area[2][1] and n.y >= f.area[1][2] and n.y < f.area[2][2] then
      out[#out + 1] = { valid = true, position = n }
      found_order[#found_order + 1] = n
    end
  end
  return out
end
game.planets = { vulcanus = { surface = vulcanus_surface } }
game.surfaces = { vulcanus_surface }
local on_tick = handlers.events["on_tick"]
-- start a sweep at t0 and tick it until it completes; returns ticks taken
local function run_sweep(t0)
  storage.next_auto = 0
  nth({ tick = t0 })
  local t = t0
  while storage.auto_sweep and t < t0 + 10000 do
    calls_this_tick = 0
    on_tick({ tick = t })
    if calls_this_tick > max_per_tick then max_per_tick = calls_this_tick end
    t = t + 1
  end
  return t - t0
end

-- settle any pending spin-up first so only auto-fire changes the charge
storage.next_auto = math.huge
nth({ tick = 99000 })
storage.strikes = {}
local before = iface.ring_status("player", "vulcanus").charged
local took = run_sweep(100000)
-- three overlapping radars (range 448) cover chunks -14..14 on both axes: one
-- 29x29-chunk rectangle, searched once, in 4x4-chunk pieces
check(area_tiles == 29 * 29 * 32 * 32,
  "overlapping radar coverage is searched exactly once (" .. area_tiles .. " tiles)")
check(area_calls == 64, "coverage cut into 64 pieces of <= 4x4 chunks (got " .. area_calls .. ")")
check(max_per_tick <= 1, "at most one piece searched per tick (got " .. max_per_tick .. ")")
check(took <= 600, "sweep finishes within the 10 s interval (" .. took .. " ticks)")
check(type(seen_force) == "table" and seen_force[1] == enemy and #seen_force == 1,
  "nest search is filtered to enemy forces engine-side")
check(#storage.strikes == 2, "two clusters in range -> two rods, out-of-range nest ignored (got "
  .. #storage.strikes .. ")")
local first = storage.strikes[1] and storage.strikes[1].pos
check(first and math.abs(first.x - 105) < 1e-9 and math.abs(first.y - 100) < 1e-9,
  "nearest cluster fires first, at the centroid of its two nests")
check(iface.ring_status("player", "vulcanus").charged == before - 2, "auto-fire spends charged rods")
check(storage.radars[3][4] == nil, "destroyed radar pruned from the registry")

-- a paused ring is not swept at all
area_calls = 0
handlers.events["on_gui_click"]({ player_index = 1,
  element = { valid = true, name = "tungsten-rain-toggle/vulcanus" } })
run_sweep(200000)
check(area_calls == 0 and storage.auto_sweep == nil, "paused ring costs no search")
handlers.events["on_gui_click"]({ player_index = 1,
  element = { valid = true, name = "tungsten-rain-toggle/vulcanus" } })

-- turning auto-fire off mid-sweep abandons it
storage.next_auto = 0
nth({ tick = 250000 })
check(storage.auto_sweep ~= nil, "sweep in progress")
setting_overrides["tungsten-rain-auto-fire"] = false
on_tick({ tick = 250001 })
check(storage.auto_sweep == nil, "disabling auto-fire drops the sweep in progress")
setting_overrides["tungsten-rain-auto-fire"] = true

-- clustering spread over ticks gives the same strikes as the all-pairs greedy
local function reference_clusters(targets, radius)
  local alive, r2, pts = {}, radius * radius, {}
  for i = 1, #targets do alive[i] = true end
  for si, seed in ipairs(targets) do
    if alive[si] then
      local cx, cy, n = 0, 0, 0
      for i, t in ipairs(targets) do
        local dx, dy = t.x - seed.x, t.y - seed.y
        if alive[i] and dx * dx + dy * dy <= r2 then cx = cx + t.x; cy = cy + t.y; n = n + 1 end
      end
      local sx, sy = cx / n, cy / n
      for i, t in ipairs(targets) do
        local dx, dy = t.x - sx, t.y - sy
        if alive[i] and dx * dx + dy * dy <= r2 then alive[i] = false end
      end
      alive[si] = false
      pts[#pts + 1] = { x = sx, y = sy }
    end
  end
  return pts
end
math.randomseed(42)
nests = {}
for i = 1, 2000 do nests[i] = { x = math.random(-440, 440) + 0.5, y = math.random(-440, 440) + 0.5 } end
iface.charge_ring("player", "vulcanus", 100000)
storage.strikes = {}
found_order = {}
max_per_tick = 0
took = run_sweep(300000)
local want = reference_clusters(found_order, 67)
local function key(p) return string.format("%.6f:%.6f", p.x, p.y) end
local got_set = {}
for _, st in ipairs(storage.strikes) do got_set[key(st.pos)] = true end
local same = #storage.strikes == #want and #found_order == 2000
for _, p in ipairs(want) do if not got_set[key(p)] then same = false end end
check(same, "sliced clustering matches the all-pairs reference on 2000 random nests ("
  .. #storage.strikes .. " vs " .. #want .. " strikes)")
check(took <= 600, "2000-nest sweep still finishes within the interval (" .. took .. " ticks)")
setting_overrides["tungsten-rain-auto-fire"] = nil

-- locale key sanity: every key referenced in control.lua exists in both locales
print("locale:")
local function locale_keys(path)
  local keys, section = {}, nil
  for line in io.lines(path) do
    local sec = line:match("^%[(.-)%]")
    if sec then section = sec
    else
      local k = line:match("^([%w%-]+)=")
      if k and section then keys[section .. "." .. k] = true end
    end
  end
  return keys
end
local used = { "tungsten-rain.no-rods", "tungsten-rain.ring-charging", "tungsten-rain.no-planet",
               "tungsten-rain.ring-not-built", "tungsten-rain.ring-station-installed",
               "tungsten-rain.ring-complete", "tungsten-rain.ring-disabled",
               "tungsten-rain.ring-enabled", "tungsten-rain.ring-paused",
               "tungsten-rain.cooldown", "tungsten-rain.incoming",
               "tungsten-rain.impact", "tungsten-rain.no-platform-strikes",
               "tungsten-rain.gui-title", "tungsten-rain.gui-col-planet",
               "tungsten-rain.gui-col-stations", "tungsten-rain.gui-col-power",
               "tungsten-rain.gui-col-rods", "tungsten-rain.gui-col-spinup",
               "tungsten-rain.gui-spinup-remaining", "tungsten-rain.gui-btn-pause",
               "tungsten-rain.gui-btn-resume", "tungsten-rain.gui-no-rings" }
for _, loc in ipairs({ "locale/en/locale.cfg", "locale/ru/locale.cfg" }) do
  local keys = locale_keys(loc)
  for _, k in ipairs(used) do
    check(keys[k:gsub("%.", ".", 1)], loc .. " has " .. k)
  end
end

print(("-"):rep(40))
if failures == 0 then
  print("ALL CHECKS PASSED")
else
  print(failures .. " CHECK(S) FAILED")
  os.exit(1)
end
