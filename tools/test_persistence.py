"""Execute the Lua-compatible production persistence modules, without Roblox.

Uses Lua 5.4 CLI or its shared library. Roblox model/lifecycle tests remain manual.
"""
import ctypes
import ctypes.util
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# table.freeze is the only Luau builtin these pure modules need.
SCRIPT = 'table.freeze = table.freeze or function(t) return t end; dofile("tools/persistence_spec.lua")'


def run():
    runtime = shutil.which("lua5.4") or shutil.which("lua")
    if runtime:
        subprocess.run([runtime, "-e", SCRIPT], cwd=ROOT, check=True)
        return True
    library = ctypes.util.find_library("lua5.4")
    if not library:
        if os.environ.get("CI"):
            raise RuntimeError("CI requires Lua 5.4 for persistence tests")
        print("PERSISTENCE TESTS: SKIP (install Lua 5.4; static checks still run)")
        return False
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.luaL_loadstring.restype = ctypes.c_int
    lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
    lua.lua_pcallk.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError("Cannot create Lua state")
    previous = Path.cwd()
    try:
        os.chdir(ROOT)
        lua.luaL_openlibs(state)
        status = lua.luaL_loadstring(state, SCRIPT.encode())
        if not status:
            status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
    finally:
        os.chdir(previous)
        lua.lua_close(state)
    return True


if __name__ == "__main__":
    run()
