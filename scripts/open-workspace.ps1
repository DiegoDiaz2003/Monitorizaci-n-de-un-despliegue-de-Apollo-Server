$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path

if (Get-Command code -ErrorAction SilentlyContinue) {
  code $root
  Write-Host "Opened workspace in Visual Studio Code: $root"
} else {
  Write-Host "VS Code command 'code' was not found. Workspace path:"
  Write-Host $root
}

Write-Host ""
Write-Host "Useful next commands:"
Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\aws\preflight.ps1 -KeyName `"apollo-lab-key`""
Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName `"apollo-lab-key`""
Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName `"apollo-lab-key`" -CreateKeyPair"

