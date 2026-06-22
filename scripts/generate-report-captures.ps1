param(
  [string]$Region = "us-east-1",
  [string]$SshKeyPath = "$HOME\.ssh\apollo-lab-key.pem",
  [string]$AppPublicIp = "54.224.96.172",
  [string]$ObservabilityPublicIp = "34.229.213.242",
  [string]$ObservabilityPrivateIp = "172.31.43.63",
  [string]$Ec2User = "ubuntu",
  [string]$OutputDir = "docs\capturas"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$captureRoot = Join-Path $root $OutputDir
$sourceRoot = Join-Path $captureRoot "source"
New-Item -ItemType Directory -Force -Path $captureRoot, $sourceRoot | Out-Null

function Save-Text {
  param(
    [string]$Name,
    [string]$Title,
    [string]$Command,
    [string]$Output
  )

  $path = Join-Path $sourceRoot $Name
  $content = @"
$Title

COMANDO
$Command

SALIDA
$Output
"@
  [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
  return $path
}

function Run-LocalCapture {
  param(
    [string]$Name,
    [string]$Title,
    [string]$Command
  )

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = powershell -NoProfile -ExecutionPolicy Bypass -Command $Command 2>&1 | Out-String
  } catch {
    $output = $_ | Out-String
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  Save-Text -Name $Name -Title $Title -Command $Command -Output $output
}

function Run-SshCapture {
  param(
    [string]$Name,
    [string]$Title,
    [string]$HostIp,
    [string]$RemoteCommand
  )

  $sshTarget = "${Ec2User}@${HostIp}"
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $args = @("-o", "StrictHostKeyChecking=accept-new", "-i", $SshKeyPath, $sshTarget, $RemoteCommand)
    $output = & ssh @args 2>&1 | Out-String
  } catch {
    $output = $_ | Out-String
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  Save-Text -Name $Name -Title $Title -Command "ssh $sshTarget '$RemoteCommand'" -Output $output
}

function Wrap-CaptureLine {
  param(
    [string]$Line,
    [int]$MaxChars
  )

  if ($Line.Length -le $MaxChars) {
    return @($Line)
  }

  $chunks = New-Object System.Collections.Generic.List[string]
  $remaining = $Line
  while ($remaining.Length -gt $MaxChars) {
    $breakAt = $remaining.LastIndexOf(" ", [Math]::Min($MaxChars, $remaining.Length - 1))
    if ($breakAt -lt 40) {
      $breakAt = $MaxChars
    }
    $chunks.Add($remaining.Substring(0, $breakAt))
    $remaining = $remaining.Substring($breakAt).TrimStart()
  }
  if ($remaining.Length -gt 0) {
    $chunks.Add($remaining)
  }
  return $chunks.ToArray()
}

function Render-TextCapture {
  param(
    [string]$SourcePath,
    [string]$ImagePath,
    [string]$Title,
    [int]$MaxLines = 62
  )

  Add-Type -AssemblyName System.Drawing

  $rawLines = [System.IO.File]::ReadAllLines($SourcePath)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $rawLines) {
    foreach ($wrapped in (Wrap-CaptureLine -Line $line -MaxChars 158)) {
      $lines.Add($wrapped)
    }
  }
  if ($lines.Count -gt $MaxLines) {
    $trimmed = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt ($MaxLines - 6); $i++) {
      $trimmed.Add($lines[$i])
    }
    $trimmed.Add("")
    $trimmed.Add("[salida recortada para la captura; el archivo fuente conserva el detalle completo]")
    $trimmed.Add("")
    for ($i = [Math]::Max(0, $lines.Count - 3); $i -lt $lines.Count; $i++) {
      $trimmed.Add($lines[$i])
    }
    $lines = $trimmed
  }

  $width = 1800
  $margin = 42
  $titleHeight = 86
  $font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Regular)
  $titleFont = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
  $smallFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
  $lineHeight = [int][Math]::Ceiling($font.GetHeight() + 6)
  $height = $titleHeight + ($lines.Count * $lineHeight) + ($margin * 2)

  $bitmap = New-Object System.Drawing.Bitmap($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

  try {
    $background = [System.Drawing.ColorTranslator]::FromHtml("#0B1220")
    $bar = [System.Drawing.ColorTranslator]::FromHtml("#1F4D78")
    $text = [System.Drawing.ColorTranslator]::FromHtml("#E6EDF3")
    $muted = [System.Drawing.ColorTranslator]::FromHtml("#9FB3C8")
    $accent = [System.Drawing.ColorTranslator]::FromHtml("#A7C7E7")
    $green = [System.Drawing.ColorTranslator]::FromHtml("#9CE29C")

    $graphics.Clear($background)
    $graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bar)), 0, 0, $width, $titleHeight)
    $graphics.DrawString($Title, $titleFont, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)), $margin, 18)
    $graphics.DrawString((Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $smallFont, (New-Object System.Drawing.SolidBrush($muted)), $margin, 56)

    $y = $titleHeight + 28
    foreach ($line in $lines) {
      $brushColor = $text
      if ($line -eq "COMANDO" -or $line -eq "SALIDA") {
        $brushColor = $accent
      } elseif ($line -match "running|green| ok | passed |healthy|GetBooks|apollo-server") {
        $brushColor = $green
      }
      $graphics.DrawString($line, $font, (New-Object System.Drawing.SolidBrush($brushColor)), $margin, $y)
      $y += $lineHeight
    }

    $parent = Split-Path -Parent $ImagePath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $bitmap.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $font.Dispose()
    $titleFont.Dispose()
    $smallFont.Dispose()
  }
}

