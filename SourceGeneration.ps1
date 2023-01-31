function Format-RequestCommand {
    param(
        $BasePath,
        $ParameterSet
    )

    #
    # Invocation of the api request, an example:
    # Invoke-OctopusRequest -PathAndQuery '/api/projects' -Skip $skip -Take $take
    #
    # Keep in mind, the generated functions accept the va
    #
    $invocation = "Invoke-OctopusRequest -PathAndQuery '{0}'" -f ($BasePath + $ParameterSet.Path)
    foreach ($apiParameter in $ParameterSet.Parameters) {
        $invocation += " -{0} `${0}" -f $apiParameter.Name
    }

    return $invocation
}

function Format-ParameterAttributes {
    param(
        $IndentLevel,

        $Parameter,

        [Parameter(ValueFromPipeline)]
        $ParameterSetName
    )

    begin {
        $attributes = @()
    }

    process {
        # Making this parameter mandatory for this parameter set if the Swagger said it was required.
        $mandatory = ''
        if($parameter.RequiredParameterSetName -contains $ParameterSetName) {
            $mandatory += ', Mandatory'
        }
        
        $attributes += "[Parameter(ParameterSetName = '{0}'{1})]`n" -f $ParameterSetName, $mandatory
    }

    end {
        $attributes = $Script:Indent[$IndentLevel] + ($attributes -join $Script:Indent[$IndentLevel])
        $attributes | Write-Output
    }
}

function Format-SwitchStatement {
    param(
        $IndentLevel,

        $Swagger,

        [Parameter(ValueFromPipeline)]
        $ParameterSets
    )

    begin {
        $source = @($Script:Indent[$IndentLevel] + "switch (`$PsCmdlet.ParameterSetName) {")
    }

    process {
        $source += "{1}'{0}' {{" -f $PSItem.SetName, $Script:Indent[$IndentLevel + 1]
        $source += $Script:Indent[$IndentLevel + 2] + (Format-RequestCommand -BasePath $swagger.basePath -ParameterSet $PSItem)
        $source += $Script:Indent[$IndentLevel + 1] + '}'
    }

    end {
        $source += $Script:Indent[$IndentLevel] + '}'
        $source | Write-Output
    }
}

function Format-FunctionParameters {
    param(
        $IndentLevel,

        [Parameter(ValueFromPipeline)]
        $Parameters
    )

    begin {
        $source = @("{0}param(" -f $Script:Indent[$IndentLevel])
        $parametersSource = @()
    }

    process {
        $attributes = $PSItem.ParameterSetName | Format-ParameterAttributes -IndentLevel ($IndentLevel + 1) -Parameter $PSItem
        $definition = "{2}[{0}]`${1}" -f $PSItem.DataType, $PSItem.Name, $Script:Indent[$IndentLevel + 1]
        $parametersSource += ($attributes + $definition)
    }

    end {
        $source += $parametersSource -join ",`n`n"
        $source += $Script:Indent[$IndentLevel] + ")`n"
        $source | Write-Output
    }
}