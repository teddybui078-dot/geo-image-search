# Vendored: SQLite amalgamation

- Source: https://sqlite.org/2026/sqlite-amalgamation-3530400.zip
- Version: 3.53.4 (SQLITE_VERSION_NUMBER 3530400)
- Files: `sqlite3.c`, `include/sqlite3.h`, `include/sqlite3ext.h` — unmodified.
- License: public domain (see header comment in `sqlite3.h`).

Why vendored instead of using the system `libsqlite3` on macOS: Apple's
system SQLite has `sqlite3_auto_extension` disabled ("Process-global auto
extensions are not supported on Apple platforms"), which breaks the
standard way of statically registering the sqlite-vec extension (see
`CSQLiteVec/VENDORED.md`). Compiled here with `-DSQLITE_ENABLE_RTREE`
and `-DSQLITE_CORE` (see `Package.swift`) so `CSQLiteVec` can be linked
directly against it without extension-loading machinery.
