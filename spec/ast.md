## Parser and AST

The parser takes token list and produces AST.

AST primarily consists of lists, which are surrounded by parentheses, and contain any number of values inside, spearated by whitespace. Those values may be:

 - lists of the following kinds: plain, quote `'`, quasiquote `\``, unquote `,`, macro expansion `!`
 - symbols
 - number literals
 - string literals - syntax sugar for a list of ASCII codes
