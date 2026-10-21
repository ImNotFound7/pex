# PEX: final design specification

Date: 2026-10-21 · Status: **Approved by the user as the converged plan. Normative for RTL, the reference model, and firmware until superseded.** Encodings (ISA bit layout, host command bytes) are frozen at gate G2 and will be added under `spec/`.

**Revision 2 (2026-10-21, user-approved):** the goal changed from "win the tapeout slot" to "build something Jane Street's hardware engineers would actually use, and get noticed for it." Added: sim+bench as the core value (§1, §10a), the OCaml host library and experiment format with expect-test output (§10a, §12), the reusable Hardcaml testbench component (§10a), the simulation-replay second act (§10), code quality and docs as first-class (§14), and building in public (§13a). Breadth stays in scope. Cuts happen later at the gates, only if time runs out (§13). Pending Codex review.

**Supersedes (kept as historical inputs, not edited):**

- [`plans.md`](../../../plans.md): Codex proposal
- [`claude-plan.md`](../../../claude-plan.md): Claude proposal
- [`plan-comparison.md`](../../../plan-comparison.md): Codex's comparison and corrections A–K

Where this document and those files disagree, this document wins.

Conventions: **MUST** = normative. *Provisional* = a value fixed at the named gate by measurement. *Judgment* = an estimate, not evidence.

---

## 1. Goal, identity, claims

**Goal.** Build an open-source protocol emulator that **Jane Street's hardware engineers would actually use**, built well enough that its authors get noticed. The yardstick is "would a Hardcaml engineer reach for this on a normal workday?", not "does it make a good demo?" Submitting a working, verified design for IHP 130 nm CMOS5L in a 6×4 Tiny Tapeout allocation by **Jan 11, 2027** (official deadline Jan 18) is a required milestone on the way, not the end goal.

**Core value: the same protocol program runs in your Hardcaml simulation and on the bench.** PEX is itself written in Hardcaml, so:

- a Hardcaml user can instantiate it in a cyclesim testbench as a programmable protocol peer next to their own design;
- the same firmware and experiment can later run against their real board through the chip;
- a failure the chip finds on the bench can be replayed in simulation with the same stimulus.

We cannot know what Jane Street uses internally (they may already have protocol testbench components). Early feedback (§13a) is the only real evidence available.

**Identity.** PEX is a two-context protocol processor in which **firmware decides what happens on a pin, and hardware decides when.** Pin changes are scheduled as timed actions with deadlines relative to the previous deadline or to a timestamped input event. They are never tied to instruction retirement. A missed deadline is a reported fault, never a silent late edge.

**Flagship demonstration, in two acts.**

1. An I2C *timing-tolerance map*. PEX emulates an I2C target and sweeps its timing cycle by cycle against a real, unmodified controller. It classifies every point (pass, the various failure kinds, emulator-invalid) and shows the specification limits on the same map.
2. **Bench → simulation.** A failure found on the bench against a controller whose RTL we have is reproduced by running the identical experiment in Hardcaml simulation, then fixed, with the fix shown passing on both (§10).

**Claims rules (MUST):**

- Do not claim invention of timed ports, event-relative output, fixed-slot multithreading, shmoo plotting, or test-case reduction. XMOS timed ports are the closest prior art and are compared explicitly.
- Do not claim PIO cannot do something unless an equal-workload PIO implementation shows it.
- Never compare at mismatched clocks. Every published rate states its clock, cycle budget, and measured result.
- State every proof with its assumptions and its bounded or unbounded status.
- The plausible contribution is the *demonstrated combination*: a small open ASIC with explicit deadline-failure reporting, a scoped proof that the contexts are isolated, firmware-defined protocols, and a reproducible measurement workflow.

---

## 2. Constraints

| Item | Value |
|---|---|
| Process / flow | IHP SG13G2 via TT `cmos5l` template (pin exact revision at G1) |
| Area | 6×4 tiles; do not assume 8×4 |
| I/O | `ui_in[7:0]`, `uo_out[7:0]`, `uio[7:0]` + `uio_oe`, `clk`, `rst_n`, `ena` |
| Clock | Single domain from the wrapper. Target 50 MHz, floor 25 MHz, *provisional*, fixed at G3 by STA |
| Human time | ~191 h to Jan 18 (~176 h to Jan 11) at 15 h/week |
| Language | Hardcaml (OCaml) → Verilog into the template |

