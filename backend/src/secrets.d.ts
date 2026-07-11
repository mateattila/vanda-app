// A wrangler types által generált Env kiegészítése a secretekkel
// (wrangler secret put APNS_TEAM_ID / APNS_KEY_ID / APNS_PRIVATE_KEY).
interface Env {
  APNS_TEAM_ID: string;
  APNS_KEY_ID: string;
  APNS_PRIVATE_KEY: string;
}
