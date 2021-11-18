<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 7.0

Copyright (c) 2017, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   iDRAC cmdlet using Redfish API to change iDRAC user password
.DESCRIPTION
   iDRAC cmdlet using Redfish API to change iDRAC user password. Once the iDRAC user password has changed, cmdlet will execute GET command to validate the new password was set. If using dash(-) or single quote(') in your current or new password, make sure to surround the password value with double quotes.
   Supported parameters: 
   - idrac_ip: Pass in iDRAC IP address
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC username current password
   - get_idrac_user_account_ids: Pass in a value of 'y' to get iDRAC user account IDs
   - idrac_user_id: Pass in the user account ID"
   - idrac_new_password: Pass in the new password you want to set to
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -get_idrac_user_account_ids y
   This example will get account details for all iDRAC user account IDs 1 through 16.
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -get_idrac_user_account_ids y
   This example will first prompt for iDRAC username/password using Get-Credentials, then get account details for all iDRAC user account IDs 1 through 16.
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -idrac_user_id 2 -idrac_new_password test 
   This example shows changing root password. I pass in the current password of "calvin", pass in "2" for the user account ID and pass in the new password i want to change to which is "test".
.EXAMPLE
   Invoke-ChangeIdracUserPasswordREDFISH -idrac_ip 192.168.0.120 -idrac_user_id 2 
   This example shows changing root password using Get-Credential. It will first prompt for current iDRAC username and password for account ID 2. Then prompt to pass in the new password you want to set. 
#>

function Invoke-ChangeIdracUserPasswordREDFISH {


param(
    [Parameter(Mandatory=$True)]
    [string]$idrac_ip,
    [Parameter(Mandatory=$False)]
    [string]$idrac_username,
    [Parameter(Mandatory=$False)]
    [string]$idrac_password,
    [Parameter(Mandatory=$False)]
    [int]$idrac_user_id,
    [Parameter(Mandatory=$False)]
    [string]$idrac_new_password,
    [Parameter(Mandatory=$False)]
    [string]$get_idrac_user_account_ids

    )

# Function to ignore SSL certs

function Ignore-SSLCertificates
{
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

# Function to get Powershell version

$global:get_powershell_version

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

get_powershell_version

function setup_idrac_creds
{
if ($global:get_powershell_version -ge 7)
{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12,[Net.SecurityProtocolType]::TLS13
}
else
{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12
}



if ($idrac_username -and $idrac_password)
{
$user = $idrac_username
$pass= $idrac_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$global:credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
}
else
{
if ($get_idrac_user_account_ids -or $idrac_new_password)
{
$get_creds = Get-Credential -Message "Pass in current iDRAC username and password"
$get_creds_username = $get_creds.GetNetworkCredential().UserName
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)
}
else
{
$get_creds = Get-Credential -Message "Pass in current iDRAC username and password"
$global:get_creds_username = $get_creds.GetNetworkCredential().UserName
$global:credential = New-Object System.Management.Automation.PSCredential($get_creds.UserName, $get_creds.Password)

$get_new_creds = Get-Credential -UserName $get_creds_username -Message "Pass in new password for user $get_creds_username"
$global:new_credential = New-Object System.Management.Automation.PSCredential($get_new_creds.UserName, $get_new_creds.Password)
$global:get_new_user_password = $get_new_creds.Password
$get_string = (New-Object PSCredential "user",$get_new_creds.Password).GetNetworkCredential().Password
$global:JsonBody = '{{"Password" : "{0}"}}' -f $get_string
}
}
}

setup_idrac_creds


if ($get_idrac_user_account_ids)
{
Write-Host "`n- Account details for all iDRAC users -`n"
Start-Sleep 5

foreach ($id in 1..16)
{

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/$id"

  
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }


if ($result.StatusCode -eq 200)
{
#Pass
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned for GET command failure",$result.StatusCode)
    return
}
$get_result = $result.Content | ConvertFrom-Json
$get_result
}
}

if ($idrac_new_password -or $idrac_user_id)
{
if ($idrac_new_password)
{
$JsonBody = '{{"Password" : "{0}"}}' -f $idrac_new_password
}
else
{
#Pass
}


Write-Host "`n- INFO, executing PATCH command to change iDRAC user password"

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/$idrac_user_id"
 
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Patch -Body $JsonBody -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    return
    } 


if ($result1.StatusCode -eq 200)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully for PATCH command to change iDRAC user password",$result1.StatusCode)
    Start-Sleep 15
    
    
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    return
}

if ($idrac_new_password)
{
$user = $idrac_username
$pass= $idrac_new_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
}
else
{
$user = $get_creds_username
$pass= $get_new_user_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)

}



Write-Host "`n- INFO, executing GET command with new user password to validate password was changed"

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/$idrac_user_id"

if ($idrac_new_password)
{
    try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }

}
else
{
 try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $new_credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $new_credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    $RespErr
    return
    }
}


if ($result.StatusCode -eq 200)
{
    [String]::Format("`n- PASS, statuscode {0} returned successfully for GET command using new user password`n",$result.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned, password not changed",$result.StatusCode)
    return
}
}
}