---

## 3. Architecture

```
 physical inputs ──▶ 2-FF sync ──▶ per-context input map (8 logical) ──▶ event units (every clk)
 uio_in[7:0], ui_in[7:3]                                                        │ CAPT
                                                                                 ▼
 ┌──────────────┐ 1 read/clk ┌───────────────────────────┐    ┌────────────────────────────┐
 │ instr memory │──────────▶ │ barrel core, 2 contexts   │──▶ │ per-context action record   │
 │ single-port  │            │ S=2: fetch one ctx while  │    │ (1 entry) vs NOW (32-bit)   │
 └──────▲───────┘            │ executing the other       │    └─────────────┬──────────────┘
        │ halted only        └──────┬─────────────▲──────┘                  │ commit
 ┌──────┴─────────────┐             │             │                         ▼
 │ host SPI (oversamp.│◀── per-ctx FIFOs, params, trace, status ──┘   per-pin ownership,
 │ in core clock)     │                                               logical→physical map,
 └────────────────────┘                                               push-pull / open-drain
```

### 3.1 Execution model

- `S` = clocks per context slot, a generator parameter. **Baseline S=2. Fallback S=4** if G1/G3 timing closure needs it. Under S=4 the execute→next-fetch path may be constrained as a 2-cycle multicycle path. Changing S changes no ISA or contract rule except slot timing.
- **S=2:** ctx0 fetches in even cycles and executes in the following odd cycle; ctx1 fetches in odd cycles and executes in the following even cycle. Instruction memory is read every cycle.
- **S=4:** ctx0 fetches at 4m and executes at 4m+1; ctx1 fetches at 4m+2 and executes at 4m+3.
- A context has at most one instruction in flight. Its next-PC is resolved before its next fetch. There is no forwarding, no inter-context stall, and no inter-context hazard.
- Each executed instruction occupies exactly one slot. A **blocked** instruction (`AT` with record full, `WAIT`, `PUSH` full, `PULL` empty) re-executes in each of its own slots with no side effects until it can complete. It never affects the other context's slots.
- Architectural effects of an instruction take place at the end of its execute cycle.

### 3.2 Per-context state (*provisional* widths, frozen at G2)

PC (8) · r0–r3 (4×8) · SR shift register (8) + bit counter · flags Z, C · 1-deep link register (8) · REF (32) · staging register {out 8, oe 8, mask 8, sample 1} · action record {D 32, out 8, oe 8, mask 8, sample 1, valid} · SAMPLE register (8) · event config + CAPT (32) + captured/overrun flags · parameter registers P0–P3 (4×16) · TX and RX FIFOs (4×8 each, *provisional*) · trace FIFO (8×32, *provisional*) · fault code (sticky) · start address (8).

**Isolation boundary:** the two contexts share **no mutable architectural state**. Everything above is per-context. Shared resources are the instruction memory (read-only while running), `NOW`, the physical input synchronizers (read-only), and the output pin cells, which are partitioned by ownership.

---

## 4. Timing contract (normative)

### 4.1 Time

- `NOW` is a 32-bit counter. During cycle *k* of a run, `NOW = k mod 2^32`. A host `START` makes the first cycle of the run cycle 0.
- Modular order: "x before y" means `(y − x) mod 2^32 ∈ [1, 2^31)`. All deadline comparisons use this. The **horizon** is 2^31 − 1 cycles (~42.9 s at 50 MHz).

### 4.2 Timed actions: stage, accept, commit

1. **Stage.** `STG`, `OUTB` and similar instructions write the context's staging register. Staging has no timing effect, and staging while an action is pending is allowed.
2. **Accept.** `AT n` (offset from an immediate or a parameter register) executes in cycle *k*:
   - If the action record is valid at the start of cycle *k*, the instruction **blocks** (§3.1). REF is not touched.
   - Otherwise compute `D = (REF + n) mod 2^32` and `δ = (D − k) mod 2^32`.
   - If `δ < L_min` or `δ ≥ 2^31`, raise **LATE** (§4.6). The record stays empty and REF is unchanged.
   - Otherwise snapshot staging into the record, set `D`, set valid, and set `REF ← D`. **REF is updated exactly once, on acceptance.**
