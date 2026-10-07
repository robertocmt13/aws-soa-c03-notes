# 08 — Lambda for CloudOps

Notas de la Sección 8 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> **Sección completada.** Lecciones 115 a 120 y cuestionario final (3/3): qué es Lambda frente a
> EC2, ventajas, lenguajes soportados, integraciones principales, precios, primera práctica con una
> función en Python, Lambda programada con EventBridge y Lambda disparada por S3 Event
> Notifications.

---

## Por qué Lambda (lección 115)

| | EC2 | Lambda |
|---|---|---|
| Qué es | Servidores virtuales en la nube | **Funciones** virtuales: no hay servidores que gestionar |
| Límite | RAM y CPU de la instancia | **Tiempo**: ejecuciones cortas |
| Funcionamiento | Encendida continuamente | Se ejecuta **bajo demanda** |
| Escalado | Hay que intervenir para añadir o quitar servidores | **Automático** |

- **"Ejecuciones cortas" es relativo**: el máximo son **15 minutos** por ejecución. Si un trabajo
  puede durar más, no es Lambda (EC2, ECS o AWS Batch).
- El **timeout por defecto son 3 segundos**. Se cambia en *Configuration → General
  configuration*, y es lo primero que mirar si una función se corta sin error en el código.

---

## Ventajas

- **Precio sencillo**: se paga por petición y por tiempo de cómputo, con una capa gratuita de
  1.000.000 de peticiones y 400.000 GB-segundos al mes.
- Integrada con todo el ecosistema de AWS y con muchos lenguajes de programación.
- Monitorización con CloudWatch.
- **Memoria de 128 MB hasta 10 GB por función.**
- **Al subir la RAM, también suben la CPU y la red.** En Lambda no se elige la CPU: se elige la
  memoria. Pregunta típica: una función lenta porque hace mucho cálculo se arregla **aumentando la
  memoria**, aunque no le falte RAM.

---

## Lenguajes soportados

- Node.js (JavaScript), Python, Java, C# (.NET Core) / PowerShell y Ruby.
- **Custom Runtime API** para otros lenguajes, mantenidos por la comunidad (por ejemplo Rust o
  Go).
- **Lambda Container Image**: la imagen tiene que implementar la Lambda Runtime API. Para ejecutar
  imágenes Docker cualesquiera, lo indicado es **ECS / Fargate**, no Lambda.

**PHP no está entre los runtimes nativos.** Para usarlo haría falta un custom runtime o una
container image.

---

## Integraciones principales

API Gateway, Kinesis, DynamoDB, S3, CloudFront, CloudWatch Events / EventBridge, CloudWatch Logs,
SNS, SQS y Cognito.

### Ejemplo: miniaturas sin servidor

1. Se sube una imagen nueva a un bucket de S3.
2. La subida **dispara** una función Lambda que crea la miniatura.
3. La función guarda la miniatura en S3 y los metadatos (nombre, tamaño, fecha de creación) en
   DynamoDB.

En mi anterior trabajo esto lo hacía un script PHP en el servidor de media, que generaba las
miniaturas al subir cada imagen. La diferencia está en el modelo: el servidor estaba siempre
encendido esperando subidas, y una avalancha de imágenes tenía que aguantarla con sus propios
recursos. Con Lambda, **la subida es el evento que lanza la función**: si no se sube nada, no hay
nada ejecutándose ni se paga; si se suben mil a la vez, se ejecutan mil funciones en paralelo.

---

## Precios

- **Por petición**: el primer millón al mes es gratis; después, 0,20 $ por millón (0,0000002 $
  por petición).
- **Por duración**, en incrementos de 1 ms, medida en **GB-segundos** (memoria × tiempo):
  - 400.000 GB-segundos al mes gratis: 400.000 segundos con 1 GB de RAM o 3.200.000 segundos con
    128 MB.
  - Después, 1 $ por cada 600.000 GB-segundos.
- Suele ser **muy barato**, y por eso es tan popular.
- Si se sube la memoria para ganar CPU, cada segundo cuesta más; pero si la función termina antes,
  el total puede quedar igual o bajar.
- Los **logs de CloudWatch** que generan las funciones se pagan aparte.

---

## Práctica: primera función (lección 116)

En `us-east-1`, con el blueprint **Hello world function** en `python3.12`, función `HelloWorld`.
Con *Create default role*, la consola crea un rol de ejecución (`HelloWorld-role-<sufijo>`) que
da permiso a la función para enviar sus logs a CloudWatch Logs.

```python
import json

print('Loading function')


def lambda_handler(event, context):
    print("value1 = " + event['key1'])
    print("value2 = " + event['key2'])
    print("value3 = " + event['key3'])
    return event['key1']  # Echo back the first key value
```

### Lo que se ve al probarla (pestaña *Test*)

