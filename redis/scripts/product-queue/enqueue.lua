-- O payload e o índice durável existem antes de o ID ficar disponível para BRPOP.
if redis.call('EXISTS', KEYS[4]) == 1 then return 0 end
local sequence = redis.call('INCR', KEYS[3])
redis.call('SET', KEYS[4], ARGV[2])
redis.call('ZADD', KEYS[2], sequence, ARGV[1])
local token = redis.call('GET', KEYS[5])
local ready = token and (KEYS[1] .. ':' .. token) or KEYS[1]
redis.call('LPUSH', ready, ARGV[1])
if token then redis.call('EXPIRE', ready, 30) end
return 1