3. **Commit.** During cycle *D* the record's comparator matches. On the rising edge that ends cycle *D*:
   - the output registers load the record's out/OE values, filtered by mask and ownership (§4.5);
   - if the sample flag is set, `SAMPLE` loads the 8 synchronized logical inputs as seen during cycle *D*;
   - the record becomes empty.
4. **Visibility.** The new pin value is present during cycle *D+1*, after clock-to-output and pad delay. Traces record *D*.
5. **No same-cycle bypass.** An `AT` executing in cycle *D* sees a valid record and blocks. The earliest re-accept is cycle *D+1*.
6. **Consequence.** For one context with the next `AT` already blocked, the minimum spacing between consecutive commits is `L_min + 1` to `L_min + S`, depending on slot phase. `L_min` is one published constant: *provisional* 2, fixed at G2.
7. Both contexts may commit in the same cycle to disjoint pins (ownership guarantees disjointness).

### 4.3 Events

- Each physical input passes through a 2-FF synchronizer. "Synchronized value in cycle *k*" means the second flop's output during cycle *k*.
- Each context maps logical inputs 0–7 to physical inputs at configuration time.
- `ARM cond` sets the context's condition: logical pin + {rise, fall, either, high, low}. It clears `captured` and takes effect from the cycle after `ARM` executes. The condition **stays armed** until the next `ARM`; `ARM none` disarms.
- **Every cycle**, independent of slots: if armed and not captured and the condition holds (for edges, the synchronized value changed between *k−1* and *k*), set `CAPT ← k` and `captured ← 1`. A level condition that already holds is captured in the first evaluated cycle. Another match while `captured = 1` sets sticky `EVENT_OVERRUN`.
- **Nominal observation offset** (documented and FPGA-measured, not guaranteed): a clean pad transition appears in `CAPT` 2–3 cycles later. Pulses shorter than 2 cycles may be missed.

### 4.4 WAIT, timeout, SYNC

- `WAIT` blocks until `captured`. On completion: `REF ← CAPT`, clear `captured`, flag `TO ← 0`.
- `WAIT +t` also has timeout deadline `T = REF + t`, where REF is unchanged while waiting. In each slot:
  - if `captured` and `CAPT` is not after `T`, take the event path above;
  - else if `NOW` is at or after `T`, complete with `REF ← T` and `TO ← 1`;
  - else stay blocked.
  - **Tie rule: an event with `CAPT = T` wins.**
  - A timeout leaves `captured`/`CAPT` unchanged. A capture after `T` remains pending for the next `WAIT`.
- Wake-up happens at slot granularity, but **REF is exact** (CAPT or T). Subsequent `AT` deadlines are therefore exact relative to the event regardless of wake-up phase, provided they are accepted in time.
- `SYNC` sets `REF ← k`, where *k* is its execute cycle.

### 4.5 Pins

- Each physical output pin *p* has a configuration: `owner ∈ {none, ctx0, ctx1}`, `logical index j ∈ 0..7`, `mode ∈ {push-pull, open-drain}`, idle value. It is writable only while halted.
- Ownable outputs: `uio[7:0]`, `uo_out[7:1]` (15 pins; `uo_out[1]` is TRIG by convention). `uo_out[0]` is host MISO and is never ownable.
- A commit by context *c* updates pin *p* iff `owner(p) = c` and mask bit `j(p) = 1`. Several pins may map to one logical index (fan-out).
- **uio, push-pull:** `oe ← oe[j]`, `out ← out[j]`.
- **uio, open-drain:** logical 0 → `oe=1, out=0`; logical 1 → `oe=0`. The pin cell enforces this, and it **never drives high**.
- **`uo_out` pins:** push-pull only (open-drain is rejected at config), `out ← out[j]`, OE ignored.
- **Halted, reset, or faulted context:** owned `uio` pins have `oe = 0`; owned `uo_out` pins show the configured idle value. Unowned `uio` pins have `oe = 0`. After reset all idle values are 0.

### 4.6 Faults and status

- Per-context sticky fault codes: `LATE`, `ILLEGAL` (undefined opcode), `HOST_CFG` (illegal configuration at START).
- On a fault the context halts, its record is cleared, and its pins go to the halted state. **The other context continues.**
- Per-context sticky flags (not faults): `EVENT_OVERRUN`, `TRACE_LOST`, FIFO under/overflow from the host side.
- A run is **emulator-invalid** if any fault or `TRACE_LOST`/`EVENT_OVERRUN` flag that the experiment depends on is set.

