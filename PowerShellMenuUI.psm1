Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Single source of truth for on-screen keybinding hints — every interactive
# prompt below shows one of these, so the wording/format never drifts
# between functions.
$script:KeyHintSelect = "Up/Down Navigate    Enter Confirm    Esc Cancel"
$script:KeyHintToggle = "Up/Down Navigate    Space Toggle    Enter Confirm    Esc Cancel"

<#
.SYNOPSIS
    Normalizes a string into a lowercase, alphanumeric-only token.
.DESCRIPTION
    Replaces every character that is not a-z/A-Z/0-9 with a hyphen and lowercases
    the result. Useful for turning free-text input (a display name, a project code)
    into something safe to use as a Kubernetes name, file name, or similar identifier.
.PARAMETER s
    The raw input string.
.EXAMPLE
    PS> ToSafeName "Hello World!"
    hello-world-
.OUTPUTS
    System.String
#>
function ToSafeName {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  return ($s -replace '[^a-zA-Z0-9]', '-').ToLower()
}

# Private helper behind Write-Context — normalizes whatever was passed as -Current
# (hashtable, ordered dictionary, list of Key/Value pairs, or a single bare value)
# into a flat array of @{Key;Value} for uniform rendering. Not exported.
function Get-ContextEntries {
  param($Current)

  if ($null -eq $Current) { return @() }

  # 1) Liste von Einträgen (Key/Value) -> 그대로
  if ($Current -is [System.Collections.IEnumerable] -and -not ($Current -is [System.Collections.IDictionary]) -and -not ($Current -is [string])) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($e in $Current) {
      if ($null -eq $e) { continue }

      # Hashtable/PSCustomObject mit Key/Value
      $k = $null
      $v = $null
      if ($e -is [System.Collections.IDictionary]) {
        if ($e.Contains("Key")) { $k = $e["Key"] }
        if ($e.Contains("Value")) { $v = $e["Value"] }
      } else {
        $kp = $e.PSObject.Properties["Key"]
        $vp = $e.PSObject.Properties["Value"]
        if ($kp) { $k = $kp.Value }
        if ($vp) { $v = $vp.Value }
      }

      if ($null -ne $k) {
        $out.Add([pscustomobject]@{ Key = [string]$k; Value = $v }) | Out-Null
      }
    }
    return $out.ToArray()
  }

  # 2) Dictionary (Hashtable, OrderedDictionary, [ordered]@{}) -> Enumerationsreihenfolge
  if ($Current -is [System.Collections.IDictionary]) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Current.GetEnumerator()) {
      $out.Add([pscustomobject]@{ Key = [string]$entry.Key; Value = $entry.Value }) | Out-Null
    }

    return $out.ToArray()
  }

  # 3) Fallback
  return @([pscustomobject]@{ Key = "Value"; Value = $Current })
}

<#
.SYNOPSIS
    Clears the screen and renders a title/hint header plus a key-value context panel.
.DESCRIPTION
    Every prompt function in this module calls Write-Context (directly or via
    Write-Section) before drawing itself, so the user always sees: what step they're
    on (Title), why (Hint), and the values already collected so far (Current) — every
    redraw is a full Clear-Host, so this needs to run first on every screen.
.PARAMETER Title
    Screen title, shown in cyan.
.PARAMETER Hint
    One-line explanation shown under the title, in dark gray.
.PARAMETER Current
    The "already collected" values to display. Accepts a hashtable/[ordered]@{},
    a list of @{Key=...;Value=...} objects, or any other single value (shown as-is).
.PARAMETER MaskKeys
    Names of keys in Current whose value should be displayed as **** instead of
    the real value (e.g. a password already entered earlier in the flow).
