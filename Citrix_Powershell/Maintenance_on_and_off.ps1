# Load Citrix snap-ins
asnp Citrix*

# Step 0: Ask for Delivery Group and number of VMs
$DGName = Read-Host "Enter the Delivery Group name"
[int]$Count = Read-Host "How many VMs do you want to migrate?"

# Get current timestamp for output file
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutFile   = "C:\Temp\migration_$TimeStamp.csv"

# Collect results for logging
$Results = @()

# Step 1: Find FSB machines (NOT in maintenance, REGISTERED) within the delivery group
$FSBMachines = Get-BrokerMachine -MaxRecordCount 2147483647 `
    | Where-Object { $_.DesktopGroupName -eq $DGName -and $_.MachineName -like "*FSB*" -and $_.InMaintenanceMode -eq $false -and $_.RegistrationState -eq "Unregistered" } `
    | Select-Object -First $Count

# Step 2: Find MSA machines (IN maintenance, REGISTERED) within the delivery group
$MSAMachines = Get-BrokerMachine -MaxRecordCount 2147483647 `
    | Where-Object { $_.DesktopGroupName -eq $DGName -and $_.MachineName -like "*MSA*" -and $_.InMaintenanceMode -eq $true -and $_.RegistrationState -eq "Unregistered" } `
    | Select-Object -First $Count

# Preview changes
Write-Host "`nThe following VMs will be set to MAINTENANCE:`n" -ForegroundColor Yellow
$FSBMachines | Select-Object MachineName, InMaintenanceMode, RegistrationState | Format-Table

Write-Host "`nThe following VMs will be REMOVED from MAINTENANCE:`n" -ForegroundColor Yellow
$MSAMachines | Select-Object MachineName, InMaintenanceMode, RegistrationState | Format-Table

# Ask for confirmation
$Confirm = Read-Host "`nDo you want to continue? (Y/N)"
if ($Confirm -notin @("Y","y","Yes","YES")) {
    Write-Host "Operation cancelled by user." -ForegroundColor Red
    exit
}

# Step 3: Apply Maintenance Mode changes
foreach ($machine in $FSBMachines) {
    Set-BrokerMachineMaintenanceMode -InputObject $machine -MaintenanceMode $true -LoggingId ([guid]::NewGuid().ToString())
    
    $Results += [PSCustomObject]@{
        MachineName   = $machine.MachineName
        Action        = "Set Maintenance"
        Timestamp     = (Get-Date)
        DeliveryGroup = $DGName
    }
}

foreach ($machine in $MSAMachines) {
    Set-BrokerMachineMaintenanceMode -InputObject $machine -MaintenanceMode $false -LoggingId ([guid]::NewGuid().ToString())
    
    $Results += [PSCustomObject]@{
        MachineName   = $machine.MachineName
        Action        = "Remove Maintenance"
        Timestamp     = (Get-Date)
        DeliveryGroup = $DGName
    }
}

# Step 4: Export results to CSV
$Results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8

Write-Host "`nMigration completed. Log file created at $OutFile" -ForegroundColor Green
