# 05 — AWS Systems Manager (SSM)

Notas de la Sección 5 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en progreso. Cubierto hasta ahora: lecciones 31 a 42.

---

## Qué es Systems Manager

Servicio para gestionar sistemas **EC2 y on-premises a escala**. Da visibilidad operativa del
estado de la infraestructura, ayuda a detectar problemas, y automatiza el parcheado para
cumplimiento. Funciona con Windows y Linux, se integra con CloudWatch (métricas y dashboards)
y con AWS Config, y **es un servicio gratuito** en su nivel básico.

La idea de fondo: en lugar de entrar máquina por máquina, se tiene un plano de control
centralizado desde el que ejecutar comandos, aplicar parches, consultar inventario y gestionar
configuración.

## Cómo funciona

Tres requisitos, y son la base de casi todas las preguntas de troubleshooting:

1. **SSM Agent** instalado y corriendo en la instancia. Viene preinstalado en Amazon Linux 2 /
   2023 y en algunas AMIs de Ubuntu.
2. **Rol IAM** con la política `AmazonSSMManagedInstanceCore` adjunto a la instancia.
3. **Conectividad** hacia los endpoints de SSM.

> Si una instancia no puede controlarse con SSM, el problema está casi siempre en el agente o
> en los permisos IAM.

Detalle importante: **el agente inicia la conexión saliente hacia AWS**, no al revés. Por eso
no hace falta abrir ningún puerto de entrada en el security group para que SSM funcione. Una
instancia sin SSH, sin HTTP y sin nada abierto aparece igualmente como *managed node*.

Una instancia correctamente configurada aparece en **Fleet Manager → Managed nodes** con el
agente en estado `Online`.

## Las piezas de SSM

| Grupo | Herramientas |
|---|---|
| **Node Tools** | Fleet Manager, Compliance, Inventory, Hybrid Activations, Session Manager, Run Command, State Manager, Patch Manager, Distributor |
| **Change Management** | Automation, Change Calendar, Maintenance Windows, Documents, Quick Setup |
| **Application Tools** | Application Manager, AppConfig, Parameter Store |
| **Operations Tools** | Explorer, OpsCenter, CloudWatch Dashboard |
| **Resource Groups** | Agrupación lógica por tags |

---

## AWS Tags

Pares clave-valor de texto que se pueden añadir a muchos recursos de AWS. El nombre es libre;
los más habituales son `Name`, `Environment`, `Team`.

Se usan para tres cosas:

- **Agrupación** de recursos
- **Automatización** (seleccionar objetivos por tag)
- **Asignación de costes** (cost allocation)

> Regla práctica del curso: **mejor tener demasiados tags que muy pocos.**

Detalle que se ve en la práctica: **el nombre de la instancia es en realidad un tag**. La
columna "Name" de la consola de EC2 no es un campo especial, es el valor del tag `Name`. Por
eso se edita desde *Manage tags*.

## Resource Groups

Permiten crear, ver y gestionar **grupos lógicos de recursos a partir de los tags**. Sirven
para agrupar aplicaciones, capas de un stack, o separar entornos de producción y desarrollo.

- Es un **servicio regional**.
- **No es exclusivo de SSM**: funciona con EC2, S3, DynamoDB, Lambda y otros. Que Run Command
  pueda apuntar a un resource group es una integración, no su razón de ser.

En la práctica se crean grupos filtrando por tipo de recurso (`AWS::EC2::Instance`) más un tag
(`Environment: Dev`), y el grupo recoge automáticamente las instancias que cumplen.

---

## SSM Documents

Un documento SSM define **qué se ejecuta**. Se escriben en **JSON o YAML**, admiten
**parámetros** y definen **acciones**.

Estructura básica de un documento de tipo Command:

```yaml
---
schemaVersion: '2.2'
description: Sample YAML template to install Apache
parameters:
  Message:
    type: "String"
    description: "Welcome Message"
    default: "Hello World"
mainSteps:
- action: aws:runShellScript
  name: configureApache
  inputs:
    runCommand:
    - 'sudo yum update -y'
    - 'sudo yum install -y httpd'
    - 'sudo systemctl start httpd'
    - 'sudo systemctl enable httpd'
    - 'echo "{{Message}} from $(hostname -f)" > /var/www/html/index.html'
```

Los parámetros se referencian con la sintaxis `{{Nombre}}` y se rellenan en el momento de
ejecutar el comando.

**AWS ya trae muchos documentos predefinidos**, propiedad de Amazon, que ahorran tener que
escribirlos. Por ejemplo `AWS-ApplyPatchBaseline` (escanea o instala parches de una patch
baseline) o documentos para ejecutar playbooks de Ansible.

Los documentos son la base compartida de varias herramientas de SSM: los usan **Run Command,
State Manager, Patch Manager, Automation** y Parameter Store.

### Comparación con user data

Conceptualmente el contenido se parece a un script de user data, pero:

