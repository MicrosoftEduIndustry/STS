#*************Initialize variables Start**********************
#Specify local folder path
$LocalFolder = "<Your local path of the app package>\OneDriveContainer"
 
#Specify the User account for an Office 365 global admin in your organization
$AdminAccount = "admin@<your tenant name>.onmicrosoft.com"
$AdminPass = "<admin_password>"
 
#Specify User's OneDrive Site URL and Folder name
$OneDriveURL = "https://<your tenant name>-my.sharepoint.com/personal/<username_domainname_com>"

#Specify name of Security group
$GroupName = "<Security group name>"

#Specify user principal name of each member of the group
$MembersInGroup = @("<member1>","<member2>")

#*************Initialize variables End**********************

#Add required references to SharePoint client assembly to use CSOM 
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client")
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime")  
 
$DocumentLibrary ="Documents"
$TargetFolderName ='' #Leave empty to target root folder
 
#Connect and Load OneDrive Library and Root Folder
$SecPwd = $(ConvertTo-SecureString $AdminPass -asplaintext -force) 
$Ctx = New-Object Microsoft.SharePoint.Client.ClientContext($OneDriveURL) 
$Credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($AdminAccount,$SecPwd) 
$Ctx.credentials = $Credentials
$List = $Ctx.Web.Lists.GetByTitle("$DocumentLibrary")
$Ctx.Load($List)
$Ctx.Load($List.RootFolder)
$Ctx.ExecuteQuery()
 
# Setting Target Folder
$TargetFolder = $null;
$TargetFolderRelativeUrl;
If($TargetFolderName) {
$TargetFolderRelativeUrl = $List.RootFolder.ServerRelativeUrl+"/"+$TargetFolderName
$TargetFolder = $Ctx.Web.GetFolderByServerRelativeUrl($TargetFolderRelativeUrl)
$Ctx.Load($TargetFolder)
$Ctx.ExecuteQuery()
if(!$TargetFolder.Exists){
Throw  "$TargetFolderName - the target folder not exist in OneDrive root folder."
}
} Else {
$TargetFolder = $List.RootFolder
$TargetFolderRelativeUrl = $TargetFolder.ServerRelativeUrl
}

#Get folders and sub folders from source location
$folders= @()
foreach ($file in (Get-ChildItem  -Recurse -Path $LocalFolder -Attributes Directory))
{
$folders +=($file.FullName).replace($LocalFolder+'','')
}
 
#Create folders and sub-folders in destination location
Write-Progress -activity "Creating folder structure in OneDrive" -status "Creating Folder"
foreach ($folder in $folders)
{
$subfolder_names = $folder.split('')
$subfolder = $TargetFolder.Folders.Add($TargetFolderRelativeUrl+$subfolder_names[0].replace('\','/'))

$Ctx.Load($subfolder)
$Ctx.ExecuteQuery()
for ($i = 1; $i -le ($subfolder_names.Count-1) ; $i++)
{
$subfolder = $subfolder.folders.Add($subfolder_names[$i])
$Ctx.Load($subfolder)
$Ctx.ExecuteQuery()
}
}
 
#Read all files recursively from the local folder and upload into corresponding OneDrive folder.
$i = 1
$Files = (Dir $LocalFolder -File -Recurse)
$TotoalFiles = $Files.Length
ForEach($File in $Files)
{
Try {
$URL_Dest = $TargetFolderRelativeUrl +(($file.FullName).Replace($LocalFolder,'')).Replace('\','/')
Write-Progress -activity "Uploading $File" -status "$i out of $TotoalFiles completed"
$FileStream = New-Object IO.FileStream($File.FullName,[System.IO.FileMode]::Open)
$FileCreationInfo = New-Object Microsoft.SharePoint.Client.FileCreationInformation
$FileCreationInfo.Overwrite = $true
$FileCreationInfo.ContentStream = $FileStream
$FileCreationInfo.URL = $URL_Dest
$Upload = $TargetFolder.Files.Add($FileCreationInfo)
$Ctx.Load($Upload)
$Ctx.ExecuteQuery()
}
catch {
Write-Host $_.Exception.Message -Forground "Red"
}
$i++
}

# Create security group and add members
# Check if the Azure AD PowerShell module has already been loaded.
if ( ! ( Get-Module AzureAD ) ) {
    # Check if the Azure AD PowerShell module is installed.
    if ( Get-Module -ListAvailable -Name AzureAD ) {
        # The Azure AD PowerShell module is not load and it is installed. This module
        # must be loaded for other operations performed by this script.
        Write-Host -Fore Yellow "Loading the Azure AD PowerShell module..."
        Import-Module AzureAD
    } else {
        Install-Module AzureAD
    }
}

Connect-AzureAD -Confirm

foreach($group in (Get-AzureADGroup -SearchString $GroupName)) {
    if ($group.DisplayName -eq $GroupName) {
        Write-Host "The group $GroupName is existed already."
        exit
    }
}
Write-Progress -activity "Creating security group " -status "creating group"
$newGroup = New-AzureADGroup -DisplayName $GroupName -SecurityEnabled $true -MailEnabled $false -MailNickName "NotSet"
$groupId = $newGroup.ObjectId
$adminUserEmails = $MembersInGroup
foreach($userEmail in $adminUserEmails) {
    try {
    $user = Get-AzureADUser -Filter "userPrincipalName eq '$userEmail'"
    $userId= $user.ObjectId
    Write-Progress -activity "Adding member to the group " -status "adding member"
    Add-AzureADGroupMember -ObjectId $groupId -RefObjectId $userId
    }
    catch {
        Write-Host "Couldn't add member $userEmail for the group" -Forground Red
    }
}
