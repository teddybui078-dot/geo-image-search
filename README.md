# 3D Interactive Map

The globe: an [OpenGlobus](https://github.com/openglobus/openglobus) 3D globe rendered inside a `WKWebView`, bridged to native Swift, showing your photos as pins on a hand-styled world — not a default basemap.

**Status: not started — skeleton only.**

## What this covers

- `WKWebView` host + `WKScriptMessageHandler` bridge, both directions (native → JS pin data, JS → native query/selection events) — exact message schema in [CONTRACT.md](CONTRACT.md)
- A native `WKNavigationDelegate` fallback UI if the webview fails to load or crashes
- Pin rendering from real `PhotoQuery.allActivePhotosWithLocation()` data — `database-structure` is merged, no mocking needed
- LOD/clustering by zoom level using OpenGlobus's built-in Entity/Layer clustering, since a real multi-year library can mean thousands of geotagged photos
- Custom color palette and pin/marker styling — explicitly not OpenGlobus's default look

OpenGlobus was chosen over CesiumJS specifically for this project: Apache-2.0, no ion account/token friction, lighter inside a `WKWebView`, and a better fit for hand-coding a custom look than fighting Cesium's heavier styling model. Full reasoning in [DESIGN.md](DESIGN.md).
