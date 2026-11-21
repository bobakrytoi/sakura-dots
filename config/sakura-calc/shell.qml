//@ pragma AppId sakura-calc
// Sakura Calc - calculator for the sakura rice (basic / scientific / converter).
//   sakura-calc                         open, or focus the running one
//   qs -p ~/.config/sakura-calc ipc call calc <fn>
//     type <text> · key enter|esc|back|copy|up|down|neg · mode calc|sci|conv · hist · state · quit
//   SAKURA_CALC_STATE=/path/state.json  alternative state file (tests)
// Closing the window quits the instance.
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    FloatingWindow {
        id: win
        title: "Calculator"
        implicitWidth: 400
        implicitHeight: 640
        minimumSize: Qt.size(340, 520)
        color: Theme.glass
        onVisibleChanged: if (!visible) Qt.quit()

        App {
            id: app
            anchors.fill: parent
            // a mapped xdg toplevel can't resize itself under Hyprland → ask the compositor
            onWantSize: (w, h) => {
                if (win.width === w && win.height === h) return;
                Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.window.resize({ x = " + Math.round(w) + ", y = " + Math.round(h)
                    + ", window = 'class:^(sakura-calc)$' }))"]);
            }
        }
        Component.onCompleted: {
            const s = app.sizes[app.mode] || [400, 640];
            win.implicitWidth = s[0] + (app.histOpen ? app.histW : 0);
            win.implicitHeight = s[1];
        }
    }

    IpcHandler {
        target: "calc"
        function type(s: string): void { app.typeText(s); }
        function key(k: string): void {
            const m = { enter: "=", esc: "clear", back: "back", neg: "neg", swap: "swap" };
            if (k === "copy") app.copyResult();
            else if (k === "up") app.histStep(1);
            else if (k === "down") app.histStep(-1);
            else app.press(m[k] || k);
        }
        function mode(m: string): void { app.mode = m; }
        function hist(): void { app.histOpen = !app.histOpen; }
        function cat(c: string): void { app.convCat = c; }
        function state(): string {
            return JSON.stringify({ mode: app.mode, expr: app.field().text, preview: app.previewText, prev: app.prevExpr,
                conv: app.mode === "conv" ? app.convOut : null, history: app.history.length, qalc: app.hasQalc,
                size: [win.width, win.height] });
        }
        function pick(side: string): void { app.pickUnit(side); }
        function quit(): void { Qt.quit(); }
    }
}
