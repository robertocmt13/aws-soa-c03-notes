# EC2 Instance Connect y EIC Endpoint

Dos mecanismos relacionados pero distintos: el primero cambia **cómo se autentica**
el acceso SSH, el segundo permite acceder a instancias **sin IP pública**.

## SSH tradicional vs EC2 Instance Connect

### SSH tradicional

- Se genera un par de claves una vez y se descarga el `.pem`
- Esa clave privada vive en el disco del administrador **de forma permanente**
- El security group debe permitir el puerto 22 desde una **IP concreta** (`1.2.3.4/32`)

Problema práctico: si cambia la IP de origen (otro wifi, otra ubicación), hay que
actualizar el security group. Y la clave, si se filtra, sigue siendo válida
indefinidamente.

### EC2 Instance Connect

No se guarda ninguna clave. En cada conexión:

1. Se solicita el acceso (consola o CLI), autenticándose con **IAM**
2. AWS genera un par de claves nuevo y empuja la pública a la instancia
3. Esa clave es válida **60 segundos**
4. Pasado ese tiempo deja de servir

El security group ya no apunta a la IP del administrador, sino al **rango de IPs
de AWS** correspondiente al servicio (consultable en
`https://ip-ranges.amazonaws.com/ip-ranges.json`, filtrando por el servicio
`EC2_INSTANCE_CONNECT`), porque quien realmente contacta con el puerto 22 es el
servicio de AWS.

### Por qué importa

La diferencia real no es el formato de la clave, es **quién la custodia y durante
cuánto tiempo**:

- Un `.pem` es un secreto estático: quien lo obtenga lo sigue teniendo mañana
- Instance Connect exige volver a demostrar la identidad en cada conexión

Esto encadena el acceso SSH a la sesión de AWS del usuario, que a su vez puede
estar protegida con MFA. Con un `.pem`, la clave es autosuficiente y no pasa por
ningún control de IAM. Con Instance Connect, sin credenciales válidas de AWS ni
siquiera se llega a poder solicitar la clave temporal.

Es el mismo principio que AWS aplica de forma general: sustituir secretos estáticos
de larga duración (claves `.pem`, access keys) por **credenciales temporales**
(roles IAM, STS, Instance Connect).

## EIC Endpoint — acceso a instancias sin IP pública

### El problema que resuelve

En una arquitectura correcta, las instancias críticas (bases de datos, servicios
internos) viven en **subredes privadas**, sin IP pública. Así no son alcanzables
desde Internet y no hay puerto expuesto a fuerza bruta.

Pero entonces surge la pregunta operativa: ¿cómo se conecta un administrador por
SSH para mantenimiento o depuración?

Opciones tradicionales:

| Solución | Inconveniente |
|---|---|
| **Bastion host** | Hay que mantener, parchear y pagar una instancia dedicada |
| **NAT Gateway** | Coste fijo elevado (~35 USD/mes) y no se apaga |
| **VPN** | Más infraestructura y complejidad de red |

El **EIC Endpoint** cubre ese caso sin infraestructura propia: AWS actúa como
bastion gestionado.

### Cómo funciona

1. El administrador se conecta al **EC2 Instance Connect Endpoint Service**
   (servicio regional de AWS)
2. Ese servicio reenvía el tráfico al **EIC Endpoint** creado dentro de la VPC
3. Desde ahí el tráfico SSH llega a la instancia por **IP privada**, sin salir a
   Internet en ningún momento

No hace falta Internet Gateway, ni NAT Gateway, ni IP pública en la instancia.

### Los dos security groups

Este es el punto que más se confunde. Hacen falta dos reglas en sentidos opuestos:

- **Security group del EIC Endpoint** → debe permitir tráfico **saliente** (SSH)
  hacia las instancias destino
- **Security group de la instancia** → debe permitir tráfico **entrante** (SSH)
  **desde el security group del EIC Endpoint**, no desde la IP del administrador

El administrador nunca contacta directamente con la instancia.

### Conexión desde la CLI

```bash
aws ec2-instance-connect ssh --instance-id i-0123456789abcdef0
```

El comando encapsula el proceso completo: autenticación IAM, generación de la
clave temporal, y apertura del túnel a través del endpoint.

### Alcance

Un EIC Endpoint sirve para **varias instancias**, siempre que estén en **su misma
VPC** y sus security groups lo permitan. No es un permiso global: para otra VPC
hace falta otro endpoint.

### Escenario de examen

Instancia **sin IP pública** + **sin NAT Gateway** + necesidad de acceso SSH
puntual + **sin desplegar infraestructura adicional** → **EIC Endpoint**.

En ese escenario no es una preferencia: sin él no existe ninguna ruta de red desde
el exterior hasta la instancia.

## Nota de diagnóstico

Al exponer un servicio en una instancia, si no llega tráfico desde fuera, el orden
de comprobación es:

1. ¿El servicio está corriendo? — `systemctl status <servicio>`
2. ¿El **security group** tiene el puerto abierto? — causa más frecuente
3. ¿La **network ACL** de la subred lo permite? — abierta por defecto, rara vez es esto

Un `ERR_CONNECTION_TIMED_OUT` (el navegador espera y no recibe respuesta) apunta a
**puerto bloqueado por firewall**. Una conexión **rechazada de inmediato** apunta
a que no hay nada escuchando en ese puerto.
