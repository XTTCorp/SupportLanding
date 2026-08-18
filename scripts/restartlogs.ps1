# Specify your lookback window (e.g., last 24 hours)
$StartTime = (Get-Date).AddDays(-1)

# 1. System Log: Reboots, Crashes, SCM Services, TCP Issues, and Physical Intel/Broadcom/Mellanox Link Drops
$SystemFilter = @{
    LogName   = 'System'
    Id        = @(
        41, 1001, 1074, 6008,          # Reboots / Crashes / Dirty shutdowns
        7031, 7034,                    # Service Control Manager crashes
        4227, 4231,                    # TCPIP Port exhaustion
        27, 32, 33                     # Common physical NIC link disconnect / establish IDs (Intel/Broadcom/Mellanox/Realtek)
    )
    StartTime = $StartTime
}

# 2. Hyper-V Virtual Switch & Team Logs (VMSwitch port disconnects, SET degradation, teaming member link changes)
$HyperVLogs = @(
    'Microsoft-Windows-Hyper-V-VmSwitch-Operational',
    'Microsoft-Windows-NIC-Teaming/Operational'
)

$AllEvents = [System.Collections.Generic.List[PSObject]]::new()

# Collect System events
try {
    $systemEvents = Get-WinEvent -FilterHashtable $SystemFilter -ErrorAction SilentlyContinue
    if ($systemEvents) { $AllEvents.AddRange($systemEvents) }
} catch {}

# Collect Hyper-V & NIC Team events
foreach ($log in $HyperVLogs) {
    try {
        $logEvents = Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $StartTime } -ErrorAction SilentlyContinue |
            Where-Object { 
                # ID 22, 23 = VmSwitch port down / link state changed
                # ID 16, 17, 18, 169 = NIC Teaming member failure / disconnected / SET status
                $_.Id -in @(16, 17, 18, 22, 23, 169) -or $_.LevelDisplayName -in @('Error', 'Warning')
            }
        if ($logEvents) { $AllEvents.AddRange($logEvents) }
    } catch {}
}

# Display results sorted chronologically
$AllEvents | 
    Sort-Object TimeCreated -Descending | 
    Select-Object TimeCreated, 
                  Id, 
                  LevelDisplayName, 
                  @{Name='Log'; Expression={$_.LogName}}, 
                  ProviderName, 
                  @{Name='Summary'; Expression={$_.Message.Split("`n")[0].Trim()}} | 
    Format-Table -Wrap -AutoSize
