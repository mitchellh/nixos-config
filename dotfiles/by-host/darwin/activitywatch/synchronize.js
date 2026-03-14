// synchronize.js - ActivityWatch to macOS Calendar (JXA)

// Configuration
const CALENDAR_NAME = "[㏒:💻]: MacBook";
const AW_API_URL = "http://localhost:5600/api";

// Filtering & Merging
const MIN_DURATION_SEC = 90;        // 1. Final Event Filter: Events smaller than this (post-merge) are discarded
const NOISE_THRESHOLD_SEC = 10;     // 2. Pre-Merge Filter: Events smaller than this are IGNORED (prevents phantom splits)
//    Aligned with MIN_DURATION_SEC to avoid invisible interruptions.
const MERGE_GAP_TOLERANCE_SEC = 666; // 3. Merge Tolerance: Merge events if gap is smaller than this (5 mins). 
//    Increased to handle AFK gaps or accepted breaks.

const IGNORE_AFK = true; // Set to true to filter out AFK time

// Imports
const app = Application.currentApplication();
app.includeStandardAdditions = true;

// --- Helpers ---

function runShellKey(cmd) {
    try {
        return app.doShellScript(cmd);
    } catch (e) {
        console.log(`Error running usage: ${cmd} -> ${e}`);
        return "";
    }
}

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

// --- Sync State (New) ---

function getHostname() {
    return runShellKey("hostname").trim();
}

function getSyncBucketId() {
    const hostname = getHostname();
    return `aw-sync-icloud-calendar-${hostname}`;
}

