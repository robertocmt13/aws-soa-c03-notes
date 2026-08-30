# Configuración inicial de IAM: usuario administrador, MFA y alias

> **Nota:** esta sección no forma parte del temario del curso. Es una práctica
> propia, motivada por estar trabajando con el usuario root durante los primeros
> laboratorios. Aunque para un entorno de pruebas resulta cómodo, es contrario a
> las buenas prácticas que AWS recomienda desde el primer día, así que decidí
> corregirlo antes de seguir avanzando.

## Por qué no trabajar con el usuario root

El usuario root tiene poder absoluto e ilimitado sobre la cuenta: puede cerrarla,
cambiar el método de pago y acceder a toda la facturación. **No se le pueden
aplicar restricciones** — ninguna política IAM lo limita. Si esas credenciales se
filtran, no hay red de seguridad posible.

Un usuario IAM tiene exactamente los permisos que se le asignen, y esos permisos
se pueden revocar, rotar o afinar sin tocar la cuenta.

Es la misma lógica que se aplica en un sistema Linux: no se trabaja como `root`
todo el día, se usa un usuario propio y se escala privilegios cuando hace falta.

### Lo que sigue siendo exclusivo del root

Aunque el usuario IAM tenga `AdministratorAccess`, estas acciones solo puede
hacerlas el root:

- Cerrar la cuenta de AWS
- Cambiar el método de pago
- Cambiar el plan de soporte
- Restaurar permisos de un usuario IAM que se haya bloqueado a sí mismo

Las credenciales del root se guardan y no se usan en el día a día.

## Pasos realizados

### 1. Crear el usuario IAM

`IAM → Users → Create user`

- Nombre: `roberto-admin`
- Marcar **Provide user access to the AWS Management Console**
- Contraseña personalizada
- Permisos: **Attach policies directly** → `AdministratorAccess`

**Detalle a tener en cuenta:** al buscar "administrator" en el listado de
políticas aparecen varias con nombre parecido (`AdministratorAccess-Amplify`,
`AdministratorAccess-AWSElasticBeanstalk`...). Son políticas acotadas a un
servicio concreto. `AdministratorAccess` ya cubre la cuenta entera, así que
adjuntar las demás no aporta nada.

### 2. Activar MFA en el usuario IAM

`IAM → Users → roberto-admin → Security credentials → Multi-factor authentication`

Tener MFA solo en el root no aporta gran cosa si el trabajo diario se hace con
otro usuario. Ambos deben tenerlo.

### 3. Crear un alias de cuenta

`IAM → Dashboard → AWS Account → Account Alias → Create`

Sin alias, el login de un usuario IAM exige introducir el **Account ID de 12
dígitos**. El alias lo sustituye por un nombre y además genera una URL directa:

```
https://<alias>.signin.aws.amazon.com/console
```

**Restricción:** los alias solo admiten minúsculas, números y guiones. Las
mayúsculas se convierten automáticamente.

## Errores encontrados durante el proceso

**`Authentication failed` al iniciar sesión como usuario IAM.**
El campo *Account ID or alias* del formulario espera el ID numérico de la cuenta
o un alias creado explícitamente. El **Account name** que muestra la consola
(la etiqueta descriptiva junto al Account ID, arriba a la derecha) **no sirve**
para iniciar sesión, aunque a simple vista parezca un alias.

Distinción entre los tres conceptos:

| Concepto | Qué es | ¿Sirve para login? |
|---|---|---|
| **Account ID** | Identificador numérico de 12 dígitos | Sí |
| **Account name** | Etiqueta descriptiva de la cuenta | No |
| **Account alias** | Identificador creado a propósito en IAM | Sí |

## Notas adicionales

**IAM es un servicio global, no regional.** La consola redirige siempre a
`us-east-1` aunque se esté trabajando en otra región. Usuarios, roles y políticas
son válidos en todas las regiones. Esta distinción entre servicios globales y
regionales es relevante de cara al examen.

**Roles preexistentes.** Es habitual encontrar roles en la cuenta sin haberlos
creado manualmente. Son *service-linked roles* que AWS genera automáticamente al
utilizar determinados servicios. No conviene eliminarlos.

## Estado final

El panel de IAM (`Security recommendations`) debe quedar sin avisos pendientes:

- MFA activado en el usuario root
- MFA activado en el usuario IAM
- Sin access keys en desuso
