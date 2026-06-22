param(
  [Parameter(Mandatory = $true)]
  [string]$KeyName,

  [string]$Region = $(aws configure get region),
  [string]$VpcId = "",
  [string]$SubnetId = "",
  [string]$AllowedCidr = "",
  [string]$AppInstanceType = "t3.small",
  [string]$ObservabilityInstanceType = "t3.medium",
  [switch]$CreateKeyPair,
  [string]$KeyPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

if ([string]::IsNullOrWhiteSpace($AllowedCidr)) {
  $publicIp = (Invoke-RestMethod "https://checkip.amazonaws.com").Trim()
  $AllowedCidr = "$publicIp/32"
}

if ([string]::IsNullOrWhiteSpace($VpcId)) {
  $VpcId = aws ec2 describe-vpcs `
    --region $Region `
    --filters "Name=isDefault,Values=true" `
    --query "Vpcs[0].VpcId" `
    --output text
}

if ([string]::IsNullOrWhiteSpace($SubnetId)) {
  $appAzs = @(aws ec2 describe-instance-type-offerings `
    --region $Region `
    --location-type availability-zone `
    --filters "Name=instance-type,Values=$AppInstanceType" `
    --query "InstanceTypeOfferings[].Location" `
    --output text) -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  $observabilityAzs = @(aws ec2 describe-instance-type-offerings `
    --region $Region `
    --location-type availability-zone `
    --filters "Name=instance-type,Values=$ObservabilityInstanceType" `
    --query "InstanceTypeOfferings[].Location" `
    --output text) -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  $supportedAzs = $appAzs | Where-Object { $observabilityAzs -contains $_ }
  if (-not $supportedAzs -or $supportedAzs.Count -eq 0) {
    throw "No common Availability Zone supports $AppInstanceType and $ObservabilityInstanceType in $Region."
  }

  $subnets = aws ec2 describe-subnets `
    --region $Region `
    --filters "Name=vpc-id,Values=$VpcId" "Name=default-for-az,Values=true" `
    --query "Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}" `
    --output json | ConvertFrom-Json

  $subnet = $subnets |
    Where-Object { $supportedAzs -contains $_.AvailabilityZone -and $_.MapPublicIpOnLaunch } |
    Select-Object -First 1

  if ($null -eq $subnet) {
    throw "No default public subnet found in an Availability Zone that supports both instance types."
  }

  $SubnetId = $subnet.SubnetId
}

if ($CreateKeyPair) {
  if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    $sshDir = Join-Path $HOME ".ssh"
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    $KeyPath = Join-Path $sshDir "$KeyName.pem"
  }

  Write-Host "Creating key pair $KeyName at $KeyPath"
  $keyMaterial = aws ec2 create-key-pair `
    --region $Region `
    --key-name $KeyName `
    --query "KeyMaterial" `
    --output text

  $keyMaterial = ($keyMaterial -join "`n").Trim()
  if ($keyMaterial -notmatch "`n") {
    $compact = $keyMaterial -replace "\s", ""
    $header = "-----BEGINRSAPRIVATEKEY-----"
    $footer = "-----ENDRSAPRIVATEKEY-----"
    if ($compact.StartsWith($header) -and $compact.EndsWith($footer)) {
      $base64 = $compact.Substring($header.Length, $compact.Length - $header.Length - $footer.Length)
      $lines = New-Object System.Collections.Generic.List[string]
      $lines.Add("-----BEGIN RSA PRIVATE KEY-----")
      for ($i = 0; $i -lt $base64.Length; $i += 64) {
        $len = [Math]::Min(64, $base64.Length - $i)
        $lines.Add($base64.Substring($i, $len))
      }
      $lines.Add("-----END RSA PRIVATE KEY-----")
      $keyMaterial = $lines -join "`n"
    }
  }

  [System.IO.File]::WriteAllText($KeyPath, $keyMaterial + "`n", [System.Text.ASCIIEncoding]::new())
  icacls $KeyPath /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null
}

