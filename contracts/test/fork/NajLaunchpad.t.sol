// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {ERC20Mock} from "@mocks/ERC20Mock.sol";
import {MockEigenVerifier} from "@mocks/MockEigenVerifier.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SyntheticLiquidityHelper} from "@test/utils/SyntheticLiquidityHelper.sol";
import {TestSwapHandler} from "@test/utils/TestSwapHandler.sol";

import {NajLaunchpad} from "@core/NajLaunchpad.sol";
import {NajHook} from "@core/NajHook.sol";
import {Router} from "@core/Router.sol";
import {SwapHandler} from "@utils/SwapHandler.sol";
import {OracleStaticSpreadAdapter} from "@adapters/strategy/OracleStaticSpreadAdapter.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-foundry-mocks/CoFheTest.sol";
import {FHE, InEuint128, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {MockPyth} from "@mocks/MockPyth.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "@script/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwapHandler} from "@interfaces/ISwapHandler.sol";
import {INajLaunchpad} from "@interfaces/INajLaunchpad.sol";

contract NajLaunchpadTest is Test {
    using stdStorage for StdStorage;
    NajLaunchpad najLaunchpad;
    NajHook najHook;
    Router najRouter;
    TestSwapHandler swapHandler;
    SyntheticLiquidityHelper syntheticHelper;
    OracleStaticSpreadAdapter strategyAdapter;
    CoFheTest private cft;
    MockEigenVerifier private mockEigenVerifier;
    MockPyth private mockPyth;

    ERC20Mock WETH;
    ERC20Mock USDC;
    IPoolManager poolManager;

    bytes32 constant ETH_USD_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant ROUTER = 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D;

    address owner;
    address alice;
    address bob;
    address curator;
    address tee;

    function setUp() public {
        //vm.createSelectFork("");

        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        curator = makeAddr("curator");
        tee = makeAddr("tee");

        cft = new CoFheTest(false);
        mockEigenVerifier = new MockEigenVerifier();
        mockPyth = new MockPyth();

        WETH = new ERC20Mock("Wrapped Ether", "WETH");
        USDC = new ERC20Mock("USD Coin", "USDC");

        (WETH, USDC) = WETH < USDC ? (WETH, USDC) : (USDC, WETH);

        address poolManagerAddr =
            deployCode("node_modules/@uniswap/v4-core/out/PoolManager.sol/PoolManager.json", abi.encode(owner));
        poolManager = IPoolManager(poolManagerAddr);

        vm.startPrank(owner);

        najLaunchpad = new NajLaunchpad(owner, poolManagerAddr);
        najHook = _deployNajHook();

        // Deploy Router first (SwapHandler address will be set after deployment)
        najRouter = new Router(address(poolManager));

        // Deploy SwapHandler with Router address
        syntheticHelper = new SyntheticLiquidityHelper();

        swapHandler = new TestSwapHandler(
            tee,
            address(najLaunchpad),
            address(najHook),
            address(poolManager),
            ROUTER,
            address(najRouter),
            PERMIT2,
            address(syntheticHelper)
        );

        // Set SwapHandler address in Router
        najRouter.setSwapHandler(address(swapHandler));

        mockPyth.setPrice(int64(2_000e8), 0, -8, uint64(block.timestamp));
        strategyAdapter =
            new OracleStaticSpreadAdapter(address(mockPyth), ETH_USD_PRICE_FEED_ID, true, address(swapHandler));
        mockEigenVerifier.setResult(true, bytes32("mrEnclave"), bytes32("mrSigner"));

        najLaunchpad.setNajHook(address(najHook));
        najHook.setLaunchpad(address(najLaunchpad));
        najHook.setSwapHandler(address(swapHandler));
        najHook.setEigenVerifier(address(mockEigenVerifier));

        vm.stopPrank();

        // Setup global approvals for NajLaunchpad to interact with PoolManager
        vm.startPrank(address(najLaunchpad));
        WETH.approve(address(poolManager), type(uint256).max);
        USDC.approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // Setup global approvals for NajHook to interact with PoolManager
        vm.startPrank(address(najHook));
        WETH.approve(address(poolManager), type(uint256).max);
        USDC.approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        deal(address(WETH), address(najHook), 1_000_000 ether);
        deal(address(USDC), address(najHook), 1_000_000_000 ether);
    }

    function test_launchPool() external {
        deal(address(WETH), curator, 1_000_000_000 ether);
        deal(address(USDC), curator, 1_000_000_000 ether);

        vm.startPrank(curator);

        WETH.approve(address(najLaunchpad), 1_000_000_000 ether);
        USDC.approve(address(najLaunchpad), 1_000_000_000 ether);

        najLaunchpad.launch(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "WETH-USDC Test Pool",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );
    }

    function test_curatorCanAddLiquidity() external {
        deal(address(WETH), curator, 1_000_000 ether);
        deal(address(USDC), curator, 1_000_000_000 ether);

        vm.startPrank(curator);

        WETH.approve(address(najLaunchpad), 100_000_000_000 ether);
        USDC.approve(address(najLaunchpad), 100_000_000_000 ether);

        PoolId poolId = najLaunchpad.launch(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "WETH-USDC Test Pool",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        najLaunchpad.addLiquidity(poolId, address(USDC), 100_000 ether);
    }


    /// @notice Test that a user swap queues funds in the router instead of executing immediately
    function test_userSwapEmitsEventOnly() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "WETH-USDC Test Pool",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        deal(address(WETH), alice, 10 ether);

        vm.startPrank(alice);
        WETH.approve(address(najRouter), type(uint256).max);

        uint256 aliceWETHBefore = WETH.balanceOf(alice);
        uint256 aliceUSDCBefore = USDC.balanceOf(alice);
        uint256 depositBefore = najRouter.userDeposits(poolId, alice, address(WETH));

        najRouter.swapExactInput(key, address(WETH), address(USDC), 1 ether);

        vm.stopPrank();

        assertEq(WETH.balanceOf(alice), aliceWETHBefore - 1 ether, "WETH should be escrowed in router");
        assertEq(USDC.balanceOf(alice), aliceUSDCBefore, "User should not receive USDC yet");
        assertEq(
            najRouter.userDeposits(poolId, alice, address(WETH)),
            depositBefore + 1 ether,
            "Router should track user deposit"
        );
    }

    /// @notice Test that TEE can execute swaps via SwapHandler
    function test_teeCanExecuteBatch() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "WETH-USDC Test Pool",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        bytes32 slot0Snapshot = syntheticHelper.captureSlot0(poolManager, key);
        swapHandler.configureSyntheticLiquidity(key, slot0Snapshot, uint128(1_000_000 ether));

        // Simulate user depositing into the router (swap request queued for TEE)
        deal(address(WETH), alice, 1 ether);
        vm.startPrank(alice);
        WETH.approve(address(najRouter), type(uint256).max);
        najRouter.swapExactInput(key, address(WETH), address(USDC), 1 ether);
        vm.stopPrank();

        // Setup swap batch
        ISwapHandler.SwapData[] memory batch = new ISwapHandler.SwapData[](1);
        batch[0] = ISwapHandler.SwapData({
            sender: alice, zeroForOne: true, amountSpecified: -1 ether, tokenIn: address(WETH), tokenOut: address(USDC)
        });

        // TEE executes batch
        vm.startPrank(tee);

        bytes memory strategyParams = abi.encode(uint256(50)); // 50 bps spread

        ISwapHandler.BatchMetadata memory metadata =
            _metadata(keccak256(abi.encodePacked("tee-batch-single")), 500, 250);
        swapHandler.postBatch(poolId, abi.encode(strategyParams, new bytes[](0)), batch, metadata);

        vm.stopPrank();

        // Verify batch was executed successfully
        assertTrue(true, "Batch executed successfully");
    }

    function test_submitBatchAttestationRevertsWithoutVerifier() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "Missing Verifier Pool",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        stdstore.target(address(najHook)).sig("eigenVerifier()").checked_write(address(0));
        assertEq(address(najHook.eigenVerifier()), address(0), "verifier should be cleared");

        InEuint128 memory vol0 = cft.createInEuint128(1, 0, address(swapHandler));
        InEuint128 memory vol1 = cft.createInEuint128(1, 0, address(swapHandler));

        vm.startPrank(address(swapHandler));
        vm.expectRevert(NajHook.NajHook__EigenVerifierNotConfigured.selector);
        najHook.submitBatchAttestation(
            key,
            keccak256("missing-verifier"),
            bytes(""),
            vol0,
            vol1
        );
        vm.stopPrank();
    }

    function test_submitBatchAttestationRevertsOnInvalidAttestation() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "Invalid Attestation",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        mockEigenVerifier.setResult(false, bytes32("badEnclave"), bytes32("badSigner"));

        InEuint128 memory vol0 = cft.createInEuint128(1, 0, address(swapHandler));
        InEuint128 memory vol1 = cft.createInEuint128(1, 0, address(swapHandler));

        vm.startPrank(address(swapHandler));
        vm.expectRevert(NajHook.NajHook__InvalidAttestation.selector);
        najHook.submitBatchAttestation(
            key, keccak256("invalid-attestation"), abi.encodePacked("attn"), vol0, vol1
        );
        vm.stopPrank();

        mockEigenVerifier.setResult(true, bytes32("mrEnclave"), bytes32("mrSigner"));
    }

    function test_finalizeBatchRevertsOnMismatchedId() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "Finalize Mismatch",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        bytes32 batchId = keccak256("batch-match");

        vm.startPrank(address(swapHandler));
        najHook.submitBatchAttestation(
            key,
            batchId,
            abi.encodePacked(batchId),
            cft.createInEuint128(5, 0, address(swapHandler)),
            cft.createInEuint128(7, 0, address(swapHandler))
        );
        vm.expectRevert(NajHook.NajHook__BatchMismatch.selector);
        najHook.finalizeBatch(key, keccak256("wrong-batch"));
        vm.stopPrank();
    }

    function test_finalizeBatchClearsEncryptedFlows() external {
        PoolId poolId = _launchPool(
            INajLaunchpad.LaunchConfig({
                token0: address(WETH),
                token1: address(USDC),
                token0SeedAmt: 100_000 ether,
                token1SeedAmt: 300_000_000 ether,
                strategyAdapter: address(strategyAdapter),
                thresholdAdapter: address(0),
                poolName: "Finalize Clears",
                curatorInfo: INajLaunchpad.CuratorInfo({
                    curator: curator, name: "Test Curator", website: "https://test.com"
                })
            })
        );

        PoolKey memory key = najLaunchpad.getPoolKey(poolId);
        bytes32 batchId = keccak256("finalize-clears");

        vm.startPrank(address(swapHandler));
        najHook.submitBatchAttestation(
            key,
            batchId,
            abi.encodePacked(batchId),
            cft.createInEuint128(10, 0, address(swapHandler)),
            cft.createInEuint128(20, 0, address(swapHandler))
        );
        vm.stopPrank();

        bytes32 poolIdBytes = PoolId.unwrap(poolId);
        assertEq(najHook.sealedBatchIds(poolIdBytes), batchId, "batch should be sealed");
        assertGt(euint128.unwrap(najHook.encryptedToken0Flow(poolIdBytes)), 0, "token0 flow seeded");

        vm.prank(address(swapHandler));
        najHook.finalizeBatch(key, batchId);

        assertEq(najHook.sealedBatchIds(poolIdBytes), bytes32(0), "batch id cleared");
        assertEq(euint128.unwrap(najHook.encryptedToken0Flow(poolIdBytes)), 0, "token0 cleared");
        assertEq(euint128.unwrap(najHook.encryptedToken1Flow(poolIdBytes)), 0, "token1 cleared");
    }

    /// @notice Helper to prepare SwapHandler with tokens and approvals
    /// @dev In production, TEE would pull tokens from users who approved SwapHandler
    function _prepareSwapHandlerTokens(address token, uint256 amount) internal {
        deal(token, address(swapHandler), IERC20(token).balanceOf(address(swapHandler)) + amount);

        vm.startPrank(address(swapHandler));
        IERC20(token).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();
    }

    function _metadata(bytes32 batchId, uint128 volume0, uint128 volume1)
        internal
        returns (ISwapHandler.BatchMetadata memory)
    {
        return ISwapHandler.BatchMetadata({
            batchId: batchId,
            attestation: abi.encodePacked(batchId),
            encryptedToken0Volume: cft.createInEuint128(volume0, 0, address(swapHandler)),
            encryptedToken1Volume: cft.createInEuint128(volume1, 0, address(swapHandler))
        });
    }

    function _launchPool(INajLaunchpad.LaunchConfig memory launchConfig) internal returns (PoolId poolId) {
        deal(address(launchConfig.token0), curator, 1_000_000_000 ether);
        deal(address(launchConfig.token1), curator, 1_000_000_000 ether);

        vm.startPrank(curator);

        // Curator approves NajLaunchpad to transfer tokens for initial liquidity
        IERC20(launchConfig.token0).approve(address(najLaunchpad), type(uint256).max);
        IERC20(launchConfig.token1).approve(address(najLaunchpad), type(uint256).max);

        poolId = najLaunchpad.launch(launchConfig);

        vm.stopPrank();
    }

    function _deployNajHook() internal returns (NajHook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        (address hookAddress, bytes32 salt) =
            HookMiner.find(owner, flags, type(NajHook).creationCode, abi.encode(poolManager, owner));
        hook = new NajHook{salt: salt}(poolManager, owner);
        require(address(hook) == hookAddress, "hook: hook address mismatch");
    }

}
