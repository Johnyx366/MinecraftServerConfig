# Initial world reset checkpoint

This records the safe reset of `chocolate-edition` to the pinned seed in its manifest.

| Purpose | Restic snapshot | Verification |
| --- | --- | --- |
| World before reset | `54f48efb` | `restic check --read-data-subset=1/20` passed |
| Fresh seeded world | `0ef18554` | `restic check --read-data-subset=1/20` passed |

The pre-reset runtime world was moved, not deleted, to `world.before-reset-20260912T214448Z`. The server starts successfully with the new world. The restic snapshots were made while the server used the consistent RCON save sequence.
