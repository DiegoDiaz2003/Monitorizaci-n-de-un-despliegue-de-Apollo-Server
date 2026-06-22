# Validacion local

## Estado actual

- AWS CLI configurada y autenticada.
- Region detectada: `us-east-1`.
- Usuario IAM detectado: `arn:aws:iam::592172381303:user/actividad_packet`.
- VPC default encontrada: `vpc-00c61b64778cb65d5`.
- Subnet default encontrada: `subnet-048e1ebd0f0cdef5d`.
- AMI Ubuntu 22.04 encontrada: `ami-0d7405d05f836d0d4`.
- No hay key pair EC2 en la region.
- `ec2:CreateKeyPair` validado con `dry-run`.
- `status-lab.ps1` confirma que no hay instancias, volumenes ni Security
  Groups del laboratorio vivos en este momento.

## Validaciones de archivos

- Scripts PowerShell: parseo OK.
- Scripts Bash: `bash -n` OK.
- ZIP de despliegue: rutas relativas OK.
- DOCX generado: paquete OOXML OK.
- `word/document.xml`: XML parseable OK.
- Apertura en Word: OK.
- Conteo Word del informe: 12 paginas, 1404 palabras.
- Healthcheck de Apollo agregado al `Dockerfile`.
- Bootstrap de observability valida Elasticsearch, Kibana, Logstash y APM.
- Bootstrap de Apollo valida query GraphQL `Health` y conectividad privada a
  APM, Elasticsearch y Kibana.
- Script `scripts/aws/collect-evidence.ps1` agregado para guardar evidencias
  post-despliegue en `evidence/<timestamp>`.
- Script `scripts/aws/status-lab.ps1` agregado para inventario AWS sin cambios.
- `delete-ec2-lab.ps1` permite borrar tambien Security Groups con
  `-DeleteSecurityGroups`.
- `docs/costes-y-confirmacion-aws.md` agregado como decision gate antes de
  crear recursos con coste.
- `docs/comandos-rapidos.md` agregado como chuleta operativa.
- `scripts/open-workspace.ps1` agregado para abrir el proyecto en VS Code.

## Limitacion de QA visual

No se pudo ejecutar el render DOCX a PNG porque `soffice`/LibreOffice no esta
instalado en esta maquina y el renderer de la skill no esta disponible en disco.
El documento se valido estructuralmente y se abrio correctamente en Microsoft
Word, pero queda pendiente una revision visual manual despues de abrirlo.

## Pendiente para cerrar la actividad

- Revisar dashboards visualmente en Kibana.
- Crear/revisar dashboards en Kibana.
- Insertar capturas reales en el informe DOCX.
- Eliminar recursos AWS al terminar para evitar costes.

## Despliegue AWS realizado

- Apollo: `i-0059be81271436a9a`, IP publica `54.224.96.172`, IP privada
  `172.31.42.65`.
- Observability: `i-0428b222902b16db4`, IP publica `34.229.213.242`, IP privada
  `172.31.43.63`.
- Kibana: `http://34.229.213.242:5601`.
- Apollo: `http://54.224.96.172/`.
- Evidencias: `evidence/20260621-223041`.
- Index patterns creados en Kibana.
- Trafico de prueba generado con `REQUESTS=60`.
