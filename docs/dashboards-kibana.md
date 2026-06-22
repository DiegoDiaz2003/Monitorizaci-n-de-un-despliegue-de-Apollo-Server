# Guia de dashboards en Kibana

La actividad pide una estrategia de monitorizacion y dashboards. Estos paneles
cubren las tres areas principales: infraestructura, APM GraphQL y logs HTTP.

## 1. Index patterns

Crea estos index patterns en `Stack Management > Index Patterns`:

| Patron | Time field | Uso |
| --- | --- | --- |
| `metricbeat-*` | `@timestamp` | CPU, RAM, disco, Docker y Nginx |
| `apm-*` | `@timestamp` | Transacciones, spans y errores de Apollo |
| `nginx.access-*` | `@timestamp` | Trafico HTTP de Nginx |
| `nginx.error-*` | `@timestamp` | Errores de Nginx |
| `apollo.application-*` | `@timestamp` | Logs JSON de Apollo |

Tambien puedes crearlos por API desde la instancia observability:

```bash
cd /opt/apollo-monitoring-lab
./scripts/kibana/create-index-patterns.sh
```

## 2. Dashboard: Infraestructura AWS

Nombre sugerido: `Apollo + Elastic - Infraestructura`.

Paneles recomendados:

| Panel | Tipo | Index pattern | Campo/Eje |
| --- | --- | --- | --- |
| CPU por host | Line | `metricbeat-*` | Y: avg `system.cpu.total.norm.pct`; X: `@timestamp`; split: `host.name` |
| RAM usada por host | Line | `metricbeat-*` | Y: avg `system.memory.actual.used.pct`; split: `host.name` |
| Load average | Line | `metricbeat-*` | Y: avg `system.load.1`; split: `host.name` |
| Disco usado | Metric/Gauge | `metricbeat-*` | avg `system.filesystem.used.pct`; split: `host.name` |
| Top procesos CPU | Data table | `metricbeat-*` | terms `process.name`; avg `system.process.cpu.total.norm.pct` |
| Docker CPU/RAM | Bar/Line | `metricbeat-*` | split: `docker.container.name`; avg `docker.cpu.total.pct`, avg `docker.memory.usage.pct` |

Filtros utiles:

```text
event.dataset: system.cpu or event.dataset: system.memory
```

Captura requerida: panel donde se vean las dos instancias, Apollo y Elastic
Stack, con CPU/RAM.

## 3. Dashboard: APM GraphQL

Nombre sugerido: `Apollo GraphQL - APM`.

Primero revisa `Observability > APM > Services > apollo-server`. Kibana ya
muestra transacciones, latencia y errores sin crear paneles manuales.

Paneles recomendados:

| Panel | Tipo | Index pattern | Campo/Eje |
| --- | --- | --- | --- |
| Throughput | Line | `apm-*` | count por `@timestamp`; filtro `service.name: "apollo-server"` |
| Latencia promedio | Line | `apm-*` | avg `transaction.duration.us`; filtro `processor.event: "transaction"` |
| Latencia p95 | Line | `apm-*` | percentile 95 de `transaction.duration.us` |
| Operaciones GraphQL | Data table | `apm-*` | terms `labels.graphql_operation_name` |
| Errores APM | Metric | `apm-*` | count; filtro `processor.event: "error"` |

Nota: si no aparece `labels.graphql_operation_name`, busca `graphql` en
Discover para ver el nombre exacto del campo indexado.

Capturas requeridas:

- Servicio `apollo-server` en APM.
- Una transaccion lenta `SlowBooks`.
- Grafico de latencia o throughput.

## 4. Dashboard: Logs y borde HTTP

Nombre sugerido: `Apollo GraphQL - Logs HTTP`.

Paneles recomendados:

| Panel | Tipo | Index pattern | Campo/Eje |
| --- | --- | --- | --- |
| Status codes | Bar/Pie | `nginx.access-*` | terms `nginx.status` |
| Peticiones por minuto | Line | `nginx.access-*` | count por `@timestamp` |
| Tiempo HTTP promedio | Line | `nginx.access-*` | avg `nginx.request_time` |
| Tiempo HTTP p95 | Line | `nginx.access-*` | percentile 95 de `nginx.request_time` |
| Top URIs | Data table | `nginx.access-*` | terms `nginx.uri` |
| Logs por nivel Apollo | Bar/Pie | `apollo.application-*` | terms `apollo.level` |

Consultas utiles en Discover:

```text
nginx.status >= 500
```

```text
apollo.msg : "GraphQL error captured"
```

```text
apollo.operation : "slowBooks"
```

Capturas requeridas:

- Discover con logs `nginx.access-*`.
- Discover con logs `apollo.application-*`.
- Dashboard con status codes y tiempos de respuesta.

## 5. Alertas recomendadas

Estas alertas se pueden dejar documentadas aunque no se configuren si la
licencia/laboratorio no lo permite.

| Alerta | Condicion | Motivo |
| --- | --- | --- |
| CPU alta | `system.cpu.total.norm.pct > 0.80` durante 5 min | Riesgo de saturacion |
| RAM baja | memoria disponible menor a 15% | Riesgo de OOM |
| Disco alto | filesystem usado mayor a 85% | Riesgo de perdida de indices/logs |
| Latencia GraphQL alta | p95 mayor a 1 s durante 5 min | Degradacion de API |
| Error rate alto | errores mayor a 5% | Problema funcional o de infraestructura |
| HTTP 5xx alto | respuestas 5xx por encima del baseline | Fallo del backend o proxy |
