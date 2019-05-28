#========================================================================
# Created by:   Dustin Hedges
# Filename:     Download-DellDriverPacks.ps1
# Version: 		1.0.0.1
# Comment: 		This script will download the latest available Dell Driver
# 				Catalog file from the web, search for any matching OS or
# 				Model strings and download the appropriate Dell Driver
# 				CAB Files to the specified Download Folder.
#========================================================================
<#
.Synopsis
   Downloads the latest available Driver CAB files from Dell
.DESCRIPTION
   Downloads the latest Dell Driver Catalog file (unless a local copy is supplied) and downloads any new Driver CAB's listed in that catalog.
.EXAMPLE
   .\Download-DellDriverPacks.ps1 -DownloadFolder "E:\Dell\Drivers\DellCatalog" -TargetModel "Latitude E7240" -Verbose

.EXAMPLE
   .\Download-DellDriverPacks.ps1 -DownloadFolder "E:\Dell\Drivers\DellCatalog" -TargetOS 64-bit_-_WinPE_5.0 -Verbose

.EXAMPLE
   .\Download-DellDriverPacks.ps1 -DownloadFolder "E:\Dell\Drivers\DellCatalog" -TargetModel "Latitude E7440" -TargetOS Windows_8.1_64-bit -Verbose
#>
[CmdletBinding()]
Param
(
	[Parameter(Mandatory = $false,
			   ValueFromPipelineByPropertyName = $true,
			   Position = 0,
			   HelpMessage = "DriverPackCatalog.cab file.  By default will download from http://downloads.dell.com")]
	[string]$DriverCatalog = "http://downloads.dell.com/catalog/DriverPackCatalog.cab",
	
	[Parameter(Mandatory = $true,
			   ValueFromPipelineByPropertyName = $true,
			   Position = 1)]
	[string]$DownloadFolder,
	
	[Parameter(Mandatory = $false,
			   ValueFromPipelineByPropertyName = $true,
			   Position = 2,
			   HelpMessage = "The Model of System you wish to download files for.  Example: Latitude E7240.")]
	[string]$TargetModel = "WinPE",
	
	[Parameter(Mandatory = $false,
			   ValueFromPipelineByPropertyName = $true,
			   Position = 3,
			   HelpMessage = "The Operating System you wish to download files for.")]
	[ValidateSet("Windows_PE_3.0_x86", "Windows_PE_3.0_x64", "Windows_PE_4.0_x86", "Windows_PE_4.0_x64", "Windows_PE_5.0_x86", "Windows_PE_5.0_x64", "Windows_Vista_x64", "Windows_Vista_x64", "Windows_XP", "Windows_7_x86", "Windows_7_x64", "Windows_8_x86", "Windows_8_x64", "Windows_8.1_x86", "Windows_8.1_x64")]
	[string]$TargetOS,
	
	[Parameter(Mandatory = $false,
			   ValueFromPipelineByPropertyName = $true,
			   Position = 4,
			   HelpMessage = "The 'Expand' switch indicates if you wish to expand/extract the downloaded CAB files into the Download Folder.  Not compatable with the 'DontWaitForDownload switch.")]
	[switch]$Expand,
	
	[Parameter(Mandatory = $false,
			   Position = 5,
			   HelpMessage = "Tells the script to start the download and continue instead of waiting for each download to finish")]
	[switch]$DontWaitForDownload
)

