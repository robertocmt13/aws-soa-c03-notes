# 10 — Amazon S3 Introduction

Notas de la Sección 10 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> **Sección completada.** Lecciones 130 a 142 y cuestionario final (5/5): buckets y objetos,
> namespaces de nombres, multipart upload, seguridad con IAM y bucket policies, Block Public
> Access, condiciones avanzadas, versionado y su troubleshooting, replicación CRR/SRR,
> replicación cross-account y Replication Time Control.

---

## Qué es S3 (lección 130)

Almacenamiento de objetos que AWS anuncia como de **escalado "infinito"**. Es uno de los pilares
de AWS: muchas webs lo usan como backend y muchos servicios de AWS se integran con él.

**Casos de uso:** backup y almacenamiento, recuperación ante desastres, archivo, almacenamiento
híbrido, hosting de aplicaciones y de media, data lakes y analítica, distribución de software y
webs estáticas.

> En el trabajo estuvimos a punto de migrar las imágenes de producto de la tienda a S3 (el caso
> de *media hosting*). Por precio nos quedamos en un servidor de OVH con software **compatible con
> la API de S3**: mismo protocolo y mismo SDK cambiando el endpoint, pero sin nada de lo que
> ofrece S3 como servicio (durabilidad, storage classes, replicación...). S3 no es un programa que
> se instale: solo existe dentro de AWS.

---

## Buckets

- Los objetos (ficheros) se guardan en **buckets**.
- **Los buckets se crean en una región.** S3 parece un servicio global (la consola lista los
  buckets de todas las regiones juntos, con una columna de región), pero cada bucket vive en la
  suya.

### Namespaces de nombres

| Namespace | Cómo funciona |
|---|---|
| **Shared global namespace** (por defecto) | El nombre es **único entre todas las cuentas y todas las regiones**. Si otra cuenta ya usa `imagenes-tienda`, no lo puedes usar en ninguna región |
| **Account regional namespace** (marzo de 2026) | Al nombre se le añade un sufijo con el ID de cuenta y la región: `prefijo-111122223333-us-east-1-an`. Solo tu cuenta puede crear buckets con ese sufijo |

- Lo que se "reutiliza" entre regiones es el **prefijo**; el nombre completo cambia porque el
  sufijo lleva la región.
- El problema que resuelve no era tener que inventar un nombre por región, sino la **unicidad
  global**: nombres ya cogidos por otras cuentas y nombres de buckets borrados que otra cuenta
  podía reclamar.
- El sufijo **cuenta para el límite de 63 caracteres** (en `us-east-1` quedan 37 para el prefijo).
- La consola añade el sufijo sola; en la API o el CLI hay que escribirlo
  (`--bucket-namespace account-regional`).

### Reglas de nombres

- Sin mayúsculas ni guiones bajos.
- No puede tener formato de IP.
- Empieza por minúscula o número.
- No puede empezar por `xn--` ni terminar en `-s3alias`.

---

## Objetos

- Cada objeto tiene una **key**, que es la **ruta completa**:
  `s3://my-bucket/my_folder1/another_folder/my_file.txt`.
- **Key = prefijo + nombre del objeto.** En el ejemplo, el prefijo es
  `my_folder1/another_folder/` y el nombre `my_file.txt`.
- **No existen los directorios.** Son keys largas con `/`. La consola los muestra como carpetas,
  y al "crear una carpeta" lo que hace es crear un objeto de 0 bytes cuya key termina en `/`.
- Consecuencia: **no hay `mv` real**. Renombrar una "carpeta" es copiar cada objeto a una key
  nueva y borrar el original. Los prefijos sí sirven para filtrar en lifecycle rules, permisos y
  notificaciones (como el filtro de prefijo de los S3 Event Notifications de la Sección 8).

### Contenido y atributos

- **Tamaño máximo de un objeto: 50 TB.** Antes eran 5 TB; las preguntas de práctica antiguas
  pueden traer todavía ese número.
