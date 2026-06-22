param(
  [string]$OutputDocx = "docs\entrega-mudevops05-act3-final.docx",
  [string]$CaptureDir = "docs\capturas"
)

$ErrorActionPreference = "Stop"

function Escape-XmlText {
  param([AllowNull()][string]$Text)

  if ($null -eq $Text) {
    return ""
  }

  return [System.Security.SecurityElement]::Escape($Text)
}

function Write-TextFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function New-RunXml {
  param(
    [string]$Text,
    [switch]$Bold,
    [switch]$Italic,
    [string]$Font = "Calibri",
    [int]$SizeHalfPoints = 22,
    [string]$Color = "000000"
  )

  $boldXml = if ($Bold) { "<w:b/>" } else { "" }
  $italicXml = if ($Italic) { "<w:i/>" } else { "" }
  $escaped = Escape-XmlText $Text
  return "<w:r><w:rPr><w:rFonts w:ascii=`"$Font`" w:hAnsi=`"$Font`"/><w:sz w:val=`"$SizeHalfPoints`"/><w:color w:val=`"$Color`"/>$boldXml$italicXml</w:rPr><w:t xml:space=`"preserve`">$escaped</w:t></w:r>"
}

function New-ParagraphXml {
  param(
    [string]$Text = "",
    [string]$Style = "",
    [switch]$Bullet,
    [switch]$Bold,
    [switch]$Italic,
    [string]$Font = "Calibri",
    [int]$SizeHalfPoints = 22,
    [string]$Color = "000000",
    [string]$Shading = "",
    [string]$Alignment = "",
    [int]$Before = -1,
    [int]$After = -1,
    [int]$LeftIndent = 0,
    [switch]$KeepNext
  )

  $styleXml = if ($Style) { "<w:pStyle w:val=`"$Style`"/>" } else { "" }
  $bulletXml = if ($Bullet) { "<w:numPr><w:ilvl w:val=`"0`"/><w:numId w:val=`"1`"/></w:numPr>" } else { "" }
  $shadeXml = if ($Shading) { "<w:shd w:val=`"clear`" w:color=`"auto`" w:fill=`"$Shading`"/>" } else { "" }
  $alignXml = if ($Alignment) { "<w:jc w:val=`"$Alignment`"/>" } else { "" }
  $indentXml = if ($LeftIndent -gt 0) { "<w:ind w:left=`"$LeftIndent`"/>" } else { "" }
  $keepXml = if ($KeepNext) { "<w:keepNext/>" } else { "" }
  $spacingParts = New-Object System.Collections.Generic.List[string]
  if ($Before -ge 0) { $spacingParts.Add("w:before=`"$Before`"") }
  if ($After -ge 0) { $spacingParts.Add("w:after=`"$After`"") }
  $spacingXml = if ($spacingParts.Count -gt 0) { "<w:spacing $($spacingParts -join ' ')/>" } else { "" }

  return @"
<w:p>
  <w:pPr>$styleXml$bulletXml$shadeXml$alignXml$indentXml$keepXml$spacingXml</w:pPr>
  $(New-RunXml -Text $Text -Bold:$Bold -Italic:$Italic -Font $Font -SizeHalfPoints $SizeHalfPoints -Color $Color)
</w:p>
"@
}

function New-PageBreakXml {
  return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
}

function New-RuleXml {
  return @'
<w:p>
  <w:pPr>
    <w:pBdr><w:bottom w:val="single" w:sz="10" w:space="6" w:color="2E74B5"/></w:pBdr>
    <w:spacing w:after="240"/>
  </w:pPr>
</w:p>
'@
}

function New-CellXml {
  param(
    [string]$Text,
    [int]$Width,
    [switch]$Header,
    [string]$Fill = ""
  )

  $fillXml = if ($Fill) { "<w:shd w:val=`"clear`" w:color=`"auto`" w:fill=`"$Fill`"/>" } else { "" }
  $bold = $Header.IsPresent
  $paragraph = New-ParagraphXml -Text $Text -Bold:$bold -SizeHalfPoints 20 -After 60
  return @"
<w:tc>
  <w:tcPr><w:tcW w:w="$Width" w:type="dxa"/>$fillXml<w:vAlign w:val="center"/></w:tcPr>
  $paragraph
</w:tc>
"@
}

function New-TableXml {
  param(
    [object[]]$Rows,
    [int[]]$Widths,
    [switch]$HasHeader
  )

  if ($Rows.Count -eq 0) {
    return ""
  }

  $columnCount = $Widths.Count
  $grid = ($Widths | ForEach-Object { "<w:gridCol w:w=`"$_`"/>" }) -join ""
  $rowXml = New-Object System.Collections.Generic.List[string]

  for ($r = 0; $r -lt $Rows.Count; $r++) {
    $row = @($Rows[$r])
    if ($row.Count -eq 1 -and $row[0] -is [array]) {
      $row = @($row[0])
    }
    $cells = New-Object System.Collections.Generic.List[string]
    for ($c = 0; $c -lt $columnCount; $c++) {
      $value = if ($c -lt $row.Count) { [string]$row[$c] } else { "" }
      $isHeader = ($HasHeader -and $r -eq 0)
      $fill = if ($isHeader) { "F2F4F7" } else { "" }
      $cells.Add((New-CellXml -Text $value -Width $Widths[$c] -Header:$isHeader -Fill $fill))
    }
    $rowXml.Add("<w:tr>$($cells -join '')</w:tr>")
  }

  return @"
<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9360" w:type="dxa"/>
    <w:tblInd w:w="120" w:type="dxa"/>
    <w:tblLayout w:type="fixed"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
      <w:left w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
      <w:right w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="D9DEE7"/>
    </w:tblBorders>
    <w:tblCellMar>
      <w:top w:w="80" w:type="dxa"/>
      <w:left w:w="120" w:type="dxa"/>
      <w:bottom w:w="80" w:type="dxa"/>
      <w:right w:w="120" w:type="dxa"/>
    </w:tblCellMar>
  </w:tblPr>
  <w:tblGrid>$grid</w:tblGrid>
  $($rowXml -join "`n")
</w:tbl>
<w:p><w:pPr><w:spacing w:after="160"/></w:pPr></w:p>
"@
}

$script:body = New-Object System.Collections.Generic.List[string]
$script:imageEntries = New-Object System.Collections.Generic.List[object]
$script:imageCounter = 0

function Add-Paragraph {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text))
}

function Add-Heading1 {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text -Style "Heading1" -Bold -Color "2E74B5" -SizeHalfPoints 32 -KeepNext))
}

function Add-Heading2 {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text -Style "Heading2" -Bold -Color "2E74B5" -SizeHalfPoints 26 -KeepNext))
}

