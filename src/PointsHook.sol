// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC1155 {
    // Happy hour configuration (2-4 PM UTC)
    uint256 public constant HAPPY_HOUR_START = 14; // 2 PM UTC
    uint256 public constant HAPPY_HOUR_END = 16;   // 4 PM UTC
    uint256 public constant BONUS_MULTIPLIER = 150; // 50% bonus (150% = 100% + 50%)
    uint256 public constant BASE_MULTIPLIER = 100;  // Base 100%

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If this is not an ETH-TOKEN pool with this hook attached, ignore
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // We only mint points if user is buying TOKEN with ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        // Calculate base points (20% of ETH spent)
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 basePoints = ethSpendAmount / 5;

        // Apply time-based bonus during happy hour
        uint256 finalPoints = _applyTimeBonus(basePoints);

        // Mint the points
        _assignPoints(key.toId(), hookData, finalPoints);

        return (this.afterSwap.selector, 0);
    }

    function _applyTimeBonus(uint256 basePoints) internal view returns (uint256) {
        // Get current hour in UTC
        uint256 currentHour = (block.timestamp / 3600) % 24;
        
        // Check if we're in happy hour (2-4 PM UTC)
        if (currentHour >= HAPPY_HOUR_START && currentHour < HAPPY_HOUR_END) {
            return (basePoints * BONUS_MULTIPLIER) / 100;
        }
        
        return basePoints;
    }

    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        // If no hookData is passed in, no points will be assigned to anyone
        if (hookData.length == 0) return;

        // Extract user address from hookData
        address user = abi.decode(hookData, (address));

        // If there is hookData but not in the format we're expecting and user address is zero
        // nobody gets any points
        if (user == address(0)) return;

        // Mint points to the user
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user, poolIdUint, points, "");
    }

    // Helper function to check if we're currently in happy hour
    function isHappyHour() public view returns (bool) {
        uint256 currentHour = (block.timestamp / 3600) % 24;
        return currentHour >= HAPPY_HOUR_START && currentHour < HAPPY_HOUR_END;
    }

    // Helper function to get current UTC hour
    function getCurrentHour() public view returns (uint256) {
        return (block.timestamp / 3600) % 24;
    }
}
