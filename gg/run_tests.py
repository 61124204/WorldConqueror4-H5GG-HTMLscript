#!/usr/bin/env python3
"""Run the offline GG mock tests with system Lua or liblua. No network/dependencies."""
from __future__ import annotations
import ctypes
import ctypes.util
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent
for executable in ('lua5.2', 'lua5.3', 'lua5.4', 'lua', 'luajit'):
    path = shutil.which(executable)
    if path:
        sys.exit(subprocess.run([path, 'test_wc4.lua'], cwd=root, check=False).returncode)

library = next((p for name in ('lua5.4', 'lua5.3', 'lua5.2')
                if (p := ctypes.util.find_library(name))), None)
if not library:
    sys.exit('Install Lua 5.2+ and run: lua test_wc4.lua')
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                               ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadbufferx.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                         ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                             ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    sys.exit('Unable to create Lua state')
try:
    lua.luaL_openlibs(state)
    os.chdir(root)
    source = (root / 'test_wc4.lua').read_bytes()
    status = lua.luaL_loadbufferx(state, source, len(source), b'@test_wc4.lua', None)
    if status == 0:
        status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if status != 0:
        message = lua.lua_tolstring(state, -1, None)
        print(message.decode('utf-8', errors='replace') if message else 'Lua failure', file=sys.stderr)
        sys.exit(1)
finally:
    lua.lua_close(state)