| | User data | Run Command con documento |
|---|---|---|
| Cuándo se ejecuta | Solo al arrancar la instancia | Cuando se quiera, sobre instancias ya en marcha |
| Sobre cuántas máquinas | Una, la que se lanza | Muchas a la vez |
| Reutilizable | No | Sí, el documento se versiona y se reutiliza |

---

## SSM Run Command

Ejecuta un documento (o directamente un comando) **sobre múltiples instancias a la vez**.

Características que caen en el examen:

- **No necesita SSH.** Ni bastión, ni key pairs, ni puertos abiertos.
- **Rate Control**: se define la concurrencia (cuántos objetivos en paralelo, en número o
  porcentaje) y un **Error Threshold** para detener la tarea si fallan demasiados.
- Integrado con **IAM** (permisos) y **CloudTrail** (auditoría de quién ejecutó qué).
- La **salida** del comando se puede ver en la consola, o enviar a un **bucket S3** o a
  **CloudWatch Logs**.
- Puede **notificar a SNS** el estado del comando (In progress, Success, Failed…).
- Puede **invocarse desde EventBridge**, lo que permite ejecutarlo por evento o programado.

### Selección de objetivos

Tres formas, y conviene conocer las tres:

1. **Specify instance tags** — todas las instancias que compartan un par clave-valor.
2. **Choose instances manually** — selección explícita.
3. **Choose a resource group** — todas las de un grupo previamente definido.

---

## Práctica realizada

Flujo completo del hands-on:

1. Crear un rol IAM para EC2 con `AmazonSSMManagedInstanceCore` (nombre usado:
   `AmazonEC2RoleForSSM`).
2. Lanzar 3 instancias con ese instance profile, **sin ningún puerto abierto**, para demostrar
   que SSM no necesita acceso entrante. La consola permite lanzar varias a la vez con el campo
   *Number of instances*.
3. Comprobar en **Fleet Manager** que aparecen como managed nodes con el agente `Online`.
4. Etiquetar las instancias (`Environment`, `Team`) y crear resource groups a partir de esos
   tags.
5. Crear un documento SSM en YAML que instala Apache y escribe un mensaje parametrizado.
6. Abrir el puerto 80 en el security group — **esto es para poder ver el resultado en el
   navegador, no para que funcione SSM**.
7. Ejecutar el documento con **Run Command** sobre las tres instancias, con concurrencia de 1
   en 1.
8. Verificar: cada IP pública devuelve el mensaje con el hostname de su propia instancia.

### Problemas encontrados

**1. Región equivocada en la consola**

Las instancias se lanzaron en `eu-north-1`, pero Fleet Manager se abrió en `us-east-1` y
mostraba *"You don't have any managed nodes in this region"*. No era un fallo del agente ni de
los permisos: era estar mirando la región incorrecta.

> **Hábito a adoptar:** comprobar siempre el selector de región al abrir una pestaña nueva de
> la consola. La consola abre las pestañas nuevas en la última región usada en esa sesión, no
> en la que se tenía delante.

**2. Activación accidental de la consola unificada de SSM**

Al buscar los nodos en la región equivocada, se pulsó *"Enable the new experience"*. Esto no es
un cambio cosmético: configura a nivel de cuenta y región un check de **DHMC** con remediación
diaria, recolección de inventario cada 12 horas, actualización automática del agente cada 14
días, y crea roles IAM adicionales.

Queda activado en `us-east-1` y hay que revertirlo en la limpieza.

---

## Notas de servicio (a fecha del curso)

Avisos que aparecen en la consola y que no están en el vídeo:

- El **Advanced Instances Tier ha sido descontinuado**. Los nodos híbridos y multicloud se
  registran sin coste adicional y sin límite de instancias, pero **desde el 30 de septiembre de
  2026 se aplica pay-per-use** al usar Session Manager o Run Command sobre esos nodos. No
  afecta a instancias EC2.
- **Just-in-time node access** es una función nueva de pago (acceso bajo petición en lugar de
  permisos permanentes). No entra en el temario.

---

## SSM Automation

Simplifica tareas comunes de mantenimiento y despliegue **sobre instancias EC2 y otros
recursos de AWS**: reiniciar instancias, crear una AMI, hacer un snapshot de EBS.

### Diferencia clave con Run Command

Esta distinción es la base para elegir la herramienta correcta:

| | Run Command | Automation |
|---|---|---|
| Dónde ejecuta | **Dentro del SO** de la instancia, vía el agente | **Llamadas a la API de AWS**, desde fuera |
| Sobre qué actúa | Instancias con SSM Agent | EC2, EBS, AMIs, RDS, S3… cualquier recurso |
| Ejemplo de paso | `sudo yum install httpd` | `aws:executeAwsApi` → `EC2: CreateSnapshot` |

Las dos se combinan: una automatización puede llamar a Run Command como uno de sus pasos
cuando necesita hacer algo dentro del sistema operativo.

### Automation Runbook

Un runbook es un **documento SSM de tipo Automation** que define las acciones a realizar.
AWS trae **runbooks predefinidos**, y también se pueden crear propios.

