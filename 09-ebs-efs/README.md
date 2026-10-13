# 09 — EC2 Storage and Data Management: EBS and EFS

Notas de la Sección 9 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> **En curso.** Lecciones 121 a 123: qué es un volumen EBS, el atributo Delete on Termination,
> práctica de creación y attach de volúmenes y tipos de volumen EBS.

---

## Qué es un volumen EBS (lección 121)

Un volumen **EBS (Elastic Block Store)** es un **disco de red** que se adjunta a una instancia
mientras está en ejecución. Los datos persisten aunque la instancia se termine.

- **Va por red, no es un disco físico del host.** Puede haber algo de latencia, y a cambio se
  puede desconectar de una instancia y conectar a otra rápidamente.
- **Una instancia por volumen**, como regla general. La excepción es **EBS Multi-Attach**: solo
  con **io1/io2**, todas las instancias **en la misma AZ**, y con un sistema de ficheros que
  admita escritura concurrente desde varios nodos (un ext4 o XFS normal montado en dos máquinas
  se corrompe).
- **Está ligado a una Availability Zone.** Un volumen de `us-east-1a` no se puede adjuntar a una
  instancia de `us-east-1b`. Para moverlo a otra AZ (o región) hay que hacer un **snapshot** y
  crear un volumen nuevo a partir de él en el destino.
- **Capacidad aprovisionada:** se define en GB y en IOPS, y **se paga todo lo aprovisionado,
  no lo usado**. Un volumen de 100 GB con 2 GB ocupados se cobra como 100 GB. La capacidad se
  puede ampliar con el tiempo.

### La analogía del "USB de red"

El curso lo compara con un **pendrive de red**: se desconecta de una máquina y se conecta a otra.
La analogía falla en un punto que es justo lo que pregunta el examen: un USB te lo llevas a
cualquier sitio, y un volumen EBS **no sale de su AZ** sin pasar por un snapshot. Se parece más a
una LUN iSCSI de una cabina: va por red y solo es accesible dentro de su "rack" (la AZ).

---

## Delete on Termination

Atributo de cada volumen que controla qué pasa con él cuando la instancia se termina:

| Volumen | Por defecto |
|---|---|
| **Raíz** | Marcado: **se borra** con la instancia |
| **Adicionales** | Desmarcado: **sobreviven** a la instancia |

- Se elige al lanzar la instancia y se puede cambiar desde la consola o la CLI. En una instancia
  ya lanzada, el del volumen raíz se cambia con la CLI
  (`aws ec2 modify-instance-attribute --block-device-mappings ...`).
- **Caso de uso / pregunta de examen:** conservar el volumen raíz al terminar la instancia →
  **desmarcar Delete on Termination**.
- Es la causa típica de coste "fantasma": terminas la instancia, el volumen adicional queda en
  estado *available* y sigue facturando.

---

## Práctica: crear y adjuntar volúmenes (lección 122)

En `us-east-1`, con una instancia `t3.micro` en `us-east-1d`.

1. Crear un volumen **gp3 de 2 GiB en la misma AZ** que la instancia (`us-east-1d`). **Hay que
   fijarse en la AZ al crear el volumen**, porque el asistente no la toma de ninguna instancia.
2. Adjuntarlo a la instancia como `/dev/sdf`. En la pestaña *Storage* aparecen los dos volúmenes
   *In-use*: el raíz `/dev/xvda` de 8 GiB y el nuevo `/dev/sdf` de 2 GiB.
3. Crear otro volumen de 2 GiB en **otra AZ** (`us-east-1a`) para comprobar que no se puede
   adjuntar: el selector de *Attach volume* solo muestra instancias de la misma AZ y dice
   *No matching running or stopped instances in use1-az1 (us-east-1a)*.
4. Borrar ese volumen y terminar la instancia.

### Lo que se ve en la práctica

