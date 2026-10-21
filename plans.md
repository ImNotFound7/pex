# Codex proposal: a protocol emulator for reproducible hardware experiments

Date: 2026-10-21

Status: **Independent proposal for comparison with Claude's plan. Not the final architecture or an approved implementation specification.** No RTL, toolchain installation, or hardware purchase is implied by this document.

## 1. What we are trying to achieve

Build an open-source, general-purpose protocol emulator ASIC worthy of a Jane Street tapeout slot. It must work, fit the prescribed process and area, and demonstrate a capability that is useful and memorable.

The proposed signature capability is:

> Turn a failure on a physical board into a small, repeatable protocol experiment, then carry that experiment into RTL simulation as a regression test.

The chip emulates peripherals, reacts to external events, precisely schedules digital pin actions, and records bounded evidence. Host software searches experiments and reduces failing cases. The same experiment description can drive a simulation adapter.

The ASIC remains useful without the reducer: it is a programmable UART/SPI/I2C device, stimulus generator, observer, and custom-protocol engine. Failure reduction demonstrates what that architecture makes possible.

Winning is the objective, not a promise. We do not know the judges' internal priorities or existing tools. Our submission must earn its claims with measurements and demonstrations.

## 2. Requirements, assumptions, and evidence

### User decisions carried forward

- Goal: win a tapeout slot through useful, distinctive, working hardware.
- Language: Hardcaml/OCaml, as selected in the discussion with Claude.
- Team: one human with roughly 15+ hours/week, assisted by Claude and Codex.
- FPGA: none owned when discussed; willing to buy one.
- Workflow now: independent proposals, then joint brainstorming and one final plan.

Claude's proposed A+C hybrid is an existing architectural candidate, not something this draft silently replaces as an agreed decision.

### Competition baseline

The supplied brief and previously checked announcement specify IHP 130 nm CMOS5L, the CMOS5L Verilog template, 6×4 tiles, open source, and a January 18, 2027 deadline. UART, SPI, and I2C are the starting protocols; USB low speed and 10 Mbit Ethernet are stretch goals. Allow roughly 0.7 mm² nominal tile area, but use the actual template geometry and mapped area for engineering decisions.

These requirements were checked during the earlier discussion. Recheck the announcement and exact template revision at project kickoff; this draft does not claim a fresh October 21 rules audit. Do not assume the suggested 8×4 expansion is available.

There are about 12½ weeks remaining from this document's date. At 15 hours/week, that is roughly 190 human hours. AI assistance does not remove board debugging, design review, or physical-flow turnaround time.

### What is known versus proposed

- Known: Jane Street explicitly values protocol flexibility, hardware debugging, reverse engineering, and design/verification techniques.
- Inference: moving a reproducible board failure into a simulation regression could be valuable to its hardware engineers.
- Proposed differentiation: a small ASIC whose event-relative execution, bounded timing, and experiment records support this workflow across protocols.
- Unproven: novelty relative to all prior art, mapped area, achievable clock rate, protocol limits, and usefulness inside Jane Street.

## 3. The flagship demonstration

Use an FPGA as a controller under test and the emulator prototype as an external peripheral. Prefer two separate devices so the demonstration includes real asynchronous I/O. A second FPGA or a microcontroller can serve as the target; final board selection follows toolchain and pin checks.

1. Run a normal I2C transaction against an emulated peripheral.
2. Introduce a documented, deliberately seeded controller bug: for example, incorrect recovery from a reset during clock stretching.
3. Execute a repeatable sequence of transactions and timing variations until the bug manifests.
4. Have host software remove unnecessary transactions and simplify timing parameters while rerunning candidates on the target.
5. Present a small reproducer, its observed trace, and a clear failure predicate.
6. Run the same experiment against a simulation of the controller using the same external protocol stimulus semantics.
7. Fix the controller and show the saved regression passing in simulation and on the FPGA.
8. Reprogram the unchanged emulator RTL for UART, SPI, and one custom protocol.

This is a proposed example, not evidence that the bug has already been found. A real bug in an open-source controller would strengthen the entry, but the schedule must not depend on discovering one. Label seeded bugs honestly.

The minimum signature demo uses a deterministic seeded bug and a bounded transaction sequence. It does not need arbitrary trace inference, statistical learning, or a general fuzzing platform.

## 4. Why this direction, and what could invalidate it

