Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# Basics
# -------------------------
function ToSafeName {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  return ($s -replace '[^a-zA-Z0-9]', '-').ToLower()
}

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

# -------------------------
# Context / Sections
# - Menüs clearen immer den Screen, daher rendern wir Kontext + Werte bei jedem Refresh erneut.
# -------------------------
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
      if ($null -eq $v) { $v = "" }
      if ($MaskKeys -contains $k) { $v = "********" }

      Write-Host ("{0}: {1}" -f $k, $v) -ForegroundColor Gray
    }
  }
}

function Write-Section {
  param(
    [string]$Title,
    [string]$Hint = "",
    $Current = $null,
    [string[]]$MaskKeys = @()
  )
  Write-Context -Title $Title -Hint $Hint -Current $Current -MaskKeys $MaskKeys
}

# -------------------------
# Options: Label/Value normalization
# Supports:
# - "text"                     => Label="text", Value="text"
# - @{Label="X"; Value=123}     => Label="X", Value=123
# - [pscustomobject] with Label/Value
# - fallback => Label=ToString(), Value=object
# -------------------------
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

# -------------------------
# Select (vertical only)
# - Returns index or value
# -------------------------
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
    $job = Start-Job -ScriptBlock $Loader -ArgumentList (@($env:PATH) + $LoaderArgs)
    while ($job.State -eq 'Running') {
      [Console]::Write("`r  $($frames[$fi++ % 4]) $LoadingMessage")
      Start-Sleep -Milliseconds 150
    }
    [Console]::Write("`r" + (" " * ($LoadingMessage.Length + 6)) + "`r")
    $loaded = Receive-Job $job -Wait; Remove-Job $job -Force
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

# -------------------------
# Yes/No (vertical only, returns bool)
# -------------------------
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

# -------------------------
# MultiSelect (vertical, returns Values)
# - Space toggles, Enter confirms
# - Options support Label/Value
# -------------------------
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

# -------------------------
# Component selection screen — two-level: group headers + checkboxes/radios
#
# $Sections = @(
#   @{ Label = "Ingress"; Items = @(
#     @{ Label = "NGINX"; Value = "nginx";    Type = "radio"; RadioGroup = "ingress"; Default = $true  }
#     @{ Label = "Traefik"; Value = "traefik"; Type = "radio"; RadioGroup = "ingress"; Default = $false }
#     @{ Label = "MetalLB"; Value = "metallb"; Type = "check";                        Default = $true  }
#   )}
# )
#
# Returns hashtable: Value -> $true/$false.
# For radio groups exactly one item per group is $true.
# Returns $null if the user presses Escape.
# -------------------------
function Read-ComponentSelectionScreen {
  # Two-level component selector.
  #
  # $Sections = @(
  #   @{ Label = "Ingress & LB"          # non-interactive separator (Screen-1 group name)
  #      Items = @(
  #        @{ Label="Ingress"; Value="ingress"; Type="group"; Default=$true; Children=@(
  #            @{ Label="NGINX"; Value="nginx"; Type="radio"; RadioGroup="ingress"; Default=$true }
  #            @{ Label="Traefik"; Value="traefik"; Type="radio"; RadioGroup="ingress"; Default=$false }
  #        )}
  #        @{ Label="MetalLB"; Value="metallb"; Type="check"; Default=$true }
  #      )
  #   }
  # )
  # Returns hashtable: Value -> $true/$false.  $null on Escape.
  param(
    [string]$Title   = "Select components",
    [string]$Message = "",
    [object[]]$Sections
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

    Clear-Host
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
    Write-Host "  Space = toggle   Enter = confirm   Esc = cancel" -ForegroundColor DarkGray
    Write-Host ""

    # Pre-count top-level items per section — single-item sections skip the separator
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
        if ($secCounts[$lastSep] -gt 1) {
          Write-Host ""
          Write-Host "  $lastSep" -ForegroundColor DarkGray
        }
        $lastSep = ""
      }

      $isFocused = ($navPos -eq $cursor)
      $arrow     = if ($isFocused) { ">" } else { " " }

      switch ($item.Kind) {
        "group" {
          $mark = if ($item.Checked) { "[X]" } else { "[ ]" }
          $line = "  $arrow $mark $($item.Label)"
          if ($isFocused) { Write-Host $line -ForegroundColor Green }
          else            { Write-Host $line }
        }
        "check" {
          $mark = if ($item.Checked) { "[X]" } else { "[ ]" }
          $line = "  $arrow $mark $($item.Label)"
          if ($isFocused) { Write-Host $line -ForegroundColor Green }
          else            { Write-Host $line }
        }
        "radio" {
          $mark = if ($item.Checked) { "(*)" } else { "( )" }
          $line = "  $arrow     $mark $($item.Label)"
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

# -------------------------
# Plain input
# -------------------------
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

function Read-SecretPlainConfirm {
  param(
    [string]$Prompt1 = "Passwort",
    [string]$Prompt2 = "Passwort erneut eingeben",

    [string]$ContextTitle = "",
    [string]$ContextHint = "",
    $ContextCurrent = $null,
    [string[]]$MaskKeys = @()
  )

  while ($true) {
    Write-Context -Title $ContextTitle -Hint $ContextHint -Current $ContextCurrent -MaskKeys $MaskKeys

    $p1 = Read-Secret $Prompt1
    if ([string]::IsNullOrWhiteSpace($p1)) {
      Write-Host "  Passwort darf nicht leer sein. Bitte erneut eingeben (ESC/Ctrl-C zum Abbrechen)." -ForegroundColor Yellow
      Start-Sleep -Milliseconds 700
      continue
    }

    $p2 = Read-Secret $Prompt2
    if ($p1 -ne $p2) {
      Write-Host "  Passwörter stimmen nicht überein. Bitte erneut." -ForegroundColor Yellow
      Start-Sleep -Milliseconds 700
      continue
    }
    return $p1
  }
}

# -------------------------
# Run an external process with a spinner, capturing output off the main thread
# -------------------------
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
  try {
    while ($job.State -eq 'Running') {
      [Console]::Write("`r  $($frames[$i % 4]) $Message")
      $i++
      Start-Sleep -Milliseconds 150
    }
  } finally {
    if ($job.State -eq 'Running') { Stop-Job -Job $job }
    [Console]::Write("`r" + (" " * ($Message.Length + 6)) + "`r")
  }

  $result = Receive-Job -Job $job -Wait
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
)
