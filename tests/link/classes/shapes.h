#pragma once
class Shape {
    public:
    int id;
    virtual int area() { return 0; }
    int describe() { return id * 1000 + area(); }
}
class Square : Shape {
    public:
    int side;
    Square(int s) { side = s; id = 1; }
    virtual int area() { return side * side; }
}
struct Vec { double x; double y; }
extern int shapeCount;
extern int primes[5];
extern double scale;
int makeSquareArea(int s);
double vecLength2(Vec v);
int apply(func f, int v);
int triple(int v);
char* greeting();