| Candidate | Value | Main risk | Recommendation |
|---|---|---|---|
| Four-thread sequencer with a broad programmable PHY | Bit processing and more protocol reach | Shared-resource timing, concurrent stream state, feature count | Retain as Claude's candidate; measure against a smaller baseline |
| Event-relative emulator plus failure reduction | Concrete debugging workflow and verifiable timing model | Signature value may live mostly in host software | Preferred candidate; prove the hardware primitives materially help |
| Capture-to-peripheral reconstruction | Useful substitute for unavailable devices | Traces do not establish unobserved behavior; large tooling scope | Later software application, not submission baseline |

An honest challenge to this proposal: a Pico or FPGA might implement much of the workflow already. Before freezing the architecture, benchmark one equivalent experiment on RP2040 PIO plus its host CPU. Compare response latency bounds, concurrent pin actions, program size, host involvement, and trace limitations. Do not claim the ASIC is inherently faster, cheaper, or unique.

If the signature demo needs no special capability beyond a conventional sequencer, keep the conventional hardware and describe the workflow accurately. Do not add gates solely to manufacture a novelty claim. If prior art already offers the full combination, sharpen the measured advantage or choose another demonstration before substantial RTL work.

## 5. Proposed hardware architecture

### 5.1 Core shape

Start with two contexts sharing a small execution datapath and instruction memory. Use a fixed service schedule for predictable instruction progress. Candidate context state: PC, small data registers, shift state, a wide timer/event reference, wait status, and fault status.

Use an 8-bit data ALU as a candidate. Address, timestamp, and timer widths are separate decisions; an 8-bit data path does not imply 8-bit time or program addresses. Measure the cost of wider data operations against actual firmware before freezing widths.

A concrete scheduling baseline for the first model is a four-clock frame:

| Clock within frame | Operation |
|---|---|
| 0 | Issue instruction-memory read for context A |
| 1 | Execute A using the registered read result |
| 2 | Issue instruction-memory read for context B |
| 3 | Execute B using the registered read result |

This assumes one-clock synchronous instruction-memory reads. Keep the same architectural latency with a flip-flop implementation. Branches affect the next fetch. Stalled contexts retain their slots; another context waking up does not alter the service period. Longer memory latency requires an explicit schedule revision and new performance calculations.

This baseline deliberately limits each context to one instruction per four core clocks. It is a candidate to measure, not a claim that all required rates fit. Independent small sequencers are the fallback if shared fetch materially compromises useful throughput.

### 5.2 Separate scheduled pin actions from instruction retirement

Each context initially gets one pending timed-action record: deadline, output value/mask, output-enable value/mask, and optionally an input sample action. A shared cycle counter advances every core clock. A due action commits at the defined internal I/O register edge even when another context is executing.

One entry is enough to test the idea and provides a measurable scheduling horizon. Firmware must schedule subsequent actions early enough. At high edge rates, the execution rate and record refill rate remain binding constraints; timed actions do not create unlimited bandwidth.

Specify before RTL:

- Whether an action may target the current clock or requires a minimum lead time.
- Exact issue/commit ordering when a record becomes free and a new command arrives.
- Relative deadlines computed from a captured event or an earlier scheduled deadline, so instruction delays do not silently accumulate phase error.
- Timestamp width and wraparound ordering; allow scheduling only within an unambiguous bounded horizon.
- One owner per output pin while running. Disjoint contexts may commit simultaneously. Reject overlapping ownership at configuration time.
- A late command produces a sticky fault and a recorded reason. It never silently becomes an on-time action.
- An experiment-invalid fault cancels pending actions and releases bidirectional outputs; dedicated outputs assume configured idle levels. Record the fault for the host.

The initial model should use a 32-bit cycle counter for clarity. Width reduction is permitted only after deriving the required experiment duration, event-record cost, and wraparound rules.

### 5.3 Inputs and external timing

Synchronize asynchronous inputs. Selected event conditions are evaluated every core clock and latched with timestamps, rather than only when a thread receives its execution slot. A wait can use an edge or masked input condition and a timeout.

For the baseline, support one armed event condition per context and one captured result. Define arming, already-satisfied level conditions, simultaneous match/timeout, and rearming. Report loss when the selected capture mode cannot retain subsequent events. This is not an unlimited logic analyzer.

Specify all timing promises at the appropriate boundary:

