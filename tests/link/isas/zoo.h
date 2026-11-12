#pragma once
// classes with virtual methods defined in a header: every unit that includes it has its own copy of the vtables
class Animal { public: virtual int legs() { return 4; } int tag; }
class Dog : Animal { public: override int legs() { return 4; } }
class Puppy : Dog { public: override int legs() { return 3; } }
class Bird : Animal { public: override int legs() { return 2; } }
Animal* make(int kind);                 // 0 Animal, 1 Dog, 2 Puppy, 3 Bird
int classify(Animal* a);                // computed in the unit that made the objects
