# StevesSR Generator Android signing

`app/stevessr-generator-test.keystore` is a committed development-only signing key for this standalone example's release APKs. The key and its password are public by design; they are isolated from FluxDO production credentials and must never be used to sign FluxDO or any production application.

The stable test key lets users install a newer nightly APK over an earlier one. Rotating or replacing this key will break in-place upgrades for APKs signed by the previous key; users would need to uninstall the old app before installing the new one.

The nightly workflow also sets Android `versionCode` from `GITHUB_RUN_NUMBER`, so each run in this workflow has a higher version code than the previous run.
