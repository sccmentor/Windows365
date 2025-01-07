# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Beta.DeviceManagement.Administration)) {
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration -Scope CurrentUser -Force -AllowClobber
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Beta.DeviceManagement.Actions)) {
    Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -Scope CurrentUser -Force -AllowClobber
}

Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Administration
Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions

# Connect to Microsoft Graph
Connect-MgGraph

# 1. Prompt the user for the provisioning policy name and re-prompt if the name already exists
do {
    $policyName = Read-Host "Please enter the name of the provisioning policy"
    $existingPolicy = Get-MgBetaDeviceManagementVirtualEndpointProvisioningPolicy -Filter "displayName eq '$policyName'"
    if ($existingPolicy) {
        Write-Host "Provisioning policy with the name '$policyName' already exists. Please enter a different name." -ForegroundColor Red
    }
} while ($existingPolicy)

# 2. Prompt the user to choose between Enterprise or Frontline license
do {
    $licenseType = Read-Host "Would you like to use Enterprise or Frontline license? (Enter 'E' for Enterprise, 'F' for Frontline)"
    if ($licenseType -match "^[EeFf]$") {
        break
    } else {
        Write-Host "Please enter 'E' for Enterprise or 'F' for Frontline." -ForegroundColor Yellow
    }
} while ($true)

if ($licenseType -eq "F" -or $licenseType -eq "f") {
    $provisioningType = "shared"  # Frontline
} else {
    $provisioningType = "dedicated"  # Enterprise
}

# 3. Prompt the user to choose between Microsoft Hosted Network or Azure Network Connection (ANC)
$networkChoice = $null
do {
    $networkChoice = Read-Host "Would you like to use Microsoft Hosted Network or an Azure Network Connection? (Enter 'M' for Microsoft Hosted, 'A' for ANC)"

    if ($networkChoice -notmatch '^[AM]$') {
        Write-Host "Invalid selection. Please enter 'M' for Microsoft Hosted or 'A' for ANC." -ForegroundColor Red
        $networkChoice = $null
    }
} while ($networkChoice -eq $null)

if ($networkChoice -eq 'A') {
    # Fetch available Azure Network Connections (ANCs)
    Write-Host "Fetching available Azure Network Connections (ANCs), please wait..." -ForegroundColor Yellow
    $ancs = Get-MgBetaDeviceManagementVirtualEndpointOnPremiseConnection

    if (-not $ancs) {
        Write-Host "No Azure Network Connections found." -ForegroundColor Red
        exit
    }

    # Display the available ANCs for selection
    $index = 0
    $ancs | ForEach-Object {
        Write-Host "${index}: $($_.DisplayName) - ID: $($_.Id)"
        $index++
    }

    # Prompt the user to select an ANC
    $ancChoice = $null
    do {
        $ancChoice = Read-Host "Please select an ANC by entering the corresponding number (0 to $($ancs.Count - 1))"

        # Validate that the input is numeric and within range
        if ($ancChoice -match '^\d+$' -and ([int]$ancChoice -ge 0) -and ([int]$ancChoice -lt $ancs.Count)) {
            $ancChoice = [int]$ancChoice  # Convert valid input to integer
        } else {
            Write-Host "Invalid selection. Please enter a number between 0 and $($ancs.Count - 1)." -ForegroundColor Red
            $ancChoice = $null
        }
    } while ($ancChoice -eq $null)

    # Retrieve the selected ANC ID
    $ancId = $ancs[$ancChoice].Id

    Write-Host "You selected ANC: $($ancs[$ancChoice].DisplayName)"

    # Set the domainJoinConfigurations for ANC
    $domainJoinConfigurations = @(
        @{
            type = "azureADJoin"
            onPremisesConnectionId = $ancId
        }
    )
} else {
    Write-Host "You selected Microsoft Hosted Network"

    # Fetch available regions for Cloud PC provisioning
    Write-Host "Fetching available regions for Cloud PC provisioning..." -ForegroundColor Yellow
    $regions = Get-MgBetaDeviceManagementVirtualEndpointSupportedRegion

    # Display the available regions for selection
    $index = 0
    $regions | ForEach-Object {
        Write-Host "${index}: $($_.DisplayName) - Region Group: $($_.RegionGroup)"
        $index++
    }

    # Prompt the user to select a region
    $regionChoice = $null
    do {
        $regionChoice = Read-Host "Please select a region by entering the corresponding number (0 to $($regions.Count - 1))"

        # Validate that the input is numeric and within range
        if ($regionChoice -match '^\d+$' -and ([int]$regionChoice -ge 0) -and ([int]$regionChoice -lt $regions.Count)) {
            $regionChoice = [int]$regionChoice  # Convert valid input to integer
        } else {
            Write-Host "Invalid selection. Please enter a number between 0 and $($regions.Count - 1)." -ForegroundColor Red
            $regionChoice = $null
        }
    } while ($regionChoice -eq $null)

    # Retrieve the selected region
    $selectedRegion = $regions[$regionChoice]
    $regionName = $selectedRegion.DisplayName
    $regionGroup = $selectedRegion.RegionGroup

    Write-Host "You selected: $regionName in Region Group: $regionGroup"

    # Set the domainJoinConfigurations for Microsoft Hosted Network
    $domainJoinConfigurations = @(
        @{
            type = "azureADJoin"
            regionGroup = $regionGroup
            regionName = "automatic"
        }
    )
}


