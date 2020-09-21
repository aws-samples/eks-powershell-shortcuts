<#
Installs Kubernetes Dashboard on AWS EKS cluster. Supports Fargate.

To run, execute following PowerShell commands:

curl -o $env:TMP/install-k8s-dashboard-on-EKS.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/install-k8s-dashboard-on-EKS.ps1
. $env:TMP/install-k8s-dashboard-on-EKS.ps1

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
    [Parameter(mandatory=$true)] [string] ${Enter latest metrics server version found at github.com/kubernetes-sigs/metrics-server/releases/},
    [Parameter(mandatory=$true)] [string] ${Enter latest Dashboard version found at github.com/kubernetes/dashboard/blob/master/README.md#install},
    [Parameter(mandatory=$true)] [object] ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install the Dashboard on Fargate. Hit Enter otherwise}
)

[string] $MetricsServerVersion = ${Enter latest metrics server version found at github.com/kubernetes-sigs/metrics-server/releases/}
[string] $DashboardVersion = ${Enter latest Dashboard version found at github.com/kubernetes/dashboard/blob/master/README.md#install}
[string] $IsFargate = ${Enter "fargate" if the cluster is Fargate-enabled and you would like to install the Dashboard on Fargate. Hit Enter otherwise}

if($IsFargate -and ($IsFargate.ToLowerInvariant() -ne "fargate")) {
    Write-Host "Parameter `"IsFargate`" has invalid value of `"$IsFargate`. It must be either `"fargate`" or blank."
    return
}

if(!$MetricsServerVersion.StartsWith("v")) {
    $MetricsServerVersion = "v" + $MetricsServerVersion
}
if(!$DashboardVersion.StartsWith("v")) {
    $DashboardVersion = "v" + $DashboardVersion
}

$context = (kubectl config view --minify -o json | ConvertFrom-Json).contexts.context.cluster.Split(".")

[string] $ClusterName = $context[0]
[string] $RegionName = $context[1]

Import-Module AWSPowerShell.NetCore

$eksCluster = $null
$eksCluster = Get-EKSCluster -Name $ClusterName -Region $RegionName

if(!$eksCluster) {
    Write-Host "Valid cluster name must be specified. Cluster `"$ClusterName`" was not found in the `"$RegionName`" region. Here is the list of existing clusters:`n$(Get-EKSClusterList -Region $RegionName)"
    return
}

# Deploy Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/$MetricsServerVersion/components.yaml
Write-Host "Waiting for Metrics Server Pods ready state..."
kubectl wait -n kube-system --for=condition=available --timeout=180s --all deployments

if($IsFargate) {
    # Create Fargate profile for “kubernetes-dashboard” namespace:
    eksctl create fargateprofile --cluster $ClusterName --region $RegionName --name kubernetes-dashboard-ns --namespace kubernetes-dashboard
}

# Deploy the Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/$DashboardVersion/aio/deploy/recommended.yaml
Write-Host "Waiting for Dashboard Pods ready state..."
kubectl wait -n kubernetes-dashboard --for=condition=available --timeout=300s --all deployments

# Create ServiceAccount and ClusterRoleBinding - credentials to login
kubectl apply -f https://gist.githubusercontent.com/vgribok/a798fd52d2dccace1c464cc7f01ecd15/raw/432c01c3e87469dfd676e45a59843b0c370126d4/yaml

# Open the dashboard
curl -o $env:TMP/open-K8s-dashbord-locally.ps1 https://raw.githubusercontent.com/vgribok/AWS-PowerShell-Shortcuts/master/src/open-K8s-dashbord-locally.ps1
. $env:TMP/open-K8s-dashbord-locally.ps1