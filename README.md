# Update BIOS for multiple makes and models

## Scripts
**Invoke-BIOSUpgrade.ps1** - Checks the make and model and bios version, then compares that with whats in a corresponding folder (BIOS\<make>\<model>). Does check for Bios password in plain text file BIOSPassword.txt (if exists). It will attempt to suspend bitlocker if enabled. Also sets a SMSTS environment variable SMSTS_BiosRebootRequired, SMSTS_BiosBatteryCharge, SMSTS_BiosBatteryCharge which can be used for a additional sequences. Also set a variable (SMSTS_MutipleBIOSUpdatesNeeded), which allows the bios to update incrementally if needed. This does require to have two steps in the tasksequence to run this script twice (or three times), but one of them should check if this variable is true. 

### Originators/Credit

* [@AdmiralTolwyn](https://github.com/AdmiralTolwyn) (Anton Romanyuk)
* [@NickolajA](https://github.com/NickolajA) (Nickolaj Andersen)