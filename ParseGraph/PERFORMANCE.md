ParseGraph performance review — 13 September 2026

Implemented optimizations in Main.lua, SkillIcons.lua, and __init__.lua. Parsing rules, stored records, settings, filters, sorting, and UI layout are preserved. No saved player data or image assets were changed.

Changes made:

- The launcher timer retains its layout while position, size, artwork, font, and controls are unchanged. Its nine text labels update when the displayed second changes. Hover, dragging, resizing, hiding, restarting, replacement controls, and failed texture retries retain their behavior.
- Discarded lists disable and release their update callbacks before being detached when a view is rebuilt.
- Plain chat without markup bypasses three unnecessary pattern scans. Damage and benefit parsers reject lines missing the literal phrases required by their existing patterns, after removing markup.
- Recent lists search backward for the requested number of matching parses, then preserve the original display order. The latest-100 history view constructs only those 100 row descriptors. Full history remains available; no records are discarded.
- Graph rendering reuses the history it has already obtained. Unfiltered all-time statistics avoid building the same combined history twice.
- Skill icon modules load on the first skill-artwork request. Existing class overrides and fallback behavior are retained. This defers their startup memory cost until needed; the first request now includes module loading.
- Removed 6,260 overwritten assignments from the icon source, retaining the final value for every name. SkillIcons.lua shrank from 828,525 to 603,836 bytes (27.1%). The tested runtime compiles both versions to effectively identical bytecode, so this source reduction is not claimed as a reduction in the final icon table's memory use.

Measured results in isolated checks:

| Workload | Original | Optimized |
| --- | ---: | ---: |
| UI setter calls during 600 timer frames | 30,600 | 171 |
| Temporary allocation: latest 3 out of 10,000 records | 1,222.0 KiB | 0.5 KiB |
| Temporary allocation: latest 100 history entries | 2,629.2 KiB | 26.1 KiB |
| Mixed chat markup processing, 100,000 calls | 0.100 s | 0.012 s |
| Mixed damage parsing, 20,000 calls | 0.099 s | 0.058 s |

History allocation measurements isolate row-descriptor construction with the combined-character option disabled. Combined-character history still has the cost of copying and sorting its source records. These measurements are not total plugin memory, FPS, or an estimate of the overall game performance improvement.

Validation passed: all four plugin files compile; 662 chat inputs across eight parsing helpers produce identical results; accumulated damage, critical hits, pets, reflects, and benefits match; all 15,218 base icon mappings and class lookup variants match; history limits, source identities, ordering, date/session/spec filters, and statistics match using 10,000 records. Timer state matches under the tested visibility and layout transitions. Lazy imports and discarded callbacks are also checked.

The checks use OBS's LuaJIT runtime through its Lua 5.1 API, with JIT compilation disabled and game/UI services simulated. They do not run LOTRO itself. The game client's actual rendering, scrolling, plugin import behavior, and overall CPU/memory use still need an in-game check. Reload the plugin, complete a dummy parse with the timer enabled, and open history and a skill breakdown to check those boundaries.

Original files are preserved in backups/performance-2026-09-13/. To roll back, unload the plugin, copy Main.lua, SkillIcons.lua, SkillIconLUT.lua, and __init__.lua from that folder over the current files, then reload it. The backup folder and tools folder are not imported by the plugin.

Reproducible checks are in tools/performance_checks.lua. Run tools/run_performance_checks.py with Python; optionally pass the path to a Lua 5.1-compatible DLL. It defaults to the installed OBS Lua runtime on this computer. The runner does not start the game, write chat messages, or access saved player data.
