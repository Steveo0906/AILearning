<#
.SYNOPSIS
    Removes an Azure Machine Learning workspace and associated resources.

.DESCRIPTION
    Deletes the Azure ML workspace, Storage Account, Key Vault, App Insights,
    and Container Registry. Optionally deletes the Resource Group.
    Includes version validation and breaking-change warning suppression.

.NOTES
    Author: Steven
    Date:   2025-10-07
#>

param(
    [Parameter(Mandatory = $true)] [string]$SubscriptionId,
    [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)] [string]$WorkspaceName,
    [switch]$RemoveResourceGroup
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

# --- Azure Context ---
Connect-AzAccount | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId

# --- Verify RG ---
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "❌ Resource Group not found: $ResourceGroupName" -ForegroundColor Red
    return
}

# --- Workspace ---
$workspace = Get-AzMLWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ($workspace) {
    Write-Host "Deleting ML Workspace: $WorkspaceName" -ForegroundColor Yellow
    Remove-AzMLWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -Force -Confirm:$false
} else {
    Write-Host "Workspace not found: $WorkspaceName" -ForegroundColor DarkGray
}

# --- Dependent Resources ---
$storageName = ($WorkspaceName.ToLower() + "stor") -replace "[^a-z0-9]", ""
$storageName = $storageName.Substring(0, [Math]::Min(24, $storageName.Length))
$keyVaultName = ($WorkspaceName.ToLower() + "-kv") -replace "[^a-z0-9-]", ""
$appInsightsName = ($WorkspaceName.ToLower() + "-ai") -replace "[^a-z0-9-]", ""

# Storage
if (Get-AzStorageAccount -Name $storageName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) {
    Write-Host "Deleting Storage Account: $storageName" -ForegroundColor Yellow
    Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName -Force
}

# Key Vault
if (Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) {
    Write-Host "Deleting Key Vault: $keyVaultName" -ForegroundColor Yellow
    Remove-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName -Force
}

# App Insights
if (Get-AzApplicationInsights -Name $appInsightsName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) {
    Write-Host "Deleting Application Insights: $appInsightsName" -ForegroundColor Yellow
    Remove-AzApplicationInsights -Name $appInsightsName -ResourceGroupName $ResourceGroupName -Force
}

# Container Registry
$acrList = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
foreach ($acr in $acrList) {
    if ($acr.Name -match $WorkspaceName.ToLower()) {
        Write-Host "Deleting Container Registry: $($acr.Name)" -ForegroundColor Yellow
        Remove-AzContainerRegistry -Name $acr.Name -ResourceGroupName $ResourceGroupName -Force
    }
}

# --- Optionally Remove RG ---
if ($RemoveResourceGroup) {
    Write-Host "`nThis will permanently delete the entire Resource Group '$ResourceGroupName'!" -ForegroundColor Red
    $confirm = Read-Host "Type 'YES' to confirm"
    if ($confirm -eq "YES") {
        Write-Host "Deleting Resource Group: $ResourceGroupName" -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $ResourceGroupName -Force -AsJob
    } else {
        Write-Host "Resource Group deletion cancelled." -ForegroundColor Cyan
    }
}

Write-Host "`n✅ Cleanup process complete." -ForegroundColor Green
