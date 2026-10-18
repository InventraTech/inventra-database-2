-- Mantém fencing e retenção da DLQ também para payload ausente/corrompido.
if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
if not redis.call('ZSCORE', KEYS[3], ARGV[2]) then return 0 end
local payload = redis.call('GET', KEYS[2])
local entry = cjson.encode({eventId = ARGV[2], status = 'FAILED', errorCode = ARGV[3],
    originalPayload = string.sub(payload or '', 1, 4096)})
redis.call('LPUSH', KEYS[4], entry)
redis.call('LTRIM', KEYS[4], 0, 999)
redis.call('EXPIRE', KEYS[4], 604800)
redis.call('EXPIRE', KEYS[2], 604800)
redis.call('ZREM', KEYS[3], ARGV[2])
return 1
