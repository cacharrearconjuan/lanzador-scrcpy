<# : parte de cmd: arranca PowerShell con el resto de este mismo archivo
@echo off
setlocal
title Lanzador de scrcpy
color 0b
set "LANZADOR_BAT=%~f0"
:: Se sale de la carpeta del .bat: si estuviera dentro de scrcpy, Windows no dejaria renombrarla
cd /d "%TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:LANZADOR_BAT))" & exit /b
#>

$VersionLanzador = 'dev'   # al publicar en GitHub se pone el numero de version

# ======================= AJUSTES (cambia aqui lo que quieras) =======================
# Parte fija de la IP. Vacio ('') = se escribe la IP entera.
$RedFija    = ''
$Puerto     = 5555
# Opciones de scrcpy. Si con la v5 la imagen sale negra, a trozos o con tirones,
# anade '--hwdec=disabled' (decodifica con la CPU, como antes de la v5).
$Opciones   = @('--video-bit-rate=2M', '--max-size=1024', '--no-audio')
# scrcpy se instala en BuscarEn, en una carpeta cuyo nombre empieza por Prefijo
# (por ejemplo C:\scrcpy-win64-v5.0.1). Las versiones viejas quedan como old_...
$BuscarEn   = 'C:\'
$Prefijo    = 'scrcpy'
# $false = no buscar actualizaciones en GitHub al arrancar.
$Actualizar = $true
# $true = si la variable ADB guardada en Windows apunta a otra carpeta, se corrige
# para siempre. Con $false solo se corrige mientras dura este lanzador.
$CorregirVariableADB = $false
# $true = al terminar, este .bat se copia dentro de la carpeta de scrcpy que se usa
# (asi, tras actualizar, tambien esta en la carpeta nueva).
$CopiarALaCarpeta = $true
# ====================================================================================

$ProgressPreference = 'SilentlyContinue'
# Se guarda una copia del .bat en memoria antes de nada (por si su carpeta pasa a old_)
$BytesBat = $null
try { $BytesBat = [IO.File]::ReadAllBytes($env:LANZADOR_BAT) } catch {}
try { Set-Location -LiteralPath $env:TEMP } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Lanzador de scrcpy' } catch {}

$Repo        = 'Genymobile/scrcpy'
$CarpetaDato = Join-Path $env:LOCALAPPDATA 'LanzadorScrcpy'
$ArchivoIP   = Join-Path $CarpetaDato 'ultima_ip.txt'
if (-not $script:LeerTecla) { $script:LeerTecla = { [Console]::ReadKey($true) } }

function Escribe([string]$texto, [string]$color = 'Gray') { Write-Host $texto -ForegroundColor $color }

function Pausa([string]$texto = 'Pulsa una tecla para salir...') {
    Write-Host $texto
    [void](& $script:LeerTecla)
}

# ---------- Versiones ----------
function Version-De([string]$dir) {
    $nombre = Split-Path $dir -Leaf
    if ($nombre -match 'v(\d+(\.\d+)+)') { try { return [version]$Matches[1] } catch {} }
    try {
        $linea = & (Join-Path $dir 'scrcpy.exe') --version 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1
        if ($linea -match 'scrcpy\s+v?(\d+(\.\d+)+)') { return [version]$Matches[1] }
    } catch {}
    return [version]'0.0'
}

function Buscar-Instalado {
    $exes = Get-ChildItem -LiteralPath $BuscarEn -Directory -Filter "$Prefijo*" -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'scrcpy.exe' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'adb.exe') }
    $lista = foreach ($e in $exes) {
        [pscustomobject]@{ Dir = $e.DirectoryName; Version = (Version-De $e.DirectoryName); Fecha = $e.LastWriteTime }
    }
    $lista | Sort-Object Version, Fecha -Descending | Select-Object -First 1
}

