.pragma library

var API_URL = "https://paceman.gg/api/ars/liveruns"
var SITE_URL = "https://paceman.gg/"
var STALE_AFTER_MS = 30000
var FORGET_WORLD_AFTER_MS = 60000

var EVENT_NAMES = ({
  "rsg.enter_nether": "Enter Nether",
  "rsg.enter_bastion": "Enter Bastion",
  "rsg.enter_fortress": "Enter Fortress",
  "rsg.first_portal": "First Portal",
  "rsg.second_portal": "Second Portal",
  "rsg.enter_stronghold": "Enter Stronghold",
  "rsg.enter_end": "Enter End",
  "rsg.credits": "Finish",
  "rsg.killed_blaze": "Killed Blaze",
  "rsg.tower_start": "Tower Start",
  "rsg.break_underground_bookshelf": "Enter Library",
  "rsg.obtain_gold_block": "Loot Monument",
  "rsg.trade": "Villager Trade"
})

var EVENT_ORDER = ({
  "rsg.enter_nether": 0,
  "rsg.enter_bastion": 1,
  "rsg.enter_fortress": 2,
  "rsg.first_portal": 3,
  "rsg.second_portal": 4,
  "rsg.enter_stronghold": 5,
  "rsg.enter_end": 6,
  "rsg.credits": 7,
  "rsg.killed_blaze": 2,
  "rsg.tower_start": 3,
  "rsg.break_underground_bookshelf": 6,
  "rsg.obtain_gold_block": -2,
  "rsg.trade": -1
})

var STANDARD_EVENTS = [
  "rsg.enter_nether",
  "rsg.enter_bastion",
  "rsg.enter_fortress",
  "rsg.first_portal",
  "rsg.second_portal",
  "rsg.enter_stronghold",
  "rsg.enter_end",
  "rsg.credits"
]

var GAME_VERSIONS = [
  "1.16.1", "All", "1.15.2", "1.8.9", "1.14.4", "1.12.2",
  "1.16.5", "1.17.1", "1.8", "1.12", "1.3.1", "1.4.2", "1.4.7",
  "1.5.2", "1.6.4", "1.7.2", "1.7.4", "1.9.4", "1.10.2",
  "1.11.2", "1.18.1", "1.18.2", "1.19.2", "1.19.4", "1.20.4",
  "1.20.6", "1.21", "1.13.2"
]

var THRESHOLD_KEYS = ({
  "rsg.enter_nether": "thresholdNether",
  "rsg.enter_bastion": "thresholdBastion",
  "rsg.enter_fortress": "thresholdFortress",
  "rsg.first_portal": "thresholdFirstPortal",
  "rsg.second_portal": "thresholdSecondPortal",
  "rsg.enter_stronghold": "thresholdStronghold",
  "rsg.enter_end": "thresholdEnd",
  "rsg.credits": "thresholdFinish"
})

var THRESHOLD_ENABLED_KEYS = ({
  "rsg.enter_nether": "notifyThresholdNether",
  "rsg.enter_bastion": "notifyThresholdBastion",
  "rsg.enter_fortress": "notifyThresholdFortress",
  "rsg.first_portal": "notifyThresholdFirstPortal",
  "rsg.second_portal": "notifyThresholdSecondPortal",
  "rsg.enter_stronghold": "notifyThresholdStronghold",
  "rsg.enter_end": "notifyThresholdEnd",
  "rsg.credits": "notifyThresholdFinish"
})

var DEFAULT_THRESHOLDS = ({
  thresholdNether: "02:00",
  thresholdBastion: "04:30",
  thresholdFortress: "04:30",
  thresholdFirstPortal: "06:00",
  thresholdSecondPortal: "07:00",
  thresholdStronghold: "07:30",
  thresholdEnd: "08:00",
  thresholdFinish: "10:00"
})

function apiUrl(gameVersion, liveOnly) {
  return API_URL
    + "?gameVersion=" + encodeURIComponent(String(gameVersion || "1.16.1"))
    + "&liveOnly=" + (liveOnly ? "true" : "false")
}

