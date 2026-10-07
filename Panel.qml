import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Panneau Prompt Corrector : deux modes (Message / Prompt), champ d'entrée
// pré-rempli avec la sélection Wayland, appel d'une API LLM compatible
// OpenAI. La config (base URL, clé API, modèle, température, prompts
// système) vit dans ~/.config/omarchy/prompt-correcter.json et est partagée
// avec le CLI omarchy-prompt-correcter.
// Hérite de qs.Ui.Panel ; ouverture/fermeture pilotée par Widget.qml.
Panel {
  id: root
  moduleName: "momoledev.prompt-correcter"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color fg: bar ? bar.foreground : Color.popups.text
  readonly property color fieldBg: Util.alpha(root.fg, 0.05)
  readonly property color fieldBorder: Util.alpha(root.fg, 0.15)

  property string mode: "message"
  property bool busy: false
  property string statusText: ""
  property bool hasError: false
  property bool settingsOpen: false
  property real runStart: 0
  property var cfg: ({
    baseUrl: "https://api.openai.com/v1",
    apiKey: "",
    model: "gpt-4o-mini",
    temperature: 0.3,
    autoCopy: true,
    language: "auto",
    systemPromptMessage: "Tu es un correcteur orthographique et grammatical. Corrige le texte de l'utilisateur : orthographe, grammaire, conjugaison, ponctuation, accords, typographie. Ne change ni le sens, ni le ton, ni le style, et n'ajoute aucun commentaire. Conserve la langue du texte d'origine. Réponds UNIQUEMENT avec le texte corrigé, sans guillemets ni préambule.",
    systemPromptRestructure: "Tu es un expert en ingénierie de prompts. Réécris le texte de l'utilisateur pour en faire un prompt clair, précis et efficace pour une IA. Structure-le si nécessaire : rôle/contexte, tâche à accomplir, contraintes, format de sortie attendu. Supprime les ambiguïtés, les redondances et les fautes. Conserve la langue du texte d'origine. Réponds UNIQUEMENT avec le prompt réécrit, sans commentaire ni explication."
  })

  readonly property var languages: [
    { value: "auto", label: "Détection auto" },
    { value: "français", label: "Français" },
    { value: "english", label: "English" },
    { value: "español", label: "Español" },
    { value: "deutsch", label: "Deutsch" },
    { value: "português", label: "Português" },
    { value: "italiano", label: "Italiano" }
  ]

  readonly property string configPath: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    var base = (xdg && xdg.length > 0) ? xdg : (Quickshell.env("HOME") + "/.config")
    return base + "/omarchy/prompt-correcter.json"
  }

  function defaultCfg() {
    return {
      baseUrl: "https://api.openai.com/v1",
      apiKey: "",
      model: "gpt-4o-mini",
      temperature: 0.3,
      autoCopy: true,
      language: "auto",
      systemPromptMessage: "Tu es un correcteur orthographique et grammatical. Corrige le texte de l'utilisateur : orthographe, grammaire, conjugaison, ponctuation, accords, typographie. Ne change ni le sens, ni le ton, ni le style, et n'ajoute aucun commentaire. Conserve la langue du texte d'origine. Réponds UNIQUEMENT avec le texte corrigé, sans guillemets ni préambule.",
      systemPromptRestructure: "Tu es un expert en ingénierie de prompts. Réécris le texte de l'utilisateur pour en faire un prompt clair, précis et efficace pour une IA. Structure-le si nécessaire : rôle/contexte, tâche à accomplir, contraintes, format de sortie attendu. Supprime les ambiguïtés, les redondances et les fautes. Conserve la langue du texte d'origine. Réponds UNIQUEMENT avec le prompt réécrit, sans commentaire ni explication."
    }
  }

  function open(payloadJson) {
    root.controller.show()
    root.grabSelection()
    Qt.callLater(function() { if (root.opened) inputArea.forceActiveFocus() })
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.close() }
  function switchPanel(direction) {
    return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.barIdentity, direction) : false
  }

  // ---------- Config persistée (partagée avec le CLI) ----------
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        var d = root.defaultCfg()
        for (var k in d) if (s[k] !== undefined) d[k] = s[k]
        root.cfg = d
      } catch (e) {}
      root.applyCfg()
    }
    onLoadFailed: function(error) { root.applyCfg() }
  }

  function applyCfg() {
    urlField.text = root.cfg.baseUrl
    keyField.text = root.cfg.apiKey
    modelField.text = root.cfg.model
    tempSlider.value = Number(root.cfg.temperature) || 0.3
    autoCopyToggle.checked = root.cfg.autoCopy === true
    var codes = root.languages.map(function(l) { return l.value })
    langDropdown.value = codes.indexOf(root.cfg.language) >= 0 ? root.cfg.language : "auto"
    sysMsgArea.text = root.cfg.systemPromptMessage
    sysPromptArea.text = root.cfg.systemPromptRestructure
  }

  function saveCfg() {
    var d = root.defaultCfg()
    d.baseUrl = urlField.text.trim() || d.baseUrl
    d.apiKey = keyField.text
    d.model = modelField.text.trim() || d.model
    d.temperature = Math.round(tempSlider.value * 100) / 100
    d.autoCopy = autoCopyToggle.checked === true
    d.language = langDropdown.value || "auto"
    d.systemPromptMessage = sysMsgArea.text
    d.systemPromptRestructure = sysPromptArea.text
    root.cfg = d
    configFile.setText(JSON.stringify(d, null, 2))
    configFile.writeAdapter()
  }

  function setStatus(msg, isErr) {
    root.statusText = msg
    root.hasError = isErr === true
  }

  // ---------- Sélection Wayland (primaire, sinon presse-papiers) ----------
  function grabSelection() {
    selectionProc.running = true
  }

  Process {
    id: selectionProc
    command: ["bash", "-c", "t=$(wl-paste -p --no-newline 2>/dev/null); if [ -z \"${t//[[:space:]]/}\" ]; then t=$(wl-paste --no-newline 2>/dev/null); fi; printf '%s' \"$t\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text).trim()
        if (t !== "") inputArea.text = t
      }
    }
  }

  // ---------- Appel API ----------
  readonly property string apiScript:
    "mode=\"$1\"; cfg=\"$2\"; text=\"$3\"; "
    + "jget() { jq -r \"$1\" \"$cfg\" 2>/dev/null; }; "
    + "base=$(jget '.baseUrl // empty'); key=$(jget '.apiKey // empty'); model=$(jget '.model // empty'); "
    + "temp=$(jget '.temperature // 0.3'); case \"$temp\" in ''|*[!0-9.]*) temp=0.3;; esac; "
    + "lang=$(jget '.language // \"auto\"'); if [ -z \"$lang\" ] || [ \"$lang\" = 'null' ]; then lang='auto'; fi; "
    + "case \"$lang\" in auto) ;; *) sys=$(printf '%s\\n%s' \"$sys\" \"Langue de sortie impérative : $lang. Réponds entièrement dans cette langue, quelle que soit celle du texte d'origine.\") ;; esac; "
    + "if [ \"$mode\" = 'prompt' ]; then sys=$(jget '.systemPromptRestructure // empty'); else sys=$(jget '.systemPromptMessage // empty'); fi; "
    + "if [ -z \"$base\" ] || [ -z \"$model\" ]; then echo '{\"error\":{\"message\":\"Configuration incomplète : renseigne la Base URL et le Modèle (bouton ⚙ du panneau).\"}}'; exit 0; fi; "
    + "url=\"${base%/}/chat/completions\"; "
    + "payload=$(jq -n --arg model \"$model\" --argjson temp \"$temp\" --arg sys \"$sys\" --arg user \"$text\" '{model:$model,temperature:$temp,messages:[{role:\"system\",content:$sys},{role:\"user\",content:$user}]}'); "
    + "if [ -n \"$key\" ]; then curl -sS --max-time 180 -X POST \"$url\" -H \"Authorization: Bearer $key\" -H \"Content-Type: application/json\" -d \"$payload\"; "
    + "else curl -sS --max-time 180 -X POST \"$url\" -H \"Content-Type: application/json\" -d \"$payload\"; fi"

  function run() {
    if (root.busy) return
    var text = inputArea.text.trim()
    if (text === "") {
      root.setStatus("Aucun texte : colle ou sélectionne du texte d'abord.", true)
      return
    }
    root.saveCfg() // le CLI partage la même config
    root.busy = true
    root.runStart = Date.now()
    root.setStatus(root.mode === "message" ? "⏳ Correction en cours…" : "⏳ Restructuration en cours…", false)
    apiProc.command = ["bash", "-c", root.apiScript, "bash", root.mode, root.configPath, text]
    apiProc.running = true
  }

  function handleApiResult(code, out, err) {
    root.busy = false
    out = String(out || "").trim()
    err = String(err || "").trim()
    if (out === "") {
      root.setStatus(code !== 0 ? "Erreur (code " + code + ") : " + (err !== "" ? err : "appel réseau impossible") : "Réponse vide de l'API.", true)
      return
    }
    var resp
    try { resp = JSON.parse(out) } catch (e) {
      root.setStatus("Réponse non JSON : " + out.slice(0, 180), true)
      return
    }
    if (resp.error) {
      var m = resp.error.message || JSON.stringify(resp.error)
      root.setStatus("API : " + m, true)
      return
    }
    var content = (resp.choices && resp.choices.length > 0 && resp.choices[0].message) ? resp.choices[0].message.content : null
    if (content === null || content === undefined) {
      root.setStatus("Réponse inattendue : " + out.slice(0, 180), true)
      return
    }
    outputArea.text = String(content).trim()
    var secs = ((Date.now() - root.runStart) / 1000).toFixed(1)
    if (root.cfg.autoCopy === true) {
      root.copyOutput(false)
      root.setStatus("✓ Terminé en " + secs + " s · 📋 résultat copié (Ctrl+V pour coller)", false)
    } else {
      root.setStatus("✓ Terminé en " + secs + " s", false)
    }
  }

  Process {
    id: apiProc
    command: []
    stdout: StdioCollector { id: apiStdout; waitForEnd: true }
    stderr: StdioCollector { id: apiStderr; waitForEnd: true }
    onExited: function(code) { root.handleApiResult(code, apiStdout.text, apiStderr.text) }
  }

  // ---------- Copier / coller ----------
  function copyOutput(markCopied) {
    if (outputArea.text.length === 0) return
    copyProc.command = ["bash", "-c", "printf '%s' \"$1\" | wl-copy", "bash", outputArea.text]
    copyProc.running = true
    if (markCopied !== false) root.setStatus("📋 Copié — colle avec Ctrl+V", false)
  }

  function pasteOutput() {
    if (outputArea.text.length === 0 || root.busy) return
    pasteProc.command = ["bash", "-c", "sleep 0.3; printf '%s' \"$1\" | wl-copy; printf '%s' \"$1\" | wtype -", "bash", outputArea.text]
    pasteProc.running = true
    root.close()
  }

  Process { id: copyProc; command: [] }
  Process { id: pasteProc; command: [] }

  Shortcut {
    sequences: ["Ctrl+Return", "Ctrl+Enter"]
    onActivated: if (root.opened) root.run()
  }

  // ---------- Composants ----------
  component ModeButton: Rectangle {
    id: mb
    property string modeId
    property string icon
    property string label
    property string subtitle
    height: modeCol.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: root.mode === mb.modeId ? Util.alpha(Color.accent, 0.18) : root.fieldBg
    border.width: Style.normalBorderWidth
    border.color: root.mode === mb.modeId ? Color.accent : root.fieldBorder

    Column {
      id: modeCol
      anchors.centerIn: parent
      spacing: Style.space(2)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: mb.icon + "  " + mb.label
        color: root.mode === mb.modeId ? Color.accent : root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: mb.subtitle
        color: Util.alpha(root.fg, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.mode = mb.modeId
        if (!root.busy) root.setStatus("", false)
      }
    }
  }

  component PillToggle: Rectangle {
    id: pt
    property string label
    property bool checked: false
    width: ptRow.implicitWidth + Style.space(20)
    height: Style.space(34)
    radius: height / 2
    color: pt.checked ? Util.alpha(Color.accent, 0.2) : root.fieldBg
    border.width: Style.normalBorderWidth
    border.color: pt.checked ? Color.accent : root.fieldBorder

    Row {
      id: ptRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Rectangle {
        width: Style.space(12); height: Style.space(12); radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: pt.checked ? Color.accent : root.fieldBorder
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pt.label
        color: pt.checked ? Color.accent : root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: pt.checked = !pt.checked
    }
  }

  component LabeledField: Column {
    id: lf
    property string label: ""
    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias echoMode: field.echoMode
    width: parent.width
    spacing: Style.space(4)

    Text {
      text: lf.label
      color: Util.alpha(root.fg, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      width: parent.width
      height: Style.space(38)
      radius: Style.cornerRadius
      color: root.fieldBg
      border.width: Style.normalBorderWidth
      border.color: root.fieldBorder
      TextField {
        id: field
        anchors.fill: parent
        anchors.margins: Style.space(8)
        background: null
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
      }
    }
  }

  component LabeledArea: Column {
    id: la
    property string label: ""
    property alias text: area.text
    property alias placeholderText: area.placeholderText
    property int areaHeight: Style.space(96)
    width: parent.width
    spacing: Style.space(4)

    Text {
      text: la.label
      color: Util.alpha(root.fg, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      width: parent.width
      height: la.areaHeight
      radius: Style.cornerRadius
      color: root.fieldBg
      border.width: Style.normalBorderWidth
      border.color: root.fieldBorder
      TextArea {
        id: area
        anchors.fill: parent
        anchors.margins: Style.space(8)
        background: null
        color: root.fg
        wrapMode: TextArea.Wrap
        textFormat: TextEdit.PlainText
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
      }
    }
  }

  // ---------- Interface ----------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(680))
    contentHeight: panel.fittedContentHeight(Style.space(640))

    Rectangle {
      anchors.fill: parent
      color: Color.popups.background
      border.width: Style.normalBorderWidth
      border.color: Color.popups.border
      radius: Style.cornerRadius
    }

    ScrollView {
      id: sv
      anchors.fill: parent
      anchors.margins: Style.space(16)
      contentWidth: sv.availableWidth
      clip: true

      Column {
        width: sv.availableWidth
        spacing: Style.space(10)

        // En-tête
        Item {
          width: parent.width
          height: Style.space(34)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "✍ Prompt Corrector"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }
          Rectangle {
            id: gearBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.cornerRadius
            color: gearMouse.containsMouse ? root.fieldBg : "transparent"
            border.width: Style.normalBorderWidth
            border.color: root.settingsOpen ? Color.accent : root.fieldBorder
            Text {
              anchors.centerIn: parent
              text: "⚙"
              color: root.settingsOpen ? Color.accent : root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: gearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }
        }

        // Choix du mode
        Row {
          width: parent.width
          spacing: Style.space(10)
          ModeButton {
            modeId: "message"
            icon: "✉"
            label: "Message"
            subtitle: "Corriger simplement"
            width: (parent.width - Style.space(10)) / 2
          }
          ModeButton {
            modeId: "prompt"
            icon: "⚡"
            label: "Prompt"
            subtitle: "Corriger & restructurer"
            width: (parent.width - Style.space(10)) / 2
          }
        }

        // Langue de sortie
        Row {
          width: parent.width
          spacing: Style.space(12)
          Dropdown {
            id: langDropdown
            label: "Langue de sortie"
            value: "auto"
            options: root.languages
            foreground: root.fg
            width: Style.space(200)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - langDropdown.width - Style.space(12)
            text: "« Détection auto » conserve la langue du texte d'origine ; sinon le résultat est écrit dans la langue choisie."
            color: Util.alpha(root.fg, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          text: "Texte d'origine"
          color: Util.alpha(root.fg, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          width: parent.width
          height: Style.space(150)
          radius: Style.cornerRadius
          color: root.fieldBg
          border.width: Style.normalBorderWidth
          border.color: root.fieldBorder
          TextArea {
            id: inputArea
            anchors.fill: parent
            anchors.margins: Style.space(8)
            background: null
            color: root.fg
            wrapMode: TextArea.Wrap
            textFormat: TextEdit.PlainText
            placeholderText: "Colle ton texte, ou sélectionne-le à l'écran avant d'ouvrir ce panneau…"
            placeholderTextColor: Util.alpha(root.fg, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Action + statut
        Row {
          width: parent.width
          spacing: Style.space(10)
          Button {
            id: runBtn
            text: root.busy ? "⏳ Traitement…" : (root.mode === "message" ? "✓ Corriger le message" : "⚡ Restructurer le prompt")
            accent: Color.accent
            fontFamily: Style.font.family
            fontSize: Style.font.bodySmall
            enabled: !root.busy
            onClicked: root.run()
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - runBtn.width - Style.space(10)
            text: root.statusText
            color: root.hasError ? "#e06c75" : Util.alpha(root.fg, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          text: "Résultat"
          color: Util.alpha(root.fg, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          width: parent.width
          height: Style.space(170)
          radius: Style.cornerRadius
          color: root.fieldBg
          border.width: Style.normalBorderWidth
          border.color: root.fieldBorder
          TextArea {
            id: outputArea
            anchors.fill: parent
            anchors.margins: Style.space(8)
            background: null
            color: root.fg
            wrapMode: TextArea.Wrap
            textFormat: TextEdit.PlainText
            placeholderText: "Le résultat apparaîtra ici…"
            placeholderTextColor: Util.alpha(root.fg, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          spacing: Style.space(10)
          Button {
            text: "📋 Copier"
            fontFamily: Style.font.family
            fontSize: Style.font.caption
            enabled: outputArea.text.length > 0
            onClicked: root.copyOutput(true)
          }
          Button {
            text: "⌨ Coller dans la fenêtre active"
            fontFamily: Style.font.family
            fontSize: Style.font.caption
            enabled: outputArea.text.length > 0 && !root.busy
            onClicked: root.pasteOutput()
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.cfg.autoCopy === true ? "copie auto : activée" : "copie auto : désactivée"
            color: Util.alpha(root.fg, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Réglages ----------
        Rectangle {
          visible: root.settingsOpen
          width: parent.width
          height: 1
          color: root.fieldBorder
        }
        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "Réglages"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            text: "API compatible OpenAI. Config enregistrée dans " + root.configPath + " — partagée avec le CLI omarchy-prompt-correcter."
            color: Util.alpha(root.fg, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          LabeledField { id: urlField; label: "Base URL"; placeholderText: "https://api.openai.com/v1" }
          LabeledField { id: keyField; label: "Clé API"; placeholderText: "sk-… (vide pour un serveur local)"; echoMode: TextInput.Password }
          LabeledField { id: modelField; label: "Modèle"; placeholderText: "gpt-4o-mini" }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Row {
              spacing: Style.space(8)
              Text {
                text: "Température"
                color: Util.alpha(root.fg, 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                text: Number(tempSlider.value).toFixed(2)
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }
            Slider {
              id: tempSlider
              width: parent.width
              from: 0
              to: 2
              stepSize: 0.05
            }
          }

          PillToggle { id: autoCopyToggle; label: "Copier automatiquement le résultat" }

          LabeledArea { id: sysMsgArea; label: "Prompt système — mode Message (correction simple)" }
          LabeledArea { id: sysPromptArea; label: "Prompt système — mode Prompt (correction & restructuration)" }

          Row {
            spacing: Style.space(10)
            Button {
              text: "💾 Enregistrer"
              accent: Color.accent
              fontFamily: Style.font.family
              fontSize: Style.font.caption
              onClicked: {
                root.saveCfg()
                root.setStatus("💾 Réglages enregistrés", false)
              }
            }
            Button {
              text: "Réinitialiser"
              fontFamily: Style.font.family
              fontSize: Style.font.caption
              onClicked: {
                root.cfg = root.defaultCfg()
                root.applyCfg()
              }
            }
          }
        }
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Bloqué dès qu'un champ a le focus — sinon le catcher avale les touches.
      blocked: {
        var win = panel.contentItem ? panel.contentItem.window : null
        if (!win) return false
        var fi = win.activeFocusItem
        return fi && fi !== keyCatcher
      }
      onCloseRequested: root.close()
    }
  }
}
