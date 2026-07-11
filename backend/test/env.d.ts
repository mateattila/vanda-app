// @cloudflare/vitest-pool-workers@0.18.x types `env` from 'cloudflare:test' as
// `Cloudflare.Env` directly (the older `ProvidedEnv extends Env` module
// augmentation was removed). We extend that namespace with the test-only
// migrations binding instead.
import type { D1Migration } from '@cloudflare/vitest-pool-workers';

declare namespace Cloudflare {
  interface Env {
    TEST_MIGRATIONS: D1Migration[];
  }
}
