# EC2 Status Checks y recuperación automática

Los *status checks* son comprobaciones automáticas que EC2 ejecuta **cada minuto**
sobre cada instancia. Publican su resultado en CloudWatch, pero por sí solos no
avisan de nada: son un semáforo que hay que mirar. Para reaccionar hace falta
montar una alarma encima.

## Los tres checks

Cada uno vigila una capa distinta, y de eso depende **qué acción corrige el fallo**.

| Check | Qué vigila | Ejemplos de causa | Resolución |
|---|---|---|---|
| **System status** | Hardware físico de AWS: el host, su red, su alimentación | Fallo de hardware, pérdida de alimentación del host | **Stop/Start** — migra la instancia a otro host |
| **Instance status** | Configuración de software y red **dentro** de la instancia | Configuración de red inválida, memoria agotada, kernel que no arranca | **Reboot** o corregir la configuración |
| **Attached EBS status** | Los volúmenes EBS conectados (alcanzables y con I/O completo) | Problemas de I/O con el volumen | Reboot o reemplazar el volumen afectado |

El punto que suele preguntarse: **si falla el system status, un reboot no sirve de
nada**, porque la instancia vuelve a arrancar en el mismo hardware defectuoso.
Hace falta un Stop/Start para que AWS la reubique en otro host.

### Personal Health Dashboard

Distinto de los status checks. Estos indican si hay un problema **ahora**; el
Personal Health Dashboard informa de **mantenimientos programados por AWS** que
afectarán a la instancia en el futuro. Información planificada, no reactiva.

## Reboot vs Stop/Start

Diferencia con consecuencias prácticas, no solo teóricas:

| | Reboot | Stop/Start |
|---|---|---|
| Cambia de host físico | No | **Sí** |
| IP pública auto-asignada | Se mantiene | **Cambia** |
| IP privada | Se mantiene | Se mantiene |
| Datos en **instance store** | Se mantienen | **Se pierden** |
| Datos en **EBS** | Se mantienen | Se mantienen |

Si la IP pública tiene que ser estable a través de un Stop/Start, hay que asociar
una **Elastic IP**. Aviso de coste: una Elastic IP asociada a una instancia en
marcha es gratuita, pero reservada sin asociar (o asociada a una instancia parada)
se factura a ~0,005 USD/hora, en torno a 3,6 USD/mes.

## Métricas en CloudWatch

Publicadas con intervalo de **1 minuto**:

- `StatusCheckFailed_System`
- `StatusCheckFailed_Instance`
- `StatusCheckFailed_AttachedEBS`
- `StatusCheckFailed` — cualquiera de las anteriores

## Dos formas de automatizar la recuperación

### Opción 1 — CloudWatch Alarm con acción `recover`

AWS migra la instancia a hardware sano **conservando su identidad completa**:
misma IP privada, misma IP pública, misma Elastic IP, metadatos y placement group.

Es más que un reboot: resuelve el fallo de hardware sin las consecuencias de un
Stop/Start manual (perder la IP pública auto-asignada).

Puede combinarse con una notificación vía **SNS**.

**Restricción importante:** la acción `recover` solo aplica a
`StatusCheckFailed_System`. Tiene sentido — recuperar significa "muévela a otro
host", y eso solo arregla fallos de hardware.

### Opción 2 — Auto Scaling Group con min/max/desired = 1

Aquí no se recupera nada: la instancia se **termina y se lanza una nueva desde
cero**. Por tanto **no conserva** ni la IP privada ni la Elastic IP, ni nada que
estuviera en disco local.

### Cuál elegir

- **Opción 1** cuando importa **esa instancia en concreto**: tiene estado, tiene
  una IP a la que apunta algo, es un servidor con identidad.
- **Opción 2** cuando la instancia es **desechable e intercambiable**: un servidor
  web sin estado detrás de un balanceador, donde da igual si es esta o la
  siguiente.

Es la misma distinción que aparece en placement groups: recursos con identidad
frente a recursos intercambiables.

## ARNs de las acciones nativas de EC2

Las alarmas pueden ejecutar acciones de EC2 directamente, con este formato:

```
arn:aws:automate:<region>:ec2:recover
arn:aws:automate:<region>:ec2:reboot
arn:aws:automate:<region>:ec2:stop
arn:aws:automate:<region>:ec2:terminate
```

## Prueba de la alarma

**No se puede provocar un fallo real de `StatusCheckFailed_System`**: eso
implicaría romper el hardware físico de AWS. Para verificar que la cadena
completa funciona, se fuerza el estado de la alarma desde la CLI:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "<nombre-de-la-alarma>" \
  --state-value ALARM \
  --state-reason "Testing recovery action"
```

Ejecutable desde **CloudShell**, sin necesidad de configurar credenciales locales.

En el historial de la alarma (pestaña **History**) debe aparecer una entrada de
tipo `Action` confirmando la ejecución:

```
Successfully executed action arn:aws:automate:eu-north-1:ec2:recover
```

Como el estado se forzó artificialmente y el hardware está sano, la alarma vuelve
sola a `OK` en el siguiente datapoint. Es el comportamiento esperado.

### Cómo verificar que `recover` conserva la identidad

Antes de lanzar la prueba, anotar la **IP pública** y la **IP privada** de la
instancia. Tras la recuperación, ambas deben ser las mismas. Esa es la diferencia
observable frente a un Stop/Start manual.

## Nota de laboratorio

Al terminar: terminar la instancia, borrar la alarma y comprobar que no quedan
volúmenes EBS en estado `available`.
