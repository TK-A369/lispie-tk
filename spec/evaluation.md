## Evaluation

### Stages of evaluation:

1. Read macros - most of the forms will evaluate to themselves, besides macro definition special forms

2. Expand macros - again, most of the forms will evaluate to themselves, besides lists of macro expansion kind; the macro will when be evaluated in stage 3: runtime evaluation

3. Runtime evaluation - literals evaluate to themselves; symbols (besides certain special forms) are variable accesses; quotelists evaluate to lists; lists that are not special forms are function calls, where first element is the function, and the rest are the arguments

### Read macros

In this stage, every `defmacro` special form will create a macro definition.

It looks like this: `(defmacro <name> <args> <body>)`, where `<name>` should be a sumbol - macro's name. `<args>` may be either a symbol - then the arguments list will be bound to a variable with such name - or a list of symbols - then individual arguments will be bound to respective variables. `<body>` will be evaluated every time the macro is expanded.

During this stage, `importmacros` special forms will result in given file being evaluated (read macros and evaluate macros stages only) and macros exported by it will be available in the current module.

And `exportmacro` special form will mark given macro as to be exported.

### Expand macros

For every list with prefix `!` (macro expansion), an appropriate macro definition will be looked up (either from current module - `defmacro` - or imported - `importmacros`), and it will be expanded/evaluated. The macro's body will be evaluated as in runtime evaluation mode. This means that it can use typical functions, although writing non-deterministic macros performing IO is generally ill-advised.

### Runtime evaluation

Normal lists (round parentheses and no prefix) means function call. The first element is the function, and the others are arguments. All of the list's elements will be evaluated.

The exception from above paragraph is when first element of the list is one of those symbols:

- `let` - this special form allows to define scoped immutable bindings/variables; the following elements should either be two-element square bracket lists (binding name and value), or otherwise an expression to evaluate and return; only the last non-square bracket list expression will be returned

- `if` - takes 2 or 3 arguments; evaluate the 1st one, and if it's true (other than 0 or empty list), then evaluate and return 2nd argument; otherwise evaluate and return 3rd argument (or return 0 if it doesn't exist)

- `def` - global immutable binding/variable; consists of two-element square bracket lists, simularly to `let`

- `fn` - represents a function; looks like this: `(fn [a b] (add a (mul b 2)))`, so the 2nd element it argument list (may also be a single symbol, then it will be bound to a list of arguments), and 3rd element is the function body; evaluates to itself; TODO: allow capturing variables from outer scope

- `do` - execute all the arguments in order, and return the value of the last one
