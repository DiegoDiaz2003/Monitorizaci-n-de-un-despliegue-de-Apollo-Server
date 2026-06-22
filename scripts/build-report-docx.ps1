param(
  [string]$InputMarkdown = "docs\entrega-mudevops05-act3.md",
  [string]$OutputDocx = "docs\entrega-mudevops05-act3.docx"
)

$ErrorActionPreference = "Stop"

function Escape-XmlText {
  param([AllowNull()][string]$Text)

  if ($null -eq $Text) {
    return ""
  }

  return [System.Security.SecurityElement]::Escape($Text)
}

function Convert-MarkdownInline {
  param([string]$Text)

  return ($Text -replace '`', "")
}

function Split-MarkdownTableRow {
  param([string]$Line)

  $trimmed = $Line.Trim()
  if ($trimmed.StartsWith('|')) {
    $trimmed = $trimmed.Substring(1)
  }
  if ($trimmed.EndsWith('|')) {
    $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
  }

  return @($trimmed -split '\|' | ForEach-Object { (Convert-MarkdownInline $_.Trim()) })
}

function Is-MarkdownTableSeparator {
  param([string]$Line)

  return ($Line.Trim() -match '^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$')
}

function New-RunXml {
  param(
    [string]$Text,
    [switch]$Bold,
    [string]$Font = "Calibri",
    [int]$SizeHalfPoints = 22,
    [string]$Color = "000000"
  )

  $boldXml = if ($Bold) { "<w:b/>" } else { "" }
  $escaped = Escape-XmlText $Text
  return "<w:r><w:rPr><w:rFonts w:ascii=`"$Font`" w:hAnsi=`"$Font`"/><w:sz w:val=`"$SizeHalfPoints`"/><w:color w:val=`"$Color`"/>$boldXml</w:rPr><w:t xml:space=`"preserve`">$escaped</w:t></w:r>"
}

