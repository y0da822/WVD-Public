<#
.DESCRIPTION
This script updates an app group users based on a Windows AD security gorup
Tested with Windows AD only, not Azure AD

.PARAMETER adGroupName
Specifies the source group that the WVD App Group will update from.

.PARAMETER aadTenantID
Specifies the Azure tenant ID that you want to login to

.PARAMETER wvdTenantName
Specifies the Tenant name for the WVD service.

.PARAMETER wvdHostPoolName
Specifies the Host Pool name for the WVD service.

.PARAMETER wvdAppGroupName
Specifies the App Group users are added to.

.PARAMETER spID
Specifies the service principal id you want to login to

.PARAMETER spPlainTextPassword
Specifies the service principal password in plain text

.NOTES
Script is offered as-is with no warranty
Test it before you trust it
Original Author : Travis Roberts
Modified Author	: y0da822
Version     : 1.0.0.0 Initial Build
#>

[CmdletBinding()]
param (
    [Parameter (Mandatory = $true)]
    [string] $adGroupName,
	[Parameter (Mandatory = $true)]
    [string] $aadTenantID,
    [Parameter (Mandatory = $true)]
    [string] $wvdTenantName,
    [Parameter (Mandatory = $true)]
    [string] $wvdHostPoolName,
    [Parameter (Mandatory = $true)]
    [string] $wvdAppGroupName,
	[Parameter (Mandatory = $true)]
    [string] $spID,
	[Parameter (Mandatory = $true)]
    [string] $spPlainTextPassword
)

# Verify WVD and AD module
$reqModule = @('ActiveDirectory', 'Microsoft.RDInfra.RDPowershell')
foreach ($module in $reqModule) {
    if (Get-Module -ListAvailable -Name $module) {
        Import-Module $module
        Write-Host "Module $module imported"
    }
    else {
        Write-Host "Module $module does not exist.  Install module and try again" -ForegroundColor Red
        exit
    }
}

$spPlainTextPassword = ConvertTo-SecureString $spPlainTextPassword -AsPlainText -Force
$spCreds = New-Object System.Management.Automation.PSCredential ($spID, $spPlainTextPassword)
# Verify the user is logged in via service principal
$rdsContext = get-rdscontext -ErrorAction SilentlyContinue
if ($rdsContext -eq $null) {
    try {
        Write-host "Use the login window to connect to WVD" -ForegroundColor Red
        Add-RdsAccount -ServicePrincipal -Credential $spCreds -TenantId $aadTenantID -ErrorAction stop -DeploymentUrl "https://rdbroker.wvd.microsoft.com"
    }
    catch {
        $ErrorMessage = $_.Exception.message
        write-host ('Error logging into the WVD account ' + $ErrorMessage)
        exit
    }
}

# Create user list and target list array
$adGroupUsers = @()
$appGroupUsers = @()

# Get the list of AD Group and WVD App Group users
try {
    $adGroupUsers = (Get-ADGroupMember -identity $adGroupName -Recursive | ForEach-Object { Get-ADUser $_.SamAccountName } | Select-Object userPrincipalName).userPrincipalName
    $appGroupUsers = (Get-RdsAppGroupUser -TenantName $wvdTenantName -HostPoolName $wvdHostPoolName -AppGroupName $wvdAppGroupName).UserPrincipalName
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Host ("Error building list of users: " + $ErrorMessage)
    Break
}

# Logic to check if source users are part of the target group, add them if not
foreach ($adGroupUser in $adGroupUsers) {
    # If user is in the AD Group and the App group, do nothing
    if ($appGroupUsers -contains $adGroupUser) {
        Write-Host ("$adGroupUser was found in the targetUsers list")
    }
    # If user is in the AD Group and not in the WVD App Group, add them
    elseif ($appGroupUsers -notcontains $adGroupUser) {
        try {
            Add-RdsAppGroupUser -ErrorAction Stop -TenantName $wvdTenantName -HostPoolName $wvdHostPoolName -AppGroupName $wvdAppGroupName -UserPrincipalName $adGroupUser
            Write-Host ("$adGroupUser not found in $wvdAppGroupName, adding to App Group $wvdAppGroupName")
        }
        Catch {
            $ErrorMessage = $_.Exception.message
            Write-Host ("Error adding user $adGroupUser to the target group. Message:" + $ErrorMessage)
        }
    }
}

# Logic to remove user from the App Group if they are not part of the AD Group
foreach ($appGroupUser in $appGroupUsers) {
    # If ths users are in the WVD App Group, but not in the AD Group, remove them from the App Group
    if (($adGroupUsers) -notcontains $appGroupUser) {
        try {
            Remove-RdsAppGroupUser -ErrorAction Stop -TenantName $wvdTenantName -HostPoolName $wvdHostPoolName -AppGroupName $wvdAppGroupName -UserPrincipalName $appGroupUser
            Write-Host ("$appGroupUser was not found in AD Group $adGroupName, removed from $wvdAppGroupName")
        }
        catch {
            $ErrorMessage = $_.Exception.message
            Write-Host ("Error removing $appGroupUser from $targetGroup Message:" + $ErrorMessage)
        }
    }
} 
