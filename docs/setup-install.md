# Setup and installation

## Install

Run `make install`. This builds `Markdown Preview.app`, copies it to
`~/Applications`, closing an older running copy before replacement, and asks
Launch Services to register it. Run `make run` to perform the same installation
and then launch the installed app. Finder should then offer **Markdown Preview**
under **Open With** for supported Markdown files.

## Make it the default `.md` application

1. Select an `.md` file in Finder and choose **File > Get Info**.
2. Under **Open with**, select **Markdown Preview**.
3. Click **Change All…** and confirm.

The app intentionally registers as an alternate viewer and does not silently
replace the user's current default.

## Enable Quick Look

The app contains a Quick Look extension. macOS normally discovers it after the
app is installed in `~/Applications` or `/Applications`. If it is disabled,
open **System Settings > General > Login Items & Extensions > Quick Look** and
enable **Markdown Preview**. Finder may take a short time to refresh extension
registration.

The system, not the app, chooses among installed Quick Look providers. The
extension declares Markdown support, but another installed provider or macOS's
own fallback may be selected.
