# Vendored JS

Same vendoring approach as `Sources/CSQLite3`/`Sources/CSQLiteVec`: pre-built
bundles checked in directly, no npm/bundler step in this Swift package. The
`WKWebView` loads these as plain static files via `Bundle.module` +
`loadFileURL(_:allowingReadAccessTo:)`.

| File | Source | Version | License |
|---|---|---|---|
| `og.es.js`, `og.css` | `@openglobus/og` (`lib/og.es.js`, `lib/og.css` on unpkg) | 0.28.7 | Apache-2.0 — the package's own `LICENSE.md` on GitHub is Apache-2.0; its `package.json` `license` field incorrectly says MIT, verified by reading both directly (unpkg's `package.json` vs. `raw.githubusercontent.com/openglobus/openglobus/master/LICENSE.md`) |
| `countries-110m.json` | `world-atlas@2` (`countries-110m.json` on unpkg), original data from Natural Earth | 2.0.2 | ISC (Natural Earth data itself is public domain) |
| `topojson-client.min.js` | `topojson-client@3` (`dist/topojson-client.min.js` on unpkg) | 3.x | ISC |

`og.es.js` is a self-contained ES module (verified: zero `import` statements)
— no other JS dependency needs vendoring for the globe library itself.

Re-vendoring: fetch the same unpkg URLs at a newer version, diff before
swapping in, since `globe.js`'s API usage (`Globe`, `EmptyTerrain`, `Entity`,
`geometry.type`/`coordinates`/`style`, `Vector`, billboard options) is pinned
against 0.28.7's actual source, not just its public docs.
