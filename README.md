# Monitorizacion de un despliegue de Apollo Server

Laboratorio para la actividad `MUDevOps05 - Actividad 3`. El proyecto deja
preparados los templates de instalacion, configuracion y justificacion para
desplegar un Apollo Server en AWS y observarlo con Elastic Stack, APM Server,
Logstash, Filebeat y Metricbeat.

## Arquitectura

- Instancia `apollo`: Apollo Server + Nginx + Filebeat + Metricbeat.
- Instancia `observability`: Elasticsearch + Kibana + Logstash + APM Server + Metricbeat.
- APM Node.js Agent envia trazas GraphQL a `apm-server:8200`.
- Filebeat envia logs de Nginx y Apollo a Logstash `5044`.
- Metricbeat envia metricas de sistema y Docker de ambas instancias, y metricas Nginx desde Apollo, a Elasticsearch `9200`.

La version por defecto de Elastic es `7.9.3` porque el enunciado enlaza la
guia de APM Server 7.9. En un entorno real conviene usar una version vigente
y revisar Elastic Agent/Fleet.

## Estructura

```text
apollo/                         Codigo de Apollo Server instrumentado con APM
elastic/                        Configuracion de APM, Logstash, Filebeat y Metricbeat
infra/aws/cloudformation-two-ec2.yaml
nginx/default.conf              Proxy reverso y endpoint stub_status
scripts/                        Bootstrap, verificacion y despliegue
scripts/kibana/create-index-patterns.sh
docs/                           Documento base de entrega y checklist de capturas
docker-compose.apollo.yml       Servicios de la instancia Apollo
docker-compose.elastic.yml      Servicios de la instancia Elastic Stack
```

Guias principales:

- `docs/runbook-paso-a-paso-aws.md`: ejecucion en AWS de principio a fin.
- `docs/dashboards-kibana.md`: dashboards y campos concretos para Kibana.
- `docs/checklist-capturas.md`: evidencias que debes guardar para el informe.
- `docs/troubleshooting.md`: errores comunes y como resolverlos.
- `docs/costes-y-confirmacion-aws.md`: recursos, limpieza y confirmacion
  requerida antes de crear EC2.
- `docs/comandos-rapidos.md`: chuleta de comandos principales.
- `docs/entrega-mudevops05-act3.docx`: informe base generado para completar
  con capturas reales tras el despliegue.
- `docs/validacion-local.md`: comprobaciones ya realizadas en esta maquina.
- `scripts/aws/collect-evidence.ps1`: guarda evidencias tecnicas tras el
  despliegue y antes de eliminar recursos.

Para abrir el proyecto en VS Code:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\open-workspace.ps1
```

## Paso 1: revisar AWS CLI

La AWS CLI ya esta configurada en esta maquina y la region detectada es
`us-east-1`. Antes de crear recursos, confirma que quieres usar esa region y
que tienes un par de claves EC2.

```powershell
aws configure get region
aws ec2 describe-key-pairs --query "KeyPairs[].KeyName" --output table
```

Tambien puedes ejecutar el preflight sin crear recursos:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\preflight.ps1 -KeyName "apollo-lab-key"
```

Y revisar si ya hay recursos del laboratorio vivos:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

## Paso 2: crear la infraestructura

Opcion A, con EC2 directo. Es la opcion recomendada si tu usuario IAM no tiene
permisos de CloudFormation.

Si todavia no tienes un par de claves EC2, puedes crearlo asi:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

Si ya tienes un par de claves:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "TU_KEYPAIR"
```

Opcion B, con CloudFormation.

Restringe `AllowedCidr` a tu IP publica. El script la detecta automaticamente
si no la pasas.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-stack.ps1 -KeyName "TU_KEYPAIR"
```

Al terminar, CloudFormation mostrara las IPs publicas/privadas de las dos
instancias.

## Paso 3: copiar el laboratorio y arrancar servicios

Usa la ruta de tu `.pem` y las IPs que salieron en CloudFormation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\deploy-to-ec2.ps1 `
  -SshKeyPath "C:\ruta\TU_KEYPAIR.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

## Paso 4: generar trafico de prueba

En la instancia Apollo:

```bash
cd /opt/apollo-monitoring-lab
./scripts/generate-load.sh http://localhost/
```

Tambien puedes abrir `http://IP_PUBLICA_APOLLO/` y ejecutar:

```graphql
query GetBooks {
  books {
    title
    author
  }
}
```

## Paso 5: validar en Kibana

Abre `http://IP_PUBLICA_OBSERVABILITY:5601` y revisa:

- Observability > APM > servicio `apollo-server`.
- Discover: indices `apollo.application-*` y `nginx.access-*`.
- Metrics: CPU, RAM, disco y Docker de ambas instancias.
- Dashboard manual con las visualizaciones propuestas en
  `docs/entrega-mudevops05-act3.md`.

## Limpieza para evitar costes

Cuando termines la actividad:

```powershell
aws cloudformation delete-stack --stack-name apollo-monitoring-lab
```

Si usaste el script EC2 directo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1
```

Para borrar tambien los Security Groups del laboratorio:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups
```
