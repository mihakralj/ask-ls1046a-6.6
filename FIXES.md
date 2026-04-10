# ASK SDK Source Compilation Fixes

Log of fixes applied to NXP SDK source files for Linux 6.6 kernel compilation.

## 2026-04-10: Fix SDK FMan source compilation errors

Three NXP SDK source files had copy-paste errors (duplicate definitions, orphaned
preprocessor blocks) that caused compilation failures on Linux 6.6.129.

### 1. `fm_pcd_ext.h` — Duplicate enums, struct members, missing `#endif`

**File:** `sdk_fman/inc/Peripherals/fm_pcd_ext.h`

**Problems:**
- Duplicate `FmPcdPlcrProfileGetAbsoluteId()` function declaration
- Missing `#ifndef USE_ENHANCED_EHASH` guard (orphaned conditional)
- Duplicate `FM_PCD_HashTableModifyMissMonitorAddr()` function declaration
- Duplicate `FM_PCD_HashTableGetKeyAging()` block with related enums/structs

**Fix:** Removed duplicate declarations and restored correct preprocessor structure.

### 2. `fm_common.h` — Duplicate enum/typedef block

**File:** `sdk_fman/Peripherals/FM/inc/fm_common.h`

**Problems:**
- Duplicate `#if (DPAA_VERSION >= 11)` block with `FE_MAX_CONTEXT_SIZE` macro
  definitions (identical copy appeared twice in succession)
- Duplicate `t_FmPortGetSetCcParamsCallback` typedef (appeared both before and
  after another typedef block)
- Missing `FmPortSetFESupport()` / `FmPortDeleteFESupport()` forward declarations
  (removed as they had no implementation and caused linker errors)
- Added `FmGetMuramSize()` declaration for ASK MURAM size query support

**Fix:** Removed duplicate blocks, relocated callback typedef to correct position,
added ASK-specific forward declarations.

### 3. `fm.c` — Orphaned `#else` block, duplicate functions

**File:** `sdk_fman/Peripherals/FM/fm.c`

**Problems:**
- Orphaned `#else` / `#endif //AUTO_FIRMWARE_LOAD` block in `FM_Config()` function
  referencing undefined `fman_firmware` symbol (the matching `#ifndef` was removed
  but the `#else` block was left behind)
- Duplicate `FM_ReadTimeStamp()` function definition (appeared twice in succession)
- Duplicate `FM_GetTimeStampIncrementPerUsec()` function definition (appeared twice)
- Added `#ifdef AUTO_FIRMWARE_LOAD` guard and `fman_firmware[]` declaration for
  firmware loading support
- Added `FmGetMuramSize()` function implementation for ASK MURAM query

**Fix:** Removed orphaned preprocessor block, removed duplicate function
definitions, restored correct `AUTO_FIRMWARE_LOAD` conditional structure.

## Notes

- All fixes are to NXP SDK overlay sources in `patches/kernel/sdk-sources/`
- The `qman_low.h` QBMan header is NOT an SDK source — it is the mainline kernel's
  file with proper `#if defined(CONFIG_ARM) || defined(CONFIG_ARM64)` guards. It
  only fails on x86 build hosts (no ARM/PPC config set). On the ARM64 CI runner
  this compiles correctly.
- The `003-ask-kernel-hooks.patch` kernel hooks were fixed in a prior commit
  (84bf9fc).