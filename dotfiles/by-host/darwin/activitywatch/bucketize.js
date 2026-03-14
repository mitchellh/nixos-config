/**
 * ActivityWatch to Apple Calendar Sync Engine (Optimized JXA/EventKit)
 * ===================================================================
 * 
 * OVERVIEW:
 * This script serves as an automated ETL (Extract, Transform, Load) pipeline that synchronizes
 * high-resolution time-tracking data from ActivityWatch into human-readable, 15-minute
 * block entries in Apple Calendar (macOS). It is designed to run unattended (e.g., via launchd)
 * and uses the native EventKit framework for high-performance batch operations.
 * 
 * CORE OBJECTIVES:
 * 1. Data Aggregation: Merges disparate event streams (Desktop window titles, iOS app usage)
 *    into a single timeline, handling overlaps with device precedence (MacBook > iPhone).
 * 
 * 2. Intelligent Categorization: Transforms raw app usage (e.g., "VS Code", "TikTok") into
 *    high-level calendar categories (e.g., "Work", "Media") based on user-defined Regex rules.
 * 
 * 3. "Time Bucketing" & Grid Alignment:
 *    - Implements au"Majority Vote" algorithm to assign 15-minute time slots to the
 *      dominant activity category (e.g., 8 mins Work + 7 mins Media = 15 mins Work).
 *    - Aligns blocks to strict :00, :15, :30, :45 intervals for visual clarity.
 *    - Applies "Gapped" formatting (+1m start / -1m end) to create visual breathing room.
 *    - Aggregates metadata: A 30-min "Media" block lists all contributing apps (e.g., "YouTube, Twitch")
 *      in the title and detailed video titles in the description.
 * 
 * 4. Idempotent Synchronization (State Reconciliation):
 *    - Operates on a rolling window (default: past 14 days).
 *    - Fetches current calendar state via EventKit predicates (fast native fetch).
 *    - Reconciles state by comparing computed blocks against existing calendar events.
 *    - Performs minimal-diff updates: Creates missing events, updates changed descriptions/times,
 *      and deletes obsolete events (orphans) to ensure 1:1 parity without duplicates.
 * 
 * 5. Performance Optimization:
 *    - Bypasses slow JXA/AppleScript object iteration in favor of the ObjC-bridged `EventKit` API.
 *    - Uses batch processing for fetching and transactional commits for writing to reduce IPC overhead.
 * 
 * EXECUTION CONTEXT:
 * - Environment: macOS JavaScript for Automation (JXA).
 * - Bridge: Requires ObjC import of 'EventKit' and 'Foundation'.
 * - API: Connects to local ActivityWatch instance (localhost:5600).
 * 
 * @param {string[]} input - JXA standard input (unused).
 * @param {object} parameters - JXA standard parameters (unused).
 * @returns {string} - Execution summary stats (Created/Updated/Deleted counts).
 */



ObjC.import('Foundation')
ObjC.import('EventKit')
ObjC.import('Cocoa')

const API_BASE = "http://localhost:5600/api/0";
const SYNC_DAYS = 14; // Sync past 14 days

// Configuration: Map categories to calendar names
const CATEGORY_CALENDAR_MAP = {
    "Work": "[㏒:🧑🏻‍💻] Work/Productivity",
    "Productivity": "[㏒:🧑🏻‍💻] Work/Productivity",
    "Trading": "[㏒:🧑🏻‍💻] Work/Productivity",
    "Web browsing": "[㏒:🧑🏻‍💻] Work/Productivity", // temporary catch-all
    "Finances & Buying shit": "[㏒:🧑🏻‍💻] Work/Productivity",
    "Media": "[㏒:🧑🏻‍💻] Dopamine",
    "Comms": "[㏒:🧑🏻‍💻] Communications",
    "Learning": "[㏒:🧑🏻‍💻] Learning",
    "Uncategorized": "[㏒:🧑🏻‍💻] FIXME",
    "BS": "[㏒:🧑🏻‍💻] FIXME",
};

