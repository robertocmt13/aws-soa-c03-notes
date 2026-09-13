# 06 — EC2 High Availability and Scalability

Notas de la Sección 6 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 50 a 67 completadas: escalabilidad, alta disponibilidad,
> Elastic Load Balancing, Application Load Balancer y Network Load Balancer (teoría y práctica),
> Gateway Load Balancer, Sticky Sessions, Cross-Zone Load Balancing, certificados SSL y SNI,
> Deregistration Delay, health checks, monitorización y troubleshooting, atributos del target
> group y reglas del ALB.

---

## Escalabilidad

Capacidad de una aplicación o sistema de **soportar más carga adaptándose**. Hay dos tipos:

| | Vertical | Horizontal |
|---|---|---|
| Qué significa | Aumentar el tamaño de la instancia | Aumentar el número de instancias |
| Uso típico | Sistemas no distribuidos: bases de datos (RDS, ElastiCache) | Aplicaciones web, sistemas distribuidos |
| Límite | El hardware: existe un tamaño máximo de instancia | Prácticamente ninguno |
| En EC2 | Cambiar el tipo de instancia | Auto Scaling Group + Load Balancer |

El curso lo explica con un call center: sustituir a un operador junior por uno senior es escalar
en vertical; contratar más operadores es escalar en horizontal. A la escalabilidad horizontal
también se la llama **elasticidad**.

Detalle operativo: en una instancia respaldada por EBS, cambiar el tipo de instancia exige
**stop/start**. El escalado vertical en EC2 conlleva un corte de servicio.

### Requisito del escalado horizontal: nada de estado local

Varias instancias detrás de un balanceador solo funcionan si ninguna guarda en su disco algo que
las demás necesiten. Si un fichero subido se queda en una instancia, las otras no lo ven, y cada
petición puede caer en una instancia distinta.

| Tipo de dato | Dónde va |
|---|---|
| Código | Dentro de la AMI, o desplegado en cada instancia |
| Imágenes y ficheros subidos | S3, normalmente con CloudFront delante |
| Directorio compartido montado en todas las instancias | EFS |
| Caché | Local en cada instancia, o compartida en ElastiCache |
| Datos de la aplicación | Base de datos compartida |

Los tres almacenamientos que hay que distinguir:

- **S3**: almacenamiento de objetos, accesible por API/HTTP. **No es un sistema de ficheros**: se
  sube y se descarga el objeto entero. Hay herramientas para montarlo como disco (s3fs,
  Mountpoint for S3), pero no se comportan como un sistema de ficheros POSIX: no admiten bien
  escrituras parciales ni bloqueos.
- **EFS**: sistema de ficheros NFS gestionado, montable a la vez en muchas instancias y en varias
  AZs. Con miles de ficheros pequeños es lento, como cualquier NFS.
- **EBS**: disco ligado a una AZ y, en el caso normal, a una sola instancia.

---

## Alta disponibilidad

Suele ir de la mano del escalado horizontal. Significa ejecutar la aplicación en **al menos dos
centros de datos, es decir, dos Availability Zones**. El objetivo es **sobrevivir a la pérdida de
un centro de datos**.

Puede ser de dos tipos:

- **Pasiva**: un standby que solo entra si cae el principal. Ejemplo: RDS Multi-AZ.
- **Activa**: todos los nodos sirven tráfico a la vez. Es el escalado horizontal.

Las IPs failover que usaba en producción son HA pasiva: la IP pasaba al servidor sano, pero en
cada momento solo uno servía tráfico.

### Escalabilidad no es alta disponibilidad

Van de la mano, pero son conceptos distintos:

- Un ASG con diez instancias **en una sola AZ** escala en horizontal, pero no es HA: si cae la
  AZ, caen las diez.
- Una instancia enorme escala en vertical y tampoco es HA.

En EC2, la alta disponibilidad viene de desplegar el ASG y el load balancer **en varias AZs**.

### Alta disponibilidad no es recuperación ante desastres

| | Protege frente a | Cómo |
|---|---|---|
| Alta disponibilidad | Caída de un centro de datos | **Multi-AZ** |
| Recuperación ante desastres (DR) | Caída de una región entera | **Multi-región**: copias en otra región |
| Backups | Borrados y corrupción de datos | Copias independientes del sistema en marcha |

La HA no protege frente a un borrado: la réplica replica también el borrado.

La separación física importa. Si se incendia un centro de datos, puede quedar fuera de servicio
todo el recinto, no solo el edificio afectado: tener servidores en dos edificios del mismo
recinto no sirve de nada, y los backups guardados en ese mismo centro de datos se pierden con
los servidores. Las AZs de AWS están separadas físicamente, con alimentación y red
independientes.

Para DR en AWS, un ejemplo ya visto es la copia de AMIs entre regiones
([sección 4](../04-ami/)).

### Ejemplo aplicado: preparar un pico previsible

Cómo se prepararía un pico como el Black Friday en una tienda online. Varias piezas se ven más
adelante en el curso.

1. **Semanas antes.** Frontales sin estado local. Pruebas de carga para saber qué se rompe
   primero (en una tienda suele ser la base de datos). Revisar las **cuotas** de la cuenta: EC2
   tiene un límite de vCPUs On-Demand por región, y si el ASG choca con él no puede lanzar más
   instancias. Se amplía en **Service Quotas**, y la solicitud tarda.
2. **Días antes, la base de datos.** Las escrituras van a la instancia principal, que se escala
   **en vertical** en una ventana tranquila, porque hay corte. Las lecturas se escalan **en
   horizontal** con read replicas y se descargan con una caché (ElastiCache).
3. **El día, los frontales.** ASG detrás de un ALB, en al menos dos AZs. **Scheduled scaling**
   para subir la capacidad antes de que empiece el pico, porque una instancia tarda minutos en
   estar lista. **Target tracking** encima, para cubrir lo que no se haya previsto.
4. **Después.** Devolver la capacidad a su valor normal.

> Lo previsible se escala por adelantado; lo imprevisible, con políticas reactivas.

---

## Elastic Load Balancing

Un load balancer es un servidor que **reenvía el tráfico a varios servidores** situados detrás
(por ejemplo, instancias EC2). Reparte **peticiones o conexiones**, no usuarios: sin stickiness,
dos peticiones seguidas del mismo cliente pueden acabar en instancias distintas.

### Para qué sirve

- Repartir la carga entre varias instancias.
- Exponer un **punto de acceso único** (un nombre DNS) para la aplicación.
- Gestionar **de forma transparente** (*seamlessly*) la caída de instancias.
- Hacer **health checks** periódicos a las instancias.
- Terminar el **SSL** (HTTPS) de los sitios web.
- Mantener la **stickiness** con cookies.
- Dar **alta disponibilidad entre zonas**.
- **Separar el tráfico público del privado.**

Lo de *seamlessly* funciona gracias a los health checks: si una instancia deja de responder, el
balanceador deja de mandarle tráfico y el usuario no se entera. Es un failover automático con
todas las instancias activas a la vez. **No es instantáneo**: la instancia tiene que fallar
varios checks seguidos antes de marcarse como *unhealthy*, y en ese intervalo alguna petición
puede fallar.

### Por qué uno gestionado

