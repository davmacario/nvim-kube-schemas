# nvim-kube-schemas

![Neovim](https://img.shields.io/badge/Neovim-%3E%3D%200.11-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Made%20with-Lua-2C2D72?logo=lua&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

Neovim plugin to automatically fetch and use YAML schemas for Kubernetes resources, consumed by Yaml-Language-Server.

## Features

- Detects the `apiVersion` and `kind` of the manifest you are editing and attaches the matching JSON schema to `yamlls` - no manual `yaml.schemas` wiring.
- Resolves Custom Resource Definitions from the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog), covering hundreds of operators (Argo CD, Cert-Manager, Prometheus, Traefik, ...).
- Falls back to the built-in Kubernetes resource schemas from [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema).
- Caches every schema on disk, so after the first fetch completion and validation work offline.
- Remembers misses too, so unknown resources are not re-requested on every buffer.

## Requirements

- Neovim >= 0.11
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server), running and attached to the buffer. The LSP client must be named `yamlls` (the default for `vim.lsp.config` and `nvim-lspconfig`) - the plugin does nothing on buffers without it.
- `curl` available on your `$PATH`
- Network access to `api.github.com` and `raw.githubusercontent.com`, for the first fetch of each schema

## Installation

With [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "davmacario/nvim-kube-schemas",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
        -- User config
    }
}
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
    "davmacario/nvim-kube-schemas",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
        require("nvim-kube-schemas").setup({
            -- User config
        })
    end,
})
```

> [!NOTE]
>
> `setup()` has to run for the plugin to do anything - the `plugin/` file is only a load
> guard. Lazy.nvim calls it for you as soon as `opts` is present (even if empty).

## Configuration

These are the defaults; pass any subset of them to `setup()`/`opts`.

```lua
require("nvim-kube-schemas").setup({
    enabled = true,
    cache_root = vim.fs.joinpath(vim.fn.stdpath("data"), "yaml-schemas"),
    augroup = nil,
    pattern = { "*.yaml", "*.yml" },
})
```

| Option       | Type               | Default                                                   | Description                                                                                                                                                                              |
| ------------ | ------------------ | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enabled`    | `boolean`          | `true`                                                    | Set to `false` to disable the plugin. The autocmd is not created, but `:NvimKubeSchemasClearCache` stays available so you can still reclaim the disk space.                              |
| `cache_root` | `string`           | `vim.fs.joinpath(vim.fn.stdpath("data"), "yaml-schemas")` | Directory where schemas are cached. Created recursively during `setup()`; setup aborts if it cannot be created.                                                                          |
| `pattern`    | `string[]`         | `{ "*.yaml", "*.yml" }`                                   | Autocmd pattern. Should match the files where `yamlls` is active.                                                                                                                        |
| `augroup`    | `string\|integer?` | `nil`                                                     | Autocmd group owning the autocmd. `nil` creates a `NvimKubeSchemas` group (cleared on reload); a string creates a group without clearing it; an integer is used as an existing group id. |

Options are merged shallowly over the defaults, and a second call to `setup()` is a no-op.

## Usage

There is nothing to invoke. Open a Kubernetes manifest in a buffer where `yamlls` is
attached, and the plugin resolves and attaches the schema in the background. On success it
reports the schema it picked:

```text
Attached schema: Kubernetes schema for Deployment
Attached schema: CRD schema for argoproj.io/application_v1alpha1.json
```

If the buffer has no top-level `apiVersion`/`kind`, or no schema exists for the resource,
it notifies you once and leaves `yamlls` on its default configuration:

```text
No CRD or Kubernetes schema found. Falling back to default LSP configuration.
```

Each buffer is only inspected once per session. The state is tracked in the buffer
variables `b:schema_attached`, `b:schema_pending` and `b:schema_checked`.

## Commands

| Command                       | Description                                                                                                 |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `:NvimKubeSchemasClearCache`  | Delete every cached schema. Asks for confirmation first (defaults to _No_, since it is a recursive delete). |
| `:NvimKubeSchemasClearCache!` | Same, without the confirmation prompt.                                                                      |

Clearing the cache also resets the per-buffer state, so open buffers re-fetch their schema
on the next `BufEnter`.

## API

```lua
local kube_schemas = require("nvim-kube-schemas")

kube_schemas.setup(opts)                   -- configure the plugin
kube_schemas.clear_cache({ force = true }) -- delete the cache; `force` skips the prompt
kube_schemas.get_config()                  -- current, merged configuration
```

## How it works

1. An autocmd on `LspAttach` and `BufEnter` fires for every file matching `pattern`, and
   only proceeds if a client named `yamlls` is attached to the buffer.
2. The buffer is scanned for top-level `apiVersion:` and `kind:` keys.
3. The CRD catalog is tried first. `apiVersion`/`kind` are normalized into a
   `<group>/<kind>_<version>.json` path (for example `argoproj.io/application_v1alpha1.json`)
   and looked up against a cached listing of the catalog's git tree.
4. If no CRD matches, the built-in Kubernetes schemas are tried, first as
   `<kind>-<version>.json` and then as `<kind>.json`.
5. The schema is downloaded into the cache, and its **local path** is registered in the
   `yaml.schemas` map of the running `yamlls` client, which is then notified with
   `workspace/didChangeConfiguration`. Schemas are always served to the language server
   from disk, never from a URL.

All network work happens on a coroutine, so the editor is never blocked.

### Cache layout

```text
<cache_root>/
├── crds/<group>/<kind>_<version>.json  # CRD schemas
├── k8s/<kind>-<version>.json           # built-in Kubernetes resource schemas
├── crd-tree.json                       # CRD catalog listing (refreshed daily)
└── meta.json                           # record of known misses (kept for 7 days)
```

Writes are atomic: each file is written to a temporary name and then renamed into place.

### Network behaviour

Requests time out after 4 seconds. After any failed request, all network access is skipped
for 60 seconds, so a flaky or absent connection does not add latency to every buffer you
open.

## Limitations

- Only the **first** document of a multi-document YAML file is inspected; the resulting
  schema is applied to the whole file.
- Only top-level `apiVersion`/`kind` keys are matched.
- Cached schema files never expire. Run `:NvimKubeSchemasClearCache` to pull fresh copies.
- Files without a top-level `apiVersion`/`kind` - Kustomize overlays, un-rendered Helm
  templates - are skipped.
- The CRD catalog listing is fetched from the GitHub API unauthenticated, which is subject
  to a 60 requests/hour per-IP limit. The daily cache makes this a non-issue in practice.

## Credits

Schemas come from two excellent community projects:

- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
- [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema)

## License

[MIT](./LICENSE)
