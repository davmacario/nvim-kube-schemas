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

## Installation

Requires Neovim >= 0.11, [plenary.nvim](https://github.com/nvim-lua/plenary.nvim), and
a running [yaml-language-server](https://github.com/redhat-developer/yaml-language-server).

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

## Documentation

The full documentation lives in the help file, which is the single source of truth for
this plugin's behaviour:

```vim
:help nvim-kube-schemas
```

If you are reading on GitHub, the same content is in
[`doc/nvim-kube-schemas.txt`](./doc/nvim-kube-schemas.txt). Jump straight to:

| Topic                                        | Help tag                               |
| -------------------------------------------- | -------------------------------------- |
| Requirements                                 | `:help nvim-kube-schemas-requirements` |
| Configuration options and defaults           | `:help nvim-kube-schemas-config`       |
| Usage and per-buffer state                   | `:help nvim-kube-schemas-usage`        |
| Commands                                     | `:help nvim-kube-schemas-commands`     |
| Lua API                                      | `:help nvim-kube-schemas-api`          |
| How schemas are resolved, cached and fetched | `:help nvim-kube-schemas-internals`    |

## Credits

This plugin started out as an improvement to the code included in [this post](https://www.reddit.com/r/neovim/comments/1iykmqc/improving_kubernetes_yaml_support_in_neovim_crds/)

Schemas come from two excellent community projects:

- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
- [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema)

## License

[MIT](./LICENSE)
