### Azure setup script for 55315 course Virtual Machine.  This script creates a Windows Server 2019 Domain Controller running SQL Server 2019.  The name of the VM is 55315-MIA-SQL.

### Startup Screen
Clear-Host
Write-Output "Azure setup script for 55315 course Virtual Machine.  This script creates a Windows Server 2019 Domain Controller running SQL Server 2019.  The name of the VM is 55315-MIA-SQL."
Write-Output "You must provide your Azure Portal credentials to continue with the setup.  A new Resource Group will be added to your account which will contain all the resources needed for the course VM."
Write-Output "You may ignore Import-Module errors during the initial stage of the setup."
Write-Output "The total setup time will be about 60 minutes (15 minutes for the initial local script configuration + 45 minutes for the remote script configuration on the VM in Azure.  Instructions for connecting to the Azure VM will be provided at the end of the initial script setup on the local computer.  Wait at least 45 minutes before using those instructions to connect to the Azure VM."

### Configure Objects & Variables
Set-StrictMode -Version 2.0
$SubscriptionName = "Azure Pass"                                       # This variable should be assigned your "Subscription Name"
$WorkFolder = "C:\Labfiles.55315\"                                     # 55315azuresetup.zip must be in this location
$AdventureWorksDB = "Adventureworks2019.bak"
$AdventureWorksDBPATH = $WorkFolder + $AdventureWorksDB 
$AdventureWorksURL = "https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/" + $AdventureWorksDB
Set-Location $WorkFolder
$AzureSetupFiles = $WorkFolder + "55315azuresetup.zip"
Expand-Archive $AzureSetupFiles $WorkFolder -Force -ErrorAction "SilentlyContinue"
Get-ChildItem -Recurse $WorkFolder | Unblock-File
$Location = "EASTUS"
$NamePrefix = "init" + (Get-Date -Format "HHmmss")     			# Replace "init" with your initials
$ResourceGroupName = $namePrefix + "rg"
$StorageAccountName = $namePrefix.tolower() + "sa"                   	# Must be lower case
$SAShare = "55315"
$VMDC = "55315-MIA-SQL"
$PublicIPDCName = "PublicIPDC"
$PW = Write-Output 'Pa$$w0rdPa$$w0rd' | ConvertTo-SecureString -AsPlainText -Force     # Password for Administrator account
$AdminCred = New-Object System.Management.Automation.PSCredential("adminz",$PW)
$CSETMP = $WorkFolder + "55315customscriptextension.tmp"
$CSENew = $WorkFolder + "55315cse.new"

### Log start time of script
$logFilePrefix = "55315AzureSetup" + (Get-Date -Format "HHmm") ; $logFileSuffix = ".txt" ; $StartTime = Get-Date 
"Create Azure VM (55315-MIA-SQL)"   >  $WorkFolder$logFilePrefix$logFileSuffix
"Start Time: " + $StartTime >> $WorkFolder$logFilePrefix$logFileSuffix

### Install Azure Modules
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
If (Get-PackageProvider -Name NuGet) {Write-Output "NuGet PackageProvider already installed."} Else {Install-PackageProvider -Name "NuGet" -Force}
If (Get-Module -ListAvailable -Name PowerShellGet) {Write-Output "PowerShellGet module already installed"} Else {Find-Module PowerShellGet -IncludeDependencies | Install-Module -Force}
If (Get-Module -ListAvailable -Name SQLServer) {Write-Output "SQLServer module already installed" ; Import-Module SQLServer} Else {Install-Module -Name SQLServer -AllowClobber -Force ; Import-Module -Name SQLServer}


### Login to Azure
Connect-AzureRmAccount
$Subscription = Get-AzureRmSubscription -SubscriptionName $SubscriptionName | Select-AzureRmSubscription

### Download AdventureWorks Database
Invoke-WebRequest -Uri $AdventureworksURL -OutFile $AdventureWorksDBPATH
Start-Sleep 5
IF (Test-Path $AdventureWorksDBPATH) {Write-Output "Adventureworks DB downloaded successfully."}

### Create Resource Group, Storage Account & Setup Resources
$ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName  -Location $Location
$StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $StorageAccountName -Location $location -Type Standard_RAGRS
$StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$StorageAccountContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$BlobShare = New-AzureStorageContainer -Name $SAShare.ToLower() -Context $StorageAccountContext -Permission Container -Verbose
$FileShare = New-AzureStorageShare $SAShare.ToLower() -Context $StorageAccountContext
# Create Custom Script Extension File (CSE)
Write-Output '### Copy From File Share Using Mapped Network Drive' > $CSENew
Write-Output "`$WorkFolder = '$WorkFolder' ; `$SAShare = '$SAShare'" >> $CSENew
Write-Output "`$LabFilesFolder = '$WorkFolder'" >> $CSENew
Write-Output 'New-Item -Path $WorkFolder -Type Directory -Force' >> $CSENew
Write-Output "`$StorageAccountName = '$StorageAccountName'" >> $CSENew
Write-Output "`$StorageAccountKey = '$StorageAccountKey'" >> $CSENew
Get-Content $CSENew, $CSETMP > 55315customscriptextension.ps1
Get-ChildItem $WorkFolder"55315customscriptextension.ps1" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"55315azuresetup.zip" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"adventureworks2019.bak" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"55315customscriptextension.ps1" | Set-AzureStorageFileContent -Share $FileShare -Force
Get-ChildItem $WorkFolder"55315azuresetup.zip" | Set-AzureStorageFileContent -Share $FileShare -Force
Get-ChildItem $WorkFolder"adventureworks2019.bak" | Set-AzureStorageFileContent -Share $FileShare -Force