Write-Host "Generating source captures in $sourceRoot"

$statusCommand = "powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName 'apollo-lab-key'"
Run-LocalCapture "aws-01-creacion-estado.txt" "AWS - creacion y estado del laboratorio" $statusCommand

Run-LocalCapture "aws-02-instancias-launchtime.txt" "AWS - EC2 con LaunchTime" "aws ec2 describe-instances --region $Region --filters 'Name=tag:Lab,Values=apollo-monitoring' --query 'Reservations[].Instances[].{Name:Tags[?Key==``Name``]|[0].Value,InstanceId:InstanceId,State:State.Name,Type:InstanceType,AZ:Placement.AvailabilityZone,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,LaunchTime:LaunchTime}' --output table"

Run-LocalCapture "aws-03-security-groups.txt" "AWS - Security Groups creados" "aws ec2 describe-security-groups --region $Region --filters 'Name=group-name,Values=apollo-monitoring-app-sg,apollo-monitoring-observability-sg' --query 'SecurityGroups[].{GroupName:GroupName,GroupId:GroupId,VpcId:VpcId,Ingress:IpPermissions[*].{Protocol:IpProtocol,From:FromPort,To:ToPort,Cidr:IpRanges[*].CidrIp,SourceSg:UserIdGroupPairs[*].GroupId}}' --output json"

Run-LocalCapture "aws-04-volumenes-keypair.txt" "AWS - Volumenes EBS y Key Pair" "aws ec2 describe-volumes --region $Region --filters 'Name=tag:Lab,Values=apollo-monitoring' --query 'Volumes[].{Name:Tags[?Key==``Name``]|[0].Value,VolumeId:VolumeId,SizeGiB:Size,State:State,AttachedTo:Attachments[0].InstanceId}' --output table; aws ec2 describe-key-pairs --region $Region --key-names apollo-lab-key --query 'KeyPairs[].{KeyName:KeyName,KeyPairId:KeyPairId}' --output table"

Run-SshCapture "observability-01-docker.txt" "Elastic Stack - contenedores activos" $ObservabilityPublicIp "cd /opt/apollo-monitoring-lab && sudo docker compose -f docker-compose.elastic.yml ps"