const IOS_APP_NAME_PRETTY_MAP = {
    "com.apple.mobilemail": "Mail📱",
    "com.apple.mobilesafari": "Safari📱",
    "com.apple.Preferences": "Settings📱",
    "com.apple.MobileSMS": "Messages📱",
    "com.apple.camera": "Camera📱",
    "com.apple.Music": "Music📱",

    // social media apps
    "com.burbn.instagram": "Instagram📱",
    "com.facebook.Facebook": "Facebook📱",
    "com.snapchat.snapchat": "Snapchat📱",
    "com.twitter.twitter": "Twitter📱",
    "com.zhiliaoapp.musically": "TikTok📱",
    "com.whatsapp.WhatsApp": "WhatsApp📱", 
    "com.linkedin.LinkedIn": "LinkedIn📱",
    "com.reddit.Reddit": "Reddit📱",

    "com.bookfusion.bookfusion": "BookFusion📱",
    "ai.perplexity.app": "Perplexity AI📱",
    "app.journalit.journalIt": "Journal It📱",  
    "com.apple.shortcuts": "Shortcuts📱"
};

// --- MAIN FUNCTION ---            

function run(input, parameters) {
    try {
        console.log("🚀 Starting Optimized Sync...");
        
        // 1. Initialize EventKit Store
        const store = $.EKEventStore.alloc.init;
        
        // --- PERMISSION CHECK START ---
        // Explicitly check/request access. This often triggers the TCC prompt if missing.
        let accessGranted = false;
        
        // macOS 14+ (Sonoma) uses requestFullAccessToEventsCompletion
        if (store.requestFullAccessToEventsCompletion) {
             // We can't use the async completion handler easily in sync JXA.
             // But checking authorizationStatusForEntityType is synchronous.
             const status = $.EKEventStore.authorizationStatusForEntityType($.EKEntityTypeEvent);
             if (status === $.EKAuthorizationStatusAuthorized) accessGranted = true;
             else console.log("⚠️ Calendar Access Status: " + status + " (3=Authorized, 0=NotDetermined, 1=Restricted, 2=Denied)");
        } else {
             // Older macOS
             // We can try to force a request, but in JXA synchronous context, 
             // we usually rely on the app already having permissions.
             const status = $.EKEventStore.authorizationStatusForEntityType($.EKEntityTypeEvent);
             if (status === $.EKAuthorizationStatusAuthorized) accessGranted = true;
        }

        if (!accessGranted) {
            return "❌ Error: Calendar Access Denied. Go to System Settings > Privacy & Security > Calendars and allow Terminal/ScriptEditor.";
        }
        console.log("🚀 Starting Optimized Sync...");
        
        
        // Request Access (Required for JXA on modern macOS)
        // Note: This often requires the app running the script (Script Editor/Terminal) to have Full Disk Access or Calendar Access in System Settings
        let accessErr = $();
        let granted = true; 
        // Modern macOS often handles this silently or via TCC, but explicitly asking is good practice in Swift/ObjC. 
        // In JXA, we assume access or fail later.
        
        // 2. Prepare Date Window
        const now = new Date();
        const startDate = new Date(now.getTime() - (SYNC_DAYS * 24 * 60 * 60 * 1000));
        
        // 3. Parallel-ish Prep: Get Calendars & AW Data
        console.log("📦 Fetching external data...");
        
        const targetCalNames = [...new Set(Object.values(CATEGORY_CALENDAR_MAP))];
        const calendarMap = getCalendarsMap(store, targetCalNames);
        
        // Fetch AW Data
        const awEvents = fetchActivityWatchData(startDate, now);
        
        // 4. Transform AW Data
        console.log(`⚙️  Processing ${awEvents.length} raw records...`);
        const generatedEvents = processByCategoryMajority(awEvents);
        
        // 5. Batch Fetch Existing Events
        console.log("📥 Batch reading existing calendar state...");
        const existingEvents = fetchExistingEventsBatch(store, Object.values(calendarMap), startDate, now);
        
        // 6. Memory Reconcile
        console.log(`⚡️ Reconciling (Gen: ${generatedEvents.length} vs Existing: ${existingEvents.length})...`);
        const stats = reconcileAndSync(store, calendarMap, generatedEvents, existingEvents);

        return `✅ Sync Done (${stats.duration}s)\nCreated: ${stats.created}\nUpdated: ${stats.updated}\nDeleted: ${stats.deleted}\nSkipped: ${stats.unchanged}`;
        
    } catch (e) {
        return "❌ Error: " + e.message + "\n" + e.stack;
    }
}

