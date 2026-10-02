# 07 — CloudFormation for CloudOps

Notas de la Sección 7 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 79 a 105 completadas. La parte de repaso reutilizada del curso de
> Developer (`[DVA]`, lecciones 79 a 98): qué es CloudFormation, ventajas, funcionamiento, formas de
> desplegar plantillas, componentes de una plantilla, prácticas de Create, Update y Delete Stack,
> YAML, `Resources`, `Parameters`, `Mappings`, `Outputs` con exports, `Conditions`, funciones
> intrínsecas, rollbacks, service role, capabilities, políticas de borrado y reemplazo, stack
> policy, termination protection, custom resources y dynamic references. Y las primeras lecciones
> específicas de CloudOps (99 a 105): user data, `cfn-init`, `cfn-signal` con wait conditions y
> sus fallos, nested stacks, `DependsOn` y el aviso de coste de StackSets.

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

> **Aviso de AWS (octubre de 2026):** se retira la consola independiente de Infrastructure
> Composer (`console.aws.amazon.com/composer`). El editor visual sigue dentro de la consola de
> CloudFormation y en VS Code con la extensión AWS Toolkit. Me llegó como evento de **AWS Health**
> (tipo *scheduledChange*). No afecta a plantillas ni stacks.

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

## Funciones intrínsecas (lección 88)

Las que hay que conocer sí o sí para el examen: `Ref`, `Fn::GetAtt`, `Fn::FindInMap`,
`Fn::ImportValue`, `Fn::Base64` y las de condiciones (`Fn::If`, `Fn::Not`, `Fn::Equals`…). Existen
más (`Fn::Join`, `Fn::Sub`, `Fn::Select`, `Fn::GetAZs`, `Fn::Split`, `Fn::Cidr`…), todas en la
documentación. Casi todas ya las había usado en mis plantillas o salieron en lecciones anteriores.

- La **forma corta con `!`** (`!Ref`, `!GetAtt`, `!Sub`…) **solo existe en YAML**. En JSON va
  siempre la forma larga: `{"Fn::GetAtt": ["EC2Instance", "PublicDnsName"]}`.
- No se puede poner una forma corta justo detrás de `!Base64` (`!Base64 !Sub "..."` no vale). Por
  eso en el UserData se escribe `Fn::Base64: !Sub |`: forma larga fuera, corta dentro.

### `Ref` frente a `Fn::GetAtt`

| Función | Sobre un parámetro | Sobre un recurso |
|---|---|---|
| `!Ref` | Devuelve el valor del parámetro | Devuelve **un único valor por defecto** que decide AWS según el tipo: el ID de la instancia EC2, el **nombre** de un bucket S3… |
| `!GetAtt Recurso.Atributo` | — | Devuelve **otro atributo** del recurso (ARN, `PublicDnsName`, `PublicIp`…) |

Solo existen los atributos que AWS ha decidido exponer. Qué devuelve cada uno está en la página del
recurso en la Template Reference, sección **Return values** (apartados *Ref* y *Fn::GetAtt*).

Ejemplo de la lección: un registro CNAME de Route 53 que apunta al `PublicDnsName` de una instancia
creada en la misma plantilla (`- !GetAtt EC2Instance.PublicDnsName`).

**`!Ref` y `!GetAtt` crean dependencias implícitas**: CloudFormation crea primero el recurso
referenciado (la instancia) y después el que lo usa (el registro DNS). Así resuelve el orden de
creación.

---

## Rollbacks (lección 89)

| Caso | Estado final | Qué implica |
|---|---|---|
| Falla la **creación** (por defecto) | `ROLLBACK_COMPLETE` | Se borra todo, pero el stack sigue en la lista. En ese estado **no se puede actualizar**: hay que borrarlo y crearlo de nuevo |
| Falla la creación con **Disable rollback** | `CREATE_FAILED` | Lo que se creó bien **se conserva** para investigar, y factura hasta que se borre el stack |
| Falla un **update** | `UPDATE_ROLLBACK_COMPLETE` | El stack vuelve solo al último estado bueno. El log de eventos muestra qué pasó |
| Falla el **rollback** de un update | `UPDATE_ROLLBACK_FAILED` | Hay que arreglar los recursos a mano y lanzar **`ContinueUpdateRollback`** (consola o `aws cloudformation continue-update-rollback`) |

Se parece a una **transacción de MySQL** (`BEGIN` … `ROLLBACK`, todo o nada). El
`UPDATE_ROLLBACK_FAILED` sería un `ROLLBACK` que se queda a medias y obliga a arreglar a mano
antes de seguir.

La opción está en *Configure stack options → Stack deployment options → Behavior on provisioning
failure*: **Roll back all resources** o **Disable rollback** (*Preserve successfully provisioned
resources*).

### Práctica

Con `2-trigger-failure.yaml` en `us-east-1`:

1. **Stack `TriggerCreationFailure`, rollback desactivado.** Terminó en `CREATE_FAILED`:
   `ServerSecurityGroup` falló, `SSHSecurityGroup` quedó en `CREATE_COMPLETE` y la instancia **ni
   se intentó** (dependencia implícita: la instancia hace `!Ref` a los dos security groups). Lo que
   se creó bien siguió vivo hasta borrar el stack.
