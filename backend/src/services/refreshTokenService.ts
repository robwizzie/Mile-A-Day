import { PostgresService } from './DbService.js';
import { generateRefreshToken, hashRefreshToken, generateAccessToken } from './tokenService.js';
import { RefreshToken, RefreshTokenMetadata, TokenPair } from '../types/auth.js';
import crypto from 'crypto';

const db = PostgresService.getInstance();

export async function createRefreshToken(userId: string, metadata: RefreshTokenMetadata): Promise<string> {
	const token = generateRefreshToken();
	const tokenHash = hashRefreshToken(token);
	const tokenFamilyId = crypto.randomUUID();

	await db.query(
		`INSERT INTO refresh_tokens
      (user_id, token_hash, token_family_id, user_agent, ip_address, device_info)
     VALUES ($1, $2, $3, $4, $5, $6)`,
		[
			userId,
			tokenHash,
			tokenFamilyId,
			metadata.userAgent,
			metadata.ipAddress,
			metadata.deviceInfo ? JSON.stringify(metadata.deviceInfo) : null
		]
	);

	return token;
}

export async function validateRefreshToken(token: string): Promise<RefreshToken | null> {
	const tokenHash = hashRefreshToken(token);

	const results = await db.query<RefreshToken>(
		`SELECT * FROM refresh_tokens
     WHERE token_hash = $1 AND revoked_at IS NULL`,
		[tokenHash]
	);

	return results.length > 0 ? results[0] : null;
}

export async function rotateRefreshToken(oldToken: string, metadata: RefreshTokenMetadata): Promise<TokenPair> {
	const isReused = await detectTokenReuse(oldToken);
	if (isReused) {
		const oldTokenHash = hashRefreshToken(oldToken);
		const revokedTokens = await db.query<RefreshToken>('SELECT token_family_id FROM refresh_tokens WHERE token_hash = $1', [
			oldTokenHash
		]);

		if (revokedTokens.length > 0) {
			await revokeTokenFamily(revokedTokens[0].token_family_id);
		}

		throw new Error('Token reuse detected - all sessions revoked');
	}

	const currentToken = await validateRefreshToken(oldToken);
	if (!currentToken) {
		throw new Error('Invalid or expired refresh token');
	}

	const accessToken = await generateAccessToken(currentToken.user_id);
	const newRefreshToken = generateRefreshToken();
	const newTokenHash = hashRefreshToken(newRefreshToken);

	await db.transaction([
		{
			query: `UPDATE refresh_tokens
              SET revoked_at = NOW(), revoked_reason = 'token_rotation'
              WHERE token_hash = $1`,
			params: [hashRefreshToken(oldToken)]
		},
		{
			query: `INSERT INTO refresh_tokens
              (user_id, token_hash, token_family_id, user_agent, ip_address, device_info)
              VALUES ($1, $2, $3, $4, $5, $6)`,
			params: [
				currentToken.user_id,
				newTokenHash,
				currentToken.token_family_id,
				metadata.userAgent,
				metadata.ipAddress,
				metadata.deviceInfo ? JSON.stringify(metadata.deviceInfo) : null
			]
		}
	]);

	return { accessToken, refreshToken: newRefreshToken };
}

export async function detectTokenReuse(token: string): Promise<boolean> {
	const tokenHash = hashRefreshToken(token);

	const results = await db.query<RefreshToken>(
		`SELECT * FROM refresh_tokens
     WHERE token_hash = $1 AND revoked_at IS NOT NULL AND revoked_reason = 'token_rotation'`,
		[tokenHash]
	);

	return results.length > 0;
}

export async function revokeRefreshToken(token: string, reason: string): Promise<void> {
	const tokenHash = hashRefreshToken(token);

	await db.query(
		`UPDATE refresh_tokens
     SET revoked_at = NOW(), revoked_reason = $1
     WHERE token_hash = $2`,
		[reason, tokenHash]
	);
}

export async function revokeAllUserTokens(userId: string, reason: string): Promise<number> {
	const result = await db.query(
		`UPDATE refresh_tokens
     SET revoked_at = NOW(), revoked_reason = $1
     WHERE user_id = $2 AND revoked_at IS NULL
     RETURNING token_id`,
		[reason, userId]
	);

	return result.length;
}

export async function revokeTokenFamily(familyId: string): Promise<void> {
	await db.query(
		`UPDATE refresh_tokens
     SET revoked_at = NOW(), revoked_reason = 'security_breach'
     WHERE token_family_id = $1 AND revoked_at IS NULL`,
		[familyId]
	);
}