// --- NATIVE EVENTKIT HELPERS ---
function getCalendarsMap(store, requiredNames) {
    const map = {};
    const allCalendars = store.calendarsForEntityType($.EKEntityTypeEvent);
    
    // 1. Index ALL existing calendars by title (across all sources)
    const count = allCalendars.count;
    const existing = {};
    for (let i = 0; i < count; i++) {
        const cal = allCalendars.objectAtIndex(i);
        // If duplicates exist, this picks the last one found, which is usually fine.
        existing[cal.title.js] = cal;
    }
    
    // 2. Identify Sources
    let defaultSource = store.defaultCalendarForNewEvents ? store.defaultCalendarForNewEvents.source : null;
    let localSource = null;
    
    const sources = store.sources;
    for(let i=0; i<sources.count; i++) {
        const s = sources.objectAtIndex(i);
        if (s.sourceType === $.EKSourceTypeLocal) {
            localSource = s;
            break;
        }
    }
    // Fallback if no local source found (rare)
    if (!localSource && sources.count > 0) localSource = sources.objectAtIndex(0);

    // 3. Get or Create
    requiredNames.forEach(name => {
        if (existing[name]) {
            map[name] = existing[name];
        } else {
            // Try Default Source first, then Local
            const targetSource = defaultSource || localSource;
            console.log(`   Creating calendar '${name}' in source '${targetSource.title.js}'...`);
            
            const newCal = $.EKCalendar.calendarForEntityTypeEventStore($.EKEntityTypeEvent, store);
            newCal.title = name;
            newCal.source = targetSource;
            
            let err = $();
            let success = store.saveCalendarCommitError(newCal, true, err);
            
            // Retry Logic: If failed on Default, force Local
            if (!success && targetSource !== localSource && localSource) {
                console.log(`   ⚠️ Creation failed in '${targetSource.title.js}'. Retrying in Local source...`);
                newCal.source = localSource;
                err = $(); // Reset error
                success = store.saveCalendarCommitError(newCal, true, err);
            }

            if (!success) {
                let errorMsg = "Unknown Error";
                try { if (err[0]) errorMsg = err[0].localizedDescription.js; } catch(e){}
                throw new Error(`Failed to create calendar '${name}': ${errorMsg}`);
            }
            map[name] = newCal;
        }
    });
    
    return map;
}


function fetchExistingEventsBatch(store, calendars, startDate, endDate) {
    const nsStart = $.NSDate.dateWithTimeIntervalSince1970(startDate.getTime() / 1000);
    const nsEnd = $.NSDate.dateWithTimeIntervalSince1970(endDate.getTime() / 1000);
    
    const calArray = $.NSMutableArray.array;
    calendars.forEach(c => calArray.addObject(c));
    
    const predicate = store.predicateForEventsWithStartDateEndDateCalendars(nsStart, nsEnd, calArray);
    
    const nsEvents = store.eventsMatchingPredicate(predicate);
    const count = nsEvents.count;
    const events = [];
    
    for (let i = 0; i < count; i++) {
        const ev = nsEvents.objectAtIndex(i);
        events.push({
            id: ev.eventIdentifier.js,
            title: ev.title.js,
            desc: ev.notes ? ev.notes.js : "",
            start: ev.startDate.timeIntervalSince1970 * 1000,
            end: ev.endDate.timeIntervalSince1970 * 1000,
            calName: ev.calendar.title.js,
            nativeObj: ev 
        });
    }
    return events;
}

// --- RECONCILIATION & SYNC ---

