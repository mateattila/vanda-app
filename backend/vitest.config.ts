import { defineConfig } from 'vitest/config';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';

// Teszt-fixture P-256 kulcs — NEM titok, kizárólag a JWT-aláírás unit tesztjéhez
// generált eldobható kulcspár (a párja a tesztfájlban lévő publikus kulcs).
export const TEST_APNS_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg9YkeBF9Ngqi9ui3x
0MuY+62eO5fJvD/tdudghHUGwIOhRANCAAS2QfeCuMMsIe8AIs9eOIdfoO8SM1Ff
V7u6xKHfYj9GYElHOyoBEnMNAHOnTZlzgfrLme6IHjOKMspMXaRRvFKm
-----END PRIVATE KEY-----`;

export default defineConfig({
  plugins: [
    // @cloudflare/vitest-pool-workers@0.18.x (paired with vitest 4) replaced the
    // old `defineWorkersConfig({ test: { poolOptions: { workers } } })` shape
    // with a Vite plugin: `cloudflareTest(workersOptions)`. The `workersOptions`
    // object itself (wrangler/miniflare keys) is unchanged from the old
    // `poolOptions.workers` shape, and it may still be an async factory.
    cloudflareTest(async () => {
      const migrations = await readD1Migrations('./migrations');
      return {
        wrangler: { configPath: './wrangler.jsonc' },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            APNS_TEAM_ID: 'TESTTEAM99X',
            APNS_KEY_ID: 'TESTKEY99XX',
            APNS_PRIVATE_KEY: TEST_APNS_PRIVATE_KEY,
          },
        },
      };
    }),
  ],
  test: {
    setupFiles: ['./test/apply-migrations.ts'],
  },
});
