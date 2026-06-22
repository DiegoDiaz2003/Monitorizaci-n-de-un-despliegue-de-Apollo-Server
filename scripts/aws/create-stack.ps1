param(
  [Parameter(Mandatory = $true)]
  [string]$KeyName,

  [string]$StackName = "apollo-monitoring-lab",
  [string]$Region = $(aws configure get region),
  [string]$VpcId = "",
  [string]$SubnetId = "",
  [string]$AllowedCidr = "",
  [string]$AppInstanceType = "t3.small",
  [string]$ObservabilityInstanceType = "t3.medium",
  [string]$UbuntuAmi = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

if ([string]::IsNullOrWhiteSpace($VpcId)) {
  $VpcId = aws ec2 describe-vpcs `
    --region $Region `
    --filters "Name=isDefault,Values=true" `
    --query "Vpcs[0].VpcId" `
    --output text
}

if ([string]::IsNullOrWhiteSpace($SubnetId)) {
  $SubnetId = aws ec2 describe-subnets `
    --region $Region `
    --filters "Name=vpc-id,Values=$VpcId" "Name=default-for-az,Values=true" `
    --query "Subnets[0].SubnetId" `
    --output text
}

if ([string]::IsNullOrWhiteSpace($AllowedCidr)) {
  $publicIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()
  $AllowedCidr = "$publicIp/32"
}

if ([string]::IsNullOrWhiteSpace($UbuntuAmi)) {
  $UbuntuAmi = aws ec2 describe-images `
    --region $Region `
    --owners 099720109477 `
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" `
    --query "sort_by(Images,&CreationDate)[-1].ImageId" `
    --output text
}

Write-Host "Region: $Region"
Write-Host "VPC: $VpcId"
Write-Host "Subnet: $SubnetId"
Write-Host "AllowedCidr: $AllowedCidr"
Write-Host "UbuntuAmi: $UbuntuAmi"

aws cloudformation deploy `
  --region $Region `
  --stack-name $StackName `
  --template-file "infra/aws/cloudformation-two-ec2.yaml" `
  --parameter-overrides `
    KeyName=$KeyName `
    VpcId=$VpcId `
    SubnetId=$SubnetId `
    AllowedCidr=$AllowedCidr `
    AppInstanceType=$AppInstanceType `
    ObservabilityInstanceType=$ObservabilityInstanceType `
    UbuntuAmi=$UbuntuAmi

aws cloudformation describe-stacks `
  --region $Region `
  --stack-name $StackName `
  --query "Stacks[0].Outputs" `
  --output table
