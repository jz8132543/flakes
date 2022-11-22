return {
    settings = {
        rnix = {
            name = 'rnix-lsp',
            cmd = {server_info->[&shell, &shellcmdflag, 'rnix-lsp']},
            whitelist: ['nix'],
        },
    },
}

