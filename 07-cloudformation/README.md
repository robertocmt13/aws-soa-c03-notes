# 07 — CloudFormation for CloudOps

Notas de la Sección 7 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 79 a 87 completadas: qué es CloudFormation, ventajas,
> funcionamiento, formas de desplegar plantillas, componentes de una plantilla, prácticas de
> Create, Update y Delete Stack, YAML, `Resources`, `Parameters`, `Mappings`, `Outputs` con
> exports y `Conditions`.

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
  plantilla, CloudFormation la sube al bucket `cf-templates-...` de la región y expone una nueva
  **Amazon S3 URL** para ese fichero. No crea un bucket por subida: usa **un único bucket
  `cf-templates-...` por región** para todas las plantillas que se suben desde la consola.
- Si la plantilla define un `Parameters`, aparece un paso adicional (**Specify stack details**)
  para darle valor. Es el mismo mecanismo de la 79, aplicado ahora a una actualización.
- **Change set preview**: antes de aplicar el cambio, CloudFormation muestra qué va a pasar,
  recurso por recurso, con una columna **Action** (`Add`, `Modify`, `Remove`) y una columna
  **Replacement**. `Replacement: True` en un recurso `Modify` significa que ese recurso no se
  puede actualizar in situ: hay que destruirlo y recrearlo. En la práctica, añadir
  `SecurityGroups` a la instancia EC2 provoca ese reemplazo de `MyInstance`, aunque el resto de
  cambios (Elastic IP y los dos security groups nuevos) son simples altas.
- **Delete stack** pide escribir el nombre del stack para confirmar, y borra **todos** los
  recursos que pertenecen al stack, incluida la Elastic IP creada en la actualización.
- **Ojo: el bucket `cf-templates-...` no pertenece al stack**, así que Delete stack **no lo
  borra**. Para dejar la cuenta limpia después de la práctica hay que ir a S3, **vaciarlo** y
  **borrarlo** a mano (un bucket con objetos no se puede borrar directamente).

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

- Cambié `AvailabilityZone` a `eu-north-1a`, y busqué el `ImageId` correcto para esa región en el
  **AMI Catalog** de la consola de EC2 (Amazon Linux 2023, kernel 6.18) en vez de copiar el de
  `us-east-1`.
- Cambié `InstanceType` a `t3.nano`.
- Añadí una propiedad `UserData` con `Fn::Base64: !Sub |` seguido del script de instalación de
  Apache. Es la primera vez que meto un `UserData` **dentro de una plantilla de CloudFormation**:
  el script va como un bloque de texto multilínea (lo visto en YAML Crash Course) envuelto en
  `Fn::Base64`, porque EC2 espera el user data codificado en Base64, y CloudFormation lo codifica
  él solo a partir del texto plano.

> **Error que cometí al principio:** puse `AvailabilityZone: eu-north-1`, que es la **región**,
> no una AZ. La propiedad espera el nombre de una zona concreta (`eu-north-1a`, `eu-north-1b`…).
> cfn-lint no lo detecta (ver más abajo): la plantilla habría fallado al desplegar.

---

## `Parameters` (lección 84)

Forma de dar **entradas** a una plantilla. Tienen sentido cuando:

- Se quiere **reutilizar** la plantilla en la empresa.
- Hay valores que **no se pueden saber de antemano**.

La pregunta que hay que hacerse: *¿es probable que esta configuración cambie en el futuro?* Si es
que sí, parámetro. Así no hay que volver a subir la plantilla para cambiar un valor.

Un caso típico es el **tipo de instancia**: misma plantilla, y se elige más o menos potencia al
crear o actualizar el stack. Al actualizar, cambiar `InstanceType` no reemplaza la instancia, pero
sí la **para y la arranca** (*Update requires: Some interruptions*), así que hay corte de servicio.

### Ajustes de un parámetro