El ELB es un **balanceador gestionado**: AWS garantiza que funciona y se encarga de
actualizaciones, mantenimiento y alta disponibilidad, a cambio de ofrecer pocos parámetros de
configuración. Montar uno propio sale más barato, pero exige mucho más trabajo.

### ELB es regional

Un ELB reparte tráfico **entre AZs de una misma región, nunca entre regiones**. Para mandar a
cada usuario a la región más cercana se usan otros servicios, con un balanceador en cada región
detrás:

- **Route 53**, con enrutamiento por latencia o por geolocalización.
- **Global Accelerator**.

### Destinos frente a servicios integrados

La diapositiva de integraciones mezcla dos cosas: los **destinos**, que reciben el tráfico del
balanceador (EC2, Auto Scaling Groups, ECS), y los **servicios que colaboran con él** sin recibir
su tráfico (ACM, CloudWatch, Route 53, WAF, Global Accelerator).

Se ve siguiendo una petición a una tienda online:

| Paso | Servicio | Papel |
|---|---|---|
| 1 | Route 53 | Resuelve el dominio a la dirección del ALB. Actúa **antes** del balanceador |
| 2 | WAF | Inspecciona la petición en el ALB y bloquea lo malicioso |
| 3 | ACM | Proporciona el certificado con el que el ALB termina el HTTPS |
| 4 | EC2 (ASG) | **Destino**: la única pieza que recibe la petición del ALB |
| 5 | RDS | La aplicación se conecta **directamente** a su endpoint. No pasa por el ALB |
| 6 | S3 | El navegador descarga las imágenes directamente (o a través de CloudFront) |
| 7 | CloudWatch | Recibe las métricas del ALB: peticiones, errores 5xx, latencia |

**RDS y S3 no van detrás de un ELB.** Tienen su propio endpoint y resuelven su alta
disponibilidad por su cuenta: en RDS Multi-AZ, el nombre DNS del endpoint pasa a apuntar al
standby si cae el principal. Además, el ALB solo entiende HTTP, y MySQL habla su propio protocolo
sobre TCP.

Equivalencia aproximada con un stack clásico:

| Stack clásico | AWS |
|---|---|
| Nginx balanceando delante de PHP-FPM | ALB |
| MySQL | RDS |
| DNS propio | Route 53 |
| Let's Encrypt en Nginx | ACM en el ALB |
| ModSecurity | WAF |
| Grafana | CloudWatch |

### Tipos de load balancer

AWS tiene cuatro tipos de balanceador gestionado:

| Tipo | Generación | Año | Capa | Protocolos |
|---|---|---|---|---|
| Classic Load Balancer (CLB) | v1 | 2009 | 4 y 7 | HTTP, HTTPS, TCP, SSL |
| Application Load Balancer (ALB) | v2 | 2016 | 7 | HTTP, HTTPS, WebSocket |
| Network Load Balancer (NLB) | v2 | 2017 | 4 | TCP, TLS, UDP |
| Gateway Load Balancer (GWLB) | — | 2020 | 3 | Protocolo IP |

Se recomienda usar los de nueva generación, que ofrecen más funcionalidades.

Algunos balanceadores pueden ser **external** (públicos, de cara a internet) o **internal**
(privados, por ejemplo para comunicar capas internas de una aplicación).

### Classic Load Balancer: retirado

El CLB está **deprecated**, desaparecerá de la consola, y el examen ya no lo incluye. El curso no
lo cubre ni tiene práctica.

Si toca migrar uno, solo hay dos sustitutos reales:

- **ALB**, si el tráfico es HTTP/HTTPS.
- **NLB**, si es TCP, UDP o TLS, o si hace falta rendimiento extremo o una IP fija.

El **GWLB no sustituye a nada**: sirve para meter appliances de red de terceros (firewalls,
sistemas de detección de intrusos) en el camino del tráfico.

La migración no se hace sobre el mismo recurso: el balanceador nuevo tiene otro nombre DNS. Se
monta en paralelo, se prueba, se cambia el DNS, se espera a que expire el TTL y solo entonces se
borra el viejo.

---

## Application Load Balancer

Balanceador de **capa 7 (HTTP)**. Es el que corresponde a una aplicación web.

- Balancea entre **varias aplicaciones HTTP repartidas en varias máquinas** (target groups).
- Balancea entre **varias aplicaciones en la misma máquina** (contenedores).
- Soporta **HTTP/2 y WebSocket**.
- Soporta **redirecciones**, por ejemplo de HTTP a HTTPS.
- Encaja con **microservicios y aplicaciones en contenedores** (Docker, Amazon ECS).
- Tiene **port mapping** para redirigir a un **puerto dinámico en ECS**.

Con el CLB, en cambio, hacía falta **un balanceador por aplicación**, cada uno facturando por su
cuenta. Un solo ALB sirve para varias.

### Target groups

Un target group es el **conjunto de destinos** al que el ALB manda una parte del tráfico. Pueden
ser:

| Tipo de destino | Detalle |
|---|---|
| Instancias EC2 | Pueden estar gestionadas por un Auto Scaling Group |
| Tareas de ECS | Gestionadas por el propio ECS |
| Funciones Lambda | La petición HTTP se traduce en un **evento JSON** |
| Direcciones IP | Tienen que ser **IPs privadas** |

- Un ALB puede enrutar a **varios target groups**.
- Los **health checks se configuran a nivel de target group**: cada grupo es una aplicación
  distinta y se comprueba a su manera.

### Reglas de enrutamiento

Quien decide a qué target group va cada petición es la **regla del listener**. Se puede enrutar
según:

- La **ruta** de la URL: `example.com/users` y `example.com/posts`.
- El **hostname**: `one.example.com` y `other.example.com`.
- La **query string** y las **cabeceras**: `example.com/users?id=123&order=false`.

El enrutamiento por hostname **no es Route 53**. Route 53 resuelve los dos dominios a la misma
dirección del ALB, y el ALB lee la cabecera `Host` de la petición para decidir el target group.
Es lo mismo que el `server_name` de los virtual hosts de Nginx.

La equivalencia en Nginx de regla y target group:

```nginx
upstream users { server 10.0.1.10; server 10.0.2.10; }   # target group
location /user { proxy_pass http://users; }             # regla del listener
```

> Ruta, query string, cabeceras y cookies los controla el cliente y se pueden manipular. Las
> reglas del ALB sirven para **repartir tráfico, nunca para controlar el acceso**.

### Destinos por IP: servidores on-premises

El ejemplo del curso manda `?Platform=Mobile` a un target group de instancias EC2 y
`?Platform=Desktop` a otro de servidores on-premises con destinos por IP. Como las IPs de destino
tienen que ser **privadas**, llegar a servidores propios exige una conexión privada con la VPC
(VPN o Direct Connect).

### Hostname fijo, no IP fija

El ALB se expone con un **hostname fijo** (`XXX.region.elb.amazonaws.com`), **no con una IP
fija**: las IPs que hay detrás cambian, así que nunca se apunta a ellas. Si hace falta una IP
fija, eso es el **NLB**.

El ALB **termina la conexión**: la instancia ve la IP privada del balanceador, no la del cliente.
La IP real llega en la cabecera **`X-Forwarded-For`**, y el puerto y el protocolo en
`X-Forwarded-Port` y `X-Forwarded-Proto`.

Matiz práctico: el cliente puede mandar su propia `X-Forwarded-For` (con curl, por ejemplo). Por
defecto el ALB no la sustituye, sino que **añade la IP real al final**. El valor fiable es el
último, el que añade el balanceador; el primero lo puede haber puesto cualquiera.

