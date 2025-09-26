$ComputerName = 1..255 | ForEach-Object { "10.10.0.$_" }
$Addresses = $ComputerName -join "' or Address='"
$Filter = "(Address='$Addresses') and ResolveAddressNames='True' and timeout=1000 and ResolveAddressNames=True and StatusCode=0"
Get-WmiObject -Class Win32_PingStatus -Filter $Filter | Sort-Object ProtocolAddressResolved | Select-Object -Property Address,ProtocolAddressResolved
