# AWS Certified CloudOps Engineer Associate (SOA-C03) — Notas de estudio

Repositorio de scripts, configuraciones y notas técnicas de mi preparación para la
certificación **AWS Certified CloudOps Engineer – Associate (SOA-C03)**.

No es un curso ni un resumen del temario oficial. Son las notas que voy tomando
sobre los puntos que me han costado entender o que tienen implicaciones prácticas
que no son obvias a primera vista: cuándo aplica cada opción, qué cuesta dinero y
qué no, y cómo se relaciona con lo que ya venía haciendo en producción.

## Contenido

| Tema | Contenido |
|---|---|
| [EC2 Monitoring](./ec2-monitoring/) | CloudWatch Agent, plugin procstat, métricas no incluidas por defecto y su coste |
| [Placement Groups](./placement-groups/) | Estrategias cluster / spread / partition y cuándo usar cada una |
| [EC2 Instance Connect](./ec2-instance-connect/) | Acceso SSH con credenciales temporales y acceso a instancias sin IP pública |
| [Status Checks y recuperación](./ec2-status-checks-recovery/) | Los tres checks, reboot vs stop/start y automatización de la recuperación con alarmas |
| [IAM: configuración inicial](./iam-initial-setup/) | Usuario administrador, MFA y alias de cuenta *(práctica propia, fuera del curso)* |
| [EC2 Hibernate](./ec2-hibernate/) | Conservación del estado de RAM, requisitos y comparativa con reboot y stop/start |

## Contexto

Administrador de sistemas y desarrollador con casi 7 años gestionando
infraestructura Linux en producción para plataformas de e-commerce: Apache/Nginx,
iptables, alta disponibilidad con IPs failover, monitorización con Grafana,
backups con rsync y despliegue continuo con Git.

Este repositorio documenta el proceso de trasladar esa base a AWS.

## Sobre las notas

Cada carpeta incluye un `README.md` con el concepto explicado y, cuando aplica,
los scripts o configuraciones correspondientes. Donde hay implicaciones de
facturación, están anotadas explícitamente: en un entorno de laboratorio es fácil
dejarse recursos encendidos y en producción es fácil disparar el coste de
métricas personalizadas sin darse cuenta.

## Fuentes y método

El contenido de estas notas procede de dos fuentes:

- El curso **AWS Certified CloudOps Engineer Associate SOA-C03 2026** de
  [Stéphane Maarek](https://www.udemy.com/user/stephane-maarek/) en Udemy.
- Conversaciones con **Claude** (Anthropic), usado como herramienta de estudio para
  profundizar en los conceptos, resolver dudas y contrastar los detalles prácticos
  y de facturación que no siempre aparecen en el material del curso.

La redacción final de los `README` se ha apoyado en esas conversaciones. Los
ejemplos, analogías y el enfoque de cada nota responden a las dudas concretas que
me fueron surgiendo durante el estudio y a mi experiencia previa administrando
infraestructura en producción.

---

Roberto Carlos Moyano Torres
[LinkedIn](https://linkedin.com/in/robertocmt13) · [GitHub](https://github.com/robertocmt13)
