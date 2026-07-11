// @cloudflare/vitest-pool-workers@0.18.x types `env` from 'cloudflare:test' as
// `Cloudflare.Env` directly. We extend that namespace with test-only bindings
// set in vitest.config.ts (miniflare bindings).
import type { D1Migration } from '@cloudflare/vitest-pool-workers';

// Extend the Cloudflare namespace used by 'cloudflare:test'
declare global {
  namespace Cloudflare {
    interface Env {
      TEST_MIGRATIONS: D1Migration[];
      APNS_PRIVATE_KEY: string;
      APNS_KEY_ID: string;
      APNS_TEAM_ID: string;
    }
  }
}
