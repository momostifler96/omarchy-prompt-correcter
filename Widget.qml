import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bouton de barre Prompt Corrector : icône ✍ qui ouvre/ferme le panneau de
// correction (Panel.qml). Même motif que momoledev.dev-tools : le panneau est
// chargé ici et reçoit manuellement les propriétés injectées par le shell
// (bar/settings/anchorItem/hostWidget).
BarWidget {
  id: root
  moduleName: "momoledev.prompt-correcter"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    // Query string contre le cache de composants : le hot-reload prend
    // aussi en compte les edits de Panel.qml.
    source: Qt.resolvedUrl("Panel.qml") + "?v=" + Date.now()
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "✍"
    slotSize: Style.bar.statusSlot
    tooltipText: "Prompt Corrector"

    onPressed: function() {
      root.toggle()
    }
  }
}