$AmiId = aws ec2 describe-images `
  --region $Region `
  --owners 099720109477 `
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" `
  --query "sort_by(Images,&CreationDate)[-1].ImageId" `
  --output text

function Get-OrCreateSecurityGroup {
  param(
    [string]$Name,
    [string]$Description
  )

  $existing = aws ec2 describe-security-groups `
    --region $Region `
    --filters "Name=vpc-id,Values=$VpcId" "Name=group-name,Values=$Name" `
    --query "SecurityGroups[0].GroupId" `
    --output text

  if ($existing -and $existing -ne "None") {
    return $existing
  }

  aws ec2 create-security-group `
    --region $Region `
    --vpc-id $VpcId `
    --group-name $Name `
    --description $Description `
    --query "GroupId" `
    --output text
}

function Add-Rule {
  param(
    [string]$GroupId,
    [int]$Port,
    [string]$CidrIp = "",
    [string]$SourceGroupId = ""
  )

  try {
    if ($SourceGroupId) {
      aws ec2 authorize-security-group-ingress `
        --region $Region `
        --group-id $GroupId `
        --ip-permissions "IpProtocol=tcp,FromPort=$Port,ToPort=$Port,UserIdGroupPairs=[{GroupId=$SourceGroupId}]" | Out-Null
    } else {
      aws ec2 authorize-security-group-ingress `
        --region $Region `
        --group-id $GroupId `
        --protocol tcp `
        --port $Port `
        --cidr $CidrIp | Out-Null
    }
  } catch {
    if ($_.Exception.Message -notmatch "InvalidPermission.Duplicate") {
      throw
    }
  }
}

$AppSg = Get-OrCreateSecurityGroup -Name "apollo-monitoring-app-sg" -Description "Apollo monitoring app access"
$ObsSg = Get-OrCreateSecurityGroup -Name "apollo-monitoring-observability-sg" -Description "Apollo monitoring observability access"

aws ec2 create-tags `
  --region $Region `
  --resources $AppSg $ObsSg `
  --tags Key=Lab,Value=apollo-monitoring | Out-Null

Add-Rule -GroupId $AppSg -Port 22 -CidrIp $AllowedCidr
Add-Rule -GroupId $AppSg -Port 80 -CidrIp $AllowedCidr
Add-Rule -GroupId $ObsSg -Port 22 -CidrIp $AllowedCidr
Add-Rule -GroupId $ObsSg -Port 5601 -CidrIp $AllowedCidr
Add-Rule -GroupId $ObsSg -Port 5601 -SourceGroupId $AppSg
Add-Rule -GroupId $ObsSg -Port 5044 -SourceGroupId $AppSg
Add-Rule -GroupId $ObsSg -Port 8200 -SourceGroupId $AppSg
Add-Rule -GroupId $ObsSg -Port 9200 -SourceGroupId $AppSg

$UserData = @"
#!/bin/bash
set -eux
apt-get update
apt-get install -y unzip curl ca-certificates
"@
$UserDataPath = Join-Path $env:TEMP "apollo-monitoring-user-data.sh"
Set-Content -LiteralPath $UserDataPath -Value $UserData -NoNewline

function New-LabInstance {
  param(
    [string]$Name,
    [string]$InstanceType,
    [string]$SecurityGroupId,
    [int]$VolumeSize
  )

  aws ec2 run-instances `
    --region $Region `
    --image-id $AmiId `
    --instance-type $InstanceType `
    --count 1 `
    --key-name $KeyName `
    --subnet-id $SubnetId `
    --security-group-ids $SecurityGroupId `
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VolumeSize,VolumeType=gp3,DeleteOnTermination=true}" `
    --user-data file://$UserDataPath `
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$Name},{Key=Lab,Value=apollo-monitoring}]" "ResourceType=volume,Tags=[{Key=Name,Value=$Name-root},{Key=Lab,Value=apollo-monitoring}]" `
    --query "Instances[0].InstanceId" `
    --output text
}

$AppInstanceId = New-LabInstance -Name "apollo-monitoring-app" -InstanceType $AppInstanceType -SecurityGroupId $AppSg -VolumeSize 20
$ObsInstanceId = New-LabInstance -Name "apollo-monitoring-observability" -InstanceType $ObservabilityInstanceType -SecurityGroupId $ObsSg -VolumeSize 40

aws ec2 wait instance-running --region $Region --instance-ids $AppInstanceId $ObsInstanceId

$instances = aws ec2 describe-instances `
  --region $Region `
  --instance-ids $AppInstanceId $ObsInstanceId `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress}" `
  --output json | ConvertFrom-Json

$instances | Format-Table -AutoSize

Write-Host ""
Write-Host "Next: run scripts\aws\deploy-to-ec2.ps1 with these IPs."
if ($CreateKeyPair) {
  Write-Host "Key saved at: $KeyPath"
}
