-- FrankenPHP runner shared by install and list-versions.
-- Pin a version project-wide via PHPX_FRANKENPHP_VERSION (e.g. in mise.toml [env]).
local fp_version = os.getenv("PHPX_FRANKENPHP_VERSION") or "latest"

-- Bash function resolving the FrankenPHP binary path (embedded in generated
-- wrappers and the php shim; keep in sync with bin/phpx). Uses `mise where`:
-- the mise github backend names the binary `frankenphp` (OS/arch suffixes
-- stripped, older releases kept them, hence the glob), and a PATH lookup could
-- hit the `frankenphp` shim mise creates (a symlink to mise itself).
local FP_FN = [[fp_path() {
    # fp_path VERSION: path of the FrankenPHP binary, installing it through mise on first use.
    # Uses `mise where` rather than a PATH lookup: the mise shims dir may hold a `frankenphp`
    # shim (a symlink to mise itself) that would otherwise be picked up.
    local v="$1" d b
    d=$(mise where "github:php/frankenphp@$v" 2>/dev/null) || {
        mise install -q "github:php/frankenphp@$v" >&2 || return 1
        d=$(mise where "github:php/frankenphp@$v") || return 1
    }
    for b in "$d"/frankenphp* "$d"/bin/frankenphp*; do
        [ -f "$b" ] && [ -x "$b" ] && { printf "%s\n" "$b"; return 0; }
    done
    echo "phpx: FrankenPHP binary not found in $d" >&2
    return 1
}]]

-- Shell expression evaluating to the FrankenPHP binary path for a version.
local function fp_bin_expr(version)
    return '"$(bash -c \'' .. FP_FN .. '; fp_path "$1"\' _ ' .. version .. ')"'
end


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

-- Path of the argv-normalising bootstrap (see libexec/phpx-run.php), copied
-- into the shared libexec so generated wrappers do not depend on the plugin dir.
local function run_php()
    return data_dir() .. "/libexec/phpx-run.php"
end

local function ensure_run_php(ctx)
    local src = plugin_dir(ctx) .. "/libexec/phpx-run.php"
    os.execute("mkdir -p " .. shell_quote(data_dir() .. "/libexec"))
    os.execute("cp " .. shell_quote(src) .. " " .. shell_quote(run_php()))
    return run_php()
end

-- FrankenPHP php-cli runner for scripts/PHARs (argv normalised by phpx-run.php).
local FP = fp_bin_expr(fp_version) .. " php-cli " .. shell_quote(run_php())

return {
    FP                   = FP,
    run_php              = run_php,
    ensure_run_php       = ensure_run_php,
    FP_FN                = FP_FN,
    fp_bin_expr          = fp_bin_expr,
    data_dir             = data_dir,
    ensure_composer_phar = ensure_composer_phar,
    detect_backend       = detect_backend,
    get_tool             = get_tool,
    shell_quote          = shell_quote,
    plugin_dir           = plugin_dir,
    opt_list             = opt_list,
}