.EXAMPLE
    PS> Write-Context -Title "OpenBao" -Hint "Configures the UI ingress" `
            -Current ([ordered]@{ Platform = "RKE2"; Domain = "example.com" })
#>
function Write-Context {
  param(
    [string]$Title = "",
    [string]$Hint = "",
    $Current = $null,
    [string[]]$MaskKeys = @()
  )

  Clear-Host

  if ($Title) { Write-Host $Title -ForegroundColor Cyan }
  if ($Hint)  { Write-Host $Hint  -ForegroundColor DarkGray }

  Write-Host ""
  $entries = @(Get-ContextEntries $Current)
  if ($entries.Count -gt 0) {
    foreach ($e in $entries) {
      $k = $e.Key
      $v = $e.Value

      if ($MaskKeys -contains $k) {
        Write-Host ("{0}: {1}" -f $k, "********") -ForegroundColor Gray
        continue
      }

      if ($null -eq $v) { $v = "" }

      # Read-MultiSelectValues returns an array of selected values — show it as
      # one comma-separated line instead of collapsing into "System.Object[]".
      $isList = ($v -is [System.Collections.IEnumerable]) -and
                -not ($v -is [string]) -and
                -not ($v -is [System.Collections.IDictionary])
      if ($isList) {
        $items = @($v)
        $joined = if ($items.Count -eq 0) { "(none)" } else { $items -join ", " }
        Write-Host ("{0}: {1}" -f $k, $joined) -ForegroundColor Gray
        continue
      }

      # Read-ComponentSelectionScreen returns @{ value = $true/$false }  — show
      # just the selected (true) keys as one comma-separated line.
      $isSelectionMap = ($v -is [System.Collections.IDictionary]) -and
                         $v.Values.Count -gt 0 -and
                         -not ($v.Values | Where-Object { $_ -isnot [bool] })
      if ($isSelectionMap) {
        $selected = @($v.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
        $joined = if ($selected.Count -eq 0) { "(none)" } else { $selected -join ", " }
        Write-Host ("{0}: {1}" -f $k, $joined) -ForegroundColor Gray
        continue
      }

      Write-Host ("{0}: {1}" -f $k, $v) -ForegroundColor Gray
    }
  }
}

<#
.SYNOPSIS
    Alias for Write-Context — same parameters, same behavior.
.DESCRIPTION
    Exists purely for readability at call sites where "this is a new section of the
    flow" reads better than "this is context for the next prompt". Pick whichever
    name fits the surrounding code; both call Write-Context underneath.
.EXAMPLE
    PS> Write-Section -Title "Step 2: Network"
#>
function Write-Section {
  param(
    [string]$Title,
    [string]$Hint = "",
    $Current = $null,
    [string[]]$MaskKeys = @()
  )
  Write-Context -Title $Title -Hint $Hint -Current $Current -MaskKeys $MaskKeys
}

<#
.SYNOPSIS
    Normalizes any reasonable "list of choices" shape into a flat array of
    [pscustomobject]@{ Label; Value } entries.
.DESCRIPTION
    Every selection function (Read-SelectValue, Read-MultiSelectValues, ...) accepts
    options as plain strings, @{Label=...;Value=...} hashtables, or PSCustomObjects
    with Label/Value properties — and calls this internally to make them uniform
    before rendering. You normally don't need to call this yourself; it's exported
    because some callers build their own selection UI on top of the same shape.
.PARAMETER Options
    A single option or a collection of options in any of the supported shapes.
    A bare string or a single Label/Value hashtable is treated as ONE option, not
    decomposed into characters/keys.
.EXAMPLE
    PS> ConvertTo-UiOptions -Options @("yes", @{ Label = "No thanks"; Value = $false })

    Label     Value
    -----     -----
    yes       yes
    No thanks False
.OUTPUTS
    System.Object[] of [pscustomobject]@{ Label; Value }
#>
function ConvertTo-UiOptions {
  param(
    $Options
  )

  # 1) Eingabe stabil in eine Item-Liste normalisieren, ohne PowerShell-Flattening (@(...))
  $items = New-Object System.Collections.Generic.List[object]

  if ($null -eq $Options) {
    # nichts
  }
  elseif ($Options -is [string]) {
    $items.Add($Options) | Out-Null
  }
  elseif ($Options -is [System.Collections.IDictionary]) {
    # Hashtable ist IEnumerable -> darf NICHT automatisch zerlegt werden, wenn es eine "single option" ist.
    $hasLabel = $false
    $hasValue = $false
    foreach ($k in $Options.Keys) {
      if ($k.ToString().Equals("Label",[System.StringComparison]::OrdinalIgnoreCase)) { $hasLabel = $true }
      if ($k.ToString().Equals("Value",[System.StringComparison]::OrdinalIgnoreCase)) { $hasValue = $true }
    }

    if ($hasLabel -or $hasValue) {
      # Single option => als EIN Element behandeln
      $items.Add($Options) | Out-Null
    } else {
      # Dictionary ohne Label/Value => ebenfalls als EIN Element (nicht zerlegen)
      $items.Add($Options) | Out-Null
    }
  }
  elseif (($Options -is [System.Collections.IEnumerable]) -and -not ($Options -is [string])) {
    # Arrays/Listen/Enumerables => explizit einsammeln
    foreach ($x in $Options) { $items.Add($x) | Out-Null }
  }
  else {
    $items.Add($Options) | Out-Null
  }

  # 2) In UI-Options (Label/Value) transformieren
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($o in $items) {
    if ($null -eq $o) { continue }

    if ($o -is [string]) {
      $out.Add([pscustomobject]@{ Label = $o; Value = $o }) | Out-Null
      continue
    }

    if ($o -is [System.Collections.IDictionary]) {
      $label = $null
      $value = $null

      foreach ($k in $o.Keys) {
        if ($k -match '^(?i)label$') { $label = $o[$k] }
        if ($k -match '^(?i)value$') { $value = $o[$k] }
      }

      if ($null -eq $label) { $label = [string]$o }
      if ($null -eq $value) { $value = $label }

      $out.Add([pscustomobject]@{ Label = [string]$label; Value = $value }) | Out-Null
      continue
    }

    $p = $o.PSObject.Properties
    $labelProp = $p | Where-Object { $_.Name -match '^(?i)label$' } | Select-Object -First 1
    $valueProp = $p | Where-Object { $_.Name -match '^(?i)value$' } | Select-Object -First 1

    if ($labelProp) {
      $label = [string]$labelProp.Value
      $value = if ($valueProp) { $valueProp.Value } else { $label }
      $out.Add([pscustomobject]@{ Label = $label; Value = $value }) | Out-Null
      continue
    }

    $out.Add([pscustomobject]@{ Label = [string]$o; Value = $o }) | Out-Null
  }

  # 3) Rückgabe ohne @(...)-Binder: echtes Array via .ToArray()
  return $out.ToArray()
}

<#
.SYNOPSIS
    Single-choice arrow-key menu that returns the chosen INDEX (not the value).
.DESCRIPTION
    Low-level building block behind Read-SelectValue / Read-YesNo. Renders Options
    as a vertical list, moves the highlighted row with the up/down arrow keys, and
    returns as soon as Enter is pressed. Prefer Read-SelectValue in calling code —
    use this directly only when you specifically need the index rather than the
    selected option's value.
.PARAMETER Title
    Question/heading shown above the list, in cyan.
.PARAMETER Message
    Optional one-line clarification shown under the title, in gray.
.PARAMETER Options
    Choices, in any shape accepted by ConvertTo-UiOptions.
.PARAMETER Default
    Index that is highlighted when the menu first appears.
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-SelectIndex -Title "Pick one" -Options @("A","B","C") -Default 1
    # Returns 0, 1, or 2 depending on what the user picked; -1 if Escape was pressed.
.OUTPUTS
    System.Int32 — the chosen index, or -1 if the user pressed Escape.
#>
function Read-SelectIndex {
  param(
    [string]$Title,
    [string]$Message,
    [object]$Options,
    [int]$Default = 0,

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  $ui = ConvertTo-UiOptions -Options $Options
  if (-not $ui -or $ui.Count -eq 0) { throw "Options leer: $Title" }

  $labels = @($ui | ForEach-Object { $_.Label })
  $idx = [Math]::Min([Math]::Max($Default,0), $labels.Count-1)

  while ($true) {
    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    if ($Message)  { Write-Host $Message -ForegroundColor Gray }
    Write-Host $script:KeyHintSelect -ForegroundColor Gray
    Write-Host ""

    for ($i=0; $i -lt $labels.Length; $i++) {
      if ($i -eq $idx) { Write-Host ("> " + $labels[$i]) -ForegroundColor Green }
      else { Write-Host ("  " + $labels[$i]) }
    }

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $idx = ($idx - 1 + $labels.Length) % $labels.Length }
      'DownArrow' { $idx = ($idx + 1) % $labels.Length }
      'Enter'     { return $idx }
      'Escape'    { return -1 }
    }
  }
}

<#
.SYNOPSIS
    Single-choice arrow-key menu — the main entry point for "pick one of these".
.DESCRIPTION
    Shows Options as a vertical list (up/down arrows to move, Enter to confirm,
    Escape to cancel) and returns the VALUE of the chosen option, not its index or
    label. Optionally runs a background Loader first (with its own spinner) to
    fetch the option list asynchronously — e.g. querying an API for available
    regions before showing the menu — and can pre-select by value once the loader
    result is in, via DefaultValue.
.PARAMETER Title
    Question/heading shown above the list, in cyan.
.PARAMETER Message
    Optional one-line clarification shown under the title, in gray.
.PARAMETER Options
    Choices, in any shape accepted by ConvertTo-UiOptions. Ignored if Loader
    is supplied and returns a result.
.PARAMETER Default
    Index highlighted when the menu first appears (before any Loader/DefaultValue
    adjustment).
.PARAMETER Loader
    Optional scriptblock run in a background job before the menu is shown, with a
    spinner animating over LoadingMessage while it runs. Its result (if any)
    replaces Options. The job receives $env:PATH as its first argument, followed
    by LoaderArgs.
.PARAMETER LoadingMessage
    Text shown next to the spinner while Loader is running.
.PARAMETER DefaultValue
    After Loader replaces Options, pre-select the option whose Value equals this.
.PARAMETER LoaderArgs
    Extra positional arguments appended after $env:PATH when invoking Loader.
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-SelectValue -Title "Target platform" -Options @(
            @{ Label = "Azure AKS"; Value = "aks" }
            @{ Label = "AWS EKS";   Value = "eks" }
        ) -Default 0
    aks
.EXAMPLE
    PS> Read-SelectValue -Title "Region" -LoadingMessage "Fetching regions..." `
            -Loader { param($path) $env:PATH = $path; Get-AvailableRegions }