- **Multipart upload:** obligatorio por encima de **5 GB** y recomendado a partir de unos
  **100 MB**. El objeto se sube en partes en paralelo y, si falla una, solo se reintenta esa
  parte.
  - **Coste oculto:** las subidas multipart que se quedan a medias siguen ocupando y facturando, y
    no aparecen en el listado normal del bucket. Se limpian con una lifecycle rule
    (`AbortIncompleteMultipartUpload`).
- **Metadata:** pares clave/valor de texto, del sistema o del usuario.
- **Tags:** pares clave/valor Unicode, **hasta 10 por objeto**. Útiles para seguridad y lifecycle.
- **Version ID**, si el versionado está activado.

---

## Práctica: primer bucket (lección 131)

En `us-east-1`. **No necesita EC2.**

Lo que se ve al crear el bucket:

- **Bucket type:**

  | | General purpose | Directory |
  |---|---|---|
  | Servicio | S3 normal | **S3 Express One Zone** |
  | Ubicación | Repartido por la región | **Una sola AZ** |
  | Para qué | Casi todo | Latencia de milisegundos de un dígito y muchísimas peticiones: entrenamiento de ML, analítica, HPC |
  | Estructura | Prefijos | Directorios de verdad |
  | Coste | — | Almacenamiento más caro, peticiones más baratas |

- **Bucket namespace:** global o account regional (ver arriba).
- **Object Ownership → ACLs disabled** (*Bucket owner enforced*, lo recomendado):
  - Las **ACLs** son el sistema antiguo de permisos objeto a objeto. Desactivadas, los permisos se
    controlan **solo con políticas** (IAM y bucket policy).
  - Lo que decide es **de quién es cada objeto**. Con ACLs activadas, un objeto subido por otra
    cuenta pertenece a esa cuenta, y el dueño del bucket puede quedarse sin poder leerlo. Con ACLs
    desactivadas, todo lo que entra es del dueño del bucket.
  - El acceso de otras cuentas se da con **bucket policy**, no con este ajuste.

### Object URL frente a Open

- La **Object URL** pública devuelve **Access Denied**: por defecto todo es privado y el **Block
  Public Access** está activado.
- El botón **Open** de la consola sí muestra el objeto porque genera una **pre-signed URL**: una
  URL temporal firmada con las credenciales de quien la genera.

### Coste y limpieza

**Empty** y después **Delete** del bucket.

---

## Seguridad en S3 (lección 132)

| Tipo | Mecanismo |
|---|---|
| **User-based** | **IAM policies**: qué llamadas a la API puede hacer un usuario o rol |
| **Resource-based** | **Bucket policy**: reglas para todo el bucket. Permite el acceso **cross-account** |
| | **Object ACL / Bucket ACL**: sistema antiguo, se puede desactivar (y viene desactivado) |

Más **cifrado** de los objetos con claves de cifrado.

### Cuándo un principal puede acceder a un objeto

**(La política IAM lo permite O la bucket policy lo permite) Y no hay ningún Deny explícito.**

- **Un Deny explícito gana siempre**, aunque haya Allow en otro sitio.
- **El "O" solo vale dentro de la misma cuenta.** Para un acceso **cross-account** hacen falta
  **las dos**: la bucket policy de la cuenta dueña del bucket y la política IAM de la cuenta que
  accede.

### Bucket policies

JSON con:

