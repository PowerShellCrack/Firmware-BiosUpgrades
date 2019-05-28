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
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {    
        return $psISE -ne $null;
    }
    catch {
        return $false;
    }
}

Function Get-ScriptPath {
    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }

    # Makes debugging from ISE easier.
    if ($PSScriptRoot -eq "")
    {
        if (Test-IsISE)
        {
            $psISE.CurrentFile.FullPath
            #$root = Split-Path -Parent $psISE.CurrentFile.FullPath
        }
        else
        {
            $context = $psEditor.GetEditorContext()
            $context.CurrentFile.Path
            #$root = Split-Path -Parent $context.CurrentFile.Path
        }
    }
    else
    {
        #$PSScriptRoot
        $PSCommandPath
        #$MyInvocation.MyCommand.Path
    }
}


Function Get-SMSTSENV{
    param(
        [switch]$ReturnLogPath,
        [switch]$NoWarning
    )
    
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process{
        try{
            # Create an object to access the task sequence environment
            $Script:tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment 
        }
        catch{
            If(${CmdletName}){$prefix = "${CmdletName} ::" }Else{$prefix = "" }
            If(!$NoWarning){Write-Warning ("{0}Task Sequence environment not detected. Running in stand-alone mode." -f $prefix)}
            
            #set variable to null
            $Script:tsenv = $null
        }
        Finally{
            #set global Logpath
            if ($Script:tsenv){
                #grab the progress UI
                $Script:TSProgressUi = New-Object -ComObject Microsoft.SMS.TSProgressUI

                # Convert all of the variables currently in the environment to PowerShell variables
                $tsenv.GetVariables() | % { Set-Variable -Name "$_" -Value "$($tsenv.Value($_))" }
                
                # Query the environment to get an existing variable
                # Set a variable for the task sequence log path
                
                #Something like: C:\MININT\SMSOSD\OSDLOGS
                #[string]$LogPath = $tsenv.Value("LogPath")
                #Somthing like C:\WINDOWS\CCM\Logs\SMSTSLog
                [string]$LogPath = $tsenv.Value("_SMSTSLogPath")
                
            }
            Else{
                [string]$LogPath = $env:Temp
            }
        }
    }
    End{
        If($ReturnLogPath){return $LogPath}
    }
}


Function Format-ElapsedTime($ts) {
    $elapsedTime = ""
    if ( $ts.Minutes -gt 0 ){$elapsedTime = [string]::Format( "{0:00} min. {1:00}.{2:00} sec.", $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10 );}
    else{$elapsedTime = [string]::Format( "{0:00}.{1:00} sec.", $ts.Seconds, $ts.Milliseconds / 10 );}
    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0){$elapsedTime = [string]::Format("{0:00} ms.", $ts.Milliseconds);}
    if ($ts.Milliseconds -eq 0){$elapsedTime = [string]::Format("{0} ms", $ts.TotalMilliseconds);}
    return $elapsedTime
}

Function Format-DatePrefix{
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
    $CombinedDateTime = "$LogDate $LogTime"
    return ($LogDate + " " + $LogTime)
}

Function Write-LogEntry{
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false,Position=2)]
		[string]$Source = '',
        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3,4)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputLogFile = $Global:LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost
    )
    ## Get the name of this function
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

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
    $LogFormat = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
    
    # Add value to log file
    try {
        Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $OutputLogFile -ErrorAction Stop
    }
    catch {
        Write-Host ("[{0}] [{1}] :: Unable to append log entry to [{1}], error: {2}" -f $LogTimePlusBias,$ScriptSource,$OutputLogFile,$_.Exception.ErrorMessage) -ForegroundColor Red
    }
    If($Outhost){
        If($Source){
            $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$Source,$Message)
        }
        Else{
            $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$ScriptSource,$Message)
        }

        Switch($Severity){
            0       {Write-Host $OutputMsg -ForegroundColor Green}
            1       {Write-Host $OutputMsg -ForegroundColor Gray}
            2       {Write-Warning $OutputMsg}
            3       {Write-Host $OutputMsg -ForegroundColor Red}
            4       {If($Global:Verbose){Write-Verbose $OutputMsg}}
            default {Write-Host $OutputMsg}
        }
    }
}

##*===========================================================================
##* VARIABLES
##*===========================================================================
# Use function to get paths because Powershell ISE and other editors have differnt results
$scriptPath = Get-ScriptPath
[string]$scriptDirectory = Split-Path $scriptPath -Parent
[string]$scriptName = Split-Path $scriptPath -Leaf
[string]$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

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
    "GIGABYTE"                              {$FlashUtility = "Efiflash.exe"}
    default                                 {$FlashUtility = "Flash64W.exe"}
}