---

## Práctica: ALB con dos instancias

### Montaje

Dos instancias `t3.micro` lanzadas a la vez desde el asistente, con este **user data** para que
cada una sirva su propio hostname y se distinga a cuál responde el balanceador:

```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
```

Al pedir más de una instancia, el asistente avisa: *"When launching more than 1 instance, consider
EC2 Auto Scaling"*. No es un error, es el recordatorio de que el patrón real de producción es
**ASG + load balancer**, no instancias sueltas.

Orden de creación:

1. **Security group para el ALB** (`demo-sg-load-balancer`): entrada HTTP:80 desde `0.0.0.0/0`.
2. **Target group** (`demo-tg-alb`): tipo *Instances*, protocolo HTTP, puerto 80, y registro de
   las dos instancias.
3. **ALB** (`DemoALB`): esquema *Internet-facing*, el security group anterior y un listener
   HTTP:80 que reenvía al target group.

El ALB exige **al menos dos Availability Zones** — lo dice el propio formulario de *Network
mapping*. Es la materialización de que un balanceador sin varias AZs no da alta disponibilidad.

### Resultado

El ALB entrega un **hostname**, no una IP:

```
http://demoalb-1744094106.eu-north-1.elb.amazonaws.com/
```

Recargando, la respuesta alterna entre las dos instancias.

### Unused frente a Unhealthy

Al **parar** una de las instancias, el target group la marca como `Unused`, con el detalle
*"Target is in the stopped state"*, y el ALB deja de mandarle tráfico: a partir de ahí la URL
devuelve siempre el mismo `Hello World`.

Son dos estados distintos y el examen los diferencia:

| Estado | Qué significa |
|---|---|
| **Unused** | El destino está registrado pero **parado o terminado**. Ni se intenta el health check |
| **Unhealthy** | El destino está **corriendo** pero falla el chequeo: puerto cerrado, servicio caído, 5xx |

Parar la instancia da `Unused`. Un `systemctl stop httpd` dejando la máquina encendida daría
`Unhealthy`.

Esto es el failover automático en funcionamiento: el health check es **activo y continuo**, el
ALB lo lanza por su cuenta cada intervalo, y al detectar el fallo retira el destino sin que haya
que tocar nada.

---

## Cadena de security groups

El patrón de seguridad correcto para un ALB: **las instancias no aceptan tráfico de internet, solo
del balanceador**.

| Security group | Regla de entrada |
|---|---|
| Del **ALB** | HTTP:80 desde `0.0.0.0/0` |
| De las **instancias** | HTTP:80 **con origen el security group del ALB**, no un CIDR |

En el desplegable de *Source* de una regla se puede elegir un CIDR o **otro security group**. Al
referenciar el SG del balanceador, la regla dice "acepto el puerto 80 de cualquier cosa que
pertenezca a ese grupo", sin depender de IPs que cambian.

### Comprobación

Con la cadena montada:

- La **URL del ALB sigue funcionando**.
- Las **IPs públicas de las instancias dejan de responder**: el navegador se queda cargando hasta
  dar `ERR_CONNECTION_TIMED_OUT`.

El detalle del **timeout** importa en un diagnóstico: un security group **descarta el paquete en
silencio**, y por eso el cliente espera hasta agotar el tiempo. Un `connection refused`
inmediato significaría que el paquete sí llegó y que no había nada escuchando en ese puerto. Ver
cuál de los dos se produce dice si el problema es de filtrado o de servicio.

---

## Reglas del listener

Un listener tiene una **regla por defecto** (*"si ninguna otra aplica"*) y reglas adicionales que
se evalúan antes.

Práctica: regla `DemoRule` sobre el listener HTTP:80.

| Campo | Valor |
|---|---|
| Condición | `Path` = `/error` |
| Acción | *Return fixed response* |
| Código | 404 |
| Content type | `text/plain` |
| Cuerpo | `Not Found, custom error` |
| Prioridad | 5 |

Resultado: `…elb.amazonaws.com/error` devuelve el texto personalizado, mientras que el resto de
rutas siguen yendo al target group.

### Prioridad

Las reglas se evalúan **de menor a mayor número**, y la regla `Default` **siempre va la última**.
Su prioridad no se puede cambiar. Con dos reglas no se nota, pero en cuanto hay varias
condiciones que podrían coincidir, el orden decide cuál gana.

### Las tres acciones posibles

| Acción | Qué hace |
|---|---|
| **Forward to target group** | Reenvía a los destinos. Es lo habitual |
| **Redirect to URL** | Devuelve una redirección. Es lo que se usa para HTTP → HTTPS |
| **Return fixed response** | **El propio ALB genera la respuesta**, sin tocar el backend |

La tercera es la base de las páginas de mantenimiento y de los bloqueos por ruta sin desplegar
nada en las instancias.

Límites que muestra la consola: 100 reglas por ALB, 5 valores de condición por regla, 6 comodines
por regla y 5 target groups ponderados por regla.

---

## Limpieza de la práctica del ALB

Hay dependencias, así que el orden no es opcional:

| # | Recurso | ¿Factura? | Nota |
|---|---|---|---|
| 1 | **Load balancer** | **Sí, por hora**, reciba tráfico o no | Primero. Mientras exista, bloquea lo demás |
| 2 | **Target group** | No | Solo se puede borrar cuando ningún listener lo referencia |
| 3 | **Instancias EC2** | **Sí** | Terminar |
| 4 | **Security group del ALB** | No | No se deja borrar mientras el ALB exista |
| 5 | Regla añadida al SG de las instancias | No | Quitarla si se va a reutilizar ese SG |

> El load balancer es el primer recurso del curso que **factura por hora solo por existir**. Con
> las instancias bastaba con terminarlas; aquí, un ALB olvidado un fin de semana se nota.

### Borrado asíncrono del target group

Justo después de borrar el ALB, el intento de borrar el target group falla con *"is currently in
use by a listener or a rule"*, aunque la misma pantalla muestre `Load balancer: None associated`.

No es un error: AWS **elimina los listeners y las reglas de forma asíncrona**, y durante un rato
el target group sigue viendo una referencia a un listener que ya no existe. Se resuelve solo
esperando un minuto y repitiendo el borrado.

---

## Network Load Balancer

Balanceador de **capa 4 (TCP/UDP)**. No entiende HTTP: mueve conexiones sin mirar lo que va
dentro.

- Reenvía tráfico **TCP y UDP** a las instancias.
- Soporta **millones de peticiones por segundo** con **latencia ultra baja**. Al no inspeccionar
  el contenido, el trabajo por conexión es mínimo.
- Tiene **una IP estática por AZ** y admite asignarle **Elastic IPs**.
- Se elige para **rendimiento extremo, tráfico TCP o UDP**, o cuando hace falta una IP fija.

### Una IP fija por AZ

Es la gran diferencia con el ALB, que solo ofrece un hostname. La IP es **por AZ**: un NLB
desplegado en tres AZs tiene tres IPs fijas, y su nombre DNS resuelve a ellas (la consola lo
marca como *A Record*).

En el *Network mapping* se elige, para cada AZ:

