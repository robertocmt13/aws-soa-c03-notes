# 07 — CloudFormation for CloudOps

Notas de la Sección 7 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lección 79 completada: qué es CloudFormation, ventajas, funcionamiento,
> formas de desplegar plantillas y componentes de una plantilla.

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
