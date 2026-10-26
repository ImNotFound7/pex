# G0: first CMOS5L GDS run through template CI

Date: 2026-10-26. Repo: https://github.com/ImNotFound7/pex (public).

## Run

- Green run: https://github.com/ImNotFound7/pex/actions/runs/40268846031 (commit `1a203bc`, "Pin CI cocotb to 2.0.1 (upstream template pin)").
- Workflows on that commit: gds run (jobs gds, precheck, gl_test, viewer) all success; `test` (run 40268846097) and `docs` (run 40268846043) success.
- Wall time of the gds run: 04:23:42Z to 05:03:34Z = 39 min 52 s. Jobs: gds 29 min 18 s (04:23:45 to 04:53:03), precheck 10 min 27 s, gl_test 42 s, viewer 16 s (the last three start after gds finishes; precheck is the tail).
- Earlier runs on the way (not green): see "Failures hit" below.

## Measurements

Artifacts downloaded with `gh run download 40268846031` into `~/.claude/jobs/22a1fc25/tmp/ci-g0` (not in repo). All metrics paths below are inside the artifact named first. The same `metrics.csv` is in two artifacts (verified identical with `diff`); the per-corner and summary tables live in the `GDS_logs` run folder.

| Fact | Value | Source (artifact / path) |
|---|---|---|
| Die size | 1289.28 x 710.64 um (`design__die__bbox 0 0 1289.28 710.64`), area 916214 um^2 = 0.916 mm^2. Confirms the spec value | `tt_submission/tt_submission/stats/metrics.csv` (also `GDS_logs/runs/wokwi/final/metrics.csv`); `DIE_AREA` in `tt_submission/src/config_merged.json` |
| Core | bbox 2.88 3.78 1286.4 706.86, area 902417 um^2 | metrics.csv: `design__core__bbox`, `design__core__area` |
| Standard-cell area (logic only) | 1166.66 um^2, 80 cells (8 sequential, 19 timing-repair buffers, 3 clock buffers) | metrics.csv: `design__instance__area__stdcell`, `design__instance__count__stdcell` |
| Utilization (logic only) | 0.129 % (`design__instance__utilization__stdcell` = 0.00129282) | metrics.csv |
| Note: `design__instance__area` | 902417 um^2 = whole core, because it includes 70995 fill cells (901251 um^2). Do not use it as design area; use `__stdcell` | metrics.csv: `design__instance__area__class:fill_cell` |
| Macros | 0 instances / 0 area | metrics.csv: `design__instance__area__macros` |
| Worst setup slack @ CLOCK_PERIOD 20 ns | +13.586 ns (corner nom_slow_1p08V_125C); typ +14.395, fast +14.841. 0 violations | metrics.csv: `timing__setup__ws` and `timing__setup__ws__corner:*`; table in `GDS_logs/runs/wokwi/55-openroad-stapostpnr/summary.rpt` |
| Worst hold slack | +0.172 ns (corner nom_fast_1p32V_m40C); typ +0.389, slow +0.778. 0 violations (17 hold buffers inserted) | metrics.csv: `timing__hold__ws`, `design__instance__count__hold_buffer`; same summary.rpt |
| Clock period | 20 ns (`CLOCK_PERIOD`) | `GDS_logs/src/config.json`, `tt_submission/src/config_merged.json` |
| Router DRC / LVS / antenna | 0 / 0 differences / 0 | metrics.csv: `route__drc_errors`, `magic__drc_error__count`, `design__lvs_*`, `antenna__violating__nets` |
| Power (nominal) | 0.0946 mW total | metrics.csv: `power__total` |
| Precheck | all 9 checks pass (pin label overlap, SG13CMOS5L DRC, zero area, KLayout checks, pin, boundary, layer, cell name, analog pin) | `precheck_reports/results.md` (+ `drc_sg13cmos5l.xml`) |
| Gate-level test | pass (2 tests) | `gatelevel_test_results/results.xml` |
| Manufacturability | see | `GDS_logs/runs/wokwi/72-misc-reportmanufacturability/manufacturability.rpt` |
| GDS / LEF / SPEF | submission files | `tt_submission/tt_submission/tt_um_imnotfound7_pex.{gds,lef,nom.spef,oas,v}`; run outputs `GDS_logs/runs/wokwi/final/{gds,lef,odb,spef,...}` |

Measurement procedure for G1: push a probe top, wait for the gds job, download the `GDS_logs` (or `tt_submission`) artifact, read `design__instance__area__stdcell` / `__macros` / `__utilization__stdcell` and `timing__{setup,hold}__ws` from `stats/metrics.csv`. Macro-bearing designs will show non-zero `design__instance__area__macros`; the per-corner timing table is in `55-openroad-stapostpnr/summary.rpt`. Placement failures (GPL-0302) would show in the gds job log.

## Failures hit and fixes (flow usage, not RTL)

1. Run 40264962020 (docs): `docs/info.md` still had the template's placeholder text, so `tt_tool.py --check-docs` reported "Missing 'How it works' / 'How to test'". Fixed by filling the sections (commit `b636f27`).
2. Run 40265829605 (viewer): GitHub Pages not enabled (HTTP 404 creating deployment). Enabled Pages with build type "workflow" via `gh api -X POST repos/ImNotFound7/pex/pages -f build_type=workflow`. No other repo settings changed. A rerun of the failed jobs then hit "Multiple artifacts named github-pages" (rerun duplicates the artifact), so a fresh run was needed.
3. Same run (gl_test): simulation passed 2/2 but the action's step `! grep failure results.xml` matches cocotb 2.1.0's `failures="0"` attribute. The upstream cmos5l template pins `cocotb==2.0.1` (pytest 8.4.2); our `test/requirements.txt` had 2.1.0. Pinned CI cocotb to 2.0.1 (commit `1a203bc`). pytest stays 9.1.1. Local venv remains cocotb 2.1.0 (2.0.1 does not build from source on Python 3.14); both pass the same tests.
4. Timing note: the first push's gds job took ~42 min wall (not a failure cause); the green run's gds job took 29 min.

## Spec errata request

(Do not edit the spec here; apply these when the spec is next revised.)

- §2 Process: "IHP SG13G2" -> **IHP SG13CMOS5L (`ihp-sg13cmos5l`): Metal1–4 + TopMetal1**.
- §2 Area: add **6x4 die = 1289.28 × 710.64 µm (0.916 mm²)** per tt-support-tools.
- §7: name the SRAM candidate `RM_IHPSG13_1P_256x16_c2_bm_bist` (0.028 mm², Metal1–4, 1-cycle read).
- §15: Claude owns the repo-root template files (`info.yaml`, `test/`, `.github/`, `docs/info.md`) and `macro/`.
- §11, §15: Codex's role (reference model, verification) moves to Claude, done through an isolated subagent with the independence boundary from Global Constraints (user decision 2026-10-26).

Die-size check: the flow reports 1289.28 x 710.64 um (metrics.csv `design__die__bbox`), so the 6x4 value is confirmed.
