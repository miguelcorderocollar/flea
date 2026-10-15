//@ pragma ShellId flea-picker-folder-test
//@ pragma NativeTextRendering
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

ShellRoot {
    id: root
    property var shell: null
    property var win: null
    property int stage: 0
    property int checks: 0
    property var failures: []
    property string base: ""
    property int request: 0
    property int ticks: 0
    property var keys: null
    property bool marking: false
    property string retainedMarks: ""
    property bool finishing: false
    function check(ok, label) { root.checks++; if (!ok) root.failures.push(label) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) { var found = root.find(item.children[i], name); if (found) return found }
        return null
    }
    function name(value) { root.win.folderCreation.name = value; root.win.folderCreation.fieldItem.text = value }
    function report() {
        clock.stop()
        for (var i = 0; i < root.failures.length; i++) console.log("PICKERFOLDER FAIL " + root.failures[i])
        console.log("PICKERFOLDER DONE checks=" + root.checks + " failed=" + root.failures.length)
    }
    function done() {
        if (root.failures.length) { root.report(); Qt.exit(1); return }
        root.finishing = true
        if (root.win && (root.win.folderMode || root.win.marks.length > 0)) root.win.accept()
        else if (root.win) root.win.cancel()
        else Qt.quit()
    }
    Connections {
        target: root.win
        function onAnsweredChanged() { if (root.win.answered && root.finishing) root.report() }
    }
    Timer {
        id: clock
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (++root.ticks > 150) {
                root.check(false, "timeout stage " + root.stage + " mark=" + (root.win ? root.win.markRequest : "?")
                    + " submitting=" + (root.win ? root.win.submitting : "?") + " message=" + (root.win ? root.win.message : "?"))
                root.done(); return
            }
            if (root.finishing) return
            if (root.stage === 0) {
                var component = Qt.createComponent("flea/PickerWindow.qml")
                if (component.status !== Component.Ready) { root.check(false, component.errorString()); root.done(); return }
                root.shell = component.createObject(root)
                root.win = root.shell.pickerWin
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.win.contentItem)
                root.base = root.win.path
                root.stage++
                return
            }
            var win = root.win
            var folder = win.folderCreation
            if (root.stage === 1) {
                if (win.listingState === "loading" || win.saveRequest || win.markRequest || !win.canCreateFolder) return
                if (!win.saving && win.req.multiple && !root.marking) {
                    root.marking = true
                    var markedName = win.folderMode ? "existing" : "keep.txt"
                    win.toggleMark(win.rows.findIndex(function(row) { return row.n === markedName }) + win.held)
                    return
                }
                root.retainedMarks = JSON.stringify(win.marks)
                if (win.saving) root.check(win.saveName === "download.zip", "caller filename")
                if (root.marking) root.check(win.marks.length === 1, "existing item checked before creation")
                var button = root.find(win.contentItem, "pickerNewFolder")
                var glyph = root.find(button, "pickerFolderGlyph")
                root.check(button.visible && button.enabled, "New folder visible and available in this picker mode")
                root.check(glyph && glyph.text === "\ueec7", "canonical Nerd Font folder-plus glyph")
                root.check(!button.ringItem.visible && !button.markItem.visible, "icon-only action has no button border")
                root.check(button.accessName === "New folder", "icon retains accessible action name")
                var up = root.find(win.contentItem, "pickerUp")
                root.check(button.parent.focusItems()[4] === button, "New folder follows Up in toolbar focus order")
                up.forceActiveFocus()
                root.keys.keyClick(Qt.Key_Tab, Qt.NoModifier, -1)
                root.check(button.activeFocus, "Tab reaches New folder from Up")
                root.keys.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, -1)
                root.check(up.activeFocus, "Shift+Tab returns from New folder to Up")
                var view = root.find(win.contentItem, "pickerListView")
                var strip = root.find(win.contentItem, "pickerStrip")
                root.check(button.x + button.width <= view.mapToItem(button.parent, 0, 0).x, "wide New folder does not overlap view controls")
                root.check(strip.mapToItem(button.parent, strip.width, 0).x <= button.x, "wide path and filters reserve folder action width")
                win.focusView()
                root.keys.keyClick(Qt.Key_N, Qt.ControlModifier | Qt.ShiftModifier, -1)
                root.stage++
            } else if (root.stage === 2) {
                if (!folder.ready || !folder.fieldItem) return
                root.check(folder.active, "modal opened")
                root.check(folder.folder === root.base, "parent captured")
                root.check(!win.canAccept, "picker cannot accept under modal")
                root.check(!win.viewItem().enabled, "listing input blocked")
                root.check(folder.fieldItem.activeFocus, "folder field focus")
                root.name("existing")
                folder.submit()
                root.request = folder.pending
                folder.submit()
                root.check(folder.pending === root.request, "duplicate submission blocked")
                root.check(!folder.close(), "pending creation cannot be dismissed")
                root.stage++
            } else if (root.stage === 3) {
                if (folder.pending) return
                root.check(folder.active && folder.error.indexOf("already exists") >= 0, "collision stays in card")
                root.check(folder.name === "existing" && folder.fieldItem.text === "existing", "failed name retained")
                root.check(folder.fieldItem.activeFocus, "failure returns field focus")
                root.check(win.path === root.base && JSON.stringify(win.marks) === root.retainedMarks, "failure preserves location and selection")
                if (win.saving) root.check(win.saveName === "download.zip", "failure preserves save filename")
                root.name("Reports 雪")
                folder.submit()
                root.stage++
            } else if (root.stage === 4) {
                if (folder.active || win.listingState === "loading" || win.saveRequest || !win.canCreateFolder) return
                root.check(win.path === root.base + "/Reports 雪", "success enters created folder")
                root.check(JSON.stringify(win.marks) === root.retainedMarks, "success preserves checked selections")
                root.check(!win.answered, "folder creation does not answer the picker")
                root.check(win.canAccept === (win.saving || win.folderMode || win.marks.length > 0), "acceptance still follows picker mode")
                if (win.saving) {
                    root.check(win.saveName === "download.zip", "success preserves filename")
                    root.check(win.contentItem.Window.window.activeFocusItem.text === "download.zip", "filename focused after success")
                } else root.check(win.viewItem().activeFocus, "listing focused after success")
                win.startNewFolder()
                root.stage++
            } else if (root.stage === 5) {
                if (!folder.ready || !folder.fieldItem) return
                root.name("Never created")
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
                root.check(!folder.active && !win.answered, "Escape/cancel dismisses card only")
                folder.received({id: root.request, ok: true, path: root.base + "/stale"})
                root.check(win.path === root.base + "/Reports 雪", "late response cannot navigate after close")
                win.setView(win.viewMode === "list" ? "grid" : "list")
                // The offscreen platform keeps its initial window size. Size the real chrome directly to test its responsive layout.
                var chrome = root.find(win.contentItem, "pickerNewFolder").parent
                chrome.anchors.right = undefined
                chrome.width = 360
                root.stage++
            } else if (root.stage === 6) {
                root.check(win.canCreateFolder, "available after changing picker view")
                var button = root.find(win.contentItem, "pickerNewFolder")
                var where = root.find(win.contentItem, "pickerWhere")
                root.check(button.parent.width === 360 && button.parent.folderButtonWrapped, "narrow picker chrome wraps folder action")
                root.check(button.y >= where.y + where.height, "wrapped action sits below path/filter/view strip")
                root.check(button.x >= 0 && button.x + button.width <= button.parent.width && button.y + button.height <= button.parent.height,
                    "wrapped folder action stays inside chrome")
                button.activated()
                root.stage++
            } else if (root.stage === 7) {
                if (!folder.ready || !folder.fieldItem) return
                root.check(folder.fieldItem.activeFocus, "toolbar action opens focused modal in other view")
                folder.close()
                root.stage++
            } else if (root.stage === 8) {
                // Closing the modal and answering the chooser are separate user events. The check worker has a one-request queue.
                if (win.markRequest || win.submitting) return
                if (win.folderMode || win.marks.length > 0) root.check(win.canAccept, "final selection remains acceptable")
                root.done()
            }
        }
    }
}
