# Name: 05_W365Graph-GetYourAutopatchGroup ID
# Created by: Paul Winstanley @sccmentor and Niall Brady @ncbrady
# Documentation: 

# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Beta.DeviceManagement.Administration)) {
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration -Scope CurrentUser -Force -AllowClobber
}

Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration

# Connect to Microsoft Graph
Connect-MgGraph

# Query all provisioning policies
$provisioningPolicies = Get-MgBetaDeviceManagementVirtualEndpointProvisioningPolicy

# Get the first policy that has a valid Autopatch Group ID
$autopatchPolicy = $provisioningPolicies | Where-Object {
    $_.autopatch -and $_.autopatch.autopatchGroupId -ne $null -and $_.autopatch.autopatchGroupId -ne ""
} | Select-Object -First 1

# Output the Autopatch Group ID if found
if ($autopatchPolicy) {
    Write-Host "Autopatch Group ID: $($autopatchPolicy.autopatch.autopatchGroupId)"
} else {
    Write-Host "No provisioning policies with a valid Autopatch Group ID found."
}
