<#
To run, execute following PowerShell commands: 

curl -o $env:TMP/ALB-ingress-controller-installer.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/ALB-ingress-controller-installer.ps1
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
#>

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)] [string] ${Enter EKS Cluster Name},
    [Parameter()] [string] $RegionName,
    [Parameter(mandatory=$true)] [string] ${Enter latest version from github.com/kubernetes-sigs/aws-alb-ingress-controller/releases}
)

if(!$RegionName) {
    $RegionName = (aws configure get region)
}
[string] $ClusterName = ${Enter EKS Cluster Name}

[string] $AlbIngressControllerVersion = ${Enter latest version from github.com/kubernetes-sigs/aws-alb-ingress-controller/releases}

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster -Name $ClusterName -Region $RegionName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found in the `"$RegionName`" region. Here is the list of existing clusters:`n$(Get-EKSClusterList -Region $RegionName)"
    return
}

# Set current kubectl context
aws eks --region $RegionName update-kubeconfig --name $ClusterName --alias $RegionName/$ClusterName

if(!$AlbIngressControllerVersion.StartsWith("v")) {
    $AlbIngressControllerVersion = "v"+$AlbIngressControllerVersion
}
Write-Host "Will be using ingress controller $AlbIngressControllerVersion"

# Create temporary directory for text files
Push-Location
mkdir $env:TMP/alb-ingress-controller-temp-files -Force | cd

try {
    $ALB_INGRESS_CONT_VER = $AlbIngressControllerVersion

    # Create ALBIngressControllerIAMPolicy IAM Policy
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/$ALB_INGRESS_CONT_VER/docs/examples/iam-policy.json
    aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://iam-policy.json

    # Install IAM-Kubernetes OpenID integration
    eksctl utils associate-iam-oidc-provider --region $RegionName --cluster $ClusterName --approve

    # Create K8s RBAC Role for ALB Ingress Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/$ALB_INGRESS_CONT_VER/docs/examples/rbac-role.yaml

    # Create K8s Service Account for the ingress controller
    [string] $AlbPolicyArn = ((aws iam list-policies --output json | ConvertFrom-Json).Policies `
                                | where { $_.PolicyName -eq "ALBIngressControllerIAMPolicy" }).Arn
    Write-Host "Policy ARN: $AlbPolicyArn"

    eksctl create iamserviceaccount `
        --region $RegionName `
        --name alb-ingress-controller `
        --namespace kube-system `
        --cluster $ClusterName `
        --attach-policy-arn $AlbPolicyArn `
        --override-existing-serviceaccounts `
        --approve

    # Download ALB Ingress Controller K8s Manifest
    curl -o alb-ingress-controller.yaml https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/$ALB_INGRESS_CONT_VER/docs/examples/alb-ingress-controller.yaml
    # Update ALB Ingress Controller K8s Manifest file “alb-ingress-controller.yaml”
    (cat alb-ingress-controller.yaml) `
        -replace "# - --cluster-name=devCluster", "- --cluster-name=$ClusterName" `
        -replace "# - --aws-vpc-id=vpc-xxxxxx", "- --aws-vpc-id=$($eksCluster.ResourcesVpcConfig.VpcId)" `
        -replace "# - --aws-region=us-west-1", "- --aws-region=$RegionName" `
        | Out-File alb-ingress-controller.yaml

    # Install ALB Ingress Controller
    kubectl apply -f .\alb-ingress-controller.yaml

    # Output pending Pods
    kubectl get pods -n kube-system
}
finally {
    Pop-Location
}