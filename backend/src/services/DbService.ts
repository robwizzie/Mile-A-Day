import { Pool, QueryResultRow, types } from "pg";
import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import * as schema from "../db/drizzle/schema.js";

// Return DATE columns (OID 1082) as 'YYYY-MM-DD' strings instead of JS Date objects.
// JS Date is local-midnight and causes TZ confusion; the backend treats these columns as strings.
types.setTypeParser(1082, (val: string) => val);

type QueryConfig = {
  query: string;
  params?: any[];
};

export class PostgresService {
  private static instance: PostgresService;
  private pool: Pool;
  private drizzleDb: NodePgDatabase<typeof schema>;

  private constructor() {
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 20,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
      statement_timeout: 30_000,
      query_timeout: 30_000,
    });

    this.pool.on("error", (err: any) => {
      console.error("Unexpected error on idle client", err);
      process.exit(1);
    });

    // Drizzle ORM shares the SAME pool as the raw-SQL helpers below, so the
    // ORM and existing `query()`/`transaction()` calls draw from one set of
    // connections. Use `.orm` for new typed queries; raw SQL stays valid.
    this.drizzleDb = drizzle({
      client: this.pool,
      schema,
      casing: "snake_case",
    });
  }

  /** Typed Drizzle ORM client backed by the shared pool. */
  public get orm(): NodePgDatabase<typeof schema> {
    return this.drizzleDb;
  }

  /**
   * Check out a raw client for multi-statement work that needs manual
   * transaction control (BEGIN/SAVEPOINT/...). Caller MUST release() it.
   */
  public async getClient() {
    return this.pool.connect();
  }

  public static getInstance(): PostgresService {
    if (!PostgresService.instance) {
      PostgresService.instance = new PostgresService();
    }
    return PostgresService.instance;
  }

  public async query<T extends QueryResultRow = any>(
    query: string,
    params?: any[],
  ): Promise<T[]> {
    const result = await this.pool.query<T>(query, params);
    return result.rows;
  }

  public async transaction(queries: QueryConfig[]): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");

      for (const { query, params } of queries) {
        await client.query(query, params);
      }

      await client.query("COMMIT");
    } catch (err) {
      await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  }

  public async close(): Promise<void> {
    await this.pool.end();
  }
}

// Convenience handles for new ORM-based code:
//   import { db, schema } from '../services/DbService.js';
//   const rows = await db.select().from(schema.users).where(eq(schema.users.userId, id));
// Backed by the singleton's shared pool. Existing raw-SQL call sites are unaffected.
export const db = PostgresService.getInstance().orm;
export { schema };