function Add-Heading3 {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text -Style "Heading3" -Bold -Color "1F4D78" -SizeHalfPoints 24 -KeepNext))
}

function Add-Bullet {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text -Bullet))
}

function Add-Callout {
  param([string]$Text)
  $script:body.Add((New-ParagraphXml -Text $Text -Shading "F4F6F9" -LeftIndent 180 -After 180))
}

function Add-Table {
  param(
    [object[]]$Rows,
    [int[]]$Widths,
    [switch]$HasHeader
  )
  $script:body.Add((New-TableXml -Rows $Rows -Widths $Widths -HasHeader:$HasHeader))
}

function Add-PageBreak {
  $script:body.Add((New-PageBreakXml))
}

function Add-Figure {
  param(
    [string]$ImagePath,
    [string]$Caption,
    [string]$AltText
  )

  $absoluteImagePath = (Resolve-Path $ImagePath).Path
  $script:imageCounter++
  $imageId = $script:imageCounter
  $relationshipId = "rIdImage$imageId"
  $targetName = "image$imageId.png"
  $script:imageEntries.Add([PSCustomObject]@{
    Source = $absoluteImagePath
    Target = $targetName
    RelationshipId = $relationshipId
  })

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Image]::FromFile($absoluteImagePath)
  try {
    $widthPx = $image.Width
    $heightPx = $image.Height
  } finally {
    $image.Dispose()
  }

  $emuPerInch = 914400
  $maxWidthEmu = [int64](6.3 * $emuPerInch)
  $maxHeightEmu = [int64](7.0 * $emuPerInch)
  $cx = $maxWidthEmu
  $cy = [int64]([double]$maxWidthEmu * ([double]$heightPx / [double]$widthPx))
  if ($cy -gt $maxHeightEmu) {
    $cy = $maxHeightEmu
    $cx = [int64]([double]$maxHeightEmu * ([double]$widthPx / [double]$heightPx))
  }

  $escapedName = Escape-XmlText (Split-Path -Leaf $absoluteImagePath)
  $escapedAlt = Escape-XmlText $AltText
  $captionText = Escape-XmlText $Caption

  $script:body.Add(@"
<w:p>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="80" w:after="80"/></w:pPr>
  <w:r>
    <w:drawing>
      <wp:inline distT="0" distB="0" distL="0" distR="0">
        <wp:extent cx="$cx" cy="$cy"/>
        <wp:effectExtent l="0" t="0" r="0" b="0"/>
        <wp:docPr id="$imageId" name="$escapedName" descr="$escapedAlt"/>
        <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
        <a:graphic>
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:pic>
              <pic:nvPicPr>
                <pic:cNvPr id="$imageId" name="$escapedName"/>
                <pic:cNvPicPr/>
              </pic:nvPicPr>
              <pic:blipFill>
                <a:blip r:embed="$relationshipId"/>
                <a:stretch><a:fillRect/></a:stretch>
              </pic:blipFill>
              <pic:spPr>
                <a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
                <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
              </pic:spPr>
            </pic:pic>
          </a:graphicData>
        </a:graphic>
      </wp:inline>
    </w:drawing>
  </w:r>
</w:p>
<w:p>
  <w:pPr><w:pStyle w:val="Caption"/><w:jc w:val="center"/><w:spacing w:after="180"/></w:pPr>
  <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:i/><w:color w:val="555555"/><w:sz w:val="18"/></w:rPr><w:t>$captionText</w:t></w:r>
</w:p>
"@)
}

