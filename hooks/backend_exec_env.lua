function PLUGIN:BackendExecEnv(ctx)
    local utils = require("utils")
    local backend = utils.detect_backend(ctx)
    local tool    = utils.get_tool(ctx)

    local file = require("file")

    if backend == "phpx" then
        local a = require("aliases")
        return {
            env_vars = {
                { key = "PHPX_FRANKENPHP_VERSION", value = a.resolve_phpx(ctx.version) }
            },
            exec_path = file.join_path(os.getenv("MISE_PLUGIN_DIR"), "bin", "phpx")
        }

    elseif backend == "composer" then
        -- Wrappers created during install call frankenphp directly
        return {
            env_vars = {
                { key = "PATH", value = file.join_path(ctx.install_path, "bin") }
            }
        }

    elseif backend == "phive" then
        -- Wrapper created during install calls frankenphp directly; expose via PATH
        return {
            env_vars = {
                { key = "PATH", value = ctx.install_path }
            }
        }

    else
        return { env_vars = {} }
    end
end