Begin
{
	
	# Trim Trailing '\' from DownloadFolder if it exists
	if ($DownloadFolder.Substring($DownloadFolder.Length - 1, 1) -eq "\")
	{
		$DownloadFolder = $DownloadFolder.Substring(0, $DownloadFolder.Length - 1)
	}
	
	
	# Create DownloadFolder if it does not exist
	if (!(Test-Path $DownloadFolder))
	{
		Try
		{
			New-Item -Path $DownloadFolder -ItemType Directory -Force | Out-Null
		}
		Catch
		{
			Write-Error "$($_.Exception)"
		}
	}
	
	
	# Download Latest Catalog and Extract
	if ($DriverCatalog -match "ftp" -or $DriverCatalog -match "http")
	{
		
		# Cleanup Old Catalog Files
		if (Test-Path "$DownloadFolder\DriverPackCatalog.cab")
		{
			Remove-Item -Path "$DownloadFolder\DriverPackCatalog.cab" -Force -Verbose | Out-Null
		}
		if (Test-Path "$DownloadFolder\DriverPackCatalog.xml")
		{
			Remove-Item -Path "$DownloadFolder\DriverPackCatalog.xml" -Force -Verbose | Out-Null
		}
		
		
		# Download Driver CAB to a temp directory for processing
		Write-Verbose "Downloading Catalog: $DriverCatalog"
		$wc = New-Object System.Net.WebClient
		$wc.DownloadFile($DriverCatalog, "$DownloadFolder\DriverPackCatalog.cab")
		if (!(Test-Path "$DownloadFolder\DriverPackCatalog.cab"))
		{
			Write-Warning "Download Failed. Exiting Script."
			Exit
		}
		
		# Extract Catalog XML File from CAB
		write-Verbose "Extracting Catalog XML to $DownloadFolder"
		$CatalogCABFile = "$DownloadFolder\DriverPackCatalog.cab"
		$CatalogXMLFile = "$DownloadFolder\DriverPackCatalog.xml"
		EXPAND $CatalogCABFile $CatalogXMLFile | Out-Null
		
	}
	else
	{
		if (!(Test-Path -Path $DriverCatalog))
		{
			Write-Warning "$DriverCatalog Does Not Exist!"
			Exit
		}
		else
		{
			$CatalogXMLFile = "$DownloadFolder\DriverPackCatalog.xml"
			Remove-Item -Path $CatalogXMLFile -Force -Verbose | Out-Null
			Write-Verbose "Extracting DriverPackCatalog.xml to $DownloadFolder"
			EXPAND $DriverCatalog $CatalogXMLFile | Out-Null
			
		}
	}
	
	Write-Verbose "Target Model: $TargetModel"
	Write-Verbose "Target Operating System: $($TargetOS.ToString())"
	
	
}# /BEGIN
Process
{
	# Import Catalog XML
	Write-Verbose "Importing Catalog XML"
	[XML]$Catalog = Get-Content $CatalogXMLFile
	
	
	# Gather Common Data from XML
	$BaseURI = "http://$($Catalog.DriverPackManifest.baseLocation)"
	$CatalogVersion = $Catalog.DriverPackManifest.version
	Write-Verbose "Catalog Version: $CatalogVersion"
	
	
	# Create Array of Driver Packages to Process
	[array]$DriverPackages = $Catalog.DriverPackManifest.DriverPackage
	
	Write-Verbose "Begin Processing Driver Packages"
	# Process Each Driver Package
	foreach ($DriverPackage in $DriverPackages)
	{
		#Write-Verbose "Processing Driver Package: $($DriverPackage.path)"
		$DriverPackageVersion = $DriverPackage.dellVersion
		$DriverPackageDownloadPath = "$BaseURI/$($DriverPackage.path)"
		$DriverPackageName = $DriverPackage.Name.Display.'#cdata-section'.Trim()
		
		if ($DriverPackage.SupportedSystems)
		{
			$Brand = $DriverPackage.SupportedSystems.Brand.Display.'#cdata-section'.Trim()
			$Model = $DriverPackage.SupportedSystems.Brand.Model.Display.'#cdata-section'.Trim()
		}
		
		# Check for matching Target Operating System
		if ($TargetOS)
		{
			$osMatchFound = $false
			$sTargetOS = $TargetOS.ToString() -replace "_", " "
			# Look at Target Operating Systems for a match
			foreach ($SupportedOS in $DriverPackage.SupportedOperatingSystems)
			{
				if ($SupportedOS.OperatingSystem.Display.'#cdata-section'.Trim() -match $sTargetOS)
				{
					#Write-Debug "OS Match Found: $sTargetOS"
					$osMatchFound = $true
				}
				
			}
		}
		
		
		# Check for matching Target Model (Not Required for WinPE)
		if ($TargetModel -ne "WinPE")
		{
			$modelMatchFound = $false
			If ("$Brand $Model" -eq $TargetModel)
			{
				#Write-Debug "Target Model Match Found: $TargetModel"
				$modelMatchFound = $true
			}
		}
		
		
		# Check Download Condition Based on Input (Model/OS Combination)
		if ($TargetOS -and ($TargetModel -ne "WinPE"))
		{
			# We are looking for a specific Model/OS Combination
			if ($modelMatchFound -and $osMatchFound) { $downloadApproved = $true }
			else { $downloadApproved = $false }
		}
		elseif ($TargetModel -ne "WinPE" -and (-Not ($TargetOS)))
		{
			# We are looking for all Model matches
			if ($modelMatchFound) { $downloadApproved = $true }
			else { $downloadApproved = $false }
		}
		else
		{
			# We are looking for all OS matches
			if ($osMatchFound) { $downloadApproved = $true }
			else { $downloadApproved = $false }
		}
		
		
		if ($downloadApproved)
		{
			
			# Create Driver Download Directory
			if ($Brand -and $Model)
			{
				$DownloadDestination = "$DownloadFolder\$Brand $Model"
			}
			else
			{
				$DownloadDestination = "$DownloadFolder\$sTargetOS"
			}
			if (!(Test-Path $DownloadDestination))
			{
				Write-Verbose "Creating Driver Download Folder: $DownloadDestination"
				New-Item -Path $DownloadDestination -ItemType Directory -Force | Out-Null
			}
			
			
			# Download Driver Package
			if (!(Test-Path "$DownloadDestination\$DriverPackageName"))
			{
				Write-Verbose "Beging File Download: $DownloadDestination\$DriverPackageName"
				$wc = New-Object System.Net.WebClient
				
				if ($DontWaitForDownload)
				{
					$wc.DownloadFileAsync($DriverPackageDownloadPath, "$DownloadDestination\$DriverPackageName")
				}
				else
				{
					$wc.DownloadFile($DriverPackageDownloadPath, "$DownloadDestination\$DriverPackageName")
					
					if (Test-Path "$DownloadDestination\$DriverPackageName")
					{
						Write-Verbose "Driver Download Complete: $DownloadDestination\$DriverPackageName"
						
						
						# Expand Driver CAB
						if ($Expand)
						{
							Write-Verbose "Expanding Driver CAB: $DownloadDestination\$($DriverPackageName -replace ".cab",'')"
							$oShell = New-Object -ComObject Shell.Application
							
							$sourceFile = $oShell.Namespace("$DownloadDestination\$DriverPackageName").items()
							$destinationFolder = $oShell.Namespace("$DownloadDestination\$($DriverPackageName -replace ".cab",'')")
							$destinationFolder.CopyHere($sourceFile)
						}
					}
				}
			}
			
			
		}# Driver Download Section
		
	}
	
	
}# /PROCESS
End
{
	Write-Verbose "Finished Processing Dell Driver Catalog"
	Write-Verbose "Downloads will execute in the background and may take some time to finish"
}# /END
