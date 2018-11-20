<#
.SYNOPSIS
    Invoke BIOS Update process.

.DESCRIPTION
    This script will invoke a BIOS update process for a viarity of manufactures. This process should be ran in WINPE.

.PARAMETER LogFileName
    Set the name of the log file produced by the flash utility.

.EXAMPLE
    

.NOTES
    FileName:    Update-BIOS.ps1
    Author:      Richard tracy
    Contact:     richard.j.tracy@gmail.com
    Created:     2018-08-24
    Inspired:    Anton Romanyuk,Nickolaj Andersen
    
    Version history:
    1.1.0 - (2018-11-07) Script created
#>

##*===========================================================================
##* FUNCTIONS
##*===========================================================================
function Write-LogEntry {
    param(
        [parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
        [ValidateNotNullOrEmpty()]
        [string]$fileArgName = $LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost
    )
    
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
	[int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
	[string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
    #  Get the file name of the source script

    Try {
	    If ($script:MyInvocation.Value.ScriptName) {
		    [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
	    }
	    Else {
		    [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
	    }
    }
    Catch {
	    $ScriptSource = ''
    }
    
    
    If(!$Severity){$Severity = 1}
    $LogFormat = "<![LOG[$Value]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
    
    # Add value to log file
    try {
        Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-LogEntry -Message "Unable to append log entry to $LogFilePath file"
    }
    If($Outhost){
        Switch($Severity){
            0       {Write-Host $Value -ForegroundColor Gray}
            1       {Write-Host $Value}
            2       {Write-Warning $Value}
            3       {Write-Host $Value -ForegroundColor Red}
            default {Write-Host $Value}
        }
    }
}


##*===========================================================================
##* VARIABLES
##*===========================================================================
## Instead fo using $PSScriptRoot variable, use the custom InvocationInfo for ISE runs
If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent
[string]$scriptPath = $InvocationInfo.MyCommand.Definition
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)

#Create Paths
$BIOSPath = Join-Path $scriptDirectory -ChildPath BIOS
$TempPath = Join-Path $scriptDirectory -ChildPath Temp
$ToolsPath = Join-Path $scriptDirectory -ChildPath Tools

Try
{
	$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
	#$logPath = $tsenv.Value("LogPath")
    $LogPath = $tsenv.Value("_SMSTSLogPath")
    $tsenv.Value("SMSTS_BiosUpdate") = "True"
    $inPE = $tsenv.Value("_SMSTSInWinPE")
}
Catch
{
	Write-Warning "TS environment not detected. Assuming stand-alone mode."
	$LogPath = $env:TEMP
}
[string]$FileName = $scriptName +'.log'
$LogFilePath = Join-Path -Path $LogPath -ChildPath $FileName

##*===========================================================================
##* MAIN
##*===========================================================================
Write-Host "Beginning BIOS update script..."
#Create Make Variable
$BIOSManufacturer = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty Manufacturer

Switch($BIOSManufacturer){
    "Dell Inc."                             {$FlashUtility = "Flash64W.exe"}
    "Award Software International, Inc."    {$FlashUtility = "awdflash899.exe"}
    "Lenovo"                                {$FlashUtility = "WinUPTP64.exe"}
    "Intel Corp."                           {$FlashUtility = "iflash.exe"}
    "Hewlett-Packard"                       {$FlashUtility = "AFUDOS.exe"}
    "American Megatrends Inc."              {$FlashUtility = "AFUDOS.exe"}
    "Phoenix Technologies LTD"              {$FlashUtility = "PHLASH16.EXE"}
    default                                 {$FlashUtility = "Flash64W.exe"}
}

#Remove any special characters from Manufacturer to support folders name
$Regex = "[^{\p{L}\p{Nd}}]+"
$ComputerMake = ($BIOSManufacturer -replace $Regex, " ").Trim()


#Get Model
$ComputerModel = Get-WmiObject -Class Win32_computersystem | Select-Object -ExpandProperty Model

#build path just in case. Path will be empty 
New-Item -ItemType Directory "$BIOSPath\$ComputerMake\$ComputerModel" -ErrorAction SilentlyContinue 

$BiosSearchPath = Join-Path $BIOSPath -ChildPath "$ComputerMake\$ComputerModel"
#Get Bios File Name (Uses the Bios EXE file in the same folder)
$BiosFileNames = Get-ChildItem $BiosSearchPath -ErrorAction SilentlyContinue | sort -Descending

#Get BIOS version
[string]$BIOSVersion = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion
Write-LogEntry ("Current BIOS version is: {0}" -f $BIOSVersion)

If($BiosFileNames){
   
    if ($tsenv) {
        If($BiosFileNames.count -gt 1){
            #FUTURE: configure MDT/SCCM property to boot back into pe for incremental bios upgrade
            $tsenv.Value("SMSTS_MutipleBIOSUpdatesNeeded") = "True"
        }Else{
            $tsenv.Value("SMSTS_MutipleBIOSUpdatesNeeded") = "False"
        }
    }

    Foreach ($BiosFileName in $BiosFileNames){
        If($BiosFileName -match $BIOSVersion){
            Write-LogEntry ("BIOS verison [{0}] matches file version [{1}], no update needed" -f $BIOSVersion,$BiosFileName.Name) -Outhost
            Break
        }
        Else{
            Write-LogEntry ("Found BIOS File: {0}" -f $BiosFileName.Name) -Outhost
            #Copy Bios Installer to the root of the package - the Flash64W didn't like when I left it in the Computer Model folder, because it has spaces. (Yes, I tried qoutes and stuff)
            Copy-Item $BiosFileName.FullName -Destination $TempPath -ErrorAction SilentlyContinue
        
            #build temp path
            $BIOSFilePath = Join-Path -Path $TempPath -ChildPath $BiosFileName.Name

            #Get Bios File Name (No Extension, used to create Log File)
            $BiosLogFileName = Get-ChildItem $BIOSFilePath | Select -ExpandProperty BaseName
            $BiosLogFileName = $BiosLogFileName + ".log"

            #Get Bios Password from File
            $BiosPassword = Get-Content "$scriptDirectory\BIOSPassword.txt" -ErrorAction SilentlyContinue

            #Update Bios
            Write-LogEntry ("Applying BIOS File from temp path: {0}" -f $BIOSFilePath)
            
            #Build command based on flash utility
            Switch($FlashUtility){
                "Flash64W.exe"    {
                                    $fileArg = "/b=$($BIOSFilePath)";
                                    $AddArgs = " /s /l=$LogPath\$BiosLogFileName";
                                    If($BiosPassword){$AddArgs += " /p=$BiosPassword"}
                                  }

                "awdflash899.exe" {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = " /cc/cd/cp/py/sn/cks/r";
                                  }

                "AFUDOS.exe"      {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = " /P";
                                  }

                "PHLASH16.EXE"    {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = " /P /B /N /C /E /K /Q /REBOOT";
                                    
                                  }

                "WinUPTP64.exe"   {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = " /S";
                                    If($BiosPassword){$AddArgs += " /pass=$BiosPassword"}
                                  }         

                "WinFlash64.exe"  {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = " /S";
                                    If($BiosPassword){$AddArgs += " /pass=$BiosPassword"}
                                  }

            }

            #make sure the path exists,build utility path
            $FlashUtilityPath = Join-Path -Path $ToolsPath -ChildPath $FlashUtility
            If( !(Test-Path $FlashUtilityPath) ){Exit}

            
            if ($tsenv -and $inPE) {
                Write-LogEntry "Script is running in Windows Preinstallation Environment (PE)" -Outhost
            }
            Else{
                Write-LogEntry "Script is running in Windows Environment" -Outhost

                # Detect Bitlocker Status
		        $OSVolumeEncypted = if ((Manage-Bde -Status C:) -match "Protection On") { Write-Output $true } else { Write-Output $false }
		
		        # Supend Bitlocker if $OSVolumeEncypted is $true
		        if ($OSVolumeEncypted -eq $true) {
			        Write-LogEntry "Suspending BitLocker protected volume: C:"
			        Manage-Bde -Protectors -Disable C:
		        }
                
            }

            #execute flashing
            If($BiosPassword){$protectedArgs = $fileArg + $($AddArgs -replace $BiosPassword, "<Password Removed>")}Else{$protectedArgs = $fileArg + $AddArgs}
            Write-LogEntry "RUNNING COMMAND : $FlashUtilityPath $protectedArgs" -Outhost
            $Process = Start-Process $FlashUtilityPath -ArgumentList $protectedArgs -PassThru -Wait

            #Creates and Set TS Variable to be used to run additional steps if reboot required.
            switch($process.ExitCode){
                0   {
                        Write-LogEntry ("BIOS installed succesfully") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosRebootRequired") = "False"}
                        If($tsenv){$tsenv.Value("SMSTS_BiosBatteryCharge") = "False"}
                    }

                2   {
                        Write-LogEntry ("BIOS installed succesfully. A reboot is required") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosRebootRequired") = "True"}
                    }

                10  {
                        Write-LogEntry ("BIOS cannot install because it requires an earlier release first") -Outhost
                        Write-LogEntry ("OR BIOS cannot install because the battery is missing or not charged") -Outhost
                        Write-LogEntry ("OR BIOS installation was cancelled") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosBatteryCharge") = "True"}
                    }
            }
        
            Start-Sleep 10
            #remove exe after completed
            Remove-Item $BIOSFilePath -Force -ErrorAction SilentlyContinue


            If($process.ExitCode -eq 2){
                Write-LogEntry ("Since BIOS update installed correctly and requires a reboot, stopping loop process to install additional BIOS until later") -Outhost
                Exit
            }
        }

    }
}
Else
{
    Write-LogEntry ("No BIOS Found for model: {0}, skipping..." -f $ComputerModel) -Outhost
}

