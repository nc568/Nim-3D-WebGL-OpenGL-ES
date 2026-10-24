#!/usr/bin/env python3
"""Nim GCC driver flag adapter; never silently falls back to GCC for C compilation."""
import os, sys
args = [a for a in sys.argv[1:] if a not in ('-w', '-fmax-errors=3', '-fno-strict-aliasing', '-fno-ident', '-fno-math-errno')]
os.execvp('cproc', ['cproc', '-D__CHAR_BIT__=8', '-DNIM_CPROC', '-D_GNU_SOURCE='] + args)
