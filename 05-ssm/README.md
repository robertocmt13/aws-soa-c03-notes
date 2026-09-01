# 05 — AWS Systems Manager (SSM)

Notas de la Sección 5 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en progreso. Cubierto hasta ahora: lecciones 31 a 34.

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