| Ajuste | Para qué |
|---|---|
| `Type` | `String`, `Number`, `CommaDelimitedList`, `List<Number>`, tipos específicos de AWS, listas de esos tipos y parámetros de **SSM Parameter Store** |
| `Description` / `ConstraintDescription` | Texto de ayuda y mensaje cuando el valor no cumple la restricción |
| `MinLength` / `MaxLength`, `MinValue` / `MaxValue` | Límites de longitud o de valor |
| `Default` | Valor por defecto |
| `AllowedValues` | Lista cerrada de valores (en la consola sale como desplegable) |
| `AllowedPattern` | Regex que tiene que cumplir el valor |
| `NoEcho` | Oculta el valor (`****`) en consola, CLI y API |

Los **tipos específicos de AWS** (por ejemplo `AWS::EC2::KeyPair::KeyName` o
`AWS::EC2::AvailabilityZone::Name`) validan el valor contra lo que existe en la cuenta: el usuario
solo puede elegir recursos reales.

CloudFormation **valida los parámetros antes de crear nada**: un valor fuera de `AllowedValues`
hace que el stack ni siquiera empiece. Es la misma idea que validar un formulario en PHP antes de
procesarlo (`AllowedValues` ≈ un `<select>`, `AllowedPattern` ≈ validación con regex).

> **`NoEcho` no es cifrado.** Solo enmascara el valor en la consola y en las respuestas de la
> API. Si ese valor acaba en un `Output`, en `Metadata` o en el `UserData`, queda expuesto. Para
> secretos de verdad: referencias dinámicas a Secrets Manager o SSM SecureString.

### Referenciar un parámetro

Con `Fn::Ref`, en YAML `!Ref`. Se puede usar en cualquier parte de la plantilla.

**`!Ref` sirve tanto para parámetros como para recursos** (por ejemplo `VpcId: !Ref MyVPC`). Dentro
de un `!Sub` no hace falta: basta con `${NombreDelParametro}`.

### Pseudo parámetros

Disponibles en cualquier plantilla sin declararlos:

| Pseudo parámetro | Devuelve |
|---|---|
| `AWS::AccountId` | ID de la cuenta, ej. `123456789012` |
| `AWS::Region` | Región donde se despliega, ej. `us-east-1` |
| `AWS::StackId` | ARN del stack |
| `AWS::StackName` | Nombre del stack |
| `AWS::NotificationARNs` | Lista de ARNs de notificación del stack |
| `AWS::NoValue` | No devuelve nada. Se usa con `Fn::If` para eliminar una propiedad según una condición |

### Práctica libre: mi plantilla con parámetros

Evolución de la plantilla de la 83, con un parámetro de texto que se inyecta en el HTML con `!Sub`
junto a un pseudo parámetro, y el tipo de instancia como parámetro con `AllowedValues`:

```yaml
---
Parameters:
  Namehttpd:
    Description: Enter hostname for httpd distincion
    Type: String
    Default: MiInstancia
  InstanceType:
    Description: EC2 instance type
    Type: String
    AllowedValues:
      - t3.nano
      - t3.micro
      - t3.small
    Default: t3.nano

Resources:
  MiInstancia:
    Type: AWS::EC2::Instance
    Properties:
      AvailabilityZone: eu-north-1a
      ImageId: "ami-06cfeaaa22092f09d"
      InstanceType: !Ref InstanceType
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          dnf update -y
          dnf install -y httpd
          systemctl start httpd
          systemctl enable httpd
          echo "<h1>Hello World from ${Namehttpd} in stack ${AWS::StackName}</h1>" > /var/www/html/index.html
```

- **Primer fallo:** metí `Parameters` indentado **dentro** de `Resources`. `Parameters` es una
  sección de primer nivel, hermana de `Resources`. Tal como estaba, CloudFormation lo habría
  tratado como un recurso llamado "Parameters" sin `Type` y la validación habría fallado.
- Cambié `yum` por `dnf`, el gestor de Amazon Linux 2023 (`yum` funciona como alias).
- Solo escrita, no desplegada. Si se desplegara: tiene que ser en `eu-north-1` (AMI y AZ de esa
  región) y, al no declarar security group, la instancia usaría el SG por defecto de la VPC, sin
  acceso HTTP.

### Herramientas: validar plantillas en local

*No es del curso, pero lo monté al escribir la plantilla.*

