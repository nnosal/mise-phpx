-- FrankenPHP runner shared by install and list-versions.
-- Pin a version project-wide via PHPX_FRANKENPHP_VERSION (e.g. in mise.toml [env]).
local fp_version = os.getenv("PHPX_FRANKENPHP_VERSION") or "latest"
local fp_bin = "frankenphp-linux"
local uname_f = io.popen("uname -s 2>/dev/null")
if uname_f then
    local uname_s = uname_f:read("*l") or ""
    uname_f:close()
    if uname_s:match("Darwin") then fp_bin = "frankenphp-mac" end
end
local FP = "mise x 'github:php/frankenphp@" .. fp_version .. "' -q --raw -- " .. fp_bin .. " php-cli"

-- Plugin data directory: <MISE_DATA_DIR>/phpx (composer.phar, extensions, php shim).
local function data_dir()
    local base = os.getenv("MISE_DATA_DIR")
    if not base or base == "" then base = (os.getenv("HOME") or "") .. "/.local/share/mise" end
    return base .. "/phpx"
end

-- Downloads composer.phar once into MISE_DATA_DIR/phpx/ and returns its path.
-- Accepts the mise `cmd` module so it can be called from any hook.
local function ensure_composer_phar(cmd)
    local phar = data_dir() .. "/composer.phar"
    os.execute("mkdir -p " .. data_dir())
    local f = io.open(phar, "r")
    if f then
        f:close()
    else
        cmd.exec("curl -sL https://getcomposer.org/composer.phar -o " .. phar)
    end
    return phar
end

-- ctx.tool for phpx:composer:cpx is "composer:cpx"
-- ctx.tool for phpx:phive:pie is "phive:pie"
-- ctx.tool for phpx:phpx is "phpx"
local function detect_backend(ctx)
    if ctx and ctx.tool then
        local sub = ctx.tool:match("^([^:]+):")
        if sub == "composer" or sub == "phive" then return sub end
        if ctx.tool == "phpx" then return "phpx" end
    end
    -- Fallback: parse install_path (phpx-composer-cpx → composer)
    if ctx and ctx.install_path then
        local p = ctx.install_path:match("/installs/([^/]+)/")
        if p then
            if p:match("^phpx%-composer%-") then return "composer" end
            if p:match("^phpx%-phive%-")    then return "phive"    end
            if p:match("^phpx")             then return "phpx"     end
        end
    end
    return "phpx"
end

-- Directory of this plugin (…/plugins/phpx). MISE_PLUGIN_DIR is not set in
-- every hook (and the `debug` library is unavailable in mise's Lua sandbox),
-- so fall back to <MISE_DATA_DIR>/plugins/<name>, derived from ctx.install_path.
local function plugin_dir(ctx)
    local env = os.getenv("MISE_PLUGIN_DIR") or os.getenv("MISE_PLUGIN_PATH")
    if env and env ~= "" then return env end
    local name = (PLUGIN and PLUGIN.name) or "phpx"
    local data_dir = os.getenv("MISE_DATA_DIR")
    if (not data_dir or data_dir == "") and ctx and ctx.install_path then
        data_dir = ctx.install_path:match("^(.*)/installs/")
    end
    if not data_dir or data_dir == "" then
        data_dir = (os.getenv("HOME") or "") .. "/.local/share/mise"
    end
    return data_dir .. "/plugins/" .. name
end

-- Single-quotes a value for safe interpolation into a shell command.
local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Normalises a tool option into a list of strings.
-- mise passes scalar options as strings and TOML arrays as Lua tables; a string
-- may also hold several entries separated by commas and/or whitespace.
--   opt_list(nil)                 → {}
--   opt_list("a/b:^1 c/d")        → {"a/b:^1", "c/d"}
--   opt_list({"a/b:^1", "c/d"})   → {"a/b:^1", "c/d"}
local function opt_list(v)
    local out = {}
    if v == nil then return out end
    if type(v) == "table" then
        for _, item in ipairs(v) do
            if item ~= nil and tostring(item) ~= "" then out[#out + 1] = tostring(item) end
        end
        return out
    end
    for item in tostring(v):gmatch("[^,%s]+") do out[#out + 1] = item end
    return out
end

-- Strips the sub-backend prefix: "composer:cpx" → "cpx", "phpx" → "phpx"
local function get_tool(ctx)
    if ctx and ctx.tool then
        return ctx.tool:match("^[^:]+:(.+)$") or ctx.tool
    end
    return ""
end

return {
    FP                   = FP,
    data_dir             = data_dir,
    ensure_composer_phar = ensure_composer_phar,
    detect_backend       = detect_backend,
    get_tool             = get_tool,
    shell_quote          = shell_quote,
    plugin_dir           = plugin_dir,
    opt_list             = opt_list,
}
