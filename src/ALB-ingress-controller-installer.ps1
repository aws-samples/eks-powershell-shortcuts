<#
To run, execute following PowerShell commands: 

curl -o $env:TMP/ALB-ingress-controller-installer.ps1 https://raw.githubusercontent.com/aws-samples/eks-powershell-shortcuts/main/src/ALB-ingress-controller-installer.ps1
. $env:TMP/ALB-ingress-controller-installer.ps1

Installs AWS ALB Ingress controller on an existing EKS Kubernetes cluster. 
This single script Combines multiple steps from https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html.

Pre-requisites:
- An AWS Account
- PowerShell 7 for running same commands on Linux, MacOS and Windows.
- aws CLI
- AWS Tools for PowerShell 
- kubectl CLI
- eksctl CLI
- helm
#>

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)] [string] ${Enter EKS Cluster Name},
    [Parameter()] [string] $RegionName
)

if(!$RegionName) {
    $RegionName = (aws configure get region)
}
[string] $ClusterName = ${Enter EKS Cluster Name}

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster -Name $ClusterName -Region $RegionName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found in the `"$RegionName`" region. Here is the list of existing clusters:`n$(Get-EKSClusterList -Region $RegionName)"
    return
}

# Set current kubectl context
aws eks --region $RegionName update-kubeconfig --name $ClusterName --alias $RegionName/$ClusterName

# Install IAM-Kubernetes OpenID integration
eksctl utils associate-iam-oidc-provider --region $RegionName --cluster $ClusterName --approve

helm upgrade -i -n kube-system aws-load-balancer-controller eks/aws-load-balancer-controller `
    --set clusterName=$CLUSTER `
    --set vpcId=$($eksCluster.ResourcesVpcConfig.VpcId) `
    --set region=$RegionName

# Output pending Pods
kubectl get pods -n kube-system
