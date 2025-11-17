# Get the script directory and read server names from file
$ScriptPath = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
} else { 
    Get-Location | Select-Object -ExpandProperty Path 
}

$ServerFile = Join-Path -Path $ScriptPath -ChildPath "storefronts.txt"  #IMP ..you all the storefront servers FQDN one per line 

# Check if the file exists
if (-not (Test-Path $ServerFile)) {
    Write-Error "Server list file not found: $ServerFile"
    Write-Host "Please create a 'storefronts.txt' file in the same directory as this script with one server name per line." -ForegroundColor Yellow
    exit
}

# Read server names from file (one per line, ignore empty lines and comments)
$StoreFrontServers = Get-Content $ServerFile | Where-Object { 
    $_ -match '\S' -and $_ -notmatch '^\s*#' 
} | ForEach-Object { $_.Trim() }

if ($StoreFrontServers.Count -eq 0) {
    Write-Error "No valid server names found in $ServerFile"
    exit
}

Write-Host "Found $($StoreFrontServers.Count) server(s) in $ServerFile" -ForegroundColor Green
Write-Host "Servers: $($StoreFrontServers -join ', ')`n" -ForegroundColor Cyan

# ScriptBlock to execute on each remote server
$ScriptBlock = {
    try {
        # Import the Citrix StoreFront module
        Import-Module Citrix.StoreFront -ErrorAction Stop
        
        $Results = @{
            Stores = @()
            Gateways = @()
        }
        
        # Get all store services with error handling
        $StoreServices = @(Get-STFStoreService -ErrorAction Stop)
        
        if ($StoreServices.Count -eq 0) {
            Write-Warning "No Store Services found on this server"
        } else {
            foreach ($StoreService in $StoreServices) {
                try {
                    # Check if there are any configured Farms (Delivery Controllers) for this Store
                    $Farms = @(Get-STFStoreFarm -StoreService $StoreService -ErrorAction SilentlyContinue)
                    
                    if ($Farms.Count -gt 0) {
                        # If there are farms, output one row per farm
                        foreach ($Farm in $Farms) {
                            $Results.Stores += [PSCustomObject]@{
                                Servername       = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
                                StoreName        = $StoreService.FriendlyName
                                VirtualPath      = $StoreService.VirtualPath
                                FarmName         = $Farm.FarmName
                                FarmType         = $Farm.FarmType
                                DeliveryServers  = $Farm.Servers -join "; "
                            }
                        }
                    } else {
                        # If no farms, still show the store info
                        $Results.Stores += [PSCustomObject]@{
                            Servername       = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
                            StoreName        = $StoreService.FriendlyName
                            VirtualPath      = $StoreService.VirtualPath
                            FarmName         = "N/A"
                            FarmType         = "N/A"
                            DeliveryServers  = "None Configured"
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing store '$($StoreService.FriendlyName)': $($_.Exception.Message)"
                }
            }
        }
        
        # Get Gateway information
        try {
            $Gateways = @(Get-STFRoamingGateway -ErrorAction Stop)
            
            foreach ($Gateway in $Gateways) {
                # Parse STA URLs to extract just the URLs
                $STAUrls = @()
                foreach ($STAEntry in $Gateway.SecureTicketAuthorityUrls) {
                    # Each entry is a comma-separated string, first element is the URL
                    $STAUrls += ($STAEntry -split ',')[0]
                }
                
                $Results.Gateways += [PSCustomObject]@{
                    Servername = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
                    GatewayName = $Gateway.Name
                    STAUrls = $STAUrls -join "; "
                }
            }
        }
        catch {
            Write-Warning "Error retrieving gateways: $($_.Exception.Message)"
        }
        
        return $Results
    }
    catch {
        Write-Error "Failed to load StoreFront module or retrieve stores: $($_.Exception.Message)"
        return $null
    }
}

# Execute on all servers and collect results
$AllStores = @()
$AllGateways = @()

foreach ($Server in $StoreFrontServers) {
    Write-Host "Connecting to $Server..." -ForegroundColor Cyan
    
    try {
        $Results = Invoke-Command -ComputerName $Server -ScriptBlock $ScriptBlock -ErrorAction Stop
        
        if ($Results) {
            $AllStores += $Results.Stores
            $AllGateways += $Results.Gateways
            Write-Host "Successfully retrieved data from $Server" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to connect to ${Server}: $($_.Exception.Message)"
    }
}

# Display Store results
if ($AllStores.Count -gt 0) {
    Write-Host "`nStoreFront Configuration Summary:" -ForegroundColor Yellow
    $AllStores | Select-Object Servername, StoreName, VirtualPath, FarmName, FarmType, DeliveryServers | Format-Table -AutoSize
    
    # Export to CSV
    $StoreCSVPath = Join-Path -Path $ScriptPath -ChildPath "StoreFrontConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    try {
        $AllStores | Select-Object Servername, StoreName, VirtualPath, FarmName, FarmType, DeliveryServers | 
            Export-Csv -Path $StoreCSVPath -NoTypeInformation -Force
        Write-Host "Store configuration exported to: $StoreCSVPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to export store CSV: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "No store data retrieved from any server"
}

# Display Gateway results
if ($AllGateways.Count -gt 0) {
    Write-Host "`nGateway Configuration Summary:" -ForegroundColor Yellow
    $AllGateways | Select-Object Servername, GatewayName, STAUrls | Format-Table -AutoSize
    
    # Export to CSV
    $GatewayCSVPath = Join-Path -Path $ScriptPath -ChildPath "GatewayConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    try {
        $AllGateways | Select-Object Servername, GatewayName, STAUrls | 
            Export-Csv -Path $GatewayCSVPath -NoTypeInformation -Force
        Write-Host "Gateway configuration exported to: $GatewayCSVPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to export gateway CSV: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "No gateway data retrieved from any server"
}