- **El aviso al terminar la instancia** lista los volúmenes que **no** tienen Delete on
  Termination y avisa de que seguirán facturando. Después de terminar, el raíz de 8 GiB
  desaparece de la lista y el de 2 GiB se queda.
- **El volumen raíz tiene Snapshot ID** (`snap-...`) porque se crea a partir del snapshot de la
  AMI: una AMI respaldada por EBS es, en el fondo, uno o varios snapshots más metadatos. El
  volumen creado a mano no tiene snapshot.
- **Nombre de AZ frente a ID de AZ.** La consola muestra `use1-az6 (us-east-1d)`. El nombre
  (`us-east-1d`) se asigna de forma distinta en cada cuenta. El ID (`use1-az6`) identifica la
  misma AZ física en todas las cuentas.
- **Nombre del dispositivo:** aunque se adjunte como `/dev/sdf`, en una instancia Nitro (como
  `t3`) Linux lo ve como **`/dev/nvme1n1`**, porque en Nitro los volúmenes EBS se presentan como
  NVMe. El volumen llega sin formatear: hay que crear el sistema de ficheros y montarlo.

### Coste y limpieza

**Coste:** mínimo (instancia y volúmenes durante unos minutos).

**Limpieza:**

1. Terminar la instancia (se lleva el volumen raíz).
2. **Borrar a mano los volúmenes creados**, también el de la otra AZ. El de 2 GiB adjuntado
   **no** se borra con la instancia.
3. Borrar el security group del asistente (`launch-wizard-N`).
4. Comprobar que *EC2 → Volumes* queda vacío.

---

## Tipos de volumen EBS (lección 123)

Seis tipos, que se caracterizan por **tamaño, throughput e IOPS**:

| Familia | Tipos | Para qué |
|---|---|---|
| General Purpose SSD | **gp2 / gp3** | Equilibrio precio/rendimiento: volúmenes de arranque, escritorios virtuales, entornos de desarrollo y pruebas, bases de datos medianas |
| Provisioned IOPS SSD | **io1 / io2 Block Express** | Máximo rendimiento sostenido y baja latencia: bases de datos críticas |
| Throughput Optimized HDD | **st1** | Bajo coste, acceso frecuente y secuencial: big data, data warehouses, procesado de logs |
| Cold HDD | **sc1** | El coste más bajo, acceso poco frecuente |

**Solo gp2/gp3 e io1/io2 pueden ser volumen de arranque.** st1 y sc1 no.

### Resumen de características

| | gp3 | gp2 | io2 Block Express | io1 | st1 | sc1 |
|---|---|---|---|---|---|---|
| Tipo | SSD | SSD | SSD | SSD | HDD | HDD |
| Tamaño | 1 GiB – 64 TiB | 1 GiB – 16 TiB | 4 GiB – 64 TiB | 4 GiB – 16 TiB | 125 GiB – 16 TiB | 125 GiB – 16 TiB |
| IOPS máx. | 80.000 | 16.000 | 256.000 | 64.000 (Nitro), 32.000 (resto) | 500 | 250 |
| Throughput máx. | 2.000 MiB/s | 250 MiB/s | 4.000 MiB/s | 1.000 MiB/s | 500 MiB/s | 250 MiB/s |
| Rendimiento | 3.000 IOPS / 125 MiB/s base, ampliables por separado | 3 IOPS/GiB, burst a 3.000 | Aprovisionado (1.000 IOPS:GiB) | Aprovisionado (50 IOPS:GiB) | Por throughput | Por throughput |
| Arranque | Sí | Sí | Sí | Sí | No | No |
| Multi-Attach | No | No | Sí | Sí | No | No |

> **La tabla resumen del curso está desactualizada en gp3:** dice 16 TiB, 16.000 IOPS y
> 1.000 MiB/s. Los límites actuales son 64 TiB, 80.000 IOPS y 2.000 MiB/s, como dice la
> diapositiva de casos de uso y como muestra la propia consola al crear un volumen.

