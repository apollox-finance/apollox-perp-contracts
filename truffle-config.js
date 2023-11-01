module.exports = {
    networks: {
        development: {
            host: "127.0.0.1",     // Localhost (default: none)
            port: 9545,            // Standard BSC port (default: none)
            network_id: "*"        // Any network (default: none)
        }
    },

    // Set default mocha options here, use special reporters etc.
    mocha: {
        // timeout: 100000
    },

    plugins: [
        'truffle-plugin-verify',
        'truffle-contract-size'  // truffle run contract-size
    ],
    api_keys: {
        bscscan: ''
    },

    // Configure your compilers
    compilers: {
        solc: {
            version: "0.8.19",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                }
            }
        }
    }
}