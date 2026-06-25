# PowerShell MenuUI

Interactive console menu/wizard UI primitives for PowerShell scripts — select
lists, multi-select checkboxes, plain & masked prompts, and a spinner for
running external processes without blocking the screen.

## Concept

Every prompt function in this module follows the same shape:

1. Clear the screen and redraw a **context panel** (title, hint, and the
   values already collected so far) — so a multi-step wizard always shows
   where you are and what's already been entered.
2. Render the actual prompt (a list, a checkbox menu, or a plain/masked
   input).
3. Block on a keypress or `Read-Host`, then return a plain value — a string,
   a bool, or whatever `Value` the chosen option carried.

There's no hidden state and no required setup: every function takes what it
needs as parameters and returns a plain value. Build a wizard by calling
these in sequence, passing the answers collected so far into each next
call's `-ContextCurrent` so the screen keeps showing prior answers as it
progresses.

Options for any select/checkbox function can be plain strings, full
`@{ Label = "..."; Value = ... }` hashtables, or a mix — `ConvertTo-UiOptions`
normalizes whatever you pass.

## Install

This module isn't published to the PowerShell Gallery. Either vendor it as a
git submodule, or just clone it next to (or inside) your own project:

```powershell
git submodule add https://github.com/ba-sw-ltda/powershell-menu-ui.git _lib/powershell-menu-ui
```

Then import it from your script:

```powershell
Import-Module "$PSScriptRoot/_lib/powershell-menu-ui/PowerShellMenuUI.psd1"
```

Requires Windows PowerShell 5.1+ or PowerShell 7+. The prompts read raw key
presses (`[Console]::ReadKey`), so they need a real interactive console — not
a non-interactive CI runner or a redirected-input session.

## Main functions

| Function | What it does |
|---|---|
| `Read-SelectValue` | Arrow-key single-choice menu. The main "pick one of these" entry point. Supports an optional async `-Loader` (with spinner) to fetch the option list first. |
| `Read-MultiSelectValues` | Checkbox menu — Space toggles, Enter confirms. For "pick any number of these". |
| `Read-ComponentSelectionScreen` | Two-level picker: toggleable groups containing checkboxes and/or radio sub-choices (e.g. "Ingress" group → NGINX vs. Traefik radio underneath it). |
| `Read-YesNo` | Two-choice Yes/No menu, returns a bool. |
| `Confirm-RetryOrExit` | "Try again or cancel?" after a recoverable failure — exits the process on cancel, otherwise returns so the caller's loop retries. |
| `Read-Plain` | Free-text prompt with an optional default. |
| `Read-SecretPlain` | Masked single-entry secret prompt (re-entering a known secret). |
| `Read-SecretPlainConfirm` | Masked secret prompt with retype-to-confirm (setting a new secret). |
| `Invoke-WithSpinner` | Runs an external executable in the background with an animated spinner, returns its exit code. |
| `Invoke-ScriptBlockWithSpinner` | Same idea, for a PowerShell scriptblock instead of an executable — e.g. a download. Returns the scriptblock's output, throws on error. |
| `Write-Context` / `Write-Section` | Clears the screen and draws the title/hint/context panel. Called internally by every prompt above; exported in case you want to draw a screen with no input on it (e.g. a "Step 3 of 5" banner). |
| `ConvertTo-UiOptions` | Normalizes strings/hashtables/objects into a uniform `@{Label;Value}` list. Used internally by every select/checkbox function. |
| `ToSafeName` | Lowercases and strips a string down to `[a-z0-9-]` — handy for turning free-text input into a safe identifier. |
| `Read-SelectIndex` | Low-level building block behind `Read-SelectValue` — same menu, but returns the chosen index instead of the value. |

Every function has full comment-based help — run `Get-Help <FunctionName> -Full`
after importing the module for parameters, examples, and return values.

## Try it

[`examples/Demo.ps1`](examples/Demo.ps1) walks through every function above
with a short explanation before each one, so you can see each
prompt in action:

```powershell
.\examples\Demo.ps1
```
