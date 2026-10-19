# Lab 4 — Respuestas a las preguntas orientadoras 1 y 4

> Borrador. Antes de entregar: completar con el tipo de instancia del Lab 3 (si se recuerda) y revisar los valores contra los PDF originales.

## Pregunta 1 — Eficiencia de escalar el monolito agregando recursos

**Criterio.** Se define la ganancia marginal de throughput por instancia agregada, ΔT/ΔR, y la eficiencia frente al escalamiento lineal ideal, E = T(n) / (n · T(1)).

| Configuración | Instancias (R) | Throughput GET, Alta carga (req/s) | Ideal lineal (req/s) |
|---|---:|---:|---:|
| Monolito local (Lab 2) | 1 | 102,6 (106,1 / 92,4 / 109,5) | 102,6 |
| Monolito en AWS tras ALB (Lab 3) | 3 | 81,0 (84,2 / 82,1 / 78,8 / 78,9) | 307,8 |

- **ΔT/ΔR** = (81,0 − 102,6) / (3 − 1) = **−10,8 req/s por instancia agregada**. Es negativa: agregar instancias no sumó throughput.
- **E** = 81,0 / 307,8 ≈ **26 %**. El escalamiento lineal ideal predice casi 308 req/s.
- **p99 del GET en Alta carga:** ~50 s en el Lab 2 y ~50 s en el Lab 3. La latencia no mejoró.
- **POST:** en el Lab 3, con 3 instancias, el error ya es 100 % en Alta carga. Su throughput de ~90 req/s corresponde a respuestas fallidas, así que no cuenta como capacidad real.

> *Limitación: no se midió en AWS una configuración de 1 instancia; se usa el Lab 2 (local) como línea base. La diferencia incluye también el efecto de separar la app de la base de datos, por lo que ΔT/ΔR es un indicador aproximado.*

**Punto en el que deja de ser proporcional.** Desde la primera instancia adicional. Con 1 instancia, el Lab 2 ya saturaba al pasar de 450 a 1500 threads (el p99 del GET sube de ~21 ms a decenas de segundos). Subir a 3 instancias no movió ese punto.

**Componente que lo explica.** La base de datos PostgreSQL compartida y su pool de conexiones. Cada instancia del monolito abre su propio pool (10 conexiones por defecto) contra la misma base. Con 3 instancias hay más procesos compitiendo por el mismo recurso, más latencia de red entre la app y la base (antes era local), y las transacciones del POST (pedido más cada ítem) retienen conexiones por más tiempo. El ALB reparte las peticiones, pero no aumenta la capacidad de la base de datos.

**Relación con los ASR.**
- **REQ3 (≥ 83,3 req/s con error ≤ 10 %):** el monolito ×3 llegó a ~81 req/s, justo debajo del umbral, y con el POST fallando al 100 %. No se cumple.
- **REQ1 (p99 del POST < 2000 ms):** se incumple desde Alta carga, con p99 de ~30–58 s en el Lab 3.
- **REQ2 (error del GET ≤ 10 %):** se sostiene hasta Muy alta carga, pero la latencia ya es inaceptable.

**Conclusión.** Escalar el monolito en bloque cuesta tres veces más cómputo y entrega el mismo throughput. Esto motiva separar los servicios y escalar solo el que se satura, y tratar la base de datos como el límite real.

---

## Pregunta 4 — Distribución de carga GET/POST

**Riesgo real: 70/30.** Un tendero consulta productos disponibles varias veces antes de confirmar un pedido, así que los GET dominan en un lunes de alta demanda. Con 70/30 los POST siguen siendo una parte importante del tráfico, porque en un lunes se concentra la reposición. Es una hipótesis de negocio, no un dato medido: la proporción se puede ajustar con datos reales de producción.

**Peor caso técnico: 30/70.** Se enfoca en lo que miden REQ1 y REQ3: el POST, que hace una escritura transaccional con 25 ítems. Esa operación retiene conexiones y bloqueos en la RDS compartida por más tiempo que un GET. Con 70 % de POST se maximiza la presión sobre el recurso que ya se identificó como cuello de botella.

**Por qué no deben coincidir.**
- La distribución realista responde si se cumplen los ASR el lunes esperado.
- La de peor caso responde dónde se rompe el sistema y cuánto margen queda.
- Una carga realista puede ocultar el límite del POST. Una de peor caso exagera la frecuencia con la que ocurre, y puede llevar a sobredimensionar la infraestructura.

**Matiz.** Según el análisis del Lab 2, el GET también es pesado (tres subconsultas `EXISTS` sin índices), así que un escenario 70/30 estresa la CPU de la base de datos. El 30/70 estresa la retención de conexiones y bloqueos. Son cuellos distintos, otra razón para probar ambas.

**Uso en la matriz.** La matriz completa se corre con 70/30. Con 30/70 se repiten solo las filas críticas: Operación normal y la primera fila donde se incumpla un ASR.