- Internal commit timing: clock-cycle exact under the documented scheduling rules.
- Input observation: affected by synchronization and sampling phase; it is not the exact analog transition time.
- External output timing: includes pad, board, and load delay.
- Narrow pulses: may be missed unless they meet the documented capture-width requirement.

Calculate worst-case input-to-response latency from synchronization, event capture, context service, instruction sequence, and output registration. Test it. Do not advertise transparent high-speed forwarding without a separate timing budget.

### 5.4 Protocol operations and instruction encoding

Required semantic operations: set masked output/value enables, sample pins, shift in/out, load/move, compare, decrement/branch, wait with timeout, capture time, schedule action, FIFO transfer, trace marker, and halt/fault reporting.

These are required capabilities, not a frozen opcode table. Write real firmware before allocating bits. Compare:

- Compact 16-bit words with extension words for wide operands.
- Wider fixed words that reduce decode complexity and instruction count.

Measure total program bits, execution cycles, and mapped area. Avoid promising a rich pin mask, delay, branch target, and arbitrary operation all inside every 16-bit word.

Simultaneous sample-and-drive is particularly valuable for SPI. Determine whether it fits one timed-action record cleanly before adding separate machinery.

### 5.5 Pin allocation

Provisional allocation, subject to the exact Tiny Tapeout wrapper:

| Pins | Proposed use |
|---|---|
| `ui_in[2:0]` | Host SPI CS_n, SCK, MOSI |
| `ui_in[3]` | Spare input; assign only when needed |
| `ui_in[7:4]` | Additional protocol/event inputs |
| `uio[7:0]` | Primary protocol signals with per-pin output enable |
| `uo_out[0]` | Host MISO |
| `uo_out[1]` | Trigger/status output |
| `uo_out[7:2]` | Additional protocol/stimulus outputs |

Use the wrapper clock input. Do not add a selectable host clock or clock mux without a demonstrated need. Reset or deselection must put protocol outputs into documented safe states. I2C drives low or releases the pin; pull-ups are external.

Dedicated output pins cannot be assumed to support electrical tri-state sharing. Document MISO behavior and board wiring accordingly. Voltage translation, pull-ups, and any USB/CAN/Ethernet electrical interface are external and must be stated explicitly.

### 5.6 Host interface and buffering

Use a small SPI slave for program loading, configuration, start/stop, status, FIFO traffic, and trace retrieval. Prefer sampling host SPI in the core clock domain if a conservative SCK limit is adequate; derive that limit from synchronization and MISO timing. Otherwise budget and verify the clock-domain crossing explicitly.

Baseline restrictions simplify the design:

- Load programs and change pin ownership while halted.
- Allow documented FIFO/status operations while running.
- Avoid instruction-memory contention from host accesses during execution.
- Use explicit framing, address bounds, and defined handling of aborted transfers.
- Never rely on host SPI for a cycle-critical response.

FIFO depth and trace depth follow mapped area and the demo's measured traffic. Overflow, underflow, and capture loss must be visible. A failed experiment must be distinguishable from an invalid experiment caused by the emulator itself.

### 5.7 Memory and area

In week one, compare a small flip-flop program store against a compatible SRAM macro. Candidate depths are 128 and 256 words; candidate word widths follow the encoding study. Include read mux/decode, write controls, and macro support logic in comparisons.

SRAM feasibility means valid views for the exact process/flow, acceptable geometry, supported power connections, timing models, and a successful routed integration. A simulation model or synthesis black box is not sufficient evidence.

Use mapped area in µm² and final floorplan utilization, not an assumed conversion from flip-flops to generic cells. Reserve room based on actual placement, clock-tree, hold-fix, and routing results. Keep a small flip-flop fallback that can run the required examples and signature experiment in bounded pieces.

Do not include CRC, stuffing, Manchester, 4B/5B, or a resynchronizing NCO in the baseline. Add one only when a selected demonstration or protocol requires it and the measured budget allows it. Any shared accelerator supporting concurrent streams needs explicit per-stream state and arbitration semantics.

## 6. Software and experiment representation

Use a small assembler and readable assembly examples. A C compiler, general-purpose language, GUI, and package ecosystem are unnecessary for the first submission.

The host experiment description contains:

