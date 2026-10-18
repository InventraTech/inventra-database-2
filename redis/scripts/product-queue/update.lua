-- Impede que um consumer antigo confirme itens após perder sua concessão.
if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
if not redis.call('ZSCORE', KEYS[3], ARGV[2]) then return 0 end
if ARGV[4] == '1' then
    redis.call('SET', KEYS[2], ARGV[3], 'EX', 604800)
    redis.call('ZREM', KEYS[3], ARGV[2])
    if ARGV[5] == '1' then
        redis.call('LPUSH', KEYS[4], ARGV[3])
        redis.call('LTRIM', KEYS[4], 0, 999)
        redis.call('EXPIRE', KEYS[4], 604800)
    end
else
    redis.call('SET', KEYS[2], ARGV[3])
end
return 1
