# Actividad abierta: Monitorizacion de un despliegue de Apollo Server

## 1. Objetivo y contexto

El objetivo de la practica es desplegar un Apollo Server de ejemplo en AWS y
monitorizarlo con Elastic Stack. La solucion propuesta separa la aplicacion y
la plataforma de observabilidad en dos instancias EC2 para poder medir de forma
independiente el consumo de recursos del servidor Apollo y del servidor Elastic
Stack.

La version base de Elastic usada en los templates es `7.9.3`, alineada con la
guia de APM Server 7.9 indicada en el enunciado. En produccion se recomienda
actualizar a una version soportada y valorar Elastic Agent/Fleet.

## 2. Criterio 1: templates de instalacion

### 2.0 Despliegue realizado en AWS

Despliegue ejecutado en `us-east-1`:

- Instancia Apollo: `i-0059be81271436a9a`.
- IP publica Apollo: `54.224.96.172`.
- IP privada Apollo: `172.31.42.65`.
- Instancia Observability: `i-0428b222902b16db4`.
- IP publica Observability/Kibana: `34.229.213.242`.
- IP privada Observability: `172.31.43.63`.
- URL Apollo: `http://54.224.96.172/`.
- URL Kibana: `http://34.229.213.242:5601`.
- Carpeta de evidencias automatizadas:
  `evidence/20260621-223041`.

Validaciones realizadas:

- Kibana `/api/status`: estado `green`.
- Apollo `GetBooks`: devuelve 4 libros.
- Apollo `Health`: devuelve `ok`.
- Elasticsearch contiene indices `apm-*`, `metricbeat-*`, `nginx.access-*` y
  `apollo.application-*`.

### 2.1 Infraestructura AWS

Templates:

- `infra/aws/cloudformation-two-ec2.yaml`
- `scripts/aws/create-ec2-lab.ps1`

Este template crea:

- Una instancia EC2 `apollo-monitoring-app` para Apollo Server, Nginx, Filebeat
  y Metricbeat.
- Una instancia EC2 `apollo-monitoring-observability` para Elasticsearch,
  Kibana, Logstash, APM Server y Metricbeat.
- Security Groups con acceso publico limitado por `AllowedCidr`.
- Reglas internas desde Apollo hacia Elastic Stack en puertos `5044`, `8200`
  y `9200`.

Comando de despliegue:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-stack.ps1 -KeyName "TU_KEYPAIR"
```

Si el usuario IAM no dispone de permisos de CloudFormation, se puede crear el
laboratorio con EC2 directo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

### 2.2 Template de Elastic Stack, Logstash y APM

Template: `docker-compose.elastic.yml`.

Servicios desplegados:

- `elasticsearch`: almacenamiento e indexacion de logs, metricas y trazas.
- `kibana`: visualizacion de dashboards, Discover y APM UI.
- `logstash`: transformacion de logs recibidos desde Filebeat por `5044`.
- `apm-server`: recepcion de datos del agente APM de Node.js por `8200`.
- `metricbeat`: metricas de sistema y Docker del servidor Elastic Stack.

Configuracion principal:

- `elastic/apm-server.yml`
- `elastic/logstash/pipeline/logstash.conf`

El pipeline de Logstash separa logs de Nginx, logs de error de Nginx y logs
JSON de Apollo, creando indices diarios:

- `nginx.access-YYYY.MM.dd`
- `nginx.error-YYYY.MM.dd`
- `apollo.application-YYYY.MM.dd`

### 2.3 Template de Apollo Server

Templates:

- `apollo/Dockerfile`
- `apollo/package.json`
- `apollo/src/index.js`
- `docker-compose.apollo.yml`

La aplicacion implementa el ejemplo de Apollo Server con el esquema `Book` y
las queries:

- `books`: devuelve la lista de libros.
- `book(title: String!)`: busca un libro por titulo.
- `health`: endpoint logico de salud.
- `slowBooks(delayMs: Int)`: simula latencia para validar trazas y percentiles.

El agente `elastic-apm-node` se inicia antes de cargar Apollo, de modo que pueda
instrumentar la aplicacion. Ademas se agregan labels de GraphQL como
`graphql.operation_name` y `graphql.result`.

### 2.4 Template de Nginx

Template: `nginx/default.conf`.

Nginx funciona como proxy reverso en el puerto `80` hacia Apollo `4000`. El
log de acceso se emite en JSON para facilitar el parseo en Logstash e incluye:

- metodo HTTP
- URI
- estado HTTP
- tiempo de peticion `request_time`
- upstream y tiempo de upstream
- user agent y referer

Tambien expone `stub_status` internamente en `8080/nginx_status`, usado por
Metricbeat para metricas del proxy.

### 2.5 Ejecucion del despliegue

Despues de crear la infraestructura se copia el laboratorio y se arrancan los
servicios con:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\deploy-to-ec2.ps1 `
  -SshKeyPath "C:\ruta\TU_KEYPAIR.pem" `
  -AppPublicIp "IP_PUBLICA_APOLLO" `
  -ObservabilityPublicIp "IP_PUBLICA_OBSERVABILITY" `
  -ObservabilityPrivateIp "IP_PRIVADA_OBSERVABILITY"
```

