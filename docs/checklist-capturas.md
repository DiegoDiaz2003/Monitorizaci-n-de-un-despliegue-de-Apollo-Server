# Checklist de capturas para la entrega

Usa esta lista para reunir evidencias del despliegue en AWS y completar el
documento final.

## Infraestructura AWS

- Captura de las dos instancias EC2 en estado `running`.
- Captura de los Security Groups mostrando puertos:
  - Apollo: `22`, `80`.
  - Observability: `22`, `5601`, y puertos internos desde Apollo `5044`, `8200`, `9200`.
- Captura de salidas CloudFormation con `ApolloUrl` y `KibanaUrl`.

## Servicios

- En observability:
  - `docker compose -f docker-compose.elastic.yml ps`
  - `curl http://localhost:9200/_cluster/health?pretty`
  - `curl http://localhost:9600/`
- En Apollo:
  - `docker compose -f docker-compose.apollo.yml ps`
  - Apollo Sandbox con query `GetBooks`.
  - Query `Health` con respuesta `ok`.

## Kibana

- APM > servicio `apollo-server`, con transacciones.
- APM > trace de `SlowBooks` mostrando el span `simulate catalog lookup`.
- Discover con indice `nginx.access-*`.
- Discover con indice `apollo.application-*`.
- Metricbeat System dashboard o Lens con CPU/RAM de las dos instancias.
- Visualizacion de Nginx: codigos 2xx/4xx/5xx y `request_time`.

## Evidencias automatizadas

- Ejecutar `scripts/aws/collect-evidence.ps1` antes de borrar recursos.
- Guardar la carpeta `evidence/<timestamp>` como respaldo de la entrega.
- Usar `00-summary.txt`, `02-ec2-instances.txt`, `10-observability-docker-ps.txt`,
  `20-apollo-docker-ps.txt` y `22-apollo-books-query.txt` como apoyo del
  criterio 1.
