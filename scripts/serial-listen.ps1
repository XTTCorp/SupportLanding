# 1. Prompt user for connection inputs (with defaults)
$ComInput = Read-Host "Enter COM Port number [Default: 3]"
if ([string]::IsNullOrWhitespace($ComInput)) { $ComInput = "3" }
$PortName = "COM$ComInput"

$BaudInput = Read-Host "Enter Baud Rate [Default: 9600]"
if ([string]::IsNullOrWhitespace($BaudInput)) { $BaudInput = "9600" }
$BaudRate = [int]$BaudInput

# Standard serial parameters
$Parity   = "None"
$DataBits = 8
$StopBits = "One"

# 2. Create and configure the SerialPort object
$port = New-Object System.IO.Ports.SerialPort($PortName, $BaudRate, $Parity, $DataBits, $StopBits)

# 3. Open the connection
try {
    $port.Open()
    Write-Host "`nSuccessfully connected to $PortName at $BaudRate baud. Listening..." -ForegroundColor Green
    Write-Host "Press CTRL+C to stop listening.`n" -ForegroundColor Yellow

    # 4. Continuous listening loop
    while ($port.IsOpen) {
        if ($port.BytesToRead -gt 0) {
            # Uses ReadExisting to safely grab any incoming text stream without waiting for a newline
            $data = $port.ReadExisting()
            Write-Host $data -NoNewline
        }
        Start-Sleep -Milliseconds 50
    }
}
catch {
    Write-Error "Failed to open $PortName. Ensure the port exists and isn't locked by another app."
}
finally {
    # 5. Clean up and close connection
    if ($port -and $port.IsOpen) {
        $port.Close()
        Write-Host "`nConnection closed." -ForegroundColor Red
    }
}
