# Lanzador de scrcpy

Un solo archivo `.bat` para ver y manejar desde el PC tu **Fire TV, Android TV, TV box o móvil Android** por la red, con [scrcpy](https://github.com/Genymobile/scrcpy).

Te encargas solo de escribir la IP. Lo demás lo hace él:

- **Instala scrcpy** si no lo tienes.
- **Lo mantiene al día**: cada vez que lo abres comprueba si hay versión nueva y la instala.
- **Conecta por ADB** y abre scrcpy.

## Descarga

Ve a **[Releases](../../releases/latest)** y descarga **`Lanzador-scrcpy.bat`**.

> Al venir de Internet, la primera vez Windows puede decir **«Windows protegió su PC»**. Pulsa **Más información → Ejecutar de todas formas**.
> También puedes hacer clic derecho en el archivo → **Propiedades** → marcar **Desbloquear** → **Aceptar**.

## Requisitos

- **Windows 10 u 11.** Usa PowerShell, que ya viene con Windows; no hay que instalar nada más.
- El PC y el dispositivo, **en la misma red**.
- En el dispositivo, **la depuración ADB activada** (ver más abajo).

## Uso

1. Haz doble clic en `Lanzador-scrcpy.bat`.
2. Escribe la IP del dispositivo **sin puntos**, que los pone el lanzador:
   - Si un número tiene **3 cifras**, el punto sale solo.
   - Si tiene **1 o 2 cifras** (como `0` o `10`), pulsa **Enter** para pasar al siguiente.

   | Escribes | Queda |
   |---|---|
   | `192` `168` `1` **Enter** `25` **Enter** | `192.168.1.25` |
   | `10` **Enter** `0` **Enter** `0` **Enter** `5` **Enter** | `10.0.0.5` |

   Si escribes los puntos por costumbre, también vale. **Retroceso** borra (también los puntos) y **Esc** empieza de nuevo.
3. La primera vez, el dispositivo te pedirá permiso: acepta **«Permitir la depuración»** y marca **«Permitir siempre desde este ordenador»**.
4. Se abre scrcpy y ya puedes manejar el dispositivo con el ratón y el teclado.

La próxima vez, **Enter sin escribir nada** vuelve a usar la última IP.

> **¿Por qué no se puede escribir la IP sin ningún punto?** Porque sería ambiguo: `1921681100` puede ser `192.168.1.100` o `192.168.110.0`. Con la regla de las 3 cifras solo hay que pulsar Enter en los números cortos.

## Activar la depuración ADB

### Fire TV

1. **Ajustes → Mi Fire TV → Acerca de** y pulsa 7 veces sobre el nombre del dispositivo hasta que aparezcan las opciones para desarrolladores.
2. **Ajustes → Mi Fire TV → Opciones para desarrolladores → Depuración ADB: activada.**
3. La IP está en **Ajustes → Mi Fire TV → Acerca de → Red**.

### Android TV, Google TV y TV box

1. **Ajustes → Sistema → Información** y pulsa 7 veces sobre **Compilación**.
2. En **Opciones para desarrolladores**, activa **Depuración USB** y, si aparece, **Depuración por red** o **ADB por red**.
3. La IP está en los ajustes de red o Wi-Fi.

Los nombres de los menús cambian según la marca.

### Móviles Android

El lanzador conecta por el puerto **5555**, el de siempre en teles y TV box. En los móviles, la «depuración inalámbrica» de Android 11 o superior usa otro puerto, que además cambia. Para usar el lanzador con un móvil:

1. Activa **Opciones para desarrolladores → Depuración USB** y conecta el móvil al PC por cable.
2. Abre una ventana de comandos en la carpeta de scrcpy (por ejemplo `C:\scrcpy-win64-v5.0.1`) y escribe `adb tcpip 5555`.
3. Desconecta el cable y usa el lanzador con la IP del móvil. Al reiniciar el móvil hay que repetirlo.

## Qué instala y dónde

- **scrcpy:** lo descarga de las [releases oficiales](https://github.com/Genymobile/scrcpy/releases) en `%TEMP%` y lo deja en `C:\scrcpy-win64-vX.Y.Z`.
  - Usa la versión de Windows que corresponde: 64 bits, 32 bits o ARM64.
  - Antes de instalar, **comprueba la suma SHA-256** publicada por scrcpy. Si no coincide, no instala nada.
- **Al actualizar:** primero descarga la versión nueva. Solo después renombra la anterior a `old_scrcpy-win64-v…` y pone la nueva en su sitio. Si falla la descarga, te quedas con la que tenías.
  - Las carpetas `old_…` se pueden borrar cuando quieras.
- **Una copia del lanzador:** lo deja dentro de la carpeta de scrcpy que usa.
- **La última IP:** se guarda en `%LOCALAPPDATA%\LanzadorScrcpy\ultima_ip.txt`.

Si en `C:\` hay varias carpetas que empiezan por `scrcpy`, usa la de versión más alta.

## Ajustes

Al principio del `.bat` hay un apartado **AJUSTES**. Ábrelo con el Bloc de notas:

| Ajuste | Por defecto | Para qué |
|---|---|---|
| `$RedFija` | `''` | Parte fija de la IP. Con `'192.168.1'` solo tendrás que escribir el final. |
| `$Puerto` | `5555` | Puerto ADB del dispositivo. |
| `$Opciones` | `--video-bit-rate=2M --max-size=1024 --no-audio` | Opciones de scrcpy ([lista completa](https://github.com/Genymobile/scrcpy#user-documentation)). |
| `$BuscarEn` / `$Prefijo` | `C:\` / `scrcpy` | Dónde busca e instala scrcpy. |
| `$Actualizar` | `$true` | Con `$false` no consulta GitHub al arrancar. |
| `$CorregirVariableADB` | `$false` | Con `$true`, si Windows tiene una variable `ADB` que apunta a otra carpeta, la corrige para siempre. |
| `$CopiarALaCarpeta` | `$true` | Copia el lanzador dentro de la carpeta de scrcpy. |

## Problemas frecuentes

**«No se ha podido conectar».** Comprueba que el dispositivo está encendido, en la misma red y con la depuración ADB activada, y que la IP no ha cambiado. El lanzador enseña la respuesta de adb y te deja reintentar o cambiar la IP.

**La conexión se queda en «unauthorized».** El dispositivo está esperando a que aceptes el permiso en su pantalla. Si no aparece el aviso, el lanzador reconecta para que salga otra vez.

**`CreateProcessW() error 2` o «Command not found … adb.exe».** Windows tiene una variable `ADB` que apunta a una carpeta de scrcpy que ya no existe. El lanzador la corrige mientras está abierto. Para arreglarla para siempre, pon `$CorregirVariableADB = $true`.

**La imagen sale negra, a trozos o con tirones.** Desde la versión 5.0, scrcpy decodifica el vídeo por hardware. Añade `'--hwdec=disabled'` a `$Opciones`.

**«No he podido comprobar si hay versión nueva».** No había Internet o GitHub no respondió. El lanzador sigue con la versión que tienes.

## Desinstalar

Borra las carpetas `C:\scrcpy-win64-…` y `C:\old_scrcpy-…`, y también `%LOCALAPPDATA%\LanzadorScrcpy`.

## Privacidad

El lanzador solo se conecta a GitHub para consultar y descargar scrcpy, y a tu dispositivo por ADB. No envía nada a ningún otro sitio. La última IP se queda en tu PC.

## Créditos y licencia

- [scrcpy](https://github.com/Genymobile/scrcpy) es de Genymobile y se distribuye con licencia Apache 2.0. Este proyecto no está relacionado con ellos y no incluye scrcpy: lo descarga de sus releases oficiales.
- El lanzador se publica con licencia [MIT](LICENSE).

## Para quien mantiene el repositorio

- **El código:** `Lanzador-scrcpy.bat` es un archivo híbrido. Las primeras líneas son de `cmd` y arrancan PowerShell con el resto del mismo archivo. Tiene que ir **en ASCII y con finales de línea CRLF**; el `.gitattributes` evita que Git los cambie.
- **Las pruebas:** `tests/comprobar.ps1` comprueba el formato, la sintaxis y la lectura de la IP con teclas simuladas. Se ejecutan en cada push (workflow **Pruebas**).
- **Publicar una versión:**
  1. Entra en **Actions → Publicar version → Run workflow** y elige qué número sube: `minor` (1.0.0 → 1.1.0), `patch` (1.0.0 → 1.0.1) o `major` (1.0.0 → 2.0.0).
  2. El workflow pasa las pruebas, pone el número de versión en el `.bat`, calcula el SHA-256 y crea la release con el `.bat` y `SHA256SUMS.txt`.
  3. La primera vez sale la `v1.0.0`.