Validacion:

```bash
./scripts/verify-stack.sh
./scripts/generate-load.sh http://localhost/
```

Ademas, el arranque valida:

- Elasticsearch por `/_cluster/health`.
- Kibana por `/api/status`.
- APM Server por `/`.
- Logstash por su API local `:9600`.
- Apollo Server con la query GraphQL `query Health { health }`.

## 3. Criterio 2: seleccion de Beats y justificacion

### 3.1 Filebeat

Filebeat se usa en la instancia Apollo para recolectar:

- Logs de acceso de Nginx.
- Logs de error de Nginx.
- Logs JSON de Apollo Server.

Justificacion: Filebeat es ligero y esta orientado a envio de logs. En esta
practica permite centralizar en Elastic los eventos de borde HTTP y los eventos
internos de la aplicacion. Al enviar a Logstash se puede transformar el JSON de
Nginx y Apollo antes de indexar.

Template: `elastic/filebeat/filebeat.yml`.

Output:

```yaml
output.logstash:
  hosts: ["${LOGSTASH_HOST}"]
```

### 3.2 Metricbeat

Metricbeat se usa para medir recursos y servicios en ambas instancias:

- Modulo `system`: CPU, RAM, load, filesystem, procesos y uptime.
- Modulo `docker`: consumo de contenedores Apollo, Nginx, Filebeat y Metricbeat.
- Modulo `nginx`: metricas `stubstatus` del proxy Nginx.

Justificacion: la rubrica exige monitorizar CPU y RAM. Metricbeat cubre esa
necesidad en el servidor Apollo y en el servidor Elastic Stack, permitiendo
comparar el consumo del host y los contenedores. El modulo Nginx agrega
visibilidad sobre conexiones activas, aceptadas, manejadas y peticiones
procesadas.

Templates:

- `elastic/metricbeat/metricbeat.yml`
- `elastic/metricbeat/metricbeat-observability.yml`

Output:

```yaml
output.elasticsearch:
  hosts: ["${ELASTICSEARCH_HOST}"]
```

### 3.3 APM Agent para Node.js

Aunque no es un Beat, es esencial para la practica porque captura transacciones
y errores de Apollo Server. El agente envia datos a APM Server y estos se
visualizan desde Kibana APM.

Variables usadas:

```bash
ELASTIC_APM_SERVICE_NAME=apollo-server
ELASTIC_APM_SERVER_URL=http://OBSERVABILITY_PRIVATE_IP:8200
ELASTIC_APM_TRANSACTION_SAMPLE_RATE=1.0
ELASTIC_APM_CAPTURE_BODY=transactions
```

## 4. Criterio 3: estrategia de monitorizacion y dashboards

### 4.1 Dashboard de infraestructura

Objetivo: comparar el consumo de la instancia Apollo y la instancia Elastic
Stack.

Visualizaciones propuestas:

- CPU total y load average por host.
- RAM usada y porcentaje de memoria disponible.
- Uso de disco y filesystem.
- Top procesos por CPU y memoria.
- Uso de CPU/RAM por contenedor Docker.

Alertas recomendadas:

- CPU mayor a 80% durante 5 minutos.
- RAM disponible menor a 15%.
- Disco usado mayor a 85%.

### 4.2 Dashboard APM GraphQL

Objetivo: analizar transacciones y queries al servidor Apollo.

Visualizaciones propuestas:

- Throughput de transacciones por minuto.
- Latencia p50, p95 y p99.
- Tasa de errores por operacion.
- Distribucion por `graphql.operation_name`.
- Trazas lentas de `SlowBooks` con span `simulate catalog lookup`.