- **Resource:** buckets y objetos.
- **Effect:** `Allow` / `Deny`.
- **Action:** llamadas a la API que se permiten o deniegan.
- **Principal:** la cuenta o el usuario al que se aplica.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::examplebucket/*"]
    }
  ]
}
```

Lectura pública de **los objetos** del bucket: cualquiera puede descargar un objeto si conoce su
key, pero **no listar** el bucket.

**El ARN depende de la acción:**

| Acción | Recurso |
|---|---|
| `s3:GetObject`, `s3:PutObject`... (objetos) | `arn:aws:s3:::mybucket/*` |
| `s3:ListBucket` (el bucket) | `arn:aws:s3:::mybucket` |

Para "listar y descargar todo" hacen falta **dos statements**, uno con cada ARN.

### Acceso desde EC2: IAM role

Una instancia accede a S3 con un **IAM role** asociado (instance profile) con los permisos
necesarios sobre el bucket. Es el mismo mecanismo que `AmazonEC2RoleForSSM` en la Sección 5. El
SDK coge solo las credenciales temporales del rol, que rotan.

**Nunca access keys en la instancia** (ni en un `.env`, ni en la configuración de la aplicación, ni
en `~/.aws/credentials`). En el examen, la opción de "guardar las access keys en la instancia" es
la incorrecta.

### Block Public Access

Cuatro ajustes (bloquear el acceso público concedido por ACLs nuevas, por cualquier ACL, por
políticas nuevas y por cualquier política), todos activados por defecto.

- Existen para **evitar fugas de datos**. Si un bucket nunca debe ser público, dejarlos activados.
- **Ganan a la bucket policy:** con Block Public Access activado, una policy pública no da acceso.
  Es un seguro contra una policy mal escrita.
- Se pueden fijar **a nivel de cuenta**, no solo de bucket.

---

## Práctica: bucket policy pública (lección 133)

En `us-east-1`. **No necesita EC2.**

1. Desactivar el **Block Public Access del bucket**. La consola obliga a escribir `confirm`: un
   bucket público por error es una de las fugas de datos más habituales.
2. Crear la bucket policy de lectura pública con el **Policy Generator** (o desde los ejemplos de
   la consola).
3. Comprobar que la Object URL ya muestra el objeto.

**Trampa del Policy Generator:** pide el ARN y, si se pone solo el del bucket con `GetObject`, la
política no funciona. Hay que añadir `/*`.

### Coste y limpieza

- **Empty** y **Delete** del bucket (la policy se va con él).
- No tocar el Block Public Access **de la cuenta**, solo el del bucket.

---

## Bucket policies avanzadas (lección 134)

Usos de las bucket policies: dar acceso público, forzar el cifrado al subir y dar acceso a otras
cuentas.

### Condiciones

| Condición | Clave | Detalle |
|---|---|---|
| IP de origen | `aws:SourceIp` | **Solo IP pública o Elastic IP**, nunca privada: S3 ve la IP desde la que llega la petición (si una EC2 sale por NAT Gateway, la del NAT) |
| VPC o VPC endpoint de origen | `aws:SourceVpc` / `aws:SourceVpce` | **Solo funciona si el tráfico entra por un VPC endpoint de S3**. "Restringir el bucket a una VPC" → VPC endpoint + esta condición |
| CloudFront | OAC (antes OAI) | Solo CloudFront puede leer el bucket; nadie se salta la CDN |
| MFA | `aws:MultiFactorAuthPresent` | Por ejemplo, denegar `DeleteObject` sin MFA |

Ejemplos: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html>

### Solo cuentas de una AWS Organization

`Allow` de `GetObject` con la condición `StringEquals` sobre **`aws:PrincipalOrgID`**: da acceso a
los principales de **cualquier cuenta de la organización** sin listarlas una a una. Las cuentas que
se añadan después entran solas.

### Rechazar subidas sin cifrado

`Deny` de `PutObject` a `"Principal": "*"` con la condición `"Null": {"s3:x-amz-server-side-encryption": true}`:
si la petición **no trae la cabecera** de cifrado, se rechaza. Afecta también al administrador.

> **Es la forma antigua.** Desde enero de 2023 S3 **cifra por defecto** todos los objetos nuevos
> (SSE-S3), así que ya no hace falta para garantizar el cifrado, e incluso rechaza subidas que se
> habrían cifrado igualmente. Saber leerla para el examen.

---

## Versionado (lecciones 135 y 136)

- Se activa **a nivel de bucket**.
- Sobrescribir la misma key crea una versión nueva (1, 2, 3...).
- Buena práctica: protege de **borrados accidentales** y permite volver a una versión anterior.

### Lo que no es "como cualquier versionado"

- **Tres estados:** sin versionar, activado y suspendido. Una vez activado, **nunca vuelve a "sin
  versionar"**, solo a suspendido. **Suspender no borra las versiones existentes.**
- Los objetos que ya existían antes de activarlo tienen el version ID **`null`**.
- **Delete markers:**
  - Borrar un objeto **sin indicar versión** no borra nada: añade un *delete marker* y el objeto
    deja de aparecer en el listado.
  - **Recuperar el objeto = borrar el delete marker.**
  - Borrar una **versión concreta** (por version ID) es **permanente**.
- **Cada versión es una copia completa y se factura entera.** No guarda diferencias como Git: diez
  versiones de una imagen de 5 MB son 50 MB. En producción se acompaña de lifecycle rules que
  expiran las versiones *noncurrent*.

### Práctica

En `us-east-1`. **No necesita EC2.** Activar el versionado, subir otra vez el mismo objeto,
volver a la versión anterior y borrar y recuperar un objeto. En la consola, el toggle **Show
versions** muestra las versiones y los delete markers.

**No hay botón de "restaurar versión".** El rollback se hace de dos formas:

| Forma | Efecto |
|---|---|
| Borrar la versión nueva (la del vídeo) | La anterior pasa a ser la actual. La nueva se pierde para siempre |
| Copiar la versión antigua encima | La antigua pasa a ser la más reciente y se conserva todo el historial. Lo prudente en producción |

### Coste y limpieza

**Empty** antes de **Delete**: borra todas las versiones y los delete markers. Borrar objetos a
mano sin *Show versions* (o con `aws s3 rm`) solo crea delete markers, y las versiones siguen
facturando. **Un objeto "borrado" en un bucket versionado sigue ocupando hasta que se borran sus
versiones.**

---

## Versionado: troubleshooting (lección 137)

- Al activar el versionado **por primera vez**, hay que esperar **al menos 15 minutos** a que se
  propague.
- Durante ese tiempo, leer objetos creados o actualizados puede dar **HTTP 404 NoSuchKey**.
- Recomendación: **esperar 15 minutos antes de lanzar escrituras**.

A mí no me pasó en la práctica: es un comportamiento que *puede* darse durante la propagación, no
algo que ocurra siempre. Para el examen: 404 NoSuchKey justo después de activar el versionado →
esperar 15 minutos.

Documentación: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/versioning-workflows.html>

---

## Replicación: CRR y SRR (lección 138)

| | CRR (Cross-Region Replication) | SRR (Same-Region Replication) |
|---|---|---|
| Destino | Otra región | La misma región |
| Casos de uso | Cumplimiento normativo, menos latencia para usuarios de otra región, copia en otra cuenta | Agregar logs de varios buckets en uno, copia en vivo de producción a una cuenta de test |

- **El versionado tiene que estar activado en los dos buckets**, origen y destino.
- Los buckets pueden estar **en cuentas distintas**.
- **La copia es asíncrona**: el destino puede ir unos segundos o minutos por detrás. Se parece más
  a un `rsync` periódico que a un RAID 1. Para un tiempo garantizado está RTC (lección 142).
- Hace falta un **rol IAM** que permita a S3 leer del origen y escribir en el destino.

---

## Replicación: qué se replica y qué no (lección 139)

- **Solo se replican los objetos nuevos**, los subidos después de crear la regla.
- Los objetos que ya existían, y los que fallaron al replicarse, se copian con **S3 Batch
  Replication**.
- **Borrados:**
  - Los **delete markers** se replican **solo si se activa esa opción** en la regla.
  - Los **borrados de una versión concreta no se replican nunca**, para que un borrado malicioso o
    accidental en el origen no se lleve también la copia del destino.
- **No hay encadenamiento (*chaining*).** Con dos reglas, bucket 1 → bucket 2 y bucket 2 →
  bucket 3, lo que se sube al bucket 1 llega al 2 pero **no al 3**:

  | Objeto | ¿Llega al bucket 2? | ¿Llega al bucket 3? |
  |---|---|---|
  | Subido al bucket 1 | Sí | **No** |
  | Subido directamente al bucket 2 | — | Sí |

  La regla del bucket 2 solo replica lo que se escribe directamente en él, no las réplicas que le
  llegan. Para llevar lo del bucket 1 al 3 hace falta una regla directa **1 → 3** (un bucket
  puede tener varias reglas hacia destinos distintos).

> Esto no lo entendí a la primera. La analogía que me sirvió: una réplica intermedia de MySQL sin
> `log_slave_updates` aplica lo que le llega del maestro, pero no lo escribe en su binlog, así
> que la réplica que cuelga de ella no lo recibe.

---

## Práctica: replicación entre regiones (lección 140)

**No necesita EC2.**

1. Crear el bucket de origen `s3-robertomoyano-bucket-origin-v2` en **`eu-west-1`** con
   versionado.
2. Crear el bucket de destino `s3-robertomoyano-bucket-replica-v2` en **`us-east-1`** con
   versionado.
3. En el origen, *Management → Replication rules → Create replication rule* (`DemoReplicationRule`),
   para todo el bucket, con destino el bucket de réplica. La consola **crea el rol IAM** sola.
4. Al guardar la regla, la consola pregunta **Replicate existing objects?** y ofrece lanzar un
   trabajo de **Batch Operations**: es S3 Batch Replication. Lo dejé en *No* (cuesta aparte).
5. Subir un objeto al origen y comprobar con **Show versions** que aparece en la réplica.
6. Activar **delete marker replication**, borrar el objeto en el origen sin indicar versión y
   comprobar que el delete marker aparece también en la réplica.

### Lo que se ve en la práctica

- **El version ID es el mismo en los dos buckets.** La replicación no crea una versión nueva en
  el destino: copia el objeto con su misma versión.
- Tras el borrado, el objeto "desaparece" de los dos buckets, pero con *Show versions* se ve el
  delete marker y la versión sigue ahí. Si se borra **la versión concreta** en el origen, ese
  borrado no llega a la réplica.
- La tabla de reglas muestra las opciones de la regla: prioridad, alcance, storage class, dueño de
  la réplica (*Replica owner*), RTC y sincronización de cambios en la réplica.

### Coste y limpieza

1. **Empty** y **Delete** de **los dos** buckets (la regla se va con el bucket de origen).
2. **IAM → Roles:** borrar el rol `s3crr_role_for_s3-robertomoyano-bucket-origin-v2`. **No se
   borra con los buckets.**
3. No tocar los roles `AWSServiceRoleFor...`: son *service-linked roles* que crea y usa cada
   servicio.

---

## Replicación entre cuentas (lección 141)

**Por defecto, el dueño del objeto en el origen es también el dueño de la réplica.** Si se
replica de la cuenta A a un bucket de la cuenta B, las réplicas siguen siendo de A aunque estén en
el bucket de B, y B puede no tener permiso para leerlas o gestionarlas en su propio bucket.

Para que las réplicas pasen a ser de la cuenta de destino (**owner override**):

1. Activar la opción **owner override** en la regla de replicación.
2. En la **cuenta de origen**: el rol IAM de replicación necesita
   `s3:ObjectOwnerOverrideToBucketOwner` sobre `arn:aws:s3:::dest-bucket/*`.
3. En la **cuenta de destino**: la bucket policy permite esa misma acción a la cuenta de origen.

Es la regla del acceso entre cuentas de la lección 132: **permiso en los dos lados** (IAM en el
origen y bucket policy en el destino). Esto aplica también a la replicación cross-account normal:
el bucket de destino tiene que permitir que el rol del origen le escriba.

> Si el bucket de destino tiene **ACLs disabled** (*Bucket owner enforced*, lo que viene por
> defecto), el dueño del bucket es dueño de todo lo que entra, réplicas incluidas, y el problema
> desaparece. Lo de la diapositiva sigue cayendo en el examen.

Sin práctica: necesita dos cuentas.

---

## Replication Time Control (lección 142)

- Garantiza la velocidad de replicación: **el 99,99 % de los objetos nuevos se replica en menos
  de 15 minutos**. Tiempo predecible y auditable.
- Funciona en la misma región o entre regiones.
- **Coste adicional por GB replicado**: solo cuando hay un requisito de negocio o de cumplimiento.
- Pista de examen: "replicación con tiempo **garantizado** / SLA / auditable" → **RTC**.

### Monitorización

RTC publica en **CloudWatch** las métricas de replicación:

| Métrica | Qué mide |
|---|---|
| `ReplicationLatency` | Cuánto va por detrás el destino |
| `BytesPendingReplication` / `OperationsPendingReplication` | Lo que queda por replicar |
| `OperationsFailedReplication` | Lo que ha fallado (se puede reintentar con Batch Replication) |

Además, S3 genera un evento cuando un objeto supera los 15 minutos
(`s3:Replication:OperationMissedThreshold`). Con eso y alarmas sobre las métricas se detecta que la
replicación se ha atascado.

> No confundir los dos "15 minutos" de la sección: **RTC replica en menos de 15 minutos**; con el
> **versionado** hay que **esperar 15 minutos después de activarlo** antes de escribir.

---

## Cuestionario de la sección

**5 de 5.** Preguntas sobre:

- Un bucket de origen A y dos de destino B y C: **una regla de replicación desde A hacia cada
  destino**, no encadenadas.
- Qué hacer antes de activar la replicación entre dos buckets: **activar el versionado en los
  dos**.
- Tener el contenido de un bucket disponible en varias regiones: **CRR**.
- Versión de los objetos que ya existían al activar el versionado: **`null`**.
- Error al crear un bucket llamado `dev`: **los nombres de bucket son globalmente únicos** y ese
  ya lo tiene otra cuenta.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| Bucket | Se crea en una región. Nombre **globalmente único** (namespace por defecto) |
| Account regional namespace | Sufijo `-cuenta-región-an`, solo tu cuenta lo usa. Opcional |
| Key | Ruta completa = prefijo + nombre. **No hay directorios** |
| Tamaño máximo | 50 TB por objeto |
| Multipart upload | Obligatorio > 5 GB, recomendado > 100 MB. Subidas incompletas → `AbortIncompleteMultipartUpload` |
| Tags de objeto | Hasta 10 |
| Directory bucket | S3 Express One Zone: una AZ, latencia mínima |
| ACLs disabled | Bucket owner enforced: permisos solo con políticas, todos los objetos son del dueño del bucket |
| Pre-signed URL | URL temporal firmada con las credenciales de quien la genera |
| Evaluación de acceso | (IAM **o** bucket policy) **y** sin Deny explícito. Cross-account: **las dos** |
| `GetObject` / `ListBucket` | `bucket/*` / `bucket` |
| EC2 → S3 | **IAM role**, nunca access keys |
| Block Public Access | Gana a la bucket policy. Nivel de bucket y de cuenta |
| `aws:SourceIp` | Solo IP pública / Elastic IP |
| Restringir a una VPC | VPC endpoint + `aws:SourceVpce` / `aws:SourceVpc` |
| Solo las cuentas de la organización | `aws:PrincipalOrgID` |
| Forzar cifrado | Deny `PutObject` si falta `x-amz-server-side-encryption` (hoy: cifrado por defecto SSE-S3) |
| Versionado | A nivel de bucket. No vuelve a "sin versionar", solo a suspendido. Objetos previos: `null` |
| Delete marker | Borrar sin versión → marker. Recuperar = borrar el marker. Borrar versión concreta = permanente |
| Coste del versionado | Cada versión se factura entera |
| 404 NoSuchKey tras activar el versionado | Esperar 15 minutos antes de escribir |
| Replicación (CRR / SRR) | Versionado en **los dos** buckets. Asíncrona. Rol IAM. Puede ser entre cuentas |
| CRR / SRR, casos de uso | CRR: cumplimiento, latencia, otra cuenta. SRR: agregación de logs, producción → test |
| Objetos que ya existían o que fallaron | **S3 Batch Replication** |
| Borrados replicados | Delete markers: opcional. Borrado de versión concreta: **nunca** |
| Chaining | **No hay**. 1 → 2 → 3 no lleva lo de 1 a 3: regla directa 1 → 3 |
| Replicación cross-account | Réplicas del dueño del origen por defecto. **Owner override** + `s3:ObjectOwnerOverrideToBucketOwner` en el rol IAM del origen y en la bucket policy del destino |
| Replicación con tiempo garantizado | **RTC**: 99,99 % en < 15 min, métricas en CloudWatch, coste extra |
