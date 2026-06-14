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
check(#settings_protos == 16, "16 settings defined (got " .. #settings_protos .. ")")
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
    on_gui_click = "on_gui_click"
  },
  inventory = { hub_main = 1, cargo_landing_pad_main = 2 }
}
local remote_ifaces = {}
remote = { add_interface = function(name, t) remote_ifaces[name] = t end }
rendering = { draw_circle = function() end }
-- settings mock: defaults must match settings.lua
local setting_defaults = {}
for _, p in ipairs(settings_protos) do setting_defaults[p.name] = p.default_value end
settings = {
  global = setmetatable({}, { __index = function(_, k)
    assert(setting_defaults[k] ~= nil, "control.lua reads undefined setting: " .. tostring(k))
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
game = { tick = 0, forces = { player = force }, connected_players = {},
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
check(s.damage_type == "tungsten-kinetic", "shockwave damage type defaults to relativistic")
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