- Initial configuration, protocol program, parameters, and output ownership.
- Target-reset procedure and allowed startup observations.
- An ordered sequence of protocol transactions and event-relative actions.
- Expected outcomes, timeouts, and a machine-readable pass/fail predicate.
- Trace selection, clock configuration, firmware hash, experiment seed if used, and result metadata.

Prefer OCaml for the initial assembler/runner to match the project, unless existing board libraries make a small Python adapter materially simpler. Keep the reference interpreter structurally independent of the RTL even if both use OCaml. Sharing constants is acceptable; copying the implementation's scheduling algorithm as the only oracle is not.

### Replay

Replay reruns a program from a known state. It is not a recording blindly applied regardless of the target's behavior. React to handshakes, check expected observations, and terminate with a meaningful divergence result when the target differs.

Save enough information to reproduce external stimulus and decisions. A bounded event trace does not guarantee visibility into the target's internal state.

### Reduction

Start with deterministic transaction-level reduction:

1. Establish that the original case fails repeatedly after reset.
2. Remove chunks of optional transactions, preserving initialization and protocol structure.
3. Rerun each candidate using the same failure predicate.
4. Keep a removal only if the same failure persists.
5. Simplify data and timing parameters with bounded candidate values.
6. Recheck the final case and export it with evidence.

Do not assume failure is monotonic in a delay parameter; binary search is valid only when that assumption has been established. The result is a reduced reproducer, not necessarily a globally minimal one. Add repeated-trial statistical handling only if the chosen target requires it; report flaky outcomes rather than declaring success.

### Simulation bridge

Interpret the same transaction/action description through a simulation adapter. Match the external stimulus semantics and account for clock phase and synchronizer latency. Preserve observed external inputs needed to reproduce a chosen run.

Demonstrate this bridge on one controller whose RTL and physical implementation we control. Do not claim arbitrary boards can be simulated from their pin traces. Avoid asserting RTL-versus-model correctness solely because both consume the same potentially incorrect protocol description.

## 7. Required protocol envelope

Proposed initial acceptance targets, pending week-one timing calculations:

| Protocol | Baseline scope | Provisional rate |
|---|---|---|
| UART | 8N1 TX and RX; two-context full duplex; framing-error observation | 115,200 baud, then 1 Mbaud if measured feasible |
| SPI | Master and slave examples; explicit support for all four modes; bounded slave response latency | 1 MHz baseline |
| I2C | Controller and target examples; 7-bit addressing, ACK/NACK, repeated START, target clock stretching | 100 kHz baseline; 400 kHz measured extension |
| Custom | A documented pulse-width or request/response protocol with event-relative response | Chosen from measured timing envelope |

These are scoped examples implemented in firmware, not fixed protocol blocks. I2C multi-controller arbitration, SPI rates above the documented bound, unusual UART formats, and simultaneous operation of every example are not baseline promises.

Select a provisional core-clock target only after checking the exact flow and board source; 25 MHz can serve as an initial engineering trial, not a guaranteed operating point. For every published protocol rate, provide a cycle budget, I/O assumptions, and a passing physical timing result at the declared core frequency.

## 8. Verification and physical evidence

### Architecture model before detailed RTL

Model instruction effects, fixed scheduling, event capture, timed actions, FIFO stalls, and faults. Produce timing diagrams for UART, SPI, and I2C programs. This should expose ISA and scheduling mistakes cheaply.

### Simulation and differential checks

- Unit checks for timers/wraparound, FIFO boundaries, pin ownership, host SPI, and memory latency.
- Differential tests between Hardcaml-generated RTL and an independent behavioral interpreter.
- Independent protocol peers/monitors for framing and electrical drive intent.
- Constrained random combinations of input phase, context wakeups, host traffic, resets, and buffer pressure.
- Replayable seeds and reduced failures saved as regression cases.

### Targeted formal checks

Prioritize small properties with explicit assumptions:

- No output drive during required reset/disable states.
- Open-drain mode never actively drives high.
- One context cannot update pins it does not own.
- Context service slots are independent of another context's wait state.
- Accepted timed actions commit once at the specified internal edge or raise the defined fault.
- FIFO ordering and no silent overwrite on full.
- Defined wraparound and timeout behavior within the supported horizon.

Prove local properties before attempting whole-core equivalence. Digital formal checks do not prove analog metastability behavior or complete protocol compliance. Include cover properties and failing mutations to check that the assertions can actually observe relevant behavior.

### Implementation evidence

