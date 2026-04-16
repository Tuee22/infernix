export default {
  testDir: "./playwright",
  fullyParallel: false,
  reporter: "list",
  timeout: 30_000,
  use: {
    baseURL: "http://127.0.0.1:43173",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run build && ../.build/infernix cluster up && ../.build/infernix service --port 43173",
    cwd: ".",
    port: 43173,
    reuseExistingServer: false,
    timeout: 30_000,
  },
};
