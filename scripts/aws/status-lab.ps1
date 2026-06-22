param(
  [string]$Region = $(aws configure get region),
  [string]$KeyName = "apollo-lab-key"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

Write-Host "Apollo Monitoring Lab status"
Write-Host "Region: $Region"
Write-Host ""

Write-Host "AWS identity"
aws sts get-caller-identity --output table
Write-Host ""

Write-Host "EC2 instances tagged Lab=apollo-monitoring"
aws ec2 describe-instances `
  --region $Region `
  --filters "Name=tag:Lab,Values=apollo-monitoring" `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,LaunchTime:LaunchTime}" `
  --output table
Write-Host ""

Write-Host "EBS volumes tagged Lab=apollo-monitoring"
aws ec2 describe-volumes `
  --region $Region `
  --filters "Name=tag:Lab,Values=apollo-monitoring" `
  --query "Volumes[].{Name:Tags[?Key=='Name']|[0].Value,VolumeId:VolumeId,State:State,SizeGiB:Size,AttachedTo:Attachments[0].InstanceId}" `
  --output table
Write-Host ""

Write-Host "Security groups"
aws ec2 describe-security-groups `
  --region $Region `
  --filters "Name=group-name,Values=apollo-monitoring-app-sg,apollo-monitoring-observability-sg" `
  --query "SecurityGroups[].{GroupName:GroupName,GroupId:GroupId,VpcId:VpcId,Description:Description}" `
  --output table
Write-Host ""

Write-Host "Key pair"
$keyPairsJson = aws ec2 describe-key-pairs `
  --region $Region `
  --query "KeyPairs[?KeyName=='$KeyName'].{KeyName:KeyName,KeyPairId:KeyPairId}" `
  --output json

$keyPairs = $keyPairsJson | ConvertFrom-Json
if ($keyPairs.Count -gt 0) {
  $keyPairs | Format-Table -AutoSize
} else {
  Write-Host "Key pair '$KeyName' was not found in $Region."
}
