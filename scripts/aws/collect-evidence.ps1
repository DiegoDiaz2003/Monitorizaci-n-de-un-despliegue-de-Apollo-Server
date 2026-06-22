param(
  [Parameter(Mandatory = $true)]
  [string]$SshKeyPath,

  [Parameter(Mandatory = $true)]
  [string]$AppPublicIp,

  [Parameter(Mandatory = $true)]
  [string]$ObservabilityPublicIp,

  [Parameter(Mandatory = $true)]
  [string]$ObservabilityPrivateIp,

  [string]$Region = $(aws configure get region),
  [string]$Ec2User = "ubuntu",
  [string]$OutputDir = "evidence"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = "us-east-1"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$evidenceRoot = Join-Path (Resolve-Path ".").Path $OutputDir
$runDir = Join-Path $evidenceRoot $timestamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Save-Text {
  param(
    [string]$Name,
    [string]$Content
  )

  $path = Join-Path $runDir $Name
  $parent = Split-Path -Parent $path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
  Write-Host "Saved $path"
}

function Run-Local {
  param(
    [string]$Name,
    [string]$Command
  )

  $content = "COMMAND`r`n$Command`r`n`r`nOUTPUT`r`n"
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $content += (powershell -NoProfile -ExecutionPolicy Bypass -Command $Command 2>&1 | Out-String)
  } catch {
    $content += ($_ | Out-String)
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  Save-Text $Name $content
}

function Run-Ssh {
  param(
    [string]$Name,
    [string]$HostIp,
    [string]$RemoteCommand
  )

  $sshTarget = "${Ec2User}@${HostIp}"
  $content = "HOST`r`n$sshTarget`r`n`r`nCOMMAND`r`n$RemoteCommand`r`n`r`nOUTPUT`r`n"
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $content += (ssh -o StrictHostKeyChecking=accept-new -i $SshKeyPath $sshTarget $RemoteCommand 2>&1 | Out-String)
  } catch {
    $content += ($_ | Out-String)
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  Save-Text $Name $content
}

$healthPayload = '{"operationName":"Health","query":"query Health { health }"}'
$booksPayload = '{"operationName":"GetBooks","query":"query GetBooks { books { title author } }"}'
$healthPayloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($healthPayload))
$booksPayloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($booksPayload))

Save-Text "00-summary.txt" @"
Apollo Monitoring Lab evidence
Timestamp: $timestamp
Region: $Region
Apollo public IP: $AppPublicIp
Observability public IP: $ObservabilityPublicIp
Observability private IP: $ObservabilityPrivateIp
Kibana URL: http://${ObservabilityPublicIp}:5601
Apollo URL: http://${AppPublicIp}/
"@

Run-Local "01-aws-identity.txt" "aws sts get-caller-identity"
Run-Local "02-ec2-instances.txt" "aws ec2 describe-instances --region $Region --filters 'Name=tag:Lab,Values=apollo-monitoring' --query 'Reservations[].Instances[].{Name:Tags[?Key==``Name``]|[0].Value,InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,LaunchTime:LaunchTime}' --output table"
Run-Local "03-security-groups.txt" "aws ec2 describe-security-groups --region $Region --filters 'Name=group-name,Values=apollo-monitoring-app-sg,apollo-monitoring-observability-sg' --query 'SecurityGroups[].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' --output json"

Run-Ssh "10-observability-docker-ps.txt" $ObservabilityPublicIp "cd /opt/apollo-monitoring-lab && sudo docker compose -f docker-compose.elastic.yml ps"
Run-Ssh "11-observability-health.txt" $ObservabilityPublicIp "curl -fsS http://localhost:9200/_cluster/health?pretty && printf '\n--- Kibana ---\n' && curl -fsS http://localhost:5601/api/status | head -c 1000 && printf '\n--- APM ---\n' && curl -fsS http://localhost:8200/ && printf '\n--- Logstash ---\n' && curl -fsS http://localhost:9600/"
Run-Ssh "12-elastic-indices.txt" $ObservabilityPublicIp "curl -fsS 'http://localhost:9200/_cat/indices?v'"
Run-Ssh "13-observability-logs-tail.txt" $ObservabilityPublicIp "docker logs elasticsearch --tail 60 2>&1; printf '\n--- kibana ---\n'; docker logs kibana --tail 60 2>&1; printf '\n--- apm ---\n'; docker logs apm-server --tail 60 2>&1; printf '\n--- logstash ---\n'; docker logs logstash --tail 60 2>&1"

Run-Ssh "20-apollo-docker-ps.txt" $AppPublicIp "cd /opt/apollo-monitoring-lab && sudo docker compose -f docker-compose.apollo.yml ps"
Run-Ssh "21-apollo-health-query.txt" $AppPublicIp "echo $healthPayloadB64 | base64 -d > /tmp/health.json && curl -fsS -X POST http://localhost/ -H content-type:application/json --data @/tmp/health.json"
Run-Ssh "22-apollo-books-query.txt" $AppPublicIp "echo $booksPayloadB64 | base64 -d > /tmp/books.json && curl -fsS -X POST http://localhost/ -H content-type:application/json --data @/tmp/books.json"
Run-Ssh "23-apollo-connectivity-observability.txt" $AppPublicIp "curl -fsS http://${ObservabilityPrivateIp}:8200/ && printf '\n--- Elasticsearch ---\n' && curl -fsS http://${ObservabilityPrivateIp}:9200/ && printf '\n--- Kibana ---\n' && curl -fsS http://${ObservabilityPrivateIp}:5601/api/status | head -c 1000"
Run-Ssh "24-apollo-logs-tail.txt" $AppPublicIp "docker logs apollo-server --tail 80 2>&1; printf '\n--- nginx ---\n'; docker logs apollo-nginx --tail 80 2>&1; printf '\n--- filebeat ---\n'; docker logs filebeat-apollo --tail 80 2>&1; printf '\n--- metricbeat ---\n'; docker logs metricbeat-apollo --tail 80 2>&1"

Run-Local "30-public-apollo-query.txt" "`$body = @{operationName='GetBooks';query='query GetBooks { books { title author } }'} | ConvertTo-Json -Compress; Invoke-RestMethod -Uri 'http://${AppPublicIp}/' -Method Post -ContentType 'application/json' -Body `$body | ConvertTo-Json -Depth 5"

Write-Host ""
Write-Host "Evidence saved in $runDir"
Write-Host "Use these text files and screenshots from Kibana/AWS Console to complete docs\entrega-mudevops05-act3.docx."
