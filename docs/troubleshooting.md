# Troubleshooting

## PowerShell no deja ejecutar `.ps1`

Error tipico:

```text
la ejecucion de scripts esta deshabilitada en este sistema
```

Solucion recomendada para esta practica, sin cambiar la politica permanente:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\preflight.ps1 -KeyName "apollo-lab-key"
```

Usa el mismo prefijo con los demas scripts `.ps1`.

## No hay key pair EC2

Sintoma en preflight:

```text
[WARN] EC2 key pairs - No key pairs found
InvalidKeyPair.NotFound
```

Solucion:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

La clave queda en:

```text
C:\Users\Mochito Pato\.ssh\apollo-lab-key.pem
```

## CloudFormation o SSM bloqueado por IAM

Sintomas observados:

```text
cloudformation:ValidateTemplate AccessDenied
ssm:GetParameter AccessDenied
```

Solucion: usar el despliegue EC2 directo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

El script directo no usa SSM para la AMI; resuelve Ubuntu 22.04 con
`ec2 describe-images`.

## SSH todavia no responde

Aunque EC2 figure como `running`, cloud-init puede tardar un poco. Espera 1 o
2 minutos y prueba:

```powershell
ssh -i "$HOME\.ssh\apollo-lab-key.pem" ubuntu@IP_PUBLICA "echo ok"
```

## Quiero confirmar que no quedan recursos vivos

Ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

Si todavia aparecen instancias, limpia con:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups
```

## Kibana tarda en arrancar

El primer arranque de Elasticsearch/Kibana puede tardar varios minutos en una
instancia pequena. Revisa:

```bash
cd /opt/apollo-monitoring-lab
docker compose -f docker-compose.elastic.yml ps
docker logs elasticsearch --tail 80
docker logs kibana --tail 80
```

## Elasticsearch no arranca por `vm.max_map_count`

El bootstrap de observability configura:

```bash
sysctl -w vm.max_map_count=262144
```

Si aun aparece el error:

```bash
sudo sysctl -w vm.max_map_count=262144
cd /opt/apollo-monitoring-lab
docker compose -f docker-compose.elastic.yml up -d
```

## APM no muestra el servicio `apollo-server`

Genera trafico desde la instancia Apollo:

```bash
cd /opt/apollo-monitoring-lab
REQUESTS=120 ./scripts/generate-load.sh http://localhost/
```

Revisa conectividad privada hacia APM Server:

```bash
curl http://IP_PRIVADA_OBSERVABILITY:8200/
docker logs apollo-server --tail 80
docker logs apm-server --tail 80
```

Comprueba tambien que Apollo responde a la query de salud:

```bash
curl -X POST http://localhost/ \
  -H "content-type: application/json" \
  --data '{"operationName":"Health","query":"query Health { health }"}'
```

## No aparecen logs en Discover

Revisa Filebeat y Logstash:

```bash
docker logs filebeat-apollo --tail 80
docker logs logstash --tail 80
curl http://IP_PRIVADA_OBSERVABILITY:9200/_cat/indices?v
```

Indices esperados:

- `nginx.access-*`
- `nginx.error-*`
- `apollo.application-*`
- `metricbeat-*`
- `apm-*`