.OUTPUTS
    The Value of the chosen option (any type), or $null if the user pressed Escape.
#>
function Read-SelectValue {
  param(
    [string]$Title,
    [string]$Message,
    $Options,
    [int]$Default = 0,

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @(),
    [scriptblock]$Loader = $null,     # optional: runs first, shows spinner, result replaces $Options
    [string]$LoadingMessage = "Lade Daten...",
    [string]$DefaultValue = "",       # pre-select by value after Loader runs
    [object[]]$LoaderArgs = @()       # extra args passed to Loader after $env:PATH
  )

  # If a loader is provided: render the context+title, show spinner, run loader, then show result
  if ($Loader) {
    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    if ($Message) { Write-Host $Message -ForegroundColor Gray }
    Write-Host ""

    $frames = @('|','/','-','\'); $fi = 0
    $loaderMaxLen = 0
    $job = Start-Job -ScriptBlock $Loader -ArgumentList (@($env:PATH) + $LoaderArgs)
    while ($job.State -eq 'Running') {
      $loaderLine = "  $($frames[$fi++ % 4]) $LoadingMessage"
      $loaderWidth = Get-ConsoleWidth
      if ($loaderLine.Length -gt $loaderWidth) { $loaderLine = $loaderLine.Substring(0, $loaderWidth - 3) + "..." }
      $loaderMaxLen = [Math]::Max($loaderMaxLen, $loaderLine.Length)
      [Console]::Write("`r$loaderLine" + (" " * ($loaderMaxLen - $loaderLine.Length)))
      Start-Sleep -Milliseconds 150
    }
    # See Invoke-WithSpinner's matching clear for why this is capped at the
    # console width instead of just $loaderMaxLen + 6.
    [Console]::Write("`r" + (" " * [Math]::Min($loaderMaxLen + 6, (Get-ConsoleWidth))) + "`r")
    # Suppress Progress while receiving — see Invoke-ScriptBlockWithSpinner's
    # Receive-Job for why an unsuppressed replay can leave a stuck progress
    # bar on screen if Loader's own code ever calls Write-Progress.
    $prevProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { $loaded = Receive-Job $job -Wait } finally { $ProgressPreference = $prevProgressPreference }
    Remove-Job $job -Force
    if ($loaded) { $Options = $loaded }

    # Re-calculate default index based on DefaultValue after Loader replaced options
    if ($DefaultValue) {
        $ui2 = ConvertTo-UiOptions -Options $Options
        $found = ($ui2 | ForEach-Object { $_.Value }).IndexOf($DefaultValue)
        if ($found -ge 0) { $Default = $found }
    }
  }

  $ui = ConvertTo-UiOptions -Options $Options
  if (-not $ui -or $ui.Count -eq 0) { throw "Options leer: $Title" }

  $i = Read-SelectIndex -Title $Title -Message $Message -Options $ui -Default $Default `
    -ContextTitle $ContextTitle -ContextHint $ContextHint -ContextCurrent $ContextCurrent -MaskKeys $MaskKeys

  if ($i -lt 0) { return $null }
  return $ui[$i].Value
}

<#
.SYNOPSIS
    Two-choice Yes/No menu (arrow keys + Enter) that returns a boolean.
.DESCRIPTION
    Thin wrapper over Read-SelectValue with exactly two options. Pressing Escape
    is treated the same as choosing "No" (returns $false), since there's no
    natural "cancel" distinct from declining a yes/no question.
.PARAMETER Title
    Question shown above the two choices, in cyan.
.PARAMETER Message
    Optional one-line clarification, in gray.
.PARAMETER DefaultYes
    Whether "Yes" is highlighted first.
.PARAMETER YesLabel
    Custom label instead of "Yes" (e.g. "Overwrite").
.PARAMETER NoLabel
    Custom label instead of "No" (e.g. "Keep existing").
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-YesNo -Title "Delete the existing cluster first?" -DefaultYes $false
.OUTPUTS
    System.Boolean
#>
function Read-YesNo {
  param(
    [string]$Title,
    [string]$Message,
    [bool]$DefaultYes = $true,
    [string]$YesLabel = "Yes",
    [string]$NoLabel  = "No",

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  $opts = @(
    @{ Label = $YesLabel; Value = $true  }
    @{ Label = $NoLabel;  Value = $false }
  )
  $def = if ($DefaultYes) { 0 } else { 1 }

  $val = Read-SelectValue -Title $Title -Message $Message -Options $opts -Default $def `
    -ContextTitle $ContextTitle -ContextHint $ContextHint -ContextCurrent $ContextCurrent -MaskKeys $MaskKeys

  if ($null -eq $val) { return $false }
  return [bool]$val
}

<#
.SYNOPSIS
    Checkbox-style menu — Space toggles an item, Enter confirms the whole set.
.DESCRIPTION
    Renders Options as a vertical list of [ ]/[x] checkboxes. Use this when the
    user can pick any number of items (zero, one, or several) rather than exactly
    one — for "exactly one of several" use Read-SelectValue instead.
.PARAMETER Title
    Heading shown above the list, in cyan.
.PARAMETER Message
    Optional one-line clarification, in gray.
.PARAMETER Options
    Choices, in any shape accepted by ConvertTo-UiOptions.
.PARAMETER DefaultValues
    Values that start out checked.
.PARAMETER Disabled
    A hashtable keyed by option Label whose entries are shown grayed-out and
    cannot be toggled (e.g. a component that's a hard prerequisite of another
    selected component).
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-MultiSelectValues -Title "Select components" `
            -Options @("Ingress","Storage","GitOps") -DefaultValues @("Ingress")
    Ingress
    GitOps
.OUTPUTS
    System.Object[] — the Values of the checked options, or $null if the user
    pressed Escape.
#>
function Read-MultiSelectValues {
  param(
    [string]$Title,
    [string]$Message,
    [object]$Options,
    [object[]]$DefaultValues = @(),
    [hashtable]$Disabled = @{},

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  $ui = ConvertTo-UiOptions -Options $Options
  if (-not $ui -or $ui.Count -eq 0) { throw "Options leer: $Title" }

  $labels = @($ui | ForEach-Object { $_.Label })

  $sel = @{}
  0..($labels.Count-1) | ForEach-Object { $sel[$_] = $false }

  # defaults by value
  for ($i=0; $i -lt $ui.Count; $i++) {
    if ($DefaultValues -contains $ui[$i].Value) { $sel[$i] = $true }
  }

  $idx = 0
  $done = $false

  while (-not $done) {
    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    if ($Message)  { Write-Host $Message -ForegroundColor Gray }
    Write-Host $script:KeyHintToggle -ForegroundColor Gray
    Write-Host ""

    for ($i=0; $i -lt $labels.Length; $i++) {
      $mark = if ($sel[$i]) { "[x]" } else { "[ ]" }
      $prefix = if ($i -eq $idx) { ">" } else { " " }
      $name = $labels[$i]

      $isDisabled = $Disabled.ContainsKey($name) -and $Disabled[$name]
      $line = "{0} {1} {2}" -f $prefix, $mark, $name

      if ($isDisabled) { Write-Host $line -ForegroundColor DarkGray }
      elseif ($i -eq $idx) { Write-Host $line -ForegroundColor Green }
      else { Write-Host $line }
    }

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $idx = ($idx - 1 + $labels.Length) % $labels.Length }
      'DownArrow' { $idx = ($idx + 1) % $labels.Length }
      'Spacebar'  {
        $name = $labels[$idx]
        $isDisabled = $Disabled.ContainsKey($name) -and $Disabled[$name]
        if (-not $isDisabled) { $sel[$idx] = -not $sel[$idx] }
      }
      'Enter'  { $done = $true }
      'Escape' { return $null }
    }
  }

  $idxs = @($sel.GetEnumerator() | Where-Object Value | ForEach-Object { [int]$_.Key } | Sort-Object)
  return @($idxs | ForEach-Object { $ui[$_].Value })
}

<#
.SYNOPSIS
    Two-level component picker: collapsible groups containing checkboxes and/or
    mutually-exclusive radio choices.
.DESCRIPTION
    Built for "select which components to install" screens where some choices are
    independent on/off switches (Type="check") and others are a single pick among
    alternatives (Type="radio", grouped by RadioGroup) — optionally nested under a
    toggleable group header (Type="group" with Children) so picking "Ingress" then
    lets you pick NGINX vs. Traefik underneath it, and unchecking the group hides
    its radio children from both the screen and the result.
.PARAMETER Title
    Heading shown at the top, in cyan.
.PARAMETER Message
    Optional one-line clarification, in gray.
.PARAMETER Sections
    Array of @{ Label = "<section name>"; Items = @(...) }. Each Items entry is
    one of:
      @{ Label; Value; Type = "check";  Default }                        — standalone checkbox
      @{ Label; Value; Type = "group";  Default; Children = @(...) }     — toggleable group
      @{ Label; Value; Type = "radio"; RadioGroup; Default }             — inside a group's Children;
                                                                            exactly one per RadioGroup
                                                                            ends up checked
    A section with only one Items entry skips printing its own Label as a
    separator (it would be redundant noise above a single row).
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-ComponentSelectionScreen -Title "Select components" -Sections @(
            @{ Label = "Ingress & LB"; Items = @(
                @{ Label = "Ingress"; Value = "ingress"; Type = "group"; Default = $true; Children = @(
                    @{ Label = "NGINX";    Value = "nginx";    Type = "radio"; RadioGroup = "ingress"; Default = $true }
                    @{ Label = "Traefik";  Value = "traefik";  Type = "radio"; RadioGroup = "ingress"; Default = $false }
                )}
                @{ Label = "MetalLB"; Value = "metallb"; Type = "check"; Default = $true }
            )}
        )
    # -> @{ ingress = $true; nginx = $true; traefik = $false; metallb = $true }
.OUTPUTS
    System.Collections.Hashtable mapping each item's Value to $true/$false, or
    $null if the user pressed Escape.
#>
function Read-ComponentSelectionScreen {
  param(
    [string]$Title   = "Select components",
    [string]$Message = "",
    [object[]]$Sections,

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  # Build flat list: sep | group | check | radio
  # radio items carry ParentValue so we know which group they belong to
  $flat = [System.Collections.Generic.List[hashtable]]::new()
  foreach ($sec in $Sections) {
    $flat.Add(@{ Kind="sep"; Label=$sec.Label }) | Out-Null
    foreach ($item in @($sec.Items)) {
      if ($item.Type -eq "group") {
        $flat.Add(@{ Kind="group"; Label=$item.Label; Value=$item.Value; Checked=[bool]$item.Default }) | Out-Null
        foreach ($child in @($item.Children)) {
          $flat.Add(@{
            Kind        = "radio"
            Label       = $child.Label
            Value       = $child.Value
            RadioGroup  = $child.RadioGroup
            Checked     = [bool]$child.Default
            ParentValue = $item.Value
          }) | Out-Null
        }
      } else {
        $flat.Add(@{ Kind=$item.Type; Label=$item.Label; Value=$item.Value; Checked=[bool]$item.Default }) | Out-Null
      }
    }
  }

  # Ensure each radio group has exactly one item selected
  $flat | Where-Object { $_.Kind -eq "radio" } | Group-Object RadioGroup | ForEach-Object {
    $sel = @($_.Group | Where-Object { $_.Checked })
    if ($sel.Count -eq 0) { $_.Group[0].Checked = $true }
    elseif ($sel.Count -gt 1) { $_.Group | ForEach-Object { $_.Checked = $false }; $_.Group[0].Checked = $true }
  }

  # Visible interactive items: sep skipped, radios hidden when parent group unchecked
  function Get-Nav($f) {
    $checkedGroups = @($f | Where-Object { $_.Kind -eq "group" -and $_.Checked } | ForEach-Object { $_.Value })
    @($f | Where-Object {
      $_.Kind -notin @("sep") -and
      ($_.Kind -ne "radio" -or $checkedGroups -contains $_.ParentValue)
    })
  }

  $cursor = 0
  $done   = $false

  while (-not $done) {
    $nav = Get-Nav $flat
    if ($cursor -ge $nav.Count) { $cursor = [Math]::Max(0, $nav.Count - 1) }

    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    if ($Message) { Write-Host $Message -ForegroundColor Gray }
    Write-Host $script:KeyHintToggle -ForegroundColor Gray
    Write-Host ""

    # Pre-count top-level items per section — single-item sections skip the separator.
    # With only one Section overall the outer Title already identifies the screen,
    # so the separator would just repeat it — skip it unconditionally in that case.
    $skipAllSeparators = @($Sections).Count -le 1
    $secCounts = @{}; $curSep = ""
    foreach ($item in $flat) {
      if ($item.Kind -eq "sep") { $curSep = $item.Label; $secCounts[$curSep] = 0 }
      elseif ($item.Kind -ne "radio" -and $curSep) { $secCounts[$curSep]++ }
    }

    $lastSep = ""
    $navPos  = 0
    foreach ($item in $flat) {
      if ($item.Kind -eq "sep") {
        $lastSep = $item.Label
        continue
      }
      if ($item.Kind -eq "radio") {
        $parent = $flat | Where-Object { $_.Kind -eq "group" -and $_.Value -eq $item.ParentValue } | Select-Object -First 1
        if (-not $parent -or -not $parent.Checked) { continue }
      }

      # Print section separator label before first item of a new section
      if ($lastSep) {
        if (-not $skipAllSeparators -and $secCounts[$lastSep] -gt 1) {
          Write-Host ""
          Write-Host $lastSep -ForegroundColor DarkGray
        }
        $lastSep = ""
      }

      $isFocused = ($navPos -eq $cursor)
      $arrow     = if ($isFocused) { ">" } else { " " }

      switch ($item.Kind) {
        "group" {
          $mark = if ($item.Checked) { "[X]" } else { "[ ]" }
          $line = "$arrow $mark $($item.Label)"
          if ($isFocused) { Write-Host $line -ForegroundColor Green }
          else            { Write-Host $line }
        }
        "check" {
          $mark = if ($item.Checked) { "[X]" } else { "[ ]" }
          $line = "$arrow $mark $($item.Label)"
          if ($isFocused) { Write-Host $line -ForegroundColor Green }
          else            { Write-Host $line }
        }
        "radio" {
          $mark = if ($item.Checked) { "(*)" } else { "( )" }
          $line = "$arrow     $mark $($item.Label)"
          if ($isFocused) { Write-Host $line -ForegroundColor Green }
          else            { Write-Host $line -ForegroundColor Gray }
        }
      }
      $navPos++
    }

    Write-Host ""
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
      'DownArrow' { $cursor = [Math]::Min($nav.Count - 1, $cursor + 1) }
      'Spacebar'  {
        $item = $nav[$cursor]
        switch ($item.Kind) {
          "group" {
            $item.Checked = -not $item.Checked
            $nav2 = Get-Nav $flat
            if ($cursor -ge $nav2.Count) { $cursor = [Math]::Max(0, $nav2.Count - 1) }
          }
          "check" { $item.Checked = -not $item.Checked }
          "radio" {
            $flat | Where-Object { $_.Kind -eq "radio" -and $_.RadioGroup -eq $item.RadioGroup } |
              ForEach-Object { $_.Checked = $false }
            $item.Checked = $true
          }
        }
      }
      'Enter'  { $done = $true }
      'Escape' { return $null }
    }
  }

  # Build result: group/check values + radio values (only from checked groups)
  $result = @{}
  $checkedGroups = @($flat | Where-Object { $_.Kind -eq "group" -and $_.Checked } | ForEach-Object { $_.Value })
  $flat | Where-Object { $_.Kind -in @("group", "check") } | ForEach-Object { $result[$_.Value] = $_.Checked }
  $flat | Where-Object { $_.Kind -eq "radio" -and $checkedGroups -contains $_.ParentValue } |
    ForEach-Object { $result[$_.Value] = $_.Checked }
  return $result
}

<#
.SYNOPSIS
    Free-text input prompt with an optional default value.
.DESCRIPTION
    Draws the context panel, then a plain Read-Host prompt. If the user presses
    Enter without typing anything and Default is non-empty, Default is returned;
    otherwise whatever was typed (including an empty string) is returned.
.PARAMETER Prompt
    The question shown to the user. If Default is set, it's appended as "[Default]".
.PARAMETER Default
    Value returned when the user submits an empty line.
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-Plain -Prompt "Cluster name" -Default "my-cluster"
.OUTPUTS
    System.String
#>
function Read-Plain {
  param(
    [string]$Prompt,
    [string]$Default = "",
    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys
  $displayPrompt = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
  $value = Read-Host $displayPrompt
  if ([string]::IsNullOrWhiteSpace($value) -and $Default) { $Default } else { $value }
}

# -------------------------
# Secret input
# Private helper behind Read-SecretPlain/Read-SecretPlainConfirm — masks the
# input via Read-Host -AsSecureString, then immediately decrypts back to a plain
# string in memory since every caller in this module needs the plain value anyway
# (e.g. to hand to a CLI tool's --password flag). Not exported on its own.
# -------------------------
function Read-Secret {
  param(
    [string]$Prompt
  )

  $sec = Read-Host -AsSecureString $Prompt
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

<#
.SYNOPSIS
    Masked single-entry secret prompt (input is hidden while typing).
.DESCRIPTION
    Draws the context panel, then reads one masked value — no confirmation/retype
    step. Use Read-SecretPlainConfirm instead when the value is being SET for the
    first time and a typo would be hard to notice (e.g. a new admin password);
    use this one when re-entering an already-known secret (e.g. an existing API
    token) where there's nothing to confirm against.
.PARAMETER Prompt
    The question shown to the user.
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-SecretPlain -Prompt "API token"
.OUTPUTS
    System.String — the plain-text secret (already decrypted from the masked input).
#>
function Read-SecretPlain {
  param(
    [string]$Prompt,

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys
  Read-Secret $Prompt
}

<#
.SYNOPSIS
    Masked secret prompt with retype-to-confirm — for setting a new secret.
.DESCRIPTION
    Asks for the secret twice (both masked); if they don't match, or the first
    entry is empty, it shows a warning and loops back to asking again rather than
    failing outright — there's no Escape/cancel path, since this is normally used
    at a point in a flow where a value is mandatory.
.PARAMETER Prompt1
    Label for the first entry.
.PARAMETER Prompt2
    Label for the confirmation entry.
.PARAMETER ContextTitle
    Forwarded to Write-Context — see Write-Context for ContextTitle/ContextHint/
    ContextCurrent/MaskKeys.
.EXAMPLE
    PS> Read-SecretPlainConfirm -Prompt1 "New admin password" -Prompt2 "Confirm password"
.OUTPUTS
    System.String — the plain-text secret, once both entries matched.
#>
function Read-SecretPlainConfirm {
  param(
    [string]$Prompt1 = "Password",
    [string]$Prompt2 = "Confirm password",

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  while ($true) {
    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys

    $p1 = Read-Secret $Prompt1
    if ([string]::IsNullOrWhiteSpace($p1)) {
      Write-Host "  Password must not be empty. Please try again (Ctrl-C to cancel)." -ForegroundColor Yellow
      Start-Sleep -Milliseconds 700
      continue
    }

    $p2 = Read-Secret $Prompt2
    if ($p1 -ne $p2) {
      Write-Host "  Passwords do not match. Please try again." -ForegroundColor Yellow
      Start-Sleep -Milliseconds 700
      continue
    }
    return $p1
  }
}

<#
.SYNOPSIS
    Runs an external executable in the background while animating a spinner,
    then reports its exit code.
.DESCRIPTION
    Starts Executable in a background job (so the spinner can animate on the main
    thread while it runs), forwarding the current $env:PATH and $env:KUBECONFIG
    into the job since background jobs don't inherit session environment
    automatically. Output is captured either way; it's only printed to the
    console if the process failed (non-zero exit code) or ShowOutput was passed —
    on success it stays silent so a multi-step install doesn't drown in noise.
.PARAMETER Message
    Text shown next to the spinner while the process runs.
.PARAMETER Executable
    Path or name of the executable to run (resolved via $env:PATH in the job).
.PARAMETER Arguments
    Arguments passed to Executable, as an array (one element per argument —
    do not pre-join them into a single string).
.PARAMETER ShowOutput
    Print the process's output even on success.
.PARAMETER EnvVars
    Extra environment variables to set inside the job before running Executable.
.PARAMETER OutputVariable
    A [ref] variable to receive the captured output lines, e.g. `([ref]$out)`.
.EXAMPLE
    PS> Invoke-WithSpinner -Message "Adding Helm repository..." -Executable "helm" `
            -Arguments @("repo", "add", "openbao", $repoUrl, "--force-update")
    0
.OUTPUTS
    System.Int32 — the exit code of Executable.
#>
# Private helper behind every spinner loop below — current terminal width,
# with a sane fallback when it can't be determined (e.g. redirected output).
# `\r` only rewinds the CURRENT row, so a line that wrapped onto a second row
# never gets fully cleared on the next redraw — every spinner line must stay
# within this width. Not exported.
function Get-ConsoleWidth {
  try { [Math]::Max(20, [Console]::WindowWidth - 1) } catch { 119 }
}

function Invoke-WithSpinner {
  [CmdletBinding()]
  param(
    [string]$Message,
    [string]$Executable,
    [string[]]$Arguments = @(),
    [switch]$ShowOutput,
    [hashtable]$EnvVars = @{},
    $OutputVariable = $null
  )

  $argsEncoded       = $Arguments -join "`0"
  $currentPath       = $env:PATH
  $currentKubeconfig = $env:KUBECONFIG

  $job = Start-Job -ScriptBlock {
    param($exe, $argsEncoded, $path, $envVars, $kubeconfig)
    $env:PATH = $path
    if ($kubeconfig) { $env:KUBECONFIG = $kubeconfig }
    foreach ($k in $envVars.Keys) { Set-Item "env:$k" $envVars[$k] }
    $argList = if ($argsEncoded) { $argsEncoded -split "`0" } else { @() }
    $out = & $exe @argList 2>&1
    [PSCustomObject]@{ Output = $out; ExitCode = $LASTEXITCODE }
  } -ArgumentList $Executable, $argsEncoded, $currentPath, $EnvVars, $currentKubeconfig

  $frames = @('|', '/', '-', '\')
  $i = 0
  $maxLen = 0
  try {
    while ($job.State -eq 'Running') {
      $line = "  $($frames[$i % 4]) $Message"
      $width = Get-ConsoleWidth
      if ($line.Length -gt $width) { $line = $line.Substring(0, $width - 3) + "..." }
      $maxLen = [Math]::Max($maxLen, $line.Length)
      [Console]::Write("`r$line" + (" " * ($maxLen - $line.Length)))
      $i++
      Start-Sleep -Milliseconds 150
    }
  } finally {
    if ($job.State -eq 'Running') { Stop-Job -Job $job }
    # Cap at the console width too — $maxLen can equal Get-ConsoleWidth
    # exactly (the line-truncation above stops it from exceeding that), so
    # the un-capped "+6" margin used to push the clear itself past the
    # width and wrap onto a second row, leaving that row's blank padding
    # behind as a stray empty line once the cursor returns to column 0.
    [Console]::Write("`r" + (" " * [Math]::Min($maxLen + 6, (Get-ConsoleWidth))) + "`r")
  }

  # Suppress Progress while receiving — see Invoke-ScriptBlockWithSpinner's
  # Receive-Job for why an unsuppressed replay can leave a stuck progress
  # bar on screen if Executable's output is ever misread as a progress record.
  $prevProgressPreference = $ProgressPreference
  $ProgressPreference = 'SilentlyContinue'
  try { $result = Receive-Job -Job $job -Wait } finally { $ProgressPreference = $prevProgressPreference }
  Remove-Job -Job $job -Force

  if ($null -ne $result.Output) {
    if ($null -ne $OutputVariable -and $OutputVariable -is [ref]) { $OutputVariable.Value = $result.Output }
    $isError = $result.ExitCode -ne 0
    if ($isError -or $ShowOutput) {
      $color = if ($isError) { "Red" } else { "Gray" }
      foreach ($line in $result.Output) { if ($line) { Write-Host $line -ForegroundColor $color } }
    }
  }

  return [int]$result.ExitCode
}

<#
.SYNOPSIS
    Runs a scriptblock in the background while animating a spinner on the
    current console line, then returns its result.
.DESCRIPTION
    Generalization of Invoke-WithSpinner for arbitrary PowerShell code instead
    of an external executable — e.g. a multi-step Invoke-WebRequest +
    Expand-Archive sequence. ScriptBlock runs in a background job, which does
    NOT have access to the caller's variables, functions, or imported
    modules — pass everything it needs through ArgumentList and stick to
    built-in cmdlets/.NET types inside it. Re-throws ScriptBlock's error (if
    any) so the caller's own try/catch handles it exactly as if the code had
    run inline.
.PARAMETER Message
    Text shown next to the spinner while ScriptBlock runs.
.PARAMETER ScriptBlock
    The code to run in the background. Receives ArgumentList as its param()
    values, in order.
.PARAMETER ArgumentList
    Values passed positionally into ScriptBlock.
.EXAMPLE
    PS> Invoke-ScriptBlockWithSpinner -Message "kubectl: Downloading v1.29.0..." -ScriptBlock {
            param($Url, $OutFile)
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        } -ArgumentList @($url, $path)
    # If ScriptBlock reports Write-Progress (Invoke-WebRequest does), its
    # latest status — e.g. "Downloaded: 2.7 MB of 15.6 MB" — is appended to
    # Message automatically.
.OUTPUTS
    Whatever ScriptBlock returns via its own output stream. Throws if
    ScriptBlock raised an error.
#>
function Invoke-ScriptBlockWithSpinner {
  [CmdletBinding()]
  param(
    [string]$Message,
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [object[]]$ArgumentList = @()
  )

  $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList

  $frames = @('|', '/', '-', '\')
  $i = 0
  $maxLen = 0
  try {
    while ($job.State -eq 'Running') {
      $line = "  $($frames[$i % 4]) $Message"

      # Surface ScriptBlock's own Write-Progress output (Invoke-WebRequest
      # reports download progress this way) — the job's Progress stream is
      # the only thing that crosses the background-job boundary live.
      $progress = $job.ChildJobs[0].Progress
      if ($progress.Count -gt 0) {
        $last = $progress[$progress.Count - 1]
        if ($last.StatusDescription)        { $line += "  $($last.StatusDescription)" }
        elseif ($last.PercentComplete -ge 0) { $line += "  ($($last.PercentComplete)%)" }
      } else {
        # Nothing reported yet — ScriptBlock is still starting up (e.g. DNS
        # lookup / TLS handshake before Invoke-WebRequest's first progress
        # record). Without this the line just sits on $Message unchanged,
        # which looks identical to a hang.
        $line += "  Initializing..."
      }

      $width = Get-ConsoleWidth
      if ($line.Length -gt $width) { $line = $line.Substring(0, $width - 3) + "..." }
      $maxLen = [Math]::Max($maxLen, $line.Length)
      [Console]::Write("`r$line" + (" " * ($maxLen - $line.Length)))
      $i++
      Start-Sleep -Milliseconds 150
    }
  } finally {
    if ($job.State -eq 'Running') { Stop-Job -Job $job }
    # See Invoke-WithSpinner's matching clear for why this is capped at the
    # console width instead of just $maxLen + 6.
    [Console]::Write("`r" + (" " * [Math]::Min($maxLen + 6, (Get-ConsoleWidth))) + "`r")
  }

  $failed      = $job.State -eq 'Failed'
  $errorReason = $job.ChildJobs[0].JobStateInfo.Reason

  # Receive-Job replays every buffered stream into THIS session, including
  # Progress — without suppressing it here, any not-yet-"Completed" progress
  # record the job recorded (Invoke-WebRequest, Expand-Archive, Remove-Item
  # all call Write-Progress) gets handed to the host's progress UI and can
  # stick around on screen since nothing ever sends its "Completed" signal.
  $prevProgressPreference = $ProgressPreference
  $ProgressPreference = 'SilentlyContinue'
  try {
    $result = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
  } finally {
    $ProgressPreference = $prevProgressPreference
  }
  Remove-Job -Job $job -Force

  if ($failed) { throw $errorReason }
  return $result
}

Export-ModuleMember -Function @(
  'ToSafeName'
  'Write-Context'
  'Write-Section'
  'ConvertTo-UiOptions'
  'Read-SelectIndex'
  'Read-SelectValue'
  'Read-YesNo'
  'Read-MultiSelectValues'
  'Read-ComponentSelectionScreen'
  'Read-Plain'
  'Read-SecretPlain'
  'Read-SecretPlainConfirm'
  'Invoke-WithSpinner'
  'Invoke-ScriptBlockWithSpinner'
)