---

## 5. Host interface

- **SPI target, mode 0, MSB first** on `ui_in[0]=CS_n`, `ui_in[1]=SCK`, `ui_in[2]=MOSI`, `uo_out[0]=MISO`. All inputs go through 2-FF synchronizers and edge detection in the core clock domain. The core has no second clock domain.
- **Provisional limits:** SCK high and low ≥ 4 core cycles each (SCK ≤ F/8), CS setup/hold ≥ 4 cycles. The MISO launch→host sample margin is derived at G3 and verified by phase sweeps. The published limit is whatever survives that analysis.
- **Framing:** command byte, 16-bit address, then a data stream with auto-increment. If CS rises mid-byte, the partial byte is discarded and only complete bytes take effect. The command set is frozen at G2: `WRITE_MEM`, `READ_MEM`, `WRITE_CFG`, `READ_CFG`, `READ_STATUS`, `CTRL` (start, halt, step, clear faults), `FIFO_PUSH(ctx)`, `FIFO_POP(ctx)`, `TRACE_POP(ctx)`.
- **Halted-only writes:** instruction memory, configuration (ownership, maps, modes, start addresses, trace mode), **parameter registers**, and the 16-bit **experiment ID**. Such writes while running are rejected and set a host error flag. FIFO push/pop and status reads are allowed at any time. As a result, host accesses never contend with instruction fetch.
- `START` validates the configuration (no `uo_out` open-drain, owner/maps in range). It sets `HOST_CFG` and does not start if validation fails.
- **The host is never in a cycle-critical path.**

---

## 6. Trace

- Per-context trace FIFO, 8 entries × 32 bits (*provisional*), **non-blocking**. On full, the entry is dropped and `TRACE_LOST` is set.
- Entry: `time[23:0] = D or CAPT or execute cycle (mod 2^24)`, `tag[7:0]`. Interpretation is fixed per run by the configured trace mode:
  - **MARK:** `MARK imm` entries only.
  - **EVENTS:** MARK + event captures (tag = logical pin).
  - **COMMITS:** each commit (tag = logical out value).
- Timestamps are unambiguous for runs shorter than 2^24 cycles (0.34 s at 50 MHz). Longer runs need periodic `MARK`s.
- The trace is bounded diagnostic evidence. **External logic-analyzer captures are the timing evidence for published claims.**

---

## 7. Memory

- Single-port, synchronous, 1-cycle read in both implementations. The core cannot tell which one it has.
- **SRAM macro (≥256×16)** only if a routed trial in the exact `cmos5l` flow passes, with valid views, power hookup and timing. **Flip-flop array 128×16** is the always-working fallback.
- Both contexts share the store, and each has a configured start address. Required protocol pairs MUST fit in 128 words total.
- Decided at **G1** from mapped µm², routed utilization, and timing.

---

## 8. ISA (semantic set; encoding frozen at G2)

| Group | Instructions |
|---|---|
| Data | `LDI r, imm8` · `MOV` · `ADD/SUB` · `AND/OR/XOR` · `SHL/SHR` through C · `CMP` |
| Control | `JMP` · `JZ/JNZ/JC/JNC` · `DJNZ r` · `CALL/RET` (1-deep) · `HALT` · `FAULT code` |
| Pins | `STG out, oe, mask` (forms from imm/reg) · `OUTB j` (SR msb → staged out[j], SR ≪ 1) · `INB j` (SAMPLE[j] → SR lsb) |
| Time | `AT +imm` · `AT Pn` · sample-flag variants · `ARM cond` · `WAIT` · `WAIT +t` · `SYNC` |
| Host | `PUSH r` · `PULL r` (block) · `LDP r, Pn.lo/hi` |
| Trace | `MARK imm` |

`OUTB` + `INB` on the single SR implements full-duplex SPI: after 8 shifts, SR holds the received byte.

**Questions G2 must answer from the example programs:** the width of `AT` immediates (≥ 434 cycles is needed for UART 115,200 at 50 MHz, so 10–12 bits or a 2-word form), 16-bit vs wider words, `L_min`, FIFO depths, and whether one action record suffices.

The second action-record entry is **not** a default fix. It is added only if a measured trace shows refill (not reaction latency) limiting a required rate.

---

## 9. Protocol acceptance (firmware only, no protocol-specific RTL)

