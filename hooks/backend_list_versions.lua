function PLUGIN:BackendListVersions(ctx)
    local utils = require("utils")
    local backend = utils.detect_backend(ctx)
    local tool    = utils.get_tool(ctx)

    if backend == "phpx" then
        local cmd  = require("cmd")
        local json = require("json")
        local token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        local auth  = token and (" -H 'Authorization: Bearer " .. token .. "'") or ""

        local result = ""
        local ok, out = pcall(function()
            return cmd.exec("curl -s" .. auth .. " 'https://api.github.com/repos/php/frankenphp/releases?per_page=100'")
        end)
        if ok then result = out or "" end

        local data = {}
        if result ~= "" then data = json.decode(result) or {} end

        local versions = {}
        if type(data) == "table" then
            for _, release in ipairs(data) do
                if release.tag_name and not release.prerelease and not release.draft then
                    table.insert(versions, (release.tag_name:gsub("^v", "")))
                end
            end
        end

        if #versions == 0 then
            return { versions = { "1.12.4" } }
        end
        return { versions = versions }

    elseif backend == "composer" then
        local cmd  = require("cmd")
        local json = require("json")
        local a    = require("aliases")
        local package = a.resolve_composer(tool)

        -- Use Packagist v2 API — no Composer or FrankenPHP needed at list time
        local result = ""
        local ok, out = pcall(function()
            return cmd.exec("curl -sf 'https://repo.packagist.org/p2/" .. package .. ".json'")
        end)
        if ok then result = out or "" end

        local data = {}
        if result ~= "" then data = json.decode(result) or {} end

        local versions = {}
        local pkgs = data.packages and data.packages[package]
        if type(pkgs) == "table" then
            for _, entry in ipairs(pkgs) do
                local v = (entry.version or ""):gsub("^v", "")
                if v ~= "" and not v:match("^dev%-") and not v:match("%-dev$") then
                    table.insert(versions, v)
                end
            end
        end

        if #versions == 0 then
            error("No versions found for " .. package)
        end

        local function semver_lt(a, b)
            local function parts(v)
                local t = {}
                for n in v:gmatch("(%d+)") do t[#t+1] = tonumber(n) end
                return t
            end
            local av, bv = parts(a), parts(b)
            for i = 1, math.max(#av, #bv) do
                local ai, bi = av[i] or 0, bv[i] or 0
                if ai ~= bi then return ai < bi end
            end
            return false
        end
        table.sort(versions, semver_lt)

        return { versions = versions }

    elseif backend == "phive" then
        local cmd  = require("cmd")
        local json = require("json")
        local a    = require("aliases")
        local repo = a.resolve_phive(tool)

        if not repo:match("/") then
            error("PHAR tool must be vendor/repo format or a known alias")
        end

        local token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
        local auth  = token and (" -H 'Authorization: Bearer " .. token .. "'") or ""

        local result = ""
        local ok, out = pcall(function()
            return cmd.exec("curl -s" .. auth .. " 'https://api.github.com/repos/" .. repo .. "/releases?per_page=100'")
        end)
        if ok then result = out or "" end

        local data = {}
        if result ~= "" then data = json.decode(result) or {} end

        local versions = {}
        if type(data) == "table" then
            for _, release in ipairs(data) do
                if release.tag_name and not release.prerelease and not release.draft then
                    table.insert(versions, (release.tag_name:gsub("^v", "")))
                end
            end
        end

        if #versions == 0 then
            error("No releases found for " .. repo)
        end

        -- Sort semver ascending (oldest → newest) so mise resolves latest = last = highest.
        local function semver_lt(a, b)
            local function parts(v)
                local t = {}
                for n in v:gmatch("(%d+)") do t[#t+1] = tonumber(n) end
                return t
            end
            local av, bv = parts(a), parts(b)
            for i = 1, math.max(#av, #bv) do
                local ai, bi = av[i] or 0, bv[i] or 0
                if ai ~= bi then return ai < bi end
            end
            return false
        end
        table.sort(versions, semver_lt)

        return { versions = versions }

    else
        error("Unknown backend: " .. backend)
    end
end
