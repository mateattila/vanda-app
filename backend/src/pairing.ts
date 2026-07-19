export type PairingRole = 'parent' | 'child';

export type PairingCodeRow = {
  code: string;
  family_id: string;
  expires_at: number;
  used_at: number | null;
  role: PairingRole;
};

export const PAIRING_CODE_TTL_MS = 10 * 60 * 1000;

export function isCodeUsable(row: PairingCodeRow, now: number): boolean {
  return row.used_at === null && now <= row.expires_at;
}

export function isPairingRole(value: unknown): value is PairingRole {
  return value === 'parent' || value === 'child';
}
