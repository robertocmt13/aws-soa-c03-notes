#!/bin/bash
#
# Instalación y configuración del Unified CloudWatch Agent en Amazon Linux 2.
#
# El agente permite publicar en CloudWatch métricas que EC2 no expone por
# defecto (RAM, espacio real en disco, procesos), ya que el hipervisor no
# puede verlas sin acceso al sistema operativo de la instancia.
#
# Requisitos previos:
#   - La instancia necesita un rol IAM con la política CloudWatchAgentServerPolicy
#     para poder publicar métricas.
#   - Si se carga la configuración desde SSM, se necesita además permiso de
#     lectura sobre el parámetro correspondiente.
#
# Uso:
#   sudo bash cloudwatch-agent-install.sh
#

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Instalación del agente
# ---------------------------------------------------------------------------
# En Amazon Linux 2 el paquete está disponible en los repositorios por defecto.
# En Debian/Ubuntu hay que descargar el .deb desde S3 e instalarlo con dpkg,
# ya que no está en los repositorios de la distribución:
#
#   wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
#   sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
#   sudo apt-get install -f   # resuelve dependencias que dpkg no gestiona

sudo yum install -y amazon-cloudwatch-agent

# ---------------------------------------------------------------------------
# 2. Asistente de configuración
# ---------------------------------------------------------------------------
# Genera el JSON de configuración de forma interactiva. Aquí se decide qué
# métricas recoger (mem, disk, procstat...) y con qué frecuencia enviarlas.
# Alternativamente se puede escribir el JSON a mano.

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard

# ---------------------------------------------------------------------------
# 3. Ficheros que el agente espera encontrar
# ---------------------------------------------------------------------------
# Si se habilita la recolección vía collectd, el agente falla al arrancar si
# este fichero no existe. Se crea vacío para evitarlo.

sudo mkdir -p /usr/share/collectd
sudo touch /usr/share/collectd/types.db

# ---------------------------------------------------------------------------
# 4. Cargar la configuración y arrancar el agente
# ---------------------------------------------------------------------------
# Las dos opciones siguientes son ALTERNATIVAS, no pasos consecutivos.
# Se usa una u otra según dónde esté almacenada la configuración.

# Opción A: configuración almacenada en SSM Parameter Store.
# Útil para aplicar la misma configuración a una flota de instancias sin
# copiar ficheros manualmente en cada una.
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c ssm:AmazonCloudWatch-linux -s

# Opción B: configuración en un fichero local de la propia instancia.
# sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
#   -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s

# ---------------------------------------------------------------------------
# 5. Comprobación
# ---------------------------------------------------------------------------
# El agente corre como un servicio systemd más, igual que Apache o MySQL.
#
#   sudo systemctl status amazon-cloudwatch-agent
#   sudo systemctl restart amazon-cloudwatch-agent
#
# Las métricas aparecen en CloudWatch bajo el namespace personalizado CWAgent.
