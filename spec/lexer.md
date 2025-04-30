## Lexer

Token types:

1. Parenthesis

  - type: normal `()`, square `[]`
  - prefix: none, quote `'`, quasiquote `\``, unquote `,`, macro expansion `!`
  - handedness: left `(`, right `)`

2. Symbol - begins with a letter (lower- or uppercase); subsequent characters can be digits too

3. Number literal - optionally prefixed with `+` or `-`, then any number of digits, then optionally dot and digits

4. String literal - quote `"`, then any characters, then quote `"` again

  - when backslash `\\` appears inside, then together with the character that follows, it forms escape sequence: \n` for line feed (aka new line), `\\` for literal backslash
  - syntax sugar for a list of ASCII codes
