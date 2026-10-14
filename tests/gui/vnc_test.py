#!/usr/bin/env python3
"""Drives examples/gui/vnc_demo through the VNC backend: grabs the screen, clicks the button, types text."""
import sys, time
sys.path.insert(0, __import__("os").path.dirname(__file__))
from rfbclient import Rfb

c = None
for _ in range(50):
    try:
        c = Rfb()
        break
    except OSError:
        time.sleep(0.1)
assert c is not None, "cannot connect to the VNC server"
print("size", c.w, c.h, "name", c.name)
c.grab()
accent = (60, 120, 216)
box = c.find_color(accent)
assert box, "the primary button was not found"
cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
print("button at", cx, cy)
before = [c.pixel(x, 70) for x in range(60, 200)]
c.click(cx, cy)
time.sleep(0.3)
c.grab()
after = [c.pixel(x, 70) for x in range(60, 200)]
assert before != after, "the label did not change after the click"
c.click(cx, cy)
time.sleep(0.2)
# type into the text box (the last widget): click it first
tb = c.find_color((255, 255, 255))
assert tb
c.click((tb[0] + tb[2]) // 2, (tb[1] + tb[3]) // 2)
c.type_text("VNC works")
time.sleep(0.3)
c.grab()
c.save_ppm(sys.argv[1] if len(sys.argv) > 1 else "/tmp/vnc_shot.ppm")
print("ok")
