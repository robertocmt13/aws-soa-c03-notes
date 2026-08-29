# EC2 Placement Groups

Un *placement group* permite controlar **dónde coloca AWS físicamente** las
instancias dentro del datacenter. Por defecto esa decisión la toma AWS.

Para entender las tres estrategias hay que tener presente cómo está montado un
datacenter: una nave con **racks**, cada rack con decenas de servidores físicos y
un switch propio en la parte superior. Cuando se habla de "fallo de rack", se
habla de perder ese conjunto entero: alimentación, red y hardware compartidos.

## Las tres estrategias

Un placement group solo admite **una** estrategia, definida en el momento de
crearlo.

### Cluster — agrupar

Coloca las instancias en el mismo rack, dentro de una única AZ.

- **Se gana:** latencia mínima y ancho de banda alto entre instancias (hasta 10 Gbps)
- **Se pierde:** si cae el rack, caen todas a la vez
- **Cuándo:** cargas donde las instancias **se hablan más entre ellas que con el
  exterior** — HPC, Spark, entrenamiento distribuido, simulaciones MPI, trading de
  baja latencia

El caso típico es un job de Spark: durante el *shuffle*, los nodos se intercambian
volúmenes grandes de datos para reagrupar registros por clave, y la red se
convierte en el cuello de botella mientras la CPU espera. Concentrarlos en el mismo
rack puede reducir el tiempo de ejecución a la mitad.

Es asumible perder el rack porque la carga es efímera y se puede relanzar.

**Recomendación práctica:** lanzar todas las instancias de golpe y del mismo tipo,
o puede aparecer un `insufficient capacity error` al añadir más después.

### Spread — separar

Garantiza que cada instancia va a hardware físico distinto: rack, alimentación y
red separados.

- **Límite: 7 instancias por AZ** — esto es lo que define su caso de uso
- **Cuándo:** pocas instancias cuya caída **simultánea** es crítica

Ejemplos: controladores de dominio, los 3 nodos de un clúster con quórum (Vault,
etcd) donde perder la mayoría deja el servicio sellado, servidores de licencias.

No aporta nada si solo hay una instancia: no hay nada que repartir.

### Partition — repartir

Divide el grupo en particiones (hasta 7 por AZ). Cada partición es un conjunto de
racks aislado del resto. Dentro de una partición puede haber muchas instancias.

- **Cuándo:** sistemas distribuidos a gran escala que replican datos y son
  *rack-aware* — Hadoop/HDFS, Cassandra, Kafka

## Por qué partition para Cassandra o Kafka

Estos sistemas ya replican datos por su cuenta, pero esa replicación solo protege
si las réplicas **no comparten hardware físico**. Tres copias en el mismo rack son
tres copias que se pierden juntas.

AWS expone a cada instancia en qué partición está, consultable por metadata:

```bash
curl http://169.254.169.254/latest/meta-data/placement/partition-number
```

El software usa ese dato para colocar réplicas en particiones distintas:

- **Cassandra** — vía *snitch* (`Ec2Snitch`, `GossipingPropertyFileSnitch`) con
  `NetworkTopologyStrategy`
- **Kafka** — propiedad `broker.rack`, la asignación de réplicas es rack-aware
- **HDFS** — rack awareness mediante script de topología

### El punto clave: quién hace qué

**AWS no reparte datos.** Solo hace dos cosas:

1. Garantizar que instancias de particiones distintas no comparten hardware
2. Decirle a cada instancia en qué partición está

Quien decide dónde va cada réplica es **Cassandra o Kafka**. Si se crea el
partition placement group pero no se configura el snitch o `broker.rack`, no se
gana nada: el software seguirá colocando réplicas a ciegas.

Tampoco es equivalente a un RAID 5. RAID 5 usa paridad y reconstruye el dato
perdido; Cassandra y Kafka guardan copias completas y sirven desde otra réplica sin
reconstruir nada — más cercano conceptualmente a RAID 1. Y en RAID 5 la controladora
reparte los datos, mientras que aquí AWS solo reparte instancias.

Nota de vocabulario: la *partición* de un topic de Kafka o la *partition key* de
Cassandra son divisiones **lógicas de datos**, distintas de la partición del
placement group, que es una división **física de hardware**.

## Spread level

Al crear un spread placement group se pide un nivel:

| Nivel | Uso |
|---|---|
| **Rack (No restrictions)** | El habitual. Reparte entre racks físicos distintos |
| **Host (Outposts only)** | Solo para AWS Outposts (hardware de AWS en tu propio datacenter). Al haber un único rack, reparte entre hosts físicos dentro de él |

## Tabla de decisión

| Situación | Estrategia |
|---|---|
| Las instancias saturan la red hablando entre ellas | Cluster |
| Son pocas (≤7 por AZ) y su caída simultánea es crítica | Spread |
| Son muchas, replican datos y el software es rack-aware | Partition |
| Ninguna de las anteriores | Ninguna |

## Lo que suele olvidarse: la mayoría no necesita ninguno

Un Auto Scaling Group de servidores web sin estado repartido en tres AZ **no
necesita placement group**. Son instancias intercambiables, y el reparto entre AZ
ya aporta la tolerancia a fallos necesaria. Añadir un placement group solo
introduce restricciones de capacidad al escalar.

Y sobre prioridades: el reparto entre **zonas de disponibilidad** protege de un
fallo mayor que el reparto entre racks. Tres instancias en 3 AZ sin placement group
están mejor protegidas que tres en un spread placement group dentro de la misma AZ.
Lo bueno es que se combinan: un spread placement group puede abarcar varias AZ.

## Otros detalles

- Los placement groups **no tienen coste** por sí mismos
- Una instancia puede moverse entre grupos, pero debe estar **parada**
- No se pueden fusionar grupos, y una instancia solo pertenece a uno
