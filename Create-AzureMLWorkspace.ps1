<#
.SYNOPSIS
    Creates an Azure Machine Learning Workspace with supporting resources.
    Fully idempotent, handles soft-deleted Key Vaults, and reuses or creates
    required dependencies.

.DESCRIPTION
    This script:
    - Connects to Azure.
    - Creates or reuses a resource group.
    - Creates Storage Account, Key Vault, and Application Insights.
    - Handles soft-deleted Key Vaults (purge + wait + recreate).
    - Creates or reuses an Azure Machine Learning Workspace.
#>

# ========================
# === CONFIGURATION ===
# ========================
$SubscriptionId     = "<YOUR_SUBSCRIPTION_ID>"
$ResourceGroupName  = "<YOUR_RESOURCE_GROUP>"
$WorkspaceName      = "<YOUR_WORKSPACE_NAME>"
$Region             = "EastUS"

# Derived resource names (adjust as desired)
$storageAccountName = ("st" + ($WorkspaceName.Replace("-", "").Substring(0, [Math]::Min(20, $WorkspaceName.Length)))).ToLower()
$keyVaultName       = ("kv-" + $WorkspaceName).ToLower()
$appInsightsName    = ("appi-" + $WorkspaceName).ToLower()

# ========================
# === AUTHENTICATION ===
# ========================
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount -Subscription $SubscriptionId | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# ========================
# === RESOURCE GROUP ===
# ========================
if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "`nCreating Resource Group: $ResourceGroupName" -ForegroundColor Yellow
    New-AzResourceGroup -Name $ResourceGroupName -Location $Region | Out-Null
} else {
    Write-Host "`nUsing existing Resource Group: $ResourceGroupName" -ForegroundColor Green
}

# ========================
# === STORAGE ACCOUNT ===
# ========================
if (-not (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue)) {
    Write-Host "`nCreating Storage Account: $storageAccountName" -ForegroundColor Yellow
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName `
        -Location $Region -SkuName "Standard_LRS" -Kind "StorageV2" | Out-Null
} else {
    Write-Host "`nUsing existing Storage Account: $storageAccountName" -ForegroundColor Green
}

# ========================
# === APPLICATION INSIGHTS ===
# ========================
if (-not (Get-AzApplicationInsights -ResourceGroupName $ResourceGroupName -Name $appInsightsName -ErrorAction SilentlyContinue)) {
    Write-Host "`nCreating Application Insights: $appInsightsName" -ForegroundColor Yellow
    New-AzApplicationInsights -ResourceGroupName $ResourceGroupName -Name $appInsightsName `
        -Location $Region -Kind web -ApplicationType web | Out-Null
} else {
    Write-Host "`nUsing existing Application Insights: $appInsightsName" -ForegroundColor Green
}

# ========================
# === KEY VAULT ===
# ========================
Write-Host "`n--- Checking Key Vault State ---" -ForegroundColor Cyan

# Check for a soft-deleted Key Vault
$deletedVault = Get-AzKeyVault -VaultName $keyVaultName -InRemovedState -Location $Region -ErrorAction SilentlyContinue

if ($deletedVault) {
    Write-Host "Soft-deleted Key Vault found: $keyVaultName — purging now..." -ForegroundColor Yellow
    Remove-AzKeyVault -VaultName $keyVaultName -Location $Region -InRemovedState -Force
    Write-Host "Purge initiated. Waiting for Azure to release the vault name..." -ForegroundColor DarkYellow
}

# Function: Wait until a Key Vault name becomes available
function Wait-ForKeyVaultAvailability {
    param (
        [string]$VaultName,
        [string]$Region,
        [int]$MaxAttempts = 12,
        [int]$DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $existsActive  = Get-AzKeyVault -VaultName $VaultName -Location $Region -ErrorAction SilentlyContinue
        $existsDeleted = Get-AzKeyVault -VaultName $VaultName -InRemovedState -Location $Region -ErrorAction SilentlyContinue

        if (-not $existsActive -and -not $existsDeleted) {
            Write-Host "Vault name $VaultName is now available (after $attempt attempt(s))." -ForegroundColor Green
            return $true
        } else {
            Write-Host "[$attempt/$MaxAttempts] Vault name still in use or soft-deleted... waiting $DelaySeconds seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Host "[ERROR] Vault name $VaultName is still locked after $($MaxAttempts * $DelaySeconds) seconds." -ForegroundColor Red
    return $false
}

# Wait until the vault name becomes available after purge
if (-not (Wait-ForKeyVaultAvailability -VaultName $keyVaultName -Region $Region)) {
    throw "Key Vault name $keyVaultName is still unavailable. Aborting deployment."
}

# Create or reuse the Key Vault
$existingVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $existingVault) {
    Write-Host "Creating Key Vault: $keyVaultName" -ForegroundColor Yellow
    try {
        $keyVault = New-AzKeyVault -Name $keyVaultName -ResourceGroupName $ResourceGroupName -Location $Region -ErrorAction Stop
        Write-Host "Key Vault created successfully." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to create Key Vault: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "Using existing Key Vault: $keyVaultName" -ForegroundColor Green
    $keyVault = $existingVault
}

# ========================
# === MACHINE LEARNING WORKSPACE ===
# ========================
Write-Host "`nChecking for existing Azure Machine Learning Workspace..." -ForegroundColor Cyan

$workspace = Get-AzMLWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $workspace) {
    Write-Host "Creating Azure Machine Learning Workspace: $WorkspaceName" -ForegroundColor Yellow
    New-AzMLWorkspace -Name $WorkspaceName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Region `
        -KeyVault $keyVaultName `
        -ApplicationInsights $appInsightsName `
        -Sku Basic | Out-Null
    Write-Host "Azure ML Workspace created successfully." -ForegroundColor Green
} else {
    Write-Host "Using existing Azure ML Workspace: $WorkspaceName" -ForegroundColor Green
}

Write-Host "`nDeployment complete. All resources are ready." -ForegroundColor Cyan
