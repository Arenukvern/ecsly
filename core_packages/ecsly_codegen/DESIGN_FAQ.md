# Design Decisions FAQ - ecsly_codegen

Quick reference for design tradeoffs for ecsly_codegen. Focus: **why** this package exists and where its boundary lies.

## Publication status

**Q: Is this package live on pub.dev?** A: Yes. `ecsly_codegen` is published as
an early prerelease on pub.dev.

## Why this package exists

**Q: Why keep this as an isolated package?**  
A: Code generation brings analyzer/build/source_gen dependencies that should not
be part of the `ecsly` runtime hot path. A separate package keeps the runtime
small while still giving component packages a standard generated-column path.

**Q: What does this package own?**  
A: `@EcsComponent`, `EcsColumnType`, and the build_runner builder that emits
column and facade factories.

## Boundary expectations

**Q: What stays out of this package?**  
A: Runtime storage, scheduling, host orchestration, framework glue, and domain
logic. Those remain in `ecsly`, host packages, or hand-written facades.

**Q: What is the expected contract style?**  
A: Stable annotations plus deterministic generated strings. Tests should cover
supported column families and invalid annotation targets.

## Repository-level consistency

**Q: Why keep internal dependencies key-only?**  
A: The Dart workspace resolves local packages centrally. Internal dependencies
inside this repo should use key-only entries such as `ecsly_codegen:`.

**Q: What should be documented as a follow-up?**  
A: Any generated API, storage ABI, or annotation migration that materially
affects component packages.