| | Primera ejecución | Segunda ejecución |
|---|---|---|
| Duration | 1,87 ms | 13,03 ms |
| Init duration | 94,77 ms | — |
| Billed duration | 97 ms | 14 ms |
| Resources configured | 128 MB | 128 MB |
| Max memory used | 37 MB | 37 MB |

- **Cold start**: la primera vez Lambda tiene que preparar el entorno de ejecución, y ese tiempo
  aparece como *Init duration*. En la segunda ejecución el entorno se reutiliza y no hay *Init
  duration*. En mi prueba, el tiempo de inicialización entró en el facturado (97 ms frente a
  1,87 ms de ejecución).
- **Max memory used** frente a **Resources configured** es el dato para ajustar la memoria.
- **Error**: con un evento de prueba sin la clave `key1`, la ejecución falla con `KeyError: 'key1'`
  y Lambda devuelve el `errorType`, el `errorMessage` y el stack trace. El log completo queda en el
  log group de CloudWatch.

### Pestañas de la función

- **Monitor**: métricas y enlace directo a los logs en CloudWatch (*View CloudWatch logs*).
- **Configuration**: memoria, timeout y demás ajustes.

### Coste y limpieza

**Coste:** cero, dentro de la capa gratuita. No hace falta ninguna instancia EC2.

**Limpieza**, que no se hace sola al borrar la función:

1. Borrar la función.
2. Borrar el log group `/aws/lambda/HelloWorld` en CloudWatch. **Sobrevive al borrado de la
   función** y por defecto los logs no caducan nunca.
3. Borrar el rol de IAM `HelloWorld-role-<sufijo>`. **Tampoco se borra solo.**

Truco: abrir desde la propia función el log group (*Monitor → View CloudWatch logs*) y el rol
(*Configuration → Permissions*) en pestañas aparte, para tenerlos a mano al limpiar.

---

## Lambda con EventBridge (lección 117)

Dos formas de lanzar una función desde EventBridge:

| Tipo | Cómo se dispara | Ejemplo |
|---|---|---|
| **Programada** | Expresión `rate(...)` o `cron(...)` | Ejecutar una tarea cada hora |
| **Por evento** | Un *event pattern* que reacciona a un cambio de estado en otro servicio | Un pipeline de CodePipeline que cambia de estado |

La programada es un crontab, pero sin un servidor que tenga que estar encendido para ejecutarlo. La
de eventos es un trigger.

> **El cron de AWS no es el de Linux.** Tiene **6 campos** (añade el año) y, en las reglas
> programadas clásicas de EventBridge, **va en UTC**, no en la hora local.

---

## Práctica: función programada (lección 118)

Función `lambda-demo-eventbridge` en `us-east-1`, *Author from scratch* con Python 3.14, y una
programación que la invoca cada minuto.

### EventBridge Scheduler frente a las reglas clásicas

El curso crea una **regla programada de EventBridge**. En la consola actual eso aparece como
*Scheduled rules (legacy)*, y la opción por defecto es **EventBridge Scheduler**, el servicio nuevo.
Hice la práctica con Scheduler:

- *Recurring schedule* → *Rate-based schedule* → `rate(1 minutes)`.
- Permite elegir la **zona horaria** (`Europe/Madrid`). Las reglas clásicas van siempre en UTC: en
  el examen, si hablan de una regla de EventBridge con cron, es UTC.
- Destino: *AWS Lambda* → `lambda-demo-eventbridge`.
- **Scheduler crea su propio rol de IAM** para poder invocar la función
  (`Amazon_EventBridge_Scheduler_LAMBDA_<sufijo>`), además del rol de ejecución de la función.

### El evento que recibe la función

Añadí un `print(event)` al código para ver qué llega. En el log de CloudWatch:

```python
{'version': '0', 'id': '...', 'detail-type': 'Scheduled Event', 'source': 'aws.scheduler',
 'account': '071959556890', 'time': '2026-10-07T21:14:34Z', 'region': 'us-east-1',
 'resources': ['arn:aws:scheduler:us-east-1:...:schedule/default/InvokeLambdaEveryMinute'],
 'detail': '{}'}
```

`source` y `detail-type` identifican quién ha invocado la función. Cada minuto aparece un `START`,
el evento, un `END` y un `REPORT` en el log group.

### Coste y limpieza

**Coste:** cero, dentro de la capa gratuita.

**Mientras la programación exista, la función se ejecuta cada minuto** y va llenando su log group.
Es lo primero que hay que deshabilitar o borrar al terminar. Limpieza:

1. Borrar la programación `InvokeLambdaEveryMinute` (primero la deshabilité).
2. Borrar la función.
3. Borrar el log group `/aws/lambda/lambda-demo-eventbridge`.
4. Borrar **los dos roles**: el de ejecución de la función (`lambda-demo-eventbridge-role-<sufijo>`)
   y el que creó Scheduler.