| Protocol | Required | Extension |
|---|---|---|
| UART | 8N1 TX + RX full duplex (one context each), 115,200 baud, framing-error detection | 1 Mbaud if measured |
| SPI controller | Modes 0–3, 1 MHz | higher rate if measured |
| SPI target | Mode 0. Published rate derived from the measured CS→first-MISO and launch-edge→MISO budgets; **floor 250 kHz, goal 1 MHz** | modes 1–3 |
| I2C controller | 100 kHz, 7-bit addressing, ACK/NACK, repeated START, honors target clock stretching | 400 kHz |
| I2C target | 100 kHz, 7-bit address, ACK/NACK, repeated START, **parameterized ACK/data timing and SCL stretch** (demo knobs) | 400 kHz |
| Custom | One firmware-only protocol chosen at G2 (e.g. 1-Wire or a pulse-width request/response) | further firmware-only protocols after freeze (JTAG, SWD, WS2812, PS/2) |

Out of baseline: CRC/stuffing/encoding accelerators, USB, Ethernet. USB low-speed may be studied **in the reference model only**. 10BASE-T is declared out of scope in the submission.

Every published rate comes with clock frequency, cycle budget, I/O assumptions, and a passing measurement.

---

## 10. Flagship demo: I2C timing-tolerance map (Act 1) and bench → simulation (Act 2)

**Setup.**

- PEX (FPGA before silicon, TT chip after) emulates a 24C02-style EEPROM at address 0x50.
- The device under test is a Raspberry Pi Pico running stock MicroPython `machine.I2C` (hardware peripheral). A second controller is optional.
- External pull-ups. The logic analyzer is decoded with sigrok.

**Sweep.**

- 16×16 grid over two target-side parameters in P0/P1: SCL stretch duration after the address ACK, and SDA data-change delay after SCL falls.
- Both are measured at the pins with the logic analyzer and overlaid with UM10204 limits (`tLOW`, `tSU;DAT`, `tHD;DAT`), so compliant and deliberately out-of-spec regions are labelled.
- One run is one grid point: halt, write P0/P1 and the experiment ID, start, then 20 controller transactions.
- More trials are added around transitions.

**Outcome classes (every trial gets exactly one):**

| Class | Meaning |
|---|---|
| `PASS` | Correct data, transaction complete |
| `CTRL_TIMEOUT` | Controller reports a timeout |
| `CTRL_ERROR` | Controller reports NACK or another error |
| `CORRUPT` | Wrong data returned, no error reported |
| `BUS_STUCK` | SDA or SCL held after the transaction; recovery needed |
| `EMU_INVALID` | PEX fault or a relevant flag set; the point is discarded, never plotted as a DUT result |
| `INCOMPLETE` | Missing PEX status, controller report, or logic-analyzer capture |

Expected rejection of out-of-spec stimulus is **not** reported as a controller bug.

**Report:**

- Valid, invalid and incomplete counts.
- Per-point class fractions.
- Cycle increment and measured external timing uncertainty.
- Boundary repeatability over ≥3 independently reset maps.
- Target recovery rate and manual-intervention count.
- Experiment ID, firmware hash, MicroPython version, clock, board, pull-ups.

Results describe *this controller in this configuration*, not an intrinsic property of the part.

**Demo gates:** the compliant region is 100% `PASS`, there are zero `EMU_INVALID` points in the published map, and the boundary repeats within one grid step across 3 maps.

**Fair baseline:** implement the same target sweep on RP2040 PIO. Report program size, measured edge-placement error vs. the logic analyzer, whether emulator-invalid points are detectable, and host involvement. A documentation-level comparison with XMOS is labelled as such.

### Act 2: bench → simulation

- **Controller:** a small I2C controller written by us in Hardcaml (`demo/`), running on the FPGA. It is a second device under test whose RTL we have. It is demo RTL, not chip RTL, so the chip freeze does not apply to it.
- **Its defect is real or labelled.** If the map exposes a genuine timing-tolerance defect in our controller (e.g. mishandled stretching), we use it. Otherwise we seed one and **label it as seeded**.
- **Steps:**
  1. Run the map against our controller and pick one failing point.
  2. Save its experiment value (§10a).
  3. Show the same failure class across 20 resets on the bench.
  4. Run the **identical experiment value** with the `Sim` backend: PEX RTL + our controller RTL in Hardcaml cyclesim. It reproduces the same outcome class and renders an expect-test waveform.
  5. Fix the controller, then show the saved experiment passing in simulation and on the FPGA.
