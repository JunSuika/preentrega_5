BEGIN;

CREATE TABLE clientes(
	id SERIAL PRIMARY KEY, --id autoincremental
	nombre VARCHAR(20) NOT NULL, --el nombre no puede ser nulo
	apellido VARCHAR(20) NOT NULL, --lo mismo el apellido
	email VARCHAR(50) UNIQUE NOT NULL, --el email no se puede repetir
	fecha_nacimiento DATE NOT NULL 
);

CREATE TABLE categorias(
	id SERIAL PRIMARY KEY, --id autoincremental
	nombre VARCHAR(50) UNIQUE NOT NULL --el nombre no puede ser nulo
);

CREATE TABLE productos(
	id SERIAL PRIMARY KEY, --id autoincremental
	nombre VARCHAR(50) NOT NULL, --el nombre no puede ser nulo
	stock INT NOT NULL,
	id_categoria INT NOT NULL,
	precio NUMERIC(10, 2) NOT NULL,
	CONSTRAINT chk_stock_real CHECK(stock >= 0), --no puede haber stock negativo
	CONSTRAINT chk_precio_positivo CHECK(precio >= 0), --no pueden ser precios negativos
	CONSTRAINT fk_id_categorias FOREIGN KEY (id_categoria) REFERENCES categorias(id) --FK que toma el id de categoría
);

CREATE TABLE ventas(
	id SERIAL PRIMARY KEY, --id autoincremental
	id_producto INT NOT NULL, 
	id_cliente INT NOT NULL,
	cantidad INT NOT NULL,
	precio_unitario NUMERIC(20, 2) NOT NULL,
	fecha DATE NOT NULL DEFAULT CURRENT_DATE,
	CONSTRAINT chk_cantidad_positiva CHECK(cantidad > 0), --no puede haber una venta de 0 productos
	CONSTRAINT chk_monto_positivo CHECK(precio_unitario >= 0), --no se puede hacer una venta nula
	CONSTRAINT fk_id_productos FOREIGN KEY (id_producto) REFERENCES productos(id), --FK que toma el id de producto
	CONSTRAINT fk_id_clientes FOREIGN KEY (id_cliente) REFERENCES clientes(id) --FK que toma el id del cliente
);

COMMIT;

WITH 

-- CTE 1: ventas_mensuales

ventas_mensuales AS (
    SELECT 
        DATE_TRUNC('month', v.fecha)::DATE AS mes,
        cat.nombre AS categoria,
        ROUND(SUM(v.cantidad * v.precio_unitario)::NUMERIC, 2) AS venta_total
    FROM ventas v
    INNER JOIN productos p ON v.id_producto = p.id
    INNER JOIN categorias cat ON p.id_categoria = cat.id
    GROUP BY 
        DATE_TRUNC('month', v.fecha),
        cat.nombre
),

-- Objetivo: Normalizar la granularidad de los datos agrupando las transacciones
-- por mes (primer día de cada mes) y categoría de producto, calculando la 
-- facturación total de cada combinación.

-- CTE 2: metricas_ventana

metricas_ventana AS (
    SELECT 
        mes,
        categoria,
        venta_total,
        RANK() OVER (
            PARTITION BY mes 
            ORDER BY venta_total DESC
        ) AS ranking_mensual,
        SUM(venta_total) OVER (
            PARTITION BY categoria 
            ORDER BY mes ASC
        ) AS acumulado_historico,
        AVG(venta_total) OVER (
            PARTITION BY categoria
        ) AS promedio_categoria
    FROM ventas_mensuales
)

-- Objetivo: Aplicar funciones de ventana (Window Functions) sobre la tabla 
-- agrupada sin perder el detalle de cada fila mensual:
--   1. Ranking mensual: Posiciona cada categoría dentro de cada mes según su 
--      volumen de facturación (de mayor a menor).
--   2. Acumulado (Running Total): Suma progresivamente las ventas de cada 
--      categoría a lo largo de los meses ordenados cronológicamente.
--   3. Promedio histórico: Calcula la media mensual de cada categoría para
--      habilitar la comparativa de rendimiento en la consulta final.

-- CONSULTA FINAL (SELECT PRINCIPAL)

SELECT 
    mes,
    categoria,
    venta_total,
    ranking_mensual,
    acumulado_historico,
    CASE 
        WHEN venta_total >= promedio_categoria THEN 'Exitoso'
        ELSE 'Bajo el promedio'
    END AS comparativa_rendimiento
FROM metricas_ventana
ORDER BY 
    mes ASC, 
    ranking_mensual ASC;

-- Objetivo: Presentar el reporte ejecutivo de 5 columnas exigido, evaluando
-- mediante lógica condicional (CASE WHEN) si el desempeño de cada categoría
-- en un mes puntual superó o igualó su propio promedio histórico ('Exitoso')
-- o si quedó por debajo ('Bajo el promedio').
