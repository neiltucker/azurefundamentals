### Setup Azure VM running SQL Server
### Configure Objects & Variables
Set-StrictMode -Version 2.0
# $ExternalIP = ((Invoke-WebRequest http://icanhazip.com -UseBasicParsing).Content).Trim()
$SubscriptionName = (Get-AzureRMSubscription)[0].Name                                 # Replace with the name of your preferred subscription
$CloudDriveMP = (Get-CloudDrive).MountPoint
$WorkFolder = "/home/$env:USER/clouddrive/labfiles.55264a/"
[Environment]::SetEnvironmentVariable("WORKFOLDER", $WorkFolder, "Machine")
Set-Location $WorkFolder
$PW = Write-Output 'Pa$$w0rdPa$$w0rd' | ConvertTo-SecureString -AsPlainText -Force     # Password for Administrator account
$AdminCred = New-Object System.Management.Automation.PSCredential("Adminz",$PW)        # Login credentials for Administrator account
$Location = "eastus"
$VMName = "vm55264srv"
$NamePrefix = ("cs" + (Get-Date -Format "HHmmss")).ToLower()                           # Replace "cs" with your initials
$ResourceGroupName = $NamePrefix.ToLower() + "rg"
$StorageAccountName = $NamePrefix.ToLower() + "sa"     # Must be lower case
$SAShare = "55264a"                                    # Must be lower case
$CSETMP = $WorkFolder + "55264customscriptextension.tmp"
$CSENew = $WorkFolder + "55264cse.new"

### Log start time of script
$logFilePrefix = "55264AzureSetup" + (Get-Date -Format "HHmm") ; $logFileSuffix = ".txt" ; $StartTime = Get-Date
"Create Azure VM (55264A)"   >  $WorkFolder$logFilePrefix$logFileSuffix
"Start Time: " + $StartTime >> $WorkFolder$logFilePrefix$logFileSuffix

<### Install Modules used in Azure
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
If (Get-PackageProvider -Name NuGet) {Write-Output "NuGet PackageProvider already installed."} Else {Install-PackageProvider -Name "NuGet" -Force}
If (Get-Module -ListAvailable -Name PowerShellGet) {Write-Output "PowerShellGet module already installed"} Else {Find-Module PowerShellGet -IncludeDependencies | Install-Module -Force}
If (Get-Module -ListAvailable -Name AzureRM) {Write-Output "AzureRM module already installed" ; Import-Module AzureRM} Else {Find-Module AzureRM -IncludeDependencies | Install-Module ; Import-Module -Name AzureRM}
If (Get-Module -ListAvailable -Name SQLServer) {Write-Output "SQLServer module already installed" ; Import-Module SQLServer} Else {Install-Module -Name SQLServer -AllowClobber -Force ; Import-Module -Name SQLServer}
If (Get-Module -ListAvailable -Name AzureAD) {Write-Output "AzureAD module already installed" ; Import-Module AzureAD} Else {Install-Module AzureAD -Force ; Import-Module -Name AzureAD}
#>

### Login to Azure & Select Azure Pass
# Connect-AzureRMAccount
$Subscription = Get-AzureRMSubscription -SubscriptionName $SubscriptionName | Set-AzureRMContext

### Create Resource Group, Storage Account & Storage Account Share
New-AzureRMResourceGroup -Name $ResourceGroupName  -Location $Location
New-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -Type Standard_RAGRS
$StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$StorageAccountContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$BlobShare = New-AzureStorageContainer -Name $SAShare.ToLower() -Context $StorageAccountContext -Permission Container -Verbose
$FileShare = New-AzureStorageShare $SAShare.ToLower() -Context $StorageAccountContext
# Create Custom Script Extension File (CSE)
Write-Output '### Copy From File Share Using Mapped Network Drive' > $CSENew
Write-Output '$WorkFolder = "c:\labfiles.55264a\" ; $FileShareName = "55264a"' >> $CSENew
Write-Output 'New-Item -Path $WorkFolder -Type Directory -Force' >> $CSENew
Write-Output "`$StorageAccountName = '$StorageAccountName'" >> $CSENew
Write-Output "`$StorageAccountKey = '$StorageAccountKey'" >> $CSENew
Get-Content $CSENew, $CSETMP > 55264customscriptextension.ps1
Get-ChildItem $WorkFolder"55264customscriptextension.ps1" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"55264a-enu_setupfiles.zip" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"55264customscriptextension.ps1" | Set-AzureStorageFileContent -Share $FileShare -Force
Get-ChildItem $WorkFolder"55264a-enu_setupfiles.zip" | Set-AzureStorageFileContent -Share $FileShare -Force