2. **Stack `FailureOnUpdate`**: creado con `0-just-ec2.yaml` y actualizado con
   `2-trigger-failure.yaml` mediante change set. Crear el change set **no cambia nada**: es solo la
   vista previa (*Execution status: AVAILABLE*). Hasta pulsar **Execute change set** no se aplica.
3. Ese update **no falló**: con los valores que di, la plantilla no tenía nada inválido, y el
   stack acabó en `UPDATE_COMPLETE` con la instancia reemplazada. Para forzar el fallo puse a mano
   una **AMI inexistente**: el update falló al reemplazar la instancia y el stack volvió solo al
   estado anterior, con la instancia original intacta.

Conclusiones:

- **El diagnóstico sale de la pestaña Events**, del *Status reason* del evento `CREATE_FAILED` o
  `UPDATE_FAILED`, no de adivinar mirando la plantilla. Yo di por hecho que fallaba la AMI y era
  un security group.
- Una **AMI inexistente no la detecta nadie antes de desplegar**: ni cfn-lint ni el change set,
  que se crea sin problema. Solo falla al ejecutar, y para eso está el rollback.
- Los **stacks borrados** se pueden consultar con *Filter status → Deleted*, eventos incluidos.
- La consola trae opciones nuevas en el change set (*Express mode*, *Deployment validations*,
  *Resource auto-import*) que no salen en el curso ni entran en el examen.

**Limpieza:** borrar los dos stacks, comprobar en EC2 que las instancias quedan en `terminated` y
que no queda ninguna Elastic IP, y vaciar y borrar el bucket `cf-templates-...-us-east-1`.

---

## Service role (lección 90)

Rol de IAM que **CloudFormation asume** para crear, actualizar y borrar los recursos del stack en
nombre del usuario. Sirve para aplicar **mínimo privilegio**: el usuario puede gestionar stacks sin
tener permisos directos sobre los recursos que esos stacks crean.

| Quién | Qué necesita |
|---|---|
| **Usuario** | `cloudformation:*` (manejar stacks, nada más) + **`iam:PassRole`** sobre el ARN del rol |
| **Service role** | Trust policy con `"Service": "cloudformation.amazonaws.com"` + los permisos sobre los recursos (en la demo, S3) |

- Un usuario con `cloudformation:*` e `iam:PassRole` sobre un rol que solo tiene S3 puede desplegar
  stacks que crean buckets, pero **no puede tocar S3** desde la consola o la CLI. Si mete una
  instancia EC2 en la plantilla, el stack falla.
- Todo cambio pasa por una plantilla: queda versionado y con su historial de eventos. En
  CloudTrail aparece el `CreateStack` con la identidad del usuario, y las llamadas a S3, hechas por
  el rol.
- El rol **se elige por stack** (*Configure stack options → Permissions*). Uno puede servir para
  muchos stacks. Si no se elige ninguno, CloudFormation usa los permisos del usuario.
- Una vez asociado, CloudFormation lo usa en **todas** las operaciones del stack, incluido el
  delete. **Si se borra el rol antes que el stack, el stack ya no se puede borrar.**
- Que la demo le dé `AmazonS3FullAccess` al rol es por simplificar. En producción, el mínimo
  privilegio se aplica en el rol: solo las acciones necesarias y sobre ARNs concretos.

### `iam:PassRole`

**No es un rol, es un permiso**: el de **entregarle un rol a un servicio** de AWS para que actúe
con él. No es exclusivo de CloudFormation: hace falta en todo servicio al que se le asigna un rol
(el instance profile de EC2, como `AmazonEC2RoleForSSM` en la Sección 5; el rol de ejecución de
Lambda; los roles de tareas de ECS…). Con un usuario administrador va incluido y no se nota.

Sin controlarlo hay **escalada de privilegios**: un usuario que solo puede lanzar instancias podría
asignarles un rol de administrador, entrar en la instancia y usar esos permisos. Por eso se limita
al ARN del rol concreto:

```json
{
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::123456789012:role/CFN-S3"
}
```

Mi analogía en Linux: es como el permiso de decidir con qué usuario corre el pool de **php-fpm**
(`user = www-data`). Si cualquiera puede poner `user = root` y luego subir un `.php`, ya es root.
Si solo puede elegir `www-data`, lo peor que puede hacer su código es lo que `www-data` tenga
permitido.

### Práctica

Rol creado en IAM con *AWS service → CloudFormation* y `AmazonS3FullAccess`, y un stack que lo usa
con una plantilla que incluye una instancia EC2: **falla**, aunque mi usuario `roberto-admin` sí
puede crear instancias. Quien crea los recursos es CloudFormation con el rol, así que los permisos
que cuentan son los del rol. Si un stack con service role falla por permisos, se amplía el **rol**,
no el usuario.

