# Lispie TK

## Overview

This is a very simple Lisp dialect interpreter.

As expected, the code is in form of S-expressions.

Functions may have side effects.

Code is firstly lexed - that is, split into tokens (like `(`, `)`, `print`, `3.4`). Then, it's parsed and converted into AST - abstract syntax tree - which is relatively simple because of code being just S-expressions. It is then evaluated, in few stages. There's no bytecode emitted nor a virtual machine that would run it - instead, the AST is evaluated directly. This significantly simplifies language interpreter design, at cost of not being able to easily save state of VM.
