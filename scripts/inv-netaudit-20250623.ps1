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

# ===DISPLAY WELCOME===
Write-Output "netaudit.ps1 - Invision Technologies"
Write-Output "Current date: $currentDate"
Write-Output "Hostname: $pcName"
Write-Output "Domain: $domain"
Write-Output "Private IP(s): $($privateIPs -join ', ')"
Write-Output "Public IP: $publicIP"
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
Invoke-Expression -Command $xttspeed
