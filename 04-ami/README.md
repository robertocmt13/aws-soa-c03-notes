# 04 — AMI (Amazon Machine Image)

Notas de la Sección 4 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

---

## Qué es una AMI

Una AMI es una plantilla que contiene el sistema operativo, el software preinstalado y la
configuración de arranque de una instancia EC2. Se construye a partir de snapshots de EBS.

Dos ideas que hay que tener claras desde el principio:

- **La AMI es un recurso regional.** Una AMI creada en `us-east-1` no se puede usar para
  lanzar instancias en `eu-north-1`. Dentro de la misma región sí sirve para cualquier AZ.
- **La AMI y su snapshot son recursos separados.** Deregistrar la AMI no borra el snapshot.
  Es el error clásico que deja almacenamiento facturando indefinidamente.

---

## AMI No Reboot Option

Al crear una AMI desde una instancia en ejecución, el comportamiento por defecto es que EC2
**apaga la instancia**, hace el snapshot de los volúmenes EBS y la vuelve a arrancar. Lo hace
para garantizar la integridad del sistema de ficheros: al parar el SO se hace flush de los
buffers a disco y se desmonta limpiamente.

La opción **No reboot** (checkbox en la consola, `--no-reboot` en la CLI) evita ese reinicio.
La instancia sigue sirviendo tráfico durante la creación de la imagen.

**El trade-off:** AWS ya no garantiza la integridad del sistema de ficheros. Lo que estuviera
en buffers de memoria sin escribir no entra en el snapshot, y una escritura a medias puede
quedar capturada en estado inconsistente.

| | Reboot (por defecto) | No reboot |
|---|---|---|
| Interrupción del servicio | Sí | No |
| Integridad del FS garantizada | Sí | No |
| Uso típico | Cualquier cosa con estado | Frontend sin estado local |

### Cómo cae en el examen

- *"Crear la AMI provocó una interrupción en producción, ¿cómo se evita?"* → No reboot.
- *"La AMI arranca con el sistema de ficheros corrupto, ¿por qué?"* → se usó No reboot.

---

## AWS Backup vs EventBridge + Lambda

Dos formas de automatizar la creación periódica de AMIs, y la diferencia entre ellas es
exactamente el reboot.

### AWS Backup

Puede crear AMIs de instancias EC2 dentro de un plan de backup programado, pero
**siempre lo hace sin reiniciar**. No existe opción de forzar el reboot.

El resultado es un backup *crash-consistent*: el equivalente a tirar del cable. Vale para
cargas sin estado, no garantiza nada para algo que esté escribiendo a disco.

### EventBridge + Lambda + CreateImage

La alternativa cuando sí se necesita integridad garantizada:

1. Una regla de **EventBridge** programada (schedule).
2. Invoca una función **Lambda**.
3. La Lambda llama a la API **`CreateImage`** pasando el parámetro de reboot activado.

Como esto implica downtime real de la instancia, se programa en la ventana de menos tráfico.

### Cómo cae en el examen

| Requisito del enunciado | Respuesta |
|---|---|
| Backups programados, sin más | AWS Backup (opción managed, siempre preferible si encaja) |
| AMIs programadas **con integridad garantizada** | EventBridge + Lambda + CreateImage con reboot |

Si el enunciado dice explícitamente que AWS Backup no cumple el requisito, la respuesta es
siempre la segunda.

---

## Migración de instancias EC2 usando AMIs

### Entre regiones

Como la AMI es regional, para llevar una instancia a otra región hay que copiar la imagen:

1. Crear una AMI de la instancia en la región origen.
2. **Copy AMI** hacia la región destino (`aws ec2 copy-image`).
3. Lanzar una instancia nueva en la región destino desde la AMI copiada.
4. Terminar la original si ya no hace falta.

```bash
aws ec2 copy-image \
  --source-region us-east-1 \
  --source-image-id ami-xxxxxxxxxxxx \
  --region eu-north-1 \
  --name "MiImagen-copy"
```

Puntos importantes:

- Copiar una AMI **copia también los snapshots de EBS** a la región destino. Se crea un
  snapshot físico nuevo, con su propio ID y su propia facturación. No es un puntero.
- La AMI copiada recibe **un AMI ID distinto**.
- Las **KMS keys también son regionales**, así que al copiar una AMI cifrada se puede (y a
  veces se debe) cambiar la key de cifrado.
