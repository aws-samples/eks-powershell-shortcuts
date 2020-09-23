<#
To run, execute following PowerShell commands:

curl -o $env:TMP/SvcAccount-for-envoy-on-eks-fargate.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/SvcAccount-for-envoy-on-eks-fargate.ps1
. $env:TMP/SvcAccount-for-envoy-on-eks-fargate.ps1

Creates Kubernetes ServiceAccount tied to IAM permissions required to run
Envoy pod on EKS Fargate nodes. 

This ServiceAccount needs to be used for Pods running in App Mesh on EKS Fargate nodes, 
which also includes Ingress Gateway Envoy contaiers and not only Envoy sidecar 
containers injected by App Mesh.

Also, the ServiceAccount is scoped to a K8s namespace and therefore needs to be created 
for each K8s namespace that is part of both App Mesh and an EKS Fargate Profile.

Pre-requisites:
- An AWS Account
- aws CLI
- PowerShell 7 for running same commands on Linux, MacOS and Windows.
- AWS Tools for PowerShell 
- kubectl CLI
- eksctl CLI
#>

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)] [string] ${Enter EKS Cluster Name},
    [Parameter()] [string] $RegionName,
    [Parameter(mandatory=$true)] [string] ${Please enter Fargate namespace for the ServiceAccount},
    [Parameter()] [string] $fargatePodAccountName="envoy-fargate-pod-svcaccount"
)

if(!$RegionName) {
    $RegionName = (aws configure get region)
}
[string] $ClusterName = ${Enter EKS Cluster Name}
[string] $NamespaceName = ${Please enter Fargate namespace for the ServiceAccount}

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster -Name $ClusterName -Region $RegionName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found in the `"$RegionName`" region. Here is the list of existing clusters:`n$(Get-EKSClusterList -Region $RegionName)"
    return
}

# Install IAM-Kubernetes OpenID integration
eksctl utils associate-iam-oidc-provider --region $RegionName --cluster $ClusterName --approve

eksctl create iamserviceaccount `
 --cluster $ClusterName `
 --region $RegionName `
 --namespace $NamespaceName `
 --name $fargatePodAccountName `
 --attach-policy-arn `
 arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess,arn:aws:iam::aws:policy/AWSCloudMapDiscoverInstanceAccess,arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess,arn:aws:iam::aws:policy/CloudWatchLogsFullAccess,arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess `
 --override-existing-serviceaccounts `
 --approve
