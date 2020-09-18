<#
Adds AWS App Mesh CRDs to an EKS Kubernetes cluster
and installs App Mesh Controller.

To run, execute following PowerShell commands:

curl -o $env:TMP/App-Mesh-Controller-EKS-Installer.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/App-Mesh-Controller-EKS-Installer.ps1
. $env:TMP/App-Mesh-Controller-EKS-Installer.ps1

Pre-requisites:
- An AWS Account
- PowerShell 7 for running same commands on Linux, MacOS and Windows.
- aws CLI
- AWS Tools for PowerShell 
- kubectl CLI
- helm CLI v3 
- eksctl CLI
#>

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)] [string] ${Enter existing cluster name, one of returned by Get-EKSClusterList command},
    [Parameter(mandatory=$true)] [string] ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install the Dashboard on Fargate. Hit Enter otherwise},
    [Parameter] [string] $Tracing = "x-ray"
)

[string] $ClusterName = ${Enter existing cluster name, one of returned by Get-EKSClusterList command}
[string] $IsFargate = ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install the Dashboard on Fargate. Hit Enter otherwise}

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster $ClusterName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found. Here is the list of existing clusters:`n$(Get-EKSClusterList)"
    return
}

#$eksCluster

# Switch kubectl profile to the cluster
$region = $eksCluster.Arn.Split(":")[3]
aws eks --region $region update-kubeconfig --name $ClusterName --alias $region/$ClusterName

# Install the App Mesh Kubernetes custom resource definitions (CRD).
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"

# Create a Kubernetes namespace for the controller.
$appMeshNamespace = "appmesh-system"
kubectl create ns $appMeshNamespace

if($IsFargate.ToLowerInvariant() -eq "fargate") {
    # On Fargate to create a Fargate profile for the namespace
    eksctl create fargateprofile --cluster $ClusterName --name "$appMeshNamespace-ns" --namespace $appMeshNamespace
}

# Create an OpenID Connect (OIDC) identity provider for the cluster
eksctl utils associate-iam-oidc-provider `
    --region=$region `
    --cluster $ClusterName `
    --approve

# Create an IAM role, attach the AWSAppMeshFullAccess and AWSCloudMapFullAccess AWS managed policies to it, 
# and bind it to the appmesh-controller Kubernetes service account.

$svcAccountName = "appmesh-controller"

eksctl create iamserviceaccount `
    --cluster $ClusterName `
    --namespace $appMeshNamespace `
    --name $svcAccountName `
    --attach-policy-arn arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess `
    --override-existing-serviceaccounts `
    --approve

# Add the eks-charts repository to Helm.
helm repo add eks https://aws.github.io/eks-charts

# Deploy the App Mesh controller. 
if($Tracing -eq "x-ray") {
    helm upgrade -i appmesh-controller eks/appmesh-controller `
        --namespace $appMeshNamespace `
        --set region=$region `
        --set serviceAccount.create=false `
        --set serviceAccount.name=$svcAccountName `
        --set tracing.enabled=true `
        --set tracing.provider=x-ray
}else {
    helm upgrade -i appmesh-controller eks/appmesh-controller `
        --namespace $appMeshNamespace `
        --set region=$region `
        --set serviceAccount.create=false `
        --set serviceAccount.name=$svcAccountName
}