function gameVersionOptions() {
  var out = []
  for (var i = 0; i < GAME_VERSIONS.length; i++)
    out.push({ value: GAME_VERSIONS[i], label: GAME_VERSIONS[i] })
  return out
}

function thresholdSettings() {
  var out = []
  for (var i = 0; i < STANDARD_EVENTS.length; i++) {
    var eventId = STANDARD_EVENTS[i]
    var key = THRESHOLD_KEYS[eventId]
    out.push({
      key: key,
      enabledKey: THRESHOLD_ENABLED_KEYS[eventId],
      label: EVENT_NAMES[eventId],
      defaultValue: DEFAULT_THRESHOLDS[key]
    })
  }
  return out
}

function eventName(eventId) {
  return EVENT_NAMES[String(eventId || "")] || ""
}

function eventIndex(eventId) {
  var key = String(eventId || "")
  return EVENT_ORDER[key] === undefined ? -999 : EVENT_ORDER[key]
}

function isStandardEvent(eventId) {
  return STANDARD_EVENTS.indexOf(String(eventId || "")) >= 0
}

function parsePaces(raw, favorites, favoritesOnly) {
  var data = raw
  if (typeof raw === "string") {
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return null
    }
  }
  if (!Array.isArray(data)) return null

  var favoriteNames = normalizeFavorites(favorites)
  var runs = []
  for (var i = 0; i < data.length; i++) {
    var run = normalizeRun(data[i], favoriteNames)
    if (!run) continue
    if (favoritesOnly && !run.isFavorite) continue
    runs.push(run)
  }
  runs.sort(paceSort)
  return runs
}

function normalizeRun(raw, favoriteNames) {
  if (!raw || typeof raw !== "object" || raw.isCheated || raw.isHidden) return null
  if (!Array.isArray(raw.eventList) || raw.eventList.length === 0) return null

  var events = []
  for (var i = 0; i < raw.eventList.length; i++) {
    var event = normalizeEvent(raw.eventList[i])
    if (event) events.push(event)
  }
  if (events.length === 0) return null

  var latest = events[events.length - 1]
  if (eventName(latest.eventId) === "") return null

  var nickname = String(raw.nickname || "").trim()
  var worldId = String(raw.worldId || "").trim()
  if (nickname === "" || worldId === "") return null

  var user = raw.user && typeof raw.user === "object" ? raw.user : {}
  var gameVersion = String(raw.gameVersion || "")

  return {
    worldId: worldId,
    nickname: nickname,
    nicknameKey: nickname.toLowerCase(),
    uuid: String(user.uuid || ""),
    twitch: user.liveAccount ? String(user.liveAccount) : "",
    gameVersion: gameVersion,
    eventList: events,
    latestEvent: latest,
    split: eventIndex(latest.eventId),
    splitName: eventName(latest.eventId),
    time: latest.igt,
    lastUpdated: finiteNumber(raw.lastUpdated, 0),
    isHighQuality: isHighQualityPace(gameVersion, events, latest),
    isFavorite: favoriteNames.indexOf(nickname.toLowerCase()) >= 0,
    itemEstimates: raw.itemData && raw.itemData.estimatedCounts
      ? raw.itemData.estimatedCounts : null
  }
}

