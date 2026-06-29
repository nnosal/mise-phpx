local function write_fp_wrapper(path, target)
    local f, err = io.open(path, "w")
    if not f then error("Cannot write wrapper " .. path .. ": " .. (err or "unknown error")) end
    f:write("#!/usr/bin/env bash\n")
    -- PHPX_FRANKENPHP_VERSION is injected by phpx:phpx BackendExecEnv at runtime
    f:write('case "$(uname -s)" in Darwin) _FP_BIN=frankenphp-mac ;; *) _FP_BIN=frankenphp-linux ;; esac\n')
    -- Inject PHP_INI_SCAN_DIR pointing to ini-scan/ which has a symlink to the active ini
    f:write('export PHP_INI_SCAN_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}/phpx/ini-scan"\n')
    f:write('exec mise x "github:php/frankenphp@${PHPX_FRANKENPHP_VERSION:-latest}" -q --raw -- "${_FP_BIN}" php-cli ' .. target .. ' "$@"\n')
    f:close()
    os.execute("chmod +x " .. path)
end

function PLUGIN:BackendInstall(ctx)
    local utils = require("utils")
    local backend = utils.detect_backend(ctx)
    local tool    = utils.get_tool(ctx)

    if backend == "phpx" then
        -- Pre-install FrankenPHP at the pinned version so it's ready at runtime.
        -- Uses github:php/frankenphp to support all versions (incl. pre-1.3.0).
        local cmd = require("cmd")
        local a   = require("aliases")
        local fp_bin = "frankenphp-linux"
        local uname_f = io.popen("uname -s 2>/dev/null")
        if uname_f then
            local uname_s = uname_f:read("*l") or ""
            uname_f:close()
            if uname_s:match("Darwin") then fp_bin = "frankenphp-mac" end
        end
        local fp_version = a.resolve_phpx(ctx.version)
        pcall(function()
            cmd.exec("mise x 'github:php/frankenphp@" .. fp_version .. "' -q --raw -- " .. fp_bin .. " --version")
        end)
        return {}

    elseif backend == "composer" then
        local cmd = require("cmd")
        local a   = require("aliases")
        local package = a.resolve_composer(tool)

        os.execute("mkdir -p " .. ctx.install_path)
        local phar = utils.ensure_composer_phar(cmd)

        local result = cmd.exec(utils.FP .. " " .. phar
            .. " require " .. package .. ":" .. ctx.version
            .. " --working-dir=" .. ctx.install_path .. " --no-interaction --quiet")
        if result and result:match("Your requirements could not") then
            error("Failed to install " .. package .. "@" .. ctx.version)
        end

        local pkg_dir = ctx.install_path .. "/vendor/" .. package
        pcall(function()
            cmd.exec(utils.FP .. " " .. phar
                .. " install --working-dir=" .. pkg_dir .. " --no-interaction --quiet")
        end)

        -- Inject version into vendor package composer.json (Composer strips it at install).
        -- Needed by tools like cpx that read __DIR__/../../composer.json for their version.
        local pkg_json = pkg_dir .. "/composer.json"
        local clean_version = ctx.version:gsub("^v", "")
        pcall(function()
            cmd.exec("python3 -c \"" ..
                "import json; p='" .. pkg_json .. "'; " ..
                "d=json.load(open(p)); d.setdefault('version','" .. clean_version .. "'); " ..
                "open(p,'w').write(json.dumps(d,indent=2))\"")
        end)

        -- Create FrankenPHP wrappers for each vendor/bin script
        local bin_dir = ctx.install_path .. "/bin"
        os.execute("mkdir -p " .. bin_dir)
        local bins = cmd.exec("ls " .. ctx.install_path .. "/vendor/bin/ 2>/dev/null") or ""
        for binary in bins:gmatch("[^\n]+") do
            if binary ~= "" then
                local src  = ctx.install_path .. "/vendor/bin/" .. binary
                local dest = bin_dir .. "/" .. binary
                write_fp_wrapper(dest, src)
            end
        end

        return {}

    elseif backend == "phive" then
        local cmd  = require("cmd")
        local json = require("json")
        local a    = require("aliases")
        local resolved = a.resolve_phive(tool)
        
        -- resolved can be a string (vendor/repo) or table (config with repo, options)
        local repo, config
        if type(resolved) == "table" then
            repo = resolved.repo
            config = resolved
        else
            repo = resolved
            config = {}
        end

        if not repo:match("/") then
            error("PHAR tool must be vendor/repo format or a known alias")
        end

        cmd.exec("mkdir -p " .. ctx.install_path)
        local phar_name = repo:match("([^/]+)$")

        -- Use GitHub API to find the actual PHAR asset URL.
        -- version_prefix controls how ctx.version maps to a release tag.
        -- When nil, probe "v{version}" then bare version (safe default for unknown repos).
        local token   = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        local auth    = token and (" -H 'Authorization: Bearer " .. token .. "'") or ""
        local version_prefix = (ctx.options and ctx.options.version_prefix) or config.version_prefix
        local tags_to_try = version_prefix ~= nil
            and { version_prefix .. ctx.version }
            or  { "v" .. ctx.version, ctx.version }
        local api_ok, api_out, tag_used
        for _, tag in ipairs(tags_to_try) do
            local api_url = "https://api.github.com/repos/" .. repo .. "/releases/tags/" .. tag
            local ok, out = pcall(function()
                return cmd.exec("curl -sL" .. auth .. " '" .. api_url .. "'")
            end)
            if ok and out and out ~= "" then
                local probe = json.decode(out) or {}
                if probe.assets then
                    api_ok, api_out, tag_used = ok, out, tag
                    break
                end
            end
        end
        if not tag_used then tag_used = (version_prefix or "v") .. ctx.version end
        local phar_url  = nil
        local phar_file = nil
        if api_ok and api_out and api_out ~= "" then
            local data = json.decode(api_out) or {}
            if data.assets then
                -- Get options from config and ctx.options (ctx.options take precedence)
                local matching = (ctx.options and ctx.options.matching) or config.matching
                local matching_regex = (ctx.options and ctx.options.matching_regex) or config.matching_regex
                local asset_pattern = (ctx.options and ctx.options.asset_pattern) or config.asset_pattern
                
                -- asset_pattern takes precedence: direct pattern match
                if asset_pattern then
                    for _, asset in ipairs(data.assets) do
                        local name = asset.name or ""
                        -- Simple glob-like pattern matching (* becomes .*)
                        local pattern = asset_pattern:gsub(".", {
                            ["*"] = ".*", ["."] = "%.", ["-"] = "%-",
                            ["+"] = "%%+", ["?"] = "%?"
                        })
                        if name:match("^" .. pattern .. "$") then
                            phar_url  = asset.browser_download_url
                            phar_file = name
                            break
                        end
                    end
                else
                    -- Collect candidates filtered by matching/matching_regex
                    local candidates = {}
                    for _, asset in ipairs(data.assets) do
                        local name = asset.name or ""
                        if name:match("%.phar$") and not name:match("%.asc$") and not name:match("%.sha") then
                            local matches = true
                            if matching and not name:find(matching, 1, true) then
                                matches = false
                            end
                            if matches and matching_regex then
                                local ok, result = pcall(function() return name:match(matching_regex) end)
                                if not ok or not result then matches = false end
                            end
                            if matches then
                                table.insert(candidates, asset)
                            end
                        end
                    end
                    -- Prefer the phar whose name matches the repo name (e.g. php-toolkit.phar
                    -- over blueprints.phar when repo is WordPress/php-toolkit).
                    -- Fall back to the first candidate when no name match is found.
                    local picked = candidates[1]
                    if not matching and not matching_regex then
                        for _, asset in ipairs(candidates) do
                            if (asset.name or ""):match("^" .. phar_name:gsub("%-", "%%-") .. "%.phar$") then
                                picked = asset
                                break
                            end
                        end
                    end
                    if picked then
                        phar_url  = picked.browser_download_url
                        phar_file = picked.name
                    end
                end
            end
        end

        if not phar_url then
            phar_file = phar_name .. ".phar"
            phar_url  = "https://github.com/" .. repo .. "/releases/download/" .. tag_used .. "/" .. phar_file
        end

        local phar_path = ctx.install_path .. "/" .. phar_file
        cmd.exec("curl -sL -o " .. phar_path .. " " .. phar_url)

        local _, stat = pcall(function() return cmd.exec("test -s " .. phar_path .. " && echo ok") end)
        if not (stat and stat:match("ok")) then
            error("Failed to download " .. phar_file .. " from " .. phar_url)
        end

        cmd.exec("chmod +x " .. phar_path)
        
        -- Determine the executable name: rename_exe > bin > tool alias > phar_name
        local rename_exe = (ctx.options and ctx.options.rename_exe) or config.rename_exe
        local bin_config = (ctx.options and ctx.options.bin) or config.bin
        local exe_name = rename_exe or bin_config or tool or phar_name
        
        -- Create a FrankenPHP wrapper instead of a symlink
        write_fp_wrapper(ctx.install_path .. "/" .. exe_name, phar_path)

        return {}

    else
        error("Unknown backend: " .. backend)
    end
end
