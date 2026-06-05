# Is it possible to force terminal or insert mode in a terminal buffer

- Seems like no

In a terminal buffer with `buf->terminal != NULL`:

1. Normal-state mode string is forced to `nt`, not `n`.

```c
else {
  buf[i++] = 'n';
  ...
  else if (curbuf->terminal) {
    buf[i++] = 't';
    if (restart_edit == 'I') {
      buf[i++] = 'T';
    }
  }
}
```

So any Normal state in a terminal buffer reports `nt`/`ntT`, never plain `n`. Source: `src/nvim/state.c:get_mode()` ([GitHub][1])

2. Insert entry is redirected before real Insert mode can run.

```c
bool edit(int cmdchar, bool startln, int count) {
  if (curbuf->terminal) {
    ...
    return terminal_enter();
  }
  ...
}
```

So `i`, `a`, `A`, `I`, `:startinsert`, etc. call `edit()`, but `edit()` immediately enters Terminal-mode instead of Insert-mode. Source: `src/nvim/edit.c:edit()` ([GitHub][2])

3. Terminal-mode itself sets the state to `MODE_TERMINAL`.

```c
assert(buf->terminal);
...
State = MODE_TERMINAL;
...
state_enter(&s->state);
...
State = save_state;
```

Source: `src/nvim/terminal.c:terminal_enter()` ([GitHub][3])

Help agrees:

* `nt`: “Normal in terminal-emulator (insert goes to Terminal mode)”
* `t`: “Terminal mode: keys go to the job”
* Terminal input: enter Terminal-mode with `i`, `I`, `a`, `A`, or `:startinsert`; leave with `<C-\><C-N>` ([Neovim][4])

So: no way to get real `n` or real `i` while the buffer remains a terminal buffer. The blocking conditions are exactly `curbuf->terminal` in `get_mode()` and `edit()`.

[1]: https://raw.githubusercontent.com/neovim/neovim/master/src/nvim/state.c "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/neovim/neovim/master/src/nvim/edit.c "raw.githubusercontent.com"
[3]: https://github.com/neovim/neovim/blob/master/src/nvim/terminal.c "neovim/src/nvim/terminal.c at master · neovim/neovim · GitHub"
[4]: https://neovim.io/doc/user/builtin.html " Builtin - Neovim docs"


# can i change (maybe temporarily), the type of the buffer to go to 'n' mode?

Not usefully.

You can set the option:

```vim
:setlocal buftype=
```

But this only changes `b_p_bt`/`'buftype'`. It does **not** clear the real terminal marker: `buf->terminal`.

Terminal identity is stored separately:

```c
term->buf_handle = buf->handle;
buf->terminal = term;
```

Source: `terminal_alloc()` in `src/nvim/terminal.c` ([GitHub][1])

`'buftype'` is then set later as an option:

```c
set_option_value(kOptBuftype, STATIC_CSTR_AS_OPTVAL("terminal"), OPT_LOCAL);
```

Source: `terminal_open()` ([GitHub][1])

But mode behavior checks `curbuf->terminal`, not `'buftype'`:

```c
else if (curbuf->terminal) {
  buf[i++] = 't';
}
```

Source: `get_mode()` in `src/nvim/state.c` from prior source.

Insert is also blocked by `curbuf->terminal`:

```c
bool edit(...) {
  if (curbuf->terminal) {
    ...
    return terminal_enter();
  }
  ...
}
```

Source: `edit()` in `src/nvim/edit.c` ([GitHub][2])

The pointer is cleared only when terminal teardown says the buffer no longer has a terminal:

```c
if (buf) {
  buf->terminal = NULL;
}
```

inside `terminal_close()` when `status == -1 || exiting`, i.e. buffer close/free path or exit, not ordinary `:setlocal buftype=`. ([GitHub][1])

So answer:

* Temporarily changing `&buftype` will not get real `n`/`i`.
* Real condition is `curbuf->terminal != NULL`.
* No Vimscript/Lua API to set `buf->terminal = NULL`.
* Only non-hacky route: copy contents to a normal buffer:

```vim
:%yank | new | put
```

or Lua equivalent.

[1]: https://raw.githubusercontent.com/neovim/neovim/master/src/nvim/terminal.c "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/neovim/neovim/master/src/nvim/edit.c "raw.githubusercontent.com"

