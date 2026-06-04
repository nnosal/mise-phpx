-- Maps phpx:phpx version aliases → FrankenPHP version refs understood by the github backend.
-- Keep in sync with bin/list-aliases.
-- Note: no stable FrankenPHP release ships PHP 8.2 (1.0.0 already ships PHP 8.3.0).
local PHPX = {
    ["php8.3"] = "1.2.5",
    ["php8.4"] = "1.11.2",
    ["php8.5"] = "1.11.3",
}

local COMPOSER = {
    ["cpx"]          = "cpx/cpx",
    ["laravel"]      = "laravel/installer",
    ["php-cs-fixer"] = "friendsofphp/php-cs-fixer",
    ["phpunit"]      = "phpunit/phpunit",
    ["psalm"]        = "vimeo/psalm",
    ["phpstan"]      = "phpstan/phpstan",
    ["psysh"]        = "psy/psysh",
}

local PHIVE = {
    ["pie"]      = "php/pie",
    ["phive"]    = "phar-io/phive",
    ["composer"] = "composer/composer",
}

local function resolve_composer(tool)
    if not tool or tool == "" then return tool end
    if not tool:match("/") then return COMPOSER[tool] or tool end
    return tool
end

local function resolve_phive(tool)
    return PHIVE[tool] or tool
end

local function resolve_phpx(version)
    return PHPX[version] or version
end

return {
    PHPX = PHPX,
    COMPOSER = COMPOSER,
    PHIVE = PHIVE,
    resolve_phpx = resolve_phpx,
    resolve_composer = resolve_composer,
    resolve_phive = resolve_phive,
}
