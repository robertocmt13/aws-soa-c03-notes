# 09 — EC2 Storage and Data Management: EBS and EFS

Notas de la Sección 9 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> **Sección completada.** Lecciones 121 a 129 y cuestionario final (6/6): volúmenes EBS, Delete on
> Termination, tipos de volumen, snapshots con Data Lifecycle Manager, Fast Snapshot Restore,
> Archive y Recycle Bin, Amazon EFS con sus modos de rendimiento y clases de almacenamiento, y
> comparativa EBS / EFS / Instance Store.

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

## Snapshots de EBS (lección 124)

Un snapshot es una copia de un volumen EBS en un momento concreto.

- **No hace falta desconectar el volumen**, pero se recomienda. Con la instancia escribiendo, el
  snapshot queda *crash-consistent* (como si se cortara la luz al disco). Para una base de datos,
  parar la escritura o la instancia antes.
- **Hacer un snapshot consume I/O del volumen**: no lanzarlo en horas de mucho tráfico.
- Los snapshots se guardan en S3 y son **regionales, no de una AZ**:
  - **Otra AZ de la misma región:** se crea el volumen desde el snapshot eligiendo la AZ de
    destino. No hace falta copiar nada.
  - **Otra región (u otra cuenta):** primero se **copia el snapshot** a esa región.
- El resultado es una **copia**, no "el mismo disco": a partir de ahí los dos volúmenes van por
  separado.

### Cifrado

Al crear un volumen desde un snapshot se puede marcar *Encrypt*. Un volumen sin cifrar **no se
puede cifrar directamente**: snapshot → volumen nuevo (o copia del snapshot) con cifrado → usar el
volumen nuevo. Los volúmenes creados desde un snapshot cifrado salen cifrados.

### Amazon Data Lifecycle Manager (DLM)

Automatiza la **creación, retención y borrado** de snapshots de EBS y de AMIs respaldadas por EBS.

- Selecciona **volúmenes o instancias por tags** (uno o varios). Sin tags bien puestos, no hay
  backups: otro motivo para etiquetar todo lo que acepte tags.
- La política define el **schedule** y la **retención** (por número de snapshots o por
  antigüedad); los que sobran los borra DLM.
- Opciones avanzadas: copia a otra región o cuenta, activar FSR, archivado.
- **No gestiona snapshots ni AMIs creados fuera de DLM**, ni **AMIs respaldadas por instance
  store**.
- Se limita a EBS. Para backups centralizados de varios servicios (RDS, EFS, DynamoDB...) está
  **AWS Backup**. Examen: snapshots de EBS por tags → DLM; backup centralizado multiservicio →
  AWS Backup.

### Fast Snapshot Restore (FSR)

- Un volumen creado desde un snapshot trae los bloques desde S3 **la primera vez que se lee cada
  uno**: el primer acceso tiene latencia.
- Soluciones: **inicializar el volumen leyéndolo entero con `dd` o `fio`** (gratis, pero tarda) o
  **activar FSR**, que crea el volumen totalmente inicializado.
- FSR se activa **por snapshot y por AZ**, y se cobra por cada combinación. **Muy caro**: en la
  consola de `us-east-1` aparecía a 0,75 $ por hora.
- Mientras está activo, todos los volúmenes que se creen desde ese snapshot en esa AZ salen
  inicializados. Caso de uso: necesitar rendimiento completo nada más crear el volumen (recuperación
  ante desastres, ASG que lanza desde una AMI). Después, desactivarlo.

### Snapshot Archive y Recycle Bin

| | Snapshot Archive | Recycle Bin |
|---|---|---|
| Qué hace | Mueve el snapshot a un nivel de archivo | Retiene los snapshots borrados para poder recuperarlos |
| Ventaja | **75 % más barato** | Protege de borrados accidentales |
| Coste oculto | Restaurar tarda **24 a 72 horas**. Mínimo de **90 días**: si se borra o restaura antes, se cobran los 90 días. Se guarda completo, no incremental | Los snapshots en la papelera **siguen facturando** |
| Configuración | Por snapshot | Reglas de retención de **1 día a 1 año**, para todos los snapshots o filtrando por tags. También para AMIs |

Archive tiene sentido para snapshots que hay que conservar mucho tiempo (cumplimiento, cierres de
año) y que casi nunca se restauran.

---

## Práctica: snapshots (lección 125)

En `us-east-1`. **No necesita instancia**: basta un volumen suelto.

1. Crear un snapshot de un volumen.
2. Crear un volumen a partir del snapshot eligiendo otra AZ. Se ve la opción de cifrar el volumen
   (no se activa).
3. Copiar el snapshot a otra región (en la demo se cancela).
4. Ver la opción de **FSR** sin activarla.
5. Crear una política de **Data Lifecycle Manager**: tipo de recurso (volúmenes o instancias),
   tags objetivo, schedule y opciones avanzadas. La creé **deshabilitada**, como en el curso.
