"""Run the Lua 5.1 regression checks without starting LOTRO.

Usage: python tools/run_performance_checks.py [path/to/lua51.dll]
The default uses the Lua 5.1 runtime bundled with OBS on this computer.
"""
import ctypes
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
runtime = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    r"C:\Program Files\obs-studio\bin\64bit\lua51.dll"
)
lib = ctypes.CDLL(str(runtime))
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lib.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.lua_close.argtypes = [ctypes.c_void_p]
state = lib.luaL_newstate()
lib.luaL_openlibs(state)

def run(source, name, execute=True):
    status = lib.luaL_loadbuffer(state, source, len(source), name.encode())
    if not status and execute:
        status = lib.lua_pcall(state, 0, 0, 0)
    if status:
        raise RuntimeError(lib.lua_tolstring(state, -1, None).decode("utf-8", "replace"))
    lib.lua_settop(state, 0)

try:
    for name in ("Main.lua", "SkillIcons.lua", "SkillIconLUT.lua", "__init__.lua"):
        run((root / name).read_bytes(), "@" + name, execute=False)
    print("PASS: all plugin files compile under Lua 5.1", flush=True)
    # Lua long strings preserve spaces and Unicode in the workspace path.
    run(("TEST_ROOT = [=[" + root.as_posix() + "/]=]").encode(), "test root")
    run((root / "tools/performance_checks.lua").read_bytes(), "@tools/performance_checks.lua")
finally:
    lib.lua_close(state)
