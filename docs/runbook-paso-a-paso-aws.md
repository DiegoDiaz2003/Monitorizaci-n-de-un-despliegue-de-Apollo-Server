# Runbook paso a paso: despliegue en AWS

Este runbook esta pensado para ejecutarlo desde PowerShell en esta carpeta:

```powershell
cd "C:\Users\Mochito Pato\Downloads\Monitorización de un despliegue de Apollo Server"
```

## 0. Comprobaciones iniciales

```powershell
aws sts get-caller-identity
aws configure get region
aws ec2 describe-key-pairs --query "KeyPairs[].KeyName" --output table
```

Ejecuta tambien el preflight del laboratorio. No crea recursos:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\preflight.ps1 -KeyName "apollo-lab-key"
```

Revisa tambien si existe algun recurso del laboratorio antes de empezar:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

En la revision actual se detecto:

- Region AWS: `us-east-1`.
- Usuario IAM: `arn:aws:iam::592172381303:user/actividad_packet`.
- No habia key pairs EC2 en la region.
- `cloudformation:ValidateTemplate` y `ssm:GetParameter` estaban bloqueados.
- `ec2:create-key-pair --dry-run` confirmo permiso para crear key pair.

Por eso se recomienda usar el script EC2 directo.

## 1. Crear infraestructura

Antes de crear recursos, revisa `docs/costes-y-confirmacion-aws.md`.

Si no tienes un par de claves EC2:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

El script guardara la clave privada en:

```text
C:\Users\Mochito Pato\.ssh\apollo-lab-key.pem
```

Si ya tienes un par de claves:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "NOMBRE_DE_TU_KEYPAIR"
```

Guarda los valores que imprime al final:

- `apollo-monitoring-app`:
  - `PublicIp`
  - `PrivateIp`
- `apollo-monitoring-observability`:
  - `PublicIp`
  - `PrivateIp`

## 2. Esperar SSH

AWS puede tardar 1 o 2 minutos en aceptar conexiones SSH aunque la instancia
ya figure como `running`.

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_APOLLO "echo ok"
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_OBSERVABILITY "echo ok"
```

## 3. Copiar laboratorio y arrancar servicios

Sustituye las IPs por las que imprimio el paso 1:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\deploy-to-ec2.ps1 `
  -SshKeyPath "$HOME\.ssh\apollo-lab-key.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

Este paso hace lo siguiente:

- Copia el proyecto a `/opt/apollo-monitoring-lab` en ambas instancias.
- Instala Docker y Docker Compose plugin.
- Arranca Elasticsearch, Kibana, Logstash, APM Server y Metricbeat.
- Arranca Apollo Server, Nginx, Filebeat y Metricbeat.

## 4. Validar Elastic Stack

En tu maquina local:

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_OBSERVABILITY `
  "cd /opt/apollo-monitoring-lab && docker compose -f docker-compose.elastic.yml ps"
```

En la instancia observability:

```bash
curl http://localhost:9200/_cluster/health?pretty
curl http://localhost:5601/api/status
curl http://localhost:8200/
curl http://localhost:9600/
```

Captura estas salidas para la entrega.

## 5. Validar Apollo Server

En tu maquina local:

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_APOLLO `
  "cd /opt/apollo-monitoring-lab && docker compose -f docker-compose.apollo.yml ps"
```

Prueba GraphQL:

```powershell
curl.exe -X POST "http://IP_PUBLICA_APOLLO/" `
  -H "content-type: application/json" `
  --data "{\"operationName\":\"GetBooks\",\"query\":\"query GetBooks { books { title author } }\"}"
```

Prueba de salud:

```powershell
curl.exe -X POST "http://IP_PUBLICA_APOLLO/" `
  -H "content-type: application/json" `
  --data "{\"operationName\":\"Health\",\"query\":\"query Health { health }\"}"
```

Tambien puedes abrir:

```text
http://IP_PUBLICA_APOLLO/
```

Y ejecutar en Apollo Sandbox:

```graphql
query GetBooks {
  books {
    title
    author
  }
}
```

## 6. Generar trafico

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_APOLLO `
  "cd /opt/apollo-monitoring-lab && ./scripts/generate-load.sh http://localhost/"
```

Para generar mas trafico:

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_APOLLO `
  "cd /opt/apollo-monitoring-lab && REQUESTS=180 ./scripts/generate-load.sh http://localhost/"
```

## 7. Revisar Kibana

Abre:

```text
http://IP_PUBLICA_OBSERVABILITY:5601
```

Puedes crear los index patterns automaticamente desde la instancia
observability:

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA_OBSERVABILITY `
  "cd /opt/apollo-monitoring-lab && chmod +x scripts/kibana/create-index-patterns.sh && ./scripts/kibana/create-index-patterns.sh"
```

Revisa:

- Observability > APM > `apollo-server`.
- Stack Management > Index Patterns:
  - `nginx.access-*`
  - `nginx.error-*`
  - `apollo.application-*`
  - `metricbeat-*`
  - `apm-*`
- Discover con logs Nginx y Apollo.
- Dashboard/Lens con las visualizaciones de `docs/dashboards-kibana.md`.

## 8. Recolectar evidencias

Antes de limpiar recursos, guarda salidas tecnicas en la carpeta `evidence/`.
Sustituye las IPs por las del paso 1:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\collect-evidence.ps1 `
  -SshKeyPath "$HOME\.ssh\apollo-lab-key.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

El script crea una subcarpeta con timestamp e incluye:

- Estado EC2 y Security Groups.
- `docker compose ps` de ambas instancias.
- Health checks de Elasticsearch, Kibana, Logstash, APM y Apollo.
- Indices disponibles en Elasticsearch.
- Queries GraphQL de salud y libros.
- Ultimas lineas de logs de contenedores.

Estas evidencias complementan las capturas visuales de AWS Console y Kibana.

## 9. Limpieza de costes

Cuando termines y tengas tus capturas:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1
```

Si tambien quieres borrar los Security Groups creados para el laboratorio:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups
```

Verifica que no queden instancias encendidas:

```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Lab,Values=apollo-monitoring" `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,PublicIp:PublicIpAddress}" `
  --output table
```

Si algo falla durante el proceso, revisa `docs/troubleshooting.md`.
