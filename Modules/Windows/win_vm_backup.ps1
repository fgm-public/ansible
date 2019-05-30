#!powershell

<#
.SYNOPSIS
    Backup VMs with some extra preparations

.DESCRIPTION
    Backup VM, in particular:
        - Offers non system VHDs deattaching
        - Delete excess backups
        - Stop VM
        - Backup VM
    
.PARAMETER vmname
Defines VM names which will backuped

.PARAMETER dest
Defines backup storage destination

.PARAMETER retain
Defines backups count which will be retained

.PARAMETER dry
Defines non system VHDs deattachment necessity

.EXAMPLE

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

$AnsibleParamVMName = @{
    obj = $params
    name = "vmname" 
    type = "str" 
    default = "fb-lks-fs"
    failifempty = $true
}
$vmname = Get-AnsibleParam @AnsibleParamVMName

$AnsibleParamDest = @{
    obj = $params
    name = "dest" 
    type = "str" 
    default = "B:\BackUp\Hyper-V\$env:Computername"
    failifempty = $true
}
$dest = Get-AnsibleParam @AnsibleParamDest

$AnsibleParamRetain = @{
    obj = $params
    name = "retain" 
    type = "int" 
    default = "4"
    failifempty = $false
}
$retain = Get-AnsibleParam @AnsibleParamRetain

$AnsibleParamDry = @{
    obj = $params
    name = "dry" 
    type = "bool" 
    default = $true
    failifempty = $false
}
$dry = Get-AnsibleParam @AnsibleParamDry

$date = (Get-Date).ToString('dd.MM.yyyy')
$BackUpDestination = Join-Path $dest $vm
$VMsSysDisksStorage = 'C:'
$VMStorages = @{}

if ($retain){
    try{
        foreach ($vm in $vmname){
            if (Test-Path $BackUpDestination){
                $Backups = Get-ChildItem $BackUpDestination
                $BackupsToDelete = $Backups.count - $RetainBackupsCount

                if ($BackupsToDelete -gt 0){
                    $BackupsList = $Backups |
                        Sort-Object CreationTime |
                            Select-Object -Last $BackupsToDelete
                    $BackupsList |
                        Remove-Item -Recurse -Force
                }
            }
        }
    }catch{
        Fail-Json -obj $result -message "$error[0]"
    }
}else{
    Add-Warning -obj $result -message "Retain parameter was not specified, will use default ( 4 )"
}

#--Remove non system disks------------------------------------------
if ($dry){
    try{
        foreach ($vm in $vmname){
            $VMStorages.$vm = Get-VMHardDiskDrive -VMName $vm |
                Where-Object -Property Path -NotLike "*$VMsSysDisksStorage\*"
            $VMStorages.$vm |
                Remove-VMHardDiskDrive
        }
    }catch{
        Fail-Json -obj $result -message "$error[0]"
    }
}else{
    Add-Warning -obj $result -message "Dry parameter was not specified, will use default ( True )"
}

try{
    foreach ($vm in $vmname){
        Stop-VM -Name $vm
    }
}catch{
    Fail-Json -obj $result -message "$error[0]"
}

#--Backup VMs----------------------------------------------------
if (Test-Path $BackUpDestination){
    foreach ($vm in $vmname){
        if (-not (Test-Path -Path "$BackUpDestination\$vm\$date")){
            try{
                New-Item -Path "$BackUpDestination\$vm\$date" -Type Directory
            }catch{
                Fail-Json -obj $result -message "$error[0]"
            }
        }
        try{
            Export-VM -Name $vm -Path "$BackUpDestination\$vm\$date" -ErrorAction Stop
            $result.changed = $true
        }catch{
            Fail-Json -obj $result -message "$error[0]"
        }
    }
}

#--Attach non system disks-----------------------------------------
if ($dry){
    try{
        foreach ($vm in $vmname){
            #$VMStorages.$vm.Path | Add-VMHardDiskDrive -VMName $vm
            foreach ($disk in $VMStorages.$vm.Path){
                Add-VMHardDiskDrive -VMName $vm -Path $disk
            }
        }
    }
    catch{
        Fail-Json -obj $result -message "$error[0]"
    }
}

Exit-Json -obj $result