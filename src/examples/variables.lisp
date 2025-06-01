(do
  (let
    [abc 3]
    [some-var "The quick brown fox jumps over the lazy dog"]
    (syscall
      print
      some-var
      "\n"
      (syscall
        to-str
        abc)
      "\n"))
  (let
    [other-var 7]
    [some-num 9.876]
    (do
      (syscall
        print
        (syscall
          to-str
          other-var)
        "\n"
        (syscall
          to-str
          some-num)
        "\n"
        (syscall
          to-str
          (syscall
            add
            other-var
            some-num))
        "\n"
        (syscall
          to-str
          abc)
        "\n"
        (syscall
          to-str
          some-var)
        "\n")))
  (syscall
    add
    11
    22))
