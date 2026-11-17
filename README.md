# Brainrot Vault Tycoon

An entry for make.fun's "Make the best AI Roblox brainrot game" bounty (roblox-brainrot-01): a 3D Roblox
game where you catch absurd meme-born brainrots in floating capsules, carry them home to your island base,
and watch them earn cash per second — while a periodic tsunami forces you to dash back to your island with
your catch.

- **The loop:** claim an open base → touch a capsule to catch the brainrot inside → carry it onto your
  island to place it on a pedestal → it pays its rate every second → spend the cash on pedestal slots,
  an income multiplier, speed boosts, or a rebirth for a permanent boost.
- **The cast:** 12 brainrots across six rarities (Common → Mythic), with four mutations (Golden, Toxic,
  Rainbow) that multiply a unit's rate up to 5x.
- **The threat:** every ~90 seconds a tsunami warning flashes, then a wall of water sweeps the arena;
  anyone caught off an island is swept home and drops their catch.
- `src/shared/` holds the catalog and economy numbers both sides read; `src/server/` owns the world, the
  state and the wave; `src/client/Game.client.luau` draws the ScreenGui HUD over the 3D world.

The place is built with Rojo from `default.project.json`:

    /home/andri/.local/bin/rojo build default.project.json --output game.rbxl

Run the entrypoint as the grader does, writing `out/` in place of `/output`:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

The rules are on the bounty's page (/bounty/roblox-brainrot-01) and in the kit's RULES.txt.
