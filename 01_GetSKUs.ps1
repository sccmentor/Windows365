# Optional - if you receive the error'Install-Package: No match was found for the specified search criteria and module name 'Microsoft.Graph.Identity.DirectoryManagement'. 
# Try Get-PSRepository to see all available registered module repositories.'
# the run the following command Register-PSRepository -Default

Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force -AllowClobber
Connect-MgGraph -Scopes "Organization.Read.All"
Get-MgSubscribedSku | Select-Object SkuId, SkuPartNumber

