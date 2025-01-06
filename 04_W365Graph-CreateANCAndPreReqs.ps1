# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -AllowClobber
}
if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Install-Module -Name Az.Resources -Scope CurrentUser -Force -AllowClobber
}
if (-not (Get-Module -ListAvailable -Name Az.Network)) {
    Install-Module -Name Az.Network -Scope CurrentUser -Force -AllowClobber
}
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Beta.DeviceManagement.Administration)) {
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration -Scope CurrentUser -Force -AllowClobber
}

# Import the modules
Import-Module -Name Az.Accounts
Import-Module -Name Az.Resources 
Import-Module -Name Az.Network 
Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration

# Connect to Azure account and capture subscription information
Connect-AzAccount
$subscription = (Get-AzContext).Subscription.Id
Write-Host "Using Subscription ID: $subscription"
Connect-MgGraph

# Regular expression for validating resource group name
$rgNameRegex = '^[\w\(\)\.\-_]+$'
# Regular expression for validating IP address and subnet (CIDR format)
$cidrRegex = '^(?:\d{1,3}\.){3}\d{1,3}\/(?:[0-9]|[12][0-9]|3[0-2])$'

# Function to validate IP address ensuring each octet is between 0-254
function Validate-IP {
    param([string]$ipPart)
    $octets = $ipPart.Split('.')
    foreach ($octet in $octets) {
        if ($octet -lt 0 -or $octet -gt 254) {
            return $false
        }
    }
    return $true
}

# Prompt for resource group name and validate
do {
    $resourceGroupName = Read-Host "Please enter the name of the resource group"
    if ($resourceGroupName -match $rgNameRegex -and $resourceGroupName[-1] -ne '.') {
        $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
        if (-not $resourceGroup) {
            Write-Host "Resource group '$resourceGroupName' does not exist. Creating it."
            # Validate the location before creating the resource group
            $attempt = 1
            $maxAttempts = 3
            $locationsLoaded = $false
            $location = ""
            $locations = Get-AzLocation | Select-Object -ExpandProperty Location
            do {
                $location = Read-Host "Please enter the location"
                if ($attempt -eq $maxAttempts -and -not $locationsLoaded) {
                    Write-Host "Loading valid location names..." -ForegroundColor Yellow
                    Write-Host "Valid locations are:" -ForegroundColor Cyan
                    $locations | Sort-Object
                    $locationsLoaded = $true
                }
                if ($locations -contains $location) {
                    break
                } else {
                    $attempt++
                    Write-Host "Invalid location entered. Please try again." -ForegroundColor Red
                }
            } while ($true)
            # Create the resource group if valid location is provided
            New-AzResourceGroup -Name $resourceGroupName -Location $location
            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
        }
        break
    } else {
        Write-Host "Invalid resource group name. Names can only include alphanumeric characters, underscores, parentheses, hyphens, periods (except at the end), and Unicode characters." -ForegroundColor Red
    }
} while ($true)

# Prompt for virtual network name and check if it exists
do {
    $vnetName = Read-Host "Please enter the name of the virtual network"
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if ($vnet) {
        Write-Host "Virtual Network '$vnetName' already exists. Please enter a new name." -ForegroundColor Red
    }
} while ($vnet)

# Prompt and validate the address prefix for virtual network
do {
    $addressPrefix = Read-Host "Please enter the address prefix for the virtual network (e.g., 10.0.0.0/16)"
    $ipPart = $addressPrefix.Split("/")[0]
    if (Validate-IP -ipPart $ipPart -and $addressPrefix -match $cidrRegex) {
        break
    } else {
        Write-Host "Invalid format or IP address. Please enter in valid CIDR format (e.g., 10.0.0.0/16)." -ForegroundColor Red
    }
} while ($true)

# Prompt for subnet name
$subnetName = Read-Host "Please enter the name of the subnet"

# Prompt and validate the subnet address prefix
do {
    $subnetPrefix = Read-Host "Please enter the address prefix for the subnet (e.g., 10.0.1.0/24)"
    $ipPart = $subnetPrefix.Split("/")[0]
    if (Validate-IP -ipPart $ipPart -and $subnetPrefix -match $cidrRegex) {
        break
    } else {
        Write-Host "Invalid format or IP address. Please enter in valid CIDR format (e.g., 10.0.1.0/24)." -ForegroundColor Red
    }
} while ($true)

# Create virtual network and subnet
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPrefix
New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $vnetName -AddressPrefix $addressPrefix -Subnet $subnetConfig
Write-Host "Virtual network '$vnetName' and subnet '$subnetName' created successfully."

# Prompt the user for ANC name
$connectionName = Read-Host "Please enter the name of the Azure Network Connection (ANC)"

# Get the Virtual Network and Subnet IDs
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName
$subnet = $vnet.Subnets | Where-Object { $_.Name -eq $subnetName }

# Verify the network resources were found
if (-not $vnet -or -not $subnet) {
    Write-Host "Error: Virtual network or subnet not found!" -ForegroundColor Red
    exit
}

# Define parameters for ANC creation
$params = @{
    DisplayName      = $connectionName
    Type             = "azureADJoin"
    SubscriptionId   = $subscription
    ResourceGroupId  = "/subscriptions/$subscription/resourceGroups/$resourceGroupName"
    VirtualNetworkId = "/subscriptions/$subscription/resourceGroups/$resourceGroupName/providers/Microsoft.Network/virtualNetworks/$vnetName"
    SubnetId         = "/subscriptions/$subscription/resourceGroups/$resourceGroupName/providers/Microsoft.Network/virtualNetworks/$vnetName/subnets/$subnetName"
}

# Create Azure Network Connection
$ancProfile = New-MgBetaDeviceManagementVirtualEndpointOnPremiseConnection -BodyParameter $params

# Monitor the creation process
do {
    Write-Output "Azure Network Connection is being created... Running Checks please wait this might take a while"
    Start-Sleep -Seconds 60
    $policyState = Get-MgBetaDeviceManagementVirtualEndpointOnPremiseConnection -CloudPcOnPremisesConnectionId $ancProfile.Id
} while ($policyState.HealthCheckStatus -eq "running")

# Check the health status of the ANC
switch ($policyState.HealthCheckStatus) {
    "passed" {
        Write-Output "The Azure Network Connection created successfully."
    }
    default {
        throw "ANC creation failed. Review errors at: https://endpoint.microsoft.com/#view/Microsoft_Azure_CloudPC/EditAzureConnectionWizardBlade/connectionId/$($policyState.id)/tabIndexToActive~/0"
    }
}

Write-Host "Azure Network Connection '$connectionName' created successfully." -ForegroundColor Green
