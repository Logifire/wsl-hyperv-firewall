# powershell -ExecutionPolicy Bypass -File .\wsl-hyperv-firewall.ps1 add 5173 [TCP|UDP]
# Manual argument parsing is used to avoid PowerShell binder errors
# for help flags (-h, --help, /?) and unknown switches (-xyz) – all show help gracefully.

Set-StrictMode -Version Latest

$RulePrefix = "WSL-HYPERV-"
$DisplayPrefix = "WSL Hyper-V - Port "
$WslFallbackGuid = "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}"
$HelpFlags = @("-h", "--help", "-help", "/?", "/help", "-?", "?", "--h", "help")

function Get-WslCreatorId {
    $settings = Get-NetFirewallHyperVVMSetting -ErrorAction Stop

    $wsl = $settings | Where-Object {
        $_.Name -match "WSL|Linux"
    } | Select-Object -First 1

    if (-not $wsl) {
        return $WslFallbackGuid
    }

    return $wsl.VMCreatorId
}

function Get-WslRuleName {
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Protocol
    )
    return "$RulePrefix$Port-$Protocol"
}

function Get-WslRules {
    $allRules = Get-NetFirewallHyperVRule -ErrorAction SilentlyContinue
    if (-not $allRules) { return $null }
    return $allRules | Where-Object { $_.Name -like "$RulePrefix*" }
}

function Show-Rules {
    $rules = Get-WslRules

    if (-not $rules) {
        Write-Host "No WSL Hyper-V firewall rules are configured."
        return
    }

    $rules |
        Select-Object Name, DisplayName, Direction, Protocol, LocalPorts, Enabled |
        Format-Table -AutoSize
}

function Show-Help {
    $text = @"

WSL Hyper-V Firewall

  add <port> [TCP|UDP]     Add port (default TCP)
  list                     Show configuration
  remove <port> [TCP|UDP]  Remove port (default TCP)

"@
    Write-Host $text
}

function Add-WslPort {
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Protocol
    )
    $ruleName = Get-WslRuleName -Port $Port -Protocol $Protocol

    $existing = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Port $Port/$Protocol is already configured."
        return
    }

    $creatorId = Get-WslCreatorId

    New-NetFirewallHyperVRule `
        -Name $ruleName `
        -DisplayName "$DisplayPrefix$Port ($Protocol)" `
        -Direction Inbound `
        -VMCreatorId $creatorId `
        -Protocol $Protocol `
        -LocalPorts $Port `
        -ErrorAction Stop | Out-Null

    Write-Host "Port $Port/$Protocol is open for WSL."
}

function Remove-WslPort {
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Protocol
    )
    $ruleName = Get-WslRuleName -Port $Port -Protocol $Protocol

    $existing = Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Port $Port/$Protocol is not configured."
        return
    }

    Remove-NetFirewallHyperVRule -Name $ruleName -ErrorAction Stop

    Write-Host "Port $Port/$Protocol is closed."
}

# --- Manual argument parsing ---

foreach ($arg in $args) {
    if ($arg -in $HelpFlags) {
        Show-Help
        exit
    }
}

$Action = if ($args.Count -ge 1) { $args[0] } else { $null }
$PortRaw = if ($args.Count -ge 2) { $args[1] } else { $null }
$ProtocolRaw = if ($args.Count -ge 3) { $args[2] } else { $null }

if ($args.Count -gt 3) {
    Write-Host "Unknown argument '$($args[3])'."
    Show-Help
    exit 1
}

# Unknown dash-prefixed action (e.g. -xyz) should show help, not binder error
if ($Action -and ($Action.StartsWith("-") -or $Action.StartsWith("/"))) {
    Write-Host "Unknown command '$Action'."
    Show-Help
    exit 1
}

if (-not $Action) {
    Show-Help
    exit
}

# Validate and normalize Port
[int]$Port = 0
$hasPort = $false
if ($PortRaw) {
    if ($PortRaw -notmatch '^\d+$' -or [int]$PortRaw -lt 1 -or [int]$PortRaw -gt 65535) {
        Write-Host "Invalid port '$PortRaw'. Port must be 1-65535."
        Show-Help
        exit 1
    }
    $Port = [int]$PortRaw
    $hasPort = $true
}

# Validate and normalize Protocol
[string]$Protocol = "TCP"
if ($ProtocolRaw) {
    $normalizedProtocol = $ProtocolRaw.ToUpper()
    if ($normalizedProtocol -notin @("TCP", "UDP")) {
        Write-Host "Invalid protocol '$ProtocolRaw'. Use TCP or UDP."
        Show-Help
        exit 1
    }
    $Protocol = $normalizedProtocol
}

switch ($Action.ToLower()) {

    "list" {
        if ($PortRaw -or $ProtocolRaw) {
            $extra = @($PortRaw, $ProtocolRaw) | Where-Object { $_ } | Join-String -Separator " "
            Write-Host "Unknown argument '$extra' for 'list'."
            Show-Help
            exit 1
        }
        Show-Rules
    }

    "add" {
        if (-not $hasPort) {
            Write-Error "Specify a port, for example 'add 5173'."
            exit 1
        }
        Add-WslPort -Port $Port -Protocol $Protocol
    }

    "remove" {
        if (-not $hasPort) {
            Write-Error "Specify a port, for example 'remove 5173'."
            exit 1
        }
        Remove-WslPort -Port $Port -Protocol $Protocol
    }

    default {
        Write-Host "Unknown command '$Action'."
        Show-Help
        exit 1
    }
}
