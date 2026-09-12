# 06 — EC2 High Availability and Scalability

Notas de la Sección 6 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 50 a 60 completadas: escalabilidad, alta disponibilidad,
> Elastic Load Balancing, Application Load Balancer y Network Load Balancer (teoría y práctica),
> Gateway Load Balancer, Sticky Sessions y Cross-Zone Load Balancing (teoría).

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
