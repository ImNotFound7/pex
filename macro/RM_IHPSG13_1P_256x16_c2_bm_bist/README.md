# RM_IHPSG13_1P_256x16_c2_bm_bist

IHP 256x16 single-port SRAM macro with BIST (one-cycle read, Metal1-4 only,
236.80 x 118.78 um = 28127.10 um^2). The CMOS5L SRAM library
(`ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram`) is a symlink to these SG13G2 views.

- Repository: https://github.com/IHP-GmbH/IHP-Open-PDK, branch `dev`
- Commit: `c6562037497437ce6bc689e633e5b45abf9bbccb` (2026-10-25, "Merge pull
  request #1302 from IHP-GmbH/fix_magic_tm1_fillobs")
- Path: `ihp-sg13g2/libs.ref/sg13g2_sram/{gds,lef,lib,cdl,doc}/`
- The `sg13g2_sram` tree is identical at `2bbec755dc67ca3db0261c3d6163e15735d66710`,
  the PDK revision tt-gds-action@ihp-cmos5l installs in CI.
- Behavioural models for simulation: `test/models/` (same commit, `verilog/`).

Licensed under the Apache License 2.0 (IHP-Open-PDK).
