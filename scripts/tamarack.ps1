#Define the name of the company so in Connectwise Control, the device shows under the company name - The below picks up the company name from Ninja under which the device is located in
$CompanyName = "Tamarack Foods, Inc."
$LocationName = "Americus""

#Convert Ninja Variables to URL friendly
$CompanyNameUri = [uri]::EscapeDataString($CompanyName)
$LocationNameUri = [uri]::EscapeDataString($LocationName)

#Define the name of the software we are searching for and look for it in both the 64 bit and 32 bit registry nodes
###Old software name before move to cloud: ScreenConnect Client (b0f26531eff63c1e)
$SoftwareName = "ScreenConnect Client (efb578c958d4b40e)"
$IsInstalled =  (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -eq $SoftwareName }) + (Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -eq $SoftwareName })

# Save the current SecurityProtocol setting
$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
 
#Begin installation process
if (-Not $IsInstalled)  
    {
    #If software is not installed, set the installer file name, download URL, and temporary directory for storing the installer
    Write-Host $SoftwareName "is not installed and will be installed."
        $DestFolder = "C:\ProgramData\NinjaRMMAgent\CustomApps"
        $InstallerFile = "$DestFolder\ScreenConnect.ClientSetup.msi"
        $InstallerLogFile = "$DestFolder\ScreenConnect.Install.log"
        $URL = "https://invtech.screenconnect.com/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest&c=$CompanyNameUri&c=$LocationNameUri&c=&c=&c=&c=&c=&c="
        
    if (Test-Path $DestFolder)
        {
        Write-Host "Folder Exists"
        }
    else
        {
        New-Item $DestFolder -ItemType Directory
        Write-Host "Folder Created Successfully"
        }
    # Set the SecurityProtocol to use only supported versions of TLS
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls13 -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    Invoke-WebRequest -Uri $URL -OutFile $InstallerFile -UseBasicParsing
    $Arguments = @"
    /c msiexec /i "$InstallerFile" /qn /norestart REBOOT=REALLYSUPPRESS /l*v "$InstallerLogFile"
"@
    Write-Host "InstallerLogFile: $InstallerLogFile"
    $Process = Start-Process -Wait cmd -ArgumentList $Arguments -Passthru
    Write-Host "Exit Code: $($Process.ExitCode)";
    Remove-Item $InstallerFile
    switch ($Process.ExitCode)
        {
        0 { Write-Host "Success" }
        3010 { Write-Host "Success. Reboot required to complete installation" }
        1641 { Write-Host "Success. Installer has initiated a reboot" }
        default {
            Write-Host "Exit code does not indicate success"
            Get-Content $InstallerLogFile -ErrorAction SilentlyContinue | select -Last 50
            }
        }
    # Restore the original SecurityProtocol setting
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    }
#If software is installed, exit
else
    {
    Write-Host $SoftwareName "is already installed and script is exiting"
    }