- **Extensión YAML de Red Hat**: no conoce las etiquetas cortas de CloudFormation y marca `!Ref`,
  `!Sub`, etc. como "Unresolved tag". Se arregla declarándolas en `yaml.customTags` del
  `settings.json` de VS Code.
- **cfn-lint**: el linter oficial de AWS para plantillas. En Ubuntu 24.04 se instala con **pipx**
  (`pip install` a nivel de sistema da `externally-managed-environment`):

  ```bash
  sudo apt install pipx
  pipx ensurepath
  pipx install cfn-lint
  cfn-lint cloudformation/from-developer-course/miejemplo.yaml
  ```

  Con la extensión **CloudFormation Linter** de VS Code los avisos salen en el editor. Las `E`
  son errores y las `W`, avisos.

- **Lo que cfn-lint no valida:** con `AvailabilityZone: eu-north-1` (la región) solo dio el aviso
  **W3010** (*Avoid hardcoding availability zones*), igual que con `eu-north-1a`. No comprueba que
  el valor exista en AWS: es como `php -l`, valida la forma, no que los recursos existan. El
  W3010 recomienda no fijar la AZ; las alternativas son quitar la propiedad (EC2 elige), un
  parámetro de tipo `AWS::EC2::AvailabilityZone::Name` o `!Select [0, !GetAZs ""]`.

---

## `Mappings` (lección 85)

Variables **fijas** dentro de la plantilla, con todos los valores escritos en ella (hardcoded).
Sirven para diferenciar entornos (dev / prod), regiones, tipos de AMI…

```yaml
Mappings:
  RegionMap:
    us-east-1:
      HVM64: ami-0ff8a91507f77f867
      HVMG2: ami-0a584ac55a7631c0c
    us-west-1:
      HVM64: ami-0bdb828fd58c52235
      HVMG2: ami-066ee5fd4a9ef77f1

Resources:
  MyEC2Instance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !FindInMap [RegionMap, !Ref "AWS::Region", HVM64]
      InstanceType: t2.micro
```

Se leen con **`Fn::FindInMap`** (`!FindInMap [MapName, TopLevelKey, SecondLevelKey]`). Encajan
muy bien con las **AMIs**, porque son específicas de cada región: con `AWS::Region` como clave, la
misma plantilla funciona en cualquier región del mapa. `HVM64` y `HVMG2` son la AMI estándar de
64 bits y la variante para instancias con GPU (familia G2), de las plantillas de ejemplo antiguas
de AWS.

En PHP es un **array asociativo anidado** (`$regionMap[$region]['HVM64']`), como los que usaba
para las restricciones y URLs de cada marketplace. Pero más restrictivo:

- Solo **dos niveles** de clave.
- Valores **estáticos**: dentro de `Mappings` no se puede usar `!Ref` ni otras funciones.
- **Sin valor por defecto**: si la clave no existe (una región que no está en el mapa), el stack
  falla.

La clave sí puede ser dinámica: un parámetro `Environment` con `AllowedValues: [dev, prod]` y
`!FindInMap [EnvMap, !Ref Environment, InstanceType]` combina las dos cosas.

### Mappings vs Parameters

| Usar | Cuándo |
|---|---|
| **Mappings** | Se conocen de antemano todos los valores posibles y se deducen de variables como región, AZ, cuenta o entorno. Dan un control más seguro sobre la plantilla |
| **Parameters** | Los valores dependen de verdad del usuario |

> **Alternativa moderna para AMIs:** mantener un mapa de IDs a mano obliga a actualizarlo. Un
> parámetro de tipo SSM resuelve la AMI más reciente en cada región sin mapa:
>
> ```yaml
> LatestAmiId:
>   Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
>   Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
> ```

---

## `Outputs` y exports (lección 86)

La sección `Outputs` declara valores de salida **opcionales**. Se ven en la consola o con la CLI,
pero lo importante es que, si se **exportan**, **otros stacks pueden importarlos**.

Caso típico: un stack de red exporta el ID de la VPC y de las subnets, y los stacks de aplicación
los consumen. Es la mejor forma de colaborar entre stacks, cada equipo gestionando su parte: la
separación de responsabilidades de la lección 79, con el mecanismo concreto que la hace posible.

