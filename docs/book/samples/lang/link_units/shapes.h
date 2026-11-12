// shapes.h: the declarations that main.a and shapes.a share
#pragma once

const int MAX_SHAPES = 3;

struct Point { int x; int y; }

class Counter {
    int n;
    public Counter() { n = 0; }
    public void bump() { n = n + 1; }
    public int value() { return n; }
}

extern int created;                  // declared here, defined in shapes.a
int area(Point a, Point b);
Point corner(int i);
int createdTwice();
