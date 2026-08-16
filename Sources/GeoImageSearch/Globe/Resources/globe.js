// Native <-> globe bridge implementation. Message shapes are locked in
// CONTRACT.md ("Native <-> globe bridge") — do not change the JSON here
// without updating CONTRACT.md and Globe/GlobeMessage.swift together.
//
// OpenGlobus has no built-in Entity/Layer clustering (verified against the
// library source directly — see Globe/Resources/vendor/VENDORED.md), so LOD
// clustering below is hand-rolled: a lat/lon grid whose cell size depends on
// camera altitude, recomputed only when the altitude crosses a bucket
// boundary. Native has no visibility into live camera state (the locked
// message schema has no "zoom changed" JS -> native message), so this has
// to live here rather than in native Swift.

import {
    Globe,
    EmptyTerrain,
    Entity,
    Vector,
    Extent,
    LonLat,
    control
} from "./vendor/og.es.js";

// topojson-client is a UMD bundle (not an ES module) loaded as a classic
// script by index.html before this module runs — see index.html's comment.
const topojson = window.topojson;

// ---- Custom palette (explicitly not OpenGlobus's default look / no
// default blue-marble basemap — DESIGN.md) ----
const PALETTE = {
    ocean: "#0b1220",
    landFill: "rgba(216, 155, 110, 0.88)",
    landStroke: "rgba(244, 201, 138, 0.9)",
    pinFill: "#ff6b4a",
    pinStroke: "#fff3ea",
    clusterFill: "#ffb703",
    clusterStroke: "#3a2400",
    clusterText: "#3a2400"
};

const BRIDGE_NAME = "geoImageSearchBridge";

function postToNative(message) {
    try {
        window.webkit.messageHandlers[BRIDGE_NAME].postMessage(message);
    } catch (e) {
        // Nothing further to report to — if the bridge itself is gone,
        // there's no native side listening for webviewError either.
        console.error("geo-image-search bridge unavailable:", e);
    }
}

function reportError(message) {
    postToNative({ type: "webviewError", message: String(message) });
}

window.addEventListener("error", (event) => {
    reportError(event.message || "Unknown script error");
});
window.addEventListener("unhandledrejection", (event) => {
    reportError((event.reason && event.reason.message) || String(event.reason));
});

// ---- Marker rendering: hand-drawn SVG data URIs instead of OpenGlobus's
// default billboard/label assets, so no extra image/font resources need
// vendoring and no fontsSrc atlas is required for cluster count badges. ----
function svgToDataUri(svg) {
    return "data:image/svg+xml;base64," + btoa(svg);
}

function pinMarker() {
    const size = 22;
    const r = size / 2 - 3;
    const svg =
        `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
        `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="${PALETTE.pinFill}" ` +
        `stroke="${PALETTE.pinStroke}" stroke-width="2.5"/></svg>`;
    return { src: svgToDataUri(svg), size };
}

function clusterMarker(count) {
    const size = count >= 100 ? 44 : count >= 10 ? 38 : 32;
    const r = size / 2 - 3;
    const label = count > 999 ? "999+" : String(count);
    const fontSize = label.length > 2 ? size * 0.32 : size * 0.4;
    const svg =
        `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
        `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="${PALETTE.clusterFill}" ` +
        `stroke="${PALETTE.clusterStroke}" stroke-width="2.5"/>` +
        `<text x="50%" y="52%" text-anchor="middle" dominant-baseline="middle" ` +
        `font-family="-apple-system, sans-serif" font-weight="700" font-size="${fontSize}" ` +
        `fill="${PALETTE.clusterText}">${label}</text></svg>`;
    return { src: svgToDataUri(svg), size };
}

// ---- LOD clustering ----
// Altitude thresholds (meters) -> grid cell size (degrees). gridDeg 0 means
// "no clustering, render individual pins". Tuned by eye against a globe
// whose radius is ~6,371,000m, not derived from a formula.
const LOD_LEVELS = [
    { minAltitude: 6_000_000, gridDeg: 15 },
    { minAltitude: 2_000_000, gridDeg: 6 },
    { minAltitude: 600_000, gridDeg: 2 },
    { minAltitude: 120_000, gridDeg: 0.5 },
    { minAltitude: 0, gridDeg: 0 }
];

function levelIndexForAltitude(altitude) {
    for (let i = 0; i < LOD_LEVELS.length; i++) {
        if (altitude >= LOD_LEVELS[i].minAltitude) return i;
    }
    return LOD_LEVELS.length - 1;
}

