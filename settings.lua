data:extend({
  {
    type = "double-setting",
    name = "tungsten-rain-damage",
    setting_type = "runtime-global",
    default_value = 500000,
    minimum_value = 1000,
    order = "a"
  },
  {
    type = "double-setting",
    name = "tungsten-rain-fire-damage",
    setting_type = "runtime-global",
    default_value = 150000,
    minimum_value = 0,
    order = "aa"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-start-fires",
    setting_type = "runtime-global",
    default_value = true,
    order = "ab"
  },
  {
    -- damage is dealt in this many pulses instead of one instant hit; the total
    -- damage is unchanged (each pulse deals 1/N of it). 1 = old instant behavior.
    type = "int-setting",
    name = "tungsten-rain-damage-pulses",
    setting_type = "runtime-global",
    default_value = 6,
    minimum_value = 1,
    maximum_value = 60,
    order = "ad"
  },
  {
    -- seconds between damage pulses (6 pulses x 0.5 s = a 3 s bombardment)
    type = "double-setting",
    name = "tungsten-rain-damage-interval",
    setting_type = "runtime-global",
    default_value = 0.5,
    minimum_value = 0.05,
    maximum_value = 5,
    order = "ae"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-fx",
    setting_type = "runtime-global",
    default_value = true,
    order = "ac"
  },
  {
    type = "double-setting",
    name = "tungsten-rain-radius",
    setting_type = "runtime-global",
    default_value = 67,
    minimum_value = 5,
    maximum_value = 300,
    order = "b"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-cooldown",
    setting_type = "runtime-global",
    default_value = 0,
    minimum_value = 0,
    order = "c"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-spinup",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 1,
    order = "ca"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-ring-capacity",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    order = "cb"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-ring-stations",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 1,
    order = "cc"
  },
  {
    -- needle cartridges: forged by the stations themselves, no item or recipe
    type = "int-setting",
    name = "tungsten-rain-needle-capacity",
    setting_type = "runtime-global",
    default_value = 1000,
    minimum_value = 1,
    order = "cd"
  },
  {
    type = "double-setting",
    name = "tungsten-rain-needle-rate",
    setting_type = "runtime-global",
    default_value = 0.2,
    minimum_value = 0.01,
    order = "ce"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-needle-radius",
    setting_type = "runtime-global",
    default_value = 32,
    minimum_value = 1,
    maximum_value = 200,
    order = "cf"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-needle-targets",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 1,
    order = "cg"
  },
  {
    type = "int-setting",
    name = "tungsten-rain-delay",
    setting_type = "runtime-global",
    default_value = 180,
    minimum_value = 0,
    order = "d"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-require-rods",
    setting_type = "runtime-global",
    default_value = true,
    order = "e"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-friendly-fire",
    setting_type = "runtime-global",
    default_value = false,
    order = "f"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-destroy-trees",
    setting_type = "runtime-global",
    default_value = true,
    order = "g"
  },
  {
    -- automatic bombardment of enemy nests/worms within radar range
    type = "bool-setting",
    name = "tungsten-rain-auto-fire",
    setting_type = "runtime-global",
    default_value = false,
    order = "h"
  },
  {
    type = "double-setting",
    name = "tungsten-rain-auto-interval",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 10,
    maximum_value = 600,
    order = "ha"
  },
  {
    -- coverage radius around each radar; 448 = vanilla radar far scan (14 chunks)
    type = "int-setting",
    name = "tungsten-rain-auto-range",
    setting_type = "runtime-global",
    default_value = 448,
    minimum_value = 32,
    maximum_value = 4096,
    order = "hb"
  },
  {
    type = "bool-setting",
    name = "tungsten-rain-auto-worms",
    setting_type = "runtime-global",
    default_value = true,
    order = "hc"
  }
})
