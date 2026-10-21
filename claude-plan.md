# Claude proposal: PEX, a time-triggered protocol engine

Date: 2026-10-21

Status: **Claude's full proposal for comparison with `plans.md` (Codex). Not the final plan.** Nothing here is approved for implementation. Numbers marked *hypothesis* are unmeasured and must be replaced by flow results before they appear in any spec.

---

## 0. Summary

PEX is a small two-context protocol processor built around one idea:

> **Firmware decides *what* happens on a pin. Hardware decides *when*, to the exact clock, independent of the code path that got there.**

Instructions execute slowly and deterministically (one per context every 2 clocks). Pin changes do not happen when an instruction retires. They happen when a **timed action** reaches its deadline. Deadlines are relative to the previous deadline or to a timestamped input edge. Timing therefore never drifts with branches, loops, or data-dependent paths, and a missed deadline is a hardware fault instead of a silent glitch.

This primitive gives us four things:

1. **UART, SPI, I2C and custom protocols in firmware**, without hand-balancing branch paths for timing (as PIO code needs to).
2. **Cycle-exact, event-relative fault injection:** "stretch SCL by *k* cycles after the 3rd ACK," "respond *k* cycles late," "pulse TRIG for *w* cycles, *d* cycles after CS falls."
3. **A flagship demo you can see:** a *protocol shmoo plot*. The chip emulates a peripheral, sweeps its response timing cycle by cycle against a **real, unmodified** controller, and maps exactly where that controller's timing tolerance breaks.
4. **A verification story that relies on the architecture:** fixed slots make firmware timing statically computable. The assembler can prove deadlines are met, and formal methods can prove one context cannot affect the other's timing.

