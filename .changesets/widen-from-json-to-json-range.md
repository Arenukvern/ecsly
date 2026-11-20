---
'ecsly': patch
---

Widen from_json_to_json to >=0.5.0 <0.7.0: oka@main and
intentcall_platform@main require ^0.6.0, and the range keeps 0.5.x
consumers valid (0.6.0 was additive — yaml-shaped maps accepted in the
jsonDecodeMap variants). Verified with core (313) and serialization
(51) suites green at from_json_to_json 0.6.1.