Alertas recomendadas:

- p95 mayor a 1 segundo durante 5 minutos.
- Error rate mayor a 5%.
- Throughput anormalmente bajo si se espera trafico constante.

### 4.3 Dashboard de logs y borde HTTP

Objetivo: observar comportamiento HTTP desde Nginx y eventos internos de la
aplicacion.

Visualizaciones propuestas:

- Conteo de status codes `2xx`, `4xx`, `5xx`.
- Top URIs solicitadas.
- Promedio y p95 de `nginx.request_time`.
- Logs de Apollo por nivel (`info`, `warn`, `error`).
- Relacion entre errores de aplicacion y errores HTTP.

Alertas recomendadas:

- Aumento de respuestas `5xx`.
- `request_time` p95 mayor a 1 segundo.
- Errores recurrentes en `apollo.application-*`.

## 5. Evidencias esperadas

Para la entrega final se deben incluir capturas de:

- EC2 con ambas instancias en ejecucion.
- `docker compose ps` en ambas instancias.
- Apollo Sandbox ejecutando `GetBooks`.
- Kibana APM mostrando el servicio `apollo-server`.
- Discover con logs `nginx.access-*` y `apollo.application-*`.
- Dashboard de CPU/RAM de Apollo y Elastic Stack.
- Dashboard de transacciones y queries GraphQL.

### 5.1 Espacios para capturas

Completar despues del despliegue:

- Captura 1: consola AWS EC2 con ambas instancias `running`.
- Captura 2: salida `docker compose -f docker-compose.elastic.yml ps`.
- Captura 3: salida `docker compose -f docker-compose.apollo.yml ps`.
- Captura 4: Apollo Sandbox con la query `GetBooks`.
- Captura 5: Kibana APM con el servicio `apollo-server`.
- Captura 6: Kibana Discover con indice `nginx.access-*`.
- Captura 7: Kibana Discover con indice `apollo.application-*`.
- Captura 8: dashboard de infraestructura con CPU/RAM de Apollo y Elastic.
- Captura 9: dashboard o APM con latencia/throughput de GraphQL.

Documentos auxiliares:

- `docs/runbook-paso-a-paso-aws.md`: comandos exactos de despliegue,
  validacion y limpieza.
- `docs/dashboards-kibana.md`: paneles concretos que se deben crear en Kibana,
  con index patterns y campos.
- `docs/checklist-capturas.md`: lista de evidencias visuales para insertar en
  el informe final.
- `docs/troubleshooting.md`: incidencias frecuentes detectadas durante la
  preparacion del laboratorio y su resolucion.
- `scripts/aws/collect-evidence.ps1`: recoleccion automatizada de evidencias
  tecnicas del despliegue antes de eliminar recursos.

## 6. Conclusiones

La solucion cubre tres capas de observabilidad:

- Infraestructura: CPU, RAM, disco, red y procesos mediante Metricbeat.
- Aplicacion: transacciones, latencia, errores y spans mediante Elastic APM.
- Logs: peticiones HTTP y eventos de aplicacion mediante Filebeat y Logstash.

Esta separacion permite diagnosticar si un problema nace en la infraestructura,
en la aplicacion GraphQL o en el borde HTTP de Nginx.

## 7. Fuentes oficiales consultadas

- Apollo Server Get Started:
  https://www.apollographql.com/docs/apollo-server/getting-started/
- Elastic APM Server 7.9 Getting Started:
  https://www.elastic.co/guide/en/apm/server/7.9/getting-started-apm-server.html
- Elastic APM Server 7.9 Install/Configure/Start:
  https://www.elastic.co/guide/en/apm/server/7.9/installing.html
  https://www.elastic.co/guide/en/apm/server/7.9/apm-server-configuration.html
  https://www.elastic.co/guide/en/apm/server/7.9/apm-server-starting.html
- Elastic APM Node.js Agent:
  https://www.elastic.co/docs/reference/apm/agents/nodejs/starting-agent
- Elastic Docker install reference:
  https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-with-docker
- Metricbeat System module:
  https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-module-system
- Metricbeat Nginx module:
  https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-module-nginx
- Filebeat Nginx module:
  https://www.elastic.co/docs/reference/beats/filebeat/filebeat-module-nginx
