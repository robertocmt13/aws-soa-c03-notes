# 07 — CloudFormation for CloudOps

Notas de la Sección 7 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 79 a 83 completadas: qué es CloudFormation, ventajas,
> funcionamiento, formas de desplegar plantillas, componentes de una plantilla, prácticas de
> Create, Update y Delete Stack, YAML y el componente `Resources`.

---

## Qué es CloudFormation

Una forma **declarativa** de describir la infraestructura de AWS. Sirve para casi cualquier
recurso (la mayoría están soportados).

En una plantilla se dice **qué** se quiere, no **cómo** crearlo:

- Quiero un security group.
- Quiero dos instancias EC2 que usen ese security group.
- Quiero dos Elastic IPs para esas instancias.
- Quiero un bucket S3.
- Quiero un load balancer delante de esas instancias.

CloudFormation lo crea todo **en el orden correcto** y con **la configuración exacta** indicada.
Es la forma de automatizar todo lo que hasta ahora se venía montando a mano en la consola.

---

## Infrastructure Composer

Herramienta visual para plantillas de CloudFormation. Funciona en las dos direcciones:

- A partir de una plantilla, **genera el diagrama** de los recursos y cómo se relacionan entre
  sí (útil para comprobar que las dependencias son las que se esperan).
- Se puede **diseñar** arrastrando componentes y genera el YAML.

Las plantillas se escriben en **YAML o JSON**. YAML es lo habitual y lo que usa el curso.

---

## Ventajas

| Ventaja | En qué consiste |
|---|---|
| **Infraestructura como código** | Nada se crea a mano, lo que da control. El código se versiona con Git y los cambios de infraestructura se revisan como código |
| **Coste** | Cada recurso del stack lleva una etiqueta que lo identifica, así se ve fácilmente cuánto cuesta cada stack. Se pueden estimar costes a partir de la plantilla |
| **Productividad** | Destruir y recrear la infraestructura al vuelo. Diagramas generados automáticamente. Programación declarativa: no hay que resolver el orden ni la orquestación |
| **Separación de responsabilidades** | Varios stacks para varias apps y capas: stacks de VPC, de red, de aplicación |
| **No reinventar la rueda** | Aprovechar plantillas existentes y la documentación |

> **Estrategia de ahorro del curso**: en entornos de desarrollo, borrar automáticamente los
> stacks a las 17:00 y recrearlos a las 8:00, de forma segura, porque la plantilla garantiza que
> todo vuelve a quedar exactamente igual.

---

## Cómo funciona

```
Template ──upload──> S3 bucket <──reference── CloudFormation ──create──> Stack ──> AWS Resources
```

- Las plantillas **se suben a S3** y CloudFormation las referencia desde allí. Al subir el
  fichero desde la consola, CloudFormation crea el bucket y lo sube automáticamente.
- **Una plantilla no se puede editar.** Para actualizarla hay que subir una **versión nueva**.
- Los stacks se identifican por su **nombre**.
- **Borrar un stack borra todos los recursos que CloudFormation creó en él.** Muy útil para
  limpiar después de una práctica, y peligroso en producción. Es el comportamiento por defecto:
  la *Deletion Policy* (lección 92) permite conservar recursos concretos al borrar el stack.

---

## Formas de desplegar una plantilla

| | Manual | Automatizada |
|---|---|---|
| Edición | Infrastructure Composer o editor de código | Fichero YAML |
| Despliegue | Consola de CloudFormation, rellenando parámetros a mano | AWS CLI (`create-stack`) o una herramienta de Continuous Delivery |
| Cuándo | Aprendizaje. Es la que se usa en el curso | **La recomendada** cuando se quiere automatizar el flujo por completo |

---

## Práctica: Create Stack (lección 80)

Plantilla mínima: una instancia EC2. Crear el stack desde la consola, opción **Choose an
existing template → Amazon S3 URL**.

- **La opción "Use a sample template" ha desaparecido.** El curso la usaba para cargar una
  plantilla de ejemplo (WordPress Multi-AZ) sin tener que subir nada. Ahora hay que coger esa
  misma plantilla como una **Amazon S3 URL** manual (la URL viene en el material del curso) y
  pegarla en **Choose an existing template → Amazon S3 URL**. Desde ahí, el botón **View in
  Infrastructure Composer** abre el diagrama generado automáticamente a partir de esa plantilla,
  sin necesidad de crear el stack.
