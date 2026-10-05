<?php

declare(strict_types=1);

namespace App\Support;

/**
 * A short Redis lock to avoid duplicate work. It never replaces a condition in the
 * database write: it can expire while the holder still works.
 */
final class RedisLock
{
    private const RELEASE = <<<'LUA'
        if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('del', KEYS[1])
        end
        return 0
        LUA;

    public function __construct(private \Redis $redis)
    {
    }

    /** Returns the owner token, or null when someone else holds the lock. */
    public function acquire(string $key, int $ttlMs): ?string
    {
        $token = bin2hex(random_bytes(16));
        $ok = $this->redis->set('lock:' . $key, $token, ['nx', 'px' => $ttlMs]);

        return $ok ? $token : null;
    }

    public function release(string $key, string $token): void
    {
        $this->redis->eval(self::RELEASE, ['lock:' . $key, $token], 1);
    }
}
