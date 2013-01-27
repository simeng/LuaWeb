module('bloglib', package.seeall)

redis = require "resty.redis"
red = nil

-- Return a table with post date as key and title as val
function posts_with_dates(limit)
    local posts, err = red:zrevrange('posts', 0, limit, 'withscores')
    if err then return {} end
    posts = red:array_to_hash(posts)
    return swap(posts)
end

-- 
-- Initialise db
--
function init_db()
    -- Start redis connection
    red = redis:new()
    local ok, err = red:connect("unix:/var/run/redis/redis.sock")
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end
end

--
-- End db, we could close here, but park it in the pool instead
--
local function end_db()
    -- put it into the connection pool of size 100,
    -- with 0 idle timeout
    local ok, err = red:set_keepalive(0, 100)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
        return
    end
end

function get_meta(page)
    return red:zscore('posts', page)
end

function get_post(page)
    return red:get('post:'..page..':log')
end

function get_post_md(page)
    return red:get('post:'..page..':md')
end

function set_post_md(page, mdhtml)
    local ok, err = red:set('post:'..page..':md', mdhtml)
end

function get_post_html(page)
    return red:get('post:'..page..':cached')
end

function set_cache(page, lastupdate)
    local ok, err = red:set('post:'..page..':cached', lastupdate)
end

function visit_index()
    red:incr("index_visist_counter")
end

function visit_page(page)
    local counter, err = red:incr(page..":visit")
end

function visit_feed()
    local counter, err = red:incr("feed:visit")
end

function init()
    init_db()
end

function destroy()
    end_db()
end

