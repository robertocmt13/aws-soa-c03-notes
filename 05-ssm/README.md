# 05 — AWS Systems Manager (SSM)

Notas de la Sección 5 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en progreso. Cubierto hasta ahora: lecciones 31 a 37.

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
| Consola unificada en `us-east-1` | No | Pendiente de revertir |

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
