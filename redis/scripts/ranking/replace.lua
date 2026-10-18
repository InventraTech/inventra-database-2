-- Lua isola execução, mas NÃO desfaz comandos anteriores em caso de erro.
-- Constrói em chave temporária; publica somente quando todo o snapshot estiver pronto.
local ttl = tonumber(ARGV[1])
if not ttl or ttl < 1 or ttl ~= math.floor(ttl) or #ARGV % 2 ~= 0 then
    return redis.error_reply('Invalid ranking arguments')
end
for i = 3, #ARGV, 2 do
    local score = tonumber(ARGV[i + 1])
    if not score or score ~= score or score == math.huge or score == -math.huge then
        return redis.error_reply('Invalid ranking score')
    end
end
redis.call('ZADD', KEYS[2], '+inf', ARGV[2])
redis.call('EXPIRE', KEYS[2], ttl)
for i = 3, #ARGV, 2 do
    redis.call('ZADD', KEYS[2], ARGV[i + 1], ARGV[i])
end
redis.call('RENAME', KEYS[2], KEYS[1])
return 1
