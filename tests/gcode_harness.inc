// shared helpers of the gcode tests (t240 ...): the display server runs in this process on the Headless backend; settle() lets the
// client and the server exchange everything that is pending. Include it after
//   import wsrv; import gui; import guix; import gcode; import adp; import gfx; import asys;
wsrv.Server* srv;
wsrv.Headless* hb;
gui.Display* d;

int stepServer(int unused) { srv->step(0); return 0; }

int pingCount = 0;

// Lets the client and the server exchange everything that is pending. A ping travels behind everything the client has sent: when the
// answer is back the server has handled it all (big windows take many rounds: their pixels go through a socket); then a few more
// rounds let the client answer what the server just did. Three times, because the answers can cause new drawing.
void settle() {
    d->sync();
    for (int round = 0; round < 3; round++) {
        pingCount++;
        d->ping(pingCount);
        for (int i = 0; i < 4000 && d->lastPong != pingCount; i++) {
            srv->step(0);
            d->pump(0);
        }
        for (int i = 0; i < 10; i++) {
            srv->step(0);
            d->pump(0);
        }
    }
}

// the display has the given size (windows that are taller than the screen cannot be clicked everywhere)
void startServerSized(int port, char* name, int screenW, int screenH) {
    hb = new wsrv.Headless(screenW, screenH);
    srv = new wsrv.Server(hb, port);
    srv->allowScreenshots = true;
    gui.idleHook = stepServer;
    char spec[16];
    format(&spec[0], 16, "%d", port);
    d = gui.connectAs(&spec[0], name);
}

void startServer(int port, char* name) {
    startServerSized(port, name, 900, 700);
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

// deletes a directory tree (the tests clean up what an earlier run left in build/tests)
void rmtree(char* path) {
    asys.Stat st;
    if (asys.lstat(path, &st) != 0) { return; }
    if (st.isDir()) {
        asys.DirList dl();
        if (asys.listDir(path, &dl) >= 0) {
            for (int i = 0; i < dl.count; i++) {
                char* child = asys.join(path, dl.name(i));
                rmtree(child);
                asys.free(child);
            }
            dl.dispose();
        }
        asys.rmdir(path);
    } else {
        asys.unlink(path);
    }
}
