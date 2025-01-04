# Check if Microsoft.Graph.Users module is installed, install if not
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
    Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force -AllowClobber
}

# Check if Microsoft.Graph.Identity.DirectoryManagement module is installed, install if not
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement)) {
    Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force -AllowClobber
}

# Connect to Microsoft Graph
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Connect-MgGraph -Scopes "Group.ReadWrite.All"

# The SKU ID for the license you want to assign
$skuId = "d201f153-d3b2-4057-be2f-fe25c8983e6f"

# Check if the SKU exists
$skuList = Get-MgSubscribedSku | Where-Object { $_.SkuId -eq $skuId }

if (-not $skuList) {
    Write-Host "The specified SKU ID '$skuId' does not exist in the tenant. Exiting."
    exit
}

# Path to the text file containing UPNs (one per line)
$userIdsFilePath = "C:\temp\userId.txt"

# Read UPNs from the text file
$userIds = Get-Content -Path $userIdsFilePath

# Loop through each UPN and check if the user exists and if the license is already assigned
foreach ($userId in $userIds) {
    # Check if the user exists
    $user = Get-MgUser -UserId $userId -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Host "User $userId does not exist. Skipping."
        continue
    }

    if ($user) {

    # Retrieve user license details
    $userLicenses = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$userId/licenseDetails"

    # Check if the SKU ID is already assigned
    $licenseAssigned = $userLicenses.value | Where-Object { $_.skuId -eq $skuId }

    if ($licenseAssigned) {
        Write-Host "License is already assigned to $userId. Skipping."
    } else {
        # Assign the license if not already assigned
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$userId/assignLicense" -Body (@{
            addLicenses = @(@{ skuId = $skuId })
            removeLicenses = @()
        } | ConvertTo-Json) > Null

        Write-Host "License assigned to $userId"
    }
}
}
