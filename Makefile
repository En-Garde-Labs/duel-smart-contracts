-include .env

deploy_base_sepolia: forge script script/Deploy.s.sol --force --rpc-url $(BASE_SEPOLIA_RPC_URL)
# deploy_base_mainnet: forge script script/Deploy.s.sol --force --rpc-url $(BASE_MAINNET_RPC_URL)
test_factory: forge test --mc DuelFactoryTest -vvv
test_duel: forge test --mc DuelTest -vvv
test_option: forge test --mc OptionTest -vvv