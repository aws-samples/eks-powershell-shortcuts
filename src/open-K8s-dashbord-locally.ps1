<#
To run, execute following PowerShell commands:

curl -o $env:TMP/open-K8s-dashbord-locally.ps1 https://raw.githubusercontent.com/aws-samples/eks-powershell-shortcuts/main/src/open-K8s-dashbord-locally.ps1
. $env:TMP/open-K8s-dashbord-locally.ps1

Opens K8s Dashboard installed on EKS with `kubectl proxy`, 
and copies authentication token to the clipboard for the ease of login.
Assumes current kubectl context is pointing to where the dashboard is installed.

Pre-requisites:
- kubectl CLI
#>

start kubectl proxy

[string] $SecretName = kubectl -n kube-system get secret -o custom-columns=":metadata.name" | Select-String -pattern eks-admin-token
[string] $kdtoken = kubectl -n kube-system get secret $SecretName -o=jsonpath='{.data.token}'
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($kdtoken)) | Set-Clipboard

start http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Write-Host "Authentication token is copied to the clipboard.`nPlease *paste* it into the `"Enter Token`" textbox when prompted to login."
