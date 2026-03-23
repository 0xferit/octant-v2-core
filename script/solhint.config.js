const rootConfig = require("../.solhint.json");

module.exports = {
    ...rootConfig,
    excludedFiles: [
        ...(rootConfig.excludedFiles || []),
        "./script/helpers/vendor/**/*.sol",
        "script/helpers/vendor/**/*.sol",
    ],
    rules: {
        ...rootConfig.rules,
        "no-console": "off",
        "no-global-import": "off",
        quotes: "off",
    },
};