- Pin exact tool, library, PDK, macro, and template versions.
- Run the template synthesis and place-and-route flow early and repeatedly at milestones.
- Track mapped area, routed utilization, setup/hold timing, unconstrained paths, and required physical checks.
- Use appropriate I/O timing assumptions and clock-domain constraints; do not hide paths to obtain a passing report.
- Run gate-level checks supported by the flow and inspect timing-sensitive behavior.
- Validate FPGA behavior with actual peers and captured waveforms.
- Report requested versus achieved frequency, rates, trace depth, limitations, and known failures.

No passing claim is made in this plan: no RTL or physical implementation has been measured yet.

## 9. Work plan and decision gates

Dates are proposed engineering milestones, not changes to the competition deadline. If a gate fails, cut scope immediately and retain the working protocol emulator.

| Dates | Work and deliverables | Exit evidence / decision |
|---|---|---|
| Oct 21–25 | Compare this plan with Claude's; recheck rules; prior-art check; select experiment and target; one final brief | Agreed signature demo, protocol scope, architecture questions, and file ownership |
| Oct 26–Nov 1 | Toolchain/template setup; minimal Hardcaml-to-GDS trial; memory integration probes; fixed-slot versus independent-engine model | Reproducible flow, actual area/timing reports, chosen memory fallback and timing model |
| Nov 2–8 | Core model, assembler subset, basic RTL, host loading, UART TX/RX | Program loaded through host port produces checked UART waveforms; no special UART RTL |
| Nov 9–15 | SPI and I2C programs; event capture and timed action record; first representative integrated physical run | Required protocol examples pass at documented initial rates; scheduling feasibility decided |
| Nov 16–22 | FPGA prototype and repeatable target reset; seeded controller bug and experiment runner | Repeatable hardware pass/fail distinction with trace and emulator-error separation |
| Nov 23–29 | Transaction reducer and simulation adapter; custom protocol example | Physical failing case reduced; corresponding simulation regression reproduced |
| Nov 30–Dec 6 | Differential/random tests, targeted formal proofs, protocol corner cases | Reproducible regression suite and explicit proof assumptions; signature demo reliable |
| Dec 7–13 | Feature freeze; physical closure; complete rate/area limits; external review | Stable candidate with timing/physical reports; no unresolved architecture dependency |
| Dec 14–27 | Fixes, demo recording, documentation, clean-build reproduction | Another person can load programs and reproduce the demo from instructions |
| Dec 28–Jan 10 | Final artifact checks, submission preparation, buffer for integration failures | Submission package ready; confirm portal requirements and final rules |
| Jan 11–18 | Submission buffer and essential corrections only | Submit by official deadline; retain the submitted revision and artifacts |

Buy an FPGA only after confirming Hardcaml-generated Verilog support, accessible I/O voltage/pins, clocking, programming tools, and a practical second-device setup. Prefer an available, well-documented board over a theoretically ideal one that arrives late. The board purchase is a separate user decision.

### Hard scope controls

- If SRAM integration is unresolved at the first feasibility gate, use the measured flip-flop fallback for baseline development; do not block the whole project.
- If timed actions cannot be fed at the required rates, compare independent sequencers or narrow published rates. Do not mask missed deadlines.
- If reduction tooling slips, preserve a manually reduced replayable regression and label the automation incomplete.
- If hardware-to-simulation reproduction fails, diagnose the semantic gap before adding more protocols.
- No new protocol accelerators after December 6 without an essential bug-fix reason.
- USB and Ethernet are optional only after the baseline demo and physical implementation are stable. Their electrical front ends and verification costs are part of that decision.

## 10. Collaboration with Claude

Keep this file as the Codex proposal. Claude should write its own plan in a different file. After comparison, create a clearly identified final plan and list which proposals it supersedes.

Suggested division after agreement:

- Human: architecture decisions, equipment, physical experiments, final acceptance.
- Claude: Hardcaml implementation and firmware/ISA integration.
- Codex: independent reference model, verification cases, timing review, physical-feasibility analysis, and experiment tooling where assigned.

This is a suggested ownership split, not evidence that Claude has accepted it. Assign exclusive files or branches before concurrent edits. Check the working tree before changing shared files. Do not overwrite another agent's uncommitted changes or have both agents silently revise the ISA.

Maintain one shared interface/timing specification after convergence. Use independent interpretations for verification and review; agreement between two AI-generated implementations is not proof of correctness.

