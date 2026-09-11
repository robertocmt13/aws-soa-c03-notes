# 06 — EC2 High Availability and Scalability

Notas de la Sección 6 del curso de AWS Certified CloudOps Engineer Associate (SOA-C03).

> Sección en curso. Lecciones 50 a 55 completadas: escalabilidad, alta disponibilidad,
> Elastic Load Balancing y Application Load Balancer (teoría y práctica).

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

## Limpieza de la práctica

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
