import QtQuick
import qs.Commons
import qs.Ui

// The panel keeps keyboard navigation; this scope owns text-entry/Tab focus.
FocusScope {
  id: root
  property var hostWidget: null
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property string deleteCandidate: ""
  readonly property string activeId: hostWidget ? hostWidget.watchlistLibrary.activeId : ""
  readonly property int listCount: hostWidget ? hostWidget.watchlistLibrary.lists.length : 0
  signal resultReady(var result)
  signal returnFocus()

  implicitHeight: editorColumn.implicitHeight
  height: implicitHeight
  onActiveIdChanged: deleteCandidate = ""
  onVisibleChanged: if (!visible) {
    deleteCandidate = ""
    nameInput.text = ""
  }
  Keys.onEscapePressed: function(event) {
    deleteCandidate = ""
    root.returnFocus()
    event.accepted = true
  }

  function focusName() {
    nameInput.forceActiveFocus()
  }

  function apply(result) {
    root.resultReady(result)
    if (result.ok) {
      nameInput.text = ""
      deleteCandidate = ""
      root.returnFocus()
    }
  }

  function create(empty) {
    if (hostWidget) apply(hostWidget.createWatchlist(nameInput.text, empty))
  }

  function rename() {
    if (hostWidget) apply(hostWidget.renameWatchlist(nameInput.text))
  }

  function remove() {
    if (!hostWidget || !activeId) return
    if (deleteCandidate !== activeId) {
      deleteCandidate = activeId
      return
    }
    apply(hostWidget.deleteWatchlist(deleteCandidate))
  }

  function cancelDeletion() {
    deleteCandidate = ""
    root.returnFocus()
  }

  Column {
    id: editorColumn
    width: parent.width
    spacing: Style.space(8)

    BorderSurface {
      width: parent.width
      height: Math.max(Style.space(40), nameInput.implicitHeight + Style.space(18))
      padding: Style.space(9)
      radius: 0
      color: Style.normalFillFor(root.foreground, Color.accent, Color.urgent)
      borderSpec: Border.controlSpec(nameInput.activeFocus ? "focus" : "normal",
        root.foreground, Color.accent)

      TextInput {
        id: nameInput
        anchors.fill: parent
        anchors.leftMargin: parent.contentLeftInset
        anchors.rightMargin: parent.contentRightInset
        verticalAlignment: TextInput.AlignVCenter
        color: root.foreground
        selectionColor: Color.accent
        selectedTextColor: Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        maximumLength: 32
        clip: true
        activeFocusOnTab: true
        Accessible.name: "Watchlist name"
        onAccepted: root.create(false)
        KeyNavigation.tab: newButton
        KeyNavigation.backtab: deleteButton

        Text {
          visible: nameInput.text === "" && !nameInput.activeFocus
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Watchlist name, e.g. Work or Crypto"
          color: root.foreground
          font: nameInput.font
          elide: Text.ElideRight
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Button {
        id: newButton
        text: "New empty"
        foreground: root.foreground
        focusable: true
        tooltipText: "Create an empty watchlist using the entered name"
        Accessible.role: Accessible.Button
        Accessible.name: "Create an empty named watchlist"
        Accessible.onPressAction: root.create(true)
        onClicked: root.create(true)
        KeyNavigation.tab: copyButton
        KeyNavigation.backtab: nameInput
      }

      Button {
        id: copyButton
        text: "Save copy"
        foreground: root.foreground
        focusable: true
        tooltipText: "Copy the current symbols and pinned quote into a new watchlist"
        Accessible.role: Accessible.Button
        Accessible.name: "Save a named copy of the current watchlist"
        Accessible.onPressAction: root.create(false)
        onClicked: root.create(false)
        KeyNavigation.tab: renameButton
        KeyNavigation.backtab: newButton
      }

      Button {
        id: renameButton
        text: "Rename"
        foreground: root.foreground
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Rename the current watchlist"
        Accessible.onPressAction: root.rename()
        onClicked: root.rename()
        KeyNavigation.tab: deleteButton
        KeyNavigation.backtab: copyButton
      }

      Button {
        id: deleteButton
        text: root.deleteCandidate ? "Confirm delete" : "Delete list"
        foreground: root.foreground
        focusable: true
        enabled: root.listCount > 1 && root.activeId !== ""
        opacity: enabled ? 1 : 0.4
        Accessible.role: Accessible.Button
        Accessible.name: root.deleteCandidate ? "Confirm deletion of the current watchlist" : "Delete the current watchlist"
        Accessible.onPressAction: root.remove()
        onClicked: root.remove()
        KeyNavigation.tab: root.deleteCandidate ? cancelButton : nameInput
        KeyNavigation.backtab: renameButton
      }

      Button {
        id: cancelButton
        visible: root.deleteCandidate !== ""
        text: "Cancel"
        foreground: root.foreground
        focusable: true
        Accessible.role: Accessible.Button
        Accessible.name: "Cancel watchlist deletion"
        Accessible.onPressAction: root.cancelDeletion()
        onClicked: root.cancelDeletion()
        KeyNavigation.tab: nameInput
        KeyNavigation.backtab: deleteButton
      }
    }
  }
}
