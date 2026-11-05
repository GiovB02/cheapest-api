import * as fs from 'fs';
import * as path from 'path';
import {
  Catalogo,
  Despacho,
  DisponibilidadZona,
  ItemPedido,
  NotaCredito,
  Pedido,
  Producto,
  Promocion,
} from '../libs/logistica/src/repositories/entities';
import {
  ItemInventario,
  RegistroCompraProductoTienda,
  RegistroVentaProductoTienda,
} from '../libs/inventario/src/repositories/entities';
import {
  ItemVenta,
  ProductoExterno,
  Venta,
} from '../libs/ventas/src/repositories/entities';
import { createDataSource } from '../libs/shared/database/src';

const CONNECTION_RETRY_DELAY_MS = parseInt(
  process.env.DB_CONNECT_RETRY_DELAY_MS || '2000',
  10,
);
const CONNECTION_RETRY_ATTEMPTS = parseInt(
  process.env.DB_CONNECT_RETRIES || '15',
  10,
);

process.env.DB_HOST ??= '127.0.0.1';
process.env.DB_PORT ??= '5432';
process.env.DB_USERNAME ??= 'postgres';
process.env.DB_PASSWORD ??= 'postgres';
process.env.DB_NAME ??= 'cheapest';

async function initializeDataSourceWithRetry(entities: Function[]) {
  let lastError: unknown;

  for (let attempt = 1; attempt <= CONNECTION_RETRY_ATTEMPTS; attempt += 1) {
    const dataSource = createDataSource(entities);

    try {
      await dataSource.initialize();
      return dataSource;
    } catch (error) {
      lastError = error;

      if (dataSource.isInitialized) {
        await dataSource.destroy().catch(() => undefined);
      }

      if (attempt === CONNECTION_RETRY_ATTEMPTS) {
        break;
      }

      console.log(
        `Waiting for Postgres (${attempt}/${CONNECTION_RETRY_ATTEMPTS}) at ${process.env.DB_HOST}:${process.env.DB_PORT}...`,
      );
      await new Promise((resolve) =>
        setTimeout(resolve, CONNECTION_RETRY_DELAY_MS),
      );
    }
  }

  throw lastError;
}

async function seedDatabase() {
  const entities = [
    Catalogo,
    Despacho,
    DisponibilidadZona,
    ItemInventario,
    ItemPedido,
    ItemVenta,
    NotaCredito,
    Pedido,
    Producto,
    ProductoExterno,
    Promocion,
    RegistroCompraProductoTienda,
    RegistroVentaProductoTienda,
    Venta,
  ];

  const dataSource = await initializeDataSourceWithRetry(entities);

  try {
    await dataSource.synchronize();

    const tables = await dataSource.query(`
      SELECT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'items_inventario'
      ) AS "exists"
    `);

    if (tables[0]?.exists) {
      const rows = await dataSource.query(
        'SELECT COUNT(*)::int AS count FROM items_inventario',
      );

      if ((rows[0]?.count ?? 0) > 0 && process.env.SEED_FORCE !== 'true') {
        console.log(
          'Database already seeded. Skipping. (SEED_FORCE=true para resembrar)',
        );
        return;
      }
    }

    const sqlPath = path.join(
      __dirname,
      '../libs/shared/database/src/seed.sql',
    );
    const sql = fs.readFileSync(sqlPath, 'utf8');
    // Cada sentencia viene precedida por líneas de comentario (`-- ...`): se
    // quitan antes de filtrar, o todas las sentencias se descartarían.
    const statements = sql
      .split(';')
      .map((statement) =>
        statement
          .split(/\r?\n/)
          .filter((line) => !line.trim().startsWith('--'))
          .join('\n')
          .trim(),
      )
      .filter((statement) => statement.length > 0);

    // Todo en una transacción: si una sentencia falla, no queda una siembra a
    // medias que el chequeo de "already seeded" tomaría como completa.
    await dataSource.transaction(async (manager) => {
      if (process.env.SEED_FORCE === 'true') {
        await manager.query(
          `TRUNCATE TABLE items_inventario, registros_compra_producto_tienda,
            registros_venta_producto_tienda, productos, catalogos,
            promociones, pedidos, items_pedido, despachos, disponibilidad_zona,
            notas_credito CASCADE`,
        );
      }

      for (const statement of statements) {
        await manager.query(statement);
      }
    });

    console.log('Database seeded successfully.');
  } finally {
    if (dataSource.isInitialized) {
      await dataSource.destroy();
    }
  }
}

void seedDatabase().catch((error) => {
  console.error('Failed to seed database:', error);
  console.error(
    'Ensure Postgres is running with `docker compose up -d postgres` and reachable with the configured DB_* environment variables.',
  );
  process.exit(1);
});