- Esa plantilla de ejemplo (ALB + Auto Scaling + RDS Multi-AZ) es cara de desplegar solo para
  ver la pantalla de creación, así que la práctica real de la 80 se hace con la plantilla propia
  del curso (una sola instancia EC2), subida como fichero.
- **Ojo con la región.** La plantilla del curso trae fijados un `ImageId` (AMI) y un
  `InstanceType` de `us-east-1`. Los IDs de AMI son específicos de cada región y `t2.micro` no
  existe en todas partes (en `eu-north-1`, por ejemplo, el equivalente es `t3.micro`). Si se
  trabaja fuera de `us-east-1`, o se cambian esos dos valores a mano, o se hace la práctica en
  `us-east-1` como en el curso.

### Tags

Además de los que pone CloudFormation automáticamente en cada recurso
(`aws:cloudformation:stack-name`, `aws:cloudformation:logical-id`, `aws:cloudformation:stack-id`)
se pueden añadir tags propios de dos formas:

- **Por recurso**, con la propiedad `Tags` dentro de `Properties`. El tag reservado `Name` es el
  que hace que el recurso muestre nombre en la consola (por ejemplo, en la lista de instancias
  EC2).
- **A nivel de stack**, en el paso *Configure stack options* de la consola. Esos tags se aplican
  automáticamente a todos los recursos del stack que admitan tags.

---

## Práctica: Update & Delete Stack (lección 81)

Se actualiza el mismo stack de la 80 con una plantilla nueva que añade una Elastic IP y dos
security groups (SSH y HTTP/HTTPS), y que introduce un **parámetro**
(`SecurityGroupDescription`).

- **Update stack → Replace existing template → Upload a template file.** Al subir la nueva
  plantilla, CloudFormation la sube a un bucket `cf-templates-...` distinto del de la creación,
  y expone una nueva **Amazon S3 URL**.
- Si la plantilla define un `Parameters`, aparece un paso adicional (**Specify stack details**)
  para darle valor. Es el mismo mecanismo de la 79, aplicado ahora a una actualización.
- **Change set preview**: antes de aplicar el cambio, CloudFormation muestra qué va a pasar,
  recurso por recurso, con una columna **Action** (`Add`, `Modify`, `Remove`) y una columna
  **Replacement**. `Replacement: True` en un recurso `Modify` significa que ese recurso no se
  puede actualizar in situ: hay que destruirlo y recrearlo. En la práctica, añadir
  `SecurityGroups` a la instancia EC2 provoca ese reemplazo de `MyInstance`, aunque el resto de
  cambios (Elastic IP y los dos security groups nuevos) son simples altas.
- **Delete stack** pide escribir el nombre del stack para confirmar, y borra **todos** los
  recursos que pertenecen al stack, incluida la Elastic IP creada en la actualización. Como todo
  lo usado en la práctica lo creó el propio stack, no hace falta limpiar nada aparte: borrar el
  stack es la limpieza completa.

---

## `Resources` (lección 83)

Es el único componente **obligatorio** de una plantilla: sin `Resources` no hay plantilla válida.
Representa los componentes de AWS que se van a crear y configurar, y los recursos declarados
dentro pueden **referenciarse entre sí**.

CloudFormation se encarga de resolver el **orden de creación, actualización y borrado** de todos
los recursos declarados. Hay más de 700 tipos de recursos soportados.

### Identificador de un tipo de recurso

```
service-provider::service-name::data-type-name
```

Por ejemplo, `AWS::EC2::Instance`. Con la práctica se acaba reconociendo el patrón sin mirar la
documentación, pero para lo que no se sabe de memoria está la **Template Reference** de AWS
(`docs.aws.amazon.com/AWSCloudFormation/.../aws-resource-<servicio>-<recurso>.html`): cada página
lista, en YAML y JSON, todas las propiedades del recurso y si son obligatorias u opcionales, y
cada propiedad compleja (por ejemplo `BlockDeviceMappings`) enlaza a su propia página de
sub-propiedades. Es la forma de "encadenar" hacia abajo hasta llegar a tipos simples (`String`,
`Boolean`, `Integer`).

### FAQ

| Pregunta | Respuesta |
|---|---|
| ¿Se puede crear un número dinámico de recursos? | Sí, con **CloudFormation Macros** y **Transform**. Fuera del alcance del curso |
| ¿Están soportados todos los servicios de AWS? | Casi todos. Para los pocos que no lo están, existe el workaround de **CloudFormation Custom Resources** |

