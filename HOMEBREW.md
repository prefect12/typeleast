# Typeleast Homebrew Tap

Typeleast is distributed through the `prefect12/tap` Homebrew tap.

## User Install

```bash
brew tap prefect12/tap
brew install typeleast
open -a Typeleast
```

Update or uninstall:

```bash
brew update
brew upgrade typeleast

brew uninstall typeleast
brew untap prefect12/tap
```

## Maintainer Setup

The tap repository is expected as a sibling checkout:

```bash
cd ..
git clone https://github.com/prefect12/homebrew-tap.git
```

The Typeleast cask lives at:

```text
../homebrew-tap/Casks/typeleast.rb
```

Required tools:

```bash
brew install gh jq
gh auth login
```

## Publish Flow

1. Update `VERSION`.
2. Build and package the app:

```bash
make build
ditto -c -k --keepParent Typeleast.app Typeleast.zip
```

3. Create a GitHub release for the matching tag and upload `Typeleast.zip`.
4. Update the cask:

```bash
make update-brew-cask
```

5. Review and publish the tap change:

```bash
cd ../homebrew-tap
git diff Casks/typeleast.rb
git add Casks/typeleast.rb
git commit -m "Update Typeleast to v$(cat ../typeleast/VERSION)"
git push
```

Alternatively, from the Typeleast repo:

```bash
make publish-brew-cask
```

## Local Cask Test

Before publishing, install the cask file directly:

```bash
brew install --cask --force ../homebrew-tap/Casks/typeleast.rb
open -a Typeleast
brew uninstall typeleast
```

## Troubleshooting

- `homebrew-tap repository not found`: clone `https://github.com/prefect12/homebrew-tap.git` as `../homebrew-tap`, or set `TAP_REPO`.
- `Typeleast.zip not found`: upload the release asset before running `make update-brew-cask`.
- Checksum mismatch: regenerate the release zip, recreate the release asset, and rerun the cask update.
