import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://redis:6379", {
  maxRetriesPerRequest: null,
  enableReadyCheck: true,
  lazyConnect: false,
  retryStrategy: (times: number) => Math.min(times * 250, 5000),
});

redis.on("error", (err: Error) => console.error("Redis:", err.message));
redis.on("connect", () => console.log("J&Z worker connected to Redis"));
redis.on("ready", () => console.log("J&Z worker Redis ready"));

const shutdown = async (): Promise<void> => {
  await redis.quit().catch(() => undefined);
  process.exit(0);
};
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());

const timer = setInterval(() => {
  void redis.ping().catch((err: Error) => console.error("Redis ping:", err.message));
}, 30_000);
timer.unref();
