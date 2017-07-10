<#
    .DESCRIPTION
        An example runbook which gets all the ARM resources using the Run As Account (Service Principal)

    .NOTES
        AUTHOR: Jose Moreno
        LASTEDIT: Mar 14, 2016
#>

param ( 
        [Object]$RecoveryPlanContext 
      ) 

$connectionName = "AzureRunAsConnection"

# Typically you would get these variables from the recovery plan context, or from
# workbook variables. I have hardcoded them for a quick demo
$rgName = "PROD-asr"
$vmName = "myvm01"
$pipName = "DR-vm01-pip"

# Initiating recovery plan
$asrName = $RecoveryPlanContext.RecoveryPlanName
write-output "Initiating association of Public IP address $pipName to VM $vmName in Resource Group $rgName, as part of the recovery plan $asrName"

# Typically you wold have different actions depending whether this is a test or not
if ($RecoveryPlanContext.FailoverType -eq "Test") {
    write-output "Typically you would do something else for test, but I am actually using test failover to demo ASR"
    $vmName = "myvm01-test"
}

# Do this only for failover, not for failback
if ($RecoveryPlanContext.FailoverDirection -eq "PrimaryToSecondary") { 
    try {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

        "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    } catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    # Get the NIC and the existing PIP
    try {
        $rg = Get-AzureRmResourceGroup -name $rgName
        $myVm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName
        $nicResource = get-azurermresource -Id $myVm.NetworkProfile.NetworkInterfaces[0].Id
        $myNic = Get-azurermnetworkinterface -resourcegroupname $nicResource.resourcegroupname -name $nicResource.Name
        $myPip = get-azurermpublicipaddress -resourcegroupname $rgName -name $pipName
    } catch {
        if (!$rg) {
            $ErrorMessage = "RG $rgName not found."
            throw $ErrorMessage 
        } elseif (!$myVm) {
            $ErrorMessage = "VM $vmName not found in resource group $rgName"
            throw $ErrorMessage 
        } elseif (!$myNic) {
            $ErrorMessage = "No NIC found in VM $vmName in resource group $rgName"
            throw $ErrorMessage 
        } elseif (!$myPip) {
            $ErrorMessage = "PIP $pipName not found in resource group $rgName"
            throw $ErrorMessage 
        } else {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    # Assign the PIP to the NIC
    try {
        $myNic.IpConfigurations[0].PublicIpAddress = $myPip
        Set-AzureRmNetworkInterface -NetworkInterface $myNic
        write-output "Public IP address assigned to NIC in VM $vmName"
    } catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
} else {
    $msg = "Failover direction is " + $RecoveryPlanContext.FailoverDirection + ": Doing nothing..."
    write-output $msg
}