**Limpieza, en este orden:** primero el stack (en `ROLLBACK_COMPLETE`, sin recursos), después el
rol de IAM y, por último, el bucket `cf-templates-...-us-east-1`.

---

## Capabilities (lección 91)

Es una **confirmación explícita** que CloudFormation exige antes de desplegar ciertas plantillas:
"sé que esta plantilla va a tocar IAM" o "sé que se va a transformar antes de desplegarse". Es una
medida de seguridad: una plantilla que crea roles o políticas puede dar más permisos de los
debidos (la escalada de privilegios de la 90), y AWS no deja hacerlo sin darse cuenta.

| La plantilla… | Capability |
|---|---|
| Crea o modifica recursos de IAM (rol, usuario, grupo, política, access keys, instance profile) **sin nombre fijo** | `CAPABILITY_IAM` |
| Lo mismo, pero **con nombre fijo** (`RoleName: MiRol`, `UserName: deploy`…) | `CAPABILITY_NAMED_IAM` |
| Usa **macros** / `Transform` o **nested stacks** | `CAPABILITY_AUTO_EXPAND` |

- `CAPABILITY_NAMED_IAM` incluye lo de `CAPABILITY_IAM`. Se pueden pasar varias a la vez.
- **Consola**: en *Review and create* aparece una casilla del tipo *"I acknowledge that AWS
  CloudFormation might create IAM resources"*, y si hay nombres fijos añade *"with custom names"*.
  CloudFormation detecta cuál hace falta.
- **CLI**: hay que saber cuál poner: `--capabilities CAPABILITY_IAM`.
- Si no se da, el despliegue falla con **`InsufficientCapabilitiesException`**.

**Práctica:** stack con `3-capabilities.yaml`: apareció la casilla de confirmación de IAM antes de
crear. Limpieza: borrar el stack (se lleva el recurso de IAM) y el bucket `cf-templates-...`.

---

## DeletionPolicy (lección 92)

Controla qué pasa con un recurso cuando **se borra el stack** o cuando **se quita el recurso de la
plantilla** en un update. Es una medida extra para conservar datos o hacer copia antes de borrar.

| Policy | Qué pasa con el recurso | Qué queda | Válido para |
|---|---|---|---|
| `Delete` | Se borra | Nada | Casi todo. **Es el valor por defecto** |
| `Retain` | Sigue vivo, pero CloudFormation deja de gestionarlo | El recurso entero, facturando | **Cualquier** recurso |
| `Snapshot` | Se hace una copia final y luego se borra | El snapshot, facturando por almacenamiento | Solo recursos con snapshots: EBS, ElastiCache, RDS, Redshift, Neptune, DocumentDB |

- **Excepción al valor por defecto:** en RDS (`AWS::RDS::DBCluster` y `AWS::RDS::DBInstance` sin
  cluster) el valor por defecto es **`Snapshot`**.
- **`Delete` no funciona en un bucket S3 con objetos**: igual que `rmdir` con un directorio lleno,
  el borrado falla y el stack se queda en `DELETE_FAILED`. Soluciones: vaciarlo a mano (como el
  `cf-templates-...`), `DeletionPolicy: Retain` o un custom resource que lo vacíe (lección 96).
- Lo retenido y los snapshots **ya no pertenecen a ningún stack**: hay que borrarlos a mano.

No hice la práctica: solo muestra que, tras borrar el stack, quedan el recurso retenido y el
snapshot.

---

## UpdateReplacePolicy (lección 93)

Mismos valores (`Delete`, `Retain`, `Snapshot`), pero aplicados cuando un **update obliga a
reemplazar** el recurso (el `Replacement: True` del change set): decide qué pasa con el **recurso
viejo**. No se aplica en updates sin reemplazo.

**`DeletionPolicy` no protege en un reemplazo.** Una base de datos con `DeletionPolicy: Snapshot`
está protegida si se borra el stack, pero si un update la reemplaza, la vieja se borra sin
snapshot, salvo que también tenga `UpdateReplacePolicy: Snapshot`. Para un recurso crítico se
ponen **las dos**.

---

## Stack Policy (lección 94)

Documento JSON que se aplica **sobre el stack** (no dentro de la plantilla) y decide **qué recursos
se pueden actualizar**. Solo afecta a **updates**.

- **Al poner una stack policy, todos los recursos quedan protegidos por defecto.** Hay que añadir
  un `Allow` explícito para lo que sí se pueda actualizar. Lo típico: permitir `Update:*` sobre
  todo y denegarlo solo sobre el recurso crítico.
- **No protege contra el borrado del stack**: para eso está la termination protection.
- Para actualizar un recurso protegido se puede pasar una **policy temporal** solo para ese update.

| Mecanismo | Dónde va | Protege frente a |
|---|---|---|
| `DeletionPolicy` / `UpdateReplacePolicy` | En la plantilla, en cada recurso | Perder el recurso al borrarlo o reemplazarlo |
| Stack Policy | Sobre el stack | Updates de recursos concretos |
| Termination Protection | Sobre el stack | Borrar el stack |

---

## Termination Protection (lección 95)