- **Claim boundary:** replay reproduces *digital, deterministic* failures of RTL we have. It does not simulate arbitrary boards, analog effects, or pull-up behavior. Automated minimization of the failing case (delta reduction) is a separate optional extension.

## 10a. Using PEX: experiments, backends, testbench component

These are first-class deliverables, not demo glue.

- **Experiment value (OCaml):** a typed description holding:
  - firmware (assembled program + start addresses);
  - configuration (pin ownership, maps, modes);
  - parameters P0–P3 per context;
  - experiment ID;
  - transaction script (host FIFO pushes/pops, expected responses, timeouts);
  - trace mode;
  - pass/fail predicate over results.

  It serializes to a file, so every interesting bench point is saved and replayable.
- **Backends behind one interface:**
  - `Sim`: PEX Hardcaml RTL in cyclesim, optionally wired to a user circuit's ports;
  - `Model`: Codex's Python reference model, via a subprocess, for cross-checks;
  - `Board`: host SPI to the FPGA or the TT chip, through a thin shim.

  All three return the same result type: outcome class, faults/flags, FIFO data, trace entries.
- **Output:** results render as **expect-test-friendly text**, with ASCII waveforms of commits and events in Jane Street's published style. A bench run and a simulation run can be compared as text diffs.
- **Hardcaml testbench component:** a documented `Pex` module (interface + configuration helpers) that a user instantiates in their own testbench, plus a small protocol firmware library (UART, SPI controller/target, I2C controller/target, custom protocol) with documented parameters. At least two worked examples: PEX as an I2C target next to a user I2C controller, and PEX as a UART peer.
- **Equivalence check (required), for every protocol example:**
  - **Open-loop programs** (no input dependence): `Sim` and `Board` produce identical commit streams (cycles, pins), checked against logic-analyzer captures.
  - **Reactive programs:** identical outcome classes and identical **event-relative commit offsets** (`D − CAPT`). Absolute cycles differ with asynchronous input phase.
  - Bench-only differences (pad delay, synchronizer phase) are documented, not hidden.

---

## 11. Verification

**Independence rule:** Codex writes the reference model **from this spec only**, in Python, never by reading the RTL. Constants may be shared through one generated file. Agreement between two AI-written implementations is evidence, not proof. Third-party oracles and real devices break ties.

| # | Item | Required? |
|---|---|---|
| V1 | Python reference model, cycle-exact for §3–§6 | required |
| V2 | Differential testing: random constrained programs + input/host stimulus. RTL vs model compared per cycle on commits (cycle, pins, OE), accepts, faults, FIFO ops, trace entries. Seeds saved | required |
| V3 | Hardcaml expect tests with ASCII waveforms for each block | required |
| V4 | SymbiYosys properties on generated Verilog, each with a **cover** and a **mutation** that must break it: no drive in reset/halt/fault; open-drain never drives high; unowned pins unchanged; an accepted action commits exactly once at D or a fault is raised; REF updated once per accept; LATE never yields a commit; event/timeout tie rule; FIFO order with no silent overwrite; modular ordering within the horizon | required |
| V5 | **Scoped isolation theorem** (self-composition miter). Given identical ctx0 program, ctx0-mapped inputs, and host writes to ctx0 state, with arbitrary ctx1 program, inputs and host traffic, ctx0's owned-pin commit stream and ctx0 local state are identical. Report the bound *k* if bounded. Intentional physical feedback is excluded | required in bounded form; unbounded is cuttable |
| V6 | Assembler deadline analyzer with three outcomes: *proven safe under listed assumptions*, *demonstrated violation*, *unknown*. Runtime `LATE` remains mandatory | optional |
| V7 | Third-party oracles: cocotb protocol models where usable in simulation; sigrok decoders on FPGA captures | required |
| V8 | Adversarial tests: input edges at every clock/slot phase; host SPI at minimum widths and aborted frames; event and timeout in the same cycle; accept attempted in the commit cycle; both contexts committing in one cycle; fault mid-run; reset mid-transaction; I2C stretching at limits | required |
| V9 | Gate-level simulation of the required protocol firmware on the synthesized netlist | required |
| V10 | FPGA hardware-in-the-loop with real peers and logic-analyzer captures | required |

