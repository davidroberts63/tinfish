Add-Type -Path .\Tavis.UriTemplates\lib\netstandard2.0\Tavis.UriTemplates.dll

<#
.SYNOPSIS
Invoke an Octopus Deploy REST api call.

.DESCRIPTION
Invokes an Octopus Deploy REST API.

.PARAMETER Method
The HTTP method to use in the request. Defaults to GET

.PARAMETER Uri
The absolute Uri to the REST API call to make. This may be a UriTemplate if desired.

.PARAMETER PathAndQuery
The absolute Path and query string to the REST API call to make. This may be a UriTemplate if desired. This will be appended to the RootUri from Set-OctopusConnection.

.PARAMETER ApiKey
The ApiKey for authenticating with Octopus Deploy. This is only needed when using the -Uri parameter. Otherwise the ApiKey from Set-OctopusConnection is used.

.PARAMETER Headers
Additional headers to be combined with the authentication headers in the REST API call.

.PARAMETER Body
An object which will be given to the body of the REST API call.

.PARAMETER Remaining
Any remaining parameters will be used in the UriTemplate processing.

.EXAMPLE
Invoke-OctopusRequest -PathAndQuery /api/Spaces-1/workerpools{/id}{?name,skip,ids,take,partialName} -Skip 5 -Take 10

The above call results in a call to https://baseoctopus.mycompany.com/api/Spaces-1/workerpools?skip=5&take=10

.NOTES

#>
function Invoke-OctopusRequest {
    [CmdletBinding()]
    param(
        [String]
        $Method = "GET",

        [Parameter(ParameterSetName='FullUri', Mandatory)]
        [Uri]
        $Uri,

        [Parameter(ParameterSetName='SessionBasedPath', Mandatory)]
        [String]
        $PathAndQuery,

        [Parameter(ParameterSetName='FullUri', Mandatory)]
        [Parameter(ParameterSetName='SessionBasedPath')]
        [String]
        $ApiKey,

        [System.Collections.IDictionary]
        $Headers,

        [Object]
        $Body,

        [Parameter(ValueFromRemainingArguments)]
        $Remaining
    )

    if($PSCmdlet.ParameterSetName -eq 'SessionBasedPath') {
        Write-Debug 'Getting session Uri and headers'
        $Uri = [Uri]($Script:OctopusSession.RootUri + "$PathAndQuery")
        $Headers =  $Headers + $Script:OctopusSession.Headers
    } else {
        Write-Debug 'Using provided Api Key'
        $Headers =  $Headers + @{ "X-Octopus-ApiKey" = $ApiKey }
    }

    #
    # Apply the remaining arguments to the Uri, assuming it is a Uri Template.
    # If its not a Uri Template the Uri will remain unmodified.
    #
    $template = New-Object Tavis.UriTemplates.UriTemplate($Uri.ToString(), $false, $true)
    $currentArgument = $null
    foreach($item in $Remaining) {
        if($item -Match '^-') {
            $currentArgument = $item -Replace '^-(.*):?$','$1' # The ':' accounts for argument splatting. Allows you to do @something at the end of the function call arg list.
            Write-Debug "Processing remaining argument: $currentArgument"
            $template.SetParameter($currentArgument, '')
        } elseif ($currentArgument -ne $null) {
            Write-Debug "Applying argument '$currentArgument' value of $item"
            $template.SetParameter($currentArgument, $item)
            $currentArgument = $null
        } else {
            throw ('Unknown argument {0}' -f $item)
        }
    }
    $finalUri = $template.Resolve()

    Write-Verbose $finalUri
    Invoke-RestMethod -Uri $finalUri -Method $Method -Headers $Headers -Body $Body
}