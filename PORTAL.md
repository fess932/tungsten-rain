**The projectile is not accelerated by the shot. The projectile lives accelerated.**

A 100 kg tungsten rod at 0.01c (3,000 km/s) carries ~107 kilotons of kinetic energy. No warhead. No radiation. At this velocity, the explosive is velocity.

You don't build a gun. You build a storage ring: a necklace of superconducting deflector stations in low orbit, where pre-accelerated rods circulate for weeks, waiting. At four hundred times orbital speed a rod doesn't orbit at all — every station bends it toward the planet by its share of the circle, twenty times a lap, and the next station catches it. Holding the queue costs almost nothing: magnetic bending does no work. Firing is a double turn: one station overdrives its magnet from a capacitor bank and bends the rod twice as hard, and the next chord no longer clears the horizon — it ends in the ground. (Skipping a turn would do the opposite: the rod would leave on the tangent for deep space.)

**How it works**

Research Kinetic Bombardment, then deliver Deflector Stations to the hub of a platform orbiting your target planet — the ring assembles itself, one station per second. Load tungsten rods into the same hub and the ring pulls them in and spins them up to cruising speed in the background. When the ring is hot, point the Mass Driver Targeter at the ground and wait three seconds for impact.

Tungsten rods are crafted from tungsten plates, carbon, copper cable, and rocket fuel — the rod's own engine charge: it accelerates itself to 0.01c, while the ring merely holds it. Deflector stations are built from LDS, accumulators, processing units, and copper cable.

**Where are the buttons?**

Both controls live in the shortcut bar and appear only after you research Kinetic Bombardment (needs Tungsten steel + Rocket silo):

- the red button with the artillery-remote icon is the Mass Driver Targeter — select to fire a rod, alt-select to enable or pause ring assembly above the planet you're on, right-drag to set the protected zone for this planet, alt + right-drag to clear it;
- the button with the radar icon opens the Storage rings status window.

Rings start inactive: alt-select with the targeter first, or the ring won't pull anything from your hubs.

**Needles: the ring guards your base on its own**

Rods are for nests. For the biters already running at your walls the ring has a second trade: it skims the asteroid dust it sweeps up and forges needle cartridges — 10 kg bundles of a hundred steel needles, held at a lazy 15 km/s. No item, no recipe, no delivery: every station of an active ring adds 0.2 per second (a full ring, 4 per second), up to 1000 in stock.

Right-drag with the targeter to mark the protected zone — one per planet, a new one replaces the old. From then on every enemy that walks into it gets a needle: biters, spitters, nests, worms, pentapods. One cartridge sprays up to 100 of them within 32 tiles, one needle each, every needle a kill. No blast, no crater, nothing of yours is touched. Needles can't be aimed by hand — they only guard the zone. They also ignore demolishers: to a demolisher a needle is a pellet to an elephant — those take a tungsten rod. The rods stay your manual heavy artillery.

Why they don't burn up: a cartridge falls whole under the same plasma cocoon that protects a rod. At about a kilometre up, the current in its copper spiral runs out, the binding lets go, and the cocoon itself blows the bundle open. Open it in orbit instead and the needles would burn up like meteors on the way down.

**Damage**

Every strike is Relativistic: damage is subtracted straight from health (a lethal hit deletes the target), so no percentage resist, flat resist, per-hit damage cap or "overkill protection" can stop it — exactly the armour packs like Rampant fixed bolt onto every damage type. The same impact also lands impact, physical and explosion damage through the normal system, so vanilla armour and other mods still react.

It rolls out as an expanding shockwave: the core takes the penetrator hit at the moment of impact, the front rolls outward to the rim over a few seconds, and every pulse hits whatever is under it — so it grinds down even a fat regenerating biter. Add a fireball with ground fires, or turn it off, in settings.

**Clearing a map**

- Carpet bombardment — drag the targeter over a nest field and it rains one rod per nest cluster, clustered by blast radius so no rod is wasted (densest clusters first if the ring runs low).
- Auto-fire (orbital patrol) — optional hands-off mode: every interval each ring bombs the nearest enemy nests, and worms, within radar coverage on its own.
- Drop-and-go logistics — a freighter dumps its whole load of rods into the ring's buffer and leaves; the ring spins them up one at a time, no need to stay parked.

**Physics & features**

- Half-built rings already work: held speed scales with station count, damage as N squared, blast radius as the cube root — a weak ring hits softer but charges faster.
- Holding charged rods is nearly free — but every bend shoves the station outward, hundreds of times harder than gravity pulls it in. So the stations hang on a closed tether hoop spun in orbit from asteroid carbon, and the recoil of the circulating tungsten becomes hoop tension. That's what caps how many rods a ring can hold.
- No cooldown between shots by default: rate of fire is limited only by how many rods are charged and how fast the ring spins up new ones.
- Per-planet, per-force rings, with a live status window: stations, power, charged rods, spin-up countdown and needle stock, plus pause/resume.
- A visible incoming tracer, an expanding shockwave, scorchmarks and smouldering smoke — all toggleable cosmetics.

**Settings**

Adjustable at runtime: center damage, fire damage, blast radius, damage pulses and their timing, rod spin-up time, ring capacity, stations for a full ring, friendly fire, destroying trees, the auto-fire mode (interval, radar range, whether to also hit worms), and needles (stock, forge rate per station, spread radius, targets per cartridge).

**Factorio versions**

0.3.x and later are for Factorio 2.1, 0.2.10 is for Factorio 2.0. The game downloads the right one for your version.

This mod started as a petty revenge fantasy against a Rampant nest that burned down my factory. Nauvis isn't Earth — but the biters don't get to know that.

**Roadmap**

Ideas in the works — partly thanks to the orbital-mechanics homework people have been doing in the comments:

- Carpet and patrol that also catch worms and loose biter clusters, not only spawners.
- Tiers of bombardment: a crude, inaccurate "rods from god" gravity drop early, with the full storage ring as the endgame upgrade.
- Infinite accuracy research: early shots scatter by ~100 tiles, late shots land surgical.
- A real orbital power economy: separate ring-keeping vs impact-deflection hardware, capacitor banks, higher-tier power (fusion, Aquilo), and a firing cooldown that comes from the recoil kick.

Suggestions welcome. This thing is being reverse-engineered better in the comments than I engineered it.