| Opción | Qué da |
|---|---|
| **Assigned by AWS** | IP fija durante toda la vida del NLB. Es la opción por defecto. Se libera al borrar el NLB |
| **Use an Elastic IP address** | Una IP reservada en la cuenta. Sobrevive a borrar el NLB y se puede asociar a otro nuevo |

En la práctica la opción de Elastic IP aparecía deshabilitada porque no tenía ninguna reservada.

**Cuándo importa: whitelisting.** El caso típico es alguien que **se conecta a tu servicio** y
tiene que dar de alta tu IP como destino en su firewall: un partner B2B que envía pedidos a tu
API, o un cliente corporativo cuyo firewall solo permite conexiones salientes hacia IPs
autorizadas. Con un ALB no hay IP que darle; con un NLB, sí.

> La IP del NLB es de **entrada**. Si es el partner quien filtra las conexiones que **tú le haces
> a él**, lo que ve es la IP de salida de tus instancias (o la de un NAT Gateway), y el NLB no
> interviene.

### IP fija del NLB frente a la IP failover de OVH

La IP failover de OVH era fija y yo decidía qué servidor la tenía. En las migraciones de hardware
preparaba el servidor nuevo en segundo plano, movía la IP y el DNS ni se enteraba. El concepto de
fondo es el mismo: **desacoplar la IP pública del servidor que responde detrás**. Cambia quién
hace el cambio y cuándo.

| | IP failover (OVH) | Elastic IP | IP del NLB |
|---|---|---|---|
| Asociada a | Un servidor | Una instancia | El balanceador, en una AZ |
| Servidores activos detrás | Uno | Uno | Todos los del target group |
| Quién cambia el destino | Yo, a mano | Yo, a mano o por API | Los health checks, automáticamente |
| Cuándo | Evento planificado | Evento planificado | De forma continua, en segundos |

El equivalente directo de la IP failover en AWS es la **Elastic IP**. El NLB va un paso más allá:
su IP no salta nunca, porque el failover ocurre por debajo, entre los destinos.

### Target groups

Los destinos de un NLB pueden ser:

| Tipo de destino | Detalle |
|---|---|
| Instancias EC2 | Igual que en el ALB |
| Direcciones IP | Tienen que ser **privadas**: alcanzables desde la VPC, por ejemplo servidores on-premises con VPN o Direct Connect |
| **Application Load Balancer** | Permite encadenar NLB → ALB |

Los health checks admiten **TCP, HTTP y HTTPS**.

**El protocolo del target group no es HTTP.** Un target group de NLB se configura con protocolos
de capa 4 (TCP, UDP, TLS…). Cuando el diagrama del curso pone "HTTP" en la flecha hacia un target
group, significa que esa aplicación habla HTTP dentro de la conexión TCP: el NLB la transporta sin
interpretarla. Lo que sí puede ser HTTP es el **health check**: el target group es TCP, pero el
chequeo puede pedir una ruta por HTTP y comprobar el código de respuesta.

### NLB delante de un ALB

El cliente llega por la IP fija del NLB, el NLB reenvía la conexión TCP al ALB, y el ALB aplica
sus reglas de capa 7 (ruta, hostname, cabeceras) como siempre. Es la forma de tener **IP fija y
enrutamiento HTTP a la vez**, algo que ninguno de los dos da por separado.

### Security groups en el NLB

Durante años el NLB no admitía security groups. Ahora sí, pero **solo si se asocian al crearlo**:
un NLB creado sin security group no puede recibirlos después. Con SG, la cadena es la misma que
con el ALB.

---

## Práctica: NLB con dos instancias

Mismo montaje que la práctica del ALB: dos instancias `t3.micro` con el mismo user data, cada
una sirviendo su hostname.

Orden de creación:

1. **Security group para el NLB** (`demo-sg-nlb`): entrada HTTP:80 desde `0.0.0.0/0`.
2. **Instancias**, con el SG `launch-wizard-1` (SSH:22 y HTTP:80 desde `0.0.0.0/0`). Con el 80
   abierto se comprueba antes, por la IP pública, que httpd responde en cada instancia.
3. **Target group** (`demo-tg-nlb`): tipo *Instances*, protocolo **TCP**, puerto 80, con las dos
   instancias registradas.
4. **NLB** (`DemoNLB`): *Internet-facing*, IPv4, VPC por defecto, tres AZs (`eu-north-1a`, `1b` y
   `1c`) con IP asignada por AWS, el SG `demo-sg-nlb` y un listener **TCP:80** que reenvía a
   `demo-tg-nlb`.
5. **Cadena de security groups**: en `launch-wizard-1`, la regla HTTP:80 pasa a tener como origen
   `demo-sg-nlb` en lugar de `0.0.0.0/0`.

Error que cometí en el paso 1: metí la regla HTTP:80 en **Outbound** en lugar de Inbound. La
pantalla de creación del SG ya trae una regla de salida y es fácil acabar editando esa. La pista
estaba en el propio formulario: *"This security group has no inbound rules"*.

### Resultado

```
http://demonlb-70ff368268ca5228.elb.eu-north-1.amazonaws.com/
```

Los dos destinos aparecen `Healthy` y la respuesta alterna entre `ip-172-31-34-9` e
`ip-172-31-47-76`, pero **no en cada recarga**: hacía falta esperar un rato.

Es el comportamiento esperado de un balanceador de capa 4. El NLB reparte **conexiones TCP, no
peticiones HTTP**, y todo lo que viaja por una misma conexión va al mismo destino. El navegador
reutiliza la conexión (keep-alive) entre recargas, así que sigue cayendo en la misma instancia
hasta que la conexión se cierra. El ALB, en cambio, termina la conexión y decide el destino
**en cada petición**, por eso allí alternaba en cada recarga.

### Diferencias con la práctica del ALB

| | ALB | NLB |
|---|---|---|
| Listener | HTTP:80 | TCP:80 |
| Target group | HTTP | TCP |
| Reglas del listener | Ruta, hostname, cabeceras, fixed response | Solo reenviar al target group (admite varios con pesos) |
| Network mapping | Subredes | Subredes y, por AZ, IP asignada por AWS o Elastic IP |
| Unidad de reparto | Petición HTTP | Conexión TCP |

---

## Limpieza de la práctica del NLB

| # | Recurso | ¿Factura? | Nota |
|---|---|---|---|
| 1 | **NLB** | **Sí, por hora**, más una parte por uso (NLCU) | Primero |
| 2 | Target group | No | |
| 3 | **Instancias EC2** | **Sí** | Terminar |
| 4 | Regla del SG de las instancias que referencia `demo-sg-nlb` | No | Quitarla antes del paso 5 |
| 5 | Security group del NLB | No | |

Un security group **referenciado por una regla de otro SG no se puede borrar**. Hay que quitar
antes esa referencia, igual que el SG del ALB no se deja borrar mientras el ALB exista.

---

## Gateway Load Balancer

Balanceador de **capa 3 (paquetes IP)**, pensado para meter appliances de seguridad de
**terceros** (firewalls, IDS/IPS, deep packet inspection) delante de una aplicación sin
rediseñar la red.

- Combina dos funciones: **Transparent Network Gateway** (punto único de entrada/salida para
  todo el tráfico) y **Load Balancer** (reparte ese tráfico entre los appliances).