$capturePath = (Resolve-Path $CaptureDir).Path
$fig = @{
  AwsState = Join-Path $capturePath "aws-01-creacion-estado.png"
  AwsInstances = Join-Path $capturePath "aws-02-instancias-launchtime.png"
  AwsSecurity = Join-Path $capturePath "aws-03-security-groups.png"
  AwsVolumes = Join-Path $capturePath "aws-04-volumenes-keypair.png"
  ObservabilityDocker = Join-Path $capturePath "observability-01-docker.png"
  ObservabilityHealth = Join-Path $capturePath "observability-02-health-indices.png"
  ApmAggs = Join-Path $capturePath "observability-03-apm-aggs.png"
  ApolloDocker = Join-Path $capturePath "apollo-01-docker.png"
  ApolloGraphql = Join-Path $capturePath "apollo-02-graphql.png"
  ApolloConnectivity = Join-Path $capturePath "apollo-03-conectividad.png"
}

foreach ($path in $fig.Values) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing capture image: $path. Run scripts\generate-report-captures.ps1 first."
  }
}

$metadataRows = @()
$metadataRows += ,@("Entrega", "MUDevOps05 - Actividad 3")
$metadataRows += ,@("Region AWS", "us-east-1")
$metadataRows += ,@("Instancia Apollo", "i-0059be81271436a9a | t3.small | 54.224.96.172")
$metadataRows += ,@("Instancia Observability", "i-0428b222902b16db4 | t3.medium | 34.229.213.242")
$metadataRows += ,@("Fecha de creacion", "2026-06-21 21:58 America/Bogota / 2026-06-22 02:58 UTC")
$metadataRows += ,@("URLs de validacion", "Apollo: http://54.224.96.172/ | Kibana: http://34.229.213.242:5601")

