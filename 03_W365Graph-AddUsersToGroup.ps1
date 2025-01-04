# Check if Microsoft.Graph.Groups module is installed, install if not
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
    Install-Module Microsoft.Graph.Groups -Scope CurrentUser -Force -AllowClobber
}

# Import and connect to Microsoft Graph
Import-Module Microsoft.Graph.Groups
Connect-MgGraph -Scopes "Group.ReadWrite.All"

# Prompt the user for the group name
$groupName = Read-Host "Please enter the name of the group"

# Check if the group exists by name
$group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

if (-not $group) {
    # If group doesn't exist, create it
    Write-Host "Group '$groupName' does not exist. Creating new group."
     $GroupParam = @{
        DisplayName = $groupName
        GroupTypes = @()
        SecurityEnabled = $true
        MailEnabled = $false
        MailNickname = $false
    }

    $group = New-MgGroup -BodyParameter $GroupParam
    Write-Host "Group '$groupName' created."
} else {
    Write-Host "Group '$groupName' already exists."
}

# Path to the text file containing UPNs (one per line)
$userIdsFilePath = "C:\temp\userId.txt"

# Read UPNs from the text file
$userUPNs = Get-Content -Path $userIdsFilePath

# Loop through each UPN and check if the user exists
foreach ($upn in $userUPNs) {
    # Check if the user exists
    $user = Get-MgUser -UserId $upn -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Host "User $upn does not exist. Skipping."
        continue
    }

    # Check if the user is already a member of the group
    $isMember = Get-MgGroupMember -GroupId $group.Id | Where-Object { $_.Id -eq $user.Id }
    
    if ($isMember) {
        Write-Host "User $upn is already a member of the group."
    } else {
        # Add the user to the group using their object ID
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
        Write-Host "User $upn added to group"
    }
}
