<#
.SYNOPSIS
Sets the common connection information for future function calls.

.DESCRIPTION
Sets the root uri and api key for future function calls. So that you don't have to specify them with each call.
This is required to be called before any other function is used.

.PARAMETER RootUri
The root uri to your Octopus Deploy website. 'https://demo.octopusdeploy.com' for example. Do not include the '/api' in this uri as that is provided in the REST API call links.

.PARAMETER ApiKey
Your api key from your Octopus Deploy profile.

.EXAMPLE
Set-OctopusConnection -RootUri https://demo.octopusdeploy.com -ApiKey "API-ABCDEFGHIJKLMNOP"

.NOTES
Be sure to call this function before making any other calls within this module.
#>
function Set-OctopusConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]
        $RootUri,
        
        [Parameter(Mandatory)]
        [String]
        $ApiKey
    )

    $Script:OctopusSession = [PSCustomObject] @{
        RootUri = $RootUri;
        Headers =  @{ "X-Octopus-ApiKey" = $ApiKey }
    }
}