Impide **borrar el stack** por accidente. Se activa al crear el stack (en las opciones) o después
(*Stack actions → Edit termination protection*). Mientras esté activa, Delete stack falla: hay que
desactivarla antes de poder borrarlo.

---

## Custom Resources (lección 96)

Se usan para:

- Recursos que **CloudFormation aún no soporta**.
- Lógica de aprovisionamiento propia para recursos **fuera de CloudFormation** (on-premises, de
  terceros…).
- Ejecutar **scripts propios** durante create / update / delete. El ejemplo típico: **vaciar un
  bucket S3 antes de que CloudFormation lo borre**.

```yaml
Resources:
  MyCustomResourceUsingLambda:
    Type: Custom::MyLambdaResource
    Properties:
      ServiceToken: arn:aws:lambda:REGION:ACCOUNT_ID:function:FUNCTION_NAME
      # Input values (optional)
      ExampleProperty: "ExampleValue"
```

- Se definen con `AWS::CloudFormation::CustomResource` o, **recomendado**,
  `Custom::MiNombreDeTipo`.
- Detrás hay una **Lambda** (lo más habitual) o un **topic de SNS**.
- **`ServiceToken`**: ARN de la Lambda o el topic al que CloudFormation envía las peticiones.
  Obligatorio y en la **misma región**. El resto de propiedades son datos de entrada opcionales.
- El custom resource no lleva el código: apunta a la Lambda, que puede estar en la misma plantilla
  o existir por su cuenta.

Funciona como un **webhook**: CloudFormation le envía el evento (`Create`, `Update` o `Delete`) con
los datos, la Lambda ejecuta su lógica y **responde** si ha ido bien o mal. Si nunca responde, el
stack se queda colgado en `IN_PROGRESS` hasta el timeout.

---

## Dynamic References (lección 97)

Permiten leer valores guardados en **SSM Parameter Store** y **Secrets Manager** desde la
plantilla. CloudFormation los resuelve durante las operaciones de create / update / delete.
Sintaxis: `'{{resolve:service-name:reference-key}}'`.

| Tipo | Lee de | Ejemplo |
|---|---|---|
| `ssm` | Parameter Store, texto plano | `'{{resolve:ssm:S3AccessControl:2}}'` |
| `ssm-secure` | Parameter Store, `SecureString` | `'{{resolve:ssm-secure:IAMUserPassword:10}}'` |
| `secretsmanager` | Secrets Manager | `'{{resolve:secretsmanager:MyRDSSecret:SecretString:password}}'` |

- Es la alternativa segura a `NoEcho` (lección 84): el secreto **no aparece** en la plantilla ni en
  la consola.
- CloudFormation **no puede crear** parámetros `SecureString` (`AWS::SSM::Parameter` solo admite
  `String` y `StringList`), aunque sí puede **leerlos** con `ssm-secure`, solo en algunas
  propiedades.
- Para datos no secretos sí puede crear parámetros, por ejemplo guardar el endpoint de una base de
  datos para que lo lean otras aplicaciones:

  ```yaml
  DBEndpointParam:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /miapp/prod/db-endpoint
      Type: String
      Value: !GetAtt MyDB.Endpoint.Address
  ```

### Contraseña de RDS: dos opciones

| | Opción 1: `ManageMasterUserPassword: true` | Opción 2: dynamic reference |
|---|---|---|
| Quién crea el secreto | **RDS**, automáticamente en Secrets Manager | Yo, con `AWS::SecretsManager::Secret` y `GenerateSecretString` |
| Cuánto hay que escribir | Una línea | El secreto + `{{resolve:secretsmanager:...}}` en `MasterUsername` / `MasterUserPassword` + `AWS::SecretsManager::SecretTargetAttachment` |
| Rotación | La gestiona RDS | El `SecretTargetAttachment` enlaza secreto e instancia para la rotación |
| Control | Menos | Total: nombre, longitud, caracteres excluidos… |

La opción 1 es la cómoda y la respuesta si piden la forma más sencilla con rotación gestionada. El
ARN del secreto se obtiene con `!GetAtt MyCluster.MasterUserSecret.SecretArn`. La opción 2 es el
patrón general, válido para cualquier recurso que necesite un secreto.

---

## Fin de la parte `[DVA]` (lección 98)

Las lecciones 80 a 97 marcadas como `[DVA]` son el repaso de CloudFormation reutilizado del curso
de Developer Associate. Desde la 99 empiezan las específicas del examen de **SysOps** (el nombre
anterior del SOA-C03). Las lecciones están grabadas con la consola antigua: las plantillas siguen
siendo válidas, pero la interfaz ha cambiado.

---

## User Data (lección 99)

Primera lección específica de CloudOps. El `UserData` de una instancia EC2 se puede escribir
dentro de la plantilla, igual que en la consola al lanzar la instancia. Lo importante es pasar
**el script entero por `Fn::Base64`**.

```yaml
UserData:
  Fn::Base64: |
    #!/bin/bash -xe
    dnf update -y
    dnf install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello World from user data</h1>" > /var/www/html/index.html
```