#Remove any special characters from Manufacturer to support folders name
$Regex = "[^{\p{L}\p{Nd}}]+"
$ComputerMake = ($BIOSManufacturer -replace $Regex, " ").Trim()
#http://downloads.dell.com/catalog/DriverPackCatalog.cab

#Get Model
$ComputerModel = Get-WmiObject -Class Win32_computersystem | Select-Object -ExpandProperty Model

#build path just in case. Path will be empty 
New-Item -ItemType Directory "$BIOSPath\$ComputerMake\$ComputerModel" -ErrorAction SilentlyContinue 

$BiosSearchPath = Join-Path $BIOSPath -ChildPath "$ComputerMake\$ComputerModel"
#Get Bios File Name (Uses the Bios EXE file in the same folder)
$BiosFiles = Get-ChildItem $BiosSearchPath -ErrorAction SilentlyContinue | sort -Descending

#Get BIOS version
[string]$BIOSVersion = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion
Write-LogEntry ("Current BIOS version is: {0}" -f $BIOSVersion)

If($BiosFiles){
   
    #set Tasksequence variable SMSTS_MutipleBIOSUpdatesFound to true if more than one file is found
    if ($tsenv) {
        If($BiosFiles.count -gt 1){
            #FUTURE: configure MDT/SCCM property to boot back into pe for incremental bios upgrade
            $tsenv.Value("SMSTS_MutipleBIOSUpdatesFound") = "True"
        }Else{
            $tsenv.Value("SMSTS_MutipleBIOSUpdatesFound") = "False"
        }
    
    }
    #set bios count to one
    $i = 1

    Foreach ($BiosFile in $BiosFiles){
        #get the version out of the BIOS file if possible

        If($tsenv){$tsenv.Value("SMSTS_MutipleBIOSUpdatesFound") = "True"}
        If($i -le $BiosFiles.count){ If($tsenv){$tsenv.Value("SMSTS_BIOSInstallRound") = $i++} }

        If($BiosFile -match $BIOSVersion){
            Write-LogEntry ("BIOS verison [{0}] matches file version [{1}], no update needed" -f $BIOSVersion,$BiosFile.Name) -Outhost
           
            #stop the multiple Bios install (in tasksequence) if version already found
            #If($tsenv){$tsenv.Value("SMSTS_MutipleBIOSUpdatesFound") = "False"}
            Break
        }
        Else{
            Write-LogEntry ("Found BIOS File: {0}" -f $BiosFile.Name) -Outhost
            #Copy Bios Installer to the root of the package - the Flash64W didn't like when I left it in the Computer Model folder, because it has spaces. (Yes, I tried qoutes and stuff)
            Copy-Item $BiosFile.FullName -Destination $TempPath -ErrorAction SilentlyContinue
        
            #build temp path
            $BIOSFilePath = Join-Path -Path $TempPath -ChildPath $BiosFile.Name

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
                                    $AddArgs = " /s /l=$LogPath\$BiosLogFileName /f";
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
                "Efiflash.exe"  {
                                    $fileArg = $BIOSFilePath;
                                    $AddArgs = "";
                                  }

            }

            #make sure the path exists,build utility path
            $FlashUtilityPath = Join-Path -Path $ToolsPath -ChildPath $FlashUtility
            If( !(Test-Path $FlashUtilityPath) ){Exit}

            
            if ($inPE) {
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
                        Write-LogEntry ("BIOS installed succesfully but a reboot is required") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosRebootRequired") = "True"}
                    }

                10  {
                        Write-LogEntry ("BIOS cannot install because it requires an earlier release first") -Outhost
                        Write-LogEntry ("OR the AC adapter and battery must be plugged in before the system BIOS can be flashed") -Outhost
                        Write-LogEntry ("OR BIOS installation was cancelled") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosBatteryCharge") = "True"}
                    }
                
                9009{
                        Write-LogEntry ("The battery must be charged above 10% before the system BIOS can be flashed") -Outhost
                        Write-LogEntry ("OR the AC adapter and battery must be plugged in before the system BIOS can be flashed") -Outhost
                        If($tsenv){$tsenv.Value("SMSTS_BiosBatteryCharge") = "True"}
                    }

                216 {
                        Write-LogEntry ("BIOS cannot install in Windows PE, it must be installed in windows") -Outhost
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
Else{
    Write-LogEntry ("No BIOS Found for model: {0}, skipping..." -f $ComputerModel) -Outhost
}

