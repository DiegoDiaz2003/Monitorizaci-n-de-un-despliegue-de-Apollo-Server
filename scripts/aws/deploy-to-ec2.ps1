param(
  [Parameter(Mandatory = $true)]
  [string]$SshKeyPath,

  [Parameter(Mandatory = $true)]
  [string]$AppPublicIp,

  [Parameter(Mandatory = $true)]
  [string]$ObservabilityPublicIp,

  [Parameter(Mandatory = $true)]
  [string]$ObservabilityPrivateIp,

  [string]$Ec2User = "ubuntu",
  [string]$ElasticVersion = "7.9.3"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path ".").Path
$zip = Join-Path $env:TEMP "apollo-monitoring-lab.zip"

if (Test-Path $zip) {
  Remove-Item $zip -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$excludedRootDirs = @(".git", "runtime", "node_modules", "evidence")
$zipStream = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
try {
  $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $files = Get-ChildItem -Path $root -Force -Recurse -File |
      Where-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart("\", "/")
        $top = ($relative -split "[\\/]")[0]
        $excludedRootDirs -notcontains $top
      }

    foreach ($file in $files) {
      $relative = $file.FullName.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
      $entry = $archive.CreateEntry($relative)
      $entryStream = $entry.Open()
      try {
        $fileStream = [System.IO.File]::OpenRead($file.FullName)
        try {
          $fileStream.CopyTo($entryStream)
        } finally {
          $fileStream.Dispose()
        }
      } finally {
        $entryStream.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
  }
} finally {
  $zipStream.Dispose()
}

function Copy-And-Unpack {
  param(
    [string]$HostIp
  )

  scp -o StrictHostKeyChecking=accept-new -i $SshKeyPath $zip "${Ec2User}@${HostIp}:/tmp/apollo-monitoring-lab.zip"
  ssh -o StrictHostKeyChecking=accept-new -i $SshKeyPath "${Ec2User}@${HostIp}" "sudo rm -rf /opt/apollo-monitoring-lab && sudo mkdir -p /opt/apollo-monitoring-lab && sudo unzip -q /tmp/apollo-monitoring-lab.zip -d /opt/apollo-monitoring-lab && sudo chown -R ${Ec2User}:${Ec2User} /opt/apollo-monitoring-lab && find /opt/apollo-monitoring-lab/scripts -name '*.sh' -exec chmod +x {} \;"
}

Write-Host "Copying files to observability instance..."
Copy-And-Unpack -HostIp $ObservabilityPublicIp

Write-Host "Starting Elastic Stack..."
ssh -i $SshKeyPath "${Ec2User}@${ObservabilityPublicIp}" "cd /opt/apollo-monitoring-lab && sudo ELASTIC_VERSION=$ElasticVersion ./scripts/bootstrap-observability.sh"

Write-Host "Copying files to Apollo instance..."
Copy-And-Unpack -HostIp $AppPublicIp

Write-Host "Starting Apollo, Nginx and Beats..."
ssh -i $SshKeyPath "${Ec2User}@${AppPublicIp}" "cd /opt/apollo-monitoring-lab && sudo ELASTIC_VERSION=$ElasticVersion APM_SERVER_URL=http://${ObservabilityPrivateIp}:8200 LOGSTASH_HOST=${ObservabilityPrivateIp}:5044 ELASTICSEARCH_HOST=http://${ObservabilityPrivateIp}:9200 KIBANA_HOST=http://${ObservabilityPrivateIp}:5601 ./scripts/bootstrap-apollo.sh"

Write-Host "Done."
Write-Host "Apollo: http://${AppPublicIp}/"
Write-Host "Kibana: http://${ObservabilityPublicIp}:5601"