- La salida del script queda en **`/var/log/cloud-init-output.log`**, dentro de la instancia. Es
  lo único realmente nuevo respecto a mi práctica libre de la 83.
- La plantilla del curso no usa `!Sub` porque el script no tiene variables. Aun así escribe
  `Fn::Base64:` en forma larga: si luego hace falta un `!Sub`, ya está preparado (dos formas
  cortas seguidas, `!Base64 !Sub`, no valen en YAML, ver lección 88).
- **`#!/bin/bash -xe`**: `-x` imprime cada comando antes de ejecutarlo (las líneas con `+`
  delante en el log, que dicen en qué paso se ha quedado el script) y `-e` corta el script en el
  primer comando que falle.

### Cómo sabe YAML dónde termina el bloque `|`

Por la **indentación**, como Python. La sangría del bloque la fija su primera línea con
contenido, y el bloque termina en la primera línea con **menos** sangría. Las líneas vacías
intermedias siguen dentro. Es como un heredoc de bash (`<<EOF`), pero sin delimitador de cierre.

```yaml
UserData:
  Fn::Base64: |
    #!/bin/bash -xe      ← marca la sangría del bloque
    dnf install -y httpd
                         ← línea vacía: sigue dentro
  # comentario           ← menos sangría: aquí termina
```

- La sangría base **se elimina** del contenido: el script llega a EC2 con el `#!/bin/bash` en la
  columna 0, que es donde tiene que estar el shebang.
- `|` conserva un salto de línea final, `|-` ninguno y `|+` todos. `>` une las líneas en una sola,
  así que para scripts siempre `|`.

### El problema

CloudFormation marca la instancia como `CREATE_COMPLETE` en cuanto EC2 la lanza, **no cuando
termina el user data**. Si el script falla a mitad, el stack sale en verde igualmente. Es lo que
resuelven las lecciones siguientes.

**Práctica** (`0-user-data.yaml`, `us-east-1`): stack con instancia y security group, página de
Apache visible en la IP pública y log revisado por EC2 Instance Connect.

---

## `cfn-init` (lección 100)

Los problemas del user data que plantea el curso: configuraciones muy grandes, cómo cambiar el
estado de la instancia **sin terminarla y crear otra**, cómo hacerlo más legible y cómo saber si
el script ha terminado bien.

La respuesta son los **CloudFormation Helper Scripts**: scripts de Python que vienen en las AMIs de
Amazon Linux (en otras se instalan con `yum` o `dnf`): **`cfn-init`**, **`cfn-signal`**,
`cfn-get-metadata` y **`cfn-hup`**. Se ejecutan **dentro de la instancia**.

La configuración se declara en la `Metadata` del recurso, en `AWS::CloudFormation::Init`, y el
`UserData` se queda en lo mínimo: llamar a `cfn-init`.

```yaml
MyInstance:
  Type: AWS::EC2::Instance
  Properties:
    # ...
    UserData:
      Fn::Base64:
        !Sub |
          #!/bin/bash -xe
          dnf update -y aws-cfn-bootstrap
          /opt/aws/bin/cfn-init -s ${AWS::StackId} -r MyInstance --region ${AWS::Region}
  Metadata:
    AWS::CloudFormation::Init:
      config:
        packages:
          yum:
            httpd: []
        files:
          "/var/www/html/index.html":
            content: |
              <h1>Hello World from EC2 instance!</h1>
            mode: '000644'
        commands:
          hello:
            command: "echo 'hello world'"
        services:
          sysvinit:
            httpd:
              enabled: 'true'
              ensureRunning: 'true'
```

- Un `config` se ejecuta **siempre en este orden**, lo escriba como lo escriba: `packages` →
  `groups` → `users` → `sources` → `files` → `commands` → `services`.
- `cfn-init` va a buscar la `Metadata` a la API de CloudFormation. Por eso recibe el stack (`-s`)
  y el recurso (`-r`).
- Es **declarativo**: no se escribe `dnf install` ni `systemctl enable`, se declara el paquete o el
  servicio y el estado que se quiere.
- **No es obligatorio.** Para algo pequeño, un `UserData` normal vale. Con 100 paquetes, ficheros y
  servicios, la `Metadata` se lee mucho mejor que un script largo.
- **`cfn-init` no avisa a CloudFormation.** Si falla, el stack sale en verde igual que en la 99. Eso
  lo hace `cfn-signal` (lección 101).
- **`cfn-hup`**: el `UserData` solo se ejecuta en el primer arranque. Si `cfn-hup` corre en la
  instancia, detecta cambios en la `Metadata` y vuelve a lanzar `cfn-init`: así se cambia la
  configuración **sin reemplazar la instancia**.
- `dnf update -y aws-cfn-bootstrap` devolvió *Nothing to do*: Amazon Linux 2023 ya trae los helper
  scripts.
- La línea `|| error_exit 'Failed to run cfn-init'` de la plantilla del curso llama a una función
  `error_exit` que **no está definida** en el script. En las plantillas de ejemplo de AWS se define
  al principio.

