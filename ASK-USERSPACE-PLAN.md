# ASK Userspace Progressive Improvement Plan

## Objective
Progressively improve the security, stability, and maintainability of the ASK userspace components (`cmm`, `dpa_app`, `fmc`, `libfci`, `libcli`). This plan addresses the specific findings regarding userspace code from the `ASK-CODE-REVIEW.md` document, moving from foundational CI integration to critical vulnerability fixes, and finally architectural hardening.

## Phase 1: Foundation & Build Integration (CI)
*Currently, userspace binaries in `data/ask-userspace/` are pre-compiled blobs. Applying fixes requires a reproducible CI build path.*

- [x] **Task 1.1: Integrate Userspace Build into CI** *(2026-04-14)*
  - Created `bin/ci-build-ask-userspace.sh` — builds libcli, libfci, dpa_app, cmm from source. Uses pre-built .so/.a from `data/ask-userspace/` for NXP-patched dependencies (libnfnetlink, libnetfilter-conntrack, fmlib, fmc).
  - Integrated into `bin/ci-build-packages.sh` — called after ASK kernel modules, before accel-ppp. Falls back to pre-built binaries on failure.
- [x] **Task 1.2: Enable Compiler Warnings & Defenses** *(2026-04-14)*
  - Updated `dpa_app/Makefile`: `-Wall -Wextra -D_FORTIFY_SOURCE=2 -fstack-protector-strong`.
  - `DPAA_DEBUG_ENABLE` is now conditional (`ifndef DPAA_DEBUG`).
  - CI build script passes hardening flags to all components.

## Phase 2: Critical Stability & Vulnerability Fixes (Immediate)
*Address issues that can cause immediate daemon crashes, heap corruption, or security vulnerabilities.*

- [x] **Task 2.1: CMM Buffer & Memory Safety** *(2026-04-14)*
  - **C11:** Added `pthread_mutex_t rtnl_pool_mutex` to `cmm_global` struct. `cmm_get_rtnl_buf()` and `cmm_free_rtnl_buf()` now lock/unlock the mutex, with bounds check against `CMM_MAX_NUM_THREADS`. Mutex initialized in `ffcontrol.c`.
  - **C14:** Replaced `strcpy(input_buf, ...)` with `snprintf(input_buf, sizeof(input_buf), "%s", ...)` in `module_route.c`.
  - **C16:** Audited — both `cmmNeighAddSolicitQ` and `__cmmNeighAdd` already check `malloc()` returns. No fix needed.
  - **C17:** Changed `cmm_print(DEBUG_STDOUT, cmm_help)` to `cmm_print(DEBUG_STDOUT, "%s", cmm_help)` in `cmm.c`.
  - **Bonus:** Fixed `CMM_MAX_64K_BUFF_SIZE` macro precedence bug (`64 *1024` → `(64 * 1024)`).
- [x] **Task 2.2: Thread Synchronization in CMM** *(2026-04-14)*
  - **C12:** `ff_enable` declared `volatile` in `cmm.h`. All reads use `__atomic_load_n(..., __ATOMIC_ACQUIRE)`, all writes use `__atomic_store_n(..., __ATOMIC_RELEASE)` in `forward_engine.c` and `cmm.c`.
- [x] **Task 2.3: dpa_app Buffer Overflows** *(2026-04-14)*
  - **C18:** Changed `sscanf` `%s` → `%63s` (fits `name[64]`) in `dpa.c`.
  - **C19:** Replaced all `sprintf(port_info->name, ...)` with `snprintf(port_info->name, CDX_CTRL_PORT_NAME_LEN, ...)` in `dpa.c`.

## Phase 3: Concurrency & IPC Hardening (Short-Term)
*Fix race conditions, locking gaps, and inter-process communication failures.*

- [ ] **Task 3.1: Conntrack Locking**
  - **C13:** Implement granular read-write locks (`pthread_rwlock_t`) for the `ct_table[]` buckets in `conntrack.c` to safely support simultaneous netlink listener inserts and CLI dumps without coarse blocking.
- [ ] **Task 3.2: libfci / FCI IPC Reliability**
  - **C22:** Modernize `libfci.c` netlink recv. Replace the indefinite blocking `recvfrom()` with a `poll()` loop + timeout to prevent `cmm` from hanging if the `cdx` kernel module fails.
  - **M16 / C15:** Encapsulate `fci_fd` accesses with a mutex to prevent interleaved multi-message corruption, and add socket re-initialization/recovery logic in `forward_engine.c` if `fci_write` fails.
- [ ] **Task 3.3: dpa_app Error Handling**
  - **C20:** Remove raw `exit(EXIT_FAILURE)` calls in `dpa_app` `fmc_compile` failure paths. Return error codes up the call stack to exit gracefully, allowing the parent environment to respond.

## Phase 4: Long-Term Architectural Refactoring
*Modernize legacy patterns and reduce resource overhead.*

- [ ] **Task 4.1: Signal Handler Safety (CMM)**
  - **M9:** Rewrite the `cmm.c` async-signal handler. Remove `fprintf`, `backtrace_symbols`, and `free`. Use only async-signal-safe functions (`write`, `_exit`) or implement a self-pipe trick to handle termination dynamically in the main loop.
- [ ] **Task 4.2: Interface Structure & Sockets (CMM)**
  - **M7 / M5:** Replace the O(n) linked list in `itf.c` with a hash table or tree structure for interface lookups. Make conntrack hash table sizes configurable/dynamic.
  - **M8:** Consolidate the 8 individual netlink sockets in `module_socket.c` into multiplexed subscriptions to reduce file descriptor load.
  - **M10:** Add `ENOBUFS` retry/backoff logic to `rtnl.c` to prevent silently dropping critical route/neighbor netlink messages under high load.
- [ ] **Task 4.3: Deprecate Hardcoded Logic (dpa_app)**
  - **M12 / M13:** Clean up unreachable test code (`ENABLE_TESTAPP1`) and export hardcoded IP/MAC configurations into an external XML or command-line parameter interface.

## Execution Strategy

1. **Sprint 1:** Execute Phase 1. Ensure `bin/ci-build-packages.sh` consistently compiles userspace tools before proceeding. This is critical—we must be able to deploy test fixes.
2. **Sprint 2:** Execute Phase 2. Apply explicit string fixes, buffer constraints, and basic thread safety.
3. **Sprint 3+:** Roll out Phase 3 and Phase 4 iteratively, accompanied by stress tests verifying conntrack throughput and IPC failover.