const edgePort = Number(process.env.INFERNIX_EDGE_PORT ?? "9090");
const edgeHost = process.env.INFERNIX_PLAYWRIGHT_HOST ?? "127.0.0.1";

export default {
  testDir: "./playwright",
  fullyParallel: false,
  reporter: "list",
  timeout: 30_000,
  use: {
    baseURL: `http://${edgeHost}:${edgePort}`,
    trace: "retain-on-failure",
  },
};
