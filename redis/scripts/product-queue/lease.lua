if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
if ARGV[2] == '0' then redis.call('DEL', KEYS[1])
else
    redis.call('EXPIRE', KEYS[1], ARGV[2])
    redis.call('EXPIRE', KEYS[2], ARGV[2])
end
return 1
