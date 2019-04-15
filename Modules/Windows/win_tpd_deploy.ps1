#!powershell

<#
    .SYNOPSIS
    Deploy tpd utility to workstations

    .DESCRIPTION
    Download tpd utility from web store
    Deploy it to %Program files (x86)% folder
    Set proper permissions to provide autoupdate
    Create desktop shortcut

    .PARAMETER path
    Filesystem path to destination where tpd utility will be placed

    .PARAMETER source
    Web path to tpd utility distro

    .PARAMETER link
    Defines shortcut creation necessity

    .PARAMETER renew
    Defines new version deployment necessity, if available

    .EXAMPLE
    - name: deploy tpd
      win_tpd_deploy:
        path: "C:\Program Files (x86)\tpd"
        source: "http://contoso.com/distros/production/tpd/3/tpd.zip"
        link: 'true'
        renew: 'true'

    Will download tpd utility, deploy it to 'path' and create desktop shortcut
    
    .INPUTS
    Regular Ansible '$args' list, passed from ansible engine functions to be parsed by 'Parse-Args' helper
    
    .OUTPUTS
    Regular Ansible '$result' object formed by 'Add-Warning', 'Fail-Json', 'Exit-Json' helpers

    .COMPONENT
    Requires helper functions from 'Ansible.ModuleUtils.Legacy' module
    WANT_JSON
    
    .FUNCTIONALITY
    Ansible windows powershell module

    .NOTES
    15.04.2019 - public version
    Copyright: (c) 2019, Fetisov Gennadiy <fgm.public@gmail.com>
    GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
#>

#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"

#WANT_JSON

$result = @{
    changed = $false
}

$params = Parse-Args $args

$AnsibleParamPath = @{
    obj = $params
    name = "path" 
    type = "str" 
    default = "C:\Program Files (x86)\tpd"
    failifempty = $false
}
$path = Get-AnsibleParam @AnsibleParamPath

$AnsibleParamSource = @{
    obj = $params
    name = "source" 
    type = "str" 
    default = "http://contoso.com/distros/production/tpd/3/tpd.zip"
    failifempty = $false
}
$source = Get-AnsibleParam @AnsibleParamSource

$AnsibleParamLink = @{
    obj = $params
    name = "link" 
    type = "bool" 
    default = $false
    failifempty = $false
}
$link = Get-AnsibleParam @AnsibleParamLink

$AnsibleParamRenew = @{
    obj = $params
    name = "renew" 
    type = "bool" 
    default = $false
    failifempty = $false
}
$renew = Get-AnsibleParam @AnsibleParamRenew

$users_group = "BUILTIN\Пользователи"
$necessary_permissions = $users_group,
			 "FullControl",
			 "ContainerInherit,ObjectInherit",
			 "None",
			 "Allow"

$tpd_link = @{
    ItemType = 'SymbolicLink';
    Path = "$env:PUBLIC\Desktop";
    Name = "tpd.lnk";
    Value = "$path\tpd.exe";
}

if (-not (Test-Path $path)) {
    try{
        New-Item -Path $path -ItemType Directory
    }
    catch{
        Fail-Json -obj $result -message "$error[0]"
    }
}else{
    Add-Warning -obj $result -message "TPD folder already exist"
}

$folder_acl = Get-Acl $path

$curent_permissions = ($folder_acl.Access |
    Where-Object -Property IdentityReference -eq $users_group).FileSystemRights

if ($curent_permissions -ne 'FullControl'){
    try{
        $permissions = New-Object System.Security.AccessControl.FileSystemAccessRule($necessary_permissions)
        $folder_acl.SetAccessRule($permissions)
    	Set-Acl -Path $path -AclObject $folder_acl
    	$result.changed = $true
    }
    catch{
        Fail-Json -obj $result -message "$error[0]"
    }
}else{
    Add-Warning -obj $result -message "TPD folder permissions already set properly"
}

if ((-not (Test-Path (Join-Path $AnsibleParamPath.default 'tpd.exe'))) -or $renew){
    try{
    	Invoke-WebRequest -Uri $source -OutFile "$path\tpd.zip"
    }catch{
    	Fail-Json -obj $result -message "$error[0]"
    }

    try{
        Expand-Archive -Path "$path\tpd.zip" -DestinationPath $path -Force
    }catch{
        Fail-Json -obj $result -message "$error[0]"
    }

    if (Test-Path "$path\tpd.exe") {
        try{
	        Remove-Item "$path\tpd.zip"
        }catch{
	        Fail-Json -obj $result -message "$error[0]"
        }
        $result.changed = $true
    }
}

if ($link){
    if (-not (Test-Path (Join-Path $tpd_link.Path $tpd_link.Name))){
        try{
    		New-Item @tpd_link
        }catch{
		    Fail-Json -obj $result -message "$error[0]"
        }
    }else{
        Add-Warning -obj $result -message "TPD link already deployed"
    }
}

Exit-Json -obj $result