```yaml
# Stack 1: exporta
Outputs:
  StackSSHSecurityGroup:
    Description: The SSH Security Group for our Company
    Value: !Ref MyCompanyWideSSHSecurityGroup
    Export:
      Name: SSHSecurityGroup

# Stack 2: importa
Resources:
  MySecureInstance:
    Type: AWS::EC2::Instance
    Properties:
      SecurityGroups:
        - !ImportValue SSHSecurityGroup
```

Se importa con **`Fn::ImportValue`** (`!ImportValue` en YAML).

| Regla | Qué implica |
|---|---|
| Nombre del export **único por cuenta y región** | No puede haber dos stacks exportando `SSHSecurityGroup` en la misma región |
| Solo **dentro de la misma región** | Un stack de `eu-north-1` no puede importar un export de `us-east-1` |
| No se puede **borrar** el stack que exporta mientras alguien lo importe | Primero hay que borrar los stacks que lo usan |
| No se puede **modificar** el valor exportado mientras esté importado | El update del stack que exporta falla |

---

## `Conditions` (lección 87)

Controlan si se crean **recursos u outputs** en función de una condición. Las habituales: entorno
(dev / test / prod), región o cualquier valor de parámetro. Una condición puede referenciar otra
condición, un parámetro o un mapping.

```yaml
Conditions:
  CreateProdResources: !Equals [ !Ref EnvType, prod ]

Resources:
  MountPoint:
    Type: AWS::EC2::VolumeAttachment
    Condition: CreateProdResources
```

- El nombre de la condición (logical ID) lo elige uno.
- Funciones lógicas disponibles: `Fn::And`, `Fn::Equals`, `Fn::If`, `Fn::Not`, `Fn::Or`.
- Con la misma plantilla, el stack de **dev** crea solo la instancia EC2 y el de **prod**, la
  instancia más un volumen EBS.

Es un `if` a dos niveles:

- **`Condition:` en un recurso u output**: se crea entero o no se crea.
- **`Fn::If` dentro de una propiedad**: cambia el valor de esa propiedad. Con `AWS::NoValue` como
  rama, la propiedad desaparece.

Según el curso, para el examen **no hace falta saber escribir condiciones**: basta con entender
qué hacen y cómo se aplican a recursos y outputs.

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
| Delete Stack | Pide confirmar escribiendo el nombre. Borra todos los recursos del stack |
| Bucket `cf-templates-...` | Uno por región. **No** pertenece al stack: Delete stack no lo borra, hay que vaciarlo y borrarlo a mano |
| Tipo de recurso | `service-provider::service-name::data-type-name`, ej. `AWS::EC2::Instance` |
| Número dinámico de recursos | Con Macros y Transform (fuera del curso) |
| Servicio de AWS no soportado | Workaround con CloudFormation Custom Resources |
| Cuándo usar un parámetro | Si la configuración puede cambiar en el futuro o no se conoce de antemano |
| Ajustes de parámetro | `Type`, `AllowedValues`, `AllowedPattern`, `Default`, Min/Max, `NoEcho`… Se validan **antes** de crear nada |
| Tipos específicos de AWS | Validan contra lo que existe en la cuenta (key pairs, AZs, VPCs…) |
| Parámetro SSM | `AWS::SSM::Parameter::Value<...>`: lee el valor de Parameter Store (ej. la AMI más reciente) |
| `NoEcho` | Enmascara, **no cifra** |
| `!Ref` | Referencia **parámetros y recursos** |
| Pseudo parámetros | `AWS::AccountId`, `Region`, `StackId`, `StackName`, `NotificationARNs`, `NoValue`. Sin declararlos |
| `Fn::FindInMap` | `!FindInMap [MapName, TopLevelKey, SecondLevelKey]` |
| Mappings | Valores conocidos de antemano y deducibles (región, entorno…). Muy útiles para AMIs por región |
| Outputs | Opcionales. Con `Export` → otros stacks los importan con `Fn::ImportValue` |
| Exports | Nombre único por cuenta y región, solo misma región. No se puede borrar ni modificar lo exportado mientras esté importado |
| Conditions | Crean o no recursos / outputs. `Fn::And`, `Equals`, `If`, `Not`, `Or` |
