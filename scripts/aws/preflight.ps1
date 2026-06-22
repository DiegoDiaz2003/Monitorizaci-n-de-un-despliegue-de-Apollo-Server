param(
  [string]$Region = $(aws configure get region),
  [string]$KeyName = "apollo-lab-key"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

function Write-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail
  )

  $status = if ($Ok) { "OK" } else { "WARN" }
  Write-Host "[$status] $Name - $Detail"
}

function Test-AwsDryRun {
  param(
    [string[]]$Arguments
  )

  $stdout = Join-Path $env:TEMP "apollo-preflight-stdout-$([guid]::NewGuid()).txt"
  $stderr = Join-Path $env:TEMP "apollo-preflight-stderr-$([guid]::NewGuid()).txt"

  try {
    $process = Start-Process `
      -FilePath "aws" `
      -ArgumentList $Arguments `
      -NoNewWindow `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdout `
      -RedirectStandardError $stderr

    $output = ((Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) + "`n" +
      (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue))

    if ($output -match "DryRunOperation") {
      return $true
    }

    $clean = ($output -replace "\s+", " ").Trim()
    if ($clean) {
      Write-Host "Dry-run failed: $clean"
    }
    return $false
  } finally {
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Apollo Monitoring Lab preflight"
Write-Host "Region: $Region"
Write-Host ""

$identity = aws sts get-caller-identity | ConvertFrom-Json
Write-Check "AWS identity" $true "$($identity.Arn)"

$vpcId = aws ec2 describe-vpcs `
  --region $Region `
  --filters "Name=isDefault,Values=true" `
  --query "Vpcs[0].VpcId" `
  --output text

Write-Check "Default VPC" ($vpcId -and $vpcId -ne "None") "$vpcId"

$subnetId = aws ec2 describe-subnets `
  --region $Region `
  --filters "Name=vpc-id,Values=$vpcId" "Name=default-for-az,Values=true" `
  --query "Subnets[0].SubnetId" `
  --output text

Write-Check "Default subnet" ($subnetId -and $subnetId -ne "None") "$subnetId"

$amiId = aws ec2 describe-images `
  --region $Region `
  --owners 099720109477 `
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" `
  --query "sort_by(Images,&CreationDate)[-1].ImageId" `
  --output text

Write-Check "Ubuntu 22.04 AMI lookup" ($amiId -and $amiId -ne "None") "$amiId"

$keyPairs = aws ec2 describe-key-pairs `
  --region $Region `
  --query "KeyPairs[].KeyName" `
  --output text

if ($keyPairs) {
  Write-Check "EC2 key pairs" $true $keyPairs
} else {
  Write-Check "EC2 key pairs" $false "No key pairs found in $Region. Use -CreateKeyPair with create-ec2-lab.ps1."
}

$createKeyAllowed = Test-AwsDryRun @("ec2", "create-key-pair", "--region", $Region, "--key-name", "${KeyName}-dryrun", "--dry-run")
Write-Check "Permission ec2:CreateKeyPair" $createKeyAllowed "dry-run"

$runInstancesAllowed = Test-AwsDryRun @(
  "ec2", "run-instances",
  "--region", $Region,
  "--image-id", $amiId,
  "--instance-type", "t3.micro",
  "--key-name", $KeyName,
  "--subnet-id", $subnetId,
  "--count", "1",
  "--dry-run"
)
Write-Check "Permission ec2:RunInstances" $runInstancesAllowed "dry-run. If WARN and the key pair does not exist yet, create the key first and rerun."

Write-Host ""
Write-Host "Recommended next command:"
if ($keyPairs -match "(^|\s)$KeyName(\s|$)") {
  Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName `"$KeyName`""
} else {
  Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName `"$KeyName`" -CreateKeyPair"
}