function normalizeEvent(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = String(raw.eventId || "")
  if (eventName(id) === "") return null
  var igt = finiteNumber(raw.igt, -1)
  if (igt < 0) return null
  return {
    eventId: id,
    name: eventName(id),
    igt: igt,
    rta: finiteNumber(raw.rta, igt)
  }
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function isHighQualityPace(gameVersion, events, latestEvent) {
  if (String(gameVersion) !== "1.16.1" || !latestEvent) return false
  if (events.length === 3) return latestEvent.igt <= 270000
  if (latestEvent.eventId === "rsg.first_portal") return latestEvent.igt <= 360000
  if (latestEvent.eventId === "rsg.enter_stronghold") return latestEvent.igt <= 450000
  if (latestEvent.eventId === "rsg.enter_end") return latestEvent.igt <= 480000
  if (latestEvent.eventId === "rsg.credits") return latestEvent.igt <= 600000
  return false
}

function paceSort(a, b) {
  if (a.isFavorite !== b.isFavorite) return a.isFavorite ? -1 : 1
  if (a.gameVersion !== b.gameVersion) {
    if (a.gameVersion === "1.16.1") return -1
    if (b.gameVersion === "1.16.1") return 1
    return a.gameVersion < b.gameVersion ? -1 : 1
  }
  if (a.isHighQuality !== b.isHighQuality) return a.isHighQuality ? -1 : 1

  var structure = eventIndex("rsg.enter_fortress")
  var bastion = eventIndex("rsg.enter_bastion")
  if (a.split === structure || b.split === structure
      || a.split === bastion || b.split === bastion) {
    if (a.eventList.length !== b.eventList.length)
      return b.eventList.length - a.eventList.length
  } else if (a.split !== b.split) {
    return b.split - a.split
  }
  if (a.time !== b.time) return a.time - b.time
  return a.nicknameKey < b.nicknameKey ? -1 : (a.nicknameKey > b.nicknameKey ? 1 : 0)
}

function normalizeFavorites(value) {
  var values = Array.isArray(value) ? value : String(value || "").split(",")
  var out = []
  for (var i = 0; i < values.length; i++) {
    var name = String(values[i] || "").trim().toLowerCase()
    if (name !== "" && out.indexOf(name) < 0) out.push(name)
  }
  return out
}

function favoriteDisplayNames(value) {
  var values = Array.isArray(value) ? value : String(value || "").split(",")
  var out = []
  var seen = []
  for (var i = 0; i < values.length; i++) {
    var name = String(values[i] || "").trim()
    var key = name.toLowerCase()
    if (name !== "" && seen.indexOf(key) < 0) {
      seen.push(key)
      out.push(name)
    }
  }
  return out
}

function addFavorite(value, nickname) {
  var names = favoriteDisplayNames(value)
  var name = String(nickname || "").trim()
  if (name === "") return names.join(", ")
  var keys = normalizeFavorites(names)
  if (keys.indexOf(name.toLowerCase()) < 0) names.push(name)
  return names.join(", ")
}

function removeFavorite(value, nickname) {
  var names = favoriteDisplayNames(value)
  var key = String(nickname || "").trim().toLowerCase()
  var out = []
  for (var i = 0; i < names.length; i++)
    if (names[i].toLowerCase() !== key) out.push(names[i])
  return out.join(", ")
}

function toggleFavorite(value, nickname) {
  var raw = Array.isArray(value) ? value.slice() : String(value || "").split(",")
  var out = []
  var key = String(nickname || "").trim().toLowerCase()
  var found = false

  for (var i = 0; i < raw.length; i++) {
    var display = String(raw[i] || "").trim()
    if (display === "") continue
    if (display.toLowerCase() === key) {
      found = true
      continue
    }
    if (normalizeFavorites(out).indexOf(display.toLowerCase()) < 0) out.push(display)
  }
  if (!found && key !== "") out.push(String(nickname).trim())
  return out.join(", ")
}

function parseThreshold(value) {
  if (value === undefined || value === null) return 0
  if (typeof value === "number") return value > 0 && isFinite(value)
    ? Math.round(value * 1000) : 0

  var text = String(value).trim()
  if (text === "" || text === "0") return 0
  if (/^\d+$/.test(text)) return Number(text) * 1000

  var parts = text.split(":")
  if (parts.length < 2 || parts.length > 3) return 0
  var total = 0
  for (var i = 0; i < parts.length; i++) {
    if (!/^\d+$/.test(parts[i])) return 0
    var number = Number(parts[i])
    if (i > 0 && number >= 60) return 0
    total = total * 60 + number
  }
  return total > 0 ? total * 1000 : 0
}

function alertConfig(settings) {
  var source = settings || {}
  var thresholds = ({})
  for (var eventId in THRESHOLD_KEYS) {
    var key = THRESHOLD_KEYS[eventId]
    var enabledKey = THRESHOLD_ENABLED_KEYS[eventId]
    var value = source[key]
    if (value === undefined || value === null) value = DEFAULT_THRESHOLDS[key]
    thresholds[eventId] = source[enabledKey] === false
      ? 0 : parseThreshold(value)
  }
  return {
    notifyStreamingOnly: source.notifyStreamingOnly === true,
    notifyFavorites: source.notifyFavorites !== false,
    notifyHighQuality: source.notifyHighQuality !== false,
    notifyThresholds: source.notifyThresholds !== false,
    thresholds: thresholds
  }
}

function emptyAlertState() {
  return { hydrated: false, worlds: ({}) }
}

function transitionAlerts(previous, runs, config, nowMs) {
  var previousState = previous && previous.worlds ? previous : emptyAlertState()
  var now = finiteNumber(nowMs, Date.now())
  var nextWorlds = ({})
  var alerts = []
  var currentRuns = Array.isArray(runs) ? runs : []
  var options = config || alertConfig({})

  for (var i = 0; i < currentRuns.length; i++) {
    var run = currentRuns[i]
    var old = previousState.worlds[run.worldId] || null
    var knownEvents = old && old.events ? old.events : ({})
    var nextEvents = ({})
    for (var k in knownEvents) nextEvents[k] = true

    var newEvents = []
    for (var e = 0; e < run.eventList.length; e++) {
      var event = run.eventList[e]
      if (!nextEvents[event.eventId]) newEvents.push(event)
      nextEvents[event.eventId] = true
    }

    nextWorlds[run.worldId] = {
      nickname: run.nickname,
      lastSeenAt: now,
      events: nextEvents
    }

    if (!previousState.hydrated) continue
    if (options.notifyStreamingOnly && !run.twitch) continue

    var favoriteStart = !old && run.isFavorite && options.notifyFavorites
    var candidates = old ? newEvents : (run.eventList.length
      ? [run.eventList[run.eventList.length - 1]] : [])

    if (candidates.length === 0 && favoriteStart) {
      alerts.push(buildAlert(run, null, ["favorite"]))
      continue
    }

    for (var c = 0; c < candidates.length; c++) {
      var candidate = candidates[c]
      var reasons = []
      if (favoriteStart && c === candidates.length - 1) reasons.push("favorite")
      var threshold = options.thresholds ? options.thresholds[candidate.eventId] : 0
      if (options.notifyThresholds && threshold > 0 && candidate.igt <= threshold)
        reasons.push("threshold")
      if (options.notifyHighQuality
          && isHighQualityPace(run.gameVersion, run.eventList, candidate))
        reasons.push("quality")
      if (reasons.length > 0) alerts.push(buildAlert(run, candidate, reasons))
    }
  }

  for (var worldId in previousState.worlds) {
    if (nextWorlds[worldId]) continue
    var previousWorld = previousState.worlds[worldId]
    if (now - finiteNumber(previousWorld.lastSeenAt, 0) <= FORGET_WORLD_AFTER_MS)
      nextWorlds[worldId] = previousWorld
  }

  return {
    alerts: alerts,
    state: { hydrated: true, worlds: nextWorlds }
  }
}

function buildAlert(run, event, reasons) {
  var labels = []
  if (reasons.indexOf("favorite") >= 0) labels.push("favorite runner")
  if (reasons.indexOf("threshold") >= 0) labels.push("under threshold")
  if (reasons.indexOf("quality") >= 0) labels.push("high-quality pace")

  var body = event
    ? event.name + " at " + formatTime(event.igt)
    : run.splitName + " at " + formatTime(run.time)
  if (labels.length > 0) body += " · " + labels.join(" · ")

  return {
    worldId: run.worldId,
    eventId: event ? event.eventId : "start",
    title: run.nickname + " is on pace",
    body: body,
    url: run.twitch
      ? "https://twitch.tv/" + encodeURIComponent(run.twitch)
      : SITE_URL + "stats/player/" + encodeURIComponent(run.nickname),
    actionLabel: run.twitch ? "Watch live" : "Open PaceMan profile"
  }
}

function notificationArgs(alert, iconPath) {
  if (!alert) return null
  var notificationKey = (String(alert.worldId || "pace")
    + "_" + String(alert.eventId || "event"))
    .replace(/[^A-Za-z0-9_.-]/g, "_")
  return [
    "sh", "-c",
    "runtime=\"${XDG_RUNTIME_DIR:-/tmp}/omarchy-paceman\";"
      + " mkdir -p \"$runtime\";"
      + " exec 9>\"$runtime/notifications.lock\";"
      + " flock -x 9;"
      + " stamp=\"$runtime/$6\";"
      + " now=$(date +%s);"
      + " last=$(cat \"$stamp\" 2>/dev/null || echo 0);"
      + " if [ $((now-last)) -lt 120 ]; then exit 0; fi;"
      + " printf '%s\\n' \"$now\" > \"$stamp\";"
      + " flock -u 9;"
      + " choice=$(notify-send --app-name=PaceMan \"--icon=$5\""
      + " --expire-time=10000 \"--action=open=$4\" \"$1\" \"$2\");"
      + " if [ \"$choice\" = open ]; then"
      + " exec omarchy-launch-browser \"$3\"; fi",
    "paceman-notification",
    String(alert.title || "PaceMan"),
    String(alert.body || ""),
    String(alert.url || SITE_URL),
    String(alert.actionLabel || "Open PaceMan"),
    String(iconPath || "applications-games"),
    notificationKey
  ]
}

function formatTime(ms, tenths) {
  var value = Math.max(0, Math.floor(finiteNumber(ms, 0)))
  var totalSeconds = Math.floor(value / 1000)
  var hours = Math.floor(totalSeconds / 3600)
  var minutes = Math.floor((totalSeconds % 3600) / 60)
  var seconds = totalSeconds % 60
  var text = pad2(minutes) + ":" + pad2(seconds)
  if (hours > 0) text = pad2(hours) + ":" + text
  if (tenths) text += "." + Math.floor((value % 1000) / 100)
  return text
}

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function estimatedTime(run, nowMs) {
  if (!run) return 0
  var delta = Math.max(0, finiteNumber(nowMs, Date.now()) - finiteNumber(run.lastUpdated, 0))
  return Math.max(0, finiteNumber(run.time, 0) + delta)
}

function normalizeRefreshInterval(value) {
  return Math.max(2, Math.min(60, Math.round(finiteNumber(value, 15))))
}

function freshnessLabel(lastSuccessAt, nowMs, loading, error) {
  if (!lastSuccessAt) return loading ? "Connecting" : (error ? "Unavailable" : "Not connected")
  var age = Math.max(0, finiteNumber(nowMs, Date.now()) - lastSuccessAt)
  if (age >= STALE_AFTER_MS) return "Stale · " + ageLabel(age)
  if (age < 2000) return "Updated just now"
  return "Updated " + ageLabel(age) + " ago"
}

function ageLabel(ms) {
  var seconds = Math.max(0, Math.floor(ms / 1000))
  if (seconds < 2) return "now"
  if (seconds < 60) return seconds + "s"
  var minutes = Math.floor(seconds / 60)
  return minutes + "m"
}

function highQualityCount(runs) {
  var count = 0
  var values = Array.isArray(runs) ? runs : []
  for (var i = 0; i < values.length; i++) if (values[i].isHighQuality) count++
  return count
}

function favoriteCount(runs) {
  var count = 0
  var values = Array.isArray(runs) ? runs : []
  for (var i = 0; i < values.length; i++) if (values[i].isFavorite) count++
  return count
}

function settingArgs(moduleName, key, value) {
  return [
    "omarchy-shell", "-q", "shell", "setBarWidget",
    String(moduleName), String(key), JSON.stringify(value), "{}"
  ]
}

function runnerProfileUrl(run) {
  return SITE_URL + "stats/player/" + encodeURIComponent(run ? run.nickname : "")
}

function twitchUrl(run) {
  return run && run.twitch
    ? "https://twitch.tv/" + encodeURIComponent(run.twitch) : ""
}

function barIcon() {
  return "\u{F0373}"
}
