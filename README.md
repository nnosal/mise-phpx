# mise-phpx

A [mise](https://mise.jdx.dev) plugin providing a zero-dependency PHP toolchain built on [FrankenPHP](https://frankenphp.dev). No system PHP required. It's like npx, uvx, bunx but for modern php (8.3+) 😎.

But that's not all, it allows you to install any PHAR CLI tool (like [composer](https://github.com/composer/composer)) directly from GitHub Releases — and any Composer package from [Packagist](https://packagist.org/). All tools execute under FrankenPHP, with no system PHP required.

## Backends

The plugin exposes three backends under a single `phpx` plugin name:

| Backend    | Tool syntax              | What it does                                                             |
| ---------- | ------------------------ | ------------------------------------------------------------------------ |
| `phpx`     | `phpx:phpx`              | FrankenPHP-backed CLI: PHP runner, built-in server, composer, extensions |
| `composer` | `phpx:composer:<pkg>`    | Composer packages installed and executed via FrankenPHP                  |
| `phive`    | `phpx:phive:<tool>`      | PHAR tools from GitHub Releases, wrapped via FrankenPHP                  |

## Getting started

```bash
# 1. Link the plugin once
mise plugin link phpx ./mise-phpx

# 2. Declare tools in your project
cat > mise.toml <<'EOF'
[tools]
"phpx:phpx"           = "php8.5"   # PHP 8.5 via FrankenPHP
"phpx:composer:cpx"   = "1.0.0"    # cpx alias for packagist "cpx/cpx" (composer package runner)
"phpx:phive:pie"      = "1.4.4"    # pie (PHP extension installer)
"phpx:phive:composer" = "2.8.9"    # specific version of composer for your project
EOF

# 3. Install everything
mise install

# 4. Use it
phpx --version          # PHP 8.5.x (FrankenPHP 1.11.3)
phpx -r 'echo 42;'      # Run PHP code
cpx laravel/laravel .   # Scaffold a Laravel project
```

All tools share the same FrankenPHP version — changing `phpx:phpx` upgrades PHP for `cpx`, `pie`, and every other declared tool at once.

## Installation

The most simple: `mise plugins install https://github.com/nnosal/mise-phpx.git`

But for developpement, you can link the plugin locally, then declare your tools in `mise.toml`:

```bash
git clone https://github.com/nnosal/mise-phpx
mise plugin link phpx ./mise-phpx
```

```toml
[tools]
"phpx:phpx"           = "php8.5"
"phpx:composer:cpx"   = "1.0.2"
"phpx:phive:pie"      = "1.4.4"
```

```bash
mise install
```

## Version aliases

`phpx:phpx` accepts PHP minor version aliases so you can track a PHP generation without pinning a specific FrankenPHP release:

| Alias    | FrankenPHP | PHP bundled |
| -------- | ---------- | ----------- |
| `php8.3` | `1.2.5`    | PHP 8.3.x   |
| `php8.4` | `1.11.2`   | PHP 8.4.x   |
| `php8.5` | `1.11.3`   | PHP 8.5.x   |
| `latest` | `latest`   | PHP 8.5.x+   |

> **Note:** no stable FrankenPHP release ships PHP 8.2 — `1.0.0` already bundles PHP 8.3.0.

Exact versions are also accepted: `"phpx:phpx" = "1.4.4"`.

To list all available versions and aliases:

```bash
mise ls-remote phpx:phpx
```

## Usage

### phpx — PHP runner

`phpx` is a drop-in PHP CLI backed by FrankenPHP:

```bash
phpx script.php                    # Execute a file
phpx -r 'echo phpversion();'       # Run inline code
phpx -S localhost:8000             # Start built-in web server
phpx -a                            # Interactive shell (psysh)
phpx console                       # Alias for interactive shell
phpx composer install              # Run Composer
phpx -x install asgrim/example-pie-extension  # Compile & install a PIE extension
phpx -x list                                   # List installed extensions
phpx --version                                 # Show PHP + FrankenPHP + Caddy versions
```

`phpx -x install` uses [PIE](https://github.com/php/pie), a system `phpize`, and auto-registers the extension in `~/.local/share/mise/phpx/extensions.ini` — loaded automatically on every `phpx` invocation via `PHP_INI_SCAN_DIR`.

> **Requirement:** `phpize` on your system must match FrankenPHP's thread-safety mode (ZTS). FrankenPHP ships as ZTS; Homebrew PHP is NTS. Pre-built binaries provided by the package bypass this constraint.

Override the FrankenPHP version for a single invocation:

```bash
phpx frankenphp@1.4.0 -r 'echo "hello";'
```

### composer — Composer packages

Install globally available Composer tools:

```toml
[tools]
"phpx:composer:phpstan" = "2.1.0"
"phpx:composer:cpx"     = "1.0.2"
```

Built-in short aliases: `cpx`, `laravel`, `php-cs-fixer`, `phpunit`, `psalm`, `phpstan`, `psysh`.

Any `vendor/package` form also works:

```toml
[tools]
"phpx:composer:my-org/my-tool" = "1.2.3"
```

### phive — PHAR tools

Fetches PHAR assets directly from GitHub Releases (curl only — no phive binary required). Every installed PHAR runs under FrankenPHP, not the host PHP.

```toml
[tools]
"phpx:phive:pie"          = "1.4.4"
"phpx:phive:phive"        = "0.15.2"
"phpx:phive:composer"     = "2.8.9"
"phpx:phive:wp-blueprint" = "0.8.1"   # WordPress/php-toolkit → blueprints.phar
```

Built-in aliases:

| Alias          | GitHub repo             | Installed as    |
| -------------- | ----------------------- | --------------- |
| `pie`          | `php/pie`               | `pie`           |
| `phive`        | `phar-io/phive`         | `phive`         |
| `composer`     | `composer/composer`     | `composer`      |
| `wp-blueprint` | `WordPress/php-toolkit` | `wp-blueprint`  |

Any `vendor/repo` form also works directly:

```toml
[tools]
"phpx:phive:my-org/my-tool" = "1.0.0"
```

#### PHAR selection

When a release ships multiple `.phar` files the plugin picks the one whose filename matches the repo name (e.g. `php-toolkit.phar` for `WordPress/php-toolkit`). If no name match is found the first `.phar` in the asset list is used. Provide `asset_pattern`, `matching`, or `matching_regex` to override this.

#### Options

These options follow the [mise GitHub backend](https://mise.jdx.dev/dev-tools/backends/github.html) naming conventions. They can be passed inline in `mise.toml`:

```toml
[tools]
"phpx:phive:my-org/my-tool" = { version = "1.0.0-beta.1", version_prefix = "v", prerelease = "true" }
```

| Option           | Default    | Description |
| ---------------- | ---------- | ----------- |
| `version_prefix` | auto-probe | Prefix prepended to the version to form the GitHub release tag. `"v"` maps version `1.2.3` → tag `v1.2.3`. When unset, the plugin probes `v{version}` then bare `{version}` automatically. |
| `prerelease`     | `false`    | Include pre-release GitHub releases when listing versions with `mise ls-remote`. |
| `asset_pattern`  | —          | Glob pattern the asset filename must match exactly (e.g. `blueprints.phar`). Takes precedence over `matching`. |
| `matching`       | —          | Plain-text substring the asset filename must contain. |
| `matching_regex` | —          | Lua pattern the asset filename must match. |
| `rename_exe`     | —          | Name for the generated wrapper script. Priority: `rename_exe` > `bin` > alias name > repo name. |
| `bin`            | —          | Alternate exe name (lower priority than `rename_exe`). |

## Common workflows

**Run a one-off PHP script**
```bash
phpx my-script.php
phpx -r 'var_dump(PHP_VERSION);'
```

**Laravel / Symfony project**
```toml
[tools]
"phpx:phpx"              = "php8.5"
"phpx:composer:laravel"  = "5.11.0"   # laravel/installer
```
```bash
mise install
laravel new my-app
cd my-app && phpx -S localhost:8000 -t public
```

**Run Composer inside a project**
```bash
phpx composer install
phpx composer require vendor/package
```

**Run phpstan or phpunit declared as tools**
```toml
[tools]
"phpx:composer:phpstan" = "2.1.0"
"phpx:composer:phpunit" = "11.0.0"
```
```bash
mise install
phpstan analyse src/
phpunit tests/
```

**Install a PHP extension**
```bash
phpx -x install asgrim/example-pie-extension
# Extension auto-registered in ~/.local/share/mise/phpx/extensions.ini
# Loaded automatically on next phpx invocation
```

**Pin a version per project, use an alias globally**

In your project's `mise.toml`, pin to a specific FrankenPHP version for reproducibility:
```toml
"phpx:phpx" = "1.11.3"
```

In your global `~/.config/mise/config.toml`, use an alias for convenience:
```toml
"phpx:phpx" = "php8.5"
```

**Upgrade PHP**

Change the alias or version in `mise.toml`, then:
```bash
mise install
```
All composer and phive tools are automatically upgraded to the new PHP version — no reinstall needed.

**Verify all tools use the same PHP**
```bash
phpx --version    # shows active FrankenPHP + PHP
cpx --version     # should report the same PHP
```

## FrankenPHP version coordination

All three backends share the same FrankenPHP version at runtime. When `phpx:phpx` is active, mise injects `PHPX_FRANKENPHP_VERSION` into the environment. The `composer` and `phive` wrappers read this variable, so `cpx`, `phpstan`, `pie`, etc. always run on the same PHP version as `phpx`.

```
phpx:phpx = "php8.5"
    └─ BackendExecEnv injects PHPX_FRANKENPHP_VERSION=1.11.3
           ├─ phpx  → github:php/frankenphp@1.11.3
           ├─ cpx   → github:php/frankenphp@1.11.3
           └─ pie   → github:php/frankenphp@1.11.3
```

If `phpx:phpx` is not declared, wrappers fall back to `latest`.

## Configuration

### GitHub token (recommended for CI)

The `phive` and `phpx` backends query the GitHub Releases API, rate-limited to 60 requests/hour unauthenticated. Set a token to avoid failures in CI or on shared machines:

```bash
export GITHUB_TOKEN=ghp_...   # or GH_TOKEN
```

## How it works

When mise installs a `phpx:*` tool it:

1. Detects the backend from the tool name prefix (`phpx`, `composer`, or `phive`).
2. Resolves version aliases (`php8.5` → `1.11.3`) before any FrankenPHP interaction.
3. Downloads FrankenPHP via `github:php/frankenphp@<version>` — supports all versions back to `1.0.0`.
4. For `composer`: downloads `composer.phar` once into `$MISE_DATA_DIR/phpx/` and uses it via FrankenPHP — no system Composer needed.
5. For `phive`: fetches the PHAR asset URL from the GitHub Releases API, falls back to the conventional download URL.
6. Generates a `#!/usr/bin/env bash` wrapper in the tool's `bin/` that calls `github:php/frankenphp@${PHPX_FRANKENPHP_VERSION:-latest}` directly, so binaries are available without a PHP environment.
7. Exposes wrappers via `PATH` through mise's `BackendExecEnv`.

## Requirements

- [mise](https://mise.jdx.dev) ≥ 2025.1
- `curl` and `python3` in `PATH`
- FrankenPHP — fetched automatically from GitHub Releases on first use

## License

MIT
