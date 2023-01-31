[CmdletBinding()]
param(
    [string]
    $OutputPath = '.\tinfish-generated',

    [switch]
    $ShowAsJson,

    [switch]
    $ShowAsTable,

    [switch]
    $ShowTimings,

    [switch]
    $GenerateSource,

    [string]
    $OctopusDeployRoot
)

Set-StrictMode -Version 3.0

$ErrorActionPreference = 'Stop'
$Script:Indent = @{
    0 = ''
    1 = "`t"
    2 = "`t`t"
    3 = "`t`t`t"
}

. .\PreProcessing.ps1
. .\SourceGeneration.ps1

#
# Loading Swagger data from local file, for local testing. Otherwise grab the data from the specified Octopus Deploy installation.
#
if(-not (Test-Path ./octopus-swagger.json)) {
    Invoke-WebRequest -Uri "$OctopusDeployRoot/api/swagger.json" -OutFile ./octopus-swagger.json
}
$json = Get-Content ./octopus-swagger.json
$swagger = ConvertFrom-Json ($json | Out-String) -AsHashtable

#
# Pre-processing the paths in the Swagger definition.
#
$cmdlets = @{}
foreach ($item in $swagger.paths.GetEnumerator()) {
    $path = $item.Name
    $httpMethods = $item.Value

    foreach($item in $httpMethods.GetEnumerator()) {
        Write-Debug ('Preprocessing {0} of {1}' -f $item.Name, $path)
        $httpMethodName = $item.Name | CapitalizeFirstChar
        $httpMethod = $item.value
        $parameters = @()
        if($httpMethod['parameters']) {
            $parameters = @($httpMethod['parameters'] | GenerateParameterSignature)
        }

        $cmdletName = Format-CmdletName -HttpMethod $httpMethodName -Uri $path
        $cmdlets = Add-CmdletDefinition -HttpMethod $httpMethodName -CmdletName $cmdletName -CmdletLibrary $cmdlets
        $cmdlets = Add-CmdletParameterSet -HttpMethod $httpMethodName -CmdletName $cmdletName -UriPath $path -Parameters $parameters -SetName $httpMethod.operationId -CmdletLibrary $cmdlets
    }
}
$cmdlets | ConvertTo-Json -Depth 10 | Out-File .\preprocessed.json -Encoding ascii

#
# Fresh start on the source generation.
#
if(Test-Path $OutputPath) {
    Remove-Item $OutputPath\* -Recurse -Force | Out-Null
} else {
    MkDir $OutputPath | Out-Null
}


#
# Generating cmdlet source.
#
if($GenerateSource) {
    #
    # Generate functions
    #
    foreach ($cmdlet in $cmdlets.Values | Sort { $_.CmdletName } | Select -First 5) {
        Write-Host ("Generating {0}" -f $cmdlet.CmdletName)

        #
        # Function header
        #
        $source = @("function $($cmdlet.CmdletName) {")

        #
        # Parameter sets
        #
        $source += $cmdlet.Parameters | Format-FunctionParameters -IndentLevel 1

        #
        # Functional body
        #
        $source += $cmdlet.ParameterSets | Format-SwitchStatement -Swagger $swagger -IndentLevel 1

        # Function closing
        $source += "}"

        $source | Out-File "$OutputPath\$($cmdlet.CmdletName).ps1" -Encoding ASCII
    }

    #
    # Pre-written functions.
    #
    Copy-Item .\Tinfish\Invoke-OctopusRequest.ps1 .\artifacts
    Copy-Item .\Tinfish\Set-OctopusConnection.ps1 .\artifacts

    #
    # Generate module level files
    #
    $psm1Content = @'
$Script:OctopusSession = $null

Get-ChildItem $PSScriptRoot\*.ps1 | ForEach-Object {
    . $_.fullname
}
'@
    $psm1Content | Out-File "$Outputpath\Tinfish.psm1" -Encoding ascii

    $manifest = @{
        Path =  "$OutputPath\Tinfish.psd1"
        RootModule = 'Tinfish.psm1'
        Guid = 'b8a9ba46-4a70-424e-96c4-fd6e278aa8d4'
        Author = "David Roberts"
        Description = 'Cmdlets for using the Octopus Deploy REST API'
        FunctionsToExport = $cmdlets.Values.CmdletName + @('Invoke-OctopusRequest', 'Set-OctopusConnection')
    }
    New-ModuleManifest @manifest
}

#
# Local run diagnostic information.
#
if($ShowAsJson) {
    $cmdlets.Values | Where Name -eq 'Worker' | Sort Name,Method | ConvertTo-Json -Depth 6
} elseif($ShowAsTable) {
    $cmdlets.Values | Sort Name,Method | FT Method,Name,Path,CmdletName,@{Name='URIs';Expression={($_.ParameterSets.Display) -join ', '} }
}
