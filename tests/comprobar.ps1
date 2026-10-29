# Pruebas del lanzador. Se ejecutan en GitHub Actions antes de publicar.
#   pwsh ./tests/comprobar.ps1 -Bat ./Lanzador-scrcpy.bat
param([Parameter(Mandatory)] [string]$Bat)

$ErrorActionPreference = 'Stop'
$global:fallos = 0
function Bien([string]$t) { Write-Host "OK   $t" }
function Mal([string]$t)  { Write-Host "MAL  $t" -ForegroundColor Red; $global:fallos++ }

$ruta  = (Resolve-Path -LiteralPath $Bat).Path
$bytes = [IO.File]::ReadAllBytes($ruta)
$texto = [Text.Encoding]::ASCII.GetString($bytes)

# ---------- 1. Formato del archivo ----------
if (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) { Bien 'solo caracteres ASCII' } else { Mal 'hay caracteres no ASCII (cmd los romperia)' }
$lfSueltos = 0
for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $lfSueltos++ } }
if ($lfSueltos -eq 0) { Bien 'finales de linea de Windows (CRLF)' } else { Mal "$lfSueltos saltos de linea sin CR (hace falta CRLF)" }
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) { Mal 'empieza con BOM (cmd fallaria en la primera linea)' } else { Bien 'sin BOM' }
$lineas = $texto -split "`r`n"
if ($lineas[0].StartsWith('<# :')) { Bien 'primera linea: cabecera hibrida cmd/PowerShell' } else { Mal 'la primera linea debe empezar por "<# :"' }
$cierre = [array]::IndexOf($lineas, '#>')
if ($cierre -gt 0) { Bien 'bloque de cmd cerrado con #>' } else { Mal 'falta la linea "#>"' }
$lineaPs = $lineas | Where-Object { $_ -match '^powershell ' } | Select-Object -First 1
if ($lineaPs -and $lineaPs.TrimEnd().EndsWith('& exit /b')) { Bien 'cmd sale en la misma linea que lanza PowerShell' } else { Mal 'la linea de powershell debe terminar en "& exit /b"' }

# ---------- 2. El PowerShell se analiza sin errores ----------
$tokens = $null; $errores = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($texto, [ref]$tokens, [ref]$errores)
if ($errores.Count -eq 0) { Bien 'PowerShell sin errores de sintaxis' } else { foreach ($e in $errores) { Mal "sintaxis: $($e.Message) (linea $($e.Extent.StartLineNumber))" } }

# ---------- 3. Lectura de la IP (teclas simuladas) ----------
$env:LANZADOR_SIN_MAIN = '1'
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [IO.Path]::GetTempPath() }
$global:cola = New-Object System.Collections.Queue
$script:LeerTecla = {
    $c = [string]$global:cola.Dequeue(); $n = [int][char]$c
    $key = if ($n -eq 13) { [ConsoleKey]::Enter } elseif ($n -eq 8) { [ConsoleKey]::Backspace } elseif ($n -eq 27) { [ConsoleKey]::Escape } else { [ConsoleKey]::A }
    New-Object System.ConsoleKeyInfo ([char]$c), $key, $false, $false, $false
}
$ErrorActionPreference = 'Continue'
iex $texto
$ErrorActionPreference = 'Stop'

function Caso([string]$fija, $ultima, [string]$teclas, [string]$esperado) {
    $global:cola.Clear()
    foreach ($ch in $teclas.ToCharArray()) { $global:cola.Enqueue([string]$ch) }
    $r = Leer-IP $fija $ultima 6>$null
    $vista = $teclas -replace "`r", '<Enter>' -replace "`b", '<Retroceso>' -replace "`e", '<Esc>'
    if ($r -eq $esperado) { Bien "IP '$fija' + $vista -> $r" } else { Mal "IP '$fija' + $vista -> '$r' (esperado '$esperado')" }
}
Caso ''          $null          "1921681`r25`r"                    '192.168.1.25'
Caso ''          $null          "1921680`r150`r"                   '192.168.0.150'
Caso ''          $null          "10`r0`r0`r5`r"                    '10.0.0.5'
Caso ''          $null          "192.168.1.25`r"                   '192.168.1.25'
Caso ''          $null          "192.168.0.150`r"                  '192.168.0.150'
Caso ''          $null          "10.0.0.5`r"                       '10.0.0.5'
Caso ''          $null          "1 2 3 4`r"                        '1.2.3.4'
Caso ''          $null          "`r1921681`r25`r"                  '192.168.1.25'
Caso ''          '10.0.0.7'     "`r"                               '10.0.0.7'
Caso ''          $null          "300`b`b`b10`r0`r0`r1`r"           '10.0.0.1'
Caso ''          $null          "1921681`r2`b25`r"                 '192.168.1.25'
Caso ''          $null          "192168`b`b`b`b123`r5`r6`r"        '192.123.5.6'
Caso ''          $null          "1921681`r25.`r"                   '192.168.1.25'
Caso ''          $null          "1921681`r25555`r"                 '192.168.1.255'
Caso ''          $null          "123`e10`r0`r0`r9`r"               '10.0.0.9'
Caso ''          $null          "001002003`r4`r"                   '1.2.3.4'
Caso '192.168.0' $null          "150`r"                            '192.168.0.150'
Caso '192.168.0' '192.168.0.50' "`r"                               '192.168.0.50'
Caso '192.168.0' $null          "`b`b1`r7`r"                       '192.168.1.7'

# ---------- 4. Otras piezas ----------
$v = Version-De 'C:\scrcpy-win64-v5.0.2'
if ($v -eq [version]'5.0.2') { Bien 'version leida del nombre de la carpeta' } else { Mal "version de la carpeta: $v" }
if ((Version-De 'C:\scrcpy-win64-v5.10') -gt (Version-De 'C:\scrcpy-win64-v5.9')) { Bien '5.10 es mas nueva que 5.9' } else { Mal '5.10 no gana a 5.9' }

Write-Host ''
if ($global:fallos -gt 0) { Write-Host "FALLOS: $global:fallos" -ForegroundColor Red; exit 1 }
Write-Host 'Todo bien.' -ForegroundColor Green
exit 0