$script:body.Add((New-ParagraphXml -Text "Informe tecnico de laboratorio" -Style "Kicker" -Bold -Color "1F4D78" -SizeHalfPoints 22 -After 80))
$script:body.Add((New-ParagraphXml -Text "Monitorizacion de un despliegue de Apollo Server" -Style "Title" -Bold -Color "0B2545" -SizeHalfPoints 42 -After 80))
$script:body.Add((New-ParagraphXml -Text "Apollo Server + Elastic Stack/APM sobre dos instancias EC2 en AWS" -Style "Subtitle" -Color "555555" -SizeHalfPoints 26 -After 240))
Add-Table -Rows $metadataRows -Widths @(2300, 7060)
$script:body.Add((New-RuleXml))
Add-Callout "Resultado del laboratorio: se crearon dos instancias EC2 en us-east-1, se desplego Apollo Server detras de Nginx y se activo Elastic Stack con Elasticsearch, Kibana, Logstash, APM Server, Filebeat y Metricbeat. La validacion muestra Apollo respondiendo GetBooks, Kibana en estado green e indices de APM, metricas y logs creados en Elasticsearch."
Add-PageBreak

Add-Heading1 "1. Objetivo y alcance"
Add-Paragraph "El objetivo de la practica es desplegar un Apollo Server de ejemplo en AWS y monitorizarlo con Elastic Stack. La solucion separa la aplicacion y la observabilidad en dos instancias EC2 para medir de forma independiente el consumo y la salud de cada capa."
Add-Paragraph "La pila usa Elastic 7.9.3 para alinearse con la guia base de APM Server indicada en el enunciado. En un entorno productivo se recomienda actualizar a una version soportada y considerar Elastic Agent/Fleet, pero para esta actividad se conserva la version solicitada."

$componentRows = @()
$componentRows += ,@("Capa", "Componentes", "Evidencia principal")
$componentRows += ,@("AWS", "EC2, EBS, Security Groups, key pair", "LaunchTime, estado running, volumenes in-use y SG creados")
$componentRows += ,@("Aplicacion", "Apollo Server, Nginx, elastic-apm-node", "Query GetBooks y health OK")
$componentRows += ,@("Observabilidad", "Elasticsearch, Kibana, Logstash, APM Server", "Cluster green, indices apm-* y logs")
$componentRows += ,@("Agentes", "Filebeat y Metricbeat", "Metricas system/docker/nginx y logs centralizados")
Add-Table -Rows $componentRows -Widths @(1700, 3600, 4060) -HasHeader

Add-Heading1 "2. Evidencia AWS desde la creacion"
Add-Paragraph "Las capturas de esta seccion se generaron desde AWS CLI con el usuario IAM disponible para el laboratorio. CloudTrail no estaba autorizado para este usuario, por lo que la evidencia de creacion se basa en los metadatos oficiales de EC2: LaunchTime, IDs de instancia, key pair, security groups y volumenes EBS."
Add-Figure -ImagePath $fig.AwsState -Caption "Figura 1. Estado general del laboratorio: identidad AWS, EC2 running, EBS, Security Groups y key pair." -AltText "Captura AWS CLI con estado de laboratorio Apollo Monitoring"
Add-Figure -ImagePath $fig.AwsInstances -Caption "Figura 2. Instancias EC2 creadas en us-east-1 con LaunchTime, IP publica, IP privada y tipo." -AltText "Captura AWS CLI describe-instances con LaunchTime"
Add-Figure -ImagePath $fig.AwsSecurity -Caption "Figura 3. Security Groups creados para la instancia Apollo y la instancia Observability." -AltText "Captura AWS CLI describe-security-groups"
Add-Figure -ImagePath $fig.AwsVolumes -Caption "Figura 4. Volumenes EBS asociados y key pair apollo-lab-key." -AltText "Captura AWS CLI de volumenes EBS y key pair"

Add-Heading1 "3. Criterio 1: templates de instalacion"
Add-Heading2 "3.1 Infraestructura AWS"
Add-Paragraph "El laboratorio puede crearse con CloudFormation o con el script EC2 directo. En esta ejecucion se uso el aprovisionamiento directo por EC2 porque permite controlar la zona de disponibilidad compatible con los tipos t3.small y t3.medium."
Add-Bullet "Instancia apollo-monitoring-app: aloja Apollo Server, Nginx, Filebeat y Metricbeat."
Add-Bullet "Instancia apollo-monitoring-observability: aloja Elasticsearch, Kibana, Logstash, APM Server y Metricbeat."
Add-Bullet "Security Groups separados: uno para el borde HTTP/Apollo y otro para la plataforma de observabilidad."
Add-Bullet "Comunicacion privada entre Apollo y Observability para APM Server, Logstash y Elasticsearch."

