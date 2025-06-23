# netaudit.ps1 - Network Testing Tool
# (c) 2025 Invision Technologies, LLC
# -
# Features:
# - Implemented Ping100.ps1 by AS199035
# - Implemented xttspeed by XTT
# - Implemented ipconfig details
# - 
# Changelog:
# - 2025/06/23 //JMaanao// Script Created
# - 
# - 

# ===SETUP===
$currentDate = (Get-Date).ToUniversalTime().ToString("dddd, MMMM dd, yyyy, h:mm:ss tt 'UTC'")
# Get the PC name (hostname)
$pcName = $env:COMPUTERNAME
# Get the domain the computer is joined to (if any)
try {
    $domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
} catch {
    $domain = "N/A"
}
# Get private IP addresses (IPv4) from network adapters that are up and not loopback
$privateIPs = Get-NetIPAddress -AddressFamily IPv4 `
    | Where-Object { $_.InterfaceOperationalStatus -eq 'Up' -and $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } `
    | Select-Object -ExpandProperty IPAddress
# Get public IP address by querying an external web service
try {
    $publicIP = (Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -ErrorAction Stop)
} catch {
    $publicIP = "Unavailable"
}
$ipconfigOutput = ipconfig /all
$runid = Get-Random -Minimum 10000 -Maximum 100000
$basepath = "C:\temp\netaudit\netaudit_report"
$reportLoc = "$basepath`_$runid.txt"


# ===DISPLAY WELCOME===
Write-Output "netaudit.ps1 - Invision Technologies"
Write-Output "Current date: $currentDate"
Write-Output "Hostname: $pcName"
Write-Output "Domain: $domain"
Write-Output "Private IP(s): $($privateIPs -join ', ')"
Write-Output "Public IP: $publicIP"
Write-Output "RunID: $runid"
Write-Output ""
Write-Output $ipconfigOutput


# ===BEGIN Ping100===
# Define the target and the number of pings
$target = "8.8.8.8"
$count = 100

Write-Output "Running Ping$count ..."

# Run Test-Connection and collect the ping results silently
# Test-Connection returns objects with ResponseTime property for each reply
$pings = Test-Connection -ComputerName $target -Count $count -ErrorAction SilentlyContinue

# Calculate statistics
if ($pings) {
    $avg = "{0:00.000}" -f ($pings | Measure-Object -Property ResponseTime -Average).Average
    $max = "{0:00.000}" -f ($pings | Measure-Object -Property ResponseTime -Maximum).Maximum
    $min = "{0:00.000}" -f ($pings | Measure-Object -Property ResponseTime -Minimum).Minimum
    $received = $pings.Count
} else {
    # If no ping replies, set all times to 0 and received to 0
    $avg = "00.000"
    $max = "00.000"
    $min = "00.000"
    $received = 0
}

# Calculate packet loss percentage
$loss = ((($count - $received) / $count) * 100)

# Format output line
$output = "Ping$count - Avg: ${avg}ms, Max: ${max}ms, Min: ${min}ms, ${loss}% Packet Loss"

# Display Results
Write-Output $output

# ===BEGIN xttspeed===
# Fetch the test from xtt.cx shortlink
$xttspeed = Invoke-RestMethod -Uri "https://xtt.cx/speed"

# Run the test
$speedoutput = Invoke-Expression -Command $xttspeed

# Log Data
$speedrpt = $speedoutput | Select-Object -Last 11

# Finalize Report
$header = "=== netaudit.ps1 Report - Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
$header | Out-File -FilePath $reportLoc -Encoding utf8 -Force
Add-Content -Path $reportLoc -Value "`nHostname: $pcName"
Add-Content -Path $reportLoc -Value "`nDomain: $domain"
Add-Content -Path $reportLoc -Value "`nPrivate IP(s): $($privateIPs -join ', ')"
Add-Content -Path $reportLoc -Value "`nPublic IP: $publicIP"
Add-Content -Path $reportLoc -Value "`n"
Add-Content -Path $reportLoc -Value "`n$ipconfigOutput"
$speedrpt | Add-Content -Path $reportLoc -Encoding utf8
$output | Add-Content -Path $reportLoc -Encoding utf8
$speedrpt | Out-File -FilePath $reportLoc -Encoding utf8 -Force
Add-Content -Path $reportLoc $output -Encoding utf8

# Notify
Write-output "Report exported to: $reportLoc"
