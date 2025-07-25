function Import-UniApimApi 
{
<#
.SYNOPSIS
Imports an API onto Azure API Management.

.DESCRIPTION
Imports an API onto Azure API Management.

.PARAMETER Environment
The Azure APIM environment.

.PARAMETER ApiName
The name of the API.

.PARAMETER ApiPath
The path of the API. Without the leading slash.

.PARAMETER OpenApiSpecPath
The path to the API specification. Without the leading slash.

.EXAMPLE
Import-UniApimApi -Environment "dev" -ApiName "my-api" -ApiPath "my-api" -OpenApiSpecPath "my-api/swagger.json"

.NOTES
At the moment this function only supports scenarios where the following is true:
- The API is hosted under the "API" subdomain of one of the uniphar.ie zones.
- The API is imported as an OpenAPI specification.
- The API is imported to the "Development" product.
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,

        [parameter(Mandatory = $true, Position = 1)]
        [string]$ApiName,

        [parameter(Mandatory = $true, Position = 2)]
        [ValidatePattern('^[^/]')] # No leading slash
        [string]$ApiPath,

        [parameter(Mandatory = $true, Position = 3)]
        [ValidatePattern('^[^/]')] # No leading slash
        [string]$OpenApiSpecPath,

        [parameter(Mandatory = $false, Position = 4)]
        [bool]$UsesCiamLogin = $false

    )

    $ResourceGroupName = "web-$Environment"
    $ApiManagementName = "uni-$ResourceGroupName-apim"

    switch ($Environment) {
        'prod' { $apiHostname = "api.uniphar.ie" }
        default { $apiHostname = "api.$Environment.uniphar.ie" }
    }

    $serviceUrl = "https://$apiHostname"
    $specificationUrl = "$serviceUrl/$OpenApiSpecPath"
    
    $context = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $ApiManagementName

    $apiId = ($ApiName -replace '[ ._]', '-').ToLower()
    $api = Import-AzApiManagementApi -Context $context -ApiId $apiId -SpecificationFormat OpenApi -SpecificationUrl $specificationUrl -Path $ApiPath -ServiceUrl $serviceUrl

    $product = Get-AzApiManagementProduct -Context $context -Title 'Development'

    Add-AzApiManagementApiToProduct -Context $context -ProductId $product.ProductId -ApiId $api.ApiId

    $namedValueName = "resource-uri-$($api.ApiId)"
    $namedValueExists = $null -ne (Get-AzApiManagementNamedValue -Context $context -Name $namedValueName)

    if ($namedValueExists) {
        # Replace placeholder in policy XML for corresponding named value
        $policyPath = "./shared-workflows/utilities/apiPolicy.xml"
        $policyTemplatePath = "./shared-workflows/utilities/apiPolicyTemplate.xml"
        $policyContent = (Get-Content $policyTemplatePath -Raw) -replace '<<<resourceUriNamedValue>>>', $namedValueName -replace '<<<usesCiamLogin>>>', $UsesCiamLogin
        $policyContent | Set-Content $policyPath

        Set-AzApiManagementPolicy -Context $context -ApiId $api.ApiId -PolicyFilePath $policyPath
    }
    else {
        Write-Error "Failed to apply policy to API '$($api.ApiId)'. Named value '$namedValueName' not found."
    }
}