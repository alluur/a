// shared helpers of the gcode tests (t240 ...): the display server runs in this process on the Headless backend; settle() lets the
// client and the server exchange everything that is pending. Include it after
//   import wsrv; import gui; import guix; import gcode; import adp; import gfx; import asys;
wsrv.Server* srv;
wsrv.Headless* hb;
gui.Display* d;

int stepServer(int unused) { srv->step(0); return 0; }

void settle() {
    d->sync();
    for (int i = 0; i < 30; i++) {
        srv->step(0);
        d->pump(0);
    }
}

void startServer(int port, char* name) {
    hb = new wsrv.Headless(900, 700);
    srv = new wsrv.Server(hb, port);
    srv->allowScreenshots = true;
    gui.idleHook = stepServer;
    char spec[16];
    format(&spec[0], 16, "%d", port);
    d = gui.connectAs(&spec[0], name);
}

void key(int k, int uni) {
    hb->tap(k, uni);
    settle();
}

// a key with modifiers held (adp.MOD_CTRL | adp.MOD_SHIFT | adp.MOD_ALT)
void keyMods(int k, int uni, int mods) {
    if ((mods & adp.MOD_CTRL) != 0) { hb->keyDown(adp.KEY_CTRL, 0); }
    if ((mods & adp.MOD_SHIFT) != 0) { hb->keyDown(adp.KEY_SHIFT, 0); }
    if ((mods & adp.MOD_ALT) != 0) { hb->keyDown(adp.KEY_ALT, 0); }
    hb->tap(k, uni);
    if ((mods & adp.MOD_ALT) != 0) { hb->keyUp(adp.KEY_ALT, 0); }
    if ((mods & adp.MOD_SHIFT) != 0) { hb->keyUp(adp.KEY_SHIFT, 0); }
    if ((mods & adp.MOD_CTRL) != 0) { hb->keyUp(adp.KEY_CTRL, 0); }
    settle();
}

void typeStr(char* s) {
    hb->typeText(s);
    settle();
}

void ctrl(int k) { keyMods(k, 0, adp.MOD_CTRL); }

// the screen position of a point given relative to a widget
int screenX(gui.Window* gw, gui.Widget* wd, int x) {
    wsrv.Win* sw = srv->findWindow(d->clientNum, gw->id);
    return sw->x + wd->absX() + x;
}

int screenY(gui.Window* gw, gui.Widget* wd, int y) {
    wsrv.Win* sw = srv->findWindow(d->clientNum, gw->id);
    return sw->y + wd->absY() + y;
}

void moveWd(gui.Window* gw, gui.Widget* wd, int x, int y) {
    hb->moveTo(screenX(gw, wd, x), screenY(gw, wd, y));
    settle();
}

void clickWd(gui.Window* gw, gui.Widget* wd, int x, int y) {
    hb->click(screenX(gw, wd, x), screenY(gw, wd, y));
    settle();
}

void rightClickWd(gui.Window* gw, gui.Widget* wd, int x, int y) {
    hb->moveTo(screenX(gw, wd, x), screenY(gw, wd, y));
    hb->buttonDown(3);
    hb->buttonUp(3);
    settle();
}

void middleClickWd(gui.Window* gw, gui.Widget* wd, int x, int y) {
    hb->moveTo(screenX(gw, wd, x), screenY(gw, wd, y));
    hb->buttonDown(2);
    hb->buttonUp(2);
    settle();
}

// press at (x0, y0), move to (x1, y1), release (widget coordinates)
void dragWd(gui.Window* gw, gui.Widget* wd, int x0, int y0, int x1, int y1) {
    hb->moveTo(screenX(gw, wd, x0), screenY(gw, wd, y0));
    hb->buttonDown(1);
    settle();
    hb->moveTo(screenX(gw, wd, x1), screenY(gw, wd, y1));
    settle();
    hb->buttonUp(1);
    settle();
}

void wheelWd(gui.Window* gw, gui.Widget* wd, int x, int y, int delta) {
    hb->moveTo(screenX(gw, wd, x), screenY(gw, wd, y));
    hb->scroll(delta);
    settle();
}

// the checksum of the pixels a window shows (without the title bar and the pointer)
int shot(gui.Window* gw) {
    return gw->surf->checksum();
}