- Al limpiar hay que **revisar ambas regiones**.

### Entre AZs

No hace falta copiar nada. La AMI sirve para cualquier AZ de su región: se crea la imagen y se
lanza la instancia nueva en la otra AZ directamente.

---

## Cross-Account AMI Sharing

Se puede compartir una AMI con otra cuenta AWS.

- **La propiedad no cambia.** La AMI sigue siendo del propietario original; la cuenta B puede
  lanzar instancias desde ella pero no borrarla, y no le cuenta en su factura de almacenamiento.
- Solo se pueden compartir AMIs con volúmenes **sin cifrar** o cifrados con una
  **customer managed key (CMK)**. Las AWS managed keys **no** se pueden compartir — respuesta
  trampa habitual.
- Si el snapshot está cifrado, hay que compartir **también la key**. Sin acceso a la CMK, la
  cuenta B no puede lanzar nada aunque tenga la AMI compartida.

Permisos de KMS implicados (concepto, no hay que memorizarlos uno a uno):
`kms:DescribeKey`, `kms:CreateGrant`, `kms:Decrypt`, `kms:GenerateDataKey`, `kms:ReEncrypt`.

## Cross-Account AMI Copy

Aquí **sí cambia la propiedad**. Si la cuenta B copia una AMI que le han compartido, la copia
resultante es suya.

- Para poder copiarla, el dueño original tiene que darle **permisos de lectura sobre el
  snapshot EBS** que respalda la AMI. Compartir solo la AMI no basta.
- Si los snapshots están cifrados, hay que compartir la key igualmente.
- La cuenta B puede **cifrar la copia con su propia CMK** durante el proceso.

> **La distinción de examen: compartir ≠ copiar.** Compartir permite usarla; copiar la hace tuya.

---

## EC2 Image Builder

Servicio para **automatizar la creación, mantenimiento, validación y test de AMIs** (y también
de imágenes de contenedor). Es el equivalente managed de una herramienta tipo Packer, y el
patrón que implementa es el de la *golden AMI* actualizada periódicamente.

- Se puede ejecutar **on schedule**, con **cron personalizado** o **manualmente**.
- **El servicio es gratis**; solo se pagan los recursos subyacentes (las instancias EC2 de
  build y test, y el almacenamiento de la AMI resultante).

### Flujo de ejecución

```
Image Builder
   → lanza Builder EC2 Instance   (aplica los build components)
   → crea la New AMI
   → lanza Test EC2 Instance      (ejecuta el test suite)
   → distribuye la AMI            (una o varias regiones)
   → termina ambas instancias
```

La fase de test es la diferencia principal frente a crear la AMI a mano: si el test falla, la
imagen no se distribuye.

### Las piezas

| Pieza | Qué define |
|---|---|
| **Recipe** | Imagen base + componentes que se le aplican. Es **inmutable**: para cambiarla hay que crear una versión nueva |
| **Components** | Scripts de build (instalar/configurar software) y de test (verificar el resultado). Máximo 20 por recipe |
| **Pipeline** | Cuándo se ejecuta la recipe (schedule / cron / manual) |
| **Infrastructure configuration** | Tipo de instancia, IAM role, VPC, terminate on failure |
| **Distribution settings** | En qué regiones acaba la AMI |
| **Workflow** | Los pasos internos de build y test. Por defecto: `build-image` y `test-image` |

### Problemas encontrados en la práctica

Dos errores reales al montar el pipeline por primera vez en una cuenta nueva:

**1. `Invalid parameter value for InstanceProfileName: The provided instance profile does not exist`**

La opción "Create with default configurations" asume que existe un instance profile llamado
`EC2InstanceProfileForImageBuilder`, pero la consola **no lo crea**. Hay que montarlo a mano.

Detalle importante de IAM: **un rol y un instance profile son objetos distintos**. El rol es la
identidad con sus permisos; el instance profile es el envoltorio que permite adjuntar ese rol a
una instancia EC2. Cuando se crea un rol desde la consola con caso de uso EC2, IAM crea los dos
y por eso normalmente no se nota. Si el rol se crea por CLI o por otra vía, el instance profile
hay que crearlo aparte.