La consola muestra el runbook como un **árbol de pasos** con sus rutas de fallo. Ejemplo real:
`AWS-QuarantineEC2Instance` encadena `GetEC2InstanceResources` → `PrepareQuarantineEC2Instance`
→ `createSnapshot` → `verifySnapshot` → `ModifyInstanceAttribute`, con un camino `On failure`
desde cada paso hacia el final.

Están organizados por categorías: Remediation, Patching, Security, Instance management, Data
backup, AMI management, Resource management, Cost management…

### Cómo se dispara

Cuatro formas:

1. **Manualmente** desde la consola, la CLI o el SDK
2. **Amazon EventBridge** (por evento o programado)
3. **Maintenance Windows** (en la ventana de mantenimiento)
4. **AWS Config**, para remediación de reglas

La cuarta es la que más cae en el examen. El patrón es:

> **IAM previene** (rechaza la llamada a la API y el recurso nunca se crea).
> **Config detecta** (evalúa por cambio de configuración o periódicamente cada 1/3/6/12/24 h).
> **Automation remedia** (ejecuta el runbook que corrige el recurso no conforme).

Config es reactivo, no preventivo: **el recurso llega a existir** y se corrige después. Siempre
hay una ventana de exposición, corta pero real. Por eso las tres capas se usan juntas.

### Opciones de ejecución

- **Simple execution** — sobre unos objetivos concretos
- **Rate control** — concurrencia y umbrales de error, igual que en Run Command
- **Multi-account and Region** — ejecutar en varias cuentas y regiones a la vez
- **Manual execution** — paso a paso, para depurar

Los objetivos pueden seleccionarse también por **resource group**.

Algunos runbooks incluyen **pasos de aprobación**: la automatización se detiene y espera
autorización humana antes de continuar (por ejemplo
`AWS-RestartEC2InstanceWithApproval`). Junto con los umbrales de error, es lo que hace la
herramienta usable en producción.

### Caso de uso: Patch AMI & Update ASG

Flujo completo orquestado por Automation, y ejemplo canónico de **infraestructura inmutable**:

1. Lanzar una instancia desde la **Source AMI**
2. **Run Command** con `AWS-RunPatchBaseline` instala los parches
3. Parar la instancia
4. Crear la imagen → **Patched AMI**
5. Terminar la instancia
6. Ejecutar un script Python
7. El script **actualiza el Launch Template** para que apunte a la nueva AMI
8. **Instance refresh** en el Auto Scaling Group

El punto que hay que entender: **los parches no se aplican a las instancias existentes**. El
instance refresh va terminando las máquinas viejas y lanzando nuevas desde el launch template
actualizado. No se parchea el servidor, se sustituye.

> Aviso de coste: replicar este flujo lanza instancias EC2 reales. El servicio Automation es
> gratuito, pero las instancias que orquesta no.

---

## SSM Parameter Store

Almacenamiento seguro y centralizado de **configuración y secretos**.

- **Cifrado opcional** con KMS, transparente para la aplicación
- **Serverless**, escalable, duradero, SDK sencillo
- **Versionado** de configuraciones y secretos
- Control de acceso mediante **IAM**
- **Notificaciones** con EventBridge
- **Integración con CloudFormation**

La idea, comparada con un fichero `.env`: el `.env` vive en el disco de cada servidor, así que
cambiar una contraseña obliga a tocar todas las máquinas. Con Parameter Store el valor está en
un único sitio, la aplicación lo pide cuando lo necesita, y además se gana versionado, cifrado
y permisos por IAM en lugar de "quien tenga acceso al disco, lo lee".

El flujo de lectura de un valor cifrado: la aplicación pide el parámetro → SSM **comprueba los
permisos IAM** → si tiene acceso a la clave KMS, se descifra y se devuelve.

### Jerarquía

Los parámetros se organizan por rutas:

```
/mi-departamento/
  mi-app/
    dev/
      db-url
      db-password
    prod/
      db-url
      db-password
```

Esto permite dos cosas importantes:

- Recuperar toda una rama de golpe con **`GetParametersByPath`** (o valores sueltos con
  `GetParameters`).
- Dar **permisos IAM por prefijo**: que un rol solo pueda leer `/mi-app/dev/*` y no toque
  producción.

### Rutas especiales

**`/aws/service/ami-amazon-linux-latest/...`** — parámetros **públicos** mantenidos por AWS que
siempre contienen el ID de la última AMI de Amazon Linux en esa región. Evitan hardcodear IDs
de AMI, que son regionales y quedan obsoletos:

```yaml
Parameters:
  LatestAmiId:
    Type: 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>'
    Default: '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64'
```

La misma plantilla vale para cualquier región y siempre lanza la imagen actualizada.

**`/aws/reference/secretsmanager/<secret_id>`** — permite leer un secreto de **Secrets
Manager** usando la API de Parameter Store. Sirve para tener un único flujo de lectura de
configuración en el código, vengan los valores de donde vengan.

### Tiers: Standard vs Advanced

