## Evaluation

### Stages of evaluation:

1. Read macros - most of the forms will evaluate to themselves, besides macro definition special forms

2. Expand macros - again, most of the forms will evaluate to themselves, besides lists of macro expansion kind; the macro will when be evaluated in stage 3: runtime evaluation

3. Runtime evaluation - symbols and literals evaluate to themselves; quotelists evaluate to lists; lists that are not special forms are function calls, where first element is the function, and the rest are the arguments