Add-Heading2 "3.2 Elastic Stack, Logstash y APM"
Add-Paragraph "El template docker-compose.elastic.yml despliega Elasticsearch, Kibana, Logstash, APM Server y Metricbeat. Logstash recibe eventos de Filebeat y separa logs de Nginx y Apollo en indices diarios."
Add-Figure -ImagePath $fig.ObservabilityDocker -Caption "Figura 5. Contenedores de Elastic Stack activos en la instancia Observability." -AltText "Docker Compose ps de Elastic Stack"
Add-Figure -ImagePath $fig.ObservabilityHealth -Caption "Figura 6. Elasticsearch green e indices apm-*, metricbeat-*, nginx.access-* y apollo.application-*." -AltText "Salud de Elasticsearch e indices de observabilidad"

Add-Heading2 "3.3 Apollo Server y Nginx"
Add-Paragraph "La aplicacion implementa el ejemplo de Apollo Server con queries books, book, health y slowBooks. Nginx funciona como proxy reverso en el puerto 80 y emite logs JSON para ser procesados por Filebeat y Logstash."
Add-Figure -ImagePath $fig.ApolloDocker -Caption "Figura 7. Contenedores Apollo Server, Nginx, Filebeat y Metricbeat activos en la instancia de aplicacion." -AltText "Docker Compose ps de Apollo Server"
Add-Figure -ImagePath $fig.ApolloGraphql -Caption "Figura 8. Validacion funcional de la query GetBooks contra Apollo Server." -AltText "Respuesta GraphQL GetBooks de Apollo Server"

Add-Heading1 "4. Criterio 2: Beats y justificacion"
$beatsRows = @()
$beatsRows += ,@("Componente", "Ubicacion", "Datos recolectados", "Justificacion")
$beatsRows += ,@("Filebeat", "Instancia Apollo", "Logs JSON de Nginx y logs de aplicacion Apollo", "Ligero y orientado a transporte de logs hacia Logstash para normalizar campos.")
$beatsRows += ,@("Metricbeat", "Ambas instancias", "CPU, RAM, filesystem, procesos, Docker y Nginx stub_status", "Cubre la rubrica de CPU/RAM y permite comparar host y contenedores.")
$beatsRows += ,@("APM Agent Node.js", "Apollo Server", "Transacciones, spans, errores y labels GraphQL", "Permite analizar latencia, throughput y errores por operacion GraphQL.")
Add-Table -Rows $beatsRows -Widths @(1500, 1800, 2900, 3160) -HasHeader
Add-Figure -ImagePath $fig.ApmAggs -Caption "Figura 9. Agregacion APM: servicio apollo-server con eventos transaction, metric, span y error." -AltText "Agregacion de APM en Elasticsearch para apollo-server"

Add-Heading1 "5. Criterio 3: estrategia de monitorizacion"
Add-Heading2 "5.1 Dashboard de infraestructura"
Add-Bullet "CPU total, load average y memoria disponible por host."
Add-Bullet "Uso de disco y filesystem para detectar saturacion de EBS."
Add-Bullet "CPU/RAM por contenedor Docker para diferenciar consumo de Apollo, Nginx, Beats y Elastic Stack."
Add-Bullet "Alertas recomendadas: CPU mayor a 80% por 5 minutos, RAM disponible menor a 15% y disco usado mayor a 85%."

Add-Heading2 "5.2 Dashboard APM GraphQL"
Add-Bullet "Throughput de transacciones por minuto."
Add-Bullet "Latencia p50, p95 y p99 por operacion GraphQL."
Add-Bullet "Tasa de errores y trazas lentas, incluyendo slowBooks para simular latencia."
Add-Bullet "Alertas recomendadas: p95 mayor a 1 segundo y error rate mayor a 5%."

