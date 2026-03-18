# WPS 公文模板目录

将外部现成模板放到本目录，文件名固定为：

- `newfile.docx`
- `newfile.xlsx`
- `newfile.pptx`

在本仓库中，`lib/overlays.nix` 会把这 3 个文件通过 overlay 覆盖到
`nur.repos.fym998.wpsoffice-cn-fcitx` 的模板目录：

- `/opt/kingsoft/wps-office/templates/`
- `/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/`

同时会修正 `share/templates/*.desktop` 的 `URL=` 指向。

## 建议

优先使用你已验证过的“党政机关公文格式”模板原件，避免自行二次制作。