| | Standard | Advanced |
|---|---|---|
| Nº de parámetros (por cuenta y región) | 10.000 | 100.000 |
| Tamaño máximo del valor | 4 KB | 8 KB |
| Parameter policies | No | **Sí** |
| Coste | Sin cargo | **0,05 USD por parámetro y mes** |

### Parameter Policies (solo tier advanced)

Permiten asignar un **TTL** a un parámetro para forzar la actualización o el borrado de datos
sensibles como contraseñas. Se pueden aplicar varias políticas a la vez.

| Política | Qué hace |
|---|---|
| `Expiration` | Borra el parámetro en una fecha concreta |
| `ExpirationNotification` | Avisa vía EventBridge N días **antes** de que expire |
| `NoChangeNotification` | Avisa vía EventBridge si el parámetro lleva N días sin cambiar |

El caso de uso típico es forzar la rotación de credenciales.

### Parameter Store vs Secrets Manager

| | Parameter Store | Secrets Manager |
|---|---|---|
| Coste | Gratis en tier estándar | Por secreto |
| Rotación automática | No | **Sí**, integrada con RDS |
| Uso típico | Configuración y secretos sencillos | Credenciales que deben rotar |

> Si el enunciado menciona **rotación automática de credenciales de base de datos**, la
> respuesta es **Secrets Manager**.

### Práctica: crear y leer parámetros

**Por consola.** El nombre del parámetro es donde se define la jerarquía directamente
(`/my-app/dev/db-url`). Antes de crearlo se elige tier (Estándar / Avanzada) y tipo:

| Tipo | Uso |
|---|---|
| `String` | Cualquier valor de cadena |
| `StringList` | Cadenas separadas por comas |
| `SecureString` | Valor cifrado con una clave KMS, propia o de otra cuenta |

Al elegir `SecureString` se selecciona el **ID de la clave KMS**. La clave por defecto es
`alias/aws/ssm` (gestionada por AWS, sin coste). La propia consola avisa de que las claves
gestionadas por AWS no se pueden compartir con otras cuentas: para eso hace falta una customer
managed key.

Hay además un campo **Tipo de datos**, que valida el contenido:

- `text` — sin validación
- `aws:ec2:image` — SSM **verifica que el valor sea un AMI ID que existe** en esa región antes
  de guardarlo. Útil para tener un parámetro tipo `/mi-empresa/golden-ami` que consumen las
  plantillas, y evita el fallo de escribir un ID mal o de otra región.

Cada parámetro tiene su propio **ARN**, su **versión** y un **historial** de cambios. El valor
de un SecureString aparece oculto en el panel y hay que pulsar "Mostrar el valor descifrado".

**Por CLI.** Lo importante de este bloque:

```bash
# Varios parámetros por nombre — el SecureString sale CIFRADO
aws ssm get-parameters --names /my-app/dev/db-url /my-app/dev/db-password

# Con --with-decryption sale en claro
aws ssm get-parameters --names /my-app/dev/db-url /my-app/dev/db-password --with-decryption

# Toda una rama de la jerarquía
aws ssm get-parameters-by-path --path /my-app --recursive
```

Dos detalles que se aprenden solo haciéndolo:

- **Sin `--with-decryption`**, el valor del SecureString se devuelve como un blob cifrado en
  base64. Para descifrarlo, la identidad IAM necesita permiso **sobre la clave KMS**, no solo
  sobre el parámetro. Son dos permisos distintos.
- **Sin `--recursive`**, `get-parameters-by-path` solo devuelve el nivel inmediato de la ruta.
  Con `--path /my-app` a secas no sale nada, porque los parámetros están un nivel más abajo.

> Sobre el ARN: es el identificador único y global de un recurso, con la forma
> `arn:aws:<servicio>:<región>:<cuenta>:<recurso>`. Donde más se usa es en políticas IAM, para
> dar permisos por prefijo:
> `"Resource": "arn:aws:ssm:eu-north-1:<cuenta>:parameter/my-app/dev/*"`

---

## SSM Fleet Manager

Interfaz para **gestionar de forma centralizada y remota** los nodos, estén en AWS o
on-premises: instancias EC2, servidores y VMs on-premise, dispositivos edge e IoT. Soporta
Windows y Linux.

Requisitos, los de siempre: **agente SSM instalado** y permisos, sea con
`AmazonSSMManagedInstanceCore` en el rol de la instancia o mediante **DHMC**.

Casos de uso:

- Seguir el estado, salud y rendimiento de los nodos
- Tareas de troubleshooting y administración: navegar el sistema de ficheros, ver logs,
  consultar el registro de Windows, listar procesos
- Abrir **RDP** en Windows o una shell con **Session Manager**

### Fleet Manager vs Automation vs CloudWatch

Tres herramientas que se confunden fácil pero no se solapan:

| | Para qué |
|---|---|
| **Fleet Manager** | Mirar y **actuar a mano** sobre un nodo concreto. Es el "SSH de investigación" |
| **Automation** | Ejecutar un runbook definido de antemano, **sin intervención** |
| **CloudWatch** | Recoger **datos** (métricas, logs) y alertar. Unidireccional, no da acceso |