// Simple arithmetic-mean centroid/grid bucketing — not geodesically correct
// near the poles or the antimeridian, but adequate for a visual LOD
// indicator at this grid granularity. See Storage/GeoMath.swift for the
// precision that actual geo queries require, which this does not need to
// match.
function clusterPins(pins, gridDeg) {
    if (gridDeg <= 0) {
        return pins.map((p) => ({ kind: "pin", id: p.id, lat: p.lat, lon: p.lon }));
    }
    const buckets = new Map();
    for (const p of pins) {
        const key = Math.floor(p.lat / gridDeg) + "_" + Math.floor(p.lon / gridDeg);
        let bucket = buckets.get(key);
        if (!bucket) {
            bucket = [];
            buckets.set(key, bucket);
        }
        bucket.push(p);
    }
    const result = [];
    for (const bucket of buckets.values()) {
        if (bucket.length === 1) {
            result.push({ kind: "pin", id: bucket[0].id, lat: bucket[0].lat, lon: bucket[0].lon });
            continue;
        }
        let sumLat = 0;
        let sumLon = 0;
        let minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
        const ids = [];
        for (const p of bucket) {
            sumLat += p.lat;
            sumLon += p.lon;
            minLat = Math.min(minLat, p.lat);
            maxLat = Math.max(maxLat, p.lat);
            minLon = Math.min(minLon, p.lon);
            maxLon = Math.max(maxLon, p.lon);
            ids.push(p.id);
        }
        result.push({
            kind: "cluster",
            ids,
            lat: sumLat / bucket.length,
            lon: sumLon / bucket.length,
            bounds: { minLat, maxLat, minLon, maxLon }
        });
    }
    return result;
}

function main() {
    const globus = new Globe({
        target: "globe",
        name: "geo-image-search-globe",
        terrain: new EmptyTerrain(),
        nightTextureSrc: null,
        specularTextureSrc: null,
        atmosphereEnabled: true,
        controls: [new control.Navigation(), new control.TouchNavigation()]
    });

    const countriesLayer = new Vector("countries", { entities: [], pickingEnabled: false });
    const pinsLayer = new Vector("pins", { entities: [] });
    globus.planet.addLayers([countriesLayer, pinsLayer]);

    // Landmasses from vendored topojson, styled with the custom palette —
    // replaces OpenGlobus's default imagery basemap entirely.
    fetch("vendor/countries-110m.json")
        .then((r) => r.json())
        .then((topology) => {
            const geo = topojson.feature(topology, topology.objects.countries);
            const entities = geo.features.map(
                (feature) =>
                    new Entity({
                        geometry: {
                            type: feature.geometry.type,
                            coordinates: feature.geometry.coordinates,
                            style: {
                                fillColor: PALETTE.landFill,
                                strokeColor: PALETTE.landStroke,
                                lineWidth: 1
                            }
                        }
                    })
            );
            countriesLayer.setEntities(entities);
        })
        .catch((e) => reportError("Failed to load country outlines: " + e));

    let currentPins = [];
    let currentLevelIndex = -1;
    const highlightedIds = new Set();

    function render() {
        const level = LOD_LEVELS[Math.max(currentLevelIndex, 0)];
        const grouped = clusterPins(currentPins, level.gridDeg);
        const entities = grouped.map((g) => {
            if (g.kind === "pin") {
                const marker = pinMarker();
                const highlighted = highlightedIds.has(g.id);
                return new Entity({
                    lonlat: [g.lon, g.lat],
                    properties: { pinId: g.id },
                    billboard: {
                        src: marker.src,
                        size: [marker.size, marker.size],
                        scale: highlighted ? 1.4 : 1.0
                    }
                });
            }
            const marker = clusterMarker(g.ids.length);
            return new Entity({
                lonlat: [g.lon, g.lat],
                properties: { clusterIds: g.ids, bounds: g.bounds },
                billboard: {
                    src: marker.src,
                    size: [marker.size, marker.size]
                }
            });
        });
        pinsLayer.setEntities(entities);
    }

    pinsLayer.events.on("lclick", (e) => {
        const entity = e.pickingObject;
        if (!entity || !entity.properties) return;
        if (entity.properties.pinId) {
            postToNative({ type: "pinSelected", id: entity.properties.pinId });
        } else if (entity.properties.bounds) {
            const b = entity.properties.bounds;
            globus.planet.flyExtent(new Extent(new LonLat(b.minLon, b.minLat), new LonLat(b.maxLon, b.maxLat)));
        }
    });

    globus.renderer.events.on("draw", () => {
        const altitude = globus.planet.camera.getAltitude();
        const level = levelIndexForAltitude(altitude);
        if (level !== currentLevelIndex) {
            currentLevelIndex = level;
            render();
        }
    });

    window.__geoImageSearchReceive = function (message) {
        try {
            switch (message.type) {
                case "setPins":
                    currentPins = message.pins || [];
                    render();
                    break;
                case "focusRegion": {
                    const b = message.bounds;
                    globus.planet.flyExtent(new Extent(new LonLat(b.minLon, b.minLat), new LonLat(b.maxLon, b.maxLat)));
                    break;
                }
                case "highlightAssets":
                    highlightedIds.clear();
                    (message.ids || []).forEach((id) => highlightedIds.add(id));
                    render();
                    break;
                default:
                    console.warn("Unknown native -> JS message type:", message.type);
            }
        } catch (e) {
            reportError("Failed handling native message '" + message.type + "': " + e);
        }
    };

    postToNative({ type: "webviewReady" });
}

try {
    main();
} catch (e) {
    reportError("Globe initialization failed: " + e);
}
