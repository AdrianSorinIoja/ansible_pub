# Load Citrix modules
asnp Citrix* -ErrorAction SilentlyContinue

# Prompt for search term and search type
$searchTerm = Read-Host "Enter search term (User/Machine)"
Write-Host "`nSearch Options:" -ForegroundColor Yellow
Write-Host "1. Machines only"
Write-Host "2. Sessions/Users only" 
Write-Host "3. Both machines and sessions"
$searchType = Read-Host "Select search type (1-3)"

# List of Citrix DDCs (farms)
$ddcList = @(
    "ddc20.testlab.com",
    "ddc01.testlab.com"
)

# Machine filter string
$machineFilter = @"
(((SessionSupport -eq `"MultiSession`") -and 
((SessionUserName -like `"*${searchTerm}*`") -or 
(DesktopGroupName -like `"*${searchTerm}*`") -or 
(SessionClientName -like `"*${searchTerm}*`") -or 
(CatalogName -like `"*${searchTerm}*`") -or 
(MachineName -like `"*${searchTerm}*`") -or 
(DNSName -like `"*${searchTerm}*`") -or 
(HostingServerName -like `"*${searchTerm}*`") -or 
(HostedMachineName -like `"*${searchTerm}*`"))) -and 
((SessionSupport -eq `"MultiSession`")))
"@

# Session filter string
$sessionFilter = @"
((UserName -like `"*${searchTerm}*`") -or 
(DesktopGroupName -like `"*${searchTerm}*`") -or 
(ClientName -like `"*${searchTerm}*`") -or 
(CatalogName -like `"*${searchTerm}*`") -or 
(DNSName -like `"*${searchTerm}*`") -or 
(HostingServerName -like `"*${searchTerm}*`") -or 
(HostedMachineName -like `"*${searchTerm}*`") -or 
(UserFullName -like `"*${searchTerm}*`") -or 
(UserUPN -like `"*${searchTerm}*`"))
"@

# Machine properties
$machineProperties = @(
    "DNSName", "MachineName", "CatalogName", "DesktopGroupName", 
    "SessionCount", "PowerState", "RegistrationState", "InMaintenanceMode",
    "OSType", "ProvisioningType", "SID", "Uid"
)

# Session properties
$sessionProperties = @(
    "SessionKey", "Uid", "SessionState", "UserFullName", "UserName", "UserUPN", 
    "Protocol", "DNSName", "DesktopGroupName", "CatalogName", "BrokeringTime", 
    "SessionSupport", "AppState", "IsAnonymousUser", "UserSID", "MachineSummaryState"
)

# Function to search machines
function Search-Machines {
    param($ddc)
    try {
        $WarningPreference = "SilentlyContinue"
        $results = Get-BrokerMachine -AdminAddress $ddc `
            -Filter $machineFilter -MaxRecordCount 500 `
            -Property $machineProperties -ReturnTotalRecordCount -Skip 0 `
            -SortBy "+DNSName,+Uid" 2>$null
        
        if ($results) {
            Write-Host "Machine results from $ddc (Found: $($results.Count) machines)" -ForegroundColor Green
            $results | Select-Object DNSName, MachineName, CatalogName, DesktopGroupName, SessionCount, PowerState, RegistrationState, InMaintenanceMode | Format-Table -AutoSize
        } else {
            Write-Host "No machine results from $ddc for search term '$searchTerm'" -ForegroundColor DarkYellow
        }
    } catch {
        if ($_.Exception.GetType().Name -ne "PartialDataException") {
            Write-Error "Failed to query machines on $ddc $($_.Exception.Message)"
        } else {
            Write-Host "Machine query completed with partial data from $ddc" -ForegroundColor Yellow
        }
    }
}

# Function to search sessions
function Search-Sessions {
    param($ddc)
    try {
        $WarningPreference = "SilentlyContinue"
        $results = Get-BrokerSession -AdminAddress $ddc `
            -Filter $sessionFilter -MaxRecordCount 500 `
            -Property $sessionProperties -ReturnTotalRecordCount -Skip 0 `
            -SortBy "+UserName,+Uid" 2>$null
        
        if ($results) {
            Write-Host "Session results from $ddc (Found: $($results.Count) sessions)" -ForegroundColor Green
            $results | Select-Object UserName, UserFullName, DNSName, DesktopGroupName, SessionState, Protocol, BrokeringTime | Format-Table -AutoSize
        } else {
            Write-Host "No session results from $ddc for search term '$searchTerm'" -ForegroundColor DarkYellow
        }
    } catch {
        if ($_.Exception.GetType().Name -ne "PartialDataException") {
            Write-Error "Failed to query sessions on $ddc $($_.Exception.Message)"
        } else {
            Write-Host "Session query completed with partial data from $ddc" -ForegroundColor Yellow
        }
    }
}

# Loop through DDCs and run the appropriate queries
foreach ($ddc in $ddcList) {
    Write-Host ("-" * 60) -ForegroundColor Cyan
    Write-Host "Querying $ddc..." -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor Cyan
    
    # Add site name here
    try {
        $siteName = (Get-BrokerSite -AdminAddress $ddc | Select-Object -ExpandProperty Name)
        Write-Host "Site: $siteName" -ForegroundColor Cyan
    } catch {
        Write-Host "Site: Unable to retrieve" -ForegroundColor Yellow
    }

    switch ($searchType) {
        "1" { 
            Write-Host "Searching machines only..." -ForegroundColor Magenta
            Search-Machines -ddc $ddc 
        }
        "2" { 
            Write-Host "Searching sessions/users only..." -ForegroundColor Magenta
            Search-Sessions -ddc $ddc 
        }
        "3" { 
            Write-Host "Searching both machines and sessions..." -ForegroundColor Magenta
            Search-Machines -ddc $ddc
            Write-Host ""
            Search-Sessions -ddc $ddc 
        }
        default { 
            Write-Host "Invalid selection. Searching both machines and sessions..." -ForegroundColor Magenta
            Search-Machines -ddc $ddc
            Write-Host ""
            Search-Sessions -ddc $ddc 
        }
    }
}

Write-Host ("-" * 60) -ForegroundColor Green
Write-Host "Search completed for term: '$searchTerm'" -ForegroundColor Green
Write-Host ("-" * 60) -ForegroundColor Green