Add-Heading2 "5.3 Dashboard de logs y borde HTTP"
Add-Bullet "Conteo de status codes 2xx, 4xx y 5xx desde nginx.access-*."
Add-Bullet "Top URIs solicitadas y promedio/p95 de request_time."
Add-Bullet "Eventos internos de Apollo por nivel desde apollo.application-*."
Add-Bullet "Relacion entre errores de aplicacion, errores HTTP y trazas APM."

Add-Heading1 "6. Validacion operativa"
Add-Paragraph "La validacion confirma que la aplicacion se comunica por red privada con Observability, que APM Server responde desde la instancia Apollo y que Kibana esta disponible para revisar los datos."
Add-Figure -ImagePath $fig.ApolloConnectivity -Caption "Figura 10. Conectividad privada desde Apollo hacia APM Server, Elasticsearch y Kibana." -AltText "Validacion de conectividad entre Apollo y Observability"

$validationRows = @()
$validationRows += ,@("Prueba", "Resultado")
$validationRows += ,@("Apollo GetBooks", "Devuelve cuatro libros desde la query GraphQL.")
$validationRows += ,@("Elasticsearch", "Cluster health green en la instancia Observability.")
$validationRows += ,@("APM", "Indices apm-* creados y servicio apollo-server presente.")
$validationRows += ,@("Logs", "Indices nginx.access-* y apollo.application-* presentes.")
$validationRows += ,@("Metricas", "Indice metricbeat-7.9.3 creado con eventos de sistema/Docker.")
Add-Table -Rows $validationRows -Widths @(2600, 6760) -HasHeader

Add-Heading1 "7. Conclusiones y limpieza"
Add-Paragraph "La solucion cubre tres capas de observabilidad: infraestructura con Metricbeat, aplicacion con Elastic APM y logs con Filebeat + Logstash. Esta separacion permite diagnosticar si un problema nace en el host EC2, en Apollo GraphQL o en el borde HTTP de Nginx."
Add-Paragraph "Cuando ya no se necesiten las evidencias, se debe eliminar el laboratorio para evitar costes de EC2 y EBS. El comando preparado para limpieza es:"
$script:body.Add((New-ParagraphXml -Text "powershell -ExecutionPolicy Bypass -File .\scripts\aws\delete-ec2-lab.ps1 -DeleteSecurityGroups" -Style "Code" -Font "Consolas" -SizeHalfPoints 18 -Shading "F4F6F9" -LeftIndent 240))

Add-Heading1 "8. Fuentes y archivos de soporte"
Add-Bullet "Apollo Server Get Started: https://www.apollographql.com/docs/apollo-server/getting-started/"
Add-Bullet "Elastic APM Server 7.9: https://www.elastic.co/guide/en/apm/server/7.9/getting-started-apm-server.html"
Add-Bullet "Elastic APM Node.js Agent: https://www.elastic.co/docs/reference/apm/agents/nodejs/starting-agent"
Add-Bullet "Metricbeat System module: https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-module-system"
Add-Bullet "Filebeat Nginx module: https://www.elastic.co/docs/reference/beats/filebeat/filebeat-module-nginx"
Add-Bullet "Repositorio local: README.md, docker-compose.apollo.yml, docker-compose.elastic.yml, scripts/aws y docs/capturas."

