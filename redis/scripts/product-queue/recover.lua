if redis.call('GET', KEYS[1]) ~= ARGV[1] then return -1 end
local pending = redis.call('ZRANGE', KEYS[3], 0, -1)
redis.call('DEL', KEYS[2])
redis.call('DEL', KEYS[4])
for _, id in ipairs(pending) do redis.call('LPUSH', KEYS[2], id) end
redis.call('EXPIRE', KEYS[2], 30)
return #pending