- El tráfico **no va dirigido al GWLB**: la route table de la subred lo desvía de forma
  transparente hacia él antes de que llegue a su destino real. El appliance decide si el paquete
  pasa o se descarta y, si pasa, se lo devuelve al GWLB, que lo reenvía al destino original. La
  aplicación nunca sabe que ese desvío existió.
- Usa el protocolo **GENEVE** por el puerto **6081**: encapsula el paquete original (con
  metadatos de origen/destino) para mandarlo al appliance, que lo desencapsula, decide, y lo
  vuelve a encapsular para devolverlo.
- Los destinos tienen que ser **appliances comerciales ya preparados para hablar GENEVE**
  (Palo Alto, Fortinet, Check Point…), normalmente del AWS Marketplace. Un `iptables` o un
  `fail2ban` normales no valen: no saben desencapsular GENEVE, y además trabajan a nivel de
  aplicación/logs, no de paquete IP.
- Sin hands-on en el curso: montar un appliance de verdad no es viable con recursos gratuitos.

---

## Sticky Sessions (Session Affinity)

Consigue que un mismo cliente vaya siempre a la misma instancia detrás del balanceador. Útil
para no perder datos de sesión que solo vive en una instancia (caché local, carrito en memoria).
Funciona en **CLB, ALB y NLB**, pero cada uno lo resuelve de forma distinta.

### ALB y CLB: por cookie

El balanceador inserta una cookie que el navegador devuelve en cada petición siguiente.

| Tipo de cookie | Quién la genera | Nombre | Duración |
|---|---|---|---|
| Duration-based | El load balancer | `AWSALB` (ALB) / `AWSELB` (CLB) | **7 días fijos, no configurable** |
| Application cookie | El target (tu app) | Lo eliges tú (no puede ser `AWSALB`, `AWSALBAPP` ni `AWSALBTG`, reservados) | La decide tu app |
| Application-based (auto) | El load balancer, imitando a una cookie de tu app | `AWSALBAPP` | — |

Con stickiness activo en la práctica del ALB, el navegador manda siempre la misma cookie y el
ALB la respeta: se vería la misma instancia en cada recarga, en vez de alternar como en la
práctica que hicimos.

### NLB: sin cookies, por IP de origen

El NLB opera en capa 4 y no puede leer ni insertar nada en el tráfico. Para conseguir
pegajosidad usa lo que ya tiene disponible de cada conexión: la **IP de origen del cliente**
(más el puerto), sobre la que aplica un hash para mandar siempre esa combinación al mismo
target. Consecuencia a tener en cuenta: varios clientes detrás del mismo NAT (una oficina
entera saliendo por la misma IP pública) caen todos en la misma instancia.

### Dependencias en el target group

- Stickiness **no se puede activar si Cross-zone load balancing está apagado**.
- No es compatible con el algoritmo de enrutamiento **Weighted random**.

---

## Cross-Zone Load Balancing

Decide si cada nodo del load balancer reparte tráfico entre **todas** las instancias de **todas**
las AZs habilitadas, o solo entre las de su propia AZ.

- **Con cross-zone**: cada nodo reparte su parte de tráfico por igual entre el total de instancias
  de todas las AZs, sin importar en cuál esté cada una.
- **Sin cross-zone**: cada nodo solo reparte entre las instancias de su propia AZ. Si una AZ tiene
  menos instancias que otra, esas cargan más tráfico por instancia que las de la AZ con más
  instancias.

### Por defecto y coste, según el tipo de balanceador

| Load balancer | Por defecto | Coste de datos inter-AZ si se activa |
|---|---|---|
| Application Load Balancer | **On** (se puede apagar a nivel de target group, no a nivel del ALB) | Sin coste |
| Network Load Balancer / Gateway Load Balancer | **Off** | **Con coste ($)** |
| Classic Load Balancer | Off | Sin coste si se activa |

El target group de un ALB tiene tres opciones: heredar el ajuste del balancer (por defecto,
hereda On), o forzarlo a On/Off explícitamente.

### Por qué apagarlo pese al desequilibrio

No es una cuestión de separar entornos (prod y dev nunca comparten balanceador). El motivo real
es el **coste de datos inter-AZ** en NLB/GWLB: si mantienes el mismo número de instancias en
cada AZ (típico con un Auto Scaling Group repartido a partes iguales), el desequilibrio de
tráfico entre AZs desaparece y te ahorras esa factura sin perder nada.

---

## Certificados SSL en el load balancer

El balanceador usa un **certificado X.509** (certificado de servidor SSL/TLS) para terminar el
HTTPS. El patrón normal es:

```
Usuario  --HTTPS (cifrado, por internet)-->  Load Balancer  --HTTP (VPC privada)-->  EC2
```

El tráfico entre el balanceador y las instancias va **sin cifrar** porque circula dentro de la
VPC. La excepción es el cumplimiento normativo: con PCI-DSS o similares puede exigirse cifrado
extremo a extremo, y entonces el tramo interno también va por HTTPS (*re-encryption*). No es lo
habitual, pero conviene tenerlo presente en una tienda online.

### De dónde sale el certificado

| Origen | Detalle |
|---|---|
| **ACM** (AWS Certificate Manager) | Lo emite y **renueva AWS**. Es la opción por defecto |
| **Importado** | Certificado propio o de un tercero, subido a ACM |
| **Desde IAM** | Opción heredada, todavía presente en el formulario del listener |

### Configuración del listener HTTPS

- Hay que especificar un **certificado por defecto**, obligatorio. Es el que se usa si el cliente
  no manda SNI o si ningún certificado de la lista coincide.
- Se puede añadir una **lista opcional de certificados** para servir varios dominios.
- Los clientes usan **SNI** para indicar a qué hostname quieren llegar.
- Se elige una **security policy**, que fija qué versiones y cifrados de SSL/TLS se aceptan. Sirve
  para dar soporte a clientes antiguos (*legacy clients*).

### SNI (Server Name Indication)

Resuelve el problema de cargar **varios certificados SSL en un mismo servidor web** para servir
varios sitios.

El cliente indica el **hostname de destino dentro del ClientHello del handshake TLS**, antes de
que exista ninguna petición HTTP y antes de que la conexión esté cifrada. El servidor busca el
certificado que corresponde a ese hostname y, si no encuentra ninguno, devuelve el certificado
por defecto.

Detalle de capa que conviene no mezclar: SNI viaja en la **capa TLS**, no en la capa HTTP. Lo que
manda el cliente es solo el dominio, sin ruta ni parámetros.

| Load balancer | Certificados SSL |
|---|---|
| **CLB** (v1) | **Uno solo**. Para varios hostnames con varios certificados hacen falta varios CLB |
| **ALB** (v2) | **Varios listeners con varios certificados**, mediante SNI |
| **NLB** (v2) | **Varios listeners con varios certificados**, mediante SNI |

SNI funciona en **ALB, NLB y CloudFront**. **No funciona en CLB**, que es de la generación
anterior.

### ACM frente a Let's Encrypt

| | Let's Encrypt (Certbot / panel) | ACM |
|---|---|---|
| Validación por DNS | Registro **TXT** | Registro **CNAME** |
| Caducidad | 90 días | — |
| Renovación | Hay que renovar (cron, o lo gestiona el panel) | **Automática y sin corte** |
| Condición para renovar | — | Que el certificado esté **en uso** por un recurso integrado |
| Dónde vive el certificado | En el servidor web | En ACM, asociado al balanceador |