---

## Lambda con S3 Event Notifications (lección 119)

S3 puede enviar un evento cuando pasa algo en un bucket:

- **Tipos de evento**: `s3:ObjectCreated`, `s3:ObjectRemoved`, `s3:ObjectRestore`,
  `s3:Replication`…
- **Filtro por nombre** de objeto (por ejemplo, solo `*.jpg`).
- **Destinos**: SNS (y de ahí, por ejemplo, a varias colas SQS), SQS o Lambda.
- Lambda se invoca de forma **asíncrona**, y los eventos que fallen pueden ir a una **DLQ** (una
  cola SQS donde quedan los que no se pudieron procesar).
- Caso de uso: generar miniaturas de las imágenes que se suben (el ejemplo de la lección 115).

Dos detalles de examen:

- **Normalmente llegan en segundos, pero pueden tardar un minuto o más.**
- **Dos escrituras simultáneas sobre el mismo objeto sin versionado pueden generar una sola
  notificación.** Para asegurar una notificación por cada escritura, **activar el versionado** del
  bucket.

### Patrón: sincronizar metadatos

Al subir un fichero, el evento lanza una Lambda que guarda sus metadatos en una tabla de **RDS** o
**DynamoDB**. Es el mismo patrón que las miniaturas, y encaja con un e-commerce: subir las imágenes
de producto y que sus datos se registren solos, sin un proceso revisando la carpeta.

---

## Práctica: función disparada por S3 (lección 120)

Función `lambda-s3` (Python) y bucket `demo-s3-event-rcmt` en `us-east-1`.

- En el bucket, *Properties → Event notifications → Create event notification*: eventos de
  creación de objetos y destino *Lambda function* → `lambda-s3`.
- **Permisos:** para que S3 pueda invocar la función, la consola añade a la Lambda una
  **resource-based policy** que permite al servicio S3 llamarla (el aviso azul de *Destination*).
  A diferencia de Scheduler, **no se crea un rol nuevo**.
- En el diagrama de la función aparece S3 como **trigger**.
- Al subir `logo.jpg`, la función se ejecutó y el log mostró el evento: una lista `Records` con
  `eventSource: 'aws:s3'` y `eventName: 'ObjectCreated:Put'`, además del bucket y la clave del
  objeto.

### Coste y limpieza

**Coste:** cero. Limpieza:

1. Vaciar y borrar el bucket (se lleva la notificación).
2. Borrar la función y su log group `/aws/lambda/lambda-s3`.
3. Borrar el rol de ejecución de la función.

---

## Cuestionario de la sección

**3 de 3.** Preguntas sobre:

- S3 Event Notifications invocando una Lambda.
- Qué servicio permite programar la ejecución de una función: **EventBridge**.
- El tamaño máximo del almacenamiento temporal `/tmp` de una función: **10 GB** (por defecto,
  512 MB).

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| Duración máxima | **15 minutos**. Timeout por defecto: 3 segundos. Más de 15 minutos → no es Lambda |
| Memoria | 128 MB a 10 GB. **CPU y red suben con la memoria**: función lenta por CPU → más memoria |
| Escalado | Automático. Se ejecuta bajo demanda |
| Precio | Por petición + por duración (GB-segundos, incrementos de 1 ms). Capa gratuita: 1 M de peticiones y 400.000 GB-s al mes |
| Lenguajes | Node.js, Python, Java, C#/PowerShell, Ruby. Otros con Custom Runtime API |
| Container image | Debe implementar la Lambda Runtime API. Docker arbitrario → ECS / Fargate |
| Cold start | Primera ejecución: *Init duration* para preparar el entorno. Las siguientes lo reutilizan |
| Limpieza | Al borrar la función **no** se borran ni el log group ni el rol de ejecución |
| EventBridge + Lambda | Programada (`rate` / `cron`) o por evento (cambio de estado en otro servicio). Cron de 6 campos, en UTC en las reglas clásicas |
| EventBridge Scheduler | Servicio nuevo de programación, con zona horaria. Crea su propio rol para invocar la función |
| S3 Event Notifications | `ObjectCreated`, `ObjectRemoved`, `ObjectRestore`, `Replication`… Filtro por nombre. Destinos: SNS, SQS, Lambda (asíncrona, con DLQ) |
| Latencia de S3 Events | Segundos, a veces un minuto o más |
| Notificaciones perdidas | Dos escrituras simultáneas sin versionado → una sola notificación. **Activar versionado** |
| Permisos S3 → Lambda | Resource-based policy en la función que permite a S3 invocarla |
| `/tmp` | Almacenamiento temporal de la función: 512 MB por defecto, hasta 10 GB |