El flujo real las encadena: la alarma de CloudWatch avisa de que el disco está al 90% y muestra
desde cuándo → se entra con Fleet Manager a ver qué carpeta ha crecido y limpiarla → si el
problema se repite, se escribe un runbook de Automation para que se resuelva solo.

Fleet Manager mira **dentro de los servidores**; CloudWatch observa los **servicios desde
fuera** (y no se limita a EC2: cubre RDS, S3, Lambda…).

---

## Default Host Management Configuration (DHMC)

Configura automáticamente las instancias EC2 como managed instances **sin usar un EC2 Instance
Profile**.

### Cómo funciona

1. La instancia se identifica ante SSM mediante el **Instance Identity Role**, un tipo de rol
   IAM **sin permisos** más allá de identificar la instancia ante los servicios de AWS.
2. SSM verifica esa identidad y le pasa el rol real,
   `AWSSystemsManagerDefaultEC2InstanceManagementRole`, que es el que lleva los permisos
   (política `AmazonSSMManagedEC2InstanceDefaultPolicy`).

La instancia demuestra quién es y SSM le entrega los permisos, en lugar de llevarlos encima
desde el principio.

### Requisitos y alcance

- **IMDSv2 obligatorio.** No soporta IMDSv1. Si una instancia no aparece con DHMC activado,
  esta es la primera sospecha.
- **Agente SSM 3.2.582.0 o superior.**
- **Se habilita por región**, no por cuenta.
- Activa automáticamente **Session Manager, Patch Manager e Inventory**, y **mantiene el agente
  actualizado**.

### Ventajas y matices

La ventaja de seguridad es real: con el método clásico, quien consiga acceso a la instancia
puede robar las credenciales del instance profile desde el metadata. Con DHMC no hay
credenciales permanentes ahí.

Pero conviene saber:

- **Es todo o nada en la región**: gestiona *todas* las instancias EC2, incluidas las que
  quizá no quieres en SSM.
- **El rol es genérico**: cubre la gestión de SSM. Si la aplicación necesita acceder a S3,
  DynamoDB u otros servicios, sigue haciendo falta un instance profile propio para eso.
- **Si una instancia ya tiene instance profile, ese gana.** DHMC solo actúa sobre las que no
  tienen ninguno. Desactivar DHMC tampoco afecta a esas instancias.

### Adopción en entornos existentes

No hace falta recrear la flota. **IMDSv2 se activa en caliente**, sin parar la instancia:

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxx \
  --http-tokens required \
  --http-endpoint enabled
