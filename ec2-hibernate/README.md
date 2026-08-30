# EC2 Hibernate

Tercera alternativa junto a *reboot* y *stop/start*, con una diferencia clave:
**conserva el estado de la memoria RAM**.

## Cómo funciona

Al hibernar, el contenido de la RAM se escribe en un fichero dentro del **volumen
raíz EBS** y la instancia se apaga. Al arrancarla de nuevo, ese volcado se
restaura y la instancia continúa exactamente donde estaba.

El sistema operativo **no se detiene ni se reinicia**: no arranca el kernel, no se
levantan los servicios, no se reinicializa nada. De ahí que el arranque sea mucho
más rápido.

Es el mismo mecanismo que la hibernación de un portátil, donde la RAM se vuelca a
la partición swap. La diferencia es que EC2 no usa swap, sino un fichero en el
volumen raíz, que además debe estar cifrado.

## Requisitos

Todos son obligatorios; si alguno falta, la opción no está disponible o la
hibernación falla:

| Requisito | Detalle |
|---|---|
| **Familias soportadas** | C3, C4, C5, I3, M3, M4, R3, R4, T2, T3... |
| **RAM** | Menos de **150 GB** |
| **Tipo de instancia** | No soportado en instancias **bare metal** |
| **AMI** | Amazon Linux 2, Linux AMI, Ubuntu, RHEL, CentOS, Windows... |
| **Volumen raíz** | Debe ser **EBS**, **cifrado**, no instance store, y con espacio suficiente |
| **Duración máxima** | No puede permanecer hibernada más de **60 días** |

El volumen raíz debe tener capacidad para el sistema operativo **más** el volcado
completo de la RAM. La consola avisa de ello al activar la opción.

El cifrado es obligatorio por un motivo evidente: en la RAM puede haber
credenciales, tokens de sesión o datos sensibles que pasan a quedar escritos en
disco.

## Configuración al lanzar la instancia

Dos ajustes en sitios distintos del formulario:

1. **Advanced details → Stop - Hibernate behavior** → `Enable`
2. **Storage (volumes) → Advanced** → `Encrypted`, seleccionando una KMS key
   (sirve la de por defecto, `alias/aws/ebs`)

## Casos de uso

- Procesos de larga duración que no conviene reiniciar desde cero
- Conservar el estado de la memoria entre sesiones
- **Servicios que tardan en inicializarse**: aplicaciones que precargan cachés o
  levantan un contexto pesado al arrancar. Con stop/start ese coste se paga en
  cada arranque; con hibernate, la caché sigue caliente al volver

## Opciones de compra

Disponible para instancias **On-Demand, Reserved y Spot**.

El caso de Spot merece explicación. Las instancias Spot usan capacidad ociosa de
AWS con grandes descuentos, a cambio de que AWS pueda reclamarlas en cualquier
momento avisando con 2 minutos. El comportamiento ante esa interrupción es
configurable: `terminate` (por defecto), `stop` o `hibernate`.

Con `hibernate`, la instancia conserva el estado de memoria y, cuando vuelve a
haber capacidad, retoma el trabajo donde lo dejó en lugar de empezar de cero. Esto
hace viable usar Spot para cargas largas, no solo para trabajos cortos y
relanzables.

## Comparativa con reboot y stop/start

| | Reboot | Stop/Start | Hibernate |
|---|---|---|---|
| Estado de la RAM | Se pierde | Se pierde | **Se conserva** |
| Cambia de host físico | No | Sí | **No** |
| IP pública auto-asignada | Se mantiene | Cambia | Cambia |
| IP privada | Se mantiene | Se mantiene | Se mantiene |
| Datos en **instance store** | Se mantienen | Se pierden | **Se pierden** |
| Datos en **EBS** | Se mantienen | Se mantienen | Se mantienen |
| Velocidad de arranque | Normal | Normal | **Mucho más rápida** |

**Consecuencia importante:** al mantenerse en el mismo host físico, la hibernación
**no sirve para recuperarse de un fallo de hardware**. Para eso hace falta un
Stop/Start, que reubica la instancia en otro host.

## Verificación de la práctica

La forma más directa de comprobar que la RAM se conservó es el comando `uptime`
antes y después de hibernar:

```bash
uptime
```

El contador **continúa** en lugar de reiniciarse:

```
11:31:15 up 2 min,  1 user,  load average: 0.15, 0.13, 0.05    # antes de hibernar
11:33:22 up 4 min,  1 user,  load average: 0.27, 0.16, 0.07    # tras despertar
```

Con un stop/start convencional el contador volvería a `up 0 min`, porque el sistema
operativo habría arrancado desde cero.

En la misma prueba se confirma el comportamiento de las IPs: la pública cambia, la
privada se mantiene.

## Nota de laboratorio

Al terminar: terminar la instancia y comprobar que no queda ningún volumen EBS en
estado `available`.
