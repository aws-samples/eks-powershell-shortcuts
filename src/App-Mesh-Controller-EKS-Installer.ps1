<#
To run, execute following PowerShell commands:

curl -o $env:TMP/App-Mesh-Controller-EKS-Installer.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/App-Mesh-Controller-EKS-Installer.ps1
. $env:TMP/App-Mesh-Controller-EKS-Installer.ps1

Adds AWS App Mesh CRDs to an existing EKS Kubernetes cluster and installs App Mesh Controller.
This single script Combines multiple steps from https://docs.aws.amazon.com/app-mesh/latest/userguide/mesh-k8s-integration.html

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
    [Parameter(mandatory=$true)] [string] ${Enter EKS Cluster Name},
    [Parameter()] [string] $RegionName,
    [Parameter(mandatory=$true)] [object] ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install App Mesh Controller on EKS Fargate nodes. Hit Enter otherwise},
    [Parameter()] [string] $Tracing = "x-ray" # turns on AWS X-Ray tracing for the Mesh
)
if(!$RegionName) {
    $RegionName = (aws configure get region)
}
[string] $ClusterName = ${Enter EKS Cluster Name}

[string] $IsFargate = ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install App Mesh Controller on EKS Fargate nodes. Hit Enter otherwise}

if($IsFargate -and ($IsFargate.ToLowerInvariant() -ne "fargate")) {
    Write-Host "Parameter `"IsFargate`" has invalid value of `"$IsFargate`. It must be either `"fargate`" or blank."
    return
}

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster -Name $ClusterName -Region $RegionName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found in the `"$RegionName`" region. Here is the list of existing clusters:`n$(Get-EKSClusterList -Region $RegionName)"
    return
}

# Set current kubectl context
aws eks --region $RegionName update-kubeconfig --name $ClusterName --alias $RegionName/$ClusterName

# Install the App Mesh Kubernetes custom resource definitions (CRD).
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"

# Create a Kubernetes namespace for the controller.
$appMeshNamespace = "appmesh-system"
kubectl create ns $appMeshNamespace

if($IsFargate) {
    # On Fargate to create a Fargate profile for the namespace
    eksctl create fargateprofile --cluster $ClusterName --region $RegionName --name "$appMeshNamespace-ns" --namespace $appMeshNamespace
}

# Create an OpenID Connect (OIDC) identity provider for the cluster
eksctl utils associate-iam-oidc-provider `
    --region=$RegionName `
    --cluster $ClusterName `
    --approve

# Create an IAM role, attach the AWSAppMeshFullAccess and AWSCloudMapFullAccess AWS managed policies to it, 
# and bind it to the appmesh-controller Kubernetes service account.

$svcAccountName = "appmesh-controller"

eksctl create iamserviceaccount `
    --cluster $ClusterName `
    --region $RegionName `
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
        --set region=$RegionName `
        --set serviceAccount.create=false `
        --set serviceAccount.name=$svcAccountName `
        --set tracing.enabled=true `
        --set tracing.provider=x-ray
}else {
    helm upgrade -i appmesh-controller eks/appmesh-controller `
        --namespace $appMeshNamespace `
        --set region=$RegionName `
        --set serviceAccount.create=false `
        --set serviceAccount.name=$svcAccountName
}