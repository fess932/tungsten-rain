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
    type = "string-setting",
    name = "tungsten-rain-damage-type",
    setting_type = "runtime-global",
    default_value = "tungsten-kinetic",
    allowed_values = { "tungsten-kinetic", "explosion", "impact", "laser", "physical" },
    order = "a2"
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
  }
})
