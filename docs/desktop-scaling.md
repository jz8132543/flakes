# Desktop Scaling on Wayland and Xwayland

## Configuration

Desktop hosts set `environment.desktop.dpi` in their host module. It is a logical DPI value with a 96-DPI baseline, not a compositor output scale:

- `arx8`: 144 DPI for its 1.5x output scale.
- `surface`: 192 DPI for its 2x output scale.

The shared desktop module forwards this value to Home Manager's `wayland.dpi`, which writes the Xft DPI resource and supplies the existing desktop compatibility hints. Umbriel separately advertises the active output scale to Xwayland through XSETTINGS. Keep `xwayland_native_resolution = true` to let X11 clients render against the physical output resolution instead of relying on compositor bitmap upscaling.

## WPS and Qt

The configured WPS package uses Fcitx's XIM frontend (`QT_IM_MODULE=xim`, `XMODIFIERS=@im=fcitx`) because WPS ships a private Qt 5.12/XCB runtime and its bundled Fcitx Qt platform plugin can create competing X11 input contexts. The package disables Qt's automatic high-DPI handling only for WPS. Its Qt scale factors remain at 1, while `QT_FONT_DPI` is taken from `WPS_QT_FONT_DPI`, derived from the host's `environment.desktop.dpi`. This avoids applying a global `QT_SCALE_FACTOR` to native Wayland Qt applications, which could double-scale them.

`QT_FONT_DPI` scales Qt text and DPI-aware widget metrics; it does not guarantee that every proprietary WPS icon or fixed-size control follows the same scale. If a WPS release handles the Ribbon, icons, or dialogs incorrectly, test that release separately before changing the package wrapper. Do not compensate by setting a global Qt scale factor.

## Limitations

X11 toolkits do not all use DPI and XSETTINGS in the same way. GTK's XSETTINGS window scale is integer-valued; fractional font DPI can still be advertised, but that does not make every GTK3 control scale fractionally. Applications that ignore both XSETTINGS and `Xft.dpi` may need an application-specific setting or a native Wayland backend.

This configuration is declarative and takes effect for newly launched applications after the desktop session is restarted. Validate visual sizing in the actual application; evaluating the Nix options alone does not prove every toolkit honors the hints.
