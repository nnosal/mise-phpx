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

-- Downloads composer.phar once into MISE_DATA_DIR/phpx/ and returns its path.
-- Accepts the mise `cmd` module so it can be called from any hook.
local function ensure_composer_phar(cmd)
    local data_dir = os.getenv("MISE_DATA_DIR") or (os.getenv("HOME") .. "/.local/share/mise")
    local phar = data_dir .. "/phpx/composer.phar"
    os.execute("mkdir -p " .. data_dir .. "/phpx")
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

-- Strips the sub-backend prefix: "composer:cpx" → "cpx", "phpx" → "phpx"
local function get_tool(ctx)
    if ctx and ctx.tool then
        return ctx.tool:match("^[^:]+:(.+)$") or ctx.tool
    end
    return ""
end

return {
    FP                   = FP,
    ensure_composer_phar = ensure_composer_phar,
    detect_backend       = detect_backend,
    get_tool             = get_tool,
}