function Ultima-Publicada {
    $arq = 'win64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $arq = 'winarm64' }
    elseif (-not [Environment]::Is64BitOperatingSystem) { $arq = 'win32' }

    $tag = $null
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $tag = [string]$r.tag_name
    } catch {}
    if (-not $tag) {
        # Plan B: la pagina "latest" redirige a /releases/tag/vX.Y.Z
        try {
            $w = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            $url = $null
            if ($w.BaseResponse.ResponseUri) { $url = $w.BaseResponse.ResponseUri.AbsoluteUri }
            elseif ($w.BaseResponse.RequestMessage) { $url = $w.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
            if ($url -match '/tag/([^/?#]+)') { $tag = $Matches[1] }
        } catch {}
    }
    if (-not $tag) { return $null }
    if ($tag -notmatch '^v?(\d+(\.\d+)+)$') { return $null }
    $ver  = [version]$Matches[1]
    $base = "https://github.com/$Repo/releases/download/$tag"
    $zips = @("scrcpy-$arq-$tag.zip")
    if ($arq -eq 'winarm64') { $zips += "scrcpy-win64-$tag.zip" }
    [pscustomobject]@{ Tag = $tag; Version = $ver; Base = $base; Zips = $zips }
}

# ---------- Instalacion ----------
function Carpeta-Superior([string]$dir) {
    # De C:\scrcpy\scrcpy-win64-v4.1 devuelve C:\scrcpy (la que cuelga de BuscarEn)
    $raiz = $BuscarEn.TrimEnd('\')
    $p = $dir.TrimEnd('\')
    while ($true) {
        $padre = Split-Path $p -Parent
        if (-not $padre -or $padre -eq $p) { return $dir }
        if ($padre.TrimEnd('\') -eq $raiz) { return $p }
        $p = $padre
    }
}

function Cerrar-Viejos([string]$top) {
    $adbViejo = Get-ChildItem -LiteralPath $top -Filter 'adb.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($adbViejo) { try { & $adbViejo.FullName kill-server 2>&1 | Out-Null } catch {} }
    Start-Sleep -Milliseconds 500
    $pref = $top.TrimEnd('\') + '\'
    while ($true) {
        $abiertos = @(Get-Process -Name 'scrcpy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($pref, [StringComparison]::OrdinalIgnoreCase) })
        if ($abiertos.Count -eq 0) { break }
        Escribe 'Hay un scrcpy abierto de la version anterior. Cierralo y pulsa una tecla...' 'Yellow'
        [void](& $script:LeerTecla)
    }
    Get-Process -Name 'adb' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($pref, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Retirar([string]$dir) {
    $top   = Carpeta-Superior $dir
    $padre = Split-Path $top -Parent
    $nuevo = 'old_' + (Split-Path $top -Leaf)
    if (Test-Path -LiteralPath (Join-Path $padre $nuevo)) { $nuevo += '_' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
    Cerrar-Viejos $top
    for ($i = 1; $i -le 3; $i++) {
        try {
            Rename-Item -LiteralPath $top -NewName $nuevo -ErrorAction Stop
            Escribe "La version anterior queda guardada como $(Join-Path $padre $nuevo)" 'DarkGray'
            return
        } catch { Start-Sleep -Seconds 2 }
    }
    Escribe "Aviso: no he podido renombrar $top (puede que algo lo tenga abierto). Lo dejo como esta y uso la version nueva." 'Yellow'
}

function Instalar($pub, $inst) {
    $tmp = Join-Path $env:TEMP ('scrcpy-actualizar-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        # 1. Descargar en %TEMP%
        $zip = $null; $nombreZip = $null
        foreach ($z in $pub.Zips) {
            Escribe "Descargando $z ..." 'Cyan'
            try {
                Invoke-WebRequest -Uri "$($pub.Base)/$z" -OutFile (Join-Path $tmp $z) -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
                $zip = Join-Path $tmp $z; $nombreZip = $z; break
            } catch { Escribe "  No se ha podido descargar: $($_.Exception.Message)" 'Yellow' }
        }
        if (-not $zip) { throw 'No se ha podido descargar scrcpy de GitHub.' }

        # 2. Comprobar la suma SHA-256 publicada
        $sumas = Join-Path $tmp 'SHA256SUMS.txt'
        $esperado = $null
        try {
            Invoke-WebRequest -Uri "$($pub.Base)/SHA256SUMS.txt" -OutFile $sumas -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
            foreach ($l in (Get-Content -LiteralPath $sumas)) {
                if ($l -match ('^\s*([0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($nombreZip) + '\s*$')) { $esperado = $Matches[1].ToLower() }
            }
        } catch {}
        if ($esperado) {
            $real = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
            if ($real -ne $esperado) { throw 'La descarga esta danada: la suma SHA-256 no coincide con la publicada. Vuelve a intentarlo.' }
            Escribe 'Descarga comprobada (SHA-256 correcto).' 'DarkGreen'
        } else {
            Escribe 'Aviso: no he podido leer la suma SHA-256 publicada; sigo sin comprobarla.' 'Yellow'
        }

        # 3. Descomprimir en %TEMP%
        Escribe 'Descomprimiendo...' 'Cyan'
        $ext = Join-Path $tmp 'x'
        Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force -ErrorAction Stop
        $exe = Get-ChildItem -LiteralPath $ext -Filter 'scrcpy.exe' -Recurse -File | Select-Object -First 1
        if (-not $exe) { throw 'El zip descargado no trae scrcpy.exe.' }
        $origen = $exe.DirectoryName
        $nombre = Split-Path $origen -Leaf
        if ($origen.TrimEnd('\') -eq $ext.TrimEnd('\') -or -not $nombre.StartsWith($Prefijo, [StringComparison]::OrdinalIgnoreCase)) {
            $nombre = [IO.Path]::GetFileNameWithoutExtension($nombreZip)
        }
        $destino = Join-Path $BuscarEn $nombre

        # 4. Renombrar la vieja a old_... (solo ahora, con la nueva ya lista)
        if ($inst) { Retirar $inst.Dir }
        if (Test-Path -LiteralPath $destino) { Retirar $destino }

        # 5. Mover la nueva a C:\
        try { Move-Item -LiteralPath $origen -Destination $destino -ErrorAction Stop }
        catch { Copy-Item -LiteralPath $origen -Destination $destino -Recurse -Force -ErrorAction Stop }
        Escribe "scrcpy $($pub.Version) instalado en $destino" 'Green'
        return $destino
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- Copia del lanzador ----------
function Copiar-Lanzador([string]$dir) {
    if (-not $CopiarALaCarpeta -or -not $BytesBat -or -not $env:LANZADOR_BAT) { return }
    $copia = Join-Path $dir ([IO.Path]::GetFileName($env:LANZADOR_BAT))
    try {
        if (Test-Path -LiteralPath $copia) {
            $hay = [IO.File]::ReadAllBytes($copia)
            if ([Linq.Enumerable]::SequenceEqual([byte[]]$hay, [byte[]]$BytesBat)) { return }
        }
        [IO.File]::WriteAllBytes($copia, $BytesBat)
        Escribe "Copiado $(Split-Path $copia -Leaf) en $dir" 'DarkGray'
    } catch {
        Escribe "Aviso: no he podido copiar el lanzador en ${dir}: $($_.Exception.Message)" 'Yellow'
    }
}

# ---------- IP ----------
function Leer-IP([string]$fija, [string]$ultima) {
    $base = @()
    if ($fija) { $base = @($fija.Trim('.').Split('.') | Where-Object { $_ -ne '' }) }
    while ($true) {
        $oct = New-Object System.Collections.Generic.List[string]
        foreach ($b in $base) { $oct.Add($b) }
        $cur = ''
        Write-Host -NoNewline 'IP: '
        if ($oct.Count -gt 0) { Write-Host -NoNewline (($oct -join '.') + '.') -ForegroundColor White }
        $reiniciar = $false
        while (-not $reiniciar) {
            $k  = & $script:LeerTecla
            $ch = [string]$k.KeyChar
            $n  = [int]$k.KeyChar   # se compara por codigo: -eq ignora los caracteres de control
            if ($ch -match '^[0-9]$') {
                if ($cur.Length -ge 3) { continue }
                $cur += $ch
                Write-Host -NoNewline $ch -ForegroundColor White
                if ($cur.Length -eq 3 -and $oct.Count -lt 3 -and [int]$cur -le 255) {
                    $oct.Add($cur); $cur = ''
                    Write-Host -NoNewline '.' -ForegroundColor White
                }
                continue
            }
            $esEnter = ($k.Key -eq [ConsoleKey]::Enter) -or ($n -eq 13)
            if ($esEnter -or $n -eq 46 -or $n -eq 32 -or $n -eq 44) {
                if ($cur -eq '') {
                    if ($esEnter -and $ultima -and $oct.Count -eq $base.Count) {
                        Write-Host "  -> ultima: $ultima" -ForegroundColor DarkGray
                        return $ultima
                    }
                    continue
                }
                if ([int]$cur -gt 255) { continue }
                if ($oct.Count -eq 3 -and -not $esEnter) { continue }
                $oct.Add($cur); $cur = ''
                if ($oct.Count -lt 4) { Write-Host -NoNewline '.' -ForegroundColor White; continue }
                Write-Host ''
                return (($oct | ForEach-Object { [string][int]$_ }) -join '.')
            }
            if ($k.Key -eq [ConsoleKey]::Backspace -or $n -eq 8) {
                if ($cur.Length -gt 0) {
                    $cur = $cur.Substring(0, $cur.Length - 1)
                    Write-Host -NoNewline "`b `b"
                } elseif ($oct.Count -gt 0) {
                    Write-Host -NoNewline "`b `b"
                    $cur = $oct[$oct.Count - 1]
                    $oct.RemoveAt($oct.Count - 1)
                }
                continue
            }
            if ($k.Key -eq [ConsoleKey]::Escape -or $n -eq 27) { Write-Host ''; $reiniciar = $true }
        }
    }
}

# ---------- ADB ----------
function Adb { & $script:AdbExe @args 2>&1 | ForEach-Object { "$_" } }

function Estado([string]$serial) {
    $e = $null
    for ($i = 0; $i -le 4; $i++) {
        $e = $null
        foreach ($l in (Adb devices)) {
            if ($l -match '^(\S+)\s+(\S+)') { if ($Matches[1] -eq $serial) { $e = $Matches[2] } }
        }
        if (-not $e -or $e -eq 'device' -or $e -eq 'unauthorized') { return $e }
        Start-Sleep -Seconds 1
    }
    return $e
}

# ======================================= PRINCIPAL =======================================
if ($env:LANZADOR_SIN_MAIN) { return }
try {
    Escribe '=========================================='
    Escribe "   Lanzador de scrcpy (ADB)  v$VersionLanzador"
    Escribe '=========================================='
    Escribe 'Buscando scrcpy...' 'DarkGray'
    $inst = Buscar-Instalado
    $Dir  = $null
    if ($inst) { $Dir = $inst.Dir }

    if ($Actualizar) {
        Escribe 'Comprobando la ultima version en GitHub...' 'DarkGray'
        $pub = Ultima-Publicada
        if (-not $pub) {
            if (-not $inst) { throw 'No tienes scrcpy y no he podido consultar GitHub. Comprueba la conexion a Internet.' }
            Escribe 'Aviso: no he podido comprobar si hay version nueva; sigo con la que tienes.' 'Yellow'
        } elseif (-not $inst) {
            Escribe "No tienes scrcpy instalado. Instalando la $($pub.Version)..." 'Cyan'
            $Dir = Instalar $pub $null
        } elseif ($inst.Version -lt $pub.Version) {
            Escribe "Tienes la $($inst.Version) y hay una nueva: $($pub.Version). Actualizando..." 'Cyan'
            $Dir = Instalar $pub $inst
        } else {
            Escribe "scrcpy $($inst.Version) esta al dia." 'DarkGreen'
        }
    } elseif (-not $inst) {
        throw "No encuentro scrcpy en $BuscarEn (carpeta que empiece por $Prefijo)."
    }

    $script:AdbExe = Join-Path $Dir 'adb.exe'
    $scrcpyExe     = Join-Path $Dir 'scrcpy.exe'
    if (-not (Test-Path -LiteralPath $script:AdbExe)) { throw "No encuentro adb.exe en $Dir" }

    # scrcpy usa la variable ADB de Windows si existe: si apunta a otra version, falla
    # con "CreateProcessW() error 2". Se corrige la guardada y la de esta sesion.
    $adbUsuario = [Environment]::GetEnvironmentVariable('ADB', 'User')
    $adbSistema = [Environment]::GetEnvironmentVariable('ADB', 'Machine')
    $adbGuardado = $adbUsuario; if (-not $adbGuardado) { $adbGuardado = $adbSistema }
    if ($CorregirVariableADB -and $adbGuardado -and $adbGuardado -ne $script:AdbExe) {
        Escribe "Corrigiendo la variable ADB de Windows (apuntaba a $adbGuardado)" 'Yellow'
        try { [Environment]::SetEnvironmentVariable('ADB', $script:AdbExe, 'User') } catch {}
    }
    $env:ADB = $script:AdbExe

    # Con scrcpy ya instalado o actualizado, este .bat se copia en su carpeta
    Copiar-Lanzador $Dir

    $ultima = $null
    if (Test-Path -LiteralPath $ArchivoIP) { $ultima = (Get-Content -LiteralPath $ArchivoIP -TotalCount 1 -ErrorAction SilentlyContinue) }
    if ($ultima) { $ultima = $ultima.Trim() }

    :pedir while ($true) {
        Write-Host ''
        Escribe "Usando: $(Split-Path $Dir -Leaf)" 'DarkGray'
        Write-Host ''
        if ($RedFija) {
            Escribe 'Escribe el final de la IP del dispositivo.'
        } else {
            Escribe 'Escribe la IP del dispositivo SIN puntos: los pongo yo.'
            Escribe '  - Si un numero tiene 3 cifras, el punto sale solo.'
            Escribe '  - Si tiene 1 o 2 (como 0 o 10), pulsa Enter para pasar al siguiente.'
            Escribe '  Ejemplo: 192 168 1 [Enter] 25 [Enter] -> 192.168.1.25'
        }
        if ($ultima) { Escribe "Enter sin escribir nada = la ultima: $ultima" 'DarkGray' }
        Escribe 'Retroceso borra, Esc empieza de nuevo.' 'DarkGray'
        Write-Host ''
        $ip = Leer-IP $RedFija $ultima
        $serial = "${ip}:$Puerto"

        Write-Host ''
        Escribe 'Desconectando dispositivos anteriores...' 'DarkGray'
        Adb disconnect | Out-Null
        $autoriza = 0

        while ($true) {
            $salida = @(); $e = $null
            for ($i = 1; $i -le 3; $i++) {
                Escribe "Conectando a $serial (intento $i de 3)..."
                $salida = @(Adb connect $serial)
                $e = Estado $serial
                if ($e -eq 'device' -or $e -eq 'unauthorized') { break }
                Adb disconnect $serial | Out-Null
                Start-Sleep -Seconds 2
            }
            while ($e -eq 'unauthorized' -and $autoriza -lt 3) {
                $autoriza++
                Write-Host ''
                Escribe 'El dispositivo pide permiso. En su pantalla acepta "Permitir la depuracion"' 'Yellow'
                Escribe 'y marca "Permitir siempre desde este ordenador". Luego pulsa una tecla...' 'Yellow'
                [void](& $script:LeerTecla)
                $e = Estado $serial
                if ($e -ne 'device') {
                    Adb disconnect $serial | Out-Null
                    $salida = @(Adb connect $serial)
                    $e = Estado $serial
                }
            }
            if ($e -eq 'device') { break pedir }

            Write-Host ''
            Escribe "No se ha podido conectar con $serial." 'Red'
            if ($e) { Escribe "Estado del dispositivo: $e" 'Red' }
            Escribe 'Respuesta de adb:'
            foreach ($l in $salida) { Write-Host "   $l" }
            Write-Host ''
            Escribe 'Comprueba que:'
            Escribe ' - el dispositivo esta encendido y en la misma red,'
            Escribe ' - la IP es la correcta (puede haber cambiado),'
            Escribe ' - la depuracion ADB (o depuracion por red) esta activada.'
            Write-Host ''
            Write-Host '[R] Reintentar   [I] Cambiar IP   [S] Salir'
            $op = ''
            while ('R', 'I', 'S' -notcontains $op) { $op = ([string](& $script:LeerTecla).KeyChar).ToUpper() }
            if ($op -eq 'S') { exit 1 }
            if ($op -eq 'I') { continue pedir }
            $autoriza = 0
        }
    }

    try {
        New-Item -ItemType Directory -Path $CarpetaDato -Force | Out-Null
        Set-Content -LiteralPath $ArchivoIP -Value $ip -ErrorAction Stop
    } catch {}

    Write-Host ''
    Escribe 'Conectado. Iniciando scrcpy...' 'Green'
    Start-Process -FilePath $scrcpyExe -ArgumentList (@("--serial=$serial") + $Opciones) -WorkingDirectory $Dir
    Start-Sleep -Seconds 2
    exit 0
} catch {
    Write-Host ''
    Escribe "ERROR: $($_.Exception.Message)" 'Red'
    Write-Host ''
    Pausa
    exit 1
}
