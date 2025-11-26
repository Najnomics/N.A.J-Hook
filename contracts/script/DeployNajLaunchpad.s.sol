// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {NajLaunchpad} from "@core/NajLaunchpad.sol";
import {NajHook} from "@core/NajHook.sol";
import {Router} from "@core/Router.sol";
import {SwapHandler} from "@utils/SwapHandler.sol";
import {OracleStaticSpreadAdapter} from "@adapters/strategy/OracleStaticSpreadAdapter.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwapHandler} from "@interfaces/ISwapHandler.sol";
import {INajLaunchpad} from "@interfaces/INajLaunchpad.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {HookMiner} from "@script/utils/HookMiner.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract DeployNajLaunchpad is Script {
    address constant POOL_MANAGER = address(0x00B036B58a818B1BC34d502D3fE730Db729e62AC);
    address constant PYTH = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    bytes32 constant ETH_USD_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant ROUTER = 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D;
    address constant TEE = 0x3B4c54f4D909a7b837F9AC6fc1f20BfDE74f3B69;

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    NajLaunchpad najLaunchpad;
    NajHook najHook;
    Router najRouter;
    SwapHandler swapHandler;
    OracleStaticSpreadAdapter strategyAdapter;
    PoolSwapTest swapRouter;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        najLaunchpad = new NajLaunchpad(deployer, POOL_MANAGER);
        najHook = _deployNajHook(deployer);

        najRouter = new Router(POOL_MANAGER);

        swapHandler = new SwapHandler(
            TEE, address(najLaunchpad), address(najHook), POOL_MANAGER, ROUTER, address(najRouter), PERMIT2
        );

        // Set SwapHandler address in Router
        najRouter.setSwapHandler(address(swapHandler));

        strategyAdapter = new OracleStaticSpreadAdapter(PYTH, ETH_USD_PRICE_FEED_ID, true, address(swapHandler));
        swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));

        najLaunchpad.setNajHook(address(najHook));
        najHook.setLaunchpad(address(najLaunchpad));
        najHook.setSwapHandler(address(swapHandler));

        vm.stopBroadcast();

        console2.log("najHook: ", address(najHook));
        console2.log("swapHandler: ", address(swapHandler));
        console2.log("najRouter: ", address(najRouter));
        console2.log("strategyAdapter: ", address(strategyAdapter));
        console2.log("najLaunchpad: ", address(najLaunchpad));
    }

    function _deployNajHook(address owner) internal returns (NajHook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(NajHook).creationCode, abi.encode(POOL_MANAGER, owner));
        hook = new NajHook{salt: salt}(IPoolManager(POOL_MANAGER), owner);
        require(address(hook) == hookAddress, "hook: hook address mismatch");
    }
}
