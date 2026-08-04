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

    // Postgres' LLVM JIT is a loss for this workload, and a latent landmine.
    //
    // It engages purely on the planner's ESTIMATED cost crossing jit_above_cost
    // — nothing about the query changes, only the table statistics under it. So
    // an endpoint runs fine for months and then, once the tables grow past some
    // invisible line, every execution starts paying ~200ms of LLVM codegen. The
    // tell is an EXPLAIN whose Execution Time is far larger than anything its
    // plan nodes account for: prod's feed query read 278ms with ~35ms of actual
    // node work, while the same query over a LARGER local dataset (on a build
    // without JIT available) took 99ms.
    //
    // Codegen only repays itself when a query evaluates its expressions over
    // millions of rows. Everything this API runs is OLTP — bounded pages, a few
    // hundred rows at most — so it never repays, on any endpoint.
    //
    // Sent per connection rather than as a startup `options` parameter: a
    // startup parameter a pooler doesn't accept fails the CONNECTION, which is
    // an outage, whereas a failed SET here just leaves that connection on the
    // old behaviour. Connections are long-lived (30s idle timeout, max 20), so
    // this runs a handful of times, not per query.
    const jit = process.env.PG_JIT === "on" ? "on" : "off";
    this.pool.on("connect", (client: any) => {
      client.query(`SET jit = ${jit}`).catch((err: any) => {
        console.error("[db] could not set jit:", err?.message ?? err);
      });
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
