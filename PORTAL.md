# Tungsten Rain — Orbital Kinetic Bombardment

> The projectile is not accelerated by the shot. The projectile lives accelerated.

A 100 kg tungsten rod at 0.01c (3,000 km/s) carries ~107 kilotons of kinetic energy.
No warhead. No radiation. At this velocity, the explosive **is** velocity.

You don't build a gun. You build a **storage ring**: a necklace of superconducting
deflector stations in low orbit, where pre-accelerated rods circulate for weeks,
waiting. Firing doesn't open a breech — one station simply skips a turn, and a rod
leaves the ring on its chord. Downward.

At night you can see the ring from the surface: friction against the residual
atmosphere keeps the circulating rods glowing at 1700 K — a string of dim embers
across the sky. Those are not stars. That is the queue.

---

## How it works

Honest acceleration at the moment of firing is impossible — 4.5×10¹⁴ J in seconds
is terawatts. So the mod does what particle physicists do:

1. **Research** Kinetic Bombardment (after Tungsten steel + Rocket silo).
2. **Activate** a ring above your target planet: alt-select anywhere on it with the
   Mass Driver Targeter (a free shortcut-bar remote, like the artillery remote).
   Rings start inactive and never touch your hubs until you say so — freighters can
   load up at any planet without feeding the wrong orbit.
3. **Build the ring**: craft Deflector Stations (LDS + accumulators + processing
   units + copper cable). Each weighs exactly one rocket. Deliver them to the hub of
   a platform parked at the planet — the ring assembles itself, one station per
   second. **Twenty rockets, and the sky starts working for you.**
4. **Feed it rods**: 8 tungsten plates + 3 carbon + 2 copper cable each — an 80 kg
   tungsten core, a 15 kg ablative carbon sheath that vaporizes into a plasma cocoon
   on entry, and a 5 kg copper Faraday spiral the deflectors grip inductively.
   The ring pulls slugs from the hub and spins them up in the background.
5. **Select a target.** Three seconds later (the rod has to come around to the
   extraction window), a 67-tile circle stops existing. The impact area is charted
   automatically, so you can see what you did. A fireball and spreading fires
   finish whatever the shockwave missed.

## Physics you can feel

- **A half-built ring already fires.** Each station can only bend the rod by a fixed
  angle, so top speed grows linearly with station count: damage scales as N², blast
  radius as N^⅔, and weaker rings charge faster (energy ∝ v²). One station = a
  popgun in 60 ticks. Twenty = 107 kt.
- **Storing charged rods costs nothing.** Magnetic force is perpendicular to
  velocity — bending does no work. A ring keeps its charge forever, even if the
  delivery platform leaves orbit.
- **No cooldown between shots.** A skipped turn spends nothing. Your rate of fire is
  your stock of charged rods plus spin-up time. Save a full magazine, then drop it
  all at once.
- **Per-planet, per-force rings** with a live status window (second shortcut button):
  stations, power, charged rods, spin-up countdown, pause/resume per planet.

## A damage type that cannot be resisted

The shockwave deals **Relativistic** damage by default — this mod's own damage type.
Resistances only apply to damage types an entity lists, and nothing in any mod lists
this one: the full number always goes through. Evolution never prepared a defense
against objects arriving at a percent of lightspeed. Prefer playing by vanilla
balance rules? Switch to **explosion** (what the nuke uses) in settings — or impact,
laser, physical. A fire component rides along either way.

## Settings (all runtime)

Damage, damage type (relativistic / explosion / impact / laser / physical), fire
damage, ignite epicenter, blast radius (67 honest tiles; 300 = "relativistic
honesty" mode, mind your UPS), stations per full ring, spin-up time, ring capacity,
designation-to-impact delay, optional minimum interval between shots, friendly fire,
trees.

## Remote API

```
remote.call("tungsten_rain", "strike", position, surface, force)
remote.call("tungsten_rain", "ring_status", "player", "nauvis")
remote.call("tungsten_rain", "build_ring", "player", "nauvis")   -- cheat/testing
remote.call("tungsten_rain", "charge_ring", "player", "nauvis", 5)
```

Open for auto-targeting integrations.

## Requires

Space Age (tungsten). Built with Rampant in mind, works without it.

## Roadmap

- Tier 2 "Pillar" behind Fulgora: 8.3 t, 9 Mt, 295 tiles. Holding it on the ring
  takes 83× the centripetal force — physically impossible without superconducting
  deflectors. The progression isn't flavor; it's statics.
- Tier 3 behind Aquilo: powering spin-up from real generation (~370 MW per rod).
- Custom rod icon, entry sound (whistle + impact), shadow + dust column animation.