| Log | Contenido |
|---|---|
| `/var/log/cloud-init-output.log` | Salida del `UserData`, incluida la llamada a `cfn-init` con el ARN del stack ya resuelto |
| `/var/log/cfn-init.log` | Lo que ha hecho `cfn-init`, paso a paso |
| `/var/log/cfn-init-cmd.log` | Salida de cada `command` |

**Práctica** (`1-cfn-init.yaml`, `us-east-1`): página generada por `cfn-init` y `cfn-init.log` con
cada paso (paquete instalado, comando, servicio habilitado y arrancado).

---

## `cfn-signal` y Wait Conditions (lección 101)

`cfn-signal` se ejecuta justo después de `cfn-init` y le dice a CloudFormation si la configuración
ha ido bien o mal. Del otro lado hace falta una **WaitCondition**, que bloquea la plantilla hasta
recibir la señal.

```yaml
UserData:
  Fn::Base64:
    !Sub |
      #!/bin/bash -x
      dnf update -y aws-cfn-bootstrap
      /opt/aws/bin/cfn-init -v --stack ${AWS::StackName} --resource MyInstance --region ${AWS::Region}
      INIT_STATUS=$?
      /opt/aws/bin/cfn-signal -e $INIT_STATUS --stack ${AWS::StackName} --resource SampleWaitCondition --region ${AWS::Region}
      exit $INIT_STATUS

SampleWaitCondition:
  CreationPolicy:
    ResourceSignal:
      Timeout: PT3M
      Count: 1
  Type: AWS::CloudFormation::WaitCondition
```

- **`INIT_STATUS=$?`** guarda el código de salida de `cfn-init`, se lo pasa a `cfn-signal` con
  `-e` y el script termina con ese mismo código.
- **Aquí el shebang es `-x`, sin `-e`, a propósito.** Con `-e`, si falla `cfn-init` el script se
  corta ahí y nunca llega a `cfn-signal`: el stack esperaría hasta el timeout en vez de fallar en
  el momento.
- **`CreationPolicy`**: `Timeout` en formato de duración ISO 8601 (`PT3M` = 3 minutos, `PT5M` = 5)
  y `Count`, el número de señales necesarias.
- La `CreationPolicy` también se puede poner **directamente en la instancia EC2 o en un Auto
  Scaling Group**, y `cfn-signal` apunta a ese recurso. En un ASG, `Count` suele ser el número de
  instancias.

Me recuerda a JavaScript: es un `await` sobre una promesa con timeout. Se resuelve con la señal de
éxito y se rechaza con una señal de fallo o al vencer el `Timeout`.

**Práctica** (`2-cfn-signal.yaml`, `us-east-1`): la instancia pasó a `CREATE_COMPLETE` a las
11:18:25, pero el stack no terminó hasta las 11:19:04, justo después de que `SampleWaitCondition`
recibiera el *SUCCESS signal* (con el ID de la instancia como `UniqueId`). Esos 40 segundos son lo
que tarda `cfn-init`. Ahora el verde del stack significa "aplicación configurada", no solo
"instancia lanzada".

---

## Fallos de `cfn-signal` (lección 102)

Qué revisar cuando la WaitCondition **no recibe las señales** que espera:

- Que la AMI tenga los **helper scripts**. Si no los trae, se pueden descargar a la instancia.
- Que `cfn-init` y `cfn-signal` se hayan ejecutado bien: `/var/log/cloud-init.log` o
  `/var/log/cfn-init.log`.
- Para poder entrar a leer esos logs hay que **desactivar el rollback**: si no, CloudFormation
  borra la instancia en cuanto falla el stack (ver lección 89).
- Que la instancia tenga **salida a Internet**, porque los scripts hablan con la API de
  CloudFormation: por **NAT** si está en una subnet privada o por **Internet Gateway** si está en
  una pública. Prueba rápida: `curl -I https://aws.amazon.com`.

**Práctica** (`3-cfn-signal-failure.yaml`, `us-east-1`): misma plantilla que la 101 con el comando
cambiado a `echo 'boom' && exit 1`. Vi dónde iba a fallar antes de que lo dijera el vídeo.
`cfn-init` falla, `cfn-signal` envía el error y `SampleWaitCondition` pasa a `CREATE_FAILED` con
*Received FAILURE signal* (marcado como *Likely root cause*), unos 40 segundos después de crearse
la instancia, sin esperar al timeout. Después, rollback de todo.

**Limpieza de las cuatro prácticas (99 a 102):** borrar cada stack (se lleva la instancia y el
security group) y vaciar y borrar el bucket `cf-templates-...-us-east-1`.

---

## Nested Stacks (lección 103)

Un **nested stack** es un stack que forma parte de otro. Sirve para aislar patrones que se
repiten (la configuración de un load balancer, un security group) en una plantilla aparte y
llamarla desde otras. Se considera buena práctica.

