import QtQuick
import QtTest
import "../../Model.js" as Model

Item {
  function event(id, time) {
    return { eventId: id, igt: time, rta: time + 100 }
  }

  function rawRun(worldId, nickname, events, extras) {
    var run = {
      worldId: worldId,
      nickname: nickname,
      gameVersion: "1.16.1",
      eventList: events,
      user: {
        uuid: "00000000-0000-0000-0000-000000000000",
        liveAccount: null
      },
      isCheated: false,
      isHidden: false,
      lastUpdated: 1000000
    }
    extras = extras || {}
    for (var key in extras) run[key] = extras[key]
    return run
  }

  function parsedRun(worldId, nickname, events, favorites) {
    return Model.parsePaces(
      [rawRun(worldId, nickname, events)], favorites || "", false)[0]
  }

  TestCase {
    name: "PaceManParsing"

    function test_invalid_json_is_not_an_empty_board() {
      compare(Model.parsePaces("{", "", false), null)
      compare(Model.parsePaces({}, "", false), null)
    }

    function test_hidden_and_cheated_runs_are_removed() {
      var nether = [event("rsg.enter_nether", 100000)]
      var data = [
        rawRun("visible", "Visible", nether),
        rawRun("hidden", "Hidden", nether, { isHidden: true }),
        rawRun("cheated", "Cheated", nether, { isCheated: true })
      ]
      var runs = Model.parsePaces(data, "", false)
      compare(runs.length, 1)
      compare(runs[0].worldId, "visible")
    }

    function test_unknown_latest_events_do_not_create_blank_rows() {
      var run = rawRun("world", "Runner", [
        event("rsg.enter_nether", 100000),
        { eventId: "unknown.event", igt: 120000, rta: 120000 }
      ])
      var runs = Model.parsePaces([run], "", false)
      compare(runs.length, 1)
      compare(runs[0].splitName, "Enter Nether")
    }

    function test_favorites_are_case_insensitive_and_pinned() {
      var nether = [event("rsg.enter_nether", 100000)]
      var runs = Model.parsePaces([
        rawRun("a", "Fast", nether),
        rawRun("b", "Favorite", [event("rsg.enter_nether", 119000)])
      ], "fAvOrItE", false)
      compare(runs[0].nickname, "Favorite")
      verify(runs[0].isFavorite)
    }

    function test_favorites_only_is_a_view_filter() {
      var nether = [event("rsg.enter_nether", 100000)]
      var runs = Model.parsePaces([
        rawRun("a", "One", nether),
        rawRun("b", "Two", nether)
      ], "Two", true)
      compare(runs.length, 1)
      compare(runs[0].nickname, "Two")
    }

    function test_current_paceman_quality_rules_are_preserved() {
      var events = [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 180000),
        event("rsg.enter_fortress", 260000)
      ]
      verify(parsedRun("world", "Runner", events).isHighQuality)
      events[2] = event("rsg.enter_fortress", 280000)
      verify(!parsedRun("world", "Runner", events).isHighQuality)
    }
  }

  TestCase {
    name: "PaceManFormatting"

    function test_times_use_stable_clock_widths() {
      compare(Model.formatTime(0), "00:00")
      compare(Model.formatTime(125000), "02:05")
      compare(Model.formatTime(3723000), "01:02:03")
      compare(Model.formatTime(125900, true), "02:05.9")
    }

    function test_thresholds_accept_mm_ss_and_hh_mm_ss() {
      compare(Model.parseThreshold("02:00"), 120000)
      compare(Model.parseThreshold("1:02:03"), 3723000)
      compare(Model.parseThreshold("90"), 90000)
      compare(Model.parseThreshold(""), 0)
      compare(Model.parseThreshold("0"), 0)
      compare(Model.parseThreshold("01:99"), 0)
      compare(Model.parseThreshold("not a time"), 0)
    }

    function test_api_query_is_encoded() {
      compare(Model.apiUrl("1.16.1", false),
              Model.API_URL + "?gameVersion=1.16.1&liveOnly=false")
      verify(Model.apiUrl("All", true).indexOf("liveOnly=true") > 0)
    }

    function test_bar_uses_the_nerd_font_minecraft_mark() {
      compare(Model.barIcon(), "\u{F0373}")
    }

    function test_freshness_uses_natural_just_now_copy() {
      compare(Model.freshnessLabel(1000, 1500, false, ""),
              "Updated just now")
      compare(Model.freshnessLabel(1000, 3000, false, ""),
              "Updated 2s ago")
    }

    function test_refresh_interval_is_bounded() {
      compare(Model.normalizeRefreshInterval("invalid"), 15)
      compare(Model.normalizeRefreshInterval(1), 2)
      compare(Model.normalizeRefreshInterval(17.6), 18)
      compare(Model.normalizeRefreshInterval(90), 60)
    }

    function test_threshold_settings_follow_split_order() {
      var settings = Model.thresholdSettings()
      compare(settings.length, 8)
      compare(settings[0].key, "thresholdNether")
      compare(settings[0].enabledKey, "notifyThresholdNether")
      compare(settings[0].label, "Enter Nether")
      compare(settings[7].key, "thresholdFinish")
      compare(settings[7].defaultValue, "10:00")
    }

    function test_split_alerts_can_be_disabled_without_losing_thresholds() {
      var config = Model.alertConfig({
        thresholdNether: "01:45",
        notifyThresholdNether: false,
        thresholdBastion: "03:30",
        notifyThresholdBastion: true
      })
      compare(config.thresholds["rsg.enter_nether"], 0)
      compare(config.thresholds["rsg.enter_bastion"], 210000)
    }
  }

  TestCase {
    name: "PaceManFavorites"

    function test_toggle_adds_and_removes_without_duplicates() {
      compare(Model.toggleFavorite("", "Runner"), "Runner")
      compare(Model.toggleFavorite("One, Two", "two"), "One")
      compare(Model.toggleFavorite("One, one", "Two"), "One, Two")
    }

    function test_favorite_list_can_add_and_remove_names() {
      compare(Model.addFavorite("One, Two", "Three"), "One, Two, Three")
      compare(Model.addFavorite("One, Two", "two"), "One, Two")
      compare(Model.removeFavorite("One, Two, Three", "TWO"),
              "One, Three")
      compare(Model.favoriteDisplayNames("One, one, TWO").join(","),
              "One,TWO")
    }

    function test_setting_values_are_json_encoded() {
      var stringArgs = Model.settingArgs("nille.paceman", "favoriteRunners", "A, B")
      compare(stringArgs[stringArgs.length - 2], "\"A, B\"")
      compare(stringArgs[stringArgs.length - 1], "{}")

      var boolArgs = Model.settingArgs("nille.paceman", "liveOnly", true)
      compare(boolArgs[boolArgs.length - 2], "true")
    }
  }

  TestCase {
    name: "PaceManAlerts"

    function test_first_snapshot_never_notifies() {
      var run = parsedRun("world", "Favorite",
        [event("rsg.enter_nether", 100000)], "Favorite")
      var transition = Model.transitionAlerts(
        Model.emptyAlertState(), [run], Model.alertConfig({}), 1000)
      compare(transition.alerts.length, 0)
      verify(transition.state.hydrated)
    }

    function test_new_favorite_run_notifies_once() {
      var initial = Model.transitionAlerts(
        Model.emptyAlertState(), [], Model.alertConfig({}), 1000)
      var run = parsedRun("world", "Favorite",
        [event("rsg.enter_nether", 130000)], "Favorite")
      var next = Model.transitionAlerts(
        initial.state, [run], Model.alertConfig({ notifyThresholds: false }), 2000)
      compare(next.alerts.length, 1)
      verify(next.alerts[0].body.indexOf("favorite runner") >= 0)

      var same = Model.transitionAlerts(
        next.state, [run], Model.alertConfig({ notifyThresholds: false }), 3000)
      compare(same.alerts.length, 0)
    }

    function test_new_split_below_threshold_notifies() {
      var config = Model.alertConfig({
        notifyFavorites: false,
        notifyHighQuality: false,
        notifyThresholds: true,
        thresholdNether: "01:30",
        thresholdBastion: "03:30"
      })
      var firstRun = parsedRun("world", "Runner",
        [event("rsg.enter_nether", 100000)])
      var initial = Model.transitionAlerts(
        Model.emptyAlertState(), [firstRun], config, 1000)

      var progressed = parsedRun("world", "Runner", [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 200000)
      ])
      var next = Model.transitionAlerts(initial.state, [progressed], config, 2000)
      compare(next.alerts.length, 1)
      compare(next.alerts[0].eventId, "rsg.enter_bastion")
      verify(next.alerts[0].body.indexOf("03:20") >= 0)
    }

    function test_threshold_and_quality_reasons_are_combined() {
      var config = Model.alertConfig({
        notifyFavorites: false,
        notifyHighQuality: true,
        notifyThresholds: true,
        thresholdFortress: "04:30"
      })
      var first = parsedRun("world", "Runner", [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 180000)
      ])
      var initial = Model.transitionAlerts(
        Model.emptyAlertState(), [first], config, 1000)
      var progressed = parsedRun("world", "Runner", [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 180000),
        event("rsg.enter_fortress", 260000)
      ])
      var next = Model.transitionAlerts(initial.state, [progressed], config, 2000)
      compare(next.alerts.length, 1)
      verify(next.alerts[0].body.indexOf("under threshold") >= 0)
      verify(next.alerts[0].body.indexOf("high-quality pace") >= 0)
    }

    function test_high_quality_alert_does_not_require_split_thresholds() {
      var config = Model.alertConfig({
        notifyFavorites: false,
        notifyHighQuality: true,
        notifyThresholds: false
      })
      var first = parsedRun("quality", "Runner", [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 180000)
      ])
      var initial = Model.transitionAlerts(
        Model.emptyAlertState(), [first], config, 1000)
      var progressed = parsedRun("quality", "Runner", [
        event("rsg.enter_nether", 100000),
        event("rsg.enter_bastion", 180000),
        event("rsg.enter_fortress", 260000)
      ])
      var next = Model.transitionAlerts(initial.state, [progressed], config, 2000)
      compare(next.alerts.length, 1)
      verify(next.alerts[0].body.indexOf("high-quality pace") >= 0)
      verify(next.alerts[0].body.indexOf("under threshold") < 0)
    }

    function test_notifications_link_to_stream_or_profile() {
      var streamRun = parsedRun("stream", "Streamer",
        [event("rsg.enter_nether", 90000)])
      streamRun.twitch = "streamer_live"
      var streamAlert = Model.buildAlert(
        streamRun, streamRun.eventList[0], ["threshold"])
      var streamArgs = Model.notificationArgs(
        streamAlert, "/tmp/minecraft.png")
      verify(streamArgs.indexOf("https://twitch.tv/streamer_live") >= 0)
      verify(streamArgs.indexOf("Watch live") >= 0)
      verify(streamArgs.indexOf("/tmp/minecraft.png") >= 0)
      verify(streamArgs[2].indexOf("flock -x") >= 0)
      verify(streamArgs.indexOf("stream_rsg.enter_nether") >= 0)

      var profileRun = parsedRun("profile", "Runner Name",
        [event("rsg.enter_nether", 90000)])
      var profileAlert = Model.buildAlert(
        profileRun, profileRun.eventList[0], ["threshold"])
      var profileArgs = Model.notificationArgs(profileAlert)
      verify(profileArgs.indexOf(
        Model.SITE_URL + "stats/player/Runner%20Name") >= 0)
      verify(profileArgs.indexOf("Open PaceMan profile") >= 0)
    }

    function test_brief_api_omission_does_not_replay_alerts() {
      var config = Model.alertConfig({
        notifyFavorites: true,
        notifyHighQuality: false,
        notifyThresholds: false
      })
      var run = parsedRun("world", "Favorite",
        [event("rsg.enter_nether", 130000)], "Favorite")
      var initial = Model.transitionAlerts(
        Model.emptyAlertState(), [run], config, 1000)
      var missing = Model.transitionAlerts(initial.state, [], config, 2000)
      var returned = Model.transitionAlerts(missing.state, [run], config, 3000)
      compare(returned.alerts.length, 0)
    }
  }
}
