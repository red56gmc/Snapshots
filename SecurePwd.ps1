$credentials = Get-Credential
$credentials.Password | ConvertFrom-SecureString | Set-Content C:\Scripts\VMware\Credential.txt
