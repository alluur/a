#!/usr/bin/env python3
"""Regenerates the expected outputs tests/t4NN_*.out of the tests t440 .. t469 from the independent Python reference implementations in this directory
(gen_t4NN.py print the expected text; they use only the Python standard library: fractions, decimal, math, statistics). Usage:  python3 tests/algo2_ref/gen_all.py [t440 ...]"""
import glob, os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
tests = os.path.dirname(here)
want = sys.argv[1:]
for gen in sorted(glob.glob(os.path.join(here, 'gen_t4*.py'))):
    num = os.path.basename(gen)[4:8]            # t4NN
    if want and num not in want:
        continue
    srcs = glob.glob(os.path.join(tests, num + '_*.a'))
    if len(srcs) != 1:
        print('skip %s (no test program)' % num)
        continue
    out = srcs[0][:-2] + '.out'
    text = subprocess.run([sys.executable, gen], check=True, capture_output=True, text=True, cwd=here).stdout
    open(out, 'w').write(text)
    print('wrote', os.path.basename(out))
