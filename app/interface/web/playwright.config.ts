import { defineConfig, devices } from "@playwright/test"

export default defineConfig({
  testDir: "./cenas",
  timeout: 180_000,
  expect: { timeout: 60_000 },
  retries: 0,
  workers: 1,
  fullyParallel: false,
  reporter: "list",
  use: {
    ...devices["Desktop Chrome"],
    headless: true,
    screenshot: "only-on-failure",
    viewport: { width: 1280, height: 900 },
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
})
