-- load our template engine
local tirtemplate = require('tirtemplate')
local bloglib = require('bloglib')
local cjson = require "cjson"
local markdown = require "markdown"
-- Load our blog atom generator
local atom = require "atom"

if not config then
    local f = assert(io.open(ngx.var.root .. "/etc/config.json", "r"))
    local c = f:read("*all")
    f:close()

    config = cjson.decode(c)
end

-- Set the content type
ngx.header.content_type = 'text/html'

-- use nginx $root variable for template dir, needs trailing slash
TEMPLATEDIR = ngx.var.root
-- The git repository storing the markdown files. Needs trailing slash
BLAGDIR = TEMPLATEDIR .. config.path.blog
BLAGTITLE = config.blog.title

BASE = config.path.base_url
BLAGURL = config.blog.url
BLAGAUTHOR = config.blog.author

-- the db global
red = nil

function filename2title(filename)
    title = filename:gsub('.md$', ''):gsub('-', ' ')
    return title
end

function slugify(title)
    slug = title:gsub(' ', '-')
    return slug
end

-- Swap key and values in a table
function swap(t)
    local a = {}
    for k, v in pairs(t) do
        a[v] = k
    end
    return a
end

-- Helper to iterate a table by sorted keys
function itersort (t, f)
  local a = {}
  -- Sort on timestamp key reverse
  f = function(a,b) return tonumber(a)>tonumber(b) end
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

-- 
-- Index view
--
local function index()
    
    -- increment index counter
    local counter, err = bloglib.visit_index()
    -- Get 10 posts
    local posts = bloglib.posts_with_dates(10)
    -- load template
    local page = tirtemplate.tload('index.html')
    local context = {
        title = BLAGTITLE, 
        counter = tostring(counter),
        posts = posts,
    }
    -- render template with counter as context
    -- and return it to nginx
    ngx.print( page(context) )
end

-- 
-- Atom feed view
--
local function feed()

    -- increment feed counter
    local counter, err = red:incr("feed:visit")
    -- Get 10 posts
    local posts = posts_with_dates(10)
    -- Set correct content type
    ngx.header.content_type = 'application/atom+xml'
    ngx.print( atom.generate_xml(BLAGTITLE, BLAGURL, BLAGAUTHOR .. "'s blog", BLAGAUTHOR, 'feed/', posts) )

end

--
-- blog view for a single post
--
local function blog(match)
    local page = match[1] 
    -- Checkf the requests page exists as a key in the sorted set
    local date, err = bloglib.get_meta(page)
    -- No match, return 404
    if err or date == ngx.null then
        return ngx.HTTP_NOT_FOUND
    end
    -- check if the page cache needs updating
    local post, err = bloglib.get_post(page)
    if err or post == ngx.null then
        ngx.say('Error fetching post from database')
        return 500
    end
    local postlog = cjson.decode(post)
    local lastupdate = 0
    for ref, attrs in pairs(postlog) do
        local logdate = attrs.timestamp
        if logdate > lastupdate then
            lastupdate = logdate
        end
    end
    local lastgenerated, err = bloglib.get_post_html(page)
    local nocache = true
    if lastgenerated == ngx.null or err then 
        lastgenerated = 0 
        nocache = true 
    else
        lastgenerated = tonumber(lastgenerated)
    end
    if lastupdate <= lastgenerated then nocache = false end
    local mdhtml = '' 
    if nocache then
        local mdfile =  BLAGDIR .. page .. '.md'
        local mdfilefp = assert(io.open(mdfile, 'r'))
        local mdcontent = mdfilefp:read('*a')
        mdhtml = markdown(mdcontent) 
        mdfilefp:close()
        bloglib.set_post_html(page, lastupdate)
        bloglib.set_post_md(page, mdhtml)
    else
        mdhtml = bloglib.get_post_md(page)
    end
    -- increment visist counter
    bloglib.visit_page(page)

    -- Get more posts to be linked
    local posts = bloglib.posts_with_dates(5)

    local ctx = {
        created = ngx.http_time(date),
        content = mdhtml,
        title = filename2title(page),
        posts = posts,
        counter = counter,
    } 
    local template = tirtemplate.tload('blog.html')
    ngx.print( template(ctx) )

end

-- mapping patterns to views
local routes = {
    ['$']         = index,
    ['feed/$']     = feed,
    ['(.*)$']     = blog,
}

-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        bloglib.init()
        exit = view(match) or ngx.HTTP_OK
        bloglib.destroy()
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )
