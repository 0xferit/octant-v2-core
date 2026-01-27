# Environment variables used in scripts

## Scripts

| Environment variable               | Description                                                                                                          |
|------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| `DRAGON_ROUTER`                    |                                                                                                                      |
| `GOVERNANCE`                       | Address of the governance controller for Split Checker (default: contract creator)                                   |
| `KEEPER`                           |                                                                                                                      |
| `MANAGEMENT`                       |                                                                                                                      |
| `MAX_OPEX_SPLIT`                   |                                                                                                                      |
| `MIN_METAPOOL_SPLIT`               |                                                                                                                      |
| `MODULE`                           |                                                                                                                      |
| `MODULE_FACTORY`                   |                                                                                                                      |
| `OWNER`                            |                                                                                                                      |
| `PRIVATE_KEY`                      | Private key of wallet deploying contracts                                                                            |
| `SAFE_ADDRESS`                     |                                                                                                                      |
| `SAFE_DRAGON_VAULT_MODULE_ADDRESS` |                                                                                                                      |
| `SAFE_PROXY_FACTORY`               | Address of Safe proxy factory (can be found in `safe_proxy_factory.json` stored on github [Safe addresses])          |
| `SAFE_OWNER{1..n}`                 |                                                                                                                      |
| `SAFE_SINGLETON`                   | Address of Safe contract singleton (can be found in `safe.json` or `safe_l2.json` stored on github [Safe addresses]) |
| `SAFE_THRESHOLD`                   | Safe's threshold (number of approvals required to execute a transaction)                                             |
| `SAFE_TOTAL_OWNERS`                |                                                                                                                      |
| `TOKEN`                            |                                                                                                                      |
| `TOTAL_VALIDATORS`                 |                                                                                                                      |
| `TREASURY`                         |                                                                                                                      |

## Tests

### Mainnet

| Environment variable      | Description                        |
|---------------------------|------------------------------------|
| `TEST_RPC_URL`            | URL of RPC endpoint                |
| `TEST_SAFE_PROXY_FACTORY` | Address of Safe proxy factory      |
| `TEST_SAFE_SINGLETON`     | Address of Safe contract singleton |

### Polygon

| Environment variable              | Description                        |
|-----------------------------------|------------------------------------|
| `TEST_RPC_URL_POLYGON`            | URL of RPC endpoint                |
| `TEST_SAFE_PROXY_FACTORY_POLYGON` | Address of Safe proxy factory      |
| `TEST_SAFE_SINGLETON_POLYGON`     | Address of Safe contract singleton |


[Safe addresses]: https://github.com/safe-global/safe-deployments/tree/main/src/assets
