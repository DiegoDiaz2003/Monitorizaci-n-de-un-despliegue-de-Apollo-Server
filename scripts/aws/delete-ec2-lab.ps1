param(
  [string]$Region = $(aws configure get region),
  [switch]$DeleteSecurityGroups
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

$instanceIds = aws ec2 describe-instances `
  --region $Region `
  --filters "Name=tag:Lab,Values=apollo-monitoring" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
  --query "Reservations[].Instances[].InstanceId" `
  --output text

if ($instanceIds) {
  aws ec2 terminate-instances --region $Region --instance-ids $instanceIds | Out-Null
  aws ec2 wait instance-terminated --region $Region --instance-ids $instanceIds
}

if ($DeleteSecurityGroups) {
  $groupIds = aws ec2 describe-security-groups `
    --region $Region `
    --filters "Name=group-name,Values=apollo-monitoring-observability-sg,apollo-monitoring-app-sg" `
    --query "SecurityGroups[].GroupId" `
    --output text

  if ($groupIds) {
    foreach ($groupId in ($groupIds -split "\s+")) {
      if ([string]::IsNullOrWhiteSpace($groupId)) {
        continue
      }

      try {
        aws ec2 delete-security-group --region $Region --group-id $groupId | Out-Null
        Write-Host "Deleted security group $groupId"
      } catch {
        Write-Host "Could not delete security group ${groupId}: $($_.Exception.Message)"
      }
    }
  }
} else {
  Write-Host "EC2 lab instances terminated. Security groups were left in place."
  Write-Host "To delete lab security groups too, rerun with -DeleteSecurityGroups."
}