```bash
aws iam create-role \
  --role-name EC2InstanceProfileForImageBuilder \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]}'

aws iam attach-role-policy --role-name EC2InstanceProfileForImageBuilder \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam attach-role-policy --role-name EC2InstanceProfileForImageBuilder \
  --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder

aws iam create-instance-profile \
  --instance-profile-name EC2InstanceProfileForImageBuilder

aws iam add-role-to-instance-profile \
  --instance-profile-name EC2InstanceProfileForImageBuilder \
  --role-name EC2InstanceProfileForImageBuilder
```

La instancia de build necesita `AmazonSSMManagedInstanceCore` porque Image Builder la controla
a través de Systems Manager.

**2. `InvalidParameterCombination ... The specified instance type is not eligible for Free Tier`
en el paso `LaunchBuildInstance`**

La infrastructure configuration por defecto no fijaba un tipo de instancia elegible para free
tier. Se resuelve editándola y seleccionando explícitamente el tipo correcto (`t3.micro` en
`eu-north-1`).

Para consultar qué tipos son free tier en una región:

```bash
aws ec2 describe-instance-types \
  --region eu-north-1 \
  --filters "Name=free-tier-eligible,Values=true" \
  --query "InstanceTypes[].InstanceType"
```

> **Lección de troubleshooting:** el error de Image Builder era en realidad un error de EC2.
> La cadena a leer es *servicio managed → paso del workflow → llamada API subyacente*
> (`RunInstances`). Este tipo de errores encadenados son buena parte del SOA-C03.

---

## AMI in Production

Cómo controlar que en producción solo se lancen instancias desde imágenes aprobadas.

- **IAM previene.** Se etiquetan las AMIs aprobadas (por ejemplo `Environment: Prod`) y se
  aplica una política IAM con una condición sobre `ec2:ResourceTag` para que los usuarios solo
  puedan lanzar desde esas.

  ```json
  {
    "Condition": {
      "StringEquals": {
        "ec2:ResourceTag/Environment": "Prod"
      }
    }
  }
  ```

- **AWS Config detecta.** Se combina con AWS Config para encontrar instancias EC2
  no conformes, es decir, las que ya están corriendo y fueron lanzadas desde AMIs no aprobadas.

> La división IAM (prevenir) / Config (detectar) es justo lo que se pregunta.

---

## Limpieza de la sección

Recursos generados y qué hay que borrar para no acumular coste:

| Recurso | ¿Factura? | Nota |
|---|---|---|
| AMI (deregister) | No directamente | Deregistrar **no** borra el snapshot |
| Snapshot EBS | **Sí** | Hay que borrarlo aparte, después de deregistrar la AMI |
| Instancias del hands-on | **Sí** | Lo más caro; terminar siempre |
| Pipeline / Recipe / Configurations | No | Limpieza de orden |
| Rol e instance profile de IAM | No | Global, no regional |
| Log groups de CloudWatch | Casi no | `/aws/imagebuilder/...` |
| Security groups | No | — |

Orden correcto: **deregistrar la AMI → borrar el snapshot**. Al revés no deja, porque el
snapshot está en uso.

Puntos de atención:

- Si se ha copiado una AMI a otra región, **revisar ambas regiones**.
- Image Builder termina solo sus instancias de build y test (`Terminate on failure: Enabled`),
  pero **no borra la AMI resultante ni su snapshot**.
- El diálogo *Delete images* de Image Builder incluye un checkbox **"Deregister AMIs"** que
  deregistra las AMIs asociadas sin tener que ir a EC2 a mano.
- Si hay una regla de retención en la **Recycle Bin**, una AMI deregistrada va a la papelera en
  lugar de desaparecer, y sigue facturando.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| AMI | Recurso **regional**, respaldado por snapshots de EBS |
| No reboot | Sin downtime, **sin garantía de integridad del FS** |
| AWS Backup | Crea AMIs pero **siempre sin reboot** |
| Integridad + programación | EventBridge + Lambda + `CreateImage` con reboot |
| Migrar de región | **Copy AMI** → genera snapshot nuevo en destino |
| Migrar de AZ | No hace falta copiar, la AMI ya sirve |
| Compartir AMI | La propiedad **no** cambia; CMK sí, AWS managed key no |
| Copiar AMI compartida | La propiedad **sí** cambia; requiere permiso sobre el snapshot |
| Image Builder | Automatiza crear/mantener/validar/testear AMIs. Servicio gratis |
| AMI aprobadas en prod | **IAM** (tags) previene, **AWS Config** detecta |
