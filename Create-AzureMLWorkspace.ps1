<#
.SYNOPSIS
    Creates an Azure Machine Learning workspace and dependencies.

.DESCRIPTION
    Automates the provisioning of an Azure ML Workspace with a Storage Account,
    Key Vault, and Application Insights. Includes version validation and
    breaking-change warning suppression.

.NOTES
    Author: Steven
    Date:   2025-10-07
#>

param(
    [Parameter(Mandatory = $true)] [string]$SubscriptionId,
    [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)] [string]$WorkspaceName,
    [Parameter(Mandatory = $false)] [string]$Region = "EastUS"
)

# --- Safety and Compatibility Checks ---
$env:SuppressAzurePowerShellBreakingChangeWarnings = "true"
Write-Host "🔧 Azure PowerShell breaking-change warnings suppressed." -ForegroundColor DarkGray

$azModule = Get-Module -ListAvailable Az | Sort-Object Version -Descending | Select-Object -First 1
if ($azModule.Version -lt [version]"11.0.0") {
    Write-Host "⚠️  Your Az module version ($($azModule.Version)) is below 11.0.0. Consider updating for long-term compatibility." -ForegroundColor Yellow
} else {
    Write-Host "✅ Az module version check passed: $($azModule.Version)" -ForegroundColor Green
}

# --- Connect and Set Context ---
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId

# --- Create Resource Group ---
if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Resource Group: $ResourceGroupName ($Region)" -ForegroundColor Yellow
    New-AzResourceGroup -Name $ResourceGroupName -Location $Region | Out-Null
} else {
    Write-Host "Resource Group exists: $ResourceGroupName" -ForegroundColor Green
}

# --- Resource Naming ---
$storageName = ($WorkspaceName.ToLower() + "stor") -replace "[^a-z0-9]", ""
$storageName = $storageName.Substring(0, [Math]::Min(24, $storageName.Length))
$keyVaultName = ($WorkspaceName.ToLower() + "-kv") -replace "[^a-z0-9-]", ""
$appInsightsName = ($WorkspaceName.ToLower() + "-ai") -replace "[^a-z0-9-]", ""

# --- Storage Account ---
if (-not (Get-AzStorageAccount -Name $storageName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Storage Account: $storageName" -ForegroundColor Yellow
    $storage = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName -Location $Region -SkuName Standard_LRS -Kind StorageV2
} else {
    Write-Host "Using existing Storage Account: $storageName" -ForegroundColor Green
    $storage = Get-AzStorageAccount -Name $storageName -ResourceGroupName $ResourceGroupName
}

# --- Key Vault ---
if (-not (Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Key Vault: $keyVaultName" -ForegroundColor Yellow
    $keyVault = New-AzKeyVault -Name $keyVaultName -ResourceGroupName $ResourceGroupName -Location $Region
} else {
    Write-Host "Using existing Key Vault: $keyVaultName" -ForegroundColor Green
    $keyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName
}

# --- Application Insights ---
if (-not (Get-AzApplicationInsights -Name $appInsightsName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Application Insights: $appInsightsName" -ForegroundColor Yellow
    $appInsights = New-AzApplicationInsights -ResourceGroupName $ResourceGroupName -Name $appInsightsName -Location $Region -ApplicationType web
} else {
    Write-Host "Using existing Application Insights: $appInsightsName" -ForegroundColor Green
    $appInsights = Get-AzApplicationInsights -Name $appInsightsName -ResourceGroupName $ResourceGroupName
}

# --- ML Workspace ---
if (-not (Get-AzMLWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Machine Learning Workspace: $WorkspaceName" -ForegroundColor Yellow
    New-AzMLWorkspace -Name $WorkspaceName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Region `
        -StorageAccountName $storage.StorageAccountName `
        -KeyVaultName $keyVault.VaultName `
        -ApplicationInsightsName $appInsights.Name `
        -ContainerRegistryName ""
} else {
    Write-Host "Workspace already exists: $WorkspaceName" -ForegroundColor Green
}

Write-Host "`n✅ Azure Machine Learning Workspace setup complete." -ForegroundColor Cyan
