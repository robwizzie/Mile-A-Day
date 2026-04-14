import { Pool, QueryResultRow, types } from 'pg';

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

	private constructor() {
		this.pool = new Pool({
			connectionString: process.env.DATABASE_URL
		});

		this.pool.on('error', (err: any) => {
			console.error('Unexpected error on idle client', err);
			process.exit(1);
		});
	}

	public static getInstance(): PostgresService {
		if (!PostgresService.instance) {
			PostgresService.instance = new PostgresService();
		}
		return PostgresService.instance;
	}

	public async query<T extends QueryResultRow = any>(query: string, params?: any[]): Promise<T[]> {
		const client = await this.pool.connect();
		try {
			const result = await client.query<T>(query, params);
			return result.rows;
		} finally {
			client.release();
		}
	}

	public async transaction(queries: QueryConfig[]): Promise<void> {
		const client = await this.pool.connect();
		try {
			await client.query('BEGIN');

			for (const { query, params } of queries) {
				await client.query(query, params);
			}

			await client.query('COMMIT');
		} catch (err) {
			await client.query('ROLLBACK');
			throw err;
		} finally {
			client.release();
		}
	}

	public async close(): Promise<void> {
		await this.pool.end();
	}
}
