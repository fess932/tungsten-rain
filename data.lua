-- Tungsten Rain: prototypes
-- 100 kg rod @ 0.01c = 4.5e14 J ~= 107 kt. Radius 67 tiles by cube-root scaling vs vanilla nuke (35 tiles ~ 15 kt).

-- Own damage type: resistances only apply to damage types an entity explicitly
-- lists, so nothing in any mod has a resist against this one. The honest option
-- for "my modpack gave nests 99.99% resists" situations.
local kinetic_damage = {
  type = "damage-type",
  name = "tungsten-kinetic"
}

local rod = {
  type = "item",
  name = "tungsten-rod",
  icon = "__space-age__/graphics/icons/tungsten-plate.png",
  icon_size = 64,
  subgroup = "ammo",
  order = "z[tungsten-rain]-a[rod]",
  stack_size = 50,
  weight = 100 * kg -- the famous 100 kg
}

-- Procedurally generated dust torus for the continuous blast wave (see tools note
-- in README). Scaled and faded at runtime via the rendering API.
local dust_ring_sprite = {
  type = "sprite",
  name = "tungsten-rain-dust-ring",
  filename = "__tungsten-rain__/graphics/dust-ring.png",
  width = 512,
  height = 512,
  priority = "high",
  flags = { "linear-minification", "linear-magnification" }
}

-- Soft gaussian glow ring: the blast front without the razor edge of draw_circle
local glow_ring_sprite = {
  type = "sprite",
  name = "tungsten-rain-glow-ring",
  filename = "__tungsten-rain__/graphics/glow-ring.png",
  width = 512,
  height = 512,
  priority = "high",
  blend_mode = "additive",
  flags = { "linear-minification", "linear-magnification" }
}

-- Tracer streak: soft-edged comet line, tail fades to nothing within the texture
local tracer_sprite = {
  type = "sprite",
  name = "tungsten-rain-tracer",
  filename = "__tungsten-rain__/graphics/tracer.png",
  width = 64,
  height = 512,
  priority = "high",
  blend_mode = "additive",
  flags = { "linear-minification", "linear-magnification" }
}

-- One station per rocket (weight = 1 t = full rocket payload). 20 rockets = one ring.
local station = {
  type = "item",
  name = "ring-deflector-station",
  icon = "__base__/graphics/icons/satellite.png",
  icon_size = 64,
  subgroup = "ammo",
  order = "z[tungsten-rain]-c[station]",
  stack_size = 10,
  weight = 1000 * kg
}

-- The targeter is a remote like the artillery one: not craftable, lives in the
-- shortcut bar, spawns into the cursor for free once the tech is researched.
local targeter = {
  type = "selection-tool",
  name = "tungsten-rain-targeter",
  icon = "__base__/graphics/icons/artillery-targeting-remote.png",
  icon_size = 64,
  flags = { "only-in-cursor", "not-stackable", "spawnable" },
  subgroup = "capsule",
  order = "z[tungsten-rain]-b[targeter]",
  stack_size = 1,
  select = {
    border_color = { r = 1, g = 0.15, b = 0.15 },
    cursor_box_type = "not-allowed",
    mode = { "nothing" }
  },
  alt_select = {
    border_color = { r = 1, g = 0.5, b = 0 },
    cursor_box_type = "not-allowed",
    mode = { "nothing" }
  }
}

-- 100 kg rod: 80 kg tungsten core, 15 kg ablative carbon sheath, 5 kg copper
-- Faraday spiral. The rocket fuel is the injector charge: the rod accelerates
-- ITSELF to 0.01c on its own propellant (the same fuel that gives a platform
-- thruster its thrust). The ring does not accelerate the rod — its deflectors
-- only catch the rocket-driven rod and hold it in a stable orbit until fired.
local rod_recipe = {
  type = "recipe",
  name = "tungsten-rod",
  enabled = false,
  energy_required = 10,
  ingredients = {
    { type = "item", name = "tungsten-plate", amount = 8 },
    { type = "item", name = "carbon",         amount = 3 },
    { type = "item", name = "copper-cable",   amount = 2 },
    { type = "item", name = "rocket-fuel",    amount = 2 }
  },
  results = { { type = "item", name = "tungsten-rod", amount = 1 } }
}

local station_recipe = {
  type = "recipe",
  name = "ring-deflector-station",
  enabled = false,
  energy_required = 30,
  ingredients = {
    { type = "item", name = "low-density-structure", amount = 10 },
    { type = "item", name = "accumulator",           amount = 5 },
    { type = "item", name = "processing-unit",       amount = 5 },
    { type = "item", name = "copper-cable",          amount = 20 }
  },
  results = { { type = "item", name = "ring-deflector-station", amount = 1 } }
}

local targeter_shortcut = {
  type = "shortcut",
  name = "tungsten-rain-targeter",
  action = "spawn-item",
  item_to_spawn = "tungsten-rain-targeter",
  technology_to_unlock = "tungsten-rain",
  unavailable_until_unlocked = true,
  style = "red",
  order = "z[tungsten-rain]",
  localised_name = { "item-name.tungsten-rain-targeter" },
  icon = "__base__/graphics/icons/artillery-targeting-remote.png",
  icon_size = 64,
  small_icon = "__base__/graphics/icons/artillery-targeting-remote.png",
  small_icon_size = 64
}

-- Status window toggle: second shortcut-bar button next to the targeter
local status_shortcut = {
  type = "shortcut",
  name = "tungsten-rain-status",
  action = "lua",
  technology_to_unlock = "tungsten-rain",
  unavailable_until_unlocked = true,
  order = "z[tungsten-rain]-b",
  localised_name = { "tungsten-rain.gui-title" },
  icon = "__base__/graphics/icons/radar.png",
  icon_size = 64,
  small_icon = "__base__/graphics/icons/radar.png",
  small_icon_size = 64
}

local tech = {
  type = "technology",
  name = "tungsten-rain",
  icon = "__base__/graphics/technology/atomic-bomb.png",
  icon_size = 256,
  prerequisites = { "tungsten-steel", "rocket-silo" },
  effects = {
    { type = "unlock-recipe", recipe = "tungsten-rod" },
    { type = "unlock-recipe", recipe = "ring-deflector-station" }
  },
  unit = {
    count = 500,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack",   1 },
      { "chemical-science-pack",   1 },
      { "metallurgic-science-pack", 1 }
    },
    time = 60
  }
}

data:extend({ kinetic_damage, dust_ring_sprite, glow_ring_sprite, tracer_sprite, rod, station, targeter, rod_recipe, station_recipe, targeter_shortcut, status_shortcut, tech })
