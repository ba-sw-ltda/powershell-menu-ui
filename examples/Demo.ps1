<#
.SYNOPSIS
    Interactive walkthrough of every PowerShellMenuUI function.
.DESCRIPTION
    Runs through each exported function in turn: a short explanation screen,
    then the live prompt itself. Answers are accumulated into one running
    context so you can see how a real multi-step wizard would chain these
    calls together (each call's -ContextCurrent shows everything answered
    so far). Meant to be run interactively and screenshotted step by step —
    it is not a test runner.
#>
[CmdletBinding()]
param()

$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot "PowerShellMenuUI.psd1") -Force

$TotalSteps = 12

function Show-Explainer {
    param([int]$Step, [string]$Function, [string]$Text)
    Clear-Host
    Write-Host ""
    Write-Host "  Demo $Step/$TotalSteps — $Function" -ForegroundColor Cyan
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Press any key to try it..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

# Read-ComponentSelectionScreen's return value is a FLAT @{ value = bool } map —
# it doesn't carry group/child relationships (and can't start to: Install-Base.ps1
# depends on that exact flat shape, e.g. $compSel["nginx"]). To show the tree
# relationship in the context panel anyway, rebuild it here from the same
# $Sections the demo already has, as "group/selected-child" tokens.
function Format-ComponentTree {
    param([object[]]$Sections, [hashtable]$Result)
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($sec in $Sections) {
        foreach ($item in @($sec.Items)) {
            if ($item.Type -eq "group") {
                if (-not $Result[$item.Value]) { continue }
                $child = @($item.Children) | Where-Object { $Result[$_.Value] } | Select-Object -First 1
                $tokens.Add($(if ($child) { "$($item.Value)/$($child.Value)" } else { $item.Value }))
            } elseif ($Result[$item.Value]) {
                $tokens.Add($item.Value)
            }
        }
    }
    if ($tokens.Count -eq 0) { return "(none)" }
    return ($tokens -join ", ")
}

function Show-Result {
    param([string]$Label, $Value)
    Write-Host ""
    # Hashtables render as a Name/Value table with its own header row — keep that
    # header on its own line instead of running it into the label text.
    if ($Value -is [System.Collections.IDictionary]) {
        Write-Host "  -> $Label`:" -ForegroundColor Green
        Write-Host ($Value | Out-String).Trim() -ForegroundColor White
    } else {
        Write-Host "  -> $Label`: " -ForegroundColor Green -NoNewline
        Write-Host ($Value | Out-String).Trim() -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

# Accumulates across the whole demo — passed as -ContextCurrent so every
# screen after the first shows everything answered up to that point.
$answers = [ordered]@{}

Clear-Host
Write-Host ""
Write-Host "  PowerShellMenuUI — Function Demo" -ForegroundColor Cyan
Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
Write-Host "  This walks through all $TotalSteps exported functions, one screen at a" -ForegroundColor Gray
Write-Host "  time. Most steps ask you to make a choice, then show you what was" -ForegroundColor Gray
Write-Host "  returned. Most prompts also display a context panel above them with" -ForegroundColor Gray
Write-Host "  everything answered so far — it starts out empty and fills in as you" -ForegroundColor Gray
Write-Host "  go, so don't expect to see much there on the first couple of screens." -ForegroundColor Gray
Write-Host ""
Write-Host "  Press any key to start..." -ForegroundColor DarkGray
[Console]::ReadKey($true) | Out-Null

# ── 1. Read-SelectValue ───────────────────────────────────────────
Show-Explainer -Step 1 -Function "Read-SelectValue" -Text `
    "Arrow-key single-choice menu. Up/Down moves the highlight, Enter confirms, Escape cancels. Returns the VALUE of the chosen option."
$platform = Read-SelectValue -Title "Target platform" -Message "Pick where this would be deployed" `
    -Options @(
        @{ Label = "Azure AKS"; Value = "Azure AKS" }
        @{ Label = "AWS EKS"; Value = "AWS EKS" }
        @{ Label = "RKE2 (On-Premise)"; Value = "RKE2 (On-Premise)" }
    ) -Default 2 -ContextTitle "Demo Wizard" -ContextHint "Step 1 of $TotalSteps — picking a target" -ContextCurrent $answers
# $null means Escape was pressed — every step below guards the same way, so
# cancelling one screen just skips it and moves on to the next.
$answers["Platform"] = if ($null -ne $platform) { $platform } else { "(skipped)" }
Show-Result -Label "Returned value" -Value $answers["Platform"]

# ── 2. Read-SelectIndex ───────────────────────────────────────────
Show-Explainer -Step 2 -Function "Read-SelectIndex" -Text `
    "The low-level building block behind Read-SelectValue — identical menu, but returns the chosen INDEX instead of the option's Value."
$idx = Read-SelectIndex -Title "Same menu, different return type" -Message "Pick any item" `
    -Options @("First", "Second", "Third") -Default 0 `
    -ContextTitle "Demo Wizard" -ContextHint "Step 2 of $TotalSteps — index instead of value" -ContextCurrent $answers
# Read-SelectIndex signals Escape with -1, not $null.
$answers["SampleIndex"] = if ($idx -ge 0) { $idx } else { "(skipped)" }
Show-Result -Label "Returned index" -Value $answers["SampleIndex"]

# ── 3. Read-MultiSelectValues ─────────────────────────────────────
Show-Explainer -Step 3 -Function "Read-MultiSelectValues" -Text `
    "Checkbox menu. Space toggles the highlighted item, Enter confirms the whole set. Returns the Values of every checked item."
$components = Read-MultiSelectValues -Title "Select components" `
    -Options @("Ingress", "Security", "Storage", "Observability", "GitOps") `
    -DefaultValues @("Ingress", "Security") `
    -ContextTitle "Demo Wizard" -ContextHint "Step 3 of $TotalSteps — picking components" -ContextCurrent $answers
$answers["Components"] = if ($null -ne $components) { $components } else { @() }
Show-Result -Label "Returned values" -Value $(if ($components) { $components -join ", " } else { "(skipped)" })

# ── 4. Read-ComponentSelectionScreen ──────────────────────────────
Show-Explainer -Step 4 -Function "Read-ComponentSelectionScreen" -Text `
    "Two-level picker: a toggleable group (here: 'Ingress') reveals radio sub-choices underneath it once checked, alongside plain standalone checkboxes."
$ingressSections = @(
    @{ Label = "Ingress & LB"; Items = @(
        @{ Label = "Ingress"; Value = "ingress"; Type = "group"; Default = $true; Children = @(
            @{ Label = "NGINX"; Value = "nginx"; Type = "radio"; RadioGroup = "ingress"; Default = $true }
            @{ Label = "Traefik"; Value = "traefik"; Type = "radio"; RadioGroup = "ingress"; Default = $false }
        )}
        @{ Label = "MetalLB"; Value = "metallb"; Type = "check"; Default = $true }
    )}
)
$ingressChoice = Read-ComponentSelectionScreen -Title "Ingress & Load Balancing" -Sections $ingressSections `
    -ContextTitle "Demo Wizard" -ContextHint "Step 4 of $TotalSteps — two-level picker" -ContextCurrent $answers
if ($null -ne $ingressChoice) {
    $answers["IngressChoice"] = Format-ComponentTree -Sections $ingressSections -Result $ingressChoice
    Show-Result -Label "Returned hashtable" -Value $ingressChoice
} else {
    $answers["IngressChoice"] = "(skipped)"
    Show-Result -Label "Returned hashtable" -Value "(skipped)"
}

# ── 5. Read-YesNo ──────────────────────────────────────────────────
Show-Explainer -Step 5 -Function "Read-YesNo" -Text `
    "Two-choice Yes/No menu — same navigation as Read-SelectValue, returns a plain boolean."
$answers["ReplaceExisting"] = Read-YesNo -Title "Replace the existing cluster?" -DefaultYes $false `
    -ContextTitle "Demo Wizard" -ContextHint "Step 5 of $TotalSteps — a yes/no decision" -ContextCurrent $answers
Show-Result -Label "Returned value" -Value $answers["ReplaceExisting"]

# ── 6. Read-Plain ──────────────────────────────────────────────────
Show-Explainer -Step 6 -Function "Read-Plain" -Text `
    "Free-text prompt. Press Enter on an empty line to accept the shown default."
$answers["ClusterName"] = Read-Plain -Prompt "Cluster name" -Default "my-cluster" `
    -ContextTitle "Demo Wizard" -ContextHint "Step 6 of $TotalSteps — free text with a default" -ContextCurrent $answers
Show-Result -Label "Returned value" -Value $answers["ClusterName"]

# ── 7. Read-SecretPlain ───────────────────────────────────────────
Show-Explainer -Step 7 -Function "Read-SecretPlain" -Text `
    "Masked single-entry prompt — for re-entering an already-known secret. Input is hidden as you type."
$token = Read-SecretPlain -Prompt "API token (try typing anything)" `
    -ContextTitle "Demo Wizard" -ContextHint "Step 7 of $TotalSteps — masked input" -ContextCurrent $answers
# Never store the real secret in $answers — it's reused as -ContextCurrent by every
# later step and would otherwise be echoed in plain text on every following screen.
$answers["ApiToken"] = "*" * $token.Length
Show-Result -Label "Captured length" -Value "$($token.Length) characters (value itself is never shown back)"

# ── 8. Read-SecretPlainConfirm ────────────────────────────────────
Show-Explainer -Step 8 -Function "Read-SecretPlainConfirm" -Text `
    "Masked prompt with retype-to-confirm — for SETTING a new secret. Loops with a warning until both entries match."
$pw = Read-SecretPlainConfirm -Prompt1 "New admin password" -Prompt2 "Confirm password" `
    -ContextTitle "Demo Wizard" -ContextHint "Step 8 of $TotalSteps — confirm-to-set" -ContextCurrent $answers
$answers["AdminPassword"] = "*" * $pw.Length
Show-Result -Label "Captured length" -Value "$($pw.Length) characters (value itself is never shown back)"

# ── 9. Invoke-WithSpinner ──────────────────────────────────────────
Show-Explainer -Step 9 -Function "Invoke-WithSpinner" -Text `
    "Runs an external process in the background while animating a spinner on the main thread, then returns its exit code. Here: 'ping' for a few seconds."
$pingArgs = if ($IsWindows -or -not (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { @("-n", "3", "127.0.0.1") } else { @("-c", "3", "127.0.0.1") }
$exitCode = Invoke-WithSpinner -Message "Pinging localhost..." -Executable "ping" -Arguments $pingArgs -ShowOutput
Show-Result -Label "Exit code" -Value $exitCode

# ── 10. Write-Context / Write-Section ─────────────────────────────
Show-Explainer -Step 10 -Function "Write-Context / Write-Section" -Text `
    "The screen header every prompt above draws automatically. Exported separately for drawing an info screen with no input on it."
Write-Section -Title "All answers collected so far" -Hint "This is exactly what Write-Context/-Section renders — title, hint, and the context panel." `
    -Current $answers -MaskKeys @("AdminPassword")
Write-Host ""
Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
[Console]::ReadKey($true) | Out-Null

# ── 11. ConvertTo-UiOptions ────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  Demo 11/$TotalSteps — ConvertTo-UiOptions" -ForegroundColor Cyan
Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
Write-Host "  Non-interactive: normalizes mixed input into a uniform Label/Value list." -ForegroundColor Gray
Write-Host ""
$normalized = ConvertTo-UiOptions -Options @("plain-string", @{ Label = "Custom Label"; Value = 42 })
$normalized | Format-Table -AutoSize
Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
[Console]::ReadKey($true) | Out-Null

# ── 12. ToSafeName ─────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  Demo 12/$TotalSteps — ToSafeName" -ForegroundColor Cyan
Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
Write-Host "  Non-interactive: lowercases and strips a string down to [a-z0-9-]." -ForegroundColor Gray
Write-Host ""
$raw  = "$($answers['ClusterName']) (Demo!)"
$safe = ToSafeName $raw
Write-Host "  ToSafeName('$raw') -> '$safe'" -ForegroundColor White
Write-Host ""

Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Demo complete." -ForegroundColor Cyan
Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