# 4. Prompt the user for SSO choice
do {
    $enableSSO = Read-Host "Would you like to enable Single Sign-On? (Y/N)"
    if ($enableSSO -match "^[YyNn]$") {
        break
    } else {
        Write-Host "Please enter 'Y' for Yes or 'N' for No." -ForegroundColor Yellow
    }
} while ($true)

$ssoEnabled = ($enableSSO -eq "Y" -or $enableSSO -eq "y")

# 5. Fetch available gallery images
Write-Host "Fetching available gallery images, please wait..." -ForegroundColor Yellow
$images = Get-MgBetaDeviceManagementVirtualEndpointGalleryImage

# Display the available images for selection
$index = 0
$images | ForEach-Object {
    Write-Host "${index}: $($_.DisplayName)"
    $index++
}

# Prompt the user to select an image by entering a valid number
$imageChoice = $null
do {
    $imageChoice = Read-Host "Please select an image by entering the corresponding number (0 to $($images.Count - 1))"

    # Validate that the input is numeric and within range
    if ($imageChoice -match '^\d+$' -and ([int]$imageChoice -ge 0) -and ([int]$imageChoice -lt $images.Count)) {
        $imageChoice = [int]$imageChoice
    } else {
        Write-Host "Invalid selection. Please enter a number between 0 and $($images.Count - 1)." -ForegroundColor Red
        $imageChoice = $null
    }
} while ($imageChoice -eq $null)

# Retrieve the selected image details
$imageId = $images[$imageChoice].Id
$imageDisplayName = $images[$imageChoice].DisplayName
Write-Host "You selected: $imageDisplayName"

# 6. Prompt the user to select a language from the list of supported languages
$languages = @(
    @{ Name = "Arabic (Saudi Arabia)"; Code = "ar-SA" }
    @{ Name = "Bulgarian (Bulgaria)"; Code = "bg-BG" }
    @{ Name = "Chinese (Simplified)"; Code = "zh-CN" }
    @{ Name = "Chinese (Traditional)"; Code = "zh-TW" }
    @{ Name = "Croatian (Croatia)"; Code = "hr-HR" }
    @{ Name = "Czech (Czech Republic)"; Code = "cs-CZ" }
    @{ Name = "Danish (Denmark)"; Code = "da-DK" }
    @{ Name = "Dutch (Netherlands)"; Code = "nl-NL" }
    @{ Name = "English (New Zealand)"; Code = "en-NZ" }
    @{ Name = "English (United Kingdom)"; Code = "en-GB" }
    @{ Name = "English (United States)"; Code = "en-US" }
    @{ Name = "Estonian (Estonia)"; Code = "et-EE" }
    @{ Name = "Finnish (Finland)"; Code = "fi-FI" }
    @{ Name = "French (Canada)"; Code = "fr-CA" }
    @{ Name = "French (France)"; Code = "fr-FR" }
    @{ Name = "German (Germany)"; Code = "de-DE" }
    @{ Name = "Greek (Greece)"; Code = "el-GR" }
    @{ Name = "Hebrew (Israel)"; Code = "he-IL" }
    @{ Name = "Hungarian (Hungary)"; Code = "hu-HU" }
    @{ Name = "Italian (Italy)"; Code = "it-IT" }
    @{ Name = "Japanese (Japan)"; Code = "ja-JP" }
    @{ Name = "Korean (Korea)"; Code = "ko-KR" }
    @{ Name = "Latvian (Latvia)"; Code = "lv-LV" }
    @{ Name = "Lithuanian (Lithuania)"; Code = "lt-LT" }
    @{ Name = "Norwegian (Bokmål)"; Code = "nb-NO" }
    @{ Name = "Polish (Poland)"; Code = "pl-PL" }
    @{ Name = "Portuguese (Brazil)"; Code = "pt-BR" }
    @{ Name = "Portuguese (Portugal)"; Code = "pt-PT" }
    @{ Name = "Romanian (Romania)"; Code = "ro-RO" }
    @{ Name = "Russian (Russia)"; Code = "ru-RU" }
    @{ Name = "Serbian (Latin, Serbia)"; Code = "sr-Latn-RS" }
    @{ Name = "Slovak (Slovakia)"; Code = "sk-SK" }
    @{ Name = "Slovenian (Slovenia)"; Code = "sl-SI" }
    @{ Name = "Spanish (Mexico)"; Code = "es-MX" }
    @{ Name = "Spanish (Spain)"; Code = "es-ES" }
    @{ Name = "Swedish (Sweden)"; Code = "sv-SE" }
    @{ Name = "Thai (Thailand)"; Code = "th-TH" }
    @{ Name = "Turkish (Türkiye)"; Code = "tr-TR" }
    @{ Name = "Ukrainian (Ukraine)"; Code = "uk-UA" }
)