```yaml
Resources:
  MyKeyPair:
    Type: AWS::EC2::KeyPair
    Properties:
      KeyName: DemoKeyPair
      KeyType: rsa

  myStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://stephane-courses-s3-assets.s3.us-east-1.amazonaws.com/LAMP_Single_Instance.template
      Parameters:
        KeyName: !Ref MyKeyPair
        DBName: "mydb"
        # ...

Outputs:
  OutputFromNestedStack:
    Value: !GetAtt myStack.Outputs.WebsiteURL
```

- El recurso es de tipo **`AWS::CloudFormation::Stack`** y apunta a la plantilla hija con
  `TemplateURL` (en S3).
- El padre le pasa valores con `Parameters` y lee lo que devuelve con
  **`!GetAtt <nested>.Outputs.<nombre>`**.
- Un nested stack puede tener sus propios nested stacks (varios niveles).
- **Para actualizar un nested stack, siempre se actualiza el padre (root stack)**, nunca el hijo
  directamente.
- Crear el stack pide **`CAPABILITY_AUTO_EXPAND`** (lección 91) además del aviso de IAM.

Me lo imagino como un **componente de React**: la plantilla hija es el componente, los
`Parameters` son sus props, los `Outputs` lo que devuelve, y cada uso crea una instancia
independiente.

### Cross stack frente a nested stack

La diferencia es **compartir un recurso** frente a **reutilizar una plantilla**:

| | Cross stack | Nested stack |
|---|---|---|
| Idea | Compartir **un** recurso desplegado una vez | Reutilizar una **plantilla**; cada padre crea su propia copia |
| Ciclo de vida | Cada stack el suyo | El hijo pertenece al padre: se actualiza y se borra con él |
| Mecanismo | `Export` + `Fn::ImportValue` | `AWS::CloudFormation::Stack` + `TemplateURL` |
| Ejemplo | Un stack de VPC cuyo ID usan App 1, App 2 y App 3 | App 1 y App 2 tienen cada una su RDS, su ASG y su ELB, sin compartir nada |

Mis analogías:

- **Cross stack** es como **una base de datos compartida**: una sola instancia con su propio ciclo
  de vida, a la que se conectan varias aplicaciones. Igual que no se tira una BD con aplicaciones
  conectadas, CloudFormation no deja borrar un export mientras algún stack lo importe.
- **Nested stack** es como **un servicio dentro de un `docker-compose`**: la plantilla es la
  imagen, cada proyecto levanta su propio contenedor, y `docker compose down` se lo lleva por
  delante (borrar el padre borra el hijo). Tampoco se toca el contenedor a mano: se cambia el
  compose y se vuelve a aplicar.

**Práctica** (`4-nestedstacks.yaml`, `us-east-1`): la plantilla hija es la de ejemplo de AWS
`LAMP_Single_Instance` (en JSON, que Stéphane ha copiado a su bucket porque AWS ya no la mantiene).
Crea una instancia con Apache, PHP y MySQL, y usa `CreationPolicy` con `cfn-signal` como en la
101: el padre espera al hijo y el hijo espera la señal de su instancia.

- Cambié la contraseña de la base de datos. La plantilla hija tiene `NoEcho` en `DBUser` y
  `DBPassword`, pero la contraseña sigue **en claro en la plantilla padre**: `NoEcho` no cifra
  (lección 84). En un caso real, dynamic reference a Secrets Manager (lección 97).

**Limpieza:** borrar el stack padre (se lleva el nested stack y la key pair `DemoKeyPair`, que la
crea la propia plantilla) y vaciar y borrar el bucket `cf-templates-...-us-east-1`.

---

## DependsOn (lección 104)

**`DependsOn`** fuerza que un recurso se cree **después** de otro.

```yaml
Resources:
  EC2Instance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-0a3c3a20c09d6f377
      InstanceType: t2.micro

  MyBucket:
    Type: AWS::S3::Bucket
    DependsOn: EC2Instance
```

- Primero se crea la instancia y después el bucket. **Al borrar, el orden se invierte**: primero
  el bucket y luego la instancia.
- Con `!Ref` y `!GetAtt` la dependencia ya es **implícita** (lección 88). `DependsOn` es para
  cuando la dependencia existe pero no aparece en la plantilla.
- Se puede usar con cualquier recurso.
- Caso típico: una instancia o una Elastic IP en una VPC que necesita el **Internet Gateway ya
  asociado** (`AWS::EC2::VPCGatewayAttachment`). Nada los referencia entre sí, y sin `DependsOn`
  CloudFormation puede intentar crearlos en paralelo y fallar.
- En la plantilla del vídeo el recurso se llama `EC2Instance` pero el `DependsOn` apunta a
  `MyEC2Instance`, que no existe: tal cual, CloudFormation la rechaza por dependencia sin resolver.

**Práctica** (`5-dependson.yml`, `us-east-1`): solo comprobar el orden de creación en los eventos
del stack.

**Limpieza:** borrar el stack y el bucket `cf-templates-...-us-east-1`.

---

## StackSets: aviso de coste (lección 105)