La diferencia real no es el método de validación, sino que ACM se encarga de la renovación. El
matiz de examen: un certificado de ACM que **no está asociado a ningún recurso no se renueva
solo**.

### Coste

Los certificados **públicos de ACM son gratuitos** si se usan en un recurso integrado de AWS
(ALB, CloudFront, API Gateway). Lo que cuesta dinero es **ACM Private CA**, para PKI interna, que
no interviene aquí.

---

## Práctica de SSL: por qué no se completa

La práctica del curso monta el listener HTTPS:443 sobre el ALB ya existente, con el target group
`demo-tg-alb` y la security policy recomendada, pero **se cancela antes de guardar**.

El motivo está en el propio formulario: el desplegable **Certificate (from ACM)** aparece vacío.
Un listener HTTPS **exige un certificado por defecto** y no deja continuar sin él. Para pedir un
certificado público en ACM hace falta **un dominio propio y validarlo**, así que sin dominio la
práctica no se puede terminar.

Alternativas si se quisiera ver el HTTPS funcionando:

- **Import certificate**: subir a ACM un certificado autofirmado generado con `openssl`. El
  navegador avisa de que no es de confianza, pero el listener se crea y el handshake TLS es real.
- Validar un dominio propio **en el DNS que sea**: ACM no obliga a usar Route 53. Basta con
  añadir el CNAME de validación donde esté alojada la zona.

> Lo aprovechable de montar el entorno igualmente: queda comprobado de primera mano que el
> bloqueo es la falta de dominio, no un tema de coste.

---

## Deregistration Delay (Connection Draining)

Es el tiempo que el balanceador **espera a que terminen las peticiones en curso** (*in-flight
requests*) cuando un destino se está dando de baja o está *unhealthy*.

| Nombre de la funcionalidad | Balanceador |
|---|---|
| **Connection Draining** | CLB |
| **Deregistration Delay** | **ALB y NLB** |

Como el CLB está deprecated, el nombre que se usa siempre es **Deregistration Delay**.

Cómo funciona:

- Deja de mandar **peticiones nuevas** al destino que se está dando de baja.
- Espera a que las conexiones ya abiertas terminen su trabajo.
- Rango: **de 1 a 3600 segundos**, con **300 segundos por defecto**.
- Se puede **desactivar poniéndolo a 0**.
- Conviene un valor **bajo** si las peticiones son cortas.

No es que el balanceador reparta nada distinto: lo que hace es **proteger las peticiones ya en
curso** cuando una instancia se va, ya sea por baja manual, por fallar los health checks o porque
un Auto Scaling Group la retira en un *scale-in*. Sin este margen, esas conexiones se cortarían
en seco a mitad de petición.

---

## Health Checks

### Estados de un destino

| Estado | Qué significa |
|---|---|
| **Initial** | Se está registrando el destino |
| **Healthy** | Pasa los chequeos |
| **Unhealthy** | Falla los chequeos |
| **Unused** | El destino no está registrado |
| **Draining** | Se está dando de baja el destino |
| **Unavailable** | Los health checks están desactivados |

### Parámetros

| Ajuste | Valor por defecto | Qué hace |
|---|---|---|
| `HealthCheckProtocol` | HTTP | Protocolo del chequeo (HTTP o HTTPS) |
| `HealthCheckPort` | 80 | Puerto del chequeo |
| `HealthCheckPath` | `/` | **Ruta de destino, configurable** |
| `HealthCheckTimeoutSeconds` | 5 | Se da por fallado si no responde en ese tiempo |
| `HealthCheckIntervalSeconds` | 30 | Cada cuánto se lanza el chequeo |
| `HealthyThresholdCount` | 3 | Chequeos correctos seguidos para marcarlo *healthy* |
| `UnhealthyThresholdCount` | 5 | Chequeos fallidos seguidos para marcarlo *unhealthy* |

El **intervalo tiene que ser mayor o igual que el timeout**: si no, se lanzaría el chequeo
siguiente antes de que terminase el anterior.

### Ruta personalizada

La ruta del health check **no tiene que ser la raíz**. Se puede apuntar a un endpoint propio
(`/health`, `/testhealth`) y hay dos motivos para hacerlo:

- Evitar que el chequeo pegue contra una raíz pesada. En tiendas PrestaShop es fácil encontrar un
  index que carga catálogo e imágenes sin optimizar.
- Tener un endpoint **dedicado** que compruebe las dependencias reales (base de datos, caché) y
  devuelva un 200 ligero, desacoplado del contenido de negocio.

### Cuando todos los destinos están unhealthy

Si un target group **solo contiene destinos unhealthy**, el ELB enruta las peticiones **entre
esos destinos unhealthy** de todos modos.

La diapositiva lo llama explícitamente un escenario de **best effort**: el balanceador no
garantiza que la petición vaya a funcionar, simplemente prefiere intentarlo con algo antes que
devolver un error a todos los usuarios. Es el último recurso, no una garantía de servicio. El
caso típico es que la configuración del propio health check esté mal y en realidad la aplicación
funcione.

---

## Monitorización y troubleshooting del ELB

Todas las métricas del load balancer se publican **directamente en CloudWatch**.

### Códigos de error y qué mirar

| Código | Significado | Dónde mirar |
|---|---|---|
| **HTTP 400** Bad Request | El cliente mandó una petición malformada que no cumple la especificación HTTP | — |
| **HTTP 503** Service Unavailable | **No hay destinos sanos** en alguna de las AZs en las que el balanceador está configurado para responder | `HealthyHostCount` en CloudWatch |
| **HTTP 504** Gateway Timeout | Expiró el tiempo de espera | Revisar el **keep-alive** de las instancias: su timeout tiene que ser **mayor** que el *idle timeout* del balanceador |

El 503 no es "una instancia que tarda en arrancar": es que **faltan destinos sanos donde
enrutar**. Una instancia que responde tarde daría más bien un 504.

### Métricas: la nomenclatura del curso está heredada del CLB

La diapositiva de monitorización dibuja un **ALB**, pero lista las métricas con los nombres
antiguos del **CLB**. Los nombres reales que aparecen hoy en CloudWatch para un ALB son otros:

| En la diapositiva (CLB) | Nombre real en ALB |
|---|---|
| `BackendConnectionErrors` | `TargetConnectionErrorCount` |
| `HTTPCode_Backend_2XX` / `3XX` / `4XX` / `5XX` | `HTTPCode_Target_2XX_Count` / `_3XX_Count` / `_4XX_Count` / `_5XX_Count` |
| `HTTPCode_ELB_4XX` / `HTTPCode_ELB_5XX` | `HTTPCode_ELB_4XX_Count` / `HTTPCode_ELB_5XX_Count` (con sufijo `_Count`) |
| `Latency` | `TargetResponseTime` |
| `SurgeQueueLength` / `SpilloverCount` | **No existen en ALB** |

`RequestCount`, `RequestCountPerTarget`, `HealthyHostCount` y `UnHealthyHostCount` se llaman
igual en ambos.

Qué mide cada una:

