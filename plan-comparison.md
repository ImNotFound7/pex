# Comparison of the Codex and Claude proposals

Date: 2026-10-21. Author: Codex.

Inputs: [Codex proposal](plans.md) and [Claude proposal](claude-plan.md). Both are unimplemented proposals. This report leaves both unchanged and does not approve or freeze an architecture.

## 1. Recommendation

**Use Claude's two-clock barrel engine and timing-sweep demonstration as the baseline candidate. Keep Codex's explicit acceptance rates, experiment validity rules, and regression workflow. Make automated reduction and simulation export a gated extension.**

Claude's revised proposal is more deliverable than Codex's complete end-to-end failure-reduction workflow. Its pipelining has a real analytical throughput advantage. Codex's proposal is more conservative about timing claims, model limitations, and separating an emulator malfunction from a target failure.

Neither plan establishes a novel hardware invention, achieved frequency, area fit, or winning probability. Both depend on the same feasibility tests. Claude's more detailed prose exposes several contradictions that must be resolved before an independent model and RTL can agree meaningfully.

Do not select an entire document as the winner. Select the strongest decisions and correct the contract.

## 2. Method and evidence levels

The current competition announcement still specifies CMOS5L, 6×4 tiles, UART/SPI/I2C as starting protocols, open source, and January 18, 2027. It highlights unique functionality and design/verification approaches but supplies no numerical judging weights. [Official announcement](https://blog.janestreet.com/protocol-emulator-asic-competition/)

This comparison uses four labels:

- **Documented:** explicitly stated in a proposal or primary source.
- **Derived:** arithmetic or engineering consequences of stated assumptions.
- **Judgment:** a reasoned recommendation, not an experimentally measured fact.
- **Unknown:** requires firmware, RTL, tool results, or physical measurement.

No weighted total or percentage chance of winning is assigned. Arbitrary scores would conceal the absence of implementation evidence. The category decisions below are judgments; the numerical tables are derived quantities, not benchmark results.

Current evidence maturity is the same for both: proposals only. Neither supplies an executing protocol program, mapped area report, routed timing report, completed proof, FPGA capture, or novelty benchmark.

## 3. Decision matrix

| Criterion | Codex | Claude | Assessment |
|---|---|---|---|
| Fit to the challenge | General firmware engine; required protocols; custom example | Same | Tie on intent; actual compliance unproven |
| Useful outcome | Failure reduced to a replayable hardware/simulation regression | Timing-tolerance map of a real controller | Both relevant; usefulness inside Jane Street remains an inference |
| Demo delivery risk | Requires controlled target, reducer, and simulation adapter | Requires real controller, sweeps, result collection | Claude has fewer custom software dependencies |
| Internal compute throughput | One instruction/context/4 clocks | One instruction/context/2 clocks | Claude has 2× scheduled throughput at equal clock |
| Output time resolution | Independent timed commits, one core cycle | Same | Tie; faster instruction retirement does not improve time quantization |
| Reactive latency | Explicitly requires a worst-case budget; no value yet | More service opportunities, but no complete latency value | Claude has potential advantage; neither establishes a bound |
| Timing specification | Cautious, many decisions explicitly open | More detailed, with contradictions and unresolved edge semantics | Claude is a better starting draft, not yet an executable contract |
| Protocol acceptance | UART 115,200; SPI 1 MHz; I2C 100 kHz; explicit roles/modes | Measures maximum rates; SPI slave mode 0 in study | Codex has clearer minimum targets; Claude deliberately tests narrower SPI-slave scope |
| Memory/area discipline | Actual area, physical macro trial, small fallback | Same, with 128×16 fallback and 256×16 candidate | Tie in approach; no measured area advantage |
| Verification ambition | Local properties, differential testing, independent peers | Adds non-interference miter and static deadline analysis | Claude has stronger proposed headlines and greater proof/tooling risk |
| Novelty evidence | Explicitly acknowledges risk that value is mostly host software | Identifies XMOS timed ports but makes some overbroad exclusivity claims | Neither establishes novelty |
| Delivery schedule | Feature freeze around Dec 6–7; substantial workflow work earlier | Feature freeze Dec 15; clearer ISA and submission dates | Claude's baseline scope is leaner; Codex provides more closure time |
| Failure classification | Explicit valid/invalid distinction, flaky and divergent outcomes | LATE fault and trace-loss flag; shmoo primarily pass/fail | Keep Codex's richer result classification |
| Reviewer independence | Separate behavioral logic; language flexible | Python oracle from spec, independent protocol tools | Prefer Claude's explicit independence boundary; language difference alone proves nothing |

## 4. Quantitative architecture comparison

### 4.1 Normalize frequency before comparing

Let F be the core clock and S the service interval per context. Scheduled instruction opportunities per context are F/S, before blocking or multiword instructions.

| Metric | Codex at 25 MHz | Claude at 25 MHz | Codex at 50 MHz | Claude at 50 MHz |
|---|---:|---:|---:|---:|
| Core-clock period | 40 ns | 40 ns | 20 ns | 20 ns |
| Clocks per context instruction slot | 4 | 2 | 4 | 2 |
| Context slot interval | 160 ns | 80 ns | 80 ns | 40 ns |
| Scheduled MIPS per context | 6.25 | 12.5 | 12.5 | 25 |
| Aggregate scheduled MIPS, two contexts | 12.5 | 25 | 25 | 50 |
| Program-read issue rate | F/2 | F | F/2 | F |
| Internal timed-action resolution | 40 ns | 40 ns | 20 ns | 20 ns |
| Nominal instruction slots per 1 MHz SPI half-period | 3.125 | 6.25 | 6.25 | 12.5 |
| Nominal instruction slots per 1 Mbaud UART bit | 6.25 | 12.5 | 12.5 | 25 |

Fractional slot counts are average capacity, not a guaranteed number of usable instructions inside a particular phase window. Input observation, slot alignment, queue occupancy, and minimum action lead time reduce the useful budget.

Claude is 2× faster at equal frequency, not 4×. Comparing Claude at its hoped-for 50 MHz with Codex's provisional 25 MHz mixes two assumptions. Both frequencies remain unmeasured.

The barrel scheme is a sensible candidate: fetch A while executing B, then fetch B while executing A. Verify exact clock-edge ordering with the selected synchronous memory so the updated branch PC is used on the next fetch. There is no demonstrated reason yet to pay the 4-clock frame's throughput penalty. There is also no proof that the pipelined option has identical area, power, or maximum frequency; its read activity is higher and implementation details matter.

### 4.2 Instruction throughput is not reactive response time

For an externally triggered action, budget:

`input observation + event latch/wakeup + slot alignment + executed instruction path + action lead time + output registration/pad delay`.

Neither plan supplies every term. A 20 ns timestamp step is not a 20 ns minimum response time. Report minimum delay, worst-case delay, phase-dependent uncertainty, and output resolution separately.

Likewise, a second action entry can absorb queued work and bursts. It cannot remove input synchronization or computation that depends on a newly observed bit. Select queue depth from a trace showing which term actually limits SPI.

### 4.3 Memory and trace budgets

| Quantity | Derived value | Consequence |
|---|---:|---|
| 128×16 program store | 2,048 bits / 256 bytes | Shared by all simultaneously loaded contexts; not 128 words each |
| 256×16 program store | 4,096 bits / 512 bytes | Twice the bits; not necessarily twice the total mapped area |
| 128×32 alternative | 4,096 bits / 512 bytes | Compare program count and decoder cost as well as word width |
| Claude's illustrative 32-bit trace, 8–16 entries | 32–64 bytes | Enough for selected evidence, not a general transaction recording |
| 24-bit trace timestamp wrap, 25 / 50 MHz | 0.6711 / 0.3355 seconds | Requires epoch reconstruction or a strict run-duration/logging convention |
| 32-bit timer half-range, 25 / 50 MHz | 85.8993 / 42.9497 seconds | Future deadlines must use a precisely defined modular horizon |
| Raw host payload ceiling at SCK=F/8, 25 / 50 MHz | 0.390625 / 0.78125 MB/s | Before command overhead, stalls, and result framing |

The trace byte count assumes a 32-bit packed entry; Claude does not fully specify the tag/pin layout. Actual storage must be counted after encoding is settled.

Neither plan has enough data to compare total area, power, routing congestion, or SRAM feasibility. Require identical library, clock, memory contents/ports, interface scope, and physical constraints for any A/B area claim.

## 5. Technical corrections needed before merging

### A. Action-record refill is contradictory in Claude's plan

Locations: [block on full](claude-plan.md#22-the-timing-contract-the-core-of-the-spec), [refill discussion](claude-plan.md#23-why-this-beats-more-contexts-or-faster-fetch).

One section says an AT blocks until the old action commits. Another says the next AT must be issued before the current action commits. With one entry, the next action can be staged or the instruction can wait early, but it cannot be accepted into the occupied record without another storage location or replacement semantics.

Define three separate events: staging values, accepting AT, committing the action. Snapshot staged data on acceptance. Update REF exactly once on successful acceptance, not on every retry. Define dequeue/enqueue on the same clock, and minimum lead time for the newly accepted action. This affects both plans and the actual maximum edge rate.

### B. Deadline D versus output edge D+1 is ambiguous

Claude says an action commits at D, but registered output means the pad changes at D+1. A register does not intrinsically add a whole clock after the chosen commit edge; it adds clock-to-output delay. An explicit extra pipeline stage can add a cycle, but it must be modeled as such.

Define whether D names the comparator observation, output-register update, or another pipeline boundary. Use that definition consistently for samples, traces, LATE checks, and assertions. Codex leaves this open rather than contradicting itself; neither is ready to implement independently.

### C. Oversampling does not eliminate asynchronous-input verification

Location: [Claude host interface](claude-plan.md#25-host-interface).

The host SPI pins are asynchronous to the core even if no SCK-clocked registers are used. Oversampling avoids a second internal clock domain but still needs synchronizers, edge detection, minimum SCK high/low widths, CS/MOSI ordering, and MISO setup analysis. SCK≤F/8 is a proposed limit, not a sufficient proof. Both plans also need phase sweeps for the protocol inputs.

### D. Static deadline checking is overpromised

Location: [Claude verification headlines](claude-plan.md#61-headline-results).

Fixed slots make instruction costs predictable. They do not bound WAIT, FIFO stalls, action-record stalls, runtime parameters, arbitrary loop counts, or dependent branch conditions. A conservative worst-case analyzer can reject a program it cannot prove safe even when no feasible failing execution exists. Therefore every rejection need not have a concrete witness.

Start with three outcomes: **proven safe under listed assumptions, demonstrated violation, unknown**. Prove bounded regions with parameter ranges and explicit environment assumptions. Unverified annotations are assumptions, not proofs. Random runs with no LATE are useful checks but cannot establish analyzer soundness. Runtime LATE detection remains mandatory.

### E. Non-interference needs a boundary around shared resources

Location: [Claude verification headlines](claude-plan.md#61-headline-results).

Fixed slots alone establish scheduling isolation, not equality of complete context behavior. A shared blocking trace FIFO, shared data FIFO, mutable parameters, global faults, or electrical feedback can couple contexts. Even shared trace-loss flags can make full architectural states differ.

State identical context-0 program/data/input observations, timer/reset, and relevant host-write sequences. Scope the theorem to owned output commits and context-local state. Partition blocking resources or specify nonblocking logging and per-context loss behavior. Exclude intentional physical feedback from the isolation premise. A bounded result must be reported with its bound; it is not an unbounded theorem.

### F. Runtime parameter updates need experiment boundaries

Location: [Claude host interface](claude-plan.md#25-host-interface).

If offsets are wider than a host transfer, byte writes can tear. Even atomic single-register writes can produce a mixed P0/P1 configuration mid-transaction. The run must record exactly which parameter set it used.

Smallest baseline: update parameters between halted runs, then start with an experiment ID. If running updates are necessary, use a defined transaction-boundary commit or snapshot. Do not advertise host-independent execution while changing timing-critical parameters unpredictably during the same experiment.

### G. Full pin reach and capture storage are underspecified

Claude's action-state estimate uses roughly 8-bit values/masks but its pin plan exposes 8 bidirectional outputs plus 6 extra outputs and TRIG. Clarify a mapping/window or widen physical masks. Both plans need a definition of where a scheduled sample goes, whether later samples can overwrite it, and how full-duplex SPI preserves outgoing versus incoming data.

Count staging state, pending-action state, sample state, and pin routing in area comparisons. Counting only the deadline and a few bytes is incomplete.

### H. A deeper queue is not a general fix for SPI-slave latency

Location: [Claude firmware study](claude-plan.md#4-firmware-study-week-2-before-rtl).

For predetermined future outputs, a queue can help. For a response contingent on a just-arrived bit or chip-select, the causal path remains. Measure CS-to-first-MISO and launch-edge-to-MISO separately. Include synchronized-input age, external setup/hold, and all supported SPI modes. Derive supported rate from these measurements before selecting more buffering.

### I. A shmoo plot requires stronger outcome semantics

Location: [Claude flagship demo](claude-plan.md#5-flagship-demo-protocol-shmoo-plot).

Separate compliant stimulus, deliberately out-of-spec stimulus, target timeout/rejection, target corruption, bus stuck, emulator LATE, and incomplete evidence. Expected rejection of malformed input is not evidence of a controller bug.

ACK delay and SCL stretching interact: holding SCL low changes the available setup interval. Compare timing measured at the pins with the relevant I2C requirements, not just two parameter values. [NXP I2C specification](https://cache.nxp.com/docs/en/user-guide/UM10204.pdf?fsrch=1&pageNum=1&sr=3)

The observed tolerance belongs to a specific controller, firmware/driver, timeout configuration, clock, board, pull-ups, and load. It is not an exact intrinsic property of the part. Record those conditions and input phase uncertainty.

### J. The evidence log cannot claim every edge without capacity proof

Claude promises a trace of exactly when each edge was driven, but proposes 8–16 entries and mostly MARK/event logging. Either log actual commits for a bounded diagnostic segment or explicitly distinguish planned action times, internal timestamps, and independent analyzer measurements. One-time protocol decoding does not prove timing compliance across an entire sweep.

### K. Scope and approval records need correction

Claude labels several recommendations as agreed in its decision table. The user has requested comparison and convergence; those entries should be recorded as proposed/adopted by Claude until the user chooses the final plan.

Codex includes all four SPI slave modes while Claude studies only mode 0. This is a scope difference, not a performance win. Choose the minimum explicitly. Also resolve Claude's feature-freeze date versus its section proposing additional work only after that date; new RTL should not start after a real freeze.

## 6. Novelty: both proposals need stronger evidence

Timed I/O is established prior art. XMOS documents a timestamped output, adding an offset to its captured port time, and outputting at that future time. This is closely related to the central AT/REF idea. [XMOS timed-output example](https://www.xmos.com/documentation/XM-002509-PC/html/)

Consequently:

- Do not claim invention of timed ports, event-relative output, hardware scheduling, or fixed-slot multithreading.
- Do not describe static timing or non-interference as results available only to this architecture.
- Do not assume the equivalent PIO experiment requires hand-balanced branches everywhere. Implement a fair baseline using existing PIO capabilities before making that claim.
- Shmoo plotting and test-case reduction are established techniques. Their application here can be valuable without being inventions.

The plausible distinctive contribution is the demonstrated combination: a small open ASIC, explicit deadline failure reporting, measurable isolation, runtime-programmable protocols, and a reproducible instrument workflow. Whether that combination is sufficiently original is still a research and judging question.

Compare against PIO for accessibility and XMOS for architectural similarity. A PIO-only comparison would omit the closest identified timing primitive. An implementation benchmark against available hardware is stronger than a feature table; where hardware is unavailable, label a documentation comparison accordingly.

## 7. Demonstration metrics

### Timing-sweep baseline

Suggested first acceptance exercise: a 16×16 grid, 20 trials per point, then additional trials around transitions. That is 5,120 trials. At an illustrative 100 ms per reset-and-trial, runtime is at least 512 seconds; at 1 second it is about 85 minutes. These are budget scenarios, not measured runtimes.

Report:

- Number of valid points/trials, invalid-emulator trials, and incomplete traces.
- Pass fraction and separate timeout/corruption/bus-stuck counts per point.
- Clock-cycle increment and measured external timing uncertainty.
- Repeatability of the boundary over at least three independently reset runs.
- Target recovery rate after failed trials; power-cycle/manual intervention count.
- Parameter-set ID, firmware hash, target software version, and board conditions.
- A specification overlay separating legal timing from intentional violations.

Twenty passing trials do not establish a rare-failure rate. Use repeated trials as a demo repeatability check; increase sample count and report uncertainty if claiming reliability statistics.

One protocol's 2-D plot is enough for the signature demo. UART and SPI still need working examples, but three separate characterization campaigns need not be on the critical path.

### Optional reduction and simulation extension

Measure original versus reduced transaction count, replay duration, host reruns required, and reproduction success rate. Do not promise a reduction ratio before selecting the target.

For a deterministic controlled target, a reasonable demo gate is repeatable failure before the fix and repeatable success after the fix across 20 resets each, with no emulator-invalid trials. Export one regression that reproduces the same failure predicate in simulation. This demonstrates the workflow; it does not prove global minimality or arbitrary-board simulation support.

The extension is accepted only after the physical baseline and reliable I2C sweep work. This keeps the memorable workflow without making two extra tools a prerequisite for a valid submission.

## 8. Acceptance metrics for the final architecture

| Metric | Required measurement | Proposed gate |
|---|---|---|
| Physical fit | Mapped area, final core geometry/utilization, required physical checks | Successful prescribed 6×4 CMOS5L flow; no unsupported macro |
| Timing | Setup/hold results, constrained clocks/I/O, corners required by flow | Meet declared operating point with justified constraints |
| Basic protocols | Independent peers, modes/roles, waveform captures | UART 115,200 8N1 full duplex; SPI 1 MHz within explicitly agreed modes; I2C 100 kHz controller and target |
| Program capacity | Assembled total words including extension words and both contexts | Each selected concurrent protocol pair fits 128×16 fallback, or revise fallback before freeze |
| Deadline slack | Latest AT acceptance versus deadline minus minimum lead time | Nonnegative worst-case slack under stated input/FIFO assumptions |
| Reactive latency | Minimum and worst-case observed edge-to-output across phases | Meets each published protocol's external timing budget |
| Isolation | Miter/local proofs and resource assumptions | Claim only properties actually proved, with explicit bounded/unbounded status |
| Fault integrity | Deliberately late/full/lost conditions | Every tested invalid condition observable; no silent late success |
| Generality | Distinct protocol program | One custom protocol works without RTL changes |
| Baseline comparison | Equal workloads, controlled clock comparisons, measured native operation | Publish program bits, response bounds, host traffic, limitations; no selective clock comparisons |
| Reproduction | Clean checkout, version-pinned tools/artifacts | Another person can build/load and rerun the selected demo |

These gates prevent an attractive diagram or plot from compensating for a nonworking chip.

## 9. Schedule and workload

From October 21 to January 18 is 89 days, about 12.7 weeks: approximately 191 hours at 15 hours/week. Holding the last week for submission issues leaves about 176 hours before January 11. This is availability arithmetic, not an effort estimate.

Neither plan allocates person-hours or proves its workload fits. Claude saves the reducer and simulation adapter but adds an assembler analysis pass and a substantial relational proof. Those additions can consume the saved time. The final plan should budget them as conditional deliverables with smaller fallback results.

Schedule differences:

- Codex's first feasibility gate ends November 1; Claude's ends October 27. Claude is more aggressive, but it is the right early risk to investigate.
- Claude freezes ISA November 3. Adopt the date as a target, conditional on real example programs and a stable timing contract.
- Both target a representative integrated physical run around mid-November.
- Codex freezes features around December 6–7; Claude December 15. Preserve the earlier freeze for hardware and treat later work as verification/docs/demo work.
- Adopt January 11 as the submission target with the official deadline as buffer.

Cut order: additional characterization protocols, automated reducer/simulation bridge, broad static analysis, unbounded isolation proof beyond a useful proved subset, trace depth. Preserve required protocol functionality, reproducible execution, visible invalid experiments, and physical closure.

## 10. Recommended merge for discussion

1. **Core:** Claude's two-context, two-clock pipeline as the first candidate. Keep 4-clock execution only if measured implementation constraints justify it.
2. **Timing:** scheduled actions with explicit acceptance/commit semantics, signed modular ordering, minimum lead time, event tie rules, and snapshot behavior.
3. **Queue:** one entry initially; add a second only after a measured refill bottleneck, not as a default cure for reactive latency.
4. **Demo:** one I2C timing-tolerance map on a real controller, with a compliant baseline and properly classified invalid points.
5. **Experiment control:** parameter changes between runs initially; save a replayable experiment record for every interesting point.
6. **Verification:** independent Python model, protocol peers, local assertions, and a narrowly stated timing-isolation proof. Bounded static timing analysis with an unknown result is optional initially.
7. **Distinctive extension:** one controlled failure reduced into a simulation regression if the baseline reaches its gates early enough.
8. **Scope:** UART/SPI/I2C plus one custom protocol. No baseline CRC/encoding accelerators, USB, or Ethernet.
9. **Milestones:** firmware-driven ISA target November 3; hardware freeze early December; target submission January 11.

This merge is a recommendation, not a replacement final plan. The next useful decision is approving the corrected scope and timing contract, followed by firmware/model and physical feasibility evidence. Adding more speculative features will not resolve the outstanding comparisons.

## 11. Review limits

Read both proposals, checked selected primary sources, and calculated throughput/storage/time budgets. No RTL was implemented, synthesized, simulated, formally proved, or benchmarked. No FPGA procurement claims were verified. The prior-art search was targeted, not exhaustive. Both original plans were preserved.