6. La regla del Recycle Bin solo la vi en el vídeo, sin crearla.

**No activar:** FSR (cobra por hora y AZ), Archive (mínimo de 90 días) ni el bloqueo de la regla del
Recycle Bin.

### Coste y limpieza

1. Si hay regla del Recycle Bin, **borrarla antes que los snapshots**; si no, los snapshots borrados
   van a la papelera y siguen facturando.
2. Borrar los snapshots de `us-east-1` **y las copias en otras regiones**.
3. Borrar todos los volúmenes (el original y los restaurados).
4. Borrar la política de DLM.
5. Opcional: borrar el rol `AWSDataLifecycleManagerDefaultRole` que crea la consola.

---

## Amazon EFS (lección 126)

**EFS (Elastic File System) es un NFS gestionado**: una carpeta de red que montan muchas instancias
a la vez, en varias AZs. Lo que escribe una instancia lo ven todas.

- **EBS es un disco** (dispositivo de bloques) para una instancia; **EFS es una carpeta
  compartida**.
- Protocolo **NFSv4.1**. Acceso controlado con un **security group** que debe permitir el **puerto
  2049** desde las instancias.
- **Solo Linux** (POSIX). Windows → FSx.
- Cifrado en reposo con **KMS**.
- Escala solo, sin planificar capacidad. **Se paga por uso** (GB ocupados), pero cada GB cuesta
  unas **3 veces lo que gp2**.
- Casos de uso: gestión de contenidos, servidores web, compartir datos, WordPress.
- Encaja con el **escalado horizontal**: las instancias del ASG no guardan nada en local y lo
  compartido vive en EFS.

### Performance mode (se elige al crear, no se cambia)

| Modo | Para qué |
|---|---|
| **General Purpose** (por defecto) | Latencia baja: web, CMS, WordPress |
| **Max I/O** | Miles de clientes en paralelo con más latencia: big data, procesado de media |

Hoy AWS recomienda General Purpose para casi todo. **Con Elastic throughput solo se puede elegir
General Purpose**: en la consola, Max I/O aparece desactivado.

### Throughput mode (se puede cambiar)

| Modo | Cómo funciona | Cuándo |
|---|---|---|
| **Bursting** | Crece con el tamaño (1 TB = 50 MiB/s, burst a 100 MiB/s), con créditos | Pocos datos y tráfico estable. Mismo problema que gp2 |
| **Provisioned** | Throughput fijo independiente del tamaño (por ejemplo, 1 GiB/s con 1 TB) | Mucho throughput con pocos datos |
| **Elastic** (por defecto) | Escala solo con la carga: hasta 3 GiB/s de lectura y 1 GiB/s de escritura. Se paga por uso | **Cargas impredecibles** |

Mismo patrón que EBS: Bursting ≈ gp2 (ligado al tamaño); Provisioned ≈ gp3/io (independiente).
La consola actual agrupa Elastic y Provisioned bajo **Enhanced**, frente a **Bursting**.

### Storage classes y lifecycle

| Clase | Para qué |
|---|---|
| **Standard** | Ficheros de acceso frecuente |
| **Infrequent Access (EFS-IA)** | Más barato de almacenar, pero **cobra por cada lectura** |
| **Archive** | Datos que se leen pocas veces al año. Alrededor de un 50 % más barato |

- Los ficheros se mueven con una **lifecycle policy** ("sin acceso en N días → IA"). La aplicación
  no nota nada: la ruta es la misma. Valores por defecto de la consola: IA a los 30 días, Archive a
  los 90.
- **Disponibilidad:** **Regional** (Multi-AZ, para producción) o **One Zone** (una AZ, más barato,
  backup activado por defecto, para desarrollo).
- **Ahorro de más del 90 %** combinando la lifecycle policy con IA/Archive. One Zone-IA es la
  combinación más barata, pero si cae la AZ se pierde el acceso a los datos.

---

## Práctica: EFS montado en dos AZs (lección 127)

En `us-east-1`, con dos instancias `t3.micro` (Amazon Linux 2023).

1. Crear el file system: **Regional**, **Elastic**, General Purpose, lifecycle por defecto y
   cifrado en reposo activado por defecto. Sin file system policy. Arranca con **6 KiB** de
   metadatos.
2. Lanzar `instance a` en `us-east-1a` e `instance b` en `us-east-1b`. En la sección *File systems*
   del asistente de EC2 se elige el EFS y el punto de montaje (`/mnt/efs/fs1`). El asistente
   **crea los security groups** y **monta el EFS con user data**, instalando `efs-utils`.
3. Conectar con EC2 Instance Connect. En `instance a`:
   `echo "hello world!" > /mnt/efs/fs1/hello.txt` (con `sudo`, porque la raíz del EFS es de root:
   permisos POSIX normales).