| Métrica | Qué indica |
|---|---|
| `HealthyHostCount` / `UnHealthyHostCount` | Destinos sanos y no sanos. Es la métrica del 503 |
| `HTTPCode_ELB_4XX_Count` | Errores de cliente **generados por el balanceador** |
| `HTTPCode_ELB_5XX_Count` | Errores de servidor **generados por el balanceador**, no por los destinos |
| `HTTPCode_Target_XXX_Count` | Códigos generados por **los destinos**. No incluye los del balanceador |
| `RequestCount` | Peticiones totales |
| `RequestCountPerTarget` | **Media de peticiones por destino**. Buena señal de si toca escalar, y es la métrica que se usa como objetivo en las políticas de *target tracking* del ASG |
| `TargetResponseTime` | Tiempo de respuesta de los destinos |

### SurgeQueueLength y SpilloverCount: solo CLB

Las dos aparecen en la diapositiva, pero son **exclusivas del Classic Load Balancer**:

- **`SurgeQueueLength`**: número total de peticiones (listener HTTP) o conexiones (listener TCP)
  pendientes de ruta hacia una instancia sana. El **máximo de la cola es 1024**. Cuanto más cerca
  de 0, mejor.
- **`SpilloverCount`**: peticiones **rechazadas por tener la cola llena**.

El ALB no encola peticiones de esa forma, así que estas dos métricas no existen ahí. Para saber
si hay que escalar en un ALB, lo que se mira es `RequestCountPerTarget` y `TargetResponseTime`.

Lo importante, en cualquier caso: **poner alarmas**, no mirar gráficas a mano.

### Access Logs

- Registran **todas las peticiones** que pasan por el balanceador.
- Se almacenan en **S3**, cifrados.
- Solo se paga el **almacenamiento de S3**, no la funcionalidad.

### Request Tracing

El balanceador añade la cabecera **`X-Amzn-Trace-Id`** a cada petición, lo que permite correlar
una misma petición entre los logs del balanceador y los de la aplicación.

---

## Atributos del target group

### Slow Start Mode

Cuando se registra un destino **nuevo** en el target group, se le va aumentando la proporción de
tráfico **de forma gradual** durante un periodo de calentamiento configurable, en lugar de darle
su cuota completa desde el primer segundo.

Sirve para que una instancia recién arrancada (por ejemplo, la que acaba de lanzar un ASG en un
*scale-out*) tenga tiempo de calentar cachés y conexiones antes de recibir su parte entera. El
resto de destinos siguen recibiendo tráfico con normalidad mientras tanto.

### Algoritmos de enrutamiento

| Algoritmo | Dónde aplica | Cómo reparte |
|---|---|---|
| **Round Robin** | ALB (HTTP/HTTPS) — es el **por defecto**. También CLB con listener TCP | Por orden, uno detrás de otro, y vuelta a empezar |
| **Least Outstanding Requests** | ALB (HTTP/HTTPS) y CLB (HTTP/HTTPS) | Manda cada petición nueva al destino con **menos peticiones en curso** |
| **Flow Hash** | **NLB** | Calcula un hash de la conexión y lo usa para elegir destino |
| **Weighted Random** | ALB | Reparto aleatorio ponderado. **Incompatible con stickiness** |

**Least Outstanding Requests**: útil cuando las peticiones no cuestan lo mismo o los destinos no
tienen la misma capacidad. Si una instancia termina antes que otra, la siguiente petición se va a
la que está más libre, en vez de respetar el turno.

**Round Robin en ALB y en CLB no es lo mismo.** El ALB **nunca tiene listeners TCP**: solo
HTTP, HTTPS, WebSocket y HTTP/2. Cuando el curso agrupa "ALB y CLB (TCP)" se refiere a dos
contextos distintos: Round Robin es el algoritmo por defecto del ALB en sus listeners
HTTP/HTTPS, y por separado es el que usa el CLB en sus listeners TCP.

**Flow Hash (solo NLB)**: selecciona destino a partir de un hash calculado sobre el **protocolo,
la IP de origen y destino, el puerto de origen y destino y el número de secuencia TCP**. Cada
conexión TCP/UDP se enruta a **un único destino durante toda la vida de la conexión**.

> El hash que aparece en el diagrama (`8743b…`) **no es tráfico cifrado del usuario**: es el
> resultado de la función hash sobre esos campos de la conexión. Es un mecanismo determinista de
> reparto, en la misma línea que el hash por IP de origen de las sticky sessions del NLB, pero con
> más campos de entrada.

---

## ALB Rules: a fondo

