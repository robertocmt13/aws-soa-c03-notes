# EC2 Monitoring — CloudWatch Agent y métricas no incluidas

## El problema: qué no ve CloudWatch por defecto

EC2 publica automáticamente en CloudWatch un conjunto de métricas sin que haya
que instalar nada:

- **CPU** — utilización, créditos (en instancias burstable tipo `t3`)
- **Red** — entrada y salida
- **Disco** — lectura/escritura, **solo para instance store**, no para EBS
- **Status checks** — los tres, detallados más abajo

Lo que **no** publica:

- **RAM**
- **Espacio real ocupado en disco** (el porcentaje de disco lleno de un volumen EBS)
- **Procesos individuales**

El motivo no es arbitrario. CPU, red y disco son métricas que el hipervisor de AWS
puede medir desde fuera, sin entrar en la instancia. La memoria que consume un
proceso concreto solo la conoce el sistema operativo que corre dentro, y AWS no
mira ahí por defecto.

Para exponer esas métricas hay que instalar el **Unified CloudWatch Agent** dentro
de la instancia. Ver [`cloudwatch-agent-install.sh`](./cloudwatch-agent-install.sh).

## Frecuencia de recogida

| Modo | Intervalo | Coste |
|---|---|---|
| Basic Monitoring | 5 minutos | Incluido |
| Detailed Monitoring | 1 minuto | De pago |

## Los tres status checks

Cada uno vigila una capa distinta, y de eso depende **qué acción corrige el fallo**.
Este es un escenario típico de examen.

| Check | Qué vigila | Acción correctiva |
|---|---|---|
| **System status** | Hardware físico de AWS: host, red, alimentación | **Stop/Start** — mueve la instancia a otro hardware |
| **Instance status** | El sistema operativo dentro de la instancia | **Reboot** — el hardware está sano |
| **Attached EBS status** | Los volúmenes EBS conectados | Depende del problema de I/O |

El punto importante: si falla el **system status**, reiniciar no sirve de nada,
porque la instancia vuelve a arrancar en el mismo hardware defectuoso. Hace falta
un Stop/Start para que AWS la reubique.

Se puede automatizar la reacción con una alarma de CloudWatch, sin intervención
manual.

## El plugin procstat

`procstat` no es un programa aparte: es un plugin **dentro** del mismo agente, que
se activa en el JSON de configuración. La relación es la misma que entre Apache y
sus módulos.

La diferencia con las métricas generales es el nivel de detalle:

- Métricas generales (`mem`, `disk`) → "el servidor está al 90% de RAM"
- `procstat` → "**mysqld** es el que se está comiendo esa RAM"

Formas de identificar el proceso a vigilar:

| Selector | Cómo identifica el proceso |
|---|---|
| `pid_file` | Por el fichero PID que crea el proceso |
| `exe` | Por el nombre del proceso (acepta regex) |
| `pattern` | Por la línea de comandos con la que se lanzó (acepta regex) |

Las métricas generadas llevan el prefijo `procstat_` (`procstat_cpu_usage`,
`procstat_memory_rss`...), lo que las distingue del resto en CloudWatch.

Ejemplo de bloque en el JSON de configuración:

```json
{
  "metrics": {
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"] },
      "procstat": [
        {
          "exe": "mysqld",
          "measurement": ["cpu_usage", "memory_rss"]
        }
      ]
    }
  }
}
```

## Coste: el detalle que se pasa por alto

Instalar el agente es gratuito. Lo que se factura son las **métricas personalizadas**
que publica.

- Las primeras **10 custom metrics son gratis de forma permanente** (no es un free
  tier de 12 meses que caduque).
- A partir de ahí, 0,30 USD por métrica y mes en el primer tramo.
- El cargo se prorratea por hora y solo se aplica en las horas en las que
  efectivamente se envían métricas.

**El matiz que dispara el coste sin avisar:** CloudWatch trata **cada combinación
distinta de dimensiones como una métrica independiente**, aunque el nombre de la
métrica sea el mismo. Vigilar `mysqld` y `apache2` con CPU y memoria cada uno no
son 2 métricas, son 4. Y eso se multiplica por cada instancia.

Con varias instancias y varios procesos vigilados se superan las 10 gratuitas
rápidamente. La conclusión práctica es la misma que con cualquier sistema de
monitorización: no se monitoriza todo porque se pueda, se monitoriza lo que
realmente hace falta diagnosticar.

## Nota de laboratorio

Al terminar las pruebas, además de terminar la instancia conviene revisar:

- **EC2 → Volumes** — que no queden volúmenes en estado `available`
- **Systems Manager → Parameter Store** — el asistente crea un parámetro con la
  configuración del agente
- **CloudWatch → Metrics** — el namespace `CWAgent` queda visible un tiempo, pero
  no genera coste si ya no entran datos nuevos; expira solo