function ensureSyncBucket() {
    const bucketId = getSyncBucketId();
    const hostname = getHostname();

    // Check exist
    const buckets = getBuckets();
    if (buckets[bucketId]) return bucketId;

    // Create
    log(`Sync bucket '${bucketId}' not found. Creating...`);
    const payload = JSON.stringify({
        client: "aw-sync-jxa-to-icloud-calendar",
        type: "sync-log",
        hostname: hostname
    });

    // Escaping JSON for shell is tricky.
    const escapedPayload = payload.replace(/"/g, '\\"');

    const cmd = `curl -X POST "${AW_API_URL}/0/buckets/${bucketId}" -H "Content-Type: application/json" -d "${escapedPayload}"`;
    runShellKey(cmd);

    return bucketId;
}

function getLastSyncTime() {
    const bucketId = getSyncBucketId();
    // Get last 1 event
    const url = `${AW_API_URL}/0/buckets/${bucketId}/events?limit=1`;
    const json = runShellKey(`curl -s "${url}"`);
    try {
        const events = JSON.parse(json);
        if (events && events.length > 0) {
            const last = events[0];
            // The timestamp of the sync event is what we want to use as 'since'
            // BUT: If the sync event represents "Sync performed AT X covering up to X", then yes.
            // Our recordSyncEvent uses scriptStartTime.
            return isoToDate(last.timestamp);
        }
    } catch (e) {
        log("Error fetching last sync time: " + e.message);
    }
    return null;
}

function recordSyncEvent(startTime, eventCount) {
    const bucketId = getSyncBucketId();
    const now = new Date();
    // We record the START time of this script run as the timestamp of the event.
    // This ensures next run picks up from where we started this time.
    const payload = JSON.stringify({
        timestamp: startTime.toISOString(),
        duration: 100,
        data: {
            status: "success",
            events_synced: eventCount,
            synced_at: now.toISOString()
        }
    });

    const escapedPayload = payload.replace(/"/g, '\\"');
    const cmd = `curl -X POST "${AW_API_URL}/0/buckets/${bucketId}/events" -H "Content-Type: application/json" -d "${escapedPayload}"`;
    runShellKey(cmd);
    log("Recorded sync event to bucket.");
}

// --- ActivityWatch API ---

function getBuckets() {
    const json = runShellKey(`curl -s "${AW_API_URL}/0/buckets/"`);
    if (!json) return {};
    return JSON.parse(json);
}

function findBucketId(prefix, options = {}) {
    const buckets = getBuckets();
    const hostname = getHostname();

    // 1. Try exact match
    const target = `${prefix}_${hostname}`;
    if (buckets[target]) return target;

    const { exclude = null } = options;

    // 2. Search for any bucket with prefix
    for (const id in buckets) {
        if (!id.startsWith(`${prefix}_`)) continue;
        if (exclude && id.includes(exclude)) continue;
        if (id) {
            return id;
        }
    }
    return null;
}

function getWindowBucketId() {
    return findBucketId("aw-watcher-window", { exclude: "_ios-" });
}

function getAfkBucketId() {
    return findBucketId("aw-watcher-afk", { exclude: "_ios-" });
}

function getEvents(bucketId, startIso) {
    // startIso should be ISO string
    // limit=-1 for all
    log(`Fetching events from ${bucketId} starting ${startIso}...`);
    const url = `${AW_API_URL}/0/buckets/${bucketId}/events?start=${encodeURIComponent(startIso)}&limit=-1`;
    const json = runShellKey(`curl -s "${url}"`);
    try {
        return JSON.parse(json);
    } catch (e) {
        log("Error parsing events JSON: " + e.message);
        return [];
    }
}

// --- Logic ---

function isoToDate(iso) {
    return new Date(iso);
}

function dateToIso(date) {
    return date.toISOString();
}

/**
 * Filter out events that overlap with AFK periods.
 */
function filterAfkEvents(windowEvents, afkEvents) {
    if (!afkEvents || afkEvents.length === 0) return windowEvents;

    // Extract AFK ranges
    // AFK event: { data: { status: "afk" }, timestamp: "...", duration: ... }
    const afkRanges = [];
    afkEvents.forEach(e => {
        if (e.data.status === "afk") {
            const start = isoToDate(e.timestamp).getTime();
            const end = start + (e.duration * 1000);
            afkRanges.push({ start, end });
        }
    });

    // Sort ranges
    afkRanges.sort((a, b) => a.start - b.start);

    const filtered = [];
    windowEvents.forEach(w => {
        const wStart = isoToDate(w.timestamp).getTime();

        let isAfk = false;
        // Simple check: drop if START is in AFK range.
        for (const range of afkRanges) {
            if (wStart >= range.start && wStart < range.end) {
                isAfk = true;
                break;
            }
        }

        if (!isAfk) {
            filtered.push(w);
        }
    });

    log(`Filtered ${windowEvents.length} -> ${filtered.length} events (removed AFK).`);
    return filtered;
}

/**
 * Filter out short "noise" events BEFORE merging.
 */
function filterNoiseEvents(events) {
    const filtered = events.filter(e => e.duration >= NOISE_THRESHOLD_SEC);
    log(`Filtered ${events.length} -> ${filtered.length} events (removed < ${NOISE_THRESHOLD_SEC}s noise).`);
    return filtered;
}

/**
 * Merges events based on App name and proximity.
 * NOW UPDATED: Groups by App first to handle interleaving (A -> B -> A).
 */
function mergeEvents(events) {
    if (!events || events.length === 0) return [];

    // 1. Group by App
    const eventsByApp = {};
    events.forEach(e => {
        const appName = e.data.app ? e.data.app.trim() : "Unknown";
        if (!eventsByApp[appName]) {
            eventsByApp[appName] = [];
        }
        eventsByApp[appName].push(e);
    });

    const finalMerged = [];

    // 2. Process each App independently
    for (const appName in eventsByApp) {
        const appEvents = eventsByApp[appName];

        // Sort ASC by time
        appEvents.sort((a, b) => isoToDate(a.timestamp) - isoToDate(b.timestamp));

        let current = null;

        appEvents.forEach(e => {
            const eStart = isoToDate(e.timestamp);
            const eDuration = e.duration;
            const eEnd = new Date(eStart.getTime() + eDuration * 1000);
            const title = e.data.title;

            if (!current) {
                current = {
                    app: appName,
                    start: eStart,
                    end: eEnd,
                    titles: [title]
                };
                return;
            }

            // Check Gap
            const gap = (eStart - current.end) / 1000; // seconds
            const effectiveGap = gap < 0 ? 0 : gap;

            // Same app guaranteed. Check tolerance.
            if (effectiveGap <= MERGE_GAP_TOLERANCE_SEC) {
                // Merge
                // Extend end if needed
                if (eEnd > current.end) {
                    current.end = eEnd;
                }
                // Add unique title
                if (!current.titles.includes(title)) {
                    current.titles.push(title);
                }
            } else {
                // Split
                finalMerged.push(current);
                current = {
                    app: appName,
                    start: eStart,
                    end: eEnd,
                    titles: [title]
                };
            }
        });

        if (current) finalMerged.push(current);
    }

    // Sort final result by start time for Calendar insertion (optional but nice)
    finalMerged.sort((a, b) => a.start - b.start);

    return finalMerged;
}

// --- Calendar ---

function ensureCalendar(name) {
    const Calendar = Application("Calendar");
    const calendars = Calendar.calendars.whose({ name: name });

    if (calendars.length === 0) {
        log(`Calendar '${name}' not found. Attempting creation...`);
        try {
            const newCal = Calendar.Calendar({ name: name });
            Calendar.calendars.push(newCal);
            log("Created calendar successfully.");
            return newCal;
        } catch (e) {
            log("Hard failure creating calendar: " + e.message);
            return null;
        }
    }
    return calendars[0];
}

function run() {
    log("Starting Sync...");
    // Capture start time for sync record (use this as the marker for NEXT run)
    const scriptStartTime = new Date();

    const Calendar = Application("Calendar");

    // 1. Find/Create Calendar
    const targetCal = ensureCalendar(CALENDAR_NAME);
    if (!targetCal) {
        log("Could not access or create target calendar. Aborting.");
        return;
    }

    // 2. Get Sync State from Bucket
    ensureSyncBucket();
    let lastSyncDate = getLastSyncTime();

    if (lastSyncDate) {
        log(`Found last sync time: ${lastSyncDate.toISOString()}`);

        // Sanity Check: If last sync is in the future, fallback?
        const now = new Date();
        if (lastSyncDate > now) {
            log("Warning: Last sync time is in the future! Fallback to 24h ago.");
            lastSyncDate = new Date(now.getTime() - (24 * 60 * 60 * 1000));
        }
    } else {
        log("No previous sync found (bucket empty). Defaulting to 24h ago.");
        const now = new Date();
        lastSyncDate = new Date(now.getTime() - (24 * 60 * 60 * 1000));
    }

    // 3. Fetch AW Data
    const bucketId = getWindowBucketId();
    if (!bucketId) {
        log("No window bucket found.");
        return;
    }

    let rawEvents = getEvents(bucketId, lastSyncDate.toISOString());
    log(`Fetched ${rawEvents.length} raw window events.`);

    if (rawEvents.length === 0) {
        log("No new events found.");
        // Still record sync event so we move the cursor forward? 
        // Yes, otherwise we keep querying old ranges.
        recordSyncEvent(scriptStartTime, 0);
        return;
    }

    // 4. Fetch AFK Data & Filter
    if (IGNORE_AFK) {
        const afkBucketId = getAfkBucketId();
        if (afkBucketId) {
            const afkEvents = getEvents(afkBucketId, lastSyncDate.toISOString());
            log(`Fetched ${afkEvents.length} AFK events.`);
            rawEvents = filterAfkEvents(rawEvents, afkEvents);
        }
    }

    // 5. Filter Noise (Short events)
    rawEvents = filterNoiseEvents(rawEvents);

    if (rawEvents.length === 0) {
        log("No events remained after filtering.");
        recordSyncEvent(scriptStartTime, 0);
        return;
    }

    // 6. Merge
    const merged = mergeEvents(rawEvents);
    log(`Merged into ${merged.length} events.`);

    // 7. Insert
    log("Inserting into Calendar...");
    let count = 0;

    merged.forEach(m => {
        const durationSec = (m.end - m.start) / 1000;
        if (durationSec < MIN_DURATION_SEC) return; // Skip short

        const titleStr = m.titles.join("\n- ");

        const props = {
            summary: `${m.app} | ${Math.round(durationSec / 60)}m`,
            startDate: m.start,
            endDate: m.end,
            description: `Titles:\n- ${titleStr}`
        };

        try {
            const newEvent = Calendar.Event(props);
            targetCal.events.push(newEvent);
            count++;
        } catch (e) {
            log("Error creating event: " + e.message);
        }
    });

    log(`Done. Created ${count} events.`);

    // 8. Record Sync
    // We record the scriptStartTime as the new 'anchor'
    recordSyncEvent(scriptStartTime, count);
}