### gp2 frente a gp3: por qué uno va ligado al tamaño y el otro no

Son dos generaciones distintas:

- **gp2 (diseño antiguo):** **3 IOPS por GiB**, con máximo de 16.000 IOPS (se alcanza en
  5.334 GiB). Para tener más IOPS había que comprar más disco aunque no hiciera falta. Los
  volúmenes pequeños compensan con **créditos de burst** hasta 3.000 IOPS; cuando se agotan, el
  volumen cae a su rendimiento base. Se vigila con la métrica **`BurstBalance`** de CloudWatch:
  "el disco iba bien y de repente va lento" en un gp2 pequeño suele ser burst agotado.
- **gp3 (diseño nuevo):** base garantizada de **3.000 IOPS y 125 MiB/s sea cual sea el tamaño**.
  IOPS y throughput se amplían **por separado** y se pagan aparte, sin tocar los GB. Es más barato
  por GB que gp2 y es la opción por defecto. Se puede migrar de gp2 a gp3 en caliente.

### io1 / io2: rendimiento aprovisionado, no "el disco más rápido"

- **Todos los EBS son discos de red**, también io1/io2. Que en Nitro se vean como NVMe es la
  interfaz, no un disco local.
- Lo que aportan es **rendimiento aprovisionado y constante**: los IOPS que pides los tienes
  siempre, sin créditos ni burst. Para aplicaciones críticas o que necesitan más de 80.000 IOPS.
- **io2 Block Express:** latencia por debajo del milisegundo, hasta 256.000 IOPS y durabilidad del
  99,999 %.
- Son los únicos que admiten **Multi-Attach**.
- **Lo más rápido en EC2 es el Instance Store** (discos NVMe físicos del host, millones de IOPS),
  pero **los datos se pierden al parar o terminar la instancia**. Examen: máximo I/O con datos
  temporales o replicados → Instance Store; alto rendimiento con datos persistentes → io2.

### st1 y sc1: cuándo tienen sentido

- Los HDD de EBS rinden en **lecturas secuenciales grandes**: sus IOPS se miden en bloques de
  1 MiB. Las lecturas pequeñas y aleatorias (buscar un fichero concreto) son lo que peor hacen.
- Tienen sentido cuando los datos **tienen que estar en un sistema de ficheros montado en un
  servidor**: st1 para uso frecuente (procesado de logs, big data); sc1 para datos fríos que se
  leen de vez en cuando y en bloque (un histórico de logs, datos de una aplicación heredada).
- Para archivar documentos que casi nunca se consultan (facturas antiguas, por ejemplo) lo natural
  en AWS es **S3** con sus clases de almacenamiento frío, no sc1.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| EBS | Disco de red, persistente, **ligado a una AZ**. Se paga lo aprovisionado |
| Mover un volumen de AZ o región | **Snapshot** → volumen nuevo en el destino |
| Una instancia por volumen | Salvo **Multi-Attach**: solo io1/io2, misma AZ, FS de clúster |
| Delete on Termination | Raíz: se borra por defecto. Adicionales: sobreviven. Conservar el raíz → desmarcarlo |
| Volúmenes de arranque | gp2/gp3 e io1/io2. **st1/sc1 no** |
| gp3 | 3.000 IOPS / 125 MiB/s base, ampliables **independientemente** del tamaño |
| gp2 | 3 IOPS/GiB, burst a 3.000, máx. 16.000. Vigilar `BurstBalance` |
| io1 / io2 Block Express | IOPS aprovisionados y sostenidos. 64.000 / 256.000 máx. Bases de datos críticas |
| st1 | HDD, throughput, acceso frecuente: big data, data warehouse, logs |
| sc1 | HDD, coste mínimo, acceso poco frecuente |
| HDD | Mínimo 125 GiB, sin arranque, sin Multi-Attach |
| Máximo rendimiento de I/O | Instance Store (efímero). Persistente → io2 |
