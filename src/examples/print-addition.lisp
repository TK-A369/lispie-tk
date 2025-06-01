(do
  (syscall
    print
    "9 + (3.2 + 4.3) = "
    (syscall
      to-str
      (syscall
        add
        9
        (syscall
          add
          3.2
          4.3)))
    "\n")
  (syscall
    print
    "3 + 4 = "
    (syscall
      to-str
      (syscall
        add
        3
        4))
    "\n"))