function New-ParagraphXml {
  param(
    [string]$Text = "",
    [string]$Style = "",
    [switch]$Bullet,
    [switch]$Bold,
    [string]$Font = "Calibri",
    [int]$SizeHalfPoints = 22,
    [string]$Color = "000000",
    [string]$Shading = "",
    [int]$LeftIndent = 0
  )

  $styleXml = if ($Style) { "<w:pStyle w:val=`"$Style`"/>" } else { "" }
  $bulletXml = if ($Bullet) { "<w:numPr><w:ilvl w:val=`"0`"/><w:numId w:val=`"1`"/></w:numPr>" } else { "" }
  $shadeXml = if ($Shading) { "<w:shd w:val=`"clear`" w:color=`"auto`" w:fill=`"$Shading`"/>" } else { "" }
  $indentXml = if ($LeftIndent -gt 0) { "<w:ind w:left=`"$LeftIndent`"/>" } else { "" }

  return @"
<w:p>
  <w:pPr>$styleXml$bulletXml$shadeXml$indentXml<w:spacing w:after="120"/></w:pPr>
  $(New-RunXml -Text $Text -Bold:$Bold -Font $Font -SizeHalfPoints $SizeHalfPoints -Color $Color)
</w:p>
"@
}

function New-TableXml {
  param([array]$Rows)

  if ($Rows.Count -eq 0) {
    return ""
  }

  $columnCount = ($Rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
  if ($columnCount -lt 1) {
    return ""
  }

  $columnWidth = [int][Math]::Floor(9360 / $columnCount)
  $grid = (($Rows[0] | Select-Object -First $columnCount) | ForEach-Object { "<w:gridCol w:w=`"$columnWidth`"/>" }) -join ""
  if ([string]::IsNullOrWhiteSpace($grid)) {
    $grid = (1..$columnCount | ForEach-Object { "<w:gridCol w:w=`"$columnWidth`"/>" }) -join ""
  }

  $rowXml = New-Object System.Collections.Generic.List[string]
  for ($r = 0; $r -lt $Rows.Count; $r++) {
    $cellXml = New-Object System.Collections.Generic.List[string]
    for ($c = 0; $c -lt $columnCount; $c++) {
      $value = ""
      if ($c -lt $Rows[$r].Count) {
        $value = $Rows[$r][$c]
      }

      $fill = if ($r -eq 0) { "<w:shd w:val=`"clear`" w:color=`"auto`" w:fill=`"F2F4F7`"/>" } else { "" }
      $bold = if ($r -eq 0) { $true } else { $false }
      $paragraph = New-ParagraphXml -Text $value -Bold:$bold -SizeHalfPoints 20
      $cellXml.Add(@"
<w:tc>
  <w:tcPr><w:tcW w:w="$columnWidth" w:type="dxa"/>$fill<w:vAlign w:val="center"/></w:tcPr>
  $paragraph
</w:tc>
"@)
    }
    $rowXml.Add("<w:tr>$($cellXml -join '')</w:tr>")
  }

  return @"
<w:tbl>
  <w:tblPr>
    <w:tblW w:w="9360" w:type="dxa"/>
    <w:tblInd w:w="120" w:type="dxa"/>
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
<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>
"@
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

$inputPath = (Resolve-Path $InputMarkdown).Path
$outputPath = Join-Path (Get-Location) $OutputDocx
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$lines = Get-Content -LiteralPath $inputPath -Encoding UTF8
$body = New-Object System.Collections.Generic.List[string]
$tableRows = New-Object System.Collections.Generic.List[object]
$codeLines = New-Object System.Collections.Generic.List[string]
$inCodeBlock = $false
$isFirstTitle = $true

function Flush-Table {
  if ($tableRows.Count -gt 0) {
    $body.Add((New-TableXml ($tableRows.ToArray())))
    $tableRows.Clear()
  }
}

function Flush-Code {
  if ($codeLines.Count -gt 0) {
    foreach ($codeLine in $codeLines) {
      $body.Add((New-ParagraphXml -Text $codeLine -Style "Code" -Font "Consolas" -SizeHalfPoints 18 -Shading "F4F6F9" -LeftIndent 240))
    }
    $body.Add((New-ParagraphXml -Text ""))
    $codeLines.Clear()
  }
}

foreach ($line in $lines) {
  if ($line.Trim().StartsWith('```')) {
    if ($inCodeBlock) {
      Flush-Code
      $inCodeBlock = $false
    } else {
      Flush-Table
      $inCodeBlock = $true
    }
    continue
  }

  if ($inCodeBlock) {
    $codeLines.Add($line)
    continue
  }

  if ($line.Trim().Length -eq 0) {
    Flush-Table
    $body.Add((New-ParagraphXml -Text ""))
    continue
  }

  if ($line.Trim().StartsWith('|')) {
    if (-not (Is-MarkdownTableSeparator $line)) {
      $tableRows.Add((Split-MarkdownTableRow $line))
    }
    continue
  }

  Flush-Table

  if ($line.StartsWith("# ")) {
    $text = $line.Substring(2).Trim()
    if ($isFirstTitle) {
      $body.Add((New-ParagraphXml -Text $text -Style "Title" -Bold -SizeHalfPoints 40 -Color "1F4D78"))
      $isFirstTitle = $false
    } else {
      $body.Add((New-ParagraphXml -Text $text -Style "Heading1" -Bold -SizeHalfPoints 32 -Color "2E74B5"))
    }
  } elseif ($line.StartsWith("## ")) {
    $body.Add((New-ParagraphXml -Text $line.Substring(3).Trim() -Style "Heading1" -Bold -SizeHalfPoints 32 -Color "2E74B5"))
  } elseif ($line.StartsWith("### ")) {
    $body.Add((New-ParagraphXml -Text $line.Substring(4).Trim() -Style "Heading2" -Bold -SizeHalfPoints 26 -Color "2E74B5"))
  } elseif ($line.StartsWith("#### ")) {
    $body.Add((New-ParagraphXml -Text $line.Substring(5).Trim() -Style "Heading3" -Bold -SizeHalfPoints 24 -Color "1F4D78"))
  } elseif ($line.TrimStart().StartsWith("- ")) {
    $body.Add((New-ParagraphXml -Text $line.TrimStart().Substring(2).Trim() -Bullet))
  } else {
    $body.Add((New-ParagraphXml -Text $line.Trim()))
  }
}

Flush-Table
Flush-Code

$tempRoot = Join-Path $env:TEMP "apollo-docx-$([guid]::NewGuid())"
$docxZip = Join-Path $env:TEMP "apollo-docx-$([guid]::NewGuid()).zip"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
  Write-TextFile (Join-Path $tempRoot "[Content_Types].xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
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

  Write-TextFile (Join-Path $tempRoot "word\_rels\document.xml.rels") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>
'@

  Write-TextFile (Join-Path $tempRoot "docProps\core.xml") @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Monitorizacion de un despliegue de Apollo Server</dc:title>
  <dc:subject>MUDevOps05 Act. 3</dc:subject>
  <dc:creator>TechOps Solutions</dc:creator>
  <cp:lastModifiedBy>TechOps Solutions</cp:lastModifiedBy>
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
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:spacing w:after="240"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:color w:val="1F4D78"/><w:sz w:val="40"/></w:rPr>
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
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr>
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

  $bodyXml = $body -join "`n"
  Write-TextFile (Join-Path $tempRoot "word\document.xml") @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $bodyXml
    <w:sectPr>
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
