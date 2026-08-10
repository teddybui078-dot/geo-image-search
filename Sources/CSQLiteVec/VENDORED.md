# Vendored: sqlite-vec amalgamation

- Source: https://github.com/asg017/sqlite-vec/releases/tag/v0.1.9
  (`sqlite-vec-0.1.9-amalgamation.tar.gz`)
- Files: `sqlite-vec.c`, `include/sqlite-vec.h` — unmodified.
- License: MIT / Apache-2.0 dual-licensed (see asg017/sqlite-vec repo).

Compiled with `-DSQLITE_CORE` (see `Package.swift`) against `CSQLite3`'s
vendored SQLite, so `sqlite3_vec_init(db, &err, nil)` can be called
directly on a connection right after `sqlite3_open` — no
`sqlite3_auto_extension`/`sqlite3_load_extension` needed, which matters
because Apple's system SQLite disables the former and this app is
sandboxed, which is a poor fit for the latter (dylib loading).