function reconcileAndSync(store, calendarMap, generated, existing) {
    let stats = { created: 0, updated: 0, deleted: 0, unchanged: 0, duration: 0 };
    const tStart = new Date();
    
    const existingMap = new Map();
    existing.forEach(ev => {
        // Round times to nearest second to avoid float drift issues
        const startSec = Math.floor(ev.start / 1000);
        const key = `${ev.calName}|${ev.title}|${startSec}`;
        existingMap.set(key, ev);
    });
    
    const touchedIds = new Set();
    
    generated.forEach(gen => {
        const calName = CATEGORY_CALENDAR_MAP[gen.categoryName] || "Time Log: FIXME";
        const startSec = Math.floor(gen.startDate.getTime() / 1000);
        const key = `${calName}|${gen.title}|${startSec}`;
        
        if (existingMap.has(key)) {
            const ex = existingMap.get(key);
            touchedIds.add(ex.id);
            
            // Check Update
            const endDiff = Math.abs(ex.end - gen.endDate.getTime());
            
            if (endDiff > 2000 || ex.desc !== gen.description) { // 2s tolerance
                const nsEv = ex.nativeObj;
                nsEv.notes = gen.description;
                nsEv.endDate = $.NSDate.dateWithTimeIntervalSince1970(gen.endDate.getTime() / 1000);
                
                let err = $();
                store.saveEventSpanCommitError(nsEv, $.EKSpanThisEvent, false, err);
                stats.updated++;
            } else {
                stats.unchanged++;
            }
        } else {
            // Create New
            const nsEv = $.EKEvent.eventWithEventStore(store);
            nsEv.title = gen.title;
            nsEv.notes = gen.description;
            nsEv.startDate = $.NSDate.dateWithTimeIntervalSince1970(gen.startDate.getTime() / 1000);
            nsEv.endDate = $.NSDate.dateWithTimeIntervalSince1970(gen.endDate.getTime() / 1000);
            nsEv.calendar = calendarMap[calName];
            
            let err = $();
            const success = store.saveEventSpanCommitError(nsEv, $.EKSpanThisEvent, false, err);
            if(success) stats.created++;
            else console.log("Failed to create event: " + gen.title);
        }
    });
    
    // Process Deletes
    existing.forEach(ex => {
        if (!touchedIds.has(ex.id)) {
            let err = $();
            store.removeEventSpanCommitError(ex.nativeObj, $.EKSpanThisEvent, false, err);
            stats.deleted++;
        }
    });
    
    // Final Commit
    let err = $();
    const commitSuccess = store.commit(err);
    if (!commitSuccess && err[0]) console.log("Commit Error: " + err[0].localizedDescription.js);
    
    stats.duration = (new Date() - tStart) / 1000;
    return stats;
}

// --- DATA PROCESSING (Optimized) ---

function processByCategoryMajority(events) {
    const SLOT_SIZE = 15 * 60 * 1000;
    const slots = new Map();
    const getSlotStart = (ms) => ms - (ms % SLOT_SIZE);

    for (const event of events) {
        const start = new Date(event.timestamp).getTime();
        const end = start + (event.duration * 1000);
        let current = start;
        const catName = (event.data.$category && event.data.$category[0]) || "Uncategorized";
        const appName = event.data.app || "Unknown";
        const title = event.data.title;

        while (current < end) {
            const slotStart = getSlotStart(current);
            const slotEnd = slotStart + SLOT_SIZE;
            const overlap = Math.min(end, slotEnd) - Math.max(start, slotStart);

            if (overlap > 0) {
                if (!slots.has(slotStart)) slots.set(slotStart, { total: 0, cats: {} });
                const slot = slots.get(slotStart);
                
                if (!slot.cats[catName]) slot.cats[catName] = { dur: 0, apps: new Set(), details: [] };
                
                const c = slot.cats[catName];
                c.dur += overlap;
                c.apps.add(IOS_APP_NAME_PRETTY_MAP[appName] || appName);
                if (title) c.details.push(title);
                slot.total += overlap;
            }
            current = slotEnd;
        }
    }

    const sortedKeys = Array.from(slots.keys()).sort((a,b) => a - b);
    const finalBlocks = [];

    for (const key of sortedKeys) {
        const slot = slots.get(key);
        if (slot.total < 3 * 60 * 1000) continue; 

        let winner = null, max = -1;
        for (const c in slot.cats) {
            if (slot.cats[c].dur > max) { max = slot.cats[c].dur; winner = c; }
        }

        const winData = slot.cats[winner];
        finalBlocks.push({
            start: key,
            end: key + SLOT_SIZE,
            cat: winner,
            apps: Array.from(winData.apps),
            details: winData.details
        });
    }

    if (finalBlocks.length === 0) return [];
    
    const merged = [];
    let curr = finalBlocks[0];

    for (let i = 1; i < finalBlocks.length; i++) {
        const next = finalBlocks[i];
        const currCalendar = CATEGORY_CALENDAR_MAP[curr.cat] || "[LOG] FIXME";
        const nextCalendar = CATEGORY_CALENDAR_MAP[next.cat] || "[LOG] FIXME";
        
        if (next.start === curr.end && nextCalendar === currCalendar) {
            curr.end = next.end;
            next.apps.forEach(a => { if(!curr.apps.includes(a)) curr.apps.push(a) });
            curr.details = curr.details.concat(next.details);
        } else {
            merged.push(formatEvent(curr));
            curr = next;
        }
    }
    merged.push(formatEvent(curr));
    return merged;
}

function formatEvent(b) {
    const uniqueDetails = [...new Set(b.details)];
    const desc = uniqueDetails.join("\n");
    return {
        title: b.apps.join(", "),
        description: desc,
        categoryName: b.cat,
        startDate: new Date(b.start + 60000), 
        endDate: new Date(b.end - 60000)
    };
}

