# Costes y confirmacion antes de crear AWS

Este laboratorio crea recursos con posible coste en AWS. No se deben crear sin
confirmacion explicita.

## Recursos que se crearan

Con el script recomendado:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

se crean:

- 1 instancia EC2 `t3.small` para Apollo, Nginx, Filebeat y Metricbeat.
- 1 instancia EC2 `t3.medium` para Elasticsearch, Kibana, Logstash, APM Server
  y Metricbeat.
- 1 volumen EBS gp3 de 20 GiB para Apollo.
- 1 volumen EBS gp3 de 40 GiB para Elastic Stack.
- 2 Security Groups.
- 1 key pair EC2 `apollo-lab-key`, si no existe.

## Como reducir coste

- Usar el laboratorio solo durante el tiempo necesario para capturas.
- Ejecutar `collect-evidence.ps1` antes de borrar recursos.
- Borrar las instancias al terminar.
- Confirmar con `status-lab.ps1` que no queda nada encendido.

Comando de limpieza:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups
```

Comando de verificacion post-limpieza:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\status-lab.ps1 -KeyName "apollo-lab-key"
```

## Estado actual antes de crear

La ultima validacion local encontro:

- Region: `us-east-1`.
- No hay instancias EC2 con tag `Lab=apollo-monitoring`.
- No hay volumenes EBS con tag `Lab=apollo-monitoring`.
- No hay Security Groups del laboratorio.
- No existe la key pair `apollo-lab-key`.

## Confirmacion necesaria

Para que Codex cree los recursos, responde explicitamente con una frase como:

```text
Confirmo crear las 2 EC2 en us-east-1 para el laboratorio Apollo Monitoring.
```

Despues de esa confirmacion se ejecutara:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\aws\create-ec2-lab.ps1 -KeyName "apollo-lab-key" -CreateKeyPair
```