Complementa la [práctica de reglas del listener](#reglas-del-listener) hecha con `DemoRule`.

- Las reglas se procesan **en orden**, y la regla `Default` va siempre la última. Con muchas
  reglas, que una no se cumpla suele ser un problema de orden, no de condición.
- Acciones soportadas: **forward**, **redirect** y **fixed-response**.

### Condiciones disponibles

| Condición | Sobre qué decide |
|---|---|
| `host-header` | La cabecera `Host` (el hostname pedido) |
| `http-request-method` | GET, POST, PUT… |
| `path-pattern` | La ruta de la URL |
| `source-ip` | La IP de origen del cliente |
| `http-header` | Cualquier cabecera HTTP |
| `query-string` | Los parámetros de la query |

### Target Group Weighting

Una **misma regla** puede repartir tráfico entre **varios target groups**, cada uno con su
**peso**.

| Target Group | Peso | Tráfico |
|---|---|---|
| Target Group 1 (Blue) | 8 | 80 % |
| Target Group 2 (Green) | 2 | 20 % |

El caso de uso típico es el **despliegue blue/green** o convivir con varias versiones de la
aplicación, controlando qué fracción de usuarios reales va a la versión nueva **sin tocar el DNS
ni montar un segundo ALB**.

Conviene no quedarse con la idea del primer diagrama (una regla → un target group): ese es el
caso simple, no una restricción. El mecanismo ya aparecía en el formulario de creación del
listener, con el botón **Add target group** y los campos **Weight** y **Percent**, aunque en su
momento no se relacionara con este concepto.

---

## Resumen para el examen

| Concepto | Clave |
|---|---|
| Escalado vertical | Instancia más grande. Bases de datos. Límite de hardware. En EC2 exige stop/start |
| Escalado horizontal | Más instancias (= elasticidad). Aplicaciones web. ASG + load balancer |
| Requisito del escalado horizontal | Instancias sin estado local |
| S3 / EFS / EBS | Objetos por API / NFS compartido multi-AZ / disco de una AZ |
| Alta disponibilidad | Al menos **dos AZs**. Sobrevivir a la pérdida de un centro de datos |
| HA pasiva vs activa | Standby (RDS Multi-AZ) vs todos sirviendo (escalado horizontal) |
| Escalabilidad ≠ HA | Diez instancias en una AZ escalan pero no son HA |
| HA vs DR | Multi-AZ vs multi-región |
| Pico previsible | Scheduled scaling por adelantado; target tracking para lo imprevisto |
| ASG que no lanza instancias | Revisar la cuota de vCPUs On-Demand de la región (Service Quotas) |
| Load balancer | Reparte peticiones o conexiones. DNS único, health checks, SSL, stickiness, multi-AZ |
| ELB gestionado | AWS se encarga de mantenimiento y HA. Pocos parámetros |
| Alcance de un ELB | **Regional**: entre AZs. Entre regiones, Route 53 o Global Accelerator |
| RDS y S3 | No van detrás de un ELB. Endpoints propios |
| Destinos vs integraciones | EC2, ASG, ECS reciben tráfico. ACM, CloudWatch, Route 53, WAF colaboran |
| CLB | v1, 2009. Deprecated y fuera del examen |
| ALB | v2, 2016. Capa 7: HTTP, HTTPS, WebSocket, HTTP/2 |
| NLB | v2, 2017. Capa 4: TCP, TLS, UDP |
| GWLB | 2020. Capa 3, protocolo IP. Appliances de red de terceros |
| Migrar un CLB | HTTP/HTTPS → ALB. TCP/UDP/TLS o IP fija → NLB |
| Internal vs external | Privado vs de cara a internet |
| Varias aplicaciones | Un ALB con varios target groups. Con CLB, uno por aplicación |
| Contenedores en ECS | Port mapping a puertos dinámicos |
| Reglas de enrutamiento | Ruta, hostname (cabecera `Host`), query string, cabeceras |
| Target groups | EC2 (o ASG), tareas ECS, Lambda (evento JSON), IPs **privadas** |
| Health checks | **A nivel de target group** |
| Destinos on-premises | Por IP privada, con VPN o Direct Connect |
| Dirección del ALB | **Hostname fijo, no IP fija**. IP fija → NLB |
| IP del cliente | `X-Forwarded-For` (más `X-Forwarded-Port` y `X-Forwarded-Proto`) |
| ALB y Availability Zones | Exige **al menos dos AZs** en el network mapping |
| Unused vs Unhealthy | Destino parado/terminado vs destino corriendo que falla el health check |
| Cadena de security groups | El SG de las instancias permite el puerto **con origen el SG del ALB**, no un CIDR |
| Timeout vs connection refused | El SG descarta en silencio (timeout); sin servicio escuchando hay refused inmediato |
| Prioridad de reglas | Se evalúan de menor a mayor. La regla `Default` siempre va la última |
| Acciones de una regla | Forward to target group, Redirect to URL, **Return fixed response** |
| Return fixed response | La genera el propio ALB. Páginas de mantenimiento sin tocar el backend |
| Coste del ALB | **Por hora solo por existir**, haya tráfico o no |
| Orden de borrado | ALB → target group → security group. El target group tarda en liberarse (borrado asíncrono) |
| NLB | Capa 4: TCP y UDP. Millones de peticiones por segundo, latencia ultra baja |
| IP del NLB | **Una IP estática por AZ**. Admite Elastic IP |
| Whitelisting por IP | NLB. El ALB solo da hostname |
| Destinos del NLB | EC2, IPs **privadas** y **ALB** |
| Health checks del NLB | TCP, HTTP y HTTPS |
| Protocolo del target group del NLB | Capa 4 (TCP, UDP, TLS…), nunca HTTP |
| IP fija + reglas HTTP | NLB delante de un ALB |
| Security groups en el NLB | Solo si se asocian al crearlo |
| Unidad de reparto | ALB: cada petición HTTP. NLB: cada conexión TCP |
| Borrar un SG referenciado | No se puede: quitar antes la regla que lo referencia |
| GWLB, capa | 3 (paquetes IP) |
| GWLB, protocolo hacia el appliance | GENEVE, puerto 6081 |
| Appliances del GWLB | Productos de terceros ya compatibles con GENEVE, no `iptables` casero |
| Sticky sessions, dónde funciona | CLB, ALB y NLB |
| Cookie `AWSALB`/`AWSELB` (duration-based) | 7 días fijos, no configurable |
| Cookie reservada, no usar | `AWSALB`, `AWSALBAPP`, `AWSALBTG` |
| Sticky sessions en NLB | Por IP de origen (hash), no por cookie |
| Stickiness incompatible con | Cross-zone apagado, y con el algoritmo Weighted random |
| Cross-zone por defecto | ALB: On (target group puede apagarlo). NLB/GWLB: Off. CLB: Off |
| Cross-zone, coste inter-AZ | Solo en NLB/GWLB si se activa |
| Cross-zone apagado en ALB | No se puede a nivel de balanceador, sí a nivel de target group |
| Certificado del load balancer | **X.509**. Desde ACM, importado, o desde IAM |
| Listener HTTPS | **Certificado por defecto obligatorio** + lista opcional para varios dominios |
| Security policy | Define versiones y cifrados de SSL/TLS aceptados. Para clientes antiguos |
| SNI | El cliente indica el hostname **en el ClientHello del handshake TLS**, capa TLS, no HTTP |
| SNI, dónde funciona | **ALB, NLB y CloudFront**. **No en CLB** |
| Certificados por balanceador | CLB: **uno solo**. ALB y NLB: varios, con SNI |
| ACM, renovación | **Automática**, pero solo si el certificado **está en uso** por un recurso |
| Coste de ACM | Certificados públicos **gratis**. Lo que se paga es **ACM Private CA** |
| Práctica de SSL | No se completa: sin dominio propio validado no hay certificado en ACM |
| Connection Draining vs Deregistration Delay | Mismo concepto: CLB vs **ALB y NLB** |
| Deregistration Delay | **1 a 3600 s, por defecto 300**. Se desactiva con 0. Bajo si las peticiones son cortas |
| Qué protege el draining | Las peticiones **ya en curso** cuando un destino se da de baja o falla |
| Estados del destino | Initial, Healthy, Unhealthy, Unused, Draining, **Unavailable** (checks desactivados) |
| Health check, valores por defecto | Intervalo 30 s, timeout 5 s, healthy 3, unhealthy 5, path `/` |
| Intervalo y timeout | El **intervalo ≥ timeout**, o se solaparían los chequeos |
| Ruta del health check | **Configurable**. Mejor un endpoint dedicado y ligero que la raíz |
| Target group todo unhealthy | El ELB enruta **entre los unhealthy** de todos modos. Escenario **best effort** |
| HTTP 400 | Petición malformada del cliente |
| HTTP 503 | **Sin destinos sanos** en alguna AZ configurada. Mirar `HealthyHostCount` |
| HTTP 504 | Timeout. El **keep-alive** de la instancia debe superar el *idle timeout* del balanceador |
| Nomenclatura de métricas | La diapositiva usa nombres de CLB. En ALB son `HTTPCode_Target_XXX_Count`, `TargetConnectionErrorCount`, `TargetResponseTime` |
| `RequestCountPerTarget` | Media de peticiones por destino. Señal para escalar y objetivo de *target tracking* |
| `SurgeQueueLength` / `SpilloverCount` | **Solo CLB**. Cola máxima 1024; el spillover son las rechazadas por cola llena |
| Access Logs | En **S3**, cifrados. Solo se paga el almacenamiento |
| Request Tracing | Cabecera **`X-Amzn-Trace-Id`** |
| Slow Start Mode | Sube el tráfico **gradualmente** a un destino **recién registrado** |
| Round Robin | **Por defecto en ALB** (HTTP/HTTPS). También CLB con listener TCP. El ALB no tiene listeners TCP |
| Least Outstanding Requests | ALB y CLB (HTTP/HTTPS). Al destino con **menos peticiones en curso** |
| Flow Hash | **Solo NLB**. Hash de protocolo, IPs, puertos y número de secuencia TCP |
| Duración del Flow Hash | La conexión TCP/UDP entera va **al mismo destino** |
| Condiciones de regla del ALB | `host-header`, `http-request-method`, `path-pattern`, `source-ip`, `http-header`, `query-string` |
| Target Group Weighting | **Una regla, varios target groups con pesos**. Blue/green sin tocar DNS |
