# Design Decisions FAQ - ecs_selection_plugin

Quick reference for design tradeoffs for ecs_selection_plugin. Focus: **why** this package exists and where its boundary lies.

## Why this package exists

**Q: Why keep this as an isolated package?**  
A: Isolation keeps ownership clear and avoids cross-layer coupling by localizing docs, APIs, and testing to one package.

**Q: What does this package own?**  
A: The concepts declared by its public API and package purpose.

## Boundary expectations

**Q: What stays out of this package?**  
A: Host orchestration, framework-specific glue outside package scope, and unrelated lifecycle policy.

**Q: What is the expected contract style?**  
A: Stable, minimally surprising APIs with constraints documented in source code and tests.

## Repository-level consistency

**Q: Why add a package-level ?**  
A: Shared constraints in this monorepo are explicit and discoverable when split across many packages.

**Q: What should be documented as follow-up work?**  
A: Any ABI, performance, or migration boundary changes that materially affect package consumers.
