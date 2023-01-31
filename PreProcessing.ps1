function Normalize {
    param(
        [Parameter(ValueFromPipeline)]
        $text
    )

    process {
        # Change - spacing to no spacing.
        $segments = $text -split '-'

        # Capitalize the first character. Don't use ToTitleCase
        # because that will change upper case letters after the first.
        # oneTwoThree would become Onetwothree. We want OneTwoThree.
        $segments = $segments | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -ge 1 } | CapitalizeFirstChar

        $segments -join '' | Write-Output
    }
}

function CapitalizeFirstChar {
    param(
        [Parameter(ValueFromPipeline)]
        $String
    )

    process {
        $_.Substring(0,1).ToUpper() + $_.Substring(1)
    }
}

function Singularize {
    param(
        [Parameter(ValueFromPipeline)]
        $text
    )

    process {

        #
        # The order of these are critical. Leave them be.
        #
        $replacements = @(
            @{find = 'ies$'; replaceWith = 'y'},
            @{find = 'sses$'; replaceWith = 'ss'},
            @{find = 'ses$'; replaceWith = 'se'},
            @{find = 'ches$'; replaceWith = 'ch'},
            @{find = 'es$'; replaceWith = 'e'},
            @{find = 'status$|stats$'; replaceWith = $null}
            @{find = 's$'; replaceWith = ''}
        )

        foreach ($item in $replacements) {
            if($text -match $item.find) {
                if($item.replaceWith -ne $null) {
                    $text = $text -replace $item.find,$item.replaceWith
                }
                break;
            }
        }

        Write-Output $text
    }
}

function DetermineParameterDataType {
    param(
        [Parameter(ValueFromPipeline)]
        $SwaggerParameter
    )

    process {
        if($SwaggerParameter['in'] -eq 'body') {
            return 'Object'
        } elseif ($SwaggerParameter['type'] -eq 'integer' -and $SwaggerParameter.format -in @('int32','int64')) {
            return $SwaggerParameter.format.Substring(0,1).ToUpper() + $SwaggerParameter.format.Substring(1) # Capitalize first character for code consistency.
        } elseif ($SwaggerParameter['type'] -eq 'boolean') {
            return 'Switch'
        } elseif ($SwaggerParameter['type'] -eq 'array') {
            # Return the array syntax. String[] or Int32[] for example.
            return (DetermineParameterDataType -SwaggerParameter $SwaggerParameter.items) + '[]'
        } else {
            return 'String'
        }
    }
}

function GenerateParameterSignature {
    param(
        [string]$ParameterSetName,

        [Parameter(ValueFromPipeline)]
        $SwaggerParameter
    )

    process {
        if($SwaggerParameter -ne $null) {
            Write-Debug ('Generating parameter signature for {0}' -f $SwaggerParameter.name)
            return [PSCustomObject]@{
                Name = $SwaggerParameter.name
                DataType =  (DetermineParameterDataType -SwaggerParameter $SwaggerParameter)
                Location = $SwaggerParameter.in
                ParameterSetName = @()
                RequiredParameterSetName = @()
                IsRequired = $SwaggerParameter['required'] -eq $true
            }
        }
    }
}

function Format-CmdletName {
    param(
        [string]
        $HttpMethod,

        [string]
        $Uri
    )

    process {
        Write-Debug ('Determining cmdlet name for {0} {1}' -f $HttpMethod,$Uri)
        $methodVerbMap = @{
            get = "Get"
            delete = "Remove"
            post = "New"
            put = "Update"
        }

        $kindVerbMap = @{
            create = 'New'
            search = 'Find'
        }
        
        $singleSegmentNounMap = @{
            '{spaceId}' = 'SpaceRoot'
        }

        #
        # We default the cmdlet verb to the appropriate verb
        # for the http method. Get, New(Post), etc... This may
        # change based on other data from the Uri.
        #
        $verb = $methodVerbMap[$HttpMethod]

        #
        # Extract the noun part of the path.
        # That being each word in the path put together. Minus the path separator and any path parameters.
        # /{baseSpaceId}/deployment/create/v1 becomes DeploymentCreateV1
        #
        $segments = @($Uri -split '/' | Where-Object { $_ -ne '' })
        $nameSegments = $segments | Where-Object { $_ -notlike '*{*' } # URI parameters will not be part of the name of the cmdlet.
            | Where-Object { $kindVerbMap.Keys -notcontains $_ } # Exclude segments that will become the cmdlet verb.
        $noun = ($nameSegments | Singularize | Normalize) -join ' '
        $noun = $noun -replace ' All$','' # 'All' endpoints are called via the -All parameter on the cmdlet.

        #
        # Some top level paths only ask for a single parameter.
        # That parameter indicates the name. For example: {spaceId} -> Space
        #
        if(-not $noun) {
            Write-Debug 'Determining noun as root or segment path parameter'
            if(-not $segments) {
                # This only happens with the path of '/' which is the root api
                $noun = 'Root'
            } elseif($segments.Length -eq 1) {
                Write-Debug ('Determining cmdlet noun from single segment parameter {0}' -f $segments[0])
                $noun = $singleSegmentNounMap[$segments[0]]
            }
        }

        #
        # Update the verb if any segment should be used as the verb identifier
        # instead of the HTTP method.
        # For example: Search -> Find, instead of Get -> Get
        #
        $kindSegment = $segments | Where-Object { $kindVerbMap.Keys -contains $_ } | Select-Object -First 1
        if($kindSegment) {
            Write-Debug ('  Mapping verb to path segment {0}' -f $kindSegment)
            $verb = $kindVerbMap[$kindSegment]
        }

        $name = "{0}-{1}" -f $verb, ($Noun -replace ' ','')
        if($name -eq '-' -or -not $name -or -not $noun) {
            Write-Warning ('Unable to determine cmdletname')
        }
        return $name
    }
}

