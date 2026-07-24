/*
 * Imported from lua-aot-5.4 (https://github.com/hugomg/lua-aot-5.4), a
 * research AOT compiler for Lua 5.4. Licensed under the MIT License:
 *
 *   Copyright (C) 1994-2021 Lua.org, PUC-Rio, Hugo Musso Gualandi
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "lauxlib.h"
#include "lualib.h"

static int next_id = 0;

/* Continuation for running the module's main chunk: everything after
   the call is just "return the chunk's single result", so the same
   function serves both the direct return and the resume-after-yield
   path. Without it, lua_call would make luaopen_ a C-call boundary
   that a coroutine.yield from the chunk's main body cannot cross. */
static int luaot_runchunk_k(lua_State *L, int status, lua_KContext ctx)
{
    (void)L; (void)status; (void)ctx;
    return 1;
}

static
void bind_magic(Proto *f)
{
    // This traversal order should be the same one that luaot.c uses
    f->aot_implementation = LUAOT_FUNCTIONS[next_id++];
    for(int i=0; i < f->sizep; i++) {
        bind_magic(f->p[i]);
    }
}

int LUAOT_LUAOPEN_NAME(lua_State *L) {
    const char *source = LUAOT_MODULE_SOURCE_CODE;
    size_t size = sizeof(LUAOT_MODULE_SOURCE_CODE)-1;
    if (size > 0 && source[0] == '#') {
        /* skip a leading '#' line, as luaL_loadfilex does for files;
           keep the newline so the chunk still parses from line 1 */
        while (size > 0 && source[0] != '\n') { source++; size--; }
    }
    /* the chunkname the module was compiled from ("@filename"), so
       debug info (source, short_src) matches the original file */
#ifndef LUAOT_MODULE_CHUNKNAME
#define LUAOT_MODULE_CHUNKNAME "@" LUAOT_MODULE_NAME
#endif
    int ok = luaL_loadbuffer(L, source, size, LUAOT_MODULE_CHUNKNAME);
    switch (ok) {
      case LUA_OK:
        /* No errors */
        break;
      case LUA_ERRSYNTAX:
        fprintf(stderr, "syntax error in bundled source code.\n");
        exit(1);
        break;
      case LUA_ERRMEM:
        fprintf(stderr, "memory allocation (out-of-memory) error in bundled source code.\n");
        exit(1);
        break;
      default:
        fprintf(stderr, "unknown error. This should never happen\n");
        exit(1);
    }

    LClosure *cl = (void *) lua_topointer(L, -1);
    bind_magic(cl->p);

    lua_callk(L, 0, 1, 0, luaot_runchunk_k);
    return luaot_runchunk_k(L, LUA_OK, 0);
}