### Create Network
$NSGRule1 = New-AzureRmNetworkSecurityRuleConfig -Name "RDPRule" -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$NSGRule2 = New-AzureRmNetworkSecurityRuleConfig -Name "MSSQLRule"  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 1433 -Access Allow
$NSGRule3 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTP" -Protocol Tcp -Direction Inbound -Priority 1003 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5985 -Access Allow
$NSGRule4 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTPS"  -Protocol Tcp -Direction Inbound -Priority 1004 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5986 -Access Allow
$NSG1 = New-AzureRMNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name "NSG1" -SecurityRules $NSGRule1,$NSGRule2,$NSGRule3,$NSGRule4 -Force
$Subnet10 = New-AzureRmVirtualNetworkSubnetConfig -Name "Subnet10" -AddressPrefix 192.168.10.0/24
$Subnet20 = New-AzureRmVirtualNetworkSubnetConfig -Name "Subnet20" -AddressPrefix 192.168.20.0/24 
$VirtualNetwork1 = New-AzureRmVirtualNetwork -Name "VirtualNetwork1" -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix 192.168.0.0/16 -Subnet $Subnet10, $Subnet20 -Force
$PublicIPDC = New-AzureRmPublicIpAddress -Name $PublicIPDCName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static  
$DCNIC1 = New-AzureRmNetworkInterface -Name "DCNIC1" -ResourceGroupName $ResourceGroupName -Location $Location -PrivateIPAddress 192.168.10.100 -SubnetId $VirtualNetwork1.Subnets[0].Id -PublicIpAddressId $PublicIPDC.Id -NetworkSecurityGroupId $NSG1.Id
$DCNIC2 = New-AzureRmNetworkInterface -Name "DCNIC2" -ResourceGroupName $ResourceGroupName -Location $Location -PrivateIPAddress 192.168.20.100 -SubnetId $VirtualNetwork1.Subnets[1].Id -NetworkSecurityGroupId $NSG1.Id

### Create VMs
# Domain Controller
$PublisherName = "MicrosoftSQLServer"
$Offer = (Get-AzureRMVMImageOffer -Location $Location -PublisherName $PublisherName | Where-Object {$_.Offer -match "SQL2019-WS2019"})[0].Offer 
$Skus = (Get-AzureRmVMImagesku -Location $Location -PublisherName $PublisherName -Offer $Offer | Where-Object {$_.Skus -match "SQLDEV"})[0].Skus
$VMSize = (Get-AzureRMVMSize -Location $Location | Where-Object {$_.Name -match "Standard_DS2"})[0].Name
$VM1 = New-AzureRmVMConfig -VMName $VMDC -VMSize $VMSize
$VM1 = Set-AzureRmVMOperatingSystem -VM $VM1 -Windows -ComputerName $VMDC -Credential $AdminCred -WinRMHttp -ProvisionVMAgent -EnableAutoUpdate
$VM1 = Set-AzureRmVMSourceImage -VM $VM1 -PublisherName $PublisherName -Offer $Offer -Skus $Skus -Version "latest"
$VM1 = Add-AzureRMVMNetworkInterface -VM $VM1 -ID $DCNIC1.Id -Primary
$VM1 = Add-AzureRMVMNetworkInterface -VM $VM1 -ID $DCNIC2.Id 
$VHDURI1 = (Get-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).PrimaryEndPoints.Blob.ToString() + "vhddc/VHDDC1.vhd"
$VM1 = Set-AzureRmVMOSDisk -VM $VM1 -Name "VHDDC1" -VHDURI $VHDURI1 -CreateOption FromImage
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM1 -Verbose
Start-AzureRMVM -Name $VMDC -ResourceGroupName $ResourceGroupName
Set-AzureRmVMCustomScriptExtension -Name "Microsoft.Compute" -TypeHandlerVersion "1.9" -FileName "55315customscriptextension.ps1" -Run "55315customscriptextension.ps1" -ForceRerun $(New-Guid).Guid -ContainerName $SAShare -ResourceGroupName $ResourceGroupName -VMName $VMDC -Location $Location -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$PublicIPAddress1 = Get-AzureRmPublicIpAddress -Name $PublicIPDCName -ResourceGroupName $ResourceGroupName
Write-Output "The virtual machine has been created and the local machine portion of the setup is finished.  Wait 45 minutes for the remote part of the setup to complete, and then you may login as Adminz by using Remote Desktop Connection to connect to its Public IP address."
Write-Output  "Public IP Address for $VMDC is: " $PublicIPAddress1.IpAddress

### Delete Resources and log end time of script
"55315-MIA-SQL   Internet IP:  " + $PublicIPAddress1.IPAddress >> $WorkFolder$logFilePrefix$logFileSuffix
"Resource Group Name  :  " + $ResourceGroupName + "   # Delete the Resource Group to remove all Azure resources created by this script (e.g. Remove-AzureRMResourceGroup -Name $ResourceGroupName -Force)"  >> $WorkFolder$logFilePrefix$logFileSuffix
$EndTime = Get-Date ; $et = "55315AzureSetup" + $EndTime.ToString("yyyyMMddHHmm")
"End Time:   " + $EndTime >> $WorkFolder$logFilePrefix$logFileSuffix
"Duration:   " + ($EndTime - $StartTime).TotalMinutes + " (Minutes)" >> $WorkFolder$logFilePrefix$logFileSuffix 
Rename-Item -Path $WorkFolder$logFilePrefix$logFileSuffix -NewName $et$logFileSuffix
Get-Content $et$logFileSuffix
### Remove-AzureRMResourceGroup -Name $ResourceGroupName -Verbose -Force
