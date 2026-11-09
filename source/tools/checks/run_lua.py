"""Run pure Lua checks using the system Lua 5.4 library (no game required)."""
import ctypes
import ctypes.util
import sys


def main():
    lua = ctypes.CDLL(ctypes.util.find_library('lua5.4') or 'liblua5.4.so.0')
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                              ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise MemoryError('Could not allocate Lua state')
    try:
        lua.luaL_openlibs(state)
        code = lua.luaL_loadfilex(state, sys.argv[1].encode(), None)
        if not code:
            code = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if code:
            print(lua.lua_tolstring(state, -1, None).decode(), file=sys.stderr)
        return int(bool(code))
    finally:
        lua.lua_close(state)


if __name__ == '__main__':
    sys.exit(main())
