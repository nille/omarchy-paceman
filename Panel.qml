import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Live RSG paces from PaceMan.gg. The API adapter, sorting, time formatting,
// favorites, thresholds, and alert transitions live in Model.js; this file owns
// only transport, persisted settings, interaction, and rendering.
Panel {
  id: root
  moduleName: "nille.paceman"
  ipcTarget: "nille.paceman"
  manageIpc: false

  // ---------------------------------------------------------------- theme

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 1.9)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // ---------------------------------------------------------------- settings

  readonly property int configuredRefreshIntervalSec:
    Model.normalizeRefreshInterval(setting("refreshIntervalSec", 15))
  readonly property string configuredGameVersion: String(
    setting("gameVersion", "1.16.1"))
  readonly property bool configuredLiveOnly: setting("liveOnly", false) === true
  readonly property bool configuredFavoritesOnly:
    setting("favoritesOnly", false) === true
  readonly property string configuredFavoriteRunners: String(
    setting("favoriteRunners", ""))

  property var pendingRefreshIntervalSec: null
  property var pendingGameVersion: null
  property var pendingLiveOnly: null
  property var pendingFavoritesOnly: null
  property var pendingFavoriteRunners: null

  readonly property int refreshIntervalSec:
    pendingRefreshIntervalSec !== null
      ? Model.normalizeRefreshInterval(pendingRefreshIntervalSec)
      : configuredRefreshIntervalSec
  readonly property string shownGameVersion: pendingGameVersion !== null
    ? String(pendingGameVersion) : configuredGameVersion
  readonly property bool shownLiveOnly: pendingLiveOnly !== null
    ? pendingLiveOnly : configuredLiveOnly
  readonly property bool shownFavoritesOnly: pendingFavoritesOnly !== null
    ? pendingFavoritesOnly : configuredFavoritesOnly
  readonly property string shownFavoriteRunners: pendingFavoriteRunners !== null
    ? String(pendingFavoriteRunners) : configuredFavoriteRunners

  function persistSetting(key, value) {
    settingsTimeout.restart()
    Quickshell.execDetached(Model.settingArgs(moduleName, key, value))
  }

  function setRefreshInterval(value) {
    value = Model.normalizeRefreshInterval(value)
    if (refreshIntervalSec === value) return
    pendingRefreshIntervalSec = value
    persistSetting("refreshIntervalSec", value)
    refreshTimer.restart()
  }

  function setGameVersion(value) {
    value = String(value || "1.16.1")
    if (shownGameVersion === value) return
    pendingGameVersion = value
    persistSetting("gameVersion", value)
    filtersChanged()
  }

  function setLiveOnly(value) {
    value = !!value
    if (shownLiveOnly === value) return
    pendingLiveOnly = value
    persistSetting("liveOnly", value)
    filtersChanged()
  }

  function setFavoritesOnly(value) {
    value = !!value
    if (shownFavoritesOnly === value) return
    pendingFavoritesOnly = value
    persistSetting("favoritesOnly", value)
    publishVisibleRuns()
  }

  function toggleFavorite(run) {
    if (!run) return
    pendingFavoriteRunners = Model.toggleFavorite(
      shownFavoriteRunners, run.nickname)
    persistSetting("favoriteRunners", pendingFavoriteRunners)
    reparseCached()
  }

  onConfiguredRefreshIntervalSecChanged: {
    if (pendingRefreshIntervalSec === configuredRefreshIntervalSec)
      pendingRefreshIntervalSec = null
  }
  onConfiguredGameVersionChanged: {
    if (pendingGameVersion === configuredGameVersion)
      pendingGameVersion = null
  }
  onConfiguredLiveOnlyChanged: {
    if (pendingLiveOnly === configuredLiveOnly)
      pendingLiveOnly = null
  }
  onConfiguredFavoritesOnlyChanged: {
    if (pendingFavoritesOnly === configuredFavoritesOnly)
      pendingFavoritesOnly = null
  }
  onConfiguredFavoriteRunnersChanged: {
    if (pendingFavoriteRunners !== null
        && Model.normalizeFavorites(pendingFavoriteRunners).join(",")
          === Model.normalizeFavorites(configuredFavoriteRunners).join(","))
      pendingFavoriteRunners = null
    reparseCached()
  }

  Timer {
    id: settingsTimeout
    interval: 2200
    onTriggered: {
      root.pendingRefreshIntervalSec = null
      root.pendingGameVersion = null
      root.pendingLiveOnly = null
      root.pendingFavoritesOnly = null
      root.pendingFavoriteRunners = null
      root.reparseCached()
    }
  }

  // ---------------------------------------------------------------- data

  property var allRuns: []
  property var runs: []
  property string lastPayload: ""
  property bool requestInFlight: false
  property bool refreshQueued: false
  property var activeRequest: null
  property string requestSignature: ""
  property string lastError: ""
  property double lastSuccessAt: 0
  property double nowMs: Date.now()
  property int retryDelayMs: 5000
  property var alertState: Model.emptyAlertState()

  readonly property int highQualityCount: Model.highQualityCount(allRuns)
  readonly property int activeFavoriteCount: Model.favoriteCount(allRuns)
  readonly property bool stale: lastSuccessAt > 0
    && nowMs - lastSuccessAt >= Model.STALE_AFTER_MS
  readonly property string freshness: Model.freshnessLabel(
    lastSuccessAt, nowMs, requestInFlight, lastError)

  function currentSignature() {
    return shownGameVersion + "|" + (shownLiveOnly ? "1" : "0")
  }

  function filtersChanged() {
    alertState = Model.emptyAlertState()
    if (activeRequest) {
      try { activeRequest.abort() } catch (e) {}
      activeRequest = null
      requestInFlight = false
    }
    retryTimer.stop()
    refresh()
  }

  function refresh() {
    if (requestInFlight) {
      refreshQueued = true
      return
    }

    var signature = currentSignature()
    var xhr = new XMLHttpRequest()
    activeRequest = xhr
    requestSignature = signature
    requestInFlight = true
    refreshQueued = false
    lastError = ""

    xhr.open("GET", Model.apiUrl(shownGameVersion, shownLiveOnly))
    xhr.timeout = 8000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (root.activeRequest !== xhr) return
      if (xhr.status >= 200 && xhr.status < 300) {
        root.finishSuccess(xhr.responseText, signature)
      } else {
        root.finishFailure(xhr.status > 0
          ? "PaceMan returned " + xhr.status
          : "Could not reach PaceMan")
      }
    }
    xhr.ontimeout = function() {
      if (root.activeRequest === xhr) root.finishFailure("PaceMan timed out")
    }
    xhr.onerror = function() {
      if (root.activeRequest === xhr) root.finishFailure("Could not reach PaceMan")
    }
    xhr.send()
  }

  function finishSuccess(payload, signature) {
    activeRequest = null
    requestInFlight = false
    if (signature !== currentSignature()) {
      if (refreshQueued) refresh()
      return
    }

    var parsed = Model.parsePaces(payload, shownFavoriteRunners, false)
    if (parsed === null) {
      finishFailure("PaceMan returned invalid data")
      return
    }

    lastPayload = payload
    allRuns = parsed
    publishVisibleRuns()
    lastSuccessAt = Date.now()
    nowMs = lastSuccessAt
    lastError = ""
    retryDelayMs = 5000
    retryTimer.stop()

    var transition = Model.transitionAlerts(
      alertState, allRuns, Model.alertConfig(settings), lastSuccessAt)
    alertState = transition.state
    for (var i = 0; i < transition.alerts.length; i++) {
      var argv = Model.notificationArgs(transition.alerts[i])
      if (argv) Quickshell.execDetached(argv)
    }

    clampCursor()
    if (refreshQueued) refresh()
  }

  function finishFailure(message) {
    activeRequest = null
    requestInFlight = false
    lastError = String(message || "Could not refresh PaceMan")
    retryTimer.interval = retryDelayMs
    retryTimer.restart()
    retryDelayMs = Math.min(60000, retryDelayMs * 2)
    if (refreshQueued) refresh()
  }

  function reparseCached() {
    if (lastPayload === "") return
    var parsed = Model.parsePaces(lastPayload, shownFavoriteRunners, false)
    if (parsed === null) return
    allRuns = parsed
    publishVisibleRuns()
    clampCursor()
  }

  function publishVisibleRuns() {
    if (!shownFavoritesOnly) {
      runs = allRuns.slice()
      return
    }
    var visible = []
    for (var i = 0; i < allRuns.length; i++)
      if (allRuns[i].isFavorite) visible.push(allRuns[i])
    runs = visible
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: retryTimer
    interval: 5000
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: refresh()

  // ---------------------------------------------------------------- cursor

  property bool cursorActive: false
  property int selectedIndex: 0
  property string expandedWorldId: ""

  readonly property int rowVersion: 0
  readonly property int rowLiveOnly: 1
  readonly property int rowFavoritesOnly: 2
  readonly property int runBase: 3
  readonly property int rowCount: runBase + runs.length

  function setCursor(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(Math.max(0, rowCount - 1), index))
  }

  function moveCursor(delta) {
    setCursor(selectedIndex + delta)
    Qt.callLater(ensureCursorVisible)
  }

  function clampCursor() {
    selectedIndex = Math.max(0, Math.min(Math.max(0, rowCount - 1), selectedIndex))
  }

  function selectedRun() {
    var index = selectedIndex - runBase
    return index >= 0 && index < runs.length ? runs[index] : null
  }

  function activateCursor() {
    if (selectedIndex === rowVersion) versionDropdown.toggle()
    else if (selectedIndex === rowLiveOnly) setLiveOnly(!shownLiveOnly)
    else if (selectedIndex === rowFavoritesOnly)
      setFavoritesOnly(!shownFavoritesOnly)
    else {
      var run = selectedRun()
      if (run) expandedWorldId = expandedWorldId === run.worldId
        ? "" : run.worldId
    }
  }

  function ensureCursorVisible() {
    if (!scrollArea || !panelColumn) return
    var item = null
    if (selectedIndex === rowVersion) item = filterRow
    else if (selectedIndex === rowLiveOnly) item = liveToggle
    else if (selectedIndex === rowFavoritesOnly) item = favoritesToggle
    else {
      var childIndex = selectedIndex - runBase
      if (childIndex >= 0 && childIndex < runRepeater.count)
        item = runRepeater.itemAt(childIndex)
    }
    if (!item) return
    var point = item.mapToItem(panelColumn, 0, 0)
    var top = point.y
    var bottom = top + item.height
    if (top < scrollArea.contentItem.contentY)
      scrollArea.contentItem.contentY = top
    else if (bottom > scrollArea.contentItem.contentY + scrollArea.height)
      scrollArea.contentItem.contentY = bottom - scrollArea.height
  }

  // ---------------------------------------------------------------- actions

  function openSite() {
    Quickshell.execDetached(["omarchy-launch-browser", Model.SITE_URL])
  }

  function openRun(run) {
    if (!run) return
    var url = Model.twitchUrl(run)
    if (url === "") url = Model.runnerProfileUrl(run)
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function openProfile(run) {
    if (run)
      Quickshell.execDetached(["omarchy-launch-browser",
                              Model.runnerProfileUrl(run)])
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ---------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Keep the control's own label alive for its click/tooltip geometry, but
    // render the glyph separately so it always uses the patched icon font.
    text: " "
    fixedWidth: vertical ? -1 : Style.space(20)
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    dimmed: root.lastSuccessAt === 0 || root.stale
    tooltipText: {
      var text = "PaceMan · " + root.allRuns.length + " active"
      if (root.activeFavoriteCount > 0)
        text += " · " + root.activeFavoriteCount + " favorite"
      if (root.highQualityCount > 0)
        text += " · " + root.highQualityCount + " high-quality"
      return text + "\n" + root.freshness
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton) root.openSite()
      else root.toggle()
    }

    Text {
      anchors.centerIn: parent
      text: Model.barIcon()
      color: button.foreground
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(410))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight,
                                             Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: versionDropdown.popupOpen
        || refreshIntervalPopup.opened
        || thresholdsPopup.opened

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        var run = root.selectedRun()
        if (key === "r") root.refresh()
        else if (key === "f" && run) root.toggleFavorite(run)
        else if (key === "o" && run) root.openRun(run)
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height
          ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.spacing.panelGap

          Item {
            id: panelHero
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight,
                                     heroLabels.implicitHeight,
                                     heroActions.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Model.barIcon()
              color: root.foreground
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroActions.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Item {
                width: parent.width
                implicitHeight: Math.max(heroTitle.implicitHeight,
                                         activePill.implicitHeight)

                Text {
                  id: heroTitle
                  anchors.left: parent.left
                  anchors.right: activePill.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "PaceMan"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                BorderSurface {
                  id: activePill
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: activeText.implicitWidth + Style.space(10)
                  implicitHeight: activeText.implicitHeight + Style.space(4)
                  color: "transparent"
                  borderSpec: Border.controlSpec(
                    "normal", root.foreground, root.accent)
                  radius: Style.cornerRadius

                  Text {
                    id: activeText
                    anchors.centerIn: parent
                    text: root.allRuns.length + " ACTIVE"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }

              Text {
                id: freshnessLink
                text: root.freshness.toUpperCase()
                color: freshnessMouse.containsMouse
                  ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight

                ToolTip.visible: freshnessMouse.containsMouse
                  && !refreshIntervalPopup.opened
                ToolTip.text: "Change refresh interval"

                MouseArea {
                  id: freshnessMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: refreshIntervalPopup.opened
                    ? refreshIntervalPopup.close()
                    : refreshIntervalPopup.open()
                }

                Popup {
                  id: refreshIntervalPopup
                  x: 0
                  y: freshnessLink.height + Style.spacing.xs
                  width: Style.space(210)
                  padding: Style.spacing.md
                  focus: true
                  closePolicy: Popup.CloseOnEscape
                    | Popup.CloseOnPressOutsideParent
                  onOpened: refreshIntervalField.field.forceActiveFocus()
                  onClosed: Qt.callLater(function() {
                    keyCatcher.forceActiveFocus()
                  })

                  background: BorderSurface {
                    color: Color.popups.background
                    borderSpec: Border.controlSpec(
                      "normal", root.foreground, root.accent)
                    radius: Style.cornerRadius
                  }

                  contentItem: Column {
                    spacing: Style.spacing.sm

                    Text {
                      text: "REFRESH INTERVAL"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Row {
                      spacing: Style.spacing.sm

                      NumberField {
                        id: refreshIntervalField
                        fieldWidth: Style.space(72)
                        from: 2
                        to: 60
                        stepSize: 1
                        value: root.refreshIntervalSec
                        foreground: root.foreground
                        accent: root.accent
                        fontFamily: root.fontFamily
                        fontSize: Style.font.body
                        onModified: function(value) {
                          root.setRefreshInterval(value)
                        }
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SECONDS"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }
              }
            }

            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              PanelActionButton {
                id: thresholdsAction
                iconText: "\u{F009A}"
                tooltipText: "Notification thresholds"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  refreshIntervalPopup.close()
                  thresholdsPopup.opened
                    ? thresholdsPopup.close() : thresholdsPopup.open()
                }

                Popup {
                  id: thresholdsPopup
                  x: thresholdsAction.width - width
                  y: thresholdsAction.height + Style.spacing.xs
                  width: Style.space(280)
                  padding: Style.spacing.md
                  focus: true
                  closePolicy: Popup.CloseOnEscape
                    | Popup.CloseOnPressOutsideParent
                  onClosed: Qt.callLater(function() {
                    keyCatcher.forceActiveFocus()
                  })

                  background: BorderSurface {
                    color: Color.popups.background
                    borderSpec: Border.controlSpec(
                      "normal", root.foreground, root.accent)
                    radius: Style.cornerRadius
                  }

                  contentItem: Column {
                    id: thresholdColumn
                    width: thresholdsPopup.width
                      - thresholdsPopup.leftPadding
                      - thresholdsPopup.rightPadding
                    spacing: Style.spacing.xs

                    Item {
                      width: parent.width
                      implicitHeight: Math.max(thresholdTitle.implicitHeight,
                                               thresholdUnit.implicitHeight)

                      Text {
                        id: thresholdTitle
                        anchors.left: parent.left
                        text: "NOTIFICATION THRESHOLDS"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        id: thresholdUnit
                        anchors.right: parent.right
                        text: "MM:SS"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Repeater {
                      model: Model.thresholdSettings()

                      delegate: Item {
                        id: thresholdRow
                        required property var modelData
                        width: thresholdColumn.width
                        implicitHeight: Math.max(thresholdLabel.implicitHeight,
                                                 thresholdField.implicitHeight)

                        Text {
                          id: thresholdLabel
                          anchors.left: parent.left
                          anchors.right: thresholdField.left
                          anchors.rightMargin: Style.spacing.md
                          anchors.verticalCenter: parent.verticalCenter
                          text: thresholdRow.modelData.label
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          elide: Text.ElideRight
                        }

                        TextField {
                          id: thresholdField
                          property string savedText: String(root.setting(
                            thresholdRow.modelData.key,
                            thresholdRow.modelData.defaultValue))
                          readonly property string trimmedText:
                            String(text).trim()
                          readonly property bool thresholdValid:
                            trimmedText === "" || trimmedText === "0"
                              || Model.parseThreshold(trimmedText) > 0

                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          width: Style.space(78)
                          text: savedText
                          placeholderText: "MM:SS"
                          horizontalAlignment: TextInput.AlignHCenter
                          foreground: thresholdValid
                            ? root.foreground : root.urgent
                          accent: root.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          inputMethodHints: Qt.ImhFormattedNumbersOnly

                          onEditingFinished: {
                            if (!thresholdValid) {
                              text = savedText
                              return
                            }
                            savedText = trimmedText
                            root.persistSetting(
                              thresholdRow.modelData.key, savedText)
                          }
                        }
                      }
                    }
                  }
                }
              }

              PanelActionButton {
                id: refreshAction
                iconText: root.requestInFlight ? "\u{F0453}" : "\u{F0450}"
                tooltipText: "Refresh live paces"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          Text {
            width: parent.width
            visible: root.lastError !== ""
            text: root.lastError + (root.lastSuccessAt > 0
              ? " · showing the last successful update" : "")
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: "FILTERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item {
            id: filterRow
            width: parent.width
            readonly property real controlHeight: Math.max(
              Style.spacing.controlHeight,
              liveToggle.implicitHeight,
              favoritesToggle.implicitHeight)
            implicitHeight: controlHeight

            Dropdown {
              id: versionDropdown
              width: Math.min(Style.space(130), parent.width * 0.38)
              rowHeight: filterRow.controlHeight
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              value: root.shownGameVersion
              options: Model.gameVersionOptions()
              foreground: root.foreground
              background: root.bar ? root.bar.background : Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive
                && root.selectedIndex === root.rowVersion
              onHovered: function(on) {
                if (on) root.setCursor(root.rowVersion)
              }
              onChanged: function(value) { root.setGameVersion(value) }
            }

            Button {
              id: liveToggle
              height: filterRow.controlHeight
              anchors.left: versionDropdown.right
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              text: "STREAMING"
              iconText: "\u{F0543}"
              selected: root.shownLiveOnly
              bordered: true
              hasCursor: root.cursorActive
                && root.selectedIndex === root.rowLiveOnly
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Only runners currently streaming on Twitch"
              onClicked: root.setLiveOnly(!root.shownLiveOnly)
              onHovered: function(on) {
                if (on) root.setCursor(root.rowLiveOnly)
              }
            }

            Button {
              id: favoritesToggle
              height: filterRow.controlHeight
              anchors.left: liveToggle.right
              anchors.leftMargin: Style.spacing.sm
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "FAVORITES"
              iconText: root.shownFavoritesOnly ? "★" : "☆"
              selected: root.shownFavoritesOnly
              bordered: true
              hasCursor: root.cursorActive
                && root.selectedIndex === root.rowFavoritesOnly
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Only favorite runners"
              onClicked: root.setFavoritesOnly(!root.shownFavoritesOnly)
              onHovered: function(on) {
                if (on) root.setCursor(root.rowFavoritesOnly)
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Item {
            width: parent.width
            implicitHeight: runsHeader.implicitHeight

            PanelSectionHeader {
              id: runsHeader
              anchors.left: parent.left
              text: root.shownFavoritesOnly ? "FAVORITE PACES" : "ACTIVE PACES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: runsHeader.verticalCenter
              text: String(root.runs.length)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Repeater {
            id: runRepeater
            model: root.runs

            delegate: Item {
              id: runDelegate
              required property var modelData
              required property int index
              width: panelColumn.width
              implicitHeight: runRow.implicitHeight

              RunRow {
                id: runRow
                width: parent.width
                runData: runDelegate.modelData
                rowIndex: root.runBase + runDelegate.index
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.requestInFlight && root.runs.length === 0
            text: root.shownFavoritesOnly
              ? "No favorite runners are currently on pace."
              : "No runners are currently on pace for this filter."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item {
            width: 1
            height: Style.spacing.xs
          }
        }
      }
    }
  }

  component RunRow: CursorSurface {
    id: row

    required property var runData
    required property int rowIndex
    readonly property bool expanded: !!runData
      && root.expandedWorldId === runData.worldId

    implicitHeight: content.implicitHeight + Style.spacing.lg
    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    foreground: root.foreground
    accent: root.accent
    fill: root.hoverFill
    currentFill: root.selectedFill

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.setCursor(row.rowIndex)
      onClicked: root.expandedWorldId = row.expanded ? "" : row.runData.worldId
      onDoubleClicked: root.openRun(row.runData)
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.spacing.sm

      Item {
        width: parent.width
        implicitHeight: Math.max(labels.implicitHeight, timeColumn.implicitHeight,
                                 favoriteButton.implicitHeight)

        PanelActionButton {
          id: favoriteButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: row.runData && row.runData.isFavorite ? "★" : "☆"
          tooltipText: row.runData && row.runData.isFavorite
            ? "Remove from favorites" : "Add to favorites"
          foreground: row.runData && row.runData.isFavorite
            ? root.accent : root.dim
          hoverColor: root.accent
          fontFamily: root.fontFamily
          onClicked: root.toggleFavorite(row.runData)
          onHovered: function(on) {
            if (on) root.setCursor(row.rowIndex)
          }
        }

        Column {
          id: labels
          anchors.left: favoriteButton.right
          anchors.leftMargin: Style.spacing.sm
          anchors.right: timeColumn.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              width: Math.min(implicitWidth, Math.max(0, parent.width
                - (liveMark.visible ? liveMark.implicitWidth + parent.spacing : 0)
                - (qualityMark.visible
                  ? qualityMark.implicitWidth + parent.spacing : 0)))
              text: row.runData ? row.runData.nickname : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: !!row.runData && row.runData.isHighQuality
              elide: Text.ElideRight
            }

            Text {
              id: liveMark
              visible: !!row.runData && row.runData.twitch !== ""
              text: "LIVE"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.children[0].verticalCenter
            }

            Text {
              id: qualityMark
              visible: !!row.runData && row.runData.isHighQuality
              text: "★ HIGH QUALITY"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.children[0].verticalCenter
            }
          }

          Text {
            width: parent.width
            text: row.runData ? row.runData.splitName
              + (root.shownGameVersion === "All"
                ? " · " + row.runData.gameVersion : "") : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Column {
          id: timeColumn
          anchors.right: openButton.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            anchors.right: parent.right
            text: Model.formatTime(row.runData ? row.runData.time : 0)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: !!row.runData && row.runData.isHighQuality
          }

          Text {
            anchors.right: parent.right
            text: Model.formatTime(Model.estimatedTime(row.runData, root.nowMs))
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelActionButton {
          id: openButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\u{F03CC}"
          tooltipText: row.runData && row.runData.twitch !== ""
            ? "Open Twitch stream" : "Open PaceMan profile"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openRun(row.runData)
          onHovered: function(on) {
            if (on) root.setCursor(row.rowIndex)
          }
        }
      }

      Column {
        width: parent.width
        visible: row.expanded
        spacing: Style.spacing.xs

        Item {
          width: parent.width
          implicitHeight: Math.max(detailsHeader.implicitHeight,
                                   collapseButton.implicitHeight)

          PanelSectionHeader {
            id: detailsHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "RUN DETAILS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PanelActionButton {
            id: collapseButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0156}"
            tooltipText: "Collapse run details"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.expandedWorldId = ""
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        Repeater {
          model: row.runData ? row.runData.eventList : []

          Item {
            required property var modelData
            width: row.width - Style.space(20)
            height: Math.max(splitName.implicitHeight, splitTime.implicitHeight)

            Text {
              id: splitName
              anchors.left: parent.left
              anchors.right: splitTime.left
              anchors.rightMargin: Style.spacing.md
              text: modelData.name
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              id: splitTime
              anchors.right: parent.right
              text: Model.formatTime(modelData.igt)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          visible: !!row.runData && row.runData.itemEstimates !== null
          width: parent.width
          text: {
            var counts = row.runData ? (row.runData.itemEstimates || {}) : {}
            var pearls = Number(counts["minecraft:ender_pearl"] || 0)
            var rods = Number(counts["minecraft:blaze_rod"] || 0)
            return "Estimated inventory · " + pearls + " pearls · " + rods + " rods"
          }
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Button {
          width: parent.width
          text: row.runData && row.runData.twitch !== ""
            ? "Watch live" : "Open runner profile"
          iconText: "\u{F03CC}"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: root.openRun(row.runData)
        }
      }
    }
  }
}