## 11. Risks and how we retire them

| Risk | Early evidence | Response |
|---|---|---|
| Interesting host software, ordinary ASIC | Equivalent PIO experiment and measured hardware needs | Narrow novelty claims; justify primitives through actual timing requirements |
| Program/trace memory dominates area | Mapped memory plus mux/control area and routed macro trial | Smaller programs/traces; bounded experiments; simpler core |
| Dynamic concurrency changes timing | Adversarial wakeups and instruction traces | Fixed slots or independent sequencers; explicit timing contract |
| Event records miss important behavior | Capture-rate stress and loss flags | Selective logging and explicit experiment-invalid results |
| Target state cannot be reproduced | Repeated reset-and-replay trials | Choose a controllable target; document replay preconditions |
| Reduction removes required setup | Transaction-aware candidate validity checks | Pin required setup; classify invalid candidates separately |
| Shared model and RTL share the same mistake | Independent protocol monitors and mutation checks | Separate oracle logic and compare against physical peers |
| Late routing/timing failure | Early representative full-flow runs | Reduce muxing/fanout/state; revise documented frequency |
| Scope consumes remaining human time | Weekly milestone demonstration | Cut stretches and automation breadth before core correctness |

## 12. What the final submission should contain

- Open-source Hardcaml, generated RTL, template configuration, and explicit license.
- ISA/timing documentation, assembler, host programming instructions, and protocol examples.
- FPGA build instructions and wiring/electrical assumptions.
- Reproducible verification commands, reference model, formal properties, assumptions, and results.
- Physical-flow artifacts and reports for the exact submitted source revision.
- A short demo: normal operation, induced failure, reduced case, simulation replay, successful fix.
- Honest limitations and a measured comparison with a relevant existing solution.
- A custom protocol implemented by changing firmware only.

The final completion criterion is demonstrated behavior and reproducible artifacts, not the number of claimed protocols or accelerators.

## 13. Questions for the joint brainstorming session

1. Is physical-failure reduction our strongest signature demo, or does Claude's architecture enable a more useful measurable result?
2. Which hardware primitive is essential to that demo and insufficiently served by a simple PIO baseline?
3. Do fixed-slot contexts plus timed actions beat two independent sequencers on measured area, memory access, and usable rates?
4. Which exact target and reset procedure make replay dependable?
5. What memory configuration and program encoding survive the first physical-flow measurements?
6. Which capability will we cut first if the November prototype slips?

These are deliberate decision gates. They should be resolved by examples and measurements before becoming implementation commitments.

## 14. Sources and prior-art starting points

These sources informed the discussion. They do not establish exhaustive novelty or guarantee compatibility with the final process revision.

- [Jane Street competition announcement](https://blog.janestreet.com/protocol-emulator-asic-competition/): requirements and stated interests.
- [CMOS5L template branch](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l): starting physical flow; pin an exact revision after checking current guidance.
- [Tiny Tapeout SRAM example](https://www.tinytapeout.com/chips/ttihp0p2/tt_um_urish_sram_test): precedent, not proof of compatibility with the chosen flow.
- [Jane Street: Programmable Hardware](https://www.signalsandthreads.com/programmable-hardware/): public discussion of hardware development and testing.
- [Jane Street: ASCII waveforms for testing hardware](https://blog.janestreet.com/using-ascii-waveforms-to-test-hardware-designs/): useful presentation and regression-test precedent.
- [RP2040 datasheet](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf): PIO timing, independent state machines, instruction memory, and I/O behavior.
- [Glasgow Interface Explorer](https://glasgow-embedded.org/en/intro.html): existing programmable interfaces and correlated capture.
- [Facedancer](https://github.com/greatscottgadgets/facedancer): existing device emulation, USB manipulation, and fuzzing.
- [Cynthion](https://greatscottgadgets.com/cynthion/): existing programmable USB instrumentation.
- [ChipWhisperer Husky](https://chipwhisperer.readthedocs.io/en/latest/Capture/ChipWhisperer-Husky.html): existing trigger and experiment capabilities.
- [PIO Ethernet implementation](https://github.com/holysnippet/pico_eth_doc): counterexample to claiming PIO cannot practically support Ethernet.

Further research before a novelty claim: physical test-case reduction, hardware-in-the-loop delta debugging, reactive replay, event processors, and portable simulation/hardware stimulus languages.