# Display the available languages for selection
$index = 0
$languages | ForEach-Object {
    Write-Host "${index}: $($_.Name)"
    $index++
}

# Prompt the user to select a language by entering a valid number
$languageChoice = $null
do {
    $languageChoice = Read-Host "Please select a language by entering the corresponding number (0 to $($languages.Count - 1))"

    # Validate that the input is numeric and within range
    if ($languageChoice -match '^\d+$' -and ([int]$languageChoice -ge 0) -and ([int]$languageChoice -lt $languages.Count)) {
        $languageChoice = [int]$languageChoice
    } else {
        Write-Host "Invalid selection. Please enter a number between 0 and $($languages.Count - 1)." -ForegroundColor Red
        $languageChoice = $null
    }
} while ($languageChoice -eq $null)

# Retrieve the selected language details
$selectedLanguage = $languages[$languageChoice]
$selectedLanguageCode = $selectedLanguage.Code
Write-Host "You selected: $($selectedLanguage.Name) with code: $selectedLanguageCode"


# 7. Prompt for device name template (5-15 characters), convert to uppercase, and validate
do {
    $deviceNameTemplate = (Read-Host "Please enter a device name template (e.g., cpc-%RAND:5%)").ToUpper()

    # Extract the numbers from %RAND:y% and %USERNAME:x%
    $randLength = [regex]::Match($deviceNameTemplate, "%RAND:(\d+)%").Groups[1].Value
    $userLength = [regex]::Match($deviceNameTemplate, "%USERNAME:(\d+)%").Groups[1].Value

    # Ensure the values are integers and default to 0 if not present
    $randLength = [int]($randLength -as [int]) -ne 0 ? [int]$randLength : 0
    $userLength = [int]($userLength -as [int]) -ne 0 ? [int]$userLength : 0

    # Strip out %RAND:y% and %USERNAME:x% from the template before length validation
    $strippedTemplate = $deviceNameTemplate -replace "%RAND:\d+%", "" -replace "%USERNAME:\d+%", ""

    # Ensure the name is valid according to Microsoft rules (5-15 chars excluding macros, must contain %RAND:y%)
    $totalLength = $strippedTemplate.Length + $randLength + $userLength

    if ($totalLength -ge 5 -and $totalLength -le 15 -and 
        $deviceNameTemplate -match "%RAND:\d+%") {
        break
    } else {
        Write-Host "Device name template must result in 5 to 15 characters and must include %RAND:y% where y is at least 5." -ForegroundColor Red
    }
} while ($true)

Write-Host "Device name template set to: $deviceNameTemplate"

# 8. Prompt the user for Autopatch services
$useAutopatch = Read-Host "Would you like to use Autopatch services? (Y/N)"
$autopatchGroupId = $null

if ($useAutopatch -match "^[Yy]$") {
    # Fetch autopatch group ID (assuming you have a predefined ID or method to fetch it)
    $autopatchGroupId = "aa48b6c3-23be-4e12-8a72-e138961c13b3"  # Example ID
    Write-Host "Autopatch Group ID: $autopatchGroupId"
}