4. En `instance b`, `cat /mnt/efs/fs1/hello.txt` devuelve `hello world!`: mismo sistema de
   ficheros en dos AZs.

### Lo que no se ve a simple vista

- **Automatic backups viene marcado por defecto.** Crea copias diarias en **AWS Backup**, en el
  vault `aws/efs/automatic-backup-vault`, y se facturan aparte. Los recovery points **no se borran
  al borrar el file system**. El vault no se puede borrar, pero vacío no cuesta nada.
- **Security groups que se referencian entre sí.** El asistente crea una pareja por instancia:
  `instance-sg-N` y `efs-sg-N`, con una regla de entrada en el puerto 2049 desde `instance-sg-N`.
  AWS no deja borrar un security group mientras otro lo use en una regla, aunque se seleccionen
  todos a la vez. Primero hay que borrar esas reglas.

### Coste y limpieza

1. Terminar las dos instancias.
2. Borrar el file system en la consola de **EFS** (se lleva los mount targets).
3. **AWS Backup → Backup vaults → `aws/efs/automatic-backup-vault`:** comprobar que no hay
   recovery points.
4. Security groups: borrar las reglas de entrada de los `efs-sg-N` que apuntan a los
   `instance-sg-N` y después borrar todos los creados (`efs-sg-N`, `instance-sg-N` y el que se
   creó a mano).
5. Comprobar que *EC2 → Volumes* queda vacío.

---

## EBS frente a EFS frente a Instance Store (lección 128)

| | EBS | EFS | Instance Store |
|---|---|---|---|
| Qué es | Disco de red | Carpeta NFS compartida | Disco físico del host |
| Instancias | Una (salvo Multi-Attach io1/io2) | Cientos, en varias AZs | Solo la suya |
| Ámbito | Una AZ | Región (o One Zone) | El host |
| Persistencia | Sobrevive a la instancia (salvo raíz con Delete on Termination) | Independiente de las instancias | **Se pierde al parar o terminar** |
| Arranque | Sí (gp/io) | **No** | Sí (formato heredado) |
| Sistema operativo | Linux y Windows | Solo Linux (POSIX) | Linux y Windows |
| Pago | GB aprovisionados | GB usados (más caro por GB) | Incluido en la instancia |
| Rendimiento | Hasta 256.000 IOPS (io2) | Escala con la carga | El máximo (millones de IOPS) |

El sistema operativo va siempre en el volumen raíz (EBS); el EFS se monta después de arrancar.

---

## Cuestionario de la sección

**6 de 6.** Preguntas sobre:

- Qué tipos de volumen **no** pueden ser de arranque: **st1 / sc1**.
- Un gp2 de 8 GB que agota el burst: **aumentar el tamaño del volumen** (más GB = más IOPS base).
- Snapshots inicializados al crear el volumen sin ejecutar comandos en el SO: **Fast Snapshot
  Restore**.
- Un volumen de 8 TB con 2 TB de datos: **el tamaño de un volumen EBS no se puede reducir**. Hay que
  crear uno más pequeño y migrar los datos.
- Los mismos datos como unidad NFS en todas las AZs: **EFS**.
- Mover datos poco usados de EFS a EFS-IA de forma continua: **EFS Lifecycle Management**.

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
| Reducir un volumen EBS | **No se puede**. Volumen nuevo más pequeño y migrar los datos |
| Snapshots | Regionales (en S3). Otra AZ → volumen desde el snapshot. Otra región → copiar el snapshot |
| Cifrar un volumen existente | Snapshot → volumen nuevo cifrado |
| Data Lifecycle Manager | Crea, retiene y borra snapshots/AMIs de EBS por tags. No gestiona lo creado fuera de DLM |
| AWS Backup | Backups centralizados de varios servicios |
| Latencia del primer acceso tras restaurar | **FSR** (caro, por snapshot y AZ) o leer el volumen con `dd` / `fio` |
| Snapshot Archive | 75 % más barato, restauración en 24–72 h, mínimo 90 días |
| Recycle Bin | Recupera snapshots/AMIs borrados. Retención de 1 día a 1 año. Siguen facturando |
| EFS | NFS gestionado, multi-AZ, solo Linux, puerto 2049, pago por uso |
| Performance mode | General Purpose (latencia) / Max I/O (paralelismo). Se elige al crear |
| Throughput mode | Bursting (según tamaño) / Provisioned (fijo) / **Elastic (impredecible)** |
| Ahorro en EFS | Lifecycle policy → IA / Archive. One Zone-IA: lo más barato, sin Multi-AZ |
| Almacenamiento compartido en varias AZs | **EFS** |
| Security group que no se deja borrar | Referenciado por otro security group o asociado a una interfaz de red |