Run-SshCapture "observability-02-health-indices.txt" "Elastic Stack - salud e indices" $ObservabilityPublicIp "curl -fsS http://localhost:9200/_cluster/health?pretty && printf '\n--- indices ---\n' && curl -fsS 'http://localhost:9200/_cat/indices/apm-*,metricbeat-*,nginx.access-*,apollo.application-*?v'"

$apmAgg = '{"aggs":{"services":{"terms":{"field":"service.name","size":10}},"events":{"terms":{"field":"processor.event","size":10}}}}'
$apmAggB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($apmAgg))
Run-SshCapture "observability-03-apm-aggs.txt" "Elastic APM - servicio y eventos" $ObservabilityPublicIp "echo $apmAggB64 | base64 -d > /tmp/apm-agg.json && curl -fsS -X POST 'http://localhost:9200/apm-*/_search?size=0&pretty' -H 'Content-Type: application/json' --data @/tmp/apm-agg.json"

Run-SshCapture "apollo-01-docker.txt" "Apollo - contenedores activos" $AppPublicIp "cd /opt/apollo-monitoring-lab && sudo docker compose -f docker-compose.apollo.yml ps"

$booksPayload = '{"operationName":"GetBooks","query":"query GetBooks { books { title author } }"}'
$booksPayloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($booksPayload))
Run-SshCapture "apollo-02-graphql.txt" "Apollo Server - consulta GraphQL GetBooks" $AppPublicIp "echo $booksPayloadB64 | base64 -d > /tmp/books.json && curl -fsS -X POST http://localhost/ -H content-type:application/json --data @/tmp/books.json"

Run-SshCapture "apollo-03-conectividad.txt" "Apollo - conectividad hacia observabilidad" $AppPublicIp "curl -fsS http://${ObservabilityPrivateIp}:8200/ && printf '\n--- Elasticsearch ---\n' && curl -fsS http://${ObservabilityPrivateIp}:9200/ && printf '\n--- Kibana ---\n' && curl -fsS http://${ObservabilityPrivateIp}:5601/api/status | head -c 1000"

$captures = @(
  @{ Source = "aws-01-creacion-estado.txt"; Image = "aws-01-creacion-estado.png"; Title = "AWS - creacion y estado" },
  @{ Source = "aws-02-instancias-launchtime.txt"; Image = "aws-02-instancias-launchtime.png"; Title = "AWS - EC2 LaunchTime" },
  @{ Source = "aws-03-security-groups.txt"; Image = "aws-03-security-groups.png"; Title = "AWS - Security Groups" },
  @{ Source = "aws-04-volumenes-keypair.txt"; Image = "aws-04-volumenes-keypair.png"; Title = "AWS - EBS y Key Pair" },
  @{ Source = "observability-01-docker.txt"; Image = "observability-01-docker.png"; Title = "Elastic Stack - Docker Compose" },
  @{ Source = "observability-02-health-indices.txt"; Image = "observability-02-health-indices.png"; Title = "Elastic Stack - salud e indices" },
  @{ Source = "observability-03-apm-aggs.txt"; Image = "observability-03-apm-aggs.png"; Title = "Elastic APM - servicio apollo-server" },
  @{ Source = "apollo-01-docker.txt"; Image = "apollo-01-docker.png"; Title = "Apollo - Docker Compose" },
  @{ Source = "apollo-02-graphql.txt"; Image = "apollo-02-graphql.png"; Title = "Apollo - GraphQL GetBooks" },
  @{ Source = "apollo-03-conectividad.txt"; Image = "apollo-03-conectividad.png"; Title = "Apollo - conectividad privada" }
)

Write-Host "Rendering PNG captures in $captureRoot"
foreach ($capture in $captures) {
  $sourcePath = Join-Path $sourceRoot $capture.Source
  $imagePath = Join-Path $captureRoot $capture.Image
  Render-TextCapture -SourcePath $sourcePath -ImagePath $imagePath -Title $capture.Title
  Write-Host "Created $imagePath"
}

Write-Host "Capture generation complete: $captureRoot"
