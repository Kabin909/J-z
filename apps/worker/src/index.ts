import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://redis:6379", {
  maxRetriesPerRequest: null,
  enableReadyCheck: true,
});

redis.on("error", (err: Error) => console.error("Redis:", err.message));
redis.on("connect", () => console.log("J&Z worker connected to Redis"));

const shutdown = async () => {
  await redis.quit().catch(() => undefined);
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

setInterval(() => {
  void redis.ping().catch((err: Error) => console.error("Redis ping:", err.message));
}, 30000);
