import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Standalone live-data harness. Launch through tests/harness/run so qs.Ui and
// qs.Commons resolve from the installed Omarchy shell.
ShellRoot {
  FloatingWindow {
    id: window
    title: "PaceMan Harness"
    implicitWidth: 620
    implicitHeight: 260
    color: Color.background
    visible: true

    QtObject {
      id: stubBar
      property string fontFamily: Style.font.family
      property color themeForeground: Color.bar.text
      property color foreground: themeForeground
      property color barForeground: themeForeground
      property bool foregroundAnimationEnabled: true
      property color background: Color.bar.background
      property color urgent: Color.bar.active
      property bool vertical: false
      property int barSize: Style.bar.sizeHorizontal
      property string position: "top"
      property var activePopout: null

      function requestPopout(owner) {
        if (activePopout === owner) return
        if (activePopout && "close" in activePopout) activePopout.close()
        activePopout = owner
      }
      function releasePopout(owner) {
        if (activePopout === owner) activePopout = null
      }
      function showTooltip(item, text) {}
      function hideTooltip(item) {}
      function registerClickTarget(item) {}
      function unregisterClickTarget(item) {}
      function moduleWidgets(name) { return [] }
      function switchPanelFrom(panel, direction) { return false }
    }

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.bar.sizeHorizontal
      color: Color.bar.background

      Loader {
        id: widgetLoader
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        source: Quickshell.env("PACEMAN_DIR") + "/Panel.qml"
        onLoaded: {
          item.bar = stubBar
          item.moduleName = "nille.paceman"
          item.settings = {
            refreshIntervalSec: 15,
            gameVersion: "1.16.1",
            liveOnly: false,
            favoritesOnly: false,
            favoriteRunners: "",
            notifyStreamingOnly: false,
            notifyFavorites: false,
            notifyHighQuality: false,
            notifyThresholds: false
          }
        }
      }
    }

    Timer {
      interval: 800
      running: true
      onTriggered: {
        if (widgetLoader.item) widgetLoader.item.open()
      }
    }
  }
}