Positioning, stated honestly: we will **lose to RP2040 PIO on raw bit rate** (PIO runs every state machine at the full ~125 MHz clock; we share ~50 MHz between two contexts). PIO already does Ethernet ([pico_eth](https://github.com/holysnippet/pico_eth)) and USB (PIO-USB). We claim no protocol PIO cannot do. We compete on **path-independent timing, event-relative deadlines with fault detection, statically checkable firmware, and zero host involvement during a run**, and we measure each of those claims.

---

## 1. Decisions carried forward

| Decision | Source |
|---|---|
| Goal: win a tapeout slot (novelty + credible verification, real GDS by Jan 18, 2027) | User |
| Solo human, ~15 h/week (~190 h left), Claude + Codex assisting | User |
| Hardcaml (OCaml) for RTL | User |
| FPGA: none yet; willing to buy | User |
| **No dynamic ready-thread scheduling** | Agreed after Codex review |
| **Two contexts baseline**, generator-parameterized | Agreed after Codex review |
| **No PHY accelerators in baseline** (CRC, stuffing, NRZI, NCO) | Agreed with Codex, see §9 |
| Cell-count tables are hypotheses until mapped µm² exist | Agreed after Codex review |
| Fault injection / timing exploration as the identity | Codex's suggestion, adopted |

What I **withdraw** from my earlier proposals:

- 4-thread round-robin over ready threads. It breaks timing isolation.
- "Static slot reallocation when a context is disabled." Timed actions make single-context rate much less critical, and giving one context back-to-back slots brings branch hazards back into a hazard-free pipeline. Not worth it.
- "MITM for free." Transparent forwarding needs its own latency budget, and it is not in the baseline.
- Any "PIO can't do X" claim.

---

## 2. Architecture

```
         ui_in[7:4] ─┐                                   ┌─▶ uo_out[7:2]
         uio_in[7:0] ┼─▶ 2-FF sync ─▶ edge/event unit    │   uio_out/oe[7:0]
                     │     (every clk, timestamps NOW)   │
                     │              │                    │
                     │              ▼                    │
   ┌──────────────┐  │   ┌─────────────────────────┐     │
   │ instr memory │──┼──▶│ barrel core, 2 contexts │     │
   │ (1 read/clk) │  │   │ fetch ctx(n%2) / exec   │     │
   └──────▲───────┘  │   │ 8-bit ALU, regs, SR     │     │
          │          │   └──────────┬──────────────┘     │
          │          │              ▼                    │
   ┌──────┴───────┐  │   ┌─────────────────────────┐     │
   │ host SPI     │  │   │ timed-action records    │─────┤
   │ slave + regs │  │   │ (1 per ctx, deadline vs │     │
   │ FIFOs, trace │◀─┼───│  32-bit NOW counter)    │     │
   └──────────────┘  │   └─────────────────────────┘     │
                     └── pin ownership + open-drain enforcement
```

### 2.1 Barrel core: 2 contexts, 2-clock frame

- A global 32-bit counter `NOW` increments every core clock.
- Context `c` fetches when `NOW mod 2 == c` and executes in the following clock, while the other context fetches.
- Instruction memory needs **one read per clock**, which a single-port SRAM provides.
- Each context has at most one instruction in flight, and its branch resolves before its next fetch. The pipeline is **hazard-free by construction** (the classic barrel-processor property). It has no forwarding, no stalls between contexts, and no shared mutable state except memory-mapped host registers.
- Every instruction consumes exactly one slot. A blocked instruction (`WAIT`, a full `AT`) re-occupies its own slot and never touches the other context's slots.

This differs from Codex's 4-clock frame (§11). It keeps the same determinism, doubles per-context throughput, and uses the same single-port memory. At 50 MHz each context runs 25 MIPS. *Hypothesis:* 50 MHz closes on IHP130. 25 MHz is the fallback; every published rate gets derated by measured Fmax.

Per-context state (*hypothesis*, frozen by the firmware study in §4):

| State | Width |
|---|---|
| PC | 8 (256 words) |
| GPR r0–r3 | 4 × 8 |
| Shift register SR + bit count | 8 + 4 |
| Flags Z, C | 2 |
| Link register (1-deep call) | 8 |
| REF (time reference) | 32 |
| Action record: deadline, out value, OE value, mask, sample flag | 32 + ~3×8 |
| Event config + captured timestamp | ~8 + 32 |
| Fault code (sticky) | 4 |

### 2.2 The timing contract (the core of the spec)

This is the part to get exactly right, and the part Codex's reference model should be written from.

1. **`AT +n`** sets deadline `D = REF + n`, then `REF ← D`. The staged action commits at the clock where `NOW == D`. Outputs are registered, so the pad changes at `D+1` plus pad and board delay. Chained `AT`s never accumulate phase error, whatever code runs between them.
2. **Record full ⇒ block.** With one record per context, an `AT` blocks until the previous action commits. Blocking happens at deterministic times, so this is still deterministic.
3. **Late ⇒ fault.** If `D − NOW < L_min` when the action enters the record, or `D − NOW` exceeds the horizon (`2^31`), the context halts with a sticky `LATE` fault. Pending actions are cancelled, owned bidirectional pins are released, and dedicated outputs go to their configured idle level. The fault is never silently converted into a late edge. This is how an experiment is marked *invalid* as opposed to *failed*.
4. **Events.** Every clock, the event unit evaluates the synchronized inputs against each context's armed condition (edge or masked level on a chosen pin). It latches `CAPT = NOW` on a match. A context in `WAIT` resumes with `REF ← CAPT`, so `AT +n` after `WAIT` means *n cycles after the synchronized edge*. The documented constant offset is the synchronizer depth (2 clocks) plus sampling phase (0–1 clock). Events are captured even while the context is not in its slot.
5. **Timeout.** `WAIT ev, +t` resumes at `REF + t` if no event arrives, with a flag set. If the event and the timeout land on the same clock, the event wins (documented, and formally checked).
6. **Sample-and-drive.** An action can also latch the synchronized input pins at its commit clock. This is the SPI primitive: drive MOSI and sample MISO on the same exact edge.
7. **Pin ownership.** Each physical output has a configured owner (ctx0, ctx1, none), set only while halted. Hardware masks actions to owned bits. Disjoint commits on the same clock both apply.
8. **Open-drain mode per pin.** Driving 0 sets OE=1 with out=0. Driving 1 sets OE=0. This is enforced in the pin cell, not in firmware, so "never drives high" is a hardware property.
9. **`SYNC`** re-anchors `REF ← NOW` for free-running starts.

Every promise is stated at its own boundary: *commit timing* is cycle-exact, *input observation* carries the synchronizer offset and ±1 clock of sampling phase, and *pad timing* adds board delay. Pulses shorter than 2 clocks may be missed (documented).

### 2.3 Why this beats "more contexts" or "faster fetch"

Instruction throughput sets **how much work** fits between two edges. Timed actions set **where the edges land**. Separating them lets us use the slow, area-cheap, provably isolated barrel core while keeping 1-clock edge resolution. In PIO the two are the same thing, which is why PIO programs balance branch paths by hand and why a data-dependent decision costs an edge a cycle.

The binding constraint is the **refill rate**: one record per context means firmware must issue the next `AT` before the current one commits. With a 2-clock slot this caps a single context near one edge every few slots. The §4 firmware study measures this per protocol. If SPI at the target rate needs it, a 2-entry record queue is the first escalation, before any new execution unit.

### 2.4 Pins

| Pins | Use |
|---|---|
| `ui_in[2:0]` | Host SPI: `CS_n`, `SCK`, `MOSI` |
| `ui_in[3]` | Spare input |
| `ui_in[7:4]` | Extra protocol/event inputs |
| `uio[7:0]` | Primary protocol pins, per-pin OE, open-drain capable |
| `uo_out[0]` | Host `MISO` |
| `uo_out[1]` | `TRIG`: owned like any output, used for scope triggers and fault pulses |
| `uo_out[7:2]` | Extra protocol/stimulus outputs |

This matches Codex's allocation. I dropped my earlier `HOST_CLK_SEL`. One clock domain: the wrapper clock. Pull-ups, level shifting and any USB/CAN electrical interface are external and documented.

### 2.5 Host interface

- SPI slave **sampled in the core clock domain** (oversampled, `SCK ≤ clk/8`). No CDC to verify.
- Framed commands: write instruction memory, read/write config, start/stop/step, read status and faults, push/pop data FIFOs, read the trace FIFO, write **parameter registers**.
- **Parameter registers P0–P3** are readable by firmware and writable by the host **while running**. They are the sweep knobs: the host changes a delay between transactions without reloading the program. `AT rP` takes its offset from a parameter.
- Program and pin-ownership writes are only allowed while halted. Host access never contends with fetch during a run.
- The host is never in a cycle-critical path.

### 2.6 Trace

`MARK imm` and (optionally) every event capture push `{NOW[23:0], ctx, tag/pins}` into a small trace FIFO. Overflow sets a sticky `TRACE_LOST` flag, so the host always knows when a trace is incomplete. Depth is set by measured area (*hypothesis*: 8–16 entries). It is a bounded evidence log, not a logic analyzer.

### 2.7 Memory

Single-port, 1-clock synchronous read in both implementations, so the core never knows which one it has.

- **Option A (preferred if it integrates):** an IHP SRAM macro, 256 × 16 or larger. It counts as feasible only with valid LEF/GDS/Liberty for the exact `cmos5l` flow, power hookup, and a **routed** trial. A synthesis black box proves nothing.
- **Option B (fallback, always kept working):** a flip-flop array, 128 × 16, with a registered read port.

Week-1 measurement decides. The ISA must fit the required examples in 128 words either way.

---

## 3. Candidate ISA (to be validated, not frozen)

These are the semantic operations, with a candidate 16-bit encoding. **Write UART TX/RX, SPI master/slave and I2C controller/target in it on the reference model before any encoding is frozen** (ISA freeze gate: Nov 3).

| Group | Instructions |
|---|---|
| Data | `LDI r, imm8` · `MOV` · `ADD/SUB` · `AND/OR/XOR` · `SHL/SHR` (through C) · `CMP` |
| Control | `JMP` · `JZ/JNZ/JC/JNC` · `DJNZ r, label` · `CALL/RET` (1-deep LR) · `HALT` · `FAULT code` |
| Pins | `STG val, mask` (stage action out/OE) · `OUTB k` (SR msb → staged bit k, shift) · `INB k` (pin k → SR lsb, shift) |
| Time | `AT +imm` · `AT rP` · `AT +imm, SAMPLE` · `WAIT ev[, +t]` · `ARM ev` · `SYNC` |
| Host | `PUSH r` / `PULL r` (block on full/empty) · `LDP r, Pn` |
| Trace | `MARK imm` |

Open encoding question the firmware study must settle: **offset width.** UART at 115,200 baud on a 50 MHz clock needs 434 cycles per bit, which does not fit an 8-bit immediate. The candidates are a 12-bit immediate in `AT`, a 2-word `AT` form, or a 16-bit offset taken from a parameter register. The answer comes from the example programs, not from taste.

---

## 4. Firmware study (week 2, before RTL)

On the reference model:

| Program | Measure |
|---|---|
| UART TX/RX 8N1, full duplex (one context each) | words, slack per bit, max baud at 25/50 MHz |
| SPI master (all 4 modes) | words, max SCK, record-refill margin |
| SPI slave (mode 0) | **worst-case CS/SCK-edge-to-MISO latency** |
| I2C controller | words, 100k/400k, handling of target clock stretching |
| I2C target | 7-bit addr, ACK/NACK, repeated START, **parameterized ACK delay and SCL stretch** (the shmoo knobs) |
| Pulse/glitch generator | event-relative pulse, min width, min delay |

Exit criteria: every program fits in 128 words total per protocol pair, published rates have a cycle budget, and the encoding is frozen. If SPI slave latency is unacceptable, escalate to a 2-entry record queue (§2.3). If that still fails, publish a lower SPI-slave rate instead of adding hardware.

---

## 5. Flagship demo: protocol shmoo plot

**Setup:** PEX (on FPGA pre-silicon, on the TT chip after) emulates an I2C target, for example a small EEPROM. The controller under test is a **real, unmodified device**: a $4 Raspberry Pi Pico running stock MicroPython `machine.I2C`, with a second option of a Linux SBC's `i2c-dev`. No seeded bug is needed. Real controllers have real, undocumented margins.

**Run:**

1. Normal transactions pass. Captured with a logic analyzer and decoded by **sigrok** (an independent decoder).
2. The host sweeps two parameters through P0/P1 while the firmware is unchanged: **ACK delay** (cycles after SCL falls) × **SCL stretch length**.
3. Each point runs *N* transactions, and the controller-side script reports pass/fail.
4. Output: a 2-D pass/fail map with cycle resolution, plus PEX's own trace of exactly when each edge was driven. It shows where this controller stops tolerating stretching and how it fails (timeout, bus lockup, corrupted read).
5. Repeat with SPI (MISO setup delay vs. SCK edge against a real SPI controller) and UART (bit-width skew ±δ, which measures the receiver's baud tolerance).
6. Reprogram the same chip for UART, SPI and a custom pulse protocol. Firmware changes only.

**Why it needs the architecture:** each point in the map is one parameter-register change, with every other edge held cycle-exact by `AT` chaining. In PIO, changing one delay inside a branchy I2C target means re-balancing paths by hand. The `LATE` fault means an invalid point (emulator missed its own deadline) is never mistaken for a controller failure. This is the measured comparison: implement the same sweep on PIO and report program size, path-balancing effort, and whether invalid points are detectable.

**Why it's memorable:** "here is the exact timing tolerance of a part you own, measured by a chip we designed" is a real reverse-engineering result, and Jane Street named reverse engineering as part of their work.

**Codex's reduction workflow** (§11) is a natural *layer above* this. Shmoo finds the boundary, and reduction minimizes a failing case. It sits on the same primitive and is listed as a stretch, not as the baseline.

---

## 6. Verification

The verification story relies on properties the architecture makes possible, not just on test volume.

### 6.1 Headline results

1. **Timing non-interference, proved formally.** Self-composition miter: two copies of the core, same ctx0 program and inputs, **arbitrary different** ctx1 program and inputs. Prove ctx0's pin-commit trace and architectural state are identical in both copies. Bounded depth first, then k-induction. This is the precise version of "one protocol can't disturb another," and few if any programmable-I/O designs state it as a theorem.
2. **Static deadline checking in the assembler.** With fixed slots, the cycle cost of any straight-line path is known. Between an anchor (`WAIT`/`AT`) and the next `AT`, the assembler computes the worst-case path length and **rejects programs that could hit `LATE`**. Bounded loops use `DJNZ` bounds, and unbounded loops require an annotation. Cross-checked in simulation: no accepted program may ever raise `LATE` in random runs, and every rejected program has a concrete witness.
3. **Independent differential testing.** Random constrained programs and input stimulus run on RTL vs. an **independent reference interpreter written by Codex from the spec**. The comparison is cycle-exact on the pin-commit/event/trace streams.

### 6.2 The rest

- **Hardcaml expect tests with ASCII waveforms** for every block (Jane Street's own published practice).
- **Formal properties (SymbiYosys on generated Verilog):** no drive during reset/halt; open-drain never drives high; unowned pins are never modified; an accepted action commits exactly once at `D` or raises a fault; FIFO order and no silent overwrite; timeout/event tie rule; `NOW` wrap ordering within the horizon. Each property gets a **cover** and a **mutation** that must make it fail, to show the property can actually observe what it claims.
- **Third-party protocol oracles:** cocotb protocol models where usable (e.g. cocotbext-uart/spi/i2c) in simulation, and sigrok decoders on FPGA captures. Neither was written by us.
- **Adversarial timing tests:** input edges at every sampling phase, simultaneous event and timeout, both contexts committing on the same clock, FIFO starvation mid-transfer, host traffic during runs, reset mid-transaction, I2C stretching at limits.
- **Gate-level simulation** of the post-synthesis netlist on the UART/SPI/I2C firmware.
- **Every failure found becomes a saved seed and a regression.**

### 6.3 Independence rule

Codex writes the reference model **from the spec only**, never from RTL, preferably in **Python** (a different language from the RTL lowers the chance of shared mistakes; constants may be shared via one generated file). Agreement between two AI implementations is evidence, not proof. Third-party oracles and real devices are the tie-breakers.

---

## 7. Toolchain and flow

- **RTL:** Hardcaml via opam (`hardcaml`, `hardcaml_waveterm`, `ppx_hardcaml`), emitting Verilog into the template's `src/`.
- **GDS:** the TT `cmos5l` template's GitHub Actions run the hardening flow. Locally we only simulate, which avoids fighting the PnR toolchain on macOS. Requires a public GitHub repo early (allowed: open source, build in public).
- **Simulation:** Hardcaml cyclesim (unit), Verilator (full chip, gate-level, cocotb).
- **Formal:** SymbiYosys + Yosys.
- **Assembler:** OCaml, sharing the ISA definition with the RTL generator (one source of truth for encodings). Includes the static deadline checker.
- **Host software:** Python (pyserial/pyftdi or the TT demo board's RP2040) for loading, sweeping and plotting.
- **FPGA (user decision):** an ECP5 board with a mature open flow (e.g. ULX3S or OrangeCrab), or a Tang Nano 20K as the cheap option. Pre-purchase checks: 3.3 V headers, enough LUTs for the full design (iCE40 UP5K is likely too small), a Yosys flow that accepts Hardcaml's Verilog. **Order by Oct 31** so it arrives before the Nov 18 bring-up.
- Pin exact versions of every tool, PDK and template revision in the repo.

---

## 8. Schedule and gates

| Dates | Work | Gate / exit evidence |
|---|---|---|
| Oct 21–27 | Converge Claude+Codex plans into one. Recheck rules. Toolchain. Fork template; minimal Hardcaml design → GDS via CI. Memory probes (FF 128×16, SRAM macro). | **G1:** flow reproducible; measured µm² for both memories; memory choice made |
| Oct 28–Nov 3 | Spec v0 (timing contract §2.2 + candidate ISA). Codex: reference model. Claude: assembler. Firmware study §4. | **G2 (Nov 3): ISA frozen**, all example programs pass on the model, rates budgeted |
| Nov 4–17 | RTL: barrel core, timed actions, events, host SPI, FIFOs. UART end-to-end in sim. Differential harness live. First full-chip GDS. | **G3 (Nov 17):** UART passes vs third-party oracle; full-chip area + Fmax measured; scope cut if over |
| Nov 18–Dec 1 | SPI + I2C pass. Formal properties. FPGA bring-up with real Pico peer. | **G4:** all three protocols on FPGA with sigrok-decoded captures |
| Dec 2–15 | Shmoo demo. Static deadline checker. Non-interference proof. Firmware-only extra protocols. | **G5 (Dec 15): feature freeze** |
| Dec 16–Jan 4 | Physical closure, GL sim, docs, demo video, clean-clone reproduction | Stable candidate, all reports for the exact revision |
| Jan 5–11 | **Target submission Jan 11** | Submitted |
| Jan 12–18 | Buffer for portal or integration surprises only | Deadline |

**Cut order if a gate slips** (first cut first):

1. Codex-style reducer / sim bridge (never in baseline)
2. Extra firmware protocols beyond UART/SPI/I2C + one custom
3. Non-interference proof: k-induction → bounded depth only
4. Shmoo automation → manual sweep of a handful of points
5. Trace FIFO depth → minimum

**Never cut:** UART/SPI/I2C in firmware, timed actions + `LATE` fault, passing physical flow, the differential test against the independent model.

---

## 9. Beyond the baseline (only after G5, in this order)

1. **Firmware-only protocols, zero RTL:** JTAG, SWD, 1-Wire, WS2812, PS/2, NEC IR, DShot. Cheap breadth that demonstrates generality.
2. **USB-LS feasibility, in the model first.** 1.5 Mbit/s at 25 MIPS/context gives ~16 instructions per bit, which may be enough for software NRZI, bit-stuffing and CRC5/16 with good bit ops. Evaluate on the reference model. Only if it falls short **and** area remains, consider a small CRC/LFSR unit with explicit per-context state.
3. **Codex's failure reduction + simulation bridge**, layered on the shmoo infrastructure.
4. **10BASE-T: explicitly out of scope.** At 25 MIPS/context it leaves ~2.5 instructions per bit, which is impossible in firmware, and the hardware it needs (Manchester + CRC32 + link pulses) costs area better spent on the baseline. We say so in the submission rather than half-doing it.

---

## 10. Ownership (if adopted)

| Area | Owner | Paths |
|---|---|---|
| Architecture decisions, hardware purchases, bench work, final acceptance | Human | — |
| Hardcaml RTL, assembler, firmware examples, host loader | Claude | `hw/`, `src/` (generated), `tools/asm/`, `fw/`, `host/` |
| Reference model, differential harness, formal properties, timing/feasibility review, prior-art benchmark (PIO comparison) | Codex | `model/`, `verif/`, `docs/feasibility/` |
| ISA + timing contract | **Shared, changes need both agents + human sign-off** | `spec/` |

Rules: each agent commits only in its own paths. The working tree is checked before each session. `spec/` changes land as their own commits with a stated reason. Nobody silently revises the ISA.

---

## 11. Where this differs from Codex's plan (agenda for joint brainstorming)

| Topic | Codex | Claude | Why |
|---|---|---|---|
| Signature demo | Board failure → reduced reproducer → simulation regression | **Protocol shmoo plot** against a real unmodified controller; reduction as a stretch | The value sits in the chip's primitive, not in host software (Codex's own §4 risk). One DUT, no seeded bug, no reducer or sim bridge on the critical path. Fits ~190 h. |
| Execution frame | 4-clock: fetch A, exec A, fetch B, exec B | **2-clock barrel**: fetch one while executing the other | Same determinism, same single-port memory, 2× throughput, hazard-free by construction |
| Timed actions | Proposed, details open | **Adopted as the central primitive** with a concrete contract (§2.2): chained deadlines, block-on-full, `LATE` halts, event tie rule | Codex's best idea. Making it the identity is what makes the slow core acceptable. |
| Verification headline | Strong property list | Same list **plus** a formal non-interference proof and assembler static deadline checking | Results only this architecture enables. Credible, specific, memorable to judges. |
| Reference model language | OCaml, structurally independent | **Python** preferred | A different language reduces shared-mistake risk |
| ISA freezing | Firmware first, no date | Firmware first, **frozen Nov 3** (G2) | The schedule needs a date |
| Physical flow | Run template flow early | Same, **via the template's GitHub Actions** | Avoid local PnR setup on macOS |
| Accelerators | Not in baseline | Agreed. USB-LS tried in firmware first, Ethernet explicitly out | — |
| Submission date | Jan 11–18 buffer | **Target Jan 11**, final week for surprises only | Same idea, firmer target |

Points where I fully agree with Codex and changed my position: no dynamic scheduling, two contexts, no accelerators in baseline, measured µm² only, honest prior-art claims, SRAM feasibility means a routed trial, late actions are faults, one owner per pin, firmware before encoding.

Open questions for the joint session:

1. Shmoo vs. failure reduction as the flagship. Or shmoo first, with a reduction layer if time allows?
2. 2-clock barrel vs 4-clock frame: any timing-closure reason to prefer 4?
3. One action record per context, or two from the start (SPI slave latency)?
4. Reference model in Python or OCaml?
5. Which FPGA board, ordered by Oct 31?
6. Do we create the public GitHub repo now, so the template CI can run G1?

---

## 12. Sources

- [Jane Street competition announcement](https://blog.janestreet.com/protocol-emulator-asic-competition/)
- [TT CMOS5L template](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l)
- [TT IHP SRAM example](https://www.tinytapeout.com/chips/ttihp0p2/tt_um_urish_sram_test)
- [RP2040 datasheet (PIO)](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf)
- [pico_eth: 10BASE-T on PIO](https://github.com/holysnippet/pico_eth) · [Pico-10BASE-T](https://github.com/tvlad1234/Pico-10BASE-T-Library)
- [Jane Street: ASCII waveforms for testing hardware](https://blog.janestreet.com/using-ascii-waveforms-to-test-hardware-designs/)
- Prior art to benchmark before novelty claims: Glasgow Interface Explorer, ChipWhisperer (timed glitch triggers), Facedancer/Cynthion, XMOS xCORE (timed ports: the closest prior art to `AT`; our difference must be stated against it).
