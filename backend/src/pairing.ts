export type PairingCodeRow = {
  code: string;
  family_id: string;
  expires_at: number;
  used_at: number | null;
};

export const PAIRING_CODE_TTL_MS = 10 * 60 * 1000;

export function isCodeUsable(row: PairingCodeRow, now: number): boolean {
  return row.used_at === null && now <= row.expires_at;
}