Every bug found becomes a saved seed or test.

---

## 12. Toolchain and flow

- Hardcaml via opam (`hardcaml`, `hardcaml_waveterm`, `ppx_hardcaml`) → Verilog in the template's `src/`.
- GDS via the template's GitHub Actions. Local work is simulation only (Hardcaml cyclesim, Verilator, cocotb) plus SymbiYosys.
- Assembler in OCaml, sharing one ISA definition with the RTL generator.
- **Host library, experiment format and backends in OCaml** (§10a), with expect-test output. Python is limited to a thin board shim (MicroPython on the TT demo board's RP2040, or pyftdi) that relays SPI frames, plus the Pico DUT scripts. The reference model stays in Python, for independence (§11).
- All tool, PDK, template and macro versions are pinned in the repo.
- **FPGA (user purchase):** an ECP5 board with an open flow (e.g. ULX3S or OrangeCrab), or a Tang Nano 20K as the low-cost option. Check before buying: 3.3 V headers, enough logic for the full design (iCE40 UP5K is likely too small), Yosys accepts Hardcaml output. Also a ~$15 sigrok-compatible logic analyzer.

---

## 13. Schedule and gates

| Gate / dates | Work | Exit evidence |
|---|---|---|
| Oct 21–27 | Recheck rules. Public repo. Toolchain. Minimal Hardcaml block → GDS through template CI. Codex starts the model | Reproducible flow run |
| **G1, Nov 1** | Memory probes: FF 128×16 vs SRAM routed trial | Measured µm², utilization, timing. **Memory decided** |
| **G2, Nov 3** | Model executes §4. UART/SPI/I2C/custom firmware written and passing on the model. Encodings written to `spec/`. Experiment type drafted (§10a). Design note drafted (§13a) | **ISA, `L_min`, widths, host commands frozen** |
| Nov 4–10 | RTL: core, actions, events, host SPI, FIFOs. OCaml host library skeleton; `Sim` backend | UART TX/RX in RTL sim vs third-party oracle, run through the `Sim` backend with expect-test output; V2 harness live |
| **G3, Nov 17** | Full-chip GDS; SPI/I2C in RTL sim; `Pex` testbench component API v0 documented | Area, utilization and Fmax measured. Decide S=2 or S=4 and the clock. **Hours check + cut proposal to user** |
| **G4, Dec 1** | FPGA bring-up (board ordered by Oct 31); required protocols on hardware; `Board` backend; first full I2C map; our I2C controller (`demo/`) on FPGA | Logic-analyzer-verified protocols; one complete map; same experiments pass on `Sim` and `Board` (§10a check). **Hours check + cut proposal to user** |
| **G5, Dec 6** | **Chip hardware feature freeze** | After this: chip bug fixes only, each with a regression. Firmware, host, testbench, demo RTL, verification and docs continue |
| Dec 7–20 | Act 2 (bench → sim → fix). Testbench examples + docs. V4–V9 completion, map repeatability, PIO baseline, physical closure iterations. Breadth firmware protocols if time allows | Demo gates (§10) met; Act 2 shown; reports for the candidate revision |
| Dec 21–Jan 4 | Docs, demo video, clean-clone reproduction, **usability test** (§14) | Reproduction and usability test succeed |
| **Jan 11** | **Submit** | Submitted revision tagged |
| Jan 12–18 | Buffer for portal or integration issues only | — |

**Workload (judgment).** Estimated scope:

| Component | Hours |
|---|---|
| Baseline | ~163 |
| Verification extras | ~18 |
| Usability additions: OCaml host + backends, testbench component, Act 2, docs uplift, write-ups | ~46 |
| Breadth firmware protocols | ~15 |
| **Total** | **~242** |

That is about 66 h more than the ~176 h available before Jan 11. Per the user's decision, **full scope stays in plan and nothing is cut in advance.** Track human hours weekly. At G3 and G4, Claude presents actual-vs-remaining hours and a cut proposal, and **the user decides** what, if anything, to cut. A missed gate triggers the same review immediately.

**Proposed cut order** (applied only by user decision; first cut first):

1. Automated reduction (delta minimization) of failing cases
2. Firmware protocols beyond the required set
3. V6 analyzer
4. PIO characterization beyond one equal-workload comparison
5. V5 beyond bounded
6. Second testbench worked example
7. Trace depth
8. SPI target rate → floor

**Never cut:** the required protocols; timed actions with `LATE`; valid/invalid experiment classification; V1+V2 independence; passing physical flow; reproducible build; **the same experiment running on `Sim` and `Board`**; **Act 2**; the `Pex` testbench component with at least one worked example; user-facing docs.

### 13a. Building in public

- The repo is public from Oct 24 (§16) and every commit is visible.
- **Short progress write-up at each gate** (G1–G5) in `docs/log/`: what was measured, what failed, what changed. Failures are included; measured honesty is part of what gets noticed.
- **Design note to `asic-competition@janestreet.com` after G2.** Claude drafts it and **the user decides whether and when to send**. Contents: one page on the sim+bench idea, the timing contract, the plan, and one direct question: *what would make a tool like this useful to your hardware team?* Feedback received changes this spec only through the normal approval rule (§15).
- No claims in public material beyond what §1's claims rules allow.

---

## 14. Acceptance metrics (release)

| Metric | Gate |
|---|---|
| Physical fit | Prescribed 6×4 `cmos5l` flow passes; no unsupported macro |
| Timing | Declared clock met with justified constraints; no hidden paths |
| Protocols | §9 required rows pass against independent peers, with logic-analyzer captures |
| Program capacity | Each required concurrent protocol pair fits 128×16 |
| Deadline slack | Non-negative worst-case slack under stated assumptions for all example firmware |
| Reactive latency | Minimum and worst-case edge-to-output measured across phases; within each published protocol's budget |
| Isolation | Only properties actually proved are claimed, with bound and assumptions |
| Fault integrity | Every injected late/full/lost condition observable; no silent late success |
| Generality | Custom protocol works with no RTL change |
| Baseline comparison | Equal-workload PIO comparison published with limitations |
| Reproduction | Clean checkout + pinned tools rebuilds and reruns the demo |
| **Sim/bench equivalence** | §10a check passes for every protocol example |
| **Usability** | Someone outside the project (not the user, not an agent) instantiates `Pex` in a Hardcaml testbench and runs an example experiment **from the docs alone**. Time taken and every stumbling point are recorded, and docs are fixed until a fresh attempt takes under 1 hour |
| **Code quality** | Every public OCaml module documented (odoc); `dune build @doc` and the build are warning-free; Hardcaml written in the idioms of Jane Street's public Hardcaml examples, reviewed against them before freeze |

---

## 15. Ownership and collaboration

| Area | Owner | Paths |
|---|---|---|
| Decisions, purchases, bench work, final acceptance | User | — |
| Hardcaml RTL, `Pex` testbench component, assembler, firmware library, OCaml host library + backends + board shim, demo I2C controller, gate write-ups | Claude | `hw/`, `src/` (generated), `tools/asm/`, `fw/`, `host/`, `demo/`, `docs/log/` |
| Reference model, differential harness, formal properties, timing/feasibility review, PIO/XMOS baseline | Codex | `model/`, `verif/`, `docs/feasibility/` |
| This spec and `spec/` encodings | Shared: **changes need the user's approval and review by both agents** | `docs/superpowers/specs/`, `spec/` |
| `Model` backend interface (CLI/JSON between `host/` and `model/`) | Codex defines it in `model/`; Claude writes the adapter in `host/` | — |

Rules (MUST):

- Run `git status` before writing.
- Write only in your own paths. Never edit or overwrite another agent's files.
- Commit your own work promptly.
- Spec changes land as separate commits with a stated reason.
- Disagreements go to the user. Neither agent silently revises the contract.

---

## 16. Open decisions

| Decision | Owner | Due |
|---|---|---|
| Create the public GitHub repo (needed for template CI) | User | Oct 24 |
| FPGA board + logic analyzer purchase | User | Oct 31 |
| Memory implementation | Measured | G1, Nov 1 |
| `AT` immediate width, word width, `L_min`, FIFO/trace depths, custom protocol | Firmware study | G2, Nov 3 |
| S (2 vs 4), declared core clock | Measured | G3, Nov 17 |
| Published SPI-target rate | Measured | G4, Dec 1 |
| Whether and when to send the design note (§13a) | User | after G2 |
| Cuts, if any (§13) | User | G3 and G4 |
| Find an outside usability tester (§14) | User | Dec 21 |
