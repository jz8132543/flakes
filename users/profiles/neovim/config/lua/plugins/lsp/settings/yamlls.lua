return {
    settings = {
        yaml = {
            format = {enable = true},
            schemas = {
                "https://json.schemastore.org/github-workflow.json" = "**/.github/workflows/*.yaml"
            },
            schemaStore = {enable = true}
        }
    }
}
