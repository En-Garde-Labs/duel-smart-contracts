-include .env

deploy_duel_base_sepolia:; forge script script/DeployDuel.s.sol --force --rpc-url $(BASE_SEPOLIA_RPC_URL) --via-ir

deploy_factory_base_sepolia:; forge script script/DeployFactory.s.sol --force --rpc-url $(BASE_SEPOLIA_RPC_URL) --via-ir

deploy_duel_base_mainnet:; forge script script/DeployDuel.s.sol --force --rpc-url $(BASE_MAINNET_RPC_URL)

deploy_factory_base_mainnet:; forge script script/DeployFactory.s.sol --force --rpc-url $(BASE_MAINNET_RPC_URL)

test_factory:; forge test --mc DuelFactoryTest -vvv

test_duel:; forge test --mc DuelTest -vvv

test_option:; forge test --mc OptionTest -vvv