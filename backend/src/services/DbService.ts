import { Pool, QueryResultRow } from 'pg';

type QueryConfig = {
	query: string;
	params?: any[];
};

export class PostgresService {
	private static instance: PostgresService;
	private pool: Pool;

	private constructor() {
		this.pool = new Pool({
			host: process.env.DB_HOST,
			port: parseInt(process.env.DB_PORT || '5432'),
			user: process.env.DB_USER,
			password: process.env.DB_PASSWORD,
			database: process.env.DB_NAME
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