// --- AW API ---

function fetchActivityWatchData(start, end) {
    const makeReq = (url, body, method="POST") => {
        const req = $.NSMutableURLRequest.requestWithURL($.NSURL.URLWithString(url));
        req.setHTTPMethod(method);
        req.setValueForHTTPHeaderField("application/json", "Content-Type");
        req.setValueForHTTPHeaderField("application/json", "Accept");
        if(body) req.setHTTPBody($.NSString.alloc.initWithUTF8String(JSON.stringify(body)).dataUsingEncoding($.NSUTF8StringEncoding));
        
        let err = $();
        const data = $.NSURLConnection.sendSynchronousRequestReturningResponseError(req, $(), err);
        if(err[0]) throw new Error(err[0].localizedDescription.js);
        return JSON.parse($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js);
    };

    // 1. Get Classes
    const classJson = makeReq(`${API_BASE}/settings/classes`, null, "GET");
    const catArr = classJson.filter(i => i.rule.type !== "none").map(i => [i.name, i.rule]);

    // 2. Resolve bucket IDs at runtime to avoid hardcoded host/device identifiers.
    const buckets = makeReq(`${API_BASE}/buckets/`, null, "GET");
    const bucketIds = Object.keys(buckets);
    const runtimeHostname = $.NSProcessInfo.processInfo.hostName.js || "";
    const runtimeHostnames = Array.from(new Set([
        runtimeHostname,
        runtimeHostname.split(".")[0]
    ].filter(Boolean)));
    const findBucketId = (label, matchers) => {
        for (const matcher of matchers) {
            const bucketId = bucketIds.find(matcher);
            if (bucketId) return bucketId;
        }
        throw new Error(`ActivityWatch bucket not found for ${label}`);
    };
    const macbookAfkBucketId = findBucketId("macbook afk", [
        id => id.startsWith("aw-watcher-afk_") && !id.startsWith("aw-watcher-afk_ios-") && runtimeHostnames.some(host => id.endsWith(host)),
        id => id.startsWith("aw-watcher-afk_") && !id.startsWith("aw-watcher-afk_ios-")
    ]);
    const macbookWindowBucketId = findBucketId("macbook window", [
        id => id.startsWith("aw-watcher-window_") && !id.startsWith("aw-watcher-window_ios-") && runtimeHostnames.some(host => id.endsWith(host)),
        id => id.startsWith("aw-watcher-window_") && !id.startsWith("aw-watcher-window_ios-")
    ]);
    const phoneAfkBucketId = findBucketId("ios afk", [
        id => id.startsWith("aw-watcher-afk_ios-")
    ]);
    const phoneWindowBucketId = findBucketId("ios window", [
        id => id.startsWith("aw-watcher-window_ios-")
    ]);
    
    // 3. Query
    const query = {
        "timeperiods": [`${formatDateForAW(start)}/${formatDateForAW(end)}`],
        "query": [
            `macbook_afk_events = query_bucket(find_bucket('${macbookAfkBucketId}'));`,
            `macbook_window_events = query_bucket(find_bucket('${macbookWindowBucketId}'));`,
            "macbook_window_events = filter_period_intersect(macbook_window_events, filter_keyvals(macbook_afk_events, 'status', ['not-afk']));",

            `phone_afk_events = query_bucket(find_bucket('${phoneAfkBucketId}'));`,
            `phone_events = query_bucket(find_bucket('${phoneWindowBucketId}'));`,
            "phone_events = filter_period_intersect(phone_events, filter_keyvals(phone_afk_events, 'status', ['not-afk']));",

            "events = union_no_overlap(macbook_window_events, phone_events);", 
          //  "events = merge_events_by_keys(events, ['app','title']);",
            `events = categorize(events, ${JSON.stringify(catArr)});`,
            "RETURN = sort_by_timestamp(events);"
        ]
    };
    
    const res = makeReq(`${API_BASE}/query/`, query);
    return res[0];
}

function formatDateForAW(date) {
    const pad = n => String(n).padStart(2,'0');
    const off = -date.getTimezoneOffset();
    const sign = off >= 0 ? '+' : '-';
    const offH = pad(Math.floor(Math.abs(off)/60));
    const offM = pad(Math.abs(off)%60);
    return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}${sign}${offH}:${offM}`;
}