# 9. Now prompt the user for an assignment group name 
    $groupName = Read-Host "Please enter the EntraID group name for assignment"

    # Check if the group exists by name and re-prompt if not
    do {
        $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        if (-not $group) {
            Write-Host "Group '$groupName' does not exist. Please try again." -ForegroundColor Red
            $groupName = Read-Host "Please enter the EntraID group name for assignment"
        }
    } while (-not $group)

    # Extract the Group ID
    $groupId = $group.Id
    Write-Host "Using group '$groupName' with ID: $groupId" -ForegroundColor Green

    if ($provisioningType -eq "shared") {
        Write-Host "Fetching available Frontline service plans..." -ForegroundColor Yellow
        $servicePlans = Get-MgBetaDeviceManagementVirtualEndpointFrontLineServicePlan
    
        # Display the available service plans
        $index = 0
        $servicePlans | ForEach-Object {
            Write-Host "${index}: $($_.DisplayName)"
            $index++
        }
    
        # Prompt the user to select a service plan with validation
        $servicePlanChoice = $null
        do {
            $servicePlanChoice = Read-Host "Please select a service plan by entering the corresponding number (0 to $($servicePlans.Count - 1))"
    
            # Validate that the input is numeric and within range
            if ($servicePlanChoice -match '^\d+$' -and ([int]$servicePlanChoice -ge 0) -and ([int]$servicePlanChoice -lt $servicePlans.Count)) {
                $servicePlanChoice = [int]$servicePlanChoice
            } else {
                Write-Host "Invalid selection. Please enter a number between 0 and $($servicePlans.Count - 1)." -ForegroundColor Red
                $servicePlanChoice = $null
            }
        } while ($servicePlanChoice -eq $null)
    
        # Retrieve the selected service plan details
        $selectedServicePlan = $servicePlans[$servicePlanChoice]
        $servicePlanId = $selectedServicePlan.Id
    
        Write-Host "You selected: $($selectedServicePlan.DisplayName)"
    }
    

# Define the body for the provisioning policy creation
$params = @{
    "@odata.type" = "#microsoft.graph.cloudPcProvisioningPolicy"
    displayName = $policyName
    provisioningType = $provisioningType
    imageId = $imageId
    imageDisplayName = $imageDisplayName
    imageType = "gallery"
    enableSingleSignOn = $ssoEnabled
    domainJoinConfigurations = $domainJoinConfigurations
    windowsSettings = @{
        language = $selectedLanguageCode
    }
    cloudPcNamingTemplate = $deviceNameTemplate
}

# Add Autopatch and microsoftManagedDesktop if enabled
if ($autopatchGroupId) {
    $params.autopatch = @{
        autopatchGroupId = $autopatchGroupId
    }
    $params.microsoftManagedDesktop = @{
        managedType = "starterManaged"
        profile = $null
    }
}

# Create the provisioning policy
$provisioningPolicy = New-MgBetaDeviceManagementVirtualEndpointProvisioningPolicy -BodyParameter $params

# Check if the provisioning policy was created successfully
if ($provisioningPolicy.Id) {
    Write-Host "Provisioning Policy '$policyName' created successfully with ID: $($provisioningPolicy.Id)" -ForegroundColor Green

    # Now assign the provisioning policy to the selected group if Enterprise is chosen
    if ($provisioningType -eq "dedicated") {
        $assignmentParams = @{
            assignments = @(
                @{
                    target = @{
                        groupId = $groupId
                    }
                }
            )
        }

        # Assign the policy to the group
        Set-MgBetaDeviceManagementVirtualEndpointProvisioningPolicy -CloudPcProvisioningPolicyId $provisioningPolicy.Id -BodyParameter $assignmentParams

        Write-Host "Provisioning Policy '$policyName' assigned to group '$groupName'." -ForegroundColor Green
    } else {
    #    Write-Host "Frontline policy created. No group assignment is created at present." -ForegroundColor Green
        $assignmentParams = @{
            assignments = @(
                @{
                    target = @{
                        groupId = $groupId
                        servicePlanId = $servicePlanId
				        # allotmentLicensesCount = 
                    }
                }
            )
        }

    # Assign the policy to the group
    Set-MgBetaDeviceManagementVirtualEndpointProvisioningPolicy -CloudPcProvisioningPolicyId $provisioningPolicy.Id -BodyParameter $assignmentParams

    Write-Host "Provisioning Policy '$policyName' assigned to group '$groupName'." -ForegroundColor Green
    }
} else {
    Write-Host "Failed to create the provisioning policy." -ForegroundColor Red
}