Stéphane recomienda **ver las prácticas de StackSets (107 a 109) sin hacerlas**. La demo activa
**AWS Config** en varias regiones con un StackSet, y Config cobra por cada configuration item
registrado y por cada evaluación de reglas. A él le costó más de 72 $ mientras grababa. Además, si
al borrar se queda un recorder activo en alguna región, sigue cobrando sin que se vea en la región
seleccionada.

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
| Funciones que hay que saber | `Ref`, `GetAtt`, `FindInMap`, `ImportValue`, `Base64` y las de condiciones |
| Forma corta `!` | Solo en YAML. En JSON, `{"Fn::...": ...}` |
| `Ref` vs `GetAtt` | `Ref` = valor por defecto del recurso (ID de EC2, nombre de bucket). `GetAtt` = otros atributos (ARN, `PublicDnsName`…). Ver *Return values* en la documentación |
| Dependencias implícitas | `Ref` y `GetAtt` hacen que el recurso referenciado se cree antes |
| Falla la creación | Rollback de todo → `ROLLBACK_COMPLETE` (no actualizable: borrar y recrear). Opción de desactivar el rollback para investigar |
| Falla un update | Vuelve al último estado bueno → `UPDATE_ROLLBACK_COMPLETE` |
| `UPDATE_ROLLBACK_FAILED` | Arreglar los recursos a mano + `ContinueUpdateRollback` |
| Change set | Solo vista previa hasta *Execute change set* |
| Service role | Rol que asume CloudFormation. El usuario necesita `cloudformation:*` + `iam:PassRole`, no permisos sobre los recursos |
| `iam:PassRole` | Permiso para entregar un rol a un servicio. Limitarlo al ARN concreto para evitar escalada de privilegios |
| Borrar un rol en uso | Si se borra antes que su stack, el stack ya no se puede borrar |
| Capabilities | `CAPABILITY_IAM` (IAM sin nombre), `CAPABILITY_NAMED_IAM` (con nombre fijo), `CAPABILITY_AUTO_EXPAND` (macros, nested stacks). Sin ella → `InsufficientCapabilitiesException` |
| DeletionPolicy | `Delete` (por defecto; `Snapshot` en RDS), `Retain` (cualquier recurso), `Snapshot` (EBS, RDS, ElastiCache, Redshift, Neptune, DocumentDB) |
| Bucket S3 con objetos | `Delete` falla → `DELETE_FAILED`. Vaciar, `Retain` o custom resource |
| UpdateReplacePolicy | Igual, pero para el recurso viejo en un reemplazo. `DeletionPolicy` no protege ahí: poner las dos |
| Stack Policy | JSON sobre el stack que protege frente a **updates**. Al ponerla, todo protegido por defecto |
| Termination Protection | Impide borrar el stack. Desactivarla antes de borrar |
| Custom resources | `Custom::Nombre` + `ServiceToken` (Lambda o SNS, misma región). Ej.: vaciar un bucket antes de borrarlo |
| Dynamic references | `{{resolve:ssm / ssm-secure / secretsmanager:...}}`. CloudFormation no crea `SecureString` |
| RDS + Secrets Manager | `ManageMasterUserPassword: true` (sencillo, rotación gestionada) o secreto propio + dynamic reference + `SecretTargetAttachment` |
| User data en la plantilla | Script entero por `Fn::Base64`. Log en `/var/log/cloud-init-output.log` |
| Bloque YAML `\|` | Termina al volver a una sangría menor. `\|` un salto final, `\|-` ninguno, `\|+` todos |
| Problema del user data | El stack marca la instancia como `CREATE_COMPLETE` al lanzarla, aunque el script falle |
| Helper scripts | `cfn-init`, `cfn-signal`, `cfn-get-metadata`, `cfn-hup`. Vienen en Amazon Linux; en otras AMIs se instalan |
| `cfn-init` | Lee `AWS::CloudFormation::Init` de la `Metadata`. Orden: packages → groups → users → sources → files → commands → services. Log en `/var/log/cfn-init.log` |
| `cfn-hup` | Detecta cambios en la `Metadata` y relanza `cfn-init` sin reemplazar la instancia |
| `cfn-signal` + WaitCondition | `cfn-signal -e $?` informa del resultado. La `CreationPolicy` (`Timeout`, `Count`) bloquea hasta recibir las señales. También en EC2 y ASG |
| WaitCondition sin señales | Helper scripts en la AMI, logs de `cfn-init`, desactivar rollback para ver los logs, salida a Internet (NAT o IGW) |
| Nested stacks | `AWS::CloudFormation::Stack` + `TemplateURL`. Outputs con `!GetAtt <nested>.Outputs.<nombre>`. Se actualizan siempre desde el padre. Piden `CAPABILITY_AUTO_EXPAND` |
| Cross vs nested | Cross: compartir un recurso (VPC) con `Export`/`ImportValue`, ciclos de vida separados. Nested: reutilizar una plantilla, cada padre su copia, ligada a él |
| `DependsOn` | Fuerza el orden de creación (al borrar, al revés). Implícito con `!Ref`/`!GetAtt`. Típico: recursos que necesitan el `VPCGatewayAttachment` del IGW |
| StackSets + Config | Prácticas solo vistas: Config en varias regiones cobra por configuration item y evaluación |