### Create Network
$NSGRule1 = New-AzureRmNetworkSecurityRuleConfig -Name "RDPRule" -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$NSGRule2 = New-AzureRmNetworkSecurityRuleConfig -Name "MSSQLRule"  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 1433 -Access Allow
$NSGRule3 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTP" -Protocol Tcp -Direction Inbound -Priority 1003 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5985 -Access Allow
$NSGRule4 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTPS"  -Protocol Tcp -Direction Inbound -Priority 1004 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5986 -Access Allow
$NSG1 = New-AzureRMNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name "NSG1" -SecurityRules $NSGRule1,$NSGRule2,$NSGRule3,$NSGRule4 -Force
$Subnet1 = New-AzureRmVirtualNetworkSubnetConfig -Name "Subnet1" -AddressPrefix 192.168.10.0/24
$VirtualNetwork1 = New-AzureRmVirtualNetwork -Name "VirtualNetwork1" -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix 192.168.0.0/16 -Subnet $Subnet1 -Force
$PublicIP1 = New-AzureRmPublicIpAddress -Name "PublicIP1" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic
$NIC1 = New-AzureRmNetworkInterface -Name "NIC1" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VirtualNetwork1.Subnets[0].Id -PublicIpAddressId $PublicIP1.Id -NetworkSecurityGroupId $NSG1.Id

### Create SQL Server VM
# Get-AzureRMVMImagePublisher -Location $Location | Where-Object { $_.PublisherName -like "Microsoft*" }
$PublisherName = "MicrosoftSQLServer"
$Offer = "SQL2017-WS2016"
$Skus = "SQLDEV"
$VMSize = (Get-AzureRMVMSize -Location $Location | Where-Object {$_.Name -like "Standard_DS2*"})[0].Name
$VM1 = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
$VM1 = Set-AzureRmVMOperatingSystem -VM $VM1 -Windows -ComputerName $VMName -Credential $AdminCred -WinRMHttp -ProvisionVMAgent -EnableAutoUpdate
$VM1 = Set-AzureRmVMSourceImage -VM $VM1 -PublisherName $PublisherName -Offer $Offer -Skus $Skus -Version "latest"
$VM1 = Add-AzureRMVMNetworkInterface -VM $VM1 -ID $NIC1.Id
$VHDURI1 = (Get-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).PrimaryEndPoints.Blob.ToString() + "vhdsrv/VHDSRV1.vhd"
$VM1 = Set-AzureRmVMOSDisk -VM $VM1 -Name "VHDSRV1" -VHDURI $VHDURI1 -CreateOption FromImage
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM1 -Verbose
Start-AzureRMVM -Name $VMName -ResourceGroupName $ResourceGroupName
Set-AzureRmVMCustomScriptExtension -Name "Microsoft.Compute" -TypeHandlerVersion "1.9" -Run "55264customscriptextension.ps1" -FileName "55264customscriptextension.ps1" -ContainerName $SAShare -ResourceGroupName $ResourceGroupName -VMName $VMName -Location $Location -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$PublicIPAddress1 = Get-AzureRmPublicIpAddress -Name "PublicIP1" -ResourceGroupName $ResourceGroupName
Write-Output "The virtual machine has been created.  Wait for five (5) miutes, then you may login as Adminz by using Remote Desktop Connection to connect to its Public IP address."
Write-Output "Public IP Address for $VMName is: " $PublicIPAddress1.IPAddress

### Log VM Information and delete the Resource Group
"Student PC   Internet IP:  " + $PublicIPAddress1.IpAddress >> $WorkFolder$logFilePrefix$logFileSuffix
"Resource Group Name     :  " + $ResourceGroupName + "   # Delete the Resource Group to remove all Azure resources created by this script (e.g. Remove-AzureRMResourceGroup -Name $ResourceGroupName -Force)"  >> $WorkFolder$logFilePrefix$logFileSuffix
$EndTime = Get-Date ; $et = "55264AzureSetup" + $EndTime.ToString("yyyyMMddHHmm")
"End Time:   " + $EndTime >> $WorkFolder$logFilePrefix$logFileSuffix
"Duration:   " + ($EndTime - $StartTime).TotalMinutes + " (Minutes)" >> $WorkFolder$logFilePrefix$logFileSuffix
Rename-Item -Path $WorkFolder$logFilePrefix$logFileSuffix -NewName $et$logFileSuffix
Get-Content $et$logFileSuffix
### Remove-AzureRMResourceGroup -Name $ResourceGroupName -Verbose -Force
### Clear-Item WSMan:\localhost\Client\TrustedHosts -Force
### pip install --upgrade pandas, pandas_datareader, scipy, matplotlib, pyodbc, pycountry, azure
