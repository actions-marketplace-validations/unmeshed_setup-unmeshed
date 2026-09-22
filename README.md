# Setup Unmeshed CLI

Install the Unmeshed CLI in a GitHub Actions job. The action adds `unmeshed` to `PATH` for later steps. It needs no checkout step, secret, or sudo access.

## Quick start

```yaml
name: Use Unmeshed CLI
on: workflow_dispatch

jobs:
  use-unmeshed:
    runs-on: ubuntu-latest
    steps:
      - uses: unmeshed/setup-unmeshed@v1
      - run: unmeshed version
```

Before the `v1` tag is published, use `unmeshed/setup-unmeshed@main`. Use `@v1` after the release.

The latest CLI release is installed by default. To select a published version:

<!-- cli-version-example:start -->
```yaml
- uses: unmeshed/setup-unmeshed@v1
  with:
    version: '1.4.0'
```
<!-- cli-version-example:end -->

## Inputs and outputs

| Name | Type | Description |
| --- | --- | --- |
| `version` | Input | Optional CLI version. Defaults to `latest`. |
| `binary-path` | Output | Absolute path to the installed executable. |

To use the output, give the setup step an `id`, then reference `steps.<id>.outputs.binary-path` in a later step.

## Supported runners

Linux and macOS on x64 and ARM64 are supported. Windows is not supported. The runner needs outbound HTTPS access to Unmeshed's download service.

## Troubleshooting

- **Download or installation failed:** Check the runner's outbound network access. If you set `version`, confirm that release is published.

For a reproducible setup, specify `version`. Pin the action to a commit SHA if your workflow requires an immutable action revision.