$outputPath = Join-Path (Get-Location) $OutputDocx
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$tempRoot = Join-Path $env:TEMP "apollo-final-docx-$([guid]::NewGuid())"
$docxZip = Join-Path $env:TEMP "apollo-final-docx-$([guid]::NewGuid()).zip"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
  Write-TextFile (Join-Path $tempRoot "[Content_Types].xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
'@

  Write-TextFile (Join-Path $tempRoot "_rels\.rels") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
'@

  $imageRelationships = ($script:imageEntries | ForEach-Object {
    "  <Relationship Id=`"$($_.RelationshipId)`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image`" Target=`"media/$($_.Target)`"/>"
  }) -join "`n"

  Write-TextFile (Join-Path $tempRoot "word\_rels\document.xml.rels") @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
$imageRelationships
</Relationships>
"@

  Write-TextFile (Join-Path $tempRoot "docProps\core.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Monitorizacion de un despliegue de Apollo Server</dc:title>
  <dc:subject>MUDevOps05 Act. 3</dc:subject>
  <dc:creator>Codex</dc:creator>
  <cp:lastModifiedBy>Codex</cp:lastModifiedBy>
</cp:coreProperties>
'@

  Write-TextFile (Join-Path $tempRoot "docProps\app.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Codex OOXML Builder</Application>
</Properties>
'@

  Write-TextFile (Join-Path $tempRoot "word\styles.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:color w:val="000000"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:after="160"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="0B2545"/><w:sz w:val="42"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:after="240"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="555555"/><w:sz w:val="26"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Kicker">
    <w:name w:val="Kicker"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:after="80"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="1F4D78"/><w:sz w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="320" w:after="160"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="2E74B5"/><w:sz w:val="32"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="2E74B5"/><w:sz w:val="26"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="1F4D78"/><w:sz w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Caption">
    <w:name w:val="Caption"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:after="180"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:i/><w:color w:val="555555"/><w:sz w:val="18"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="40" w:after="80"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr>
  </w:style>
</w:styles>
'@

  Write-TextFile (Join-Path $tempRoot "word\numbering.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="1">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="-"/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>
'@

  Write-TextFile (Join-Path $tempRoot "word\header1.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr><w:pBdr><w:bottom w:val="single" w:sz="4" w:space="1" w:color="D9DEE7"/></w:pBdr><w:spacing w:after="80"/></w:pPr>
    <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="555555"/><w:sz w:val="18"/></w:rPr><w:t>MUDevOps05 Act. 3 | Apollo Monitoring Lab</w:t></w:r>
  </w:p>
</w:hdr>
'@

  Write-TextFile (Join-Path $tempRoot "word\footer1.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr><w:jc w:val="right"/></w:pPr>
    <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="777777"/><w:sz w:val="18"/></w:rPr><w:t>Pagina </w:t></w:r>
    <w:fldSimple w:instr="PAGE"><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="777777"/><w:sz w:val="18"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>
  </w:p>
</w:ftr>
'@

  New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "word\media") | Out-Null
  foreach ($entry in $script:imageEntries) {
    Copy-Item -LiteralPath $entry.Source -Destination (Join-Path (Join-Path $tempRoot "word\media") $entry.Target) -Force
  }

  $bodyXml = $script:body -join "`n"
  Write-TextFile (Join-Path $tempRoot "word\document.xml") @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    $bodyXml
    <w:sectPr>
      <w:headerReference w:type="default" r:id="rId3"/>
      <w:footerReference w:type="default" r:id="rId4"/>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
      <w:cols w:space="708"/>
      <w:docGrid w:linePitch="360"/>
    </w:sectPr>
  </w:body>
</w:document>
"@

  if (Test-Path -LiteralPath $docxZip) {
    Remove-Item -LiteralPath $docxZip -Force
  }
  if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $tempRootFull = (Get-Item -LiteralPath $tempRoot).FullName
  $tempRootPrefixRegex = '^' + [regex]::Escape($tempRootFull + [System.IO.Path]::DirectorySeparatorChar)
  $zipStream = [System.IO.File]::Open($docxZip, [System.IO.FileMode]::CreateNew)
  try {
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
      foreach ($file in Get-ChildItem -LiteralPath $tempRoot -Recurse -File) {
        $relative = ($file.FullName -replace $tempRootPrefixRegex, '').Replace('\', '/')
        $entry = $archive.CreateEntry($relative)
        $entryStream = $entry.Open()
        try {
          $fileStream = [System.IO.File]::OpenRead($file.FullName)
          try {
            $fileStream.CopyTo($entryStream)
          } finally {
            $fileStream.Dispose()
          }
        } finally {
          $entryStream.Dispose()
        }
      }
    } finally {
      $archive.Dispose()
    }
  } finally {
    $zipStream.Dispose()
  }

  Move-Item -LiteralPath $docxZip -Destination $outputPath -Force
  Write-Host "DOCX created: $outputPath"
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $docxZip -Force -ErrorAction SilentlyContinue
}
