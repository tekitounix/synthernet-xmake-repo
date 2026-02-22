---
globs:
  - "**/*.hh"
  - "**/*.cc"
  - "**/*.cpp"
  - "**/*.h"
---

# C++ Code Quality Rules

## Naming
- `lower_case`: functions, methods, variables, parameters, members, constexpr, namespaces
- `CamelCase`: types, classes, structs, enums, concepts, type aliases (except `_t` for scalar aliases)
- `UPPER_CASE`: enum values, scoped enum values
- No member prefixes (`m_`, `_` suffix prohibited). Use `this->` for disambiguation
- Pointers left-aligned: `int* ptr`

## Style
- C++23 standard
- `constexpr` only, never `inline constexpr` (redundant since C++17)
- Always use braces for `if`/`else`/`for`/`while`
- Parenthesize mixed-priority expressions: `(i * 2) + 1`
- Explicit bool: `ptr != nullptr`, `(flags & mask) != 0`
- Use `std::clamp`/`std::min`/`std::max`, not hand-written if-chains
- Use `auto*` for pointer types, `const auto*` for const pointers
- No nested ternary operators

## Real-time Safety (process() / audio callbacks / ISR)
Hard constraints — violation causes UB or audio glitches:
- NEVER allocate heap (`new`, `malloc`, `std::vector` growth)
- NEVER use blocking sync (`mutex`, `semaphore`)
- NEVER throw exceptions
- NEVER use stdio (`printf`, `cout`)

## IWYU Pragmas
- Umbrella headers (`core.hh`, `dbg.hh`, `midi.hh` etc.) MUST have `// IWYU pragma: export` on all re-exported includes
- Without pragma, clangd `unused-includes` and `clang-include-cleaner` produce false positives
- When creating or modifying an umbrella header, always add the pragma

## After Editing
- Verify no new clang-tidy warnings in VSCode Problems
- Run `xmake test` if you changed lib/ code
- Run `xmake build <target>` to verify compilation