### Práctica libre: plantilla EC2 adaptada a `eu-north-1` con UserData

Por mi cuenta, después del vídeo, he escrito una plantilla desde cero (sin partir de las del
repo del curso) para practicar cómo moverse por la Template Reference:

- Cambié `AvailabilityZone` a `eu-north-1`, y busqué el `ImageId` correcto para esa región en el
  **AMI Catalog** de la consola de EC2 (Amazon Linux 2023, kernel 6.18) en vez de copiar el de
  `us-east-1`.
- Cambié `InstanceType` a `t3.nano`.
- Añadí una propiedad `UserData` con `Fn::Base64: !Sub |` seguido del script de instalación de
  Apache. Es la primera vez que meto un `UserData` **dentro de una plantilla de CloudFormation**:
  el script va como un bloque de texto multilínea (lo visto en YAML Crash Course) envuelto en
  `Fn::Base64`, porque EC2 espera el user data codificado en Base64, y CloudFormation lo codifica
  él solo a partir del texto plano.

---

## Building blocks de una plantilla

### Componentes

| Componente | Qué es |
|---|---|
| `AWSTemplateFormatVersion` | Identifica las capacidades de la plantilla. Valor: `"2010-09-09"` |
| `Description` | Comentarios sobre la plantilla |
| `Resources` | **Obligatorio.** Los recursos de AWS declarados en la plantilla |
| `Parameters` | Entradas **dinámicas** de la plantilla |
| `Mappings` | Variables **estáticas** de la plantilla |
| `Outputs` | Referencias a lo que se ha creado |
| `Conditions` | Condiciones para crear o no ciertos recursos |

### Helpers

- **References**
- **Functions**

---

## CloudFormation y Terraform

*Fuera del examen: el SOA-C03 es 100% CloudFormation. Anotado porque Terraform aparece en muchas
ofertas de empleo.*

Misma idea (infraestructura como código declarativa), con diferencias de alcance:

| | CloudFormation | Terraform |
|---|---|---|
| Nubes | Solo AWS | Multi-cloud (AWS, Azure, GCP, Proxmox…) |
| Lenguaje | YAML / JSON | HCL, lenguaje propio |
| Estado | Lo gestiona AWS | Fichero `.tfstate` que gestiona el usuario, en local o en un backend remoto |
| Mantenedor | AWS | HashiCorp |

Los conceptos de esta sección (stacks, parámetros, outputs, dependencias entre recursos) se
trasladan casi directamente a Terraform.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| CloudFormation | IaC **declarativa**: se dice qué se quiere y AWS lo crea en el orden correcto |
| Formato | YAML o JSON |
| Infrastructure Composer | Genera el diagrama de una plantilla, o la plantilla desde un diseño visual |
| Plantilla | Se sube a **S3**. **No se edita**: se sube una versión nueva |
| Stack | Se identifica por su nombre. Borrarlo borra **todo** lo que creó (salvo Deletion Policy) |
| Coste | Los recursos del stack se etiquetan, así se ve cuánto cuesta cada stack |
| Despliegue automatizado | YAML + AWS CLI (`create-stack`) o herramienta de CD. El recomendado |
| Único componente obligatorio | `Resources` |
| `AWSTemplateFormatVersion` | `"2010-09-09"` |
| Parameters vs Mappings | Parameters = entradas **dinámicas**; Mappings = variables **estáticas** |
| Tags automáticos | `aws:cloudformation:stack-name`, `logical-id`, `stack-id`. No se pueden quitar |
| Tags propios | Por recurso (`Tags` en `Properties`, tag `Name` da nombre visible) o por stack (*Configure stack options*) |
| Update Stack | *Replace existing template* + nueva S3 URL o fichero. Si hay `Parameters`, pide valores |
| Change set | Vista previa por recurso: **Action** (Add / Modify / Remove) y **Replacement** (True = se destruye y recrea) |
| Delete Stack | Pide confirmar escribiendo el nombre. Borra todos los recursos del stack, sin excepciones manuales |
| Tipo de recurso | `service-provider::service-name::data-type-name`, ej. `AWS::EC2::Instance` |
| Número dinámico de recursos | Con Macros y Transform (fuera del curso) |
| Servicio de AWS no soportado | Workaround con CloudFormation Custom Resources |