```

El riesgo es que alguna aplicación siga usando IMDSv1. Antes de forzarlo conviene revisar la
métrica de CloudWatch **`MetadataNoToken`**, que cuenta las llamadas que aún usan v1: si está a
cero, se puede forzar sin miedo.

La adopción real es gradual: se activa DHMC, las instancias nuevas nacen gestionadas, y las
antiguas siguen con su instance profile hasta que toque renovarlas por otro motivo. Si además
se va a crear una AMI nueva de todas formas, ahí sí compensa dejarla ya con IMDSv2 y el agente
al día.

> **IMDSv2 no se hereda de la AMI**: es un atributo de la instancia. Lo que sí se puede es
> fijarlo en el **launch template**, para que todo lo que se lance desde ahí venga con v2
> obligatorio.

### Práctica realizada

1. Activar DHMC en **eu-north-1** desde Fleet Manager → *Configurar la administración de hosts
   predeterminada*. La propia pantalla ofrece **crear el rol** en el momento.
2. Lanzar una instancia (`DemoInstance`, Amazon Linux 2023) **sin ningún rol IAM**. La consola
   ya la crea con *Versión de metadatos: Solo V2 (token obligatorio)*, avisando de que las
   aplicaciones que usen V1 dejarán de funcionar.
3. Comprobar en los detalles de la instancia: **Rol de IAM vacío**, `IMDSv2: Required`.
4. En Fleet Manager, la instancia aparece igualmente como **Online**, con la versión del agente
   (3.3.4624.0 en esta prueba).

Detalle curioso: en los detalles de EC2 el campo **"Administradas" pone `falso`** — porque no
tiene instance profile — y aun así SSM la gestiona. Son dos vistas distintas del mismo hecho.

> En el vídeo la instancia no aparecía y hubo que revisar la versión del agente. Con la AMI de
> Amazon Linux 2023 actual el agente ya viene por encima del mínimo y funciona directamente.

---

## SSM Inventory

Recolecta **metadatos** de los nodos gestionados, EC2 y on-premises: software instalado, drivers
del SO, configuraciones, actualizaciones aplicadas, servicios en ejecución.

- Se puede **fijar el intervalo** de recolección (minutos, horas, días). El mínimo real es de 30
  minutos: no es una herramienta de tiempo real.
- Los datos se ven en la **consola**, o se almacenan en **S3** para consultarlos con **Athena** y
  representarlos con **QuickSight**.
- Permite **consultar datos de varias cuentas y regiones** de forma centralizada.
- Se puede definir **Custom Inventory** para metadatos propios (el ejemplo del curso: la ubicación
  en rack de cada nodo).
- Es de solo lectura y **no tiene coste** por sí mismo.

### Athena y QuickSight

Ninguno de los dos es de SSM; aparecen aquí solo como consumidores del inventario:

- **Athena** ejecuta consultas SQL directamente sobre ficheros en S3, sin cargar nada en una base
  de datos. Se factura por **volumen de datos escaneados** en cada consulta.
- **QuickSight** es la capa de dashboards encima de esos datos.

Para el examen basta la cadena: **Inventory → Resource Data Sync → S3 → Athena → QuickSight**.

### Inventory vs CloudWatch

Se parecen en que ambos recogen información de las máquinas, pero el eje que los separa no es la
cantidad de datos sino **estado frente a serie temporal**:

| | CloudWatch | Inventory |
|---|---|---|
| Qué almacena | Valores numéricos en el tiempo | Hechos sobre la máquina |
| Ejemplo | CPU al 40 % a las 15:03 | Kernel 6.1.x, `httpd 2.4.62` instalado |
| Cadencia | Segundos o minutos | 30 minutos como mínimo |
| Pregunta que responde | ¿Cómo se comporta? | ¿Qué hay dentro? |

### Dónde se consultan los datos

| Vista | Requisitos |
|---|---|
| **Inventory → Dashboard** | Ninguno. Tarjetas predefinidas sobre los nodos de la región |
| **Fleet Manager → nodo → Inventory** | Ninguno. Los datos de una máquina concreta |
| **Inventory → Detailed View** | **Resource Data Sync + AWS Glue + Athena**. Tiene coste |

Solo la tercera necesita infraestructura adicional. Es fácil confundirse y pensar que sin sync no
se ve el inventario.

---

## SSM State Manager

Automatiza el mantenimiento de los nodos gestionados **en un estado definido**.

La unidad de trabajo es la **association**, que se compone de tres cosas:

1. El **estado** que se quiere mantener, expresado como un **documento SSM**
2. Los **objetivos** (por tags, manualmente o por resource group)
3. Un **schedule**: cada cuánto se aplica

Casos de uso típicos: aprovisionar software al arrancar (*bootstrap*), aplicar actualizaciones del
SO de forma periódica, mantener el agente de CloudWatch configurado, garantizar que un antivirus
está instalado o que un puerto está cerrado.

### El matiz importante: State Manager no decide nada

Es tentador imaginar un bucle del tipo *"State Manager consulta Inventory, ve que falta un parche y
lo instala"*. **Ese bucle no existe.**

State Manager es un **planificador**: ejecuta el documento sobre los objetivos con la periodicidad
indicada, siempre, haya cambiado algo o no. Quien decide qué hace falta es **el documento**, porque
está escrito para ser **idempotente**: `AWS-RunPatchBaseline` entra en la máquina, compara contra
la patch baseline y aplica solo lo que falta. Si ya está al día, no hace nada.

Inventory es el lado de **lectura** (qué hay) y Compliance el de **resultado** (si la association
quedó conforme). Ninguno de los dos alimenta a State Manager.

> La forma correcta de plantear *"quiero este parche en todas las instancias con
> `Environment: Dev`"* es: una association con `AWS-RunPatchBaseline`, objetivo por ese tag, con
> schedule. El destino es ese; lo que no existe es la consulta previa al inventario.

El bucle real de *"comprobar el estado y corregir si no cumple"* sí está en AWS, pero es el trío ya
visto en Automation: **IAM previene → Config detecta → Automation remedia**.

Detalle que cierra el círculo: **la propia recolección de Inventory es una association de State
Manager**, con el documento `AWS-GatherSoftwareInventory`. Cuando en la consola se configura el
inventario, lo que se crea por debajo es una association. Es el mejor ejemplo de que State Manager
es el motor de programación de SSM y no una herramienta con criterio propio.

### Run Command vs State Manager

Las dos ejecutan documentos sobre instancias. La diferencia es el eje temporal:

| | Run Command | State Manager |
|---|---|---|
| Cuándo se ejecuta | **Una vez**, cuando se lanza | **De forma recurrente**, según schedule |
| Para qué sirve | Una acción puntual sobre la flota | Mantener una configuración en el tiempo |
| Qué deja detrás | Un historial de ejecución | Una association viva |
| Instancias nuevas | No las alcanza | **Sí**, si encajan con el targeting por tag |

Esa última fila es la que más se aprovecha en la práctica: una association apuntando a un tag
alcanza automáticamente a cualquier instancia futura que nazca con ese tag.

---

## Resource Data Sync

Envía el inventario de una región a un **bucket S3**, para poder consultarlo de forma centralizada.
Varias regiones y varias cuentas pueden escribir al mismo bucket, y ahí es donde entra la consulta
con Athena.

Los objetos quedan organizados por tipo de dato, cuenta y región:

```
AWS:InstanceInformation/accountid=<cuenta>/region=eu-north-1/...
```

**El sync no crea el bucket**: tiene que existir antes, y con una bucket policy que permita a SSM
escribir en él.

### Práctica realizada

1. Lanzar 3 instancias `t3.micro` con el instance profile `AmazonEC2RoleForSSM` y los tags
   `Environment` y `Team` (`ContabilidadDev`, `ContabilidadPro`, `DesarrolloDev`).
2. Crear el bucket S3 en `eu-north-1`.
3. Añadirle una bucket policy que autorice al servicio SSM a escribir.
4. Crear el Resource Data Sync desde **Inventory → Resource data syncs → Create**.
5. Verificar `Last status: Successful` y comprobar los objetos en el bucket.

La bucket policy se resolvió leyendo la documentación de AWS, sin seguir el vídeo. Es el patrón
estándar de *"un servicio de AWS escribe en mi bucket"* y conviene entender por qué tiene la forma
que tiene:

```json
{
  "Sid": "SSMBucketPermissionsCheck",
  "Effect": "Allow",
  "Principal": { "Service": "ssm.amazonaws.com" },
  "Action": "s3:GetBucketAcl",
  "Resource": "arn:aws:s3:::<bucket>"
},
{
  "Sid": "SSMBucketDelivery",
  "Effect": "Allow",
  "Principal": { "Service": "ssm.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": ["arn:aws:s3:::<bucket>/*/accountid=<cuenta>/*"],
  "Condition": {
    "StringEquals": {
      "s3:x-amz-acl": "bucket-owner-full-control",
      "aws:SourceAccount": "<cuenta>"
    },
    "ArnLike": {
      "aws:SourceArn": "arn:aws:ssm:*:<cuenta>:resource-data-sync/*"
    }
  }
}
```

- Son **dos sentencias con recursos distintos a propósito**: `s3:GetBucketAcl` es SSM comprobando
  que puede escribir *antes* de intentarlo, por eso apunta al bucket a secas, sin `/*`.
  `s3:PutObject` es la escritura real y apunta a la ruta.
- Las condiciones `aws:SourceAccount` y `aws:SourceArn` **no son decoración**: sin ellas la política
  autoriza al servicio SSM de **cualquier cuenta** a escribir en el bucket. Es la protección contra
  el problema del *confused deputy*.
- El `Sid` debe ser **alfanumérico**: un espacio delante del nombre es un error silencioso fácil de
  colar.

### Problemas encontrados

**1. `PermanentRedirect`: el nombre del bucket ya existía**

Al crear el sync con el bucket llamado `demo-ssm-inventory`:

```
[ResourceDataSyncInvalidConfigurationException] S3 write failed ... due to
[The bucket is in this region: eu-central-1. Please use this region to retry
the request (Status Code: 301; Error Code: PermanentRedirect)]
```

La causa no era la región configurada en el formulario, sino que **ese nombre de bucket ya existía
y era de otra cuenta**, en `eu-central-1`. El **espacio de nombres de S3 es global**: no hay dos
buckets con el mismo nombre en todo AWS, independientemente de la cuenta y la región. Cualquier
nombre genérico está cogido.

> En el examen esto aparece disfrazado: *"el equipo no puede crear un bucket con el nombre X, ¿por
> qué?"* → el nombre ya está en uso a nivel global.

**2. `Cannot get Role for the user` en Detailed View**

Con el sync ya funcionando (`Successful`), la pestaña **Detailed View** devuelve ese error.

No es un problema del sync ni de permisos del usuario. La Detailed View **no lee de S3
directamente**: necesita un **crawler de AWS Glue** que catalogue los ficheros y **Athena** para
consultarlos, y para eso la documentación exige configurar la entidad IAM y un rol de servicio
específico (`Amazon-GlueServiceRoleForSSM`) que no existe hasta que se monta esa integración. La
consola falla al buscarlo, y falla igual siendo administrador: no falta un permiso, falta un rol.

**Decisión: no se ha montado.** Implica dejar un crawler de Glue ejecutándose y consultas de Athena,
**ambos facturables** (la propia consola lo avisa en un banner), y no entra en el temario del
SOA-C03. Para verificar la práctica basta con comprobar los objetos directamente en el bucket.

---

## Limpieza

| Recurso | ¿Factura? | Nota |
|---|---|---|
| Instancias EC2 | **Sí** | Lo único que cuesta de verdad. Terminar siempre |
| Volúmenes EBS raíz | **Sí** | Se borran solos al terminar la instancia |
| Documento SSM propio | No | Documents → Owned by me |
| Resource groups | No | Regionales |
| Security group | No | — |
| Rol IAM `AmazonEC2RoleForSSM` | No | **Conservar**: se reutiliza en el resto de la sección |
| Parámetros de Parameter Store | No | Tier estándar, sin coste. Clave `alias/aws/ssm` tampoco cuesta |
| Resource Data Sync | No | Borrarlo **primero**, para que deje de escribir. Borrarlo **no vacía el bucket** |
| Bucket S3 del inventario | **Sí** | Vaciar y después borrar. La consola no borra un bucket con objetos |
| Associations de State Manager | No | Borrarlas: si apuntan a un tag, alcanzan a cualquier instancia futura con ese tag |
| DHMC | No | Se desactiva desde Fleet Manager. Desactivarlo no afecta a instancias con instance profile |
| Rol `AWSSystemsManagerDefaultEC2InstanceManagementRole` | No | Lo crea DHMC al activarlo |
| Consola unificada en `us-east-1` | No | Pendiente de revertir |
| Bucket `do-not-delete-ssm-diagnosis-<cuenta>-us-east-1-…` | **Sí** | Lo crea la función *Diagnose and remediate* de la consola unificada. Borrarlo **después** de desactivarla, o se vuelve a crear |

### Orden de borrado del inventario

El Resource Data Sync **no se borra desde la pestaña de Inventory**, que solo lo lista. Está en
Fleet Manager, en la pestaña de gestión de la cuenta. Como AWS ha movido esa pantalla varias veces
entre Inventory, Fleet Manager y Settings, la CLI va a tiro fijo:

```bash
aws ssm list-resource-data-sync --region eu-north-1
aws ssm delete-resource-data-sync --sync-name DemoSync --region eu-north-1
```

Después se vacía y se borra el bucket. Borrar el sync corta la escritura, pero **no elimina los
objetos ya sincronizados**.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| Requisitos de SSM | Agente + rol IAM (`AmazonSSMManagedInstanceCore`) + conectividad |
| Instancia no gestionada | El problema es el agente o los permisos IAM |
| Dirección de la conexión | El agente sale hacia AWS; no hace falta abrir puertos de entrada |
| Tags | Agrupación, automatización y cost allocation. El nombre es un tag |
| Resource Groups | Agrupación lógica por tags. **Regional**. No solo para EC2 |
| Documents | JSON o YAML, con parámetros y acciones. Los usa Run Command, State Manager, Patch Manager y Automation |
| Run Command | Ejecuta sobre muchas instancias **sin SSH**. Rate control y error threshold |
| Objetivos de Run Command | Por tags, manualmente, o por resource group |
| Salida de Run Command | Consola, S3 o CloudWatch Logs. Notificaciones vía SNS |
| Invocación automática | EventBridge |
| Run Command vs Automation | Dentro del SO vs llamadas a la API de AWS |
| Disparadores de Automation | Consola/CLI/SDK, EventBridge, Maintenance Windows y **AWS Config** |
| Las tres capas | IAM previene, Config detecta, Automation remedia |
| Parchear una flota | `AWS-RunPatchBaseline` → nueva AMI → launch template → **instance refresh** del ASG |
| Parameter Store | Configuración y secretos, jerárquico, cifrado con KMS, permisos por prefijo |
| `GetParametersByPath` | Recupera toda una rama de la jerarquía |
| Parameter policies | TTL para forzar rotación. **Solo en tier advanced (de pago)** |
| Rotación automática de credenciales | **Secrets Manager**, no Parameter Store |
| `--with-decryption` | Necesario para leer un SecureString en claro. Requiere permiso **sobre la clave KMS** |
| `--recursive` | Sin él, `get-parameters-by-path` solo devuelve el nivel inmediato |
| Tipo de dato `aws:ec2:image` | Valida que el valor sea un AMI ID existente en esa región |
| Fleet Manager | Investigar y actuar a mano sobre un nodo. No solo EC2: on-premise, VMs, edge, IoT |
| Inventory | Metadatos de los nodos: software, drivers, configuración, servicios. Solo lectura y sin coste |
| Inventory vs CloudWatch | Estado (qué hay dentro) vs serie temporal (cómo se comporta) |
| Consulta centralizada del inventario | **Resource Data Sync → S3 → Athena → QuickSight**, multi-cuenta y multi-región |
| State Manager | Mantiene los nodos en un estado definido mediante **associations** (documento + objetivos + schedule) |
| State Manager no consulta Inventory | La idempotencia está **en el documento**, no en el planificador |
| Recolección de Inventory | Es una **association de State Manager** con `AWS-GatherSoftwareInventory` |
| Run Command vs State Manager | Una vez vs recurrente. Solo State Manager alcanza a instancias futuras con el tag |
| Nombres de bucket S3 | **Namespace global**. Un nombre repetido da `301 PermanentRedirect` |
| Bucket policy para un servicio | `GetBucketAcl` sobre el bucket + `PutObject` sobre la ruta, con `aws:SourceAccount` y `aws:SourceArn` contra el *confused deputy* |
| DHMC | Instancias gestionadas **sin instance profile**. Por región. Requiere **IMDSv2** y agente ≥ 3.2.582.0 |
| Instance Identity Role | Rol **sin permisos**, solo identifica la instancia ante AWS |
| Instancia con instance profile | DHMC no la toca; el instance profile tiene prioridad |
| `MetadataNoToken` | Métrica de CloudWatch para saber si algo aún usa IMDSv1 antes de forzar v2 |
