# Comandos rapidos

Ejecutar desde:

```powershell
cd "C:\Users\Mochito Pato\Downloads\Monitorización de un despliegue de Apollo Server"
```

## Antes de crear recursos

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\preflight.ps1 -KeyName "apollo-lab-key"
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

## Crear EC2

Requiere confirmacion explicita porque genera coste:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

## Desplegar servicios

Sustituir IPs:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\deploy-to-ec2.ps1 `
  -SshKeyPath "$HOME\.ssh\apollo-lab-key.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

## Generar trafico

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_APOLLO `
  "cd /opt/apollo-monitoring-lab && REQUESTS=180 ./scripts/generate-load.sh http://localhost/"
```

## Recolectar evidencias

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\collect-evidence.ps1 `
  -SshKeyPath "$HOME\.ssh\apollo-lab-key.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

## Limpiar recursos

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

