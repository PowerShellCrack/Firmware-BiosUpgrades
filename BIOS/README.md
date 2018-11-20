The Update-BIOS.ps1 will auomatatically create the folder if needed

But to manually get the make, model run these commands in powershell

Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty Manufacturer
Get-WmiObject -Class Win32_computersystem | Select-Object -ExpandProperty Model

After these commands are ran, run this script to ge tthe folder name:

$BIOSManufacturer = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty Manufacturer
$Regex = "[^{\p{L}\p{Nd}}]+"
($BIOSManufacturer -replace $Regex, " ").Trim()
