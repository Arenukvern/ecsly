# Bounded skill evaluation

The frozen prompt/rubric definitions are in ../evals/prompts.json and
../evals/held_out.json. Cases mirror the portable rule-case schema. They are
workflow/routing guidance cases, not aesthetic, runtime or performance oracles.
The app's contract and supervised browser checks provide separate runtime evidence.

2026-10-13 paired seats used the same inherited model/settings and <=180-word
answers, with read-only access except for saving owned evidence. Baseline seats
did not load this skill. Candidate seats loaded it and could inspect supporting
references/source. Answers and exposure metadata are retained in the canonical
example's output/validation/skill-eval-2026-10-13 directory.

| Case | Purpose | Observed guidance |
| --- | --- | --- |
| T1 | Reusable dependency preview | Candidate gave the actual scaffold flags and ECS seams; baseline proposed generic CustomPainter/controller structure after an initial repository inspection. |
| T2 | Background remote revision | Both described revision/deduplication and preserved focus; candidate also named the injected adapter/frame policy and current native failures. |
| T3 | Inline HTML without Flutter host | Both correctly chose visualize and avoided a Flutter process. |
| H1 | Two viewers and host catalog | Both described independent ownership; candidate named public host/address/checkpoint APIs and explicit collision refusal. |
| H2 | Millisecond claim | Both separated cold preparation, warm data/code updates and independent presentation; neither promised universal millisecond startup. |
| H3 | Late teardown after address reuse | Both required matching ownership before detach; candidate gave the existing instance guard and checkpoint key. Neither fully spelled out the browser-process boundary. |
| H4 | Spinner despite fast callback | Both refused superiority claims and required repeated equivalent-workload, independently useful pixel observations. |

The first five cases were accidentally read with scoring criteria visible to both
seats. They are exploratory evidence, not a blinded held-out gate. Fresh H3/H4
seats received a separate prompt-only input and did not read the rubrics. SKILL.md
remained unchanged during those runs; supporting workflow/verification docs were
updated during execution, so this is not a fully immutable package comparison.
Manual root review found no harmful guidance regression on those two questions,
but several rubric subrequirements were only partial. This small guidance trial
does not establish general routing accuracy, full skill acceptance, aesthetic
quality or a statistically measured improvement. Repeat from a frozen complete
package snapshot for stronger promotion evidence.

The native `steward eval --skill --json` route failed: its fixed T1 catalog names
skills absent from this repository and did not evaluate ecsly-visualization.
Do not present that command as green. Portable YAML fixtures are available for
the owning marketplace runner; direct rule checks only prove their static terms.
Skill quick_validate and fresh scaffold/consumer gates are separate checks.

A held-out answer also identified an unqualified boundary: late asynchronous
checkpoint writes across remounts need their own serialization/ownership trial.
The current live multi-view test proves checkpoint restoration and stale registry
teardown, not an arbitrary delayed native storage completion race.

2026-10-13 reproducible replay preparation: `tool/skill_evaluation/freeze.dart`
captured 193 owned source files and separate prompt-only input. `verify.dart`
rechecked every captured byte, the exact file inventory, manifest digest and
prompt-only digest after local static evaluation. Capture digest:
`c3dc027837e7a196aa88a1b22be0a334f0319c6c16d9c4618d83671612300a8a`.
Later source edits do not alter that baseline. The full capture still includes
rubrics; it is not an execution sandbox and does not freeze external references.

Local plugin-eval 0.1.0 reports static score 53/F, three instruction-budget
failures and one warning. Its generic benchmark proposal was generated but not
executed. The installed runner says there is no simulated dry-run mode. These
results establish a reproducible input epoch and identify instruction-cost work;
they do not establish behavioral improvement or a new held-out gate. Future
paired implementation tasks must include a Canvas/widget consumer with neither
scene package present, and verify that resolved dependency boundary explicitly.

The delayed-checkpoint concern now has three controlled adapter regressions:
per-key serial writes, queued stale-call refusal and late-restore owner refusal.
The canonical host uses this adapter, and a fresh Canvas consumer's supervised
two-view run passes 14 effects including checkpoint restoration across remounts.
These checks cover process-local ownership. Native persistence durability,
cross-tab coordination and initial cached reads during an in-flight older save
remain unqualified; no skill behavior score follows from the implementation tests.

Subsequent host bootstrap work closes the initial cached-read gap within one
process: a queued fresh read waits for prior writes before world creation.
Delayed-write and bootstrap failure/rebuild regressions pass, with 19 canonical
tests and a fresh nine-test Canvas consumer. A real 14-effect multi-view job
confirms normal startup/remount integration. Native durability and separate
process/tab concurrency remain outside this evidence.

2026-10-14 guidance maintenance preserves the historical verification text in
the example's `validation/skill_history`, with its original link base and byte
hash. The active reference now routes to current native toolkit and web receipts
and distinguishes OS activation observation from sampled web focus. Local static
analysis estimates deferred cost 11,450 → 7,379 tokens; score remains 53/F. The
entrypoint and trigger description were unchanged. This is evidence relocation
and correction of stale facts, not a held-out behavioral promotion. Original
193-file replay still verifies; a separate 199-file capture includes the archived
history, digest `f25b020aa963af17c2e050f7c0cfdb310726c72f4adc5bd8ac3f6653ba2b065a`.
It predates this evaluation-log append. Paired novel implementation evaluation
and instruction-cost improvements remain open.

2026-10-14 novel implementation pair: two fresh agents received the same damped
oscillator task and SDK/package roots; only one received this skill. Prompt,
rubric and guidance/oracle inputs were frozen before evaluation and archived as
byte-preserving text with hashes. Both apps pass five model tests, analysis and
Oka release compilation. Baseline fails headless semantics readiness before
input. Skill-assisted passes 15 browser checks including 11 independently
observed pointer effects and analytical reference values. Desktop captures were
inspected for both. This is one task, not general skill superiority or canonical
promotion. The absolute-index selection criterion has an explicitly recorded
interpretation limitation; baseline did not reach it.

The [comparison archive](../../../../examples/damped_oscillator/validation/skill-eval-2026-10-14/comparison.json)
retains failures, original sources, frozen guidance and a parameterized task.
The app is extracted as [damped_oscillator](../../../../examples/damped_oscillator/README.md).
A separate post-extraction epoch caught state-to-AX projection latency. Existing
harness observation-only retry now waits for the same label; no click is replayed.
It passes 16 checks, with inspected scrolling captures of both 320px plots and
selection controls. Original paired evaluation receipts remain unchanged.
Broader isolated implementation cases, independent promotion and instruction-cost
improvements remain open.