function Add-CmdletDefinition {
    param(
        $HttpMethod,
        $CmdletName,
        $CmdletLibrary
    )

    process {
        Write-Debug ('Checking for existing cmdlet {0}' -f $CmdletName)
        if($CmdletLibrary[$CmdletName]) {
            # Basic cmdlet definition already exists. Nothing to do here.
            # This means there's an additional http method that is being added.
            # Which equates to a parameter set.
        } else {
            Write-Debug ('Adding cmdlet definition for {0}' -f $CmdletName)

            $CmdletLibrary[$CmdletName] = [PSCustomObject]@{
                Method = $HttpMethod
                HttpMethod = $HttpMethod
                CmdletName = $CmdletName
                ParameterSets = @() # This holds the parameter sets for use by method body generation.
                Parameters = @() # This holds the parameters directly for param generation.
            }
        }
    
        return $CmdletLibrary
    }
}

function Add-CmdletParameterSet {
    param(
        $HttpMethod,
        $CmdletName,
        $UriPath,
        $Parameters,
        $SetName,
        $CmdletLibrary
    )

    process {
        #
        # Calls ending in '/all' may have no unique parameter and will need one. To identify
        # when to use the '/all' suffixed request rather than the typicall id based request.
        #
        if($path -like '*/all') {
            $Parameters += @{
                in = 'path'
                name = 'All'
                description = ''
                type = 'boolean'
            } | GenerateParameterSignature
        }

        $existingCmdlet = $CmdletLibrary[$CmdletName]

        if($existingCmdlet) {
            Write-Debug ('Adding cmdlet parameter set for {0}' -f $CmdletName)
            #
            # Basic Parameter Set info from the Swagger data.
            #
            $display = if($Parameters) { $Parameters.Name -join ';' }
            $existingCmdlet.ParameterSets += @{
                Path = $UriPath
                Parameters = $Parameters
                SetName = $SetName
                Display = $SetName + '=' + $UriPath + ' -> ' + $display
            }

            #
            # Merge the new parameters with existing parameters. But combine parameter set names on matching parameter names.
            # That comment needs work. This code needs work.
            #
            Write-Debug "Merging parameters from parameter set '$SetName' of $($existingCmdlet.CmdletName)"
            foreach($parameter in $parameters) {
                Write-Debug "  Merging parameter '$($parameter.Name)' "

                $parameter.ParameterSetName = @($SetName)
                $existingParameter = $existingCmdlet.Parameters | Where-Object Name -eq $parameter.Name
                if($existingParameter) {
                    $existingParameter.ParameterSetName += @($parameter.ParameterSetName)
                } else {
                    Write-Debug '    Adding new parameter to cmdlet'
                    $existingCmdlet.Parameters += $parameter
                }

                #
                # Merge the parameter sets this parameter is required for.
                #
                if($parameter.IsRequired) {
                    Write-Debug "    Merging required parameter"
                    $parameter.RequiredParameterSetName = @($SetName)
                    if($existingParameter) {
                        $existingParameter.RequiredParameterSetName += @($parameter.RequiredParameterSetName)
                    }
                    $parameter.IsRequired = $false # Reset it so future parameters may choose to re-enable for different parameter sets.
                }
            }
        } else {
            Write-Warning ("{0} {1} cmdlet not found in listing. Add the cmdlet first." -f $HttpMethod, $CmdletName)
        }

        return $CmdletLibrary
    }
}
