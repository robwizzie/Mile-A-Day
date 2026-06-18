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

// Window during which re-presenting an already-rotated refresh token is treated
// as a legitimate retry (the previous refresh response was lost to a dropped
// connection, or the app was suspended before it stored the new token) rather
// than a replay attack. Within the window we hand back a fresh working pair
// instead of revoking the whole family; outside it, a reused token still nukes
// every session.
const ROTATION_GRACE_MS = 60_000;

export async function rotateRefreshToken(oldToken: string, metadata: RefreshTokenMetadata): Promise<TokenPair> {
	const oldTokenHash = hashRefreshToken(oldToken);

	const rows = await db.query<RefreshToken>('SELECT * FROM refresh_tokens WHERE token_hash = $1', [oldTokenHash]);
	const presented = rows[0];

	if (!presented) {
		throw new Error('Invalid or expired refresh token');
	}

	// The presented token has already been rotated away (or otherwise revoked).
	if (presented.revoked_at) {
		const rotatedAgoMs = Date.now() - new Date(presented.revoked_at).getTime();
		const withinGrace = presented.revoked_reason === 'token_rotation' && rotatedAgoMs <= ROTATION_GRACE_MS;

		if (withinGrace) {
			// Legitimate retry after a lost refresh response: re-issue a fresh
			// pair in the same family without revoking it.
			return reissueWithinGrace(presented, metadata);
		}

		// Outside the grace window (or revoked for another reason, e.g. manual
		// logout / a prior breach) -> genuine reuse. Revoke the whole family.
		await revokeTokenFamily(presented.token_family_id);
		throw new Error('Token reuse detected - all sessions revoked');
	}

	// Normal rotation: the presented token is live.
	const accessToken = await generateAccessToken(presented.user_id);
	const newRefreshToken = generateRefreshToken();
	const newTokenHash = hashRefreshToken(newRefreshToken);

	await db.transaction([
		{
			query: `UPDATE refresh_tokens
              SET revoked_at = NOW(), revoked_reason = 'token_rotation', replaced_by_hash = $2
              WHERE token_hash = $1`,
			params: [oldTokenHash, newTokenHash]
		},
		insertTokenOp(presented.user_id, newTokenHash, presented.token_family_id, metadata)
	]);

	return { accessToken, refreshToken: newRefreshToken };
}

/**
 * Re-issues a fresh access + refresh token pair for a token rotated within the
 * grace window, WITHOUT revoking the token family. Retires the prior successor
 * if it is still live (the client never received it) so the family keeps at
 * most one active token, and chains the presented token to the new successor so
 * repeated retries within the window resolve consistently.
 */
async function reissueWithinGrace(presented: RefreshToken, metadata: RefreshTokenMetadata): Promise<TokenPair> {
	const accessToken = await generateAccessToken(presented.user_id);
	const newRefreshToken = generateRefreshToken();
	const newTokenHash = hashRefreshToken(newRefreshToken);

	const ops: { query: string; params: any[] }[] = [];

	if (presented.replaced_by_hash) {
		// Retire the previous successor only if it is still live. If it has
		// already been used/rotated, leave it alone -- that's a real chain.
		ops.push({
			query: `UPDATE refresh_tokens
              SET revoked_at = NOW(), revoked_reason = 'token_rotation', replaced_by_hash = $2
              WHERE token_hash = $1 AND revoked_at IS NULL`,
			params: [presented.replaced_by_hash, newTokenHash]
		});
	}

	// Chain the presented (already-revoked) token to the new successor so a
	// further retry within the window resolves to the same place.
	ops.push({
		query: `UPDATE refresh_tokens SET replaced_by_hash = $2 WHERE token_hash = $1`,
		params: [presented.token_hash, newTokenHash]
	});

	ops.push(insertTokenOp(presented.user_id, newTokenHash, presented.token_family_id, metadata));

	await db.transaction(ops);

	return { accessToken, refreshToken: newRefreshToken };
}

function insertTokenOp(userId: string, tokenHash: string, familyId: string, metadata: RefreshTokenMetadata) {
	return {
		query: `INSERT INTO refresh_tokens
            (user_id, token_hash, token_family_id, user_agent, ip_address, device_info)
            VALUES ($1, $2, $3, $4, $5, $6)`,
		params: [
			userId,
			tokenHash,
			familyId,
			metadata.userAgent,
			metadata.ipAddress,
			metadata.deviceInfo ? JSON.stringify(metadata.deviceInfo) : null
		]
	};